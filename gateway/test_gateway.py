"""Behavior tests of the web gateway (gateway.py).

They run inside the gateway container, where the hash-pinned dependencies are installed:
make local-verify with BM_WEB=on runs `python -m unittest -v test_gateway` there. Every server listens on a free
127.0.0.1 port in a background thread of this process; nothing reaches GitHub or Basic Memory.
"""

from __future__ import annotations

import asyncio
import dataclasses
import json
import socket
import tempfile
import threading
import time
import unittest
import urllib.request
from pathlib import Path
from typing import Any

import uvicorn
from fastmcp import Client, FastMCP
from fastmcp.client.transports import StreamableHttpTransport
from fastmcp.exceptions import ToolError
from fastmcp.server.auth.providers.jwt import StaticTokenVerifier
from mcp import MCPError

import gateway

# The 21 tools of the Basic Memory tools/list on the VM (spec web-connector section 2).
BACKEND_TOOLS = (
    "basic_memory_diagnostics",
    "build_context",
    "create_memory_project",
    "delete_note",
    "delete_project",
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
)
# A tool a later Basic Memory release could add: the gateway must not open it.
NEW_TOOL = "new_tool"
BLOCKED_TOOLS = ("delete_note", "create_memory_project", "delete_project")
ALLOWED_TOOL_COUNT = 18
OWNER_ID = "4242"
TOKENS = {
    "owner": {"client_id": "test-client", "scopes": [], "sub": OWNER_ID},
    "other": {"client_id": "test-client", "scopes": [], "sub": "5151"},
    "no-sub": {"client_id": "test-client", "scopes": []},
    # The owner's GitHub login instead of the numeric id: a renamed login can be claimed by anyone.
    "login-sub": {"client_id": "test-client", "scopes": [], "sub": "octocat", "login": "octocat"},
}
# A client header that must not reach Basic Memory.
PROBE_HEADER = "x-forward-probe"
# claude.ai gives the discovery endpoints 10 seconds.
DISCOVERY_LIMIT_SECONDS = 10
SERVER_START_TIMEOUT_SECONDS = 20
FAKE_ENV = {
    "BM_WEB_BASE_URL": "http://127.0.0.1:8738",
    "BM_WEB_GITHUB_USER_ID": OWNER_ID,
    "BM_WEB_GITHUB_CLIENT_ID": "fake-client-id",
    "BM_WEB_GITHUB_CLIENT_SECRET": "FAKE-SECRET-c1d2e3",
    "BM_WEB_JWT_KEY": "FAKE-JWT-KEY-" + "0123456789abcdef" * 3,
}


class ServerThread:
    """Serves an ASGI app with uvicorn on a free 127.0.0.1 port in a daemon thread."""

    def __init__(self) -> None:
        self._socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._socket.bind(("127.0.0.1", 0))
        self.port: int = self._socket.getsockname()[1]
        self.base_url = f"http://127.0.0.1:{self.port}"
        self._server: uvicorn.Server | None = None
        self._thread: threading.Thread | None = None

    def start(self, app: Any) -> None:
        self._server = uvicorn.Server(uvicorn.Config(app, log_level="warning", lifespan="on"))
        self._thread = threading.Thread(target=self._server.run, kwargs={"sockets": [self._socket]}, daemon=True)
        self._thread.start()
        deadline = time.monotonic() + SERVER_START_TIMEOUT_SECONDS
        while not self._server.started:
            if time.monotonic() > deadline or not self._thread.is_alive():
                raise RuntimeError(f"test server on port {self.port} did not start")
            time.sleep(0.05)

    def stop(self) -> None:
        if self._server is not None and self._thread is not None:
            self._server.should_exit = True
            self._thread.join(SERVER_START_TIMEOUT_SECONDS)
        self._socket.close()


class FakeBackend:
    """A Basic Memory stand-in that records the request headers it receives and the tools it runs."""

    def __init__(self) -> None:
        self.headers: list[dict[str, str]] = []
        self.calls: list[str] = []
        self._server = FastMCP("fake-basic-memory")
        for name in (*BACKEND_TOOLS, NEW_TOOL):
            self._server.tool(self._tool(name), name=name)
        # Stateless: the gateway opens a backend session per request, and a stateful fake logged ClosedResourceError
        # tracebacks when such a session closed while a request of it was still being handled.
        self._app = self._server.http_app(stateless_http=True)

    def _tool(self, name: str):
        def tool(identifier: str = "", title: str = "", directory: str = "", content: str = "") -> str:
            self.calls.append(name)
            return f"{name} ok"

        return tool

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] == "http":
            self.headers.append({key.decode().lower(): value.decode() for key, value in scope["headers"]})
        await self._app(scope, receive, send)


