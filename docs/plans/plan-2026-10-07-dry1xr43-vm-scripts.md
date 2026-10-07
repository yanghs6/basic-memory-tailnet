# dry1xr43 VM Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VM 부트스트랩, 배포·검증·상태·로그, 백업·복원 스크립트와 Make 타깃을 만든다. 모두 stub 기반 bats 테스트로 검증하므로, 실제 VM 없이도 완성할 수 있다.

**Architecture:**
- Mac의 스크립트가 SSH로 VM을 다룬다. 첫 부트스트랩만 공인 IP SSH를 쓰고, 이후에는 Tailscale SSH(`remote`)를 쓴다.
- VM에서 실행할 부분은 `scripts/remote/bootstrap.sh`로 분리해 로컬에서 단위 테스트한다.
- 테스트의 `ssh` stub은 원격 명령을 로컬에서 실행하고, 테스트 임시 디렉터리를 VM 경로로 쓴다(`use_vm_env`).

**Tech Stack:** Bash(macOS 3.2 호환), GNU Make, Docker Compose, Basic Memory 0.23.2, Tailscale(Serve, SSH), bats-core 1.14.0 + bats-support/assert, kcov, shellcheck 0.11.0, shfmt 3.12.0, jq, curl

**Spec:** `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md`

**Sequence:** 계획 2/4. 전제: [local-foundation 계획](plan-2026-10-07-sqzn0teq-local-foundation.md) 완료(`make check` PASS, 테스트 39개). 다음 계획: `docs/plans/plan-2026-10-07-hydaxf15-docs-skills.md`

## Global Constraints

- Basic Memory image: `ghcr.io/basicmachines-co/basic-memory:0.23.2@sha256:939f1173d96626c280763e14622f2381d49fbbb7db17cae2e832f4f639405643`. Command `basic-memory mcp --transport streamable-http --host 0.0.0.0 --port 8000 --path /mcp`.
- Host port: `127.0.0.1:${BM_PORT:-8737}`. 컨테이너 포트는 8000이다. `127.0.0.1` 외의 주소에는 절대 바인딩하지 않는다.
- VM 경로:
  - 앱: `/opt/basic-memory` (`BM_REMOTE_APP_DIR`)
  - 데이터: `/srv/basic-memory/{knowledge,config}` (`BM_REMOTE_DATA_ROOT`)
  - 컨테이너 UID/GID: `1000`
- Tailscale:
  - 기기 이름은 `bm-node`, 태그는 `tag:bm-server`다.
  - Funnel은 쓰지 않는다. 노출은 `tailscale serve --bg http://127.0.0.1:8737`로만 한다.
  - 인증 키는 `TS_AUTHKEY` 환경변수나 숨김 프롬프트로만 받는다. 로컬과 원격 어디에서도 명령 인자나 디스크에 남기지 않는다. 원격에서는 `/run` tmpfs의 0600 임시 파일로 `--auth-key=file:`에 넘기고 즉시 삭제한다.
- 도구 이미지(digest 고정):
  - `koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d`
  - `mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d`
  - `bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f`
  - `kcov/kcov:latest@sha256:481289ae32e55e5b733019515acd10948a4f76dfed381765577db909664fc603`
- 스크립트 작성 규칙:
  - `#!/usr/bin/env bash` 다음 줄에 `set -euo pipefail`을 둔다. `scripts/lib/common.sh`는 source만 하므로 예외다.
  - **macOS bash 3.2 호환**: `mapfile`, `readarray`, `declare -A`, `${x,,}`, `inherit_errexit`, 빈 배열 확장을 쓰지 않는다.
  - die할 수 있는 함수를 `x="$(fn)"`로 호출하면 뒤에 `|| exit 1`을 붙인다. bash 3.2는 명령 치환 안에서 errexit를 상속하지 않기 때문이다.
- shfmt 스타일은 `.editorconfig`를 따른다(2칸 들여쓰기, case 들여쓰기, 이항 연산자는 줄 앞). 리디렉션은 공백 없이 `>file`로 쓴다. lint가 포맷 차이를 보고하면 `make fmt`로 고친다.
- shellcheck 예외는 이유와 함께 그 줄 바로 위에만 둔다. trap으로만 호출되는 함수(`cleanup`, `restart_container`)에 SC2317이 나오면 `# shellcheck disable=SC2317  # invoked via trap`을 붙인다. 다른 경고는 코드를 고친다.
- 커버리지: `scripts/` 라인 커버리지 80% 이상. `scripts/` 아래 모든 실행 스크립트는 최소 한 테스트에서 실행돼야 한다.
- 언어:
  - 코드, 주석, 스크립트 메시지, `AGENTS.md`, `SKILL.md`는 영어로 쓴다.
  - README, runbooks, ARCHITECTURE, ADR은 한국어로 쓴다.
  - 저장소 노트에는 `Verified` / `Command` / `Assumption` / `Open question` 표기를 쓴다.
- 커밋:
  - 형식은 `<type>: <description>`(feat, fix, refactor, docs, test, chore).
  - attribution 줄은 넣지 않는다(사용자 전역 설정).
  - 매 커밋 전에 `make check`를 실행한다.
- 수명주기 작업은 Make 타깃으로만 한다. raw `docker compose`나 `ssh`는 실패 진단에만 쓰고, 그 이유를 기록한다.

## Review Focus

