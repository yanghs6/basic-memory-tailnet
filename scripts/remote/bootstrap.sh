#!/usr/bin/env bash
# Runs ON the VM as root (uploaded by scripts/bootstrap-vm.sh). Safe to run repeatedly.
# stdin: first line is the Tailscale auth key; it may be empty when the VM is already on the tailnet.
set -euo pipefail

readonly TS_HOSTNAME="${TS_HOSTNAME:-agent-hub}"
readonly BM_PORT="${BM_PORT:-8737}"
readonly SB_PORT="${SB_PORT:-3000}"
# Tailscale Serve publishes SilverBullet on this https port of the same tailnet name (443 stays Basic Memory).
readonly SB_HTTPS_PORT=8443
readonly BM_REMOTE_DATA_ROOT="${BM_REMOTE_DATA_ROOT:-/srv/basic-memory}"
readonly BM_REMOTE_APP_DIR="${BM_REMOTE_APP_DIR:-/opt/basic-memory}"
readonly ADMIN_USER="${ADMIN_USER:-ubuntu}"
# tailscale (join the tailnet, Serve) or ssh (reached over an SSH host alias; Tailscale is not installed or touched).
readonly BM_ACCESS="${BM_ACCESS:-tailscale}"
readonly CONTAINER_UID=1000
readonly SWAP_SIZE_MB=1024
readonly SWAP_FILE_MODE=600
# Overridable only for tests.
readonly ETC_DIR="${ETC_DIR:-/etc}"
readonly RUN_DIR="${RUN_DIR:-/run}"
readonly OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
readonly SWAP_FILE="${SWAP_FILE:-/swapfile}"
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

# fstab_has_entry FSTAB -> succeeds when FSTAB already lists $SWAP_FILE as its first field.
fstab_has_entry() {
  [[ -f "$1" ]] && awk -v file="$SWAP_FILE" '$1 == file { found = 1 } END { exit !found }' "$1"
}

# ensure_swap -> a 1 GB swap file unless the VM already has active swap. Every step is safe to repeat: fallocate
# resizes a leftover file, mkswap rewrites it, and the fstab line is added once, after swapon succeeded.
ensure_swap() {
  local active fstab="$ETC_DIR/fstab"
  active="$(swapon --show --noheadings)" || die "could not list swap: is swapon installed?"
  if [[ -n "$active" ]]; then
    log "swap already active; skipping"
    return 0
  fi
  fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" \
    || die "could not create $SWAP_FILE: free some disk space, then rerun 'make vm-bootstrap'"
  chmod "$SWAP_FILE_MODE" "$SWAP_FILE"
  mkswap "$SWAP_FILE" >/dev/null || die "mkswap failed on $SWAP_FILE: rerun 'make vm-bootstrap'"
  swapon "$SWAP_FILE" || die "swapon failed on $SWAP_FILE: rerun 'make vm-bootstrap'"
  if ! fstab_has_entry "$fstab"; then
    printf '%s none swap sw 0 0\n' "$SWAP_FILE" >>"$fstab"
  fi
  log "swap enabled: $SWAP_FILE (${SWAP_SIZE_MB} MB)"
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
# `serve --bg` may print an enable URL and exit 0 without applying any config, so read the result back. The VM has
# no jq, so this checks that both targets appear; verify-vm.sh checks the target of each port.
configure_serve() {
  local bm_target="http://127.0.0.1:${BM_PORT}" sb_target="http://127.0.0.1:${SB_PORT}" serve_status port
  tailscale serve --bg "$bm_target" || die "tailscale serve failed: rerun 'make vm-bootstrap' (it is safe to repeat)"
  tailscale serve --bg --https="$SB_HTTPS_PORT" "$sb_target" \
    || die "tailscale serve for SilverBullet failed: rerun 'make vm-bootstrap' (it is safe to repeat)"
  serve_status="$(tailscale serve status)" || die "could not read tailscale serve status: rerun 'make vm-bootstrap'"
  if grep -qi 'funnel on' <<<"$serve_status"; then
    die "Funnel is on for this node, which makes the unauthenticated endpoint public: turn it off (docs/runbooks/rbk-2026-10-12-operations.md, Exposure audit), then rerun 'make vm-bootstrap'"
  fi
  for port in "$BM_PORT" "$SB_PORT"; do
    grep -qE "proxy http://127\.0\.0\.1:${port}/?\$" <<<"$serve_status" \
      || die "Serve is not active (expected a proxy to http://127.0.0.1:$port, got: $serve_status): enable MagicDNS and HTTPS certificates in the Tailscale admin console (docs/runbooks/rbk-2026-10-12-accounts.md), then rerun 'make vm-bootstrap'"
  done
  log "tailscale serve -> $bm_target (https 443) and $sb_target (https $SB_HTTPS_PORT), tailnet only"
}

main() {
  local auth_key=""
  IFS= read -r auth_key || true
  case "$BM_ACCESS" in
    tailscale | ssh) ;;
    *) die "BM_ACCESS must be tailscale or ssh (got '$BM_ACCESS')" ;;
  esac
  ensure_swap
  install_docker
  ensure_docker_group
  if [[ "$BM_ACCESS" == tailscale ]]; then
    install_tailscale
  fi
  prepare_dirs
  if [[ "$BM_ACCESS" == tailscale ]]; then
    join_tailnet "$auth_key"
    configure_serve
  else
    log "access mode ssh: skipping Tailscale"
  fi
  log "done"
}

main "$@"