def closed_port() -> int:
    """A 127.0.0.1 port nothing listens on."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


async def is_refused(client: Client, name: str, arguments: dict[str, Any] | None = None) -> bool:
    """True when the gateway refuses the call with a tool or protocol error."""
    try:
        result = await client.call_tool(name, arguments or {}, raise_on_error=False)
    except (ToolError, MCPError):
        return True
    return result.is_error


class GatewayToolsTest(unittest.IsolatedAsyncioTestCase):
    """The gateway in front of the fake backend, with static test tokens instead of GitHub."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.backend = FakeBackend()
        cls.backend_server = ServerThread()
        cls.backend_server.start(cls.backend)
        cls.gateway_server = ServerThread()
        settings = dataclasses.replace(
            gateway.Settings.from_env({**FAKE_ENV, "BM_WEB_BASE_URL": cls.gateway_server.base_url}),
            backend_url=f"{cls.backend_server.base_url}/mcp",
        )
        proxy = gateway.build_gateway(settings, auth=StaticTokenVerifier(tokens=TOKENS))
        cls.gateway_server.start(proxy.http_app())

    @classmethod
    def tearDownClass(cls) -> None:
        cls.gateway_server.stop()
        cls.backend_server.stop()

    def setUp(self) -> None:
        self.backend.headers.clear()
        self.backend.calls.clear()

    def client(self, token: str) -> Client:
        transport = StreamableHttpTransport(
            f"{self.gateway_server.base_url}/mcp", headers={PROBE_HEADER: "client-value"}, auth=token
        )
        return Client(transport)

    async def tool_names(self, token: str) -> set[str]:
        async with self.client(token) as client:
            return {tool.name for tool in await client.list_tools()}

    async def test_owner_lists_exactly_the_allowed_tools(self) -> None:
        names = await self.tool_names("owner")
        self.assertEqual(names, gateway.ALLOWED_TOOLS)
        self.assertEqual(len(names), ALLOWED_TOOL_COUNT)

    async def test_blocked_and_unknown_tools_are_hidden_and_refused_for_the_owner(self) -> None:
        names = await self.tool_names("owner")
        async with self.client("owner") as client:
            for name in (*BLOCKED_TOOLS, NEW_TOOL):
                with self.subTest(tool=name):
                    self.assertNotIn(name, names)
                    self.assertTrue(await is_refused(client, name, {"identifier": "x"}))
        self.assertEqual(self.backend.calls, [])

    async def test_other_user_sees_no_tools_and_cannot_call(self) -> None:
        self.assertEqual(await self.tool_names("other"), set())
        async with self.client("other") as client:
            self.assertTrue(await is_refused(client, "read_note", {"identifier": "x"}))
        self.assertEqual(self.backend.calls, [])

    async def test_token_without_numeric_owner_sub_is_rejected(self) -> None:
        for token in ("no-sub", "login-sub"):
            with self.subTest(token=token):
                self.assertEqual(await self.tool_names(token), set())
                async with self.client(token) as client:
                    self.assertTrue(await is_refused(client, "read_note", {"identifier": "x"}))
        self.assertEqual(self.backend.calls, [])
        # The gateway is still up for the owner after the refusals.
        self.assertEqual(len(await self.tool_names("owner")), ALLOWED_TOOL_COUNT)

    async def test_backend_never_receives_authorization(self) -> None:
        async with self.client("owner") as client:
            await client.call_tool("read_note", {"identifier": "x"})
        self.assertEqual(self.backend.calls, ["read_note"])
        self.assertTrue(self.backend.headers, "the backend received no request")
        for headers in self.backend.headers:
            self.assertNotIn("authorization", headers)
            self.assertNotIn(PROBE_HEADER, headers)

    async def test_audit_line_names_tool_and_note_without_content(self) -> None:
        with self.assertLogs(gateway.AUDIT_LOGGER_NAME, "INFO") as captured:
            async with self.client("owner") as client:
                await client.call_tool("write_note", {"title": "T", "directory": "d", "content": "BODY-7f3a"})
        lines = [json.loads(record.getMessage()) for record in captured.records]
        self.assertEqual(len(lines), 1)
        line = lines[0]
        self.assertEqual(line["tool"], "write_note")
        self.assertEqual(line["user"], OWNER_ID)
        self.assertEqual(line["note"], {"title": "T", "directory": "d"})
        self.assertIsInstance(line["ms"], int)
        self.assertIn("time", line)
        self.assertNotIn("BODY-7f3a", "\n".join(captured.output))

    async def test_refused_calls_are_audited_with_the_caller_and_without_content(self) -> None:
        for token, user in (("other", "5151"), ("no-sub", None)):
            with self.subTest(token=token):
                with self.assertLogs(gateway.AUDIT_LOGGER_NAME, "INFO") as captured:
                    async with self.client(token) as client:
                        arguments = {"title": "T", "directory": "d", "content": "BODY-9c4e"}
                        self.assertTrue(await is_refused(client, "write_note", arguments))
                lines = [json.loads(record.getMessage()) for record in captured.records]
                self.assertEqual(len(lines), 1)
                self.assertEqual(lines[0]["user"], user)
                self.assertEqual(lines[0]["tool"], "write_note")
                self.assertEqual(lines[0]["note"], {"title": "T", "directory": "d"})
                self.assertNotIn("BODY-9c4e", "\n".join(captured.output))
        self.assertEqual(self.backend.calls, [])