1. **잘못된 `BM_TAILNET_DOMAIN`:** `https://`나 끝에 점이 붙은 값을 넣으면 URL이 깨지고, 원인을 알 수 없는 curl 실패만 남는다. 기대 동작은 형식 안내와 함께 즉시 실패하는 것이다. → Task 2에서 `verify-vm.sh` 테스트를 추가한다.
2. **새로 만든 VM에 복원:** 회수된 뒤 새로 만든 VM에는 `/srv/basic-memory`가 없을 수 있다. 이때도 restore가 성공해야 하고 `.prev-*` 디렉터리는 생기지 않아야 한다. → Task 3에서 테스트를 추가한다.
3. **이미 설정된 VM에 부트스트랩 재실행:** 인증 키 없이 성공해야 하고, Docker와 Tailscale을 다시 설치하지 않아야 한다. → Task 1에서 테스트를 추가한다.
4. **백업 중 실패:** 스트림이 끊겨도 컨테이너는 반드시 다시 시작돼야 하고, 반쪽짜리 아카이브가 남으면 안 된다. → Task 3에서 테스트를 추가한다.

## File Structure

```
scripts/remote/bootstrap.sh scripts/bootstrap-vm.sh                     Task 1
tests/stubs/{sudo,tailscale,apt-get,dpkg,id,usermod} tests/fixtures/os-release tests/bootstrap.bats  Task 1
scripts/{deploy,verify-vm,status,logs}.sh                               Task 2
tests/stubs/{ss,free,nc} tests/vm_ops.bats                              Task 2
scripts/{backup,restore}.sh tests/backup_restore.bats                   Task 3
Makefile AGENTS.md                                                      Task 1~3에서 수정
```

---

### Task 1: VM 부트스트랩 (`remote/bootstrap.sh`, `bootstrap-vm.sh`)

**Files:**
- Create: `scripts/remote/bootstrap.sh`, `scripts/bootstrap-vm.sh`
- Create: `tests/stubs/{sudo,tailscale,apt-get,dpkg,id,usermod}`, `tests/fixtures/os-release`
- Modify: `Makefile`(`vm-bootstrap`)
- Test: `tests/bootstrap.bats`

**Interfaces:**
- Consumes: `common.sh`(`BM_REMOTE_APP_DIR`, `BM_REMOTE_DATA_ROOT`, `SSH_CONNECT_TIMEOUT_SECONDS`, `log`, `step`, `die`, `require_cmd`, `mask`), stubs `ssh`, `curl`(다운로드 모드)
- Produces:
  - `scripts/remote/bootstrap.sh`: VM에서 root로 실행한다. stdin 첫 줄이 인증 키이고, 비어 있어도 된다.
    - 환경변수: `BM_PORT`, `BM_REMOTE_DATA_ROOT`, `BM_REMOTE_APP_DIR`, `ADMIN_USER`, `TS_HOSTNAME`
    - 테스트 전용 환경변수: `ETC_DIR`, `RUN_DIR`, `OS_RELEASE`
  - `scripts/bootstrap-vm.sh PUBLIC_IP`: 키는 `TS_AUTHKEY`나 숨김 프롬프트로 받는다.
  - stub 규약:
    - `tailscale`: `status`의 종료 코드는 `TS_STUB_STATUS_EXIT`(기본 0)를 따른다. `up --auth-key=file:P`를 받으면 P의 내용을 `$STUB_LOG.authkey`에 복사한다. `serve status`는 URL 한 줄을 출력한다.
    - `id`: `ID_STUB_GROUPS`(기본 `ubuntu adm sudo`)를 출력한다.
    - `dpkg --print-architecture`는 `arm64`를 출력한다.
    - `sudo`: 앞쪽 `-` 옵션을 버리고 `env "$@"`로 실행한다.

- [ ] **Step 1: stub과 픽스처 작성 (모두 실행 권한 부여)**

`tests/stubs/sudo`:
```bash
#!/usr/bin/env bash
# Test stub for sudo: drops leading options (-n) and runs the rest with env (handles VAR=value cmd).
set -euo pipefail
printf 'sudo %s\n' "$*" >>"$STUB_LOG"
while [[ "${1:-}" == -* ]]; do
  shift
done
exec env "$@"
```

`tests/stubs/tailscale`:
```bash
#!/usr/bin/env bash
# Test stub for tailscale. TS_STUB_STATUS_EXIT sets the `status` exit code (0 = on the tailnet).
# `up --auth-key=file:PATH` copies the key file to $STUB_LOG.authkey so tests can check it.
set -euo pipefail
printf 'tailscale %s\n' "$*" >>"$STUB_LOG"
case "${1:-}" in
  status) exit "${TS_STUB_STATUS_EXIT:-0}" ;;
  up)
    for arg in "$@"; do
      if [[ "$arg" == --auth-key=file:* ]]; then
        cp "${arg#--auth-key=file:}" "$STUB_LOG.authkey"
      fi
    done
    ;;
  serve)
    if [[ "${2:-}" == status ]]; then
      echo "https://bm-node.example.ts.net (tailnet only)"
      echo "|-- / proxy http://127.0.0.1:8737"
    fi
    ;;
esac
```

`tests/stubs/apt-get`:
```bash
#!/usr/bin/env bash
# Test stub for apt-get: logs only.
set -euo pipefail
printf 'apt-get %s\n' "$*" >>"$STUB_LOG"
```

`tests/stubs/dpkg`:
```bash
#!/usr/bin/env bash
# Test stub for dpkg: answers --print-architecture with arm64.
set -euo pipefail
printf 'dpkg %s\n' "$*" >>"$STUB_LOG"
if [[ "${1:-}" == --print-architecture ]]; then
  echo arm64
fi
```

`tests/stubs/id`:
```bash
#!/usr/bin/env bash
# Test stub for id: prints the groups in ID_STUB_GROUPS.
set -euo pipefail
printf 'id %s\n' "$*" >>"$STUB_LOG"
echo "${ID_STUB_GROUPS:-ubuntu adm sudo}"
```

`tests/stubs/usermod`:
```bash
#!/usr/bin/env bash
# Test stub for usermod: logs only.
set -euo pipefail
printf 'usermod %s\n' "$*" >>"$STUB_LOG"
```

`tests/fixtures/os-release`:
```
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION_CODENAME=noble
UBUNTU_CODENAME=noble
```

