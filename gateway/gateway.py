"""OAuth gateway of the claude.ai web connector (spec web-connector, section 3.4).

A FastMCP proxy in front of Basic Memory: GitHub login, one owner checked by numeric GitHub id, an allow list of 18
tools, one audit line per tool call without note content, and a client store whose expired records are culled.
boot.py runs it as uid 1000 after it installed the hash-pinned dependencies; the settings come from the environment
that compose passes on (BM_WEB_*).
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import re
import sys
import time
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

import fastmcp
from cryptography.fernet import Fernet
from fastmcp import FastMCP
from fastmcp.server import create_proxy
from fastmcp.server.auth import AccessToken, AuthContext, AuthProvider
from fastmcp.server.auth.jwt_issuer import derive_jwt_key
from fastmcp.server.auth.providers.github import GitHubProvider
from fastmcp.server.dependencies import get_access_token
from fastmcp.server.middleware import AuthMiddleware, CallNext, Middleware, MiddlewareContext
from fastmcp.server.providers.proxy import ProxyClient
from key_value.aio.protocols import AsyncKeyValue
from key_value.aio.stores.filetree import (
    FileTreeStore,
    FileTreeV1CollectionSanitizationStrategy,
    FileTreeV1KeySanitizationStrategy,
)
from key_value.aio.wrappers.encryption import FernetEncryptionWrapper

# The Basic Memory tools the connector opens: the VM's 21 without delete_note, create_memory_project and
# delete_project. A tool a later Basic Memory adds stays closed until it is added here.
ALLOWED_TOOLS = frozenset(
    {
        "basic_memory_diagnostics",
        "build_context",
        "edit_note",
        "fetch",
        "list_directory",
        "list_memory_projects",
        "list_workspaces",
        "move_note",
        "read_content",
        "read_note",
        "recent_activity",
        "schema_diff",
        "schema_infer",
        "schema_validate",
        "search",
        "search_notes",
        "view_note",
        "write_note",
    }
)
# The only redirect URI a client may register: the claude.ai connector callback.
CLAUDE_CALLBACK = "https://claude.ai/api/mcp/auth_callback"
# How long a GitHub token check is reused instead of calling the GitHub API on every request.
GITHUB_CACHE_TTL_SECONDS = 300
# How often expired store records (authorization transactions and the like) are deleted from disk.
CULL_INTERVAL_SECONDS = 3600
# The tool arguments that name a note or a place; the audit line keeps only these, never content.
AUDIT_ARG_KEYS = (
    "identifier",
    "title",
    "directory",
    "path",
    "url",
    "id",
    "destination_path",
    "destination_folder",
    "dir_name",
    "project",
)
AUDIT_LOGGER_NAME = "gateway.audit"
# Basic Memory on the compose network; the gateway reaches nothing else.
BACKEND_URL = "http://basic-memory:8000/mcp"
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 8080
GATEWAY_NAME = "basic-memory-web"
MIN_JWT_KEY_LENGTH = 32
NUMERIC_ID = re.compile(r"[0-9]+")
# FastMCP's own key derivation and store layout (fastmcp/server/auth/oauth_proxy/proxy.py), so the store is the one
# FastMCP would create by default under FASTMCP_HOME.
JWT_SIGNING_SALT = "fastmcp-jwt-signing-key"
STORAGE_KEY_SALT = "fastmcp-storage-encryption-key"
STORAGE_SUBDIR = "oauth-proxy"
STORAGE_FINGERPRINT_CHARS = 12

AUDIT_LOG = logging.getLogger(AUDIT_LOGGER_NAME)
LOG = logging.getLogger("gateway")


def _is_base_url(value: str) -> bool:
    """An http(s) origin without a path, query or fragment, so BASE_URL/mcp is the resource claude.ai sees."""
    parts = urlsplit(value)
    has_extra = bool(parts.path or parts.query or parts.fragment)
    return parts.scheme in ("http", "https") and bool(parts.netloc) and not has_extra


# Each setting and the check its value must pass.
_SETTING_CHECKS = {
    "BM_WEB_BASE_URL": _is_base_url,
    "BM_WEB_GITHUB_USER_ID": lambda value: NUMERIC_ID.fullmatch(value) is not None,
    "BM_WEB_GITHUB_CLIENT_ID": bool,
    "BM_WEB_GITHUB_CLIENT_SECRET": bool,
    "BM_WEB_JWT_KEY": lambda value: len(value) >= MIN_JWT_KEY_LENGTH,
}


@dataclass(frozen=True)
class Settings:
    base_url: str
    owner_id: str
    client_id: str
    client_secret: str = field(repr=False)
    jwt_key: str = field(repr=False)
    backend_url: str = BACKEND_URL

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> Settings:
        """The settings from env; a SystemExit that names only the missing or malformed variables, never a value."""
        bad = [name for name, check in _SETTING_CHECKS.items() if not check(env.get(name, ""))]
        if bad:
            raise SystemExit(
                f"gateway: missing or malformed {', '.join(bad)}: set it in .env in the main checkout "
                "(base URL without a path, numeric GitHub user id, JWT key of at least "
                f"{MIN_JWT_KEY_LENGTH} characters)"
            )
        return cls(
            base_url=env["BM_WEB_BASE_URL"],
            owner_id=env["BM_WEB_GITHUB_USER_ID"],
            client_id=env["BM_WEB_GITHUB_CLIENT_ID"],
            client_secret=env["BM_WEB_GITHUB_CLIENT_SECRET"],
            jwt_key=env["BM_WEB_JWT_KEY"],
        )


def is_owner(token: AccessToken | None, owner_id: str) -> bool:
    """True only for a token whose "sub" is the numeric GitHub id owner_id (a login can change hands)."""
    if token is None:
        return False
    subject = token.claims.get("sub")
    return isinstance(subject, str) and NUMERIC_ID.fullmatch(subject) is not None and subject == owner_id


def make_storage(data_dir: Path, jwt_key: str) -> tuple[AsyncKeyValue, FileTreeStore]:
    """The encrypted client store FastMCP would create under data_dir, and the file store under it (for cull)."""
    signing_key = derive_jwt_key(low_entropy_material=jwt_key, salt=JWT_SIGNING_SALT)
    storage_key = derive_jwt_key(high_entropy_material=signing_key.decode(), salt=STORAGE_KEY_SALT)
    fingerprint = hashlib.sha256(storage_key).hexdigest()[:STORAGE_FINGERPRINT_CHARS]
    storage_dir = data_dir / STORAGE_SUBDIR / fingerprint
    storage_dir.mkdir(parents=True, exist_ok=True)
    tree = FileTreeStore(
        data_directory=storage_dir,
        key_sanitization_strategy=FileTreeV1KeySanitizationStrategy(storage_dir),
        collection_sanitization_strategy=FileTreeV1CollectionSanitizationStrategy(storage_dir),
    )
    store = FernetEncryptionWrapper(key_value=tree, fernet=Fernet(key=storage_key), raise_on_decryption_error=False)
    return store, tree


async def cull_forever(store: FileTreeStore, interval_seconds: int) -> None:
    """Delete expired store records now and every interval_seconds. FastMCP never does: unauthenticated /authorize
    requests leave transaction files behind."""
    while True:
        try:
            await store.cull()
        except Exception:
            LOG.exception("could not cull the gateway store; trying again in %s s", interval_seconds)
        await asyncio.sleep(interval_seconds)


class AuditMiddleware(Middleware):
    """One JSON line per tool call, refused ones included: time, user (the token's "sub", null without one), tool,
    note identifiers and duration (the owner check plus the backend call)."""

    async def on_call_tool(self, context: MiddlewareContext, call_next: CallNext):
        started = time.monotonic()
        try:
            return await call_next(context)
        finally:
            token = get_access_token()
            arguments = context.message.arguments or {}
            line = {
                "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "user": token.claims.get("sub") if token is not None else None,
                "tool": context.message.name,
                "note": {key: arguments[key] for key in AUDIT_ARG_KEYS if key in arguments},
                "ms": round((time.monotonic() - started) * 1000),
            }
            AUDIT_LOG.info(json.dumps(line, ensure_ascii=False, default=str))


def build_gateway(settings: Settings, auth: AuthProvider) -> FastMCP:
    """The proxy to settings.backend_url: client headers stay out, only the owner sees and calls the allowed tools."""

    def owner_only(context: AuthContext) -> bool:
        return is_owner(context.token, settings.owner_id)

    gateway = create_proxy(
        ProxyClient(settings.backend_url, forward_incoming_headers=False),
        name=GATEWAY_NAME,
        auth=auth,
        # The first middleware is the outermost, so calls the owner check refuses are audited too.
        middleware=[AuditMiddleware(), AuthMiddleware(auth=owner_only)],
    )
    gateway.enable(names=set(ALLOWED_TOOLS), components={"tool"}, only=True)
    return gateway


def github_auth(settings: Settings, client_storage: AsyncKeyValue) -> GitHubProvider:
    """GitHub login with the consent screen on, the claude.ai callback only and a 5-minute token check cache."""
    return GitHubProvider(
        client_id=settings.client_id,
        client_secret=settings.client_secret,
        base_url=settings.base_url,
        jwt_signing_key=settings.jwt_key,
        allowed_client_redirect_uris=[CLAUDE_CALLBACK],
        client_storage=client_storage,
        cache_ttl_seconds=GITHUB_CACHE_TTL_SECONDS,
    )


async def _serve(gateway: FastMCP, tree: FileTreeStore) -> None:
    culler = asyncio.create_task(cull_forever(tree, CULL_INTERVAL_SECONDS))
    try:
        # No uvicorn access log: it prints each path with its query string, and /auth/callback carries the one-time
        # GitHub authorization code there. Tool calls still get their audit line.
        await gateway.run_http_async(
            host=LISTEN_HOST, port=LISTEN_PORT, show_banner=False, uvicorn_config={"access_log": False}
        )
    finally:
        culler.cancel()


def main() -> None:
    settings = Settings.from_env(os.environ)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(message)s"))
    AUDIT_LOG.addHandler(handler)
    AUDIT_LOG.setLevel(logging.INFO)
    AUDIT_LOG.propagate = False
    storage, tree = make_storage(fastmcp.settings.home, settings.jwt_key)
    gateway = build_gateway(settings, auth=github_auth(settings, storage))
    asyncio.run(_serve(gateway, tree))


if __name__ == "__main__":
    main()
