#!/usr/bin/env bash
# Runs ON the VM as root (uploaded by scripts/bootstrap-vm.sh). Safe to run repeatedly.
# stdin: first line is the Tailscale auth key; it may be empty when the VM is already on the tailnet.
set -euo pipefail

readonly TS_HOSTNAME="${TS_HOSTNAME:-bm-node}"
readonly BM_PORT="${BM_PORT:-8737}"
readonly BM_REMOTE_DATA_ROOT="${BM_REMOTE_DATA_ROOT:-/srv/basic-memory}"
readonly BM_REMOTE_APP_DIR="${BM_REMOTE_APP_DIR:-/opt/basic-memory}"
readonly ADMIN_USER="${ADMIN_USER:-ubuntu}"
readonly CONTAINER_UID=1000
# Overridable only for tests.
readonly ETC_DIR="${ETC_DIR:-/etc}"
readonly RUN_DIR="${RUN_DIR:-/run}"
readonly OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
readonly DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
# Assumption: unattended-upgrades often holds the dpkg lock right after first boot; wait instead of failing.
readonly APT_LOCK_TIMEOUT_SECONDS=300

# Never prompt during package installs (there is no tty over ssh).
export DEBIAN_FRONTEND=noninteractive

# Global so the EXIT trap can still see it; the key file must never outlive this script.
key_file=""

log() { printf '[bootstrap] %s\n' "$*" >&2; }

die() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

write_docker_source() {
  local codename arch
  # shellcheck disable=SC1090
  codename="$(. "$OS_RELEASE" && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" || exit 1
  arch="$(dpkg --print-architecture)" || exit 1
  mkdir -p "$ETC_DIR/apt/sources.list.d"
  cat >"$ETC_DIR/apt/sources.list.d/docker.sources" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

apt_get() {
  apt-get -o "DPkg::Lock::Timeout=$APT_LOCK_TIMEOUT_SECONDS" "$@"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "docker already installed"
    return 0
  fi
  log "installing docker from download.docker.com"
  apt_get update -q
  apt_get install -y -q ca-certificates curl
  install -m 0755 -d "$ETC_DIR/apt/keyrings"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$ETC_DIR/apt/keyrings/docker.asc"
  chmod a+r "$ETC_DIR/apt/keyrings/docker.asc"
  write_docker_source
  apt_get update -q
  # shellcheck disable=SC2086
  apt_get install -y -q $DOCKER_PACKAGES
}

ensure_docker_group() {
  if id -nG "$ADMIN_USER" | tr ' ' '\n' | grep -qx docker; then
    log "$ADMIN_USER already in the docker group"
    return 0
  fi
  usermod -aG docker "$ADMIN_USER"
  log "added $ADMIN_USER to the docker group (applies to new SSH sessions)"
}

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    log "tailscale already installed"
    return 0
  fi
  log "installing tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
}

prepare_dirs() {
  mkdir -p "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config" "$BM_REMOTE_APP_DIR"
  chown -R "$CONTAINER_UID:$CONTAINER_UID" "$BM_REMOTE_DATA_ROOT"
  chown "$ADMIN_USER:$ADMIN_USER" "$BM_REMOTE_APP_DIR"
  log "data dirs ready under $BM_REMOTE_DATA_ROOT"
}

join_tailnet() {
  local auth_key="$1"
  if tailscale status >/dev/null 2>&1; then
    log "already on the tailnet; refreshing hostname and Tailscale SSH"
    tailscale set --hostname="$TS_HOSTNAME" --ssh
    return 0
  fi
  [[ -n "$auth_key" ]] || die "not on the tailnet and no auth key given: rerun 'make vm-bootstrap' and paste a pre-approved tagged key"
  # mktemp creates the file with mode 0600; /run is tmpfs, so the key never reaches disk.
  key_file="$(mktemp "$RUN_DIR/ts-authkey.XXXXXX")" || exit 1
  trap 'rm -f "$key_file"' EXIT
  printf '%s' "$auth_key" >"$key_file"
  tailscale up --auth-key="file:$key_file" --hostname="$TS_HOSTNAME" --ssh \
    || die "tailscale up failed: check the key is valid, unused and pre-approved"
  rm -f "$key_file"
  log "joined the tailnet as $TS_HOSTNAME with Tailscale SSH enabled"
}

# Verified (tailscale cli/serve_legacy.go, read in the final review): when HTTPS is not enabled on the tailnet,
# `serve --bg` may print an enable URL and exit 0 without applying any config, so read the result back.
configure_serve() {
  local target="http://127.0.0.1:${BM_PORT}" serve_status
  tailscale serve --bg "$target" || die "tailscale serve failed: rerun 'make vm-bootstrap' (it is safe to repeat)"
  serve_status="$(tailscale serve status)" || die "could not read tailscale serve status: rerun 'make vm-bootstrap'"
  if grep -qi 'funnel on' <<<"$serve_status"; then
    die "Funnel is on for this node, which makes the unauthenticated endpoint public: turn it off (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Exposure audit), then rerun 'make vm-bootstrap'"
  fi
  grep -qE "proxy http://127\.0\.0\.1:${BM_PORT}/?\$" <<<"$serve_status" \
    || die "Serve is not active (expected a proxy to $target, got: $serve_status): enable MagicDNS and HTTPS certificates in the Tailscale admin console (docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md), then rerun 'make vm-bootstrap'"
  log "tailscale serve -> $target (tailnet only)"
}

main() {
  local auth_key=""
  IFS= read -r auth_key || true
  install_docker
  ensure_docker_group
  install_tailscale
  prepare_dirs
  join_tailnet "$auth_key"
  configure_serve
  log "done"
}

main "$@"