- [ ] **Step 2: 실패하는 테스트 작성 (`tests/bootstrap.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs apt-get dpkg id usermod tailscale curl sudo ssh
  use_vm_env
  export ETC_DIR="$BATS_TEST_TMPDIR/etc" RUN_DIR="$BATS_TEST_TMPDIR/run"
  export OS_RELEASE="$REPO_DIR/tests/fixtures/os-release" ADMIN_USER=root
  mkdir -p "$RUN_DIR"
  BOOTSTRAP="$REPO_DIR/scripts/remote/bootstrap.sh"
  WRAPPER="$REPO_DIR/scripts/bootstrap-vm.sh"
}

run_bootstrap_with_key() {
  run bash -c 'printf "%s\n" "$1" | "$0"' "$BOOTSTRAP" "$1"
}

@test "installs docker from the official apt repo when docker is missing" {
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key tskey-auth-test123
  assert_success
  run grep -F 'apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin' "$STUB_LOG"
  assert_success
  run cat "$ETC_DIR/apt/sources.list.d/docker.sources"
  assert_line "Suites: noble"
  assert_line "Architectures: arm64"
}

@test "skips the docker install when docker exists" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "docker already installed"
  run grep -F 'docker-ce' "$STUB_LOG"
  assert_failure
}

@test "adds the admin user to the docker group only when missing" {
  setup_stubs docker
  export ID_STUB_GROUPS="root"
  run_bootstrap_with_key ""
  run grep -F 'usermod -aG docker root' "$STUB_LOG"
  assert_success

  : >"$STUB_LOG"
  export ID_STUB_GROUPS="root docker"
  run_bootstrap_with_key ""
  run grep -F 'usermod' "$STUB_LOG"
  assert_failure
}

@test "installs tailscale with the official script when missing" {
  setup_stubs docker
  rm "$STUB_BIN/tailscale"
  export CURL_STUB_SCRIPT="ln -s $REPO_DIR/tests/stubs/tailscale $STUB_BIN/tailscale"
  run_bootstrap_with_key ""
  assert_success
  run grep -F 'curl -fsSL https://tailscale.com/install.sh' "$STUB_LOG"
  assert_success
}

@test "joins the tailnet with the key in a temp file, never in argv" {
  setup_stubs docker
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key tskey-auth-secret987
  assert_success
  run cat "$STUB_LOG.authkey"
  assert_output "tskey-auth-secret987"
  run grep -F 'tskey-auth-secret987' "$STUB_LOG"
  assert_failure
  run grep -E 'tailscale up --auth-key=file:.* --hostname=bm-node --ssh' "$STUB_LOG"
  assert_success
  run ls -A "$RUN_DIR"
  assert_output ""
}

@test "fails with guidance when not on the tailnet and no key is given" {
  setup_stubs docker
  export TS_STUB_STATUS_EXIT=1
  run_bootstrap_with_key ""
  assert_failure
  assert_output --partial "not on the tailnet and no auth key given"
}

@test "only refreshes hostname and Tailscale SSH when already on the tailnet" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  run grep -F 'tailscale set --hostname=bm-node --ssh' "$STUB_LOG"
  assert_success
  run grep -F 'tailscale up' "$STUB_LOG"
  assert_failure
}

@test "creates data dirs owned by the container uid and serves the loopback port" {
  setup_stubs docker
  run_bootstrap_with_key ""
  assert_success
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
  run grep -F 'tailscale serve --bg http://127.0.0.1:8737' "$STUB_LOG"
  assert_success
}

@test "bootstrap-vm uploads the script and passes the key on stdin only" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-wrapper123 TS_STUB_STATUS_EXIT=1
  run "$WRAPPER" 203.0.113.10
  assert_success
  assert_output --partial "using auth key tske****"
  assert_output --partial "only then delete the OCI ingress rule for port 22"
  refute_output --partial "tskey-auth-wrapper123"
  run grep -F 'root@203.0.113.10 cat > /tmp/bm-bootstrap.sh' "$STUB_LOG"
  assert_success
  run grep -F 'tskey-auth-wrapper123' "$STUB_LOG"
  assert_failure
  run cat "$STUB_LOG.authkey"
  assert_output "tskey-auth-wrapper123"
}

@test "bootstrap-vm reads the key from the prompt when TS_AUTHKEY is unset" {
  export BM_VM_USER=root TS_STUB_STATUS_EXIT=1
  run bash -c 'printf "tskey-auth-prompt456\n" | "$0" 203.0.113.10' "$WRAPPER"
  assert_success
  run cat "$STUB_LOG.authkey"
  assert_output "tskey-auth-prompt456"
}

@test "bootstrap-vm requires the public IP" {
  run "$WRAPPER"
  assert_failure
  assert_output --partial "usage: make vm-bootstrap HOST=<public-ip>"
}

@test "bootstrap-vm explains an upload failure" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-x SSH_STUB_FAIL_MATCH="cat > /tmp/bm-bootstrap.sh"
  run "$WRAPPER" 203.0.113.10
  assert_failure
  assert_output --partial "upload failed"
}

@test "bootstrap-vm says a failed run is safe to repeat" {
  export BM_VM_USER=root TS_AUTHKEY=tskey-auth-x SSH_STUB_FAIL_MATCH="bash /tmp/bm-bootstrap.sh"
  run "$WRAPPER" 203.0.113.10
  assert_failure
  assert_output --partial "it is safe to repeat"
}
```

- [ ] **Step 3: 실패 확인**

Run: `make test`
Expected: FAIL. `bootstrap.bats` 13개가 스크립트 없음으로 실패한다.

- [ ] **Step 4: `scripts/remote/bootstrap.sh` 구현 (실행 권한 부여)**

```bash
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

log() { printf '[bootstrap] %s\n' "$*" >&2; }

die() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

write_docker_source() {
  local codename arch
  # shellcheck disable=SC1090
  codename="$(. "$OS_RELEASE" && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  arch="$(dpkg --print-architecture)"
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

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "docker already installed"
    return 0
  fi
  log "installing docker from download.docker.com"
  apt-get update -q
  apt-get install -y -q ca-certificates curl
  install -m 0755 -d "$ETC_DIR/apt/keyrings"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$ETC_DIR/apt/keyrings/docker.asc"
  chmod a+r "$ETC_DIR/apt/keyrings/docker.asc"
  write_docker_source
  apt-get update -q
  # shellcheck disable=SC2086
  apt-get install -y -q $DOCKER_PACKAGES
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
  local auth_key="$1" key_file
  if tailscale status >/dev/null 2>&1; then
    log "already on the tailnet; refreshing hostname and Tailscale SSH"
    tailscale set --hostname="$TS_HOSTNAME" --ssh
    return 0
  fi
  [[ -n "$auth_key" ]] || die "not on the tailnet and no auth key given: rerun 'make vm-bootstrap' and paste a pre-approved tagged key"
  # mktemp creates the file with mode 0600; /run is tmpfs, so the key never reaches disk.
  key_file="$(mktemp "$RUN_DIR/ts-authkey.XXXXXX")"
  printf '%s' "$auth_key" >"$key_file"
  if ! tailscale up --auth-key="file:$key_file" --hostname="$TS_HOSTNAME" --ssh; then
    rm -f "$key_file"
    die "tailscale up failed: check the key is valid, unused and pre-approved"
  fi
  rm -f "$key_file"
  log "joined the tailnet as $TS_HOSTNAME with Tailscale SSH enabled"
}

configure_serve() {
  tailscale serve --bg "http://127.0.0.1:${BM_PORT}"
  log "tailscale serve -> http://127.0.0.1:${BM_PORT} (tailnet only)"
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
```

- [ ] **Step 5: `scripts/bootstrap-vm.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# First-time VM setup over the VM's public IP, before Tailscale SSH exists. Safe to rerun.
# Usage: bootstrap-vm.sh PUBLIC_IP   (Tailscale auth key from $TS_AUTHKEY or a hidden prompt)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly REMOTE_SCRIPT=/tmp/bm-bootstrap.sh
readonly TS_HOSTNAME=bm-node

ssh_public() {
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" "$@"
}

read_auth_key() {
  local key="${TS_AUTHKEY:-}"
  if [[ -z "$key" ]]; then
    read -r -s -p "Tailscale auth key (leave empty if the VM is already on the tailnet): " key || true
    printf '\n' >&2
  fi
  printf '%s' "$key"
}

main() {
  local host="${1:-}" user="${BM_VM_USER:-ubuntu}" key remote_env
  [[ -n "$host" ]] || die "usage: make vm-bootstrap HOST=<public-ip>"
  require_cmd ssh
  key="$(read_auth_key)"
  if [[ -n "$key" ]]; then
    log "using auth key $(mask "$key")"
  fi

  step "upload bootstrap script to $user@$host"
  ssh_public "$user@$host" "cat > $REMOTE_SCRIPT" <"$SCRIPT_DIR/remote/bootstrap.sh" \
    || die "upload failed: check the public IP, your SSH key, and the OCI ingress rule for port 22"

  step "run bootstrap on the VM (docker, tailscale, data dirs, serve)"
  remote_env="BM_PORT=${BM_PORT:-8737} BM_REMOTE_DATA_ROOT=$BM_REMOTE_DATA_ROOT BM_REMOTE_APP_DIR=$BM_REMOTE_APP_DIR"
  remote_env="$remote_env ADMIN_USER=$user TS_HOSTNAME=$TS_HOSTNAME"
  printf '%s\n' "$key" | ssh_public "$user@$host" "sudo $remote_env bash $REMOTE_SCRIPT" \
    || die "bootstrap failed on the VM: rerun 'make vm-bootstrap HOST=$host' (it is safe to repeat)"
  ssh_public "$user@$host" "rm -f $REMOTE_SCRIPT" || log "WARNING: could not remove $REMOTE_SCRIPT on the VM"

  log "Next steps:"
  log "  1. ssh $user@$TS_HOSTNAME true    # must succeed over Tailscale SSH"
  log "  2. only then delete the OCI ingress rule for port 22 (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
  log "  3. make deploy verify status"
}

main "$@"
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 52 tests).

- [ ] **Step 7: Makefile에 `vm-bootstrap` 추가**

`.PHONY`에 `vm-bootstrap`를 추가하고, 파일 끝에 다음을 붙인다.
```make
vm-bootstrap: ## First-time VM setup over public SSH (HOST=<public-ip>; asks for a Tailscale auth key)
	scripts/bootstrap-vm.sh "$(HOST)"
```

- [ ] **Step 8: Commit**

Run: `make check` (PASS)
```bash
git add scripts/remote/bootstrap.sh scripts/bootstrap-vm.sh tests/stubs tests/fixtures/os-release tests/bootstrap.bats Makefile
git commit -m "feat: add idempotent VM bootstrap over SSH with Tailscale join and serve"
```


---

### Task 2: 배포, 검증, 상태, 로그 (`deploy`, `verify-vm`, `status`, `logs`)

**Files:**
- Create: `scripts/deploy.sh`, `scripts/verify-vm.sh`, `scripts/status.sh`, `scripts/logs.sh`
- Create: `tests/stubs/{ss,free,nc}`
- Modify: `Makefile`(`deploy`, `verify`, `status`, `logs`)
- Test: `tests/vm_ops.bats`

**Interfaces:**
- Consumes:
  - `common.sh`: `remote`, `remote_compose`, `require_env`, `HEALTH_TIMEOUT_SECONDS`, `BM_REMOTE_*`
  - `scripts/verify-mcp.sh URL`
  - stubs `ssh`, `docker`, `curl`, `sudo`, `tailscale`
- Produces:
  - `scripts/verify-vm.sh`: Task 3의 `restore` 레시피도 호출한다.
  - stub 규약: `ss`는 `SS_STUB_OUTPUT`(기본: 127.0.0.1:8737 LISTEN 한 줄, 빈 문자열 허용)을 출력한다. `free -m`은 total 3900MB, available `FREE_STUB_AVAILABLE_MB`(기본 3000)를 출력한다. `nc`는 `NC_STUB_EXIT`(기본 1 = 닫힘)로 종료한다.

- [ ] **Step 1: stub 작성 (실행 권한 부여)**

`tests/stubs/ss`:
```bash
#!/usr/bin/env bash
# Test stub for ss: prints SS_STUB_OUTPUT (default: one loopback listener on 8737; may be set to "").
set -euo pipefail
printf 'ss %s\n' "$*" >>"$STUB_LOG"
output="${SS_STUB_OUTPUT-LISTEN 0 4096 127.0.0.1:8737 0.0.0.0:*}"
if [[ -n "$output" ]]; then
  printf '%s\n' "$output"
fi
```

`tests/stubs/free`:
```bash
#!/usr/bin/env bash
# Test stub for free -m: 3900 MB total, FREE_STUB_AVAILABLE_MB available (default 3000 -> 23% used).
set -euo pipefail
printf 'free %s\n' "$*" >>"$STUB_LOG"
printf '               total        used        free      shared  buff/cache   available\n'
printf 'Mem:            3900         700        2200           5        1000        %s\n' "${FREE_STUB_AVAILABLE_MB:-3000}"
printf 'Swap:              0           0           0\n'
```

`tests/stubs/nc`:
```bash
#!/usr/bin/env bash
# Test stub for nc: exits NC_STUB_EXIT (default 1 = connection refused).
set -euo pipefail
printf 'nc %s\n' "$*" >>"$STUB_LOG"
exit "${NC_STUB_EXIT:-1}"
```

- [ ] **Step 2: 실패하는 테스트 작성 (`tests/vm_ops.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker curl sudo tailscale ss free nc
  use_vm_env
  export VERIFY_ID=test1
  cp -R "$REPO_DIR/tests/fixtures/mcp-sse" "$BATS_TEST_TMPDIR/fixtures"
  export CURL_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
}

