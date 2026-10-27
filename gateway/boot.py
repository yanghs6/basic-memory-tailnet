"""Entry point of the gateway container (compose command), run as root by the stock python image.

1. Installs the hash-pinned dependencies of requirements.txt into the gateway-deps volume, only when the file changed
   since the last install (its sha256 is kept next to them). The new set goes into a fresh directory first and
   replaces /deps/site only when pip succeeded.
2. Gives the data directory (the client store) to uid 1000.
3. Drops to uid 1000 and replaces itself with gateway.py: the process that serves the public path never runs as root.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

APP_DIR = Path("/app")
REQUIREMENTS = APP_DIR / "requirements.txt"
GATEWAY = APP_DIR / "gateway.py"
DEPS_DIR = Path("/deps")
SITE_DIR = DEPS_DIR / "site"
NEW_SITE_DIR = DEPS_DIR / "site.new"
OLD_SITE_DIR = DEPS_DIR / "site.old"
REQUIREMENTS_STAMP = DEPS_DIR / "requirements.sha256"
DATA_DIR = Path("/data")
# The container user of this repo (BM_CONTAINER_UID in scripts/lib/vm.sh).
APP_UID = 1000
APP_GID = 1000


def log(message: str) -> None:
    print(f"boot: {message}", flush=True)


def requirements_digest() -> str:
    return hashlib.sha256(REQUIREMENTS.read_bytes()).hexdigest()


def installed_digest() -> str:
    try:
        return REQUIREMENTS_STAMP.read_text().strip()
    except FileNotFoundError:
        return ""


def install_dependencies(digest: str) -> None:
    """Install requirements.txt with every hash checked into NEW_SITE_DIR, then swap it in for SITE_DIR."""
    for leftover in (NEW_SITE_DIR, OLD_SITE_DIR):
        shutil.rmtree(leftover, ignore_errors=True)
    log("installing the pinned dependencies (requirements.txt changed or nothing installed yet)")
    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--require-hashes",
            "--no-deps",
            "--only-binary=:all:",
            "--no-cache-dir",
            "--disable-pip-version-check",
            "--root-user-action=ignore",
            "--target",
            str(NEW_SITE_DIR),
            "--requirement",
            str(REQUIREMENTS),
        ],
        check=True,
    )
    if SITE_DIR.exists():
        SITE_DIR.rename(OLD_SITE_DIR)
    NEW_SITE_DIR.rename(SITE_DIR)
    shutil.rmtree(OLD_SITE_DIR, ignore_errors=True)
    stamp = REQUIREMENTS_STAMP.with_suffix(".partial")
    stamp.write_text(f"{digest}\n")
    stamp.replace(REQUIREMENTS_STAMP)
    log("dependencies installed")


def own_data_dir() -> None:
    """Give DATA_DIR and everything in it to the app user (a restore or a root run may have left root files)."""
    for root, dirs, files in os.walk(DATA_DIR):
        for name in (root, *(os.path.join(root, entry) for entry in (*dirs, *files))):
            if os.lstat(name).st_uid != APP_UID:
                os.lchown(name, APP_UID, APP_GID)


def main() -> None:
    digest = requirements_digest()
    if digest != installed_digest() or not SITE_DIR.is_dir():
        install_dependencies(digest)
    own_data_dir()
    os.setgroups([])
    os.setgid(APP_GID)
    os.setuid(APP_UID)
    os.execv(sys.executable, [sys.executable, str(GATEWAY)])


if __name__ == "__main__":
    main()