class RunRecorder:
    """Stands in for the FastMCP server in gateway._serve: records the run_http_async arguments and returns."""

    def __init__(self) -> None:
        self.kwargs: dict[str, Any] = {}

    async def run_http_async(self, **kwargs: Any) -> None:
        self.kwargs = kwargs


class IdleTree:
    """Stands in for the client store in gateway._serve: cull deletes nothing."""

    async def cull(self) -> None:
        return None


class ServeTest(unittest.IsolatedAsyncioTestCase):
    async def test_serve_turns_the_uvicorn_access_log_off(self) -> None:
        # The access log prints each request path with its query string, so /auth/callback?code=... would put the
        # one-time GitHub authorization code into the container log.
        recorder = RunRecorder()
        await gateway._serve(recorder, IdleTree())
        self.assertIs(recorder.kwargs.get("uvicorn_config", {}).get("access_log"), False)


class GatewayMetadataTest(unittest.IsolatedAsyncioTestCase):
    async def test_metadata_answers_while_backend_is_down(self) -> None:
        server = ServerThread()
        settings = dataclasses.replace(
            gateway.Settings.from_env({**FAKE_ENV, "BM_WEB_BASE_URL": server.base_url}),
            backend_url=f"http://127.0.0.1:{closed_port()}/mcp",
        )
        with tempfile.TemporaryDirectory() as data_dir:
            storage, _ = gateway.make_storage(Path(data_dir), settings.jwt_key)
            server.start(gateway.build_gateway(settings, auth=gateway.github_auth(settings, storage)).http_app())
            try:
                started = time.monotonic()
                status = await asyncio.to_thread(self.metadata_status, server.base_url)
                elapsed = time.monotonic() - started
            finally:
                server.stop()
        self.assertEqual(status, 200)
        self.assertLess(elapsed, DISCOVERY_LIMIT_SECONDS)

    @staticmethod
    def metadata_status(base_url: str) -> int:
        url = f"{base_url}/.well-known/oauth-authorization-server"
        with urllib.request.urlopen(url, timeout=DISCOVERY_LIMIT_SECONDS) as response:
            return response.status


class SettingsTest(unittest.TestCase):
    def test_settings_name_the_missing_or_malformed_variable_only(self) -> None:
        for name, value in (("BM_WEB_GITHUB_USER_ID", "octo"), ("BM_WEB_JWT_KEY", "")):
            with self.subTest(variable=name):
                with self.assertRaises(SystemExit) as caught:
                    gateway.Settings.from_env({**FAKE_ENV, name: value})
                message = str(caught.exception)
                self.assertIn(name, message)
                for secret in (FAKE_ENV["BM_WEB_GITHUB_CLIENT_SECRET"], FAKE_ENV["BM_WEB_JWT_KEY"], "octo"):
                    self.assertNotIn(secret, message)


class StorageTest(unittest.IsolatedAsyncioTestCase):
    async def test_cull_removes_expired_records(self) -> None:
        with tempfile.TemporaryDirectory() as data_dir:
            store, tree = gateway.make_storage(Path(data_dir), FAKE_ENV["BM_WEB_JWT_KEY"])
            await store.put(key="expiring", value={"n": 1}, collection="test-records", ttl=1)
            await store.put(key="kept", value={"n": 2}, collection="test-records")
            before = len(list(Path(data_dir).rglob("*.json")))
            await asyncio.sleep(1.5)
            await tree.cull()
            after = len(list(Path(data_dir).rglob("*.json")))
            self.assertEqual(after, before - 1)
            self.assertEqual(await store.get(key="kept", collection="test-records"), {"n": 2})


if __name__ == "__main__":
    unittest.main()