# --- deploy ---

@test "deploy uploads compose.yaml and a VM .env, then pulls and waits for healthy" {
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  assert_output --partial "deployed. Next: make verify"
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  run grep -F 'docker compose pull -q' "$STUB_LOG"
  assert_success
  run grep -F 'docker compose up -d --wait --wait-timeout 180' "$STUB_LOG"
  assert_success
}

@test "deploy reports an unhealthy container" {
  export DOCKER_STUB_FAIL_MATCH="up -d"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "did not become healthy within 180s"
}

@test "deploy explains an unreachable VM" {
  export SSH_STUB_FAIL_MATCH="compose.yaml"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "is bm-node reachable over Tailscale SSH?"
}

@test "deploy requires the VM settings from .env" {
  unset BM_VM_HOST
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  assert_output --partial "missing env BM_VM_HOST"
}

# --- verify-vm ---

@test "verify runs the MCP round trip over the tailnet URL and checks loopback binding" {
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_output --partial "OK: MCP round trip passed"
  assert_output --partial "port 8737 listens on 127.0.0.1 only"
  run grep -F 'https://bm-node.example.ts.net/mcp' "$STUB_LOG"
  assert_success
}

@test "verify fails when the port is exposed beyond loopback" {
  export SS_STUB_OUTPUT="LISTEN 0 4096 0.0.0.0:8737 0.0.0.0:*"
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "port 8737 is exposed beyond loopback"
}

@test "verify fails when nothing listens on the port" {
  export SS_STUB_OUTPUT=""
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "nothing listens on port 8737"
}

@test "verify rejects a malformed tailnet domain" {
  export BM_TAILNET_DOMAIN="https://tail1234.ts.net."
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "BM_TAILNET_DOMAIN must look like tail1234.ts.net"
}

@test "verify confirms public ports are closed when BM_VM_PUBLIC_IP is set" {
  export BM_VM_PUBLIC_IP=203.0.113.10
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 and 8737"
}

@test "verify fails when the public IP still accepts connections" {
  export BM_VM_PUBLIC_IP=203.0.113.10 NC_STUB_EXIT=0
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "accepts connections on port 22"
}

# --- status ---

@test "status shows containers, memory use and tailscale serve" {
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "basic-memory-server"
  assert_output --partial "memory used: 23%"
  assert_output --partial "proxy http://127.0.0.1:8737"
  refute_output --partial "WARNING"
}

@test "status warns about OCI idle reclamation below 20% memory" {
  export FREE_STUB_AVAILABLE_MB=3500
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "memory used: 10%"
  assert_output --partial "WARNING: memory below 20%"
}

@test "status fails when tailscale serve is not configured" {
  export SSH_STUB_FAIL_MATCH="tailscale serve status"
  run "$REPO_DIR/scripts/status.sh"
  assert_failure
  assert_output --partial "tailscale serve is not configured"
}

@test "status fails when containers cannot be queried" {
  export SSH_STUB_FAIL_MATCH="compose ps"
  run "$REPO_DIR/scripts/status.sh"
  assert_failure
  assert_output --partial "could not query containers on bm-node"
}

# --- logs ---

@test "logs prints the last 200 lines from the VM" {
  run "$REPO_DIR/scripts/logs.sh"
  assert_success
  run grep -F 'docker compose logs --tail=200' "$STUB_LOG"
  assert_success
}

@test "logs explains a failure" {
  export SSH_STUB_FAIL_MATCH="compose logs"
  run "$REPO_DIR/scripts/logs.sh"
  assert_failure
  assert_output --partial "could not read logs from bm-node"
}
```

- [ ] **Step 3: 실패 확인**

Run: `make test`
Expected: FAIL. `vm_ops.bats` 16개가 스크립트 없음으로 실패한다.

- [ ] **Step 4: `scripts/deploy.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Copy compose.yaml and a generated .env to the VM, then pull and start Basic Memory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

vm_env() {
  printf 'BM_PORT=%s\n' "${BM_PORT:-8737}"
  printf 'BM_KNOWLEDGE_DIR=%s/knowledge\n' "$BM_REMOTE_DATA_ROOT"
  printf 'BM_CONFIG_DIR=%s/config\n' "$BM_REMOTE_DATA_ROOT"
}

main() {
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER

  step "upload compose.yaml to $BM_VM_HOST:$BM_REMOTE_APP_DIR"
  remote "cat > $BM_REMOTE_APP_DIR/compose.yaml" <"$REPO_DIR/compose.yaml" \
    || die "upload failed: is $BM_VM_HOST reachable over Tailscale SSH? (ssh $BM_VM_USER@$BM_VM_HOST true)"

  step "write $BM_REMOTE_APP_DIR/.env"
  vm_env | remote "cat > $BM_REMOTE_APP_DIR/.env" || die "could not write $BM_REMOTE_APP_DIR/.env on the VM"

  step "pull image and start (waits up to ${HEALTH_TIMEOUT_SECONDS}s for healthy)"
  remote_compose "pull -q" || die "image pull failed on the VM: check its network, then 'make logs'"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "container did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"

  log "deployed. Next: make verify"
}

main "$@"
```

- [ ] **Step 5: `scripts/verify-vm.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Verify the VM end to end: MCP round trip over the tailnet URL, loopback-only binding on the VM,
# and (when BM_VM_PUBLIC_IP is set) that the public IP refuses SSH and the MCP port.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly PUBLIC_PROBE_TIMEOUT_SECONDS=5

check_loopback_binding() {
  local port="$1" listeners
  step "check port $port is bound to loopback only"
  listeners="$(remote "ss -Hltn 'sport = :$port'")" || die "could not list listeners on $BM_VM_HOST"
  [[ -n "$listeners" ]] || die "nothing listens on port $port on the VM: run 'make deploy'"
  if awk '{ print $4 }' <<<"$listeners" | grep -vqE '^127\.0\.0\.1:'; then
    die "port $port is exposed beyond loopback: $listeners"
  fi
  log "OK: port $port listens on 127.0.0.1 only"
}

check_public_closed() {
  local port="$1" probe
  if [[ -z "${BM_VM_PUBLIC_IP:-}" ]]; then
    log "skip public exposure check (set BM_VM_PUBLIC_IP in .env to enable it)"
    return 0
  fi
  require_cmd nc
  step "check public IP $BM_VM_PUBLIC_IP refuses ports 22 and $port"
  for probe in 22 "$port"; do
    if nc -z -w "$PUBLIC_PROBE_TIMEOUT_SECONDS" "$BM_VM_PUBLIC_IP" "$probe" >/dev/null 2>&1; then
      die "public IP $BM_VM_PUBLIC_IP accepts connections on port $probe: remove that OCI ingress rule"
    fi
  done
  log "OK: public IP $BM_VM_PUBLIC_IP refuses ports 22 and $port"
}

main() {
  local port="${BM_PORT:-8737}"
  require_cmd ssh curl jq
  require_env BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN
  [[ "$BM_TAILNET_DOMAIN" =~ ^[a-z0-9-]+\.ts\.net$ ]] \
    || die "BM_TAILNET_DOMAIN must look like tail1234.ts.net (no https://, no trailing dot): '$BM_TAILNET_DOMAIN'"

  "$SCRIPT_DIR/verify-mcp.sh" "https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}/mcp"
  check_loopback_binding "$port"
  check_public_closed "$port"
}

main "$@"
```

- [ ] **Step 6: `scripts/status.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Show VM container state, memory use against the OCI idle threshold, and tailscale serve config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# OCI may reclaim Always Free A1 VMs when CPU (p95), network and memory all stay below 20% for 7 days.
readonly IDLE_MEMORY_PERCENT=20

memory_used_percent() {
  remote "free -m" | awk '/^Mem:/ { printf "%d\n", ($2 - $7) * 100 / $2 }'
}

main() {
  local used
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER

  step "containers"
  remote_compose "ps" || die "could not query containers on $BM_VM_HOST (try: ssh $BM_VM_USER@$BM_VM_HOST true)"

  step "memory (OCI idle threshold ${IDLE_MEMORY_PERCENT}%)"
  used="$(memory_used_percent)" || die "could not read memory usage on $BM_VM_HOST"
  [[ "$used" =~ ^[0-9]+$ ]] || die "unexpected memory reading from free -m: '$used'"
  log "memory used: ${used}%"
  if ((used < IDLE_MEMORY_PERCENT)); then
    log "WARNING: memory below ${IDLE_MEMORY_PERCENT}%; with idle CPU and network OCI may reclaim this VM (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Idle reclamation)"
  fi

  step "tailscale serve"
  remote "sudo -n tailscale serve status" \
    || die "tailscale serve is not configured: rerun 'make vm-bootstrap HOST=<public-ip>' (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md)"
}

main "$@"
```

- [ ] **Step 7: `scripts/logs.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Print recent Basic Memory container logs from the VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly LOG_TAIL_LINES=200

main() {
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  remote_compose "logs --tail=$LOG_TAIL_LINES" || die "could not read logs from $BM_VM_HOST"
}

main "$@"
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 68 tests).

- [ ] **Step 9: Makefile에 VM 운영 타깃 추가**

`.PHONY`에 `deploy verify status logs`를 추가하고, 파일 끝에 다음을 붙인다.
```make
deploy: ## Copy compose.yaml to the VM and start Basic Memory (waits until healthy)
	scripts/deploy.sh

verify: ## Verify the tailnet MCP endpoint, loopback-only binding and closed public ports
	scripts/verify-vm.sh

status: ## Show VM containers, memory use (idle-reclaim risk) and tailscale serve
	scripts/status.sh

logs: ## Show the last 200 lines of the VM container logs
	scripts/logs.sh
```

- [ ] **Step 10: Commit**

Run: `make check` (PASS)
```bash
git add scripts/deploy.sh scripts/verify-vm.sh scripts/status.sh scripts/logs.sh tests/stubs tests/vm_ops.bats Makefile
git commit -m "feat: add VM deploy, verify, status and logs targets"
```


---

### Task 3: 백업과 복원

**Files:**
- Create: `scripts/backup.sh`, `scripts/restore.sh`
- Modify: `Makefile`(`backup`, `restore`)
- Test: `tests/backup_restore.bats`

**Interfaces:**
- Consumes:
  - `common.sh`: `remote`, `remote_compose`, `sha256_of`, `HEALTH_TIMEOUT_SECONDS`, `BM_CONTAINER_UID`, `BM_REMOTE_DATA_ROOT`
  - `scripts/verify-vm.sh`(Make 레시피에서 restore 다음에 실행)
- Produces:
  - `backups/bm-<YYYYmmddTHHMMSSZ>.tgz`: 최상위 디렉터리가 `basic-memory/`인 tar.gz
  - `<archive>.sha256`: `<hex>  <basename>` 형식
  - `BACKUP_DIR` 환경변수(테스트용, 기본값은 `<repo>/backups`)

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/backup_restore.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker sudo
  use_vm_env
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  BACKUP="$REPO_DIR/scripts/backup.sh"
  RESTORE="$REPO_DIR/scripts/restore.sh"
}

# make_archive NOTE -> creates $ARCHIVE (+ .sha256) holding basic-memory/knowledge/restored.md
make_archive() {
  local src="$BATS_TEST_TMPDIR/src"
  mkdir -p "$src/basic-memory/knowledge" "$src/basic-memory/config"
  echo "$1" >"$src/basic-memory/knowledge/restored.md"
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/bm-20261007T000000Z.tgz"
  tar -C "$src" -czf "$ARCHIVE" basic-memory
  printf '%s  %s\n' "$(sha256sum "$ARCHIVE" | awk '{ print $1 }')" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
}

restore_with_answer() {
  run bash -c 'printf "%s\n" "$1" | "$0" "$2"' "$RESTORE" "$1" "$ARCHIVE"
}

# --- backup ---

@test "backup stores a checksummed archive of the data root and restarts the container" {
  run "$BACKUP"
  assert_success
  local archive
  archive="$(ls "$BACKUP_DIR"/bm-*.tgz)"
  run tar -tzf "$archive"
  assert_line "basic-memory/knowledge/a.md"
  run cat "$archive.sha256"
  assert_output "$(sha256sum "$archive" | awk '{ print $1 }')  $(basename "$archive")"
  run grep -E '^docker compose (stop|start)' "$STUB_LOG"
  assert_line --index 0 "docker compose stop"
  assert_line --index 1 "docker compose start"
}

@test "backup leaves no partial archive and still restarts the container when streaming fails" {
  export SSH_STUB_FAIL_MATCH="tar -C"
  run "$BACKUP"
  assert_failure
  assert_output --partial "backup stream failed"
  run ls -A "$BACKUP_DIR"
  assert_output ""
  run grep -F 'compose start' "$STUB_LOG"
  assert_success
}

@test "backup changes nothing when the container cannot be stopped" {
  export SSH_STUB_FAIL_MATCH="compose stop"
  run "$BACKUP"
  assert_failure
  assert_output --partial "could not stop the container; nothing was changed"
  run grep -F 'compose start' "$STUB_LOG"
  assert_failure
}

# --- restore ---

@test "restore replaces the data, keeps the previous copy and fixes ownership" {
  make_archive "from backup"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "from backup"
  run bash -c 'cat "$0".prev-*/knowledge/a.md' "$BM_REMOTE_DATA_ROOT"
  assert_output "original"
  run stat -c '%u' "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "1000"
  run grep -F 'compose up -d --wait --wait-timeout 180' "$STUB_LOG"
  assert_success
}

@test "restore works on a fresh VM without existing data" {
  make_archive "fresh"
  rm -r "$BM_REMOTE_DATA_ROOT"
  restore_with_answer yes
  assert_success
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "fresh"
  run bash -c 'ls -d "$0".prev-* 2>/dev/null' "$BM_REMOTE_DATA_ROOT"
  assert_failure
}

@test "restore aborts without touching the VM unless the user types yes" {
  make_archive "x"
  restore_with_answer no
  assert_failure
  assert_output --partial "aborted: you must type 'yes'"
  run grep -F 'ssh' "$STUB_LOG"
  assert_failure
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}

@test "restore rejects an archive whose checksum does not match" {
  make_archive "x"
  echo "0000  $(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
  restore_with_answer yes
  assert_failure
  assert_output --partial "checksum mismatch"
  run grep -F 'ssh' "$STUB_LOG"
  assert_failure
}

@test "restore requires an existing archive with its checksum file" {
  run "$RESTORE" "$BACKUP_DIR/missing.tgz"
  assert_failure
  assert_output --partial "backup not found"

  make_archive "x"
  rm "$ARCHIVE.sha256"
  run "$RESTORE" "$ARCHIVE"
  assert_failure
  assert_output --partial "checksum file missing"
}

@test "restore prints usage without an argument" {
  run "$RESTORE"
  assert_failure
  assert_output --partial "usage: make restore BACKUP=backups/bm-<stamp>.tgz"
}

@test "restore points at the kept copy when extraction fails" {
  make_archive "x"
  export SSH_STUB_FAIL_MATCH="-xzf"
  restore_with_answer yes
  assert_failure
  assert_output --partial "extract failed; previous data is at $BM_REMOTE_DATA_ROOT.prev-"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `backup_restore.bats` 10개가 스크립트 없음으로 실패한다.

- [ ] **Step 3: `scripts/backup.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Download a consistent backup of the VM data root into backups/ (the container is stopped briefly
# so SQLite files are not copied mid-write; it is always restarted, even on failure).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly BACKUP_DIR="${BACKUP_DIR:-$REPO_DIR/backups}"
ARCHIVE=""

restart_container() {
  local exit_code=$?
  if [[ -n "$ARCHIVE" && -f "$ARCHIVE.partial" ]]; then
    rm -f "$ARCHIVE.partial"
  fi
  step "restart container"
  if ! remote_compose "start"; then
    log "WARNING: container restart failed; run 'make deploy' to bring it back"
    exit_code=1
  fi
  exit "$exit_code"
}

main() {
  local parent name
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/bm-$(date -u +%Y%m%dT%H%M%SZ).tgz"
  parent="$(dirname "$BM_REMOTE_DATA_ROOT")"
  name="$(basename "$BM_REMOTE_DATA_ROOT")"

  step "stop container (a brief stop keeps SQLite consistent)"
  remote_compose "stop" || die "could not stop the container; nothing was changed"
  trap restart_container EXIT

  step "stream $BM_REMOTE_DATA_ROOT from $BM_VM_HOST"
  remote "sudo -n tar -C $parent -czf - $name" >"$ARCHIVE.partial" \
    || die "backup stream failed; no archive was written"
  mv "$ARCHIVE.partial" "$ARCHIVE"
  printf '%s  %s\n' "$(sha256_of "$ARCHIVE")" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
  log "backup saved: $ARCHIVE"
}

main "$@"
```

- [ ] **Step 4: `scripts/restore.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Restore a backup made by `make backup` onto the VM. Current data is moved aside, never deleted.
# Usage: restore.sh backups/bm-<stamp>.tgz   (asks the user to type yes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

verify_checksum() {
  local archive="$1" expected actual
  expected="$(awk '{ print $1 }' "$archive.sha256")"
  actual="$(sha256_of "$archive")"
  [[ "$expected" == "$actual" ]] \
    || die "checksum mismatch for $archive (expected $expected, got $actual): the file is corrupt or was modified"
}

confirm() {
  local answer=""
  read -r -p "$1" answer || true
  [[ "$answer" == yes ]] || die "aborted: you must type 'yes' to restore"
}

main() {
  local archive="${1:-}" root="$BM_REMOTE_DATA_ROOT" stamp
  [[ -n "$archive" ]] || die "usage: make restore BACKUP=backups/bm-<stamp>.tgz"
  [[ -f "$archive" ]] || die "backup not found: $archive"
  [[ -f "$archive.sha256" ]] || die "checksum file missing: $archive.sha256 (restore only archives made by 'make backup')"
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  verify_checksum "$archive"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  confirm "Replace $root on $BM_VM_HOST with $(basename "$archive")? Current data moves to $root.prev-$stamp. Type 'yes': "

  step "stop container"
  remote_compose "stop" || die "could not stop the container; nothing was changed"

  step "move current data to $root.prev-$stamp"
  remote "if [ -e $root ]; then sudo -n mv $root $root.prev-$stamp; fi" \
    || die "could not move current data aside; nothing was changed"

  step "extract $(basename "$archive")"
  remote "sudo -n tar -C $(dirname "$root") -xzf -" <"$archive" \
    || die "extract failed; previous data is at $root.prev-$stamp"
  remote "sudo -n chown -R $BM_CONTAINER_UID:$BM_CONTAINER_UID $root" || die "could not fix ownership of $root"

  step "start container"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "container did not become healthy: run 'make logs' (previous data is at $root.prev-$stamp)"
  log "restored $(basename "$archive")"
}

main "$@"
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 78 tests).

- [ ] **Step 6: Makefile에 백업과 복원 타깃 추가**

`.PHONY`에 `backup restore`를 추가하고, 파일 끝에 다음을 붙인다.
```make
backup: ## Download a consistent backup of VM data into backups/ (brief container stop)
	scripts/backup.sh

restore: ## Restore BACKUP=backups/bm-<stamp>.tgz to the VM (asks for yes), then verify
	scripts/restore.sh "$(BACKUP)"
	scripts/verify-vm.sh
```

- [ ] **Step 7: `AGENTS.md`에 VM 타깃 추가**

`## Commands`의 `- Local: ...` 줄을 다음으로 바꾼다.
```markdown
- Local: `make local-up local-verify local-down`. VM: `make vm-bootstrap deploy verify status logs backup restore` (each changes or reads the VM; ask the user before the ones that change it).
```

- [ ] **Step 8: Commit**

Run: `make check` (PASS)
```bash
git add scripts/backup.sh scripts/restore.sh tests/backup_restore.bats Makefile AGENTS.md
git commit -m "feat: add VM backup and restore with checksum and confirmation"
```


---

### 마무리: 다음 계획으로 넘기기

- [ ] `make check`가 PASS하는지 확인한다.
- [ ] 이 계획의 Progress log에 결과(테스트 수, 커버리지 %, 특이사항)를 `Verified`로 기록한다.
- [ ] 계획을 옮기고 커밋한다.

```bash
git mv docs/plans/plan-2026-10-07-dry1xr43-vm-scripts.md docs/plans/completed/
git mv docs/plans/plan-2026-10-07-hydaxf15-docs-skills.md docs/plans/active/
git commit -m "docs: complete the vm-scripts plan and activate the docs-skills plan"
```

---

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-07 | Verified | `tailscale up --auth-key=file:<path>` 지원 (tailscale.com/kb/1241) |
