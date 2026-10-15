# 11 Web UI VM Rollout Implementation Plan

> **For agentic workers:** Tasks 1-3 change code and docs only: use superpowers:subagent-driven-development or superpowers:executing-plans. Task 4 changes the VM: run it in the main session with the user (superpowers:executing-plans), never in a subagent, and get the user's OK before each VM-changing step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make verify`·`make probe`가 SilverBullet과 Serve 8443을 검사하게 하고, 부트스트랩이 Serve 8443을 설정하게 한 뒤, 사용자와 함께 실제 VM(`agent-hub-01`)에 배포해 스펙 §1 완료 조건 2·3·4·6을 증거와 함께 충족한다.

**Architecture:**
- `scripts/verify-vm.sh`가 계획 10의 `verify-sb.sh`를 `https://agent-hub.<tailnet>.ts.net:8443`으로 부른다(`probe`는 `--read-only`).
- 3000번 포트의 루프백 바인딩을 검사하고, 공인 IP 점검 포트에 8443과 3000을 더한다.
- Serve 검사는 `tailscale serve status --json`을 Mac에서 jq로 읽어 포트별 대상과 포트별 Funnel을 본다.
- `scripts/remote/bootstrap.sh`는 `tailscale serve --bg --https=8443`을 더하고 두 대상이 보이는지 확인한다. VM에는 jq가 없다.
- 기존 VM에는 `make vm-bootstrap HOST=agent-hub`를 다시 실행해 적용한다(스펙 §3, 계획 05 Step 14에서 키 없이 재실행됨을 확인함).

**Tech Stack:** bash 3.2 호환 셸, bats-core + bats-assert, jq(Mac), Tailscale Serve(`serve status --json`, `--https=8443`), GCP e2-micro(Ubuntu 26.04 Minimal amd64), 계획 10의 스크립트

**Spec:** `docs/specs/2026-10-14-silverbullet-web-ui-design.md` (특히 §1, §3, §7.6, §7.7, §9)

**Sequence:** 계획 11. 다음 전제를 모두 만족한 뒤 시작한다.
- 계획 10이 `main`에 병합됐다.
- 계획 05(PR #2)가 `main`에 병합됐다. 운영 런북과 ADR 0002를 같이 고친다.
- main 체크아웃 `.env`에 `SB_USER`가 있다(계획 10 전제 1).

## Global Constraints

- VM을 바꾸는 명령은 단계마다 사용자 OK를 받은 뒤 실행한다: `make vm-bootstrap`, `make deploy`, `make restore`, `make sb-fonts`, `sudo` 쓰기. `make probe status logs verify backup`은 OK가 필요 없다(AGENTS.md).
- 읽기 전용 진단에 raw `ssh`·`docker`를 쓸 때는 이유를 Progress log에 적는다(AGENTS.md Commands).
- `gcloud`는 `--configuration=bm-personal`로만 실행한다. VM을 정지하지 않는다(외부 IP가 바뀜).
- VM의 외부·tailnet IP, tailnet 이름, 프로젝트 id를 커밋·PR·코멘트·문서 어디에도 쓰지 않는다. `<공인 IP>`, `<tailnet>`, `<프로젝트>`로 가린다.
- `SB_USER`와 세션 쿠키는 출력하지 않는다. 브라우저 로그인은 사용자가 직접 한다. 에이전트는 `.env`를 읽지 않는다.
- Serve 매핑: 443 → `http://127.0.0.1:${BM_PORT}`(8737), 8443 → `http://127.0.0.1:${SB_PORT}`(3000), 두 포트 모두 Funnel off. GCP 방화벽은 바꾸지 않는다.
- AGENTS.md 스크립트 규칙(머리, `common.sh`, `die`, bash 3.2, 상수), 테스트 먼저(RED → GREEN), ADR 0004. 기존 assertion을 약하게 바꾸지 않는다. 동작이 바뀐 기대값(점검 포트 목록, nc 호출 수)만 고친다.
- 테스트는 `make test`/`make check`로만 돌린다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 11`, `Task: <N|review|none>`. `Co-authored-by`, `Signed-off-by`, `Claude-Session`, 세션 링크, `Generated with`는 넣지 않는다.
- PR 흐름: 머신 계정으로 push하고 초안 PR 하나를 연다. 제목은 `feat: serve the SilverBullet web UI on the tailnet and verify it`, 본문 마지막 문단은 `Assisted-by`와 `Plan: 11`이다.
- 결과는 이 계획의 Progress log와 ADR 0005에 `Verified` / `Command` / `Assumption` / `Open question`으로 기록한다.

## Review Focus

1. **Serve가 8443을 엉뚱한 곳으로 보내거나 아예 없음.** 예: 443과 8443이 뒤바뀜, `serve reset` 뒤 8443만 빠짐. 지금 검사는 `tailnet only` 문구만 본다. → Task 1 Serve 실패 반복문.
2. **Funnel이 8443에만 켜짐.** 로그인 화면이 인터넷에 열린다. → Task 1 반복문의 `TS_STUB_FUNNEL_PORT=8443` 사례.
3. **`make probe`가 로그인하거나 `SB_USER`를 요구함.** probe는 노트도 세션도 만들지 않는 진단 도구여야 한다. → Task 1 probe 테스트가 `SB_USER` 없이 통과하고 `/.auth` 호출이 없는지 본다.
4. **공인 IP 점검에서 8443·3000이 빠짐.** → Task 1 성공 테스트가 nc 6회와 포트 목록을 확인한다.
5. **부트스트랩을 다시 실행하면 443 매핑이 사라지거나, 8443 적용이 조용히 실패함.** 예: HTTPS가 꺼져 enable URL만 출력하고 exit 0으로 끝남. → Task 2 테스트가 두 `serve` 명령과 8443 누락 시 실패를 확인한다. 실제 VM에서는 Task 4 Step 3이 JSON으로 두 매핑을 확인한다.

## 실제 VM에서만 확인할 수 있는 항목

해당 Step에서 결과를 Progress log에 `Verified`(명령 포함)로 적는다. 확인하지 못하면 `Assumption`으로 남긴다.

1. `tailscale serve status --json`의 실제 모양이 스텁과 같다: `Web`의 키는 `<호스트>:<포트>`, 값은 `Handlers["/"].Proxy`이고, `AllowFunnel`이 없거나 모두 false다. (Step 3)
2. `tailscale serve --bg --https=8443 http://127.0.0.1:3000`이 443 매핑을 지우지 않는다. (Step 3)
3. Serve를 거친 로그인 쿠키에 `Secure`가 붙는다(`X-Forwarded-Proto`). `make verify`의 `OK: SilverBullet checks passed for https://…:8443`이 증거다. (Step 5)
4. `sudo -n -u '#1000'`로 노트 폴더에 쓸 수 있다(배포의 `sb-space.sh`). (Step 4)
5. 첫 배포에서 Basic Memory를 다시 만드는 시간(콜드 스타트)이 360초 안이고, SilverBullet이 healthy가 된다. (Step 4)
6. SilverBullet 컨테이너는 호스트의 `127.0.0.1:8737`과 Basic Memory 컨테이너에 닿지 못한다. (Step 6)
7. amd64에서 두 컨테이너를 함께 띄운 뒤의 메모리·스왑 사용량과 OOM 여부. (Step 7)

---

### 시작: 브랜치, worktree, 초안 PR (에이전트)

- [ ] 전제 세 가지를 확인한다.
  - `gh pr view <계획 10 PR 번호> --json state`와 `gh pr view 2 --json state`가 모두 `MERGED`다.
  - `SB_USER`는 계획 10 전제 1의 `sb-user-check`로 확인한다.
- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/11-web-ui-vm-rollout` 브랜치를 만든다(git-workflow 스킬의 Start).
- [ ] 첫 커밋으로 이 계획 파일을 `active/`로 옮기고 push한 뒤 초안 PR을 연다.

```bash
git mv docs/plans/backlog/2026-10-14-11-web-ui-vm-rollout.md docs/plans/active/2026-10-14-11-web-ui-vm-rollout.md
git commit -m "docs: start plan 11 web UI VM rollout" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 11" --trailer "Task: none"
git push -u origin plan/11-web-ui-vm-rollout
gh pr create --draft --base main --title "feat: serve the SilverBullet web UI on the tailnet and verify it" --body-file "$TMPDIR/pr-11.md"
```

---

### Task 1: `verify`·`probe`의 SilverBullet·Serve 검사

**Files:**
- Modify: `scripts/verify-vm.sh`(전체), `tests/stubs/tailscale`(JSON 모드, 8443), `Makefile`(`verify`·`probe` 설명)
- Test: `tests/vm_ops.bats`(setup, verify·probe 테스트)

**Interfaces:**
- Consumes: 계획 10의 `scripts/verify-sb.sh [--read-only] URL`, curl 스텁의 `CURL_SB_COOKIE`, `use_vm_env`의 `SB_USER`·`SB_PORT`
- Produces:
  - `verify-vm.sh`의 상수 `SB_HTTPS_PORT=8443`, `PUBLIC_PROBE_PORTS="22 80 443 8443"`
  - 함수 `serve_proxy CONFIG_JSON PORT`: https PORT의 `/` 프록시 대상을 출력한다(끝 `/` 제거, 없으면 빈 값).
  - tailscale 스텁의 `serve status --json`과 환경변수 `TS_STUB_SERVE_8443`(8443 대상, 빈 값이면 매핑 없음), `TS_STUB_FUNNEL_PORT`(Funnel이 켜진 포트, 기본 443)

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/vm_ops.bats`)**

`setup`의 `export CURL_FIXTURES=…` 다음 줄에 넣는다. https URL에서는 `Secure`가 있어야 통과하기 때문이다.

```bash
  export CURL_SB_COOKIE="set-cookie: auth_agent-hub=stub-session-token; Path=/; SameSite=Lax; HttpOnly; Secure"
```

"verify runs the MCP round trip over the tailnet URL and checks loopback binding"를 아래로 바꾼다.

```bash
@test "verify runs the MCP round trip and the SilverBullet login over the tailnet URLs and checks both loopback ports" {
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_success
  assert_output --partial "OK: MCP round trip passed"
  assert_output --partial "OK: SilverBullet checks passed for https://agent-hub.example.ts.net:8443"
  assert_output --partial "port 8737 listens on 127.0.0.1 only"
  assert_output --partial "port 3000 listens on 127.0.0.1 only"
  assert_output --partial "443 -> 127.0.0.1:8737, 8443 -> 127.0.0.1:3000"
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 80 443 8443 8737 3000"
  run grep -F 'https://agent-hub.example.ts.net/mcp' "$STUB_LOG"
  assert_success
  run grep -c '^nc ' "$STUB_LOG"
  assert_output 6
}
```

"verify bounds the public probe's connect time with -G on macOS only"의 `assert_output 4`를 `assert_output 6`으로 바꾼다. 점검 포트가 둘 늘었다.

"probe runs every check without writing notes"를 아래로 바꾼다.

```bash
@test "probe runs every check without writing notes, logging in or needing SB_USER" {
  unset SB_USER
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_success
  assert_output --partial "OK: MCP read-only probe passed"
  assert_output --partial "OK: SilverBullet answers and refuses requests without a login"
  assert_output --partial "tailscale serve is tailnet only"
  assert_output --partial "public IP 203.0.113.10 refuses"
  run grep -F '"method":"tools/call"' "$STUB_LOG.requests"
  assert_failure
  run grep -F '/.auth' "$STUB_LOG"
  assert_failure
}
```

"verify fails when Tailscale Funnel exposes the VM" 다음에 넣는다. 각 사례는 `env`에 넘길 `VAR=value` 단어 한두 개다.

```bash
@test "verify fails unless Serve sends 443 to Basic Memory and 8443 to SilverBullet with Funnel off on both" {
  local case
  for case in "TS_STUB_SERVE_8443=" "TS_STUB_SERVE_8443=http://127.0.0.1:8737" "TS_STUB_SERVE_EMPTY=1" \
    "TS_STUB_FUNNEL=on TS_STUB_FUNNEL_PORT=8443"; do
    run env $case "$REPO_DIR/scripts/verify-vm.sh" --read-only
    [[ "$status" -ne 0 ]] || fail "expected a failure with $case; got: $output"
  done
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 바꾸거나 새로 쓴 verify·probe 테스트 4개가 실패한다(`port 3000`·`8443` 문구 없음, nc 4회, 새 Serve 검사 없음). 나머지는 PASS한다.

- [ ] **Step 3: `tests/stubs/tailscale` (전체)**

```bash
#!/usr/bin/env bash
# Test stub for tailscale. TS_STUB_STATUS_EXIT sets the `status` exit code (0 = on the tailnet).
# `up --auth-key=file:PATH` copies the key file to $STUB_LOG.authkey so tests can check it.
# `serve status [--json]` describes 443 -> http://127.0.0.1:8737 and 8443 -> $TS_STUB_SERVE_8443
# (default http://127.0.0.1:3000; empty = no 8443 mapping), tailnet only.
# TS_STUB_FUNNEL=on turns Funnel on for https port TS_STUB_FUNNEL_PORT (default 443).
# TS_STUB_SERVE_EMPTY=1 makes `serve status` report no config (Serve/HTTPS not enabled on the tailnet).
set -euo pipefail
printf 'tailscale %s\n' "$*" >>"$STUB_LOG"

readonly HOST=agent-hub.example.ts.net
SB_TARGET="${TS_STUB_SERVE_8443-http://127.0.0.1:3000}"
FUNNEL_PORT=""
if [[ "${TS_STUB_FUNNEL:-off}" == on ]]; then
  FUNNEL_PORT="${TS_STUB_FUNNEL_PORT:-443}"
fi

# scope PORT -> the text-mode suffix of https port PORT.
scope() {
  if [[ "$1" == "$FUNNEL_PORT" ]]; then
    echo "(Funnel on)"
  else
    echo "(tailnet only)"
  fi
}

serve_text() {
  if [[ -n "${TS_STUB_SERVE_EMPTY:-}" ]]; then
    echo "No serve config"
    return
  fi
  echo "https://$HOST $(scope 443)"
  echo "|-- / proxy http://127.0.0.1:8737"
  if [[ -n "$SB_TARGET" ]]; then
    echo
    echo "https://$HOST:8443 $(scope 8443)"
    echo "|-- / proxy $SB_TARGET"
  fi
}

serve_json() {
  local web funnel=""
  if [[ -n "${TS_STUB_SERVE_EMPTY:-}" ]]; then
    echo '{}'
    return
  fi
  web="\"$HOST:443\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://127.0.0.1:8737\"}}}"
  if [[ -n "$SB_TARGET" ]]; then
    web="$web,\"$HOST:8443\":{\"Handlers\":{\"/\":{\"Proxy\":\"$SB_TARGET\"}}}"
  fi
  if [[ -n "$FUNNEL_PORT" ]]; then
    funnel=",\"AllowFunnel\":{\"$HOST:$FUNNEL_PORT\":true}"
  fi
  printf '{"TCP":{"443":{"HTTPS":true},"8443":{"HTTPS":true}},"Web":{%s}%s}\n' "$web" "$funnel"
}

case "${1:-}" in
  status) exit "${TS_STUB_STATUS_EXIT:-0}" ;;
  up)
    for arg in "$@"; do
      if [[ "$arg" == --auth-key=file:* ]]; then
        cp "${arg#--auth-key=file:}" "$STUB_LOG.authkey"
      fi
    done
    # TS_STUB_UP_EXIT=<n> simulates a rejected key: the key was read, then `up` fails.
    exit "${TS_STUB_UP_EXIT:-0}"
    ;;
  serve)
    if [[ "${2:-}" == status && "${3:-}" == --json ]]; then
      serve_json
    elif [[ "${2:-}" == status ]]; then
      serve_text
    fi
    ;;
esac
```

- [ ] **Step 4: `scripts/verify-vm.sh` 구현**

머리 주석, 상수, Serve 검사, 공인 포트 검사, `main`을 바꾼다. `check_loopback_binding`, `probe_port`, `validate_public_ip`, `probe_is_open`은 그대로 둔다.

```bash
#!/usr/bin/env bash
# Verify the VM end to end: MCP round trip over the tailnet URL, the SilverBullet login on https port 8443,
# loopback-only binding of both ports, tailnet-only Serve that sends 443 to Basic Memory and 8443 to SilverBullet
# (no Funnel on either), and that the public IP refuses common ports. With --read-only it writes no notes and does
# not log in. Firewall rules and the tailnet policy cannot be read from here; audit them by hand
# (docs/runbooks/operations.md, Exposure audit).
# Usage: verify-vm.sh [--read-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly PUBLIC_PROBE_TIMEOUT_SECONDS=5
readonly SB_HTTPS_PORT=8443
readonly PUBLIC_PROBE_PORTS="22 80 443 $SB_HTTPS_PORT"
```

`check_serve_tailnet_only`(현재 `:27-36`)를 지우고 그 자리에 넣는다.

```bash
# serve_proxy CONFIG_JSON PORT -> the proxy target of path / on https port PORT in `tailscale serve status --json`,
# without a trailing slash (empty when there is none).
serve_proxy() {
  jq -r --arg suffix ":$2" \
    '[(.Web // {}) | to_entries[] | select(.key | endswith($suffix)) | .value.Handlers["/"].Proxy // empty] | join(" ") | rtrimstr("/")' <<<"$1"
}

check_serve() {
  local bm_port="$1" sb_port="$2" serve funnel pair https_port local_port target
  step "check tailscale serve: tailnet only, 443 -> Basic Memory, $SB_HTTPS_PORT -> SilverBullet"
  serve="$(remote "sudo -n tailscale serve status --json")" || die "could not read tailscale serve status on $BM_VM_HOST"
  funnel="$(jq -r '[(.AllowFunnel // {})[] | select(. == true)] | length' <<<"$serve")" \
    || die "unexpected tailscale serve status (not JSON): $serve"
  ((funnel == 0)) \
    || die "Funnel is on for this node: the unauthenticated endpoint is public; turn it off (docs/runbooks/operations.md, Exposure audit)"
  for pair in "443 $bm_port" "$SB_HTTPS_PORT $sb_port"; do
    read -r https_port local_port <<<"$pair"
    target="$(serve_proxy "$serve" "$https_port")" || die "unexpected tailscale serve status (not JSON): $serve"
    [[ "$target" == "http://127.0.0.1:$local_port" ]] \
      || die "tailscale serve must proxy https port $https_port to http://127.0.0.1:$local_port (found '${target:-nothing}'): rerun 'make vm-bootstrap HOST=$BM_VM_HOST'"
  done
  log "OK: tailscale serve is tailnet only: 443 -> 127.0.0.1:$bm_port, $SB_HTTPS_PORT -> 127.0.0.1:$sb_port"
}
```

`check_public_closed`(현재 `:81-91`)를 바꾼다.

```bash
check_public_closed() {
  local ports="$PUBLIC_PROBE_PORTS $*" probe platform
  platform="$(uname -s)" || die "could not detect the local platform with uname -s"
  step "check public IP $BM_VM_PUBLIC_IP refuses ports $ports"
  for probe in $ports; do
    if probe_is_open "$platform" "$BM_VM_PUBLIC_IP" "$probe"; then
      die "public IP $BM_VM_PUBLIC_IP accepts connections on port $probe: remove the firewall rule that allows it"
    fi
  done
  log "OK: public IP $BM_VM_PUBLIC_IP refuses ports $ports"
}
```

`main`(현재 `:93-115`)을 바꾼다.

```bash
main() {
  local port="${BM_PORT:-8737}" sb_port="${SB_PORT:-3000}" url sb_url
  case "${1:-}" in
    "" | --read-only) ;;
    *) die "usage: verify-vm.sh [--read-only]" ;;
  esac
  require_cmd ssh curl jq nc
  require_env BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP
  [[ "$BM_TAILNET_DOMAIN" =~ ^[a-z0-9-]+\.ts\.net$ ]] \
    || die "BM_TAILNET_DOMAIN must look like tail1234.ts.net (no https://, no trailing dot): '$BM_TAILNET_DOMAIN'"
  validate_public_ip "$BM_VM_PUBLIC_IP"
  url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}/mcp"
  sb_url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}:$SB_HTTPS_PORT"

  if [[ "${1:-}" == --read-only ]]; then
    "$SCRIPT_DIR/verify-mcp.sh" --read-only "$url"
    "$SCRIPT_DIR/verify-sb.sh" --read-only "$sb_url"
  else
    "$SCRIPT_DIR/verify-mcp.sh" "$url"
    "$SCRIPT_DIR/verify-sb.sh" "$sb_url"
  fi
  check_loopback_binding "$port"
  check_loopback_binding "$sb_port"
  check_serve "$port" "$sb_port"
  check_public_closed "$port" "$sb_port"
  log "OK: automated VM checks passed; audit firewall rules and the tailnet policy by hand (docs/runbooks/operations.md, Exposure audit)"
}
```

`Makefile`의 두 설명을 바꾼다.

```make
verify: ## Full VM check: MCP write/read/delete, SilverBullet login, loopback binding, tailnet-only serve, closed public ports
```

```make
probe: ## Read-only VM check: same as verify but writes no notes and does not log in to SilverBullet
```

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected:
- exit 0이고 `vm_ops.bats` 전체가 ok다.
- 바꾸지 않은 "verify fails when Tailscale Funnel exposes the VM"은 JSON의 `AllowFunnel` 때문에 `Funnel is on for this node`를 내며 계속 통과한다.
- 텍스트 모드를 쓰는 `bootstrap.bats`와 `status` 테스트도 PASS한다.

- [ ] **Step 6: 커밋과 push**

```bash
git add scripts/verify-vm.sh tests/stubs/tailscale tests/vm_ops.bats Makefile
git commit -m "feat: verify the SilverBullet login and each Serve port on the VM" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 11" --trailer "Task: 1"
git push
```

### Task 2: 부트스트랩의 Serve 8443

**Files:**
- Modify: `scripts/remote/bootstrap.sh:7` 근처(상수), `:141-153`(`configure_serve`), `scripts/bootstrap-vm.sh:54`(원격 환경변수)
- Test: `tests/bootstrap.bats`(두 테스트 수정)

**Interfaces:**
- Consumes: Task 1의 tailscale 스텁(텍스트 모드의 8443 블록, `TS_STUB_SERVE_8443`)
- Produces: 부트스트랩이 `tailscale serve --bg --https=8443 http://127.0.0.1:${SB_PORT}`를 실행한다. `bootstrap-vm.sh`는 `SB_PORT`를 원격 환경으로 넘긴다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/bootstrap.bats`)**

"on a host already on the tailnet it skips the docker install, …and serves the loopback port"(현재 `:76`)의 이름 끝을 `serves both loopback ports`로 바꾼다. `grep -F 'tailscale serve --bg http://127.0.0.1:8737'` 검사 다음에 넣는다.

```bash
  run grep -F 'tailscale serve --bg --https=8443 http://127.0.0.1:3000' "$STUB_LOG"
  assert_success
```

"fails with HTTPS guidance when Serve is not active after setup"(현재 `:95`)를 반복문으로 바꾼다. 원래 사례(`TS_STUB_SERVE_EMPTY=1`)는 그대로 남는다.

```bash
@test "fails with HTTPS guidance when Serve is not active after setup, also when only the 8443 mapping is missing" {
  local case
  setup_stubs docker
  for case in "TS_STUB_SERVE_EMPTY=1" "TS_STUB_SERVE_8443="; do
    run env "$case" bash -c 'printf "\n" | "$0"' "$BOOTSTRAP"
    assert_failure
    assert_output --partial "Serve is not active"
    assert_output --partial "enable MagicDNS and HTTPS certificates"
    refute_output --partial "done"
  done
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 두 테스트만 실패한다. 첫째는 8443 `serve` 호출이 없어서, 둘째는 `TS_STUB_SERVE_8443=` 사례가 통과해 버려서다.

- [ ] **Step 3: 구현**

`scripts/remote/bootstrap.sh`의 `readonly BM_PORT=…`(현재 `:7`) 다음에 넣는다.

```bash
readonly SB_PORT="${SB_PORT:-3000}"
# Tailscale Serve publishes SilverBullet on this https port of the same tailnet name (443 stays Basic Memory).
readonly SB_HTTPS_PORT=8443
```

`configure_serve`(현재 `:141-153`, 위 주석 포함)를 바꾼다.

```bash
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
    die "Funnel is on for this node, which makes the unauthenticated endpoint public: turn it off (docs/runbooks/operations.md, Exposure audit), then rerun 'make vm-bootstrap'"
  fi
  for port in "$BM_PORT" "$SB_PORT"; do
    grep -qE "proxy http://127\.0\.0\.1:${port}/?\$" <<<"$serve_status" \
      || die "Serve is not active (expected a proxy to http://127.0.0.1:$port, got: $serve_status): enable MagicDNS and HTTPS certificates in the Tailscale admin console (docs/runbooks/accounts.md), then rerun 'make vm-bootstrap'"
  done
  log "tailscale serve -> $bm_target (https 443) and $sb_target (https $SB_HTTPS_PORT), tailnet only"
}
```

`scripts/bootstrap-vm.sh:54`를 바꾼다.

```bash
  remote_env="BM_PORT=${BM_PORT:-8737} SB_PORT=${SB_PORT:-3000} BM_REMOTE_DATA_ROOT=$BM_REMOTE_DATA_ROOT BM_REMOTE_APP_DIR=$BM_REMOTE_APP_DIR"
```

- [ ] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0. `bootstrap.bats` 전체가 ok이고, `repo.bats`의 "no script enables Tailscale Funnel"도 통과한다.

- [ ] **Step 5: 커밋과 push**

```bash
git add scripts/remote/bootstrap.sh scripts/bootstrap-vm.sh tests/bootstrap.bats
git commit -m "feat: serve SilverBullet on https port 8443 of the tailnet name" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 11" --trailer "Task: 2"
git push
```

### Task 3: 운영 문서

**Files:**
- Modify: `docs/runbooks/operations.md`, `docs/runbooks/bootstrap.md:29-35`, `docs/ARCHITECTURE.md`(토폴로지 첫 줄들, Serve 행, 자동 검증 범위, 검증 흐름), `README.md:39`

**Interfaces:**
- Consumes: Task 1·2의 출력 문구(`OK: SilverBullet checks passed`, `refuses ports 22 80 443 8443 8737 3000`)

- [ ] **Step 1: `docs/runbooks/operations.md`**

"일상 명령" 표의 배포 행 다음에 한 행을 넣는다.

```markdown
| 웹 UI 글꼴 (새 VM이나 글꼴을 바꿀 때) | `make sb-fonts` |
```

표 아래 첫 문장을 바꾼다.

```markdown
에이전트는 `vm-bootstrap`, `deploy`, `restore`, `sb-fonts` 전에 사용자의 OK를 받습니다. `probe`, `status`, `logs`, `verify`, `backup`은 OK 없이 실행할 수 있습니다(`verify`는 테스트 노트를 쓰고 지우며 SilverBullet에 로그인했다가 로그아웃하고, `backup`은 컨테이너를 잠깐 멈춥니다).
```

"## 업그레이드·복구·진단" 절 다음에 새 절을 넣는다.

```markdown
## 웹 UI (SilverBullet)

- 주소는 `https://agent-hub.<tailnet>.ts.net:8443`이고 tailnet 안에서만 열립니다. main 체크아웃 `.env`의 `SB_USER`로 로그인합니다. 트리는 `Cmd-O`, 페이지 검색은 `Cmd-K`, 노트 본문 검색은 `Cmd-Shift-F`, 그래프는 명령 팔레트의 `Graph: Explore`입니다. 에이전트에게 노트를 알려 줄 때는 `Basic Memory: Copy memory:// Link`로 주소를 복사합니다.
- 노트 검색에 본문 문단이 안 나오면 그 브라우저에서 `Space: Reindex`를 한 번 실행합니다. 왼쪽에 트리가 안 보이면 `Cmd-O`를 누릅니다.
- **관찰 카테고리 경고:** `[fact]`·`[decision]` 같은 카테고리 글자를 누르면 SilverBullet이 카테고리를 지웁니다(`[]`가 되고 Basic Memory는 그 관찰을 `note`로 다시 색인). 실수했으면 바로 `Cmd+Z`로 되돌립니다.
- **비밀번호 교체:** main 체크아웃 `.env`의 `SB_USER`를 바꾸고 `make deploy`(사용자 OK)를 실행합니다. VM `.env`가 바뀌면 compose가 SilverBullet을 다시 만들고, 열린 브라우저는 다시 로그인해야 합니다.
- **글꼴:** 새 VM이거나 글꼴을 바꿀 때 `make sb-fonts`(사용자 OK). 복원하면 백업에 든 글꼴이 돌아오므로 다시 올릴 필요가 없습니다.
- **무시 목록:** 저장소의 `silverbullet/notes.gitignore`를 고치고 `make deploy`를 실행합니다. 배포가 Basic Memory를 다시 만들어 새 목록을 읽게 합니다(VM 콜드 스타트 161~192초). 이미 색인된 항목은 남습니다.
- **관리 페이지:** `Library/agent-hub/agent-hub.md`는 배포마다 덮어씁니다. 개인 설정은 `CONFIG` 페이지에 둡니다. 대시보드 `index`는 처음 한 번만 만들고 이후에는 건드리지 않습니다.
```

Exposure audit 첫 문단의 자동 검사 목록을 바꾼다.

```markdown
`make verify`/`make probe`는 VM 쪽에서 확인할 수 있는 것만 자동으로 검사합니다: 8737·3000의 `127.0.0.1` 바인딩, Serve가 tailnet 전용이고 443→Basic Memory·8443→SilverBullet인지(두 포트 모두 Funnel off), 공인 IP의 22·80·443·8443·8737·3000 차단. 나머지 두 가지는 VM에서 읽을 수 없으므로, 배포 직후와 방화벽·정책을 바꾼 뒤(VM 재구축 포함)에 손으로 점검하고 결과를 Incident log 아래 "점검 기록"에 남깁니다.
```

Funnel 문단의 `serve reset` 문장 끝에 한 문장을 더한다. 계획 05가 이 문단을 고쳤으면 고친 문장 뒤에 더한다.

```markdown
`serve reset`은 443과 8443 설정을 모두 지우므로, 그 뒤 `make vm-bootstrap HOST=agent-hub`로 두 포트를 다시 설정합니다.
```

- [ ] **Step 2: `docs/runbooks/bootstrap.md:29-35`와 `README.md:39`**

`bootstrap.md:29`의 `make deploy verify status`를 `make deploy sb-fonts verify status`로 바꾼다(`sb-fonts`는 Mac의 TTF가 필요하다. README 사전 요구사항 참고). `:33`과 `:35`를 바꾼다.

```markdown
- [ ] `make verify`가 `OK: MCP round trip passed`, `OK: SilverBullet checks passed`, `listens on 127.0.0.1 only`(8737과 3000), `tailscale serve is tailnet only`, `refuses ports 22 80 443 8443 8737 3000`을 모두 출력한다.
```

```markdown
- [ ] `make status`에 두 컨테이너의 `(healthy)`, `proxy http://127.0.0.1:8737`, `proxy http://127.0.0.1:3000`이 보이고, 스왑이 활성이다(`no active swap` 경고가 없음).
```

`README.md:39`의 끝 `make deploy verify status`를 `make deploy sb-fonts verify status`로 바꾼다.

- [ ] **Step 3: `docs/ARCHITECTURE.md`**

토폴로지 첫 세 줄(계획 10이 쓴 블록의 `[개인/회사 Mac]`부터 `▼`까지)을 다음으로 바꾼다.

```
[개인/회사 Mac] ── tailnet ──▶ https://agent-hub.<tailnet>.ts.net/mcp        에이전트 (MCP)
  에이전트, 브라우저,            └──▶ https://agent-hub.<tailnet>.ts.net:8443  브라우저 (로그인)
  make deploy/verify/backup          │ Tailscale Serve (HTTPS, tailnet 전용)
  (Tailscale SSH)                    ▼
```

구성 요소 표의 Tailscale Serve 행을 바꾼다.

```markdown
| Tailscale Serve | VM | tailnet HTTPS 443 → `http://127.0.0.1:8737`(Basic Memory), 8443 → `http://127.0.0.1:3000`(SilverBullet) |
```

신뢰 경계의 "자동 검증 범위" 줄에서 `(바인딩, Serve 상태, 공인 IP의 22·80·443·8737)`을 `(8737·3000 바인딩, Serve 포트별 대상과 Funnel, SilverBullet 로그인·셸 꺼짐, 공인 IP의 22·80·443·8443·8737·3000)`으로 바꾼다.

주요 흐름의 검증 줄을 바꾼다.

```markdown
- **검증:** `make verify` → tailnet URL로 MCP 왕복(initialize, tools/list, 쓰기·읽기·삭제) → 8443의 SilverBullet 로그인·쿠키·셸 꺼짐 → 포트 바인딩(8737, 3000) → Serve 포트별 대상, tailnet 전용 → 공인 IP 포트 차단. `make probe`는 노트를 쓰지 않고 SilverBullet에 로그인하지 않습니다.
```

- [ ] **Step 4: 확인**

Run: `make check`
Expected: exit 0. 상대 링크·docs 경로 검사와 `gcloud` 설정 검사가 통과한다.

Run: `grep -rn '22·80·443·8737\|22 80 443 8737' docs README.md`
Expected: 출력 없음. 완료된 계획 문서(`docs/plans/completed/`)에 남은 줄은 당시 기록이므로 고치지 않는다.

- [ ] **Step 5: 커밋과 push**

```bash
git add docs/runbooks/operations.md docs/runbooks/bootstrap.md docs/ARCHITECTURE.md README.md
git commit -m "docs: add the web UI to the runbooks and the architecture" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 11" --trailer "Task: 3"
git push
```

### Task 4: VM 반영 (사용자와 함께, 단계마다 OK)

**Files:**
- Modify: `docs/decisions/0005-web-ui-silverbullet.md`("VM 측정" 절), 스펙 §3(해소한 Assumption), 이 계획 파일(Progress log)

**Interfaces:**
- Consumes: 계획 10·11의 모든 Make 타깃, 런북
- Produces: 스펙 §1 완료 조건 2·3·4·6의 증거

이 Task는 VM을 바꾼다. **각 단계 전에 사용자 OK를 받는다.** 사람은 VM 대상 타깃을 main 체크아웃에서 실행해도 된다(운영 런북).

- [ ] **Step 1: 사전 점검 (OK 불필요)**

```bash
make status
grep 'image:' compose.yaml
make backup
```

Expected:
- `make status`의 Basic Memory 이미지가 `compose.yaml`의 `basic-memory` 이미지와 같다(운영 런북 "배포·복원 전 이미지 점검"). 다르면 멈추고 사용자에게 묻는다.
- `make backup`이 `backup saved: <main>/backups/bm-<stamp>.tgz`로 끝난다. 이 백업이 롤백 지점이다. 경로를 Progress log에 적는다.

- [ ] **Step 2: Serve 8443 적용 (사용자 OK 후)**

Run: `make vm-bootstrap HOST=agent-hub </dev/null`
Expected: 키 없이 다음 줄들이 나온다.
- `already on the tailnet; refreshing hostname and Tailscale SSH`
- `tailscale serve -> http://127.0.0.1:8737 (https 443) and http://127.0.0.1:3000 (https 8443), tailnet only`
- `[bootstrap] done`

사용자가 자기 터미널에서 실행한다면 키 프롬프트에서 빈 값으로 Enter를 누른다. 키를 요구하며 멈추면 기록하고 사용자와 정한다.

- [ ] **Step 3: Serve 모양 확인 (읽기 전용, 항목 1·2)**

Run: `ssh ubuntu@agent-hub 'sudo -n tailscale serve status --json' | jq '{web: (.Web | with_entries(.key |= sub("^[^:]+"; "<host>")) | map_values(.Handlers["/"].Proxy)), funnel: (.AllowFunnel // {})}'`

Expected:
- `web`에 `"<host>:443": "http://127.0.0.1:8737"`과 `"<host>:8443": "http://127.0.0.1:3000"`이 있다.
- `funnel`이 `{}`이다.
- 호스트 이름은 `<host>`로 가려지므로 결과를 그대로 기록해도 된다.
- raw `ssh`를 쓴 이유: 스텁 JSON과 실제 모양을 비교하려는 읽기 전용 확인이다.
- 모양이 다르면 Task 1의 `serve_proxy`와 스텁을 실제에 맞추는 수정 커밋을 만든다(`fix:`, `Task: 4`). 그다음 이 Step부터 다시 한다.

이어서 `make probe`를 실행한다. 아직 SilverBullet을 배포하지 않았으므로 `SilverBullet does not answer at …:8443/.ping`으로 실패하는 것이 정상이다. 3000 루프백 검사 전에 멈춘다.

- [ ] **Step 4: 배포 (사용자 OK 후, 항목 4·5)**

Run: `time make deploy`
Expected:
- `the notes .gitignore changed`가 나오고, Basic Memory를 다시 만든 뒤 `deployed. Next: make verify`로 끝난다.
- 걸린 시간을 기록한다(콜드 스타트 포함, 360초 안).
- `sudo -n -u #1000` 쓰기가 실패하면 멈추고 `bm-diagnose` 스킬로 원인을 찾는다.

- [ ] **Step 5: 글꼴과 종단 검증 (`sb-fonts`는 사용자 OK 후, 항목 3)**

```bash
make sb-fonts
make verify status
```

Expected:
- `make verify`가 다음을 출력하고, 글꼴 경고는 없다.
  - `OK: MCP round trip passed`
  - `OK: SilverBullet checks passed for https://agent-hub.<tailnet>.ts.net:8443`
  - `port 3000 listens on 127.0.0.1 only`
  - `tailscale serve is tailnet only: 443 -> 127.0.0.1:8737, 8443 -> 127.0.0.1:3000`
  - `refuses ports 22 80 443 8443 8737 3000`
- `make status`에 두 컨테이너의 `(healthy)`와 메모리·스왑이 나온다.
- 출력의 tailnet 이름은 `<tailnet>`으로 가려 기록한다.

- [ ] **Step 6: 컨테이너 격리 확인 (읽기 전용, 항목 6)**

```bash
ssh ubuntu@agent-hub 'docker exec silverbullet-server curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8737/mcp || true'
ssh ubuntu@agent-hub 'gw="$(docker network inspect basic-memory_silverbullet -f "{{(index .IPAM.Config 0).Gateway}}")"; docker exec silverbullet-server curl -s -m 3 -o /dev/null -w "%{http_code}\n" "http://$gw:8737/mcp" || true'
ssh ubuntu@agent-hub 'docker exec silverbullet-server curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://basic-memory-server:8000/mcp || true'
```

Expected:
- 세 줄 모두 `000`이다. SilverBullet 컨테이너는 다음 세 곳 모두에 닿지 못한다.
  - 컨테이너 자신의 루프백
  - 호스트 게이트웨이(Basic Memory는 호스트 `127.0.0.1`에만 바인딩)
  - 다른 네트워크의 Basic Memory 컨테이너
- raw `ssh`·`docker exec`를 쓴 이유: 스펙 §3 Assumption을 확인하는 읽기 전용 보안 점검이다.
- `000`이 아닌 값이 하나라도 나오면 멈추고 사용자와 정한다(스펙 §8의 네트워크 분리 가정이 깨진 것이다).

- [ ] **Step 7: 메모리·OOM (읽기 전용, 항목 7, 완료 조건 6)**

```bash
make status
ssh ubuntu@agent-hub 'docker stats --no-stream --format "{{.Name}} {{.MemUsage}}"; sudo -n dmesg | grep -i -E "out of memory|oom-kill" || echo none'
```

Expected:
- 다음을 기록한다: 두 컨테이너의 메모리, 전체 메모리·스왑 사용량, OOM 줄(`none`).
- 브라우저 확인(Step 8)을 한 뒤 한 번 더 잰다.
- OOM이 있거나 스왑이 크게 늘면 ADR 0002를 다시 판단할지 사용자와 정한다.

- [ ] **Step 8: 브라우저 확인 (사용자, 완료 조건 3·4)**

사용자가 Mac 브라우저에서 `https://agent-hub.<tailnet>.ts.net:8443`을 열어 로그인한다. 에이전트는 계획 10 Task 6 Step 4·5의 목록으로 함께 확인한다.
- 3단 레이아웃, 대시보드, 글꼴 Regular·Bold, `Graph: Explore`
- 새 페이지 줄바꿈
- `search_notes`에 SilverBullet 전용 페이지가 나오지 않음. `search_notes`는 tailnet URL의 MCP로 부른다(계획 10 Task 6의 일회용 스크립트에서 `URL`만 `https://agent-hub.<tailnet>.ts.net/mcp`로 바꿈).

VM에는 시드 노트를 넣지 않고 실제 노트로 확인한다. 줄바꿈 확인용 페이지(`research/Newline Check`)는 확인 뒤 지울지 사용자에게 묻는다.

- [ ] **Step 9: 기록**

- ADR 0005의 "VM 측정" 절에 Step 4·5·7의 수치를 `Verified`(명령 포함)로 적는다: 배포 시간, 두 컨테이너 메모리, 전체 메모리·스왑, OOM 여부.
- 스펙 §3의 "Assumption (계획 11에서 확인)" 중 확인한 것을 `Verified (계획 11, <날짜>)`로 바꾼다.
- Progress log에 Step 1~8의 증거를 적는다.

- [ ] **Step 10: 커밋과 push**

```bash
git add docs/decisions/0005-web-ui-silverbullet.md docs/specs/2026-10-14-silverbullet-web-ui-design.md docs/plans/active/2026-10-14-11-web-ui-vm-rollout.md
git commit -m "docs: record the web UI rollout on the VM" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 11" --trailer "Task: 4"
git push
```

**롤백(문제가 생겼을 때, 사용자 OK 후):**
- SilverBullet만 문제라면 `ssh ubuntu@agent-hub 'cd /opt/basic-memory && docker compose stop silverbullet'`로 멈추고 이유를 Incident log에 적는다. Basic Memory는 그대로 돈다.
- 데이터가 상했다면 Step 1의 백업으로 `make restore BACKUP=<그 파일>`을 실행한다. 사용자가 자기 터미널에서 `yes`를 입력한다.

---

### 마무리: 리뷰, 넘기기 (git-workflow 스킬의 Review and merge)

- [ ] Progress log에 그날 `make check`의 테스트 수와 커버리지 %를 `Verified`로 적고, 계획 파일을 `docs/plans/completed/`로 옮겨 커밋·push한다(`Task: none`).
- [ ] 다른 벤더의 읽기 전용 리뷰(`make review BRANCH=plan/11-web-ui-vm-rollout REVIEWER=<다른 벤더>`)는 사용자 승인 후 실행한다. PR 코멘트 게시도 승인 후 한다. 게시 전에 VM IP와 tailnet 이름, 세션 id를 가린다.
- [ ] 지적을 검증하고 하나당 커밋 하나로 고친다. 2회차까지만 돈다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.
- [ ] 병합 뒤 Clean up 절로 worktree를 정리한다(`backups/`·`.env` 확인 먼저).

## Follow-ups (이 계획 밖)

- VM 기본 서비스 계정 제거(스펙 §8.6). VM을 멈춰야 하는 클라우드 변경이므로 별도로 승인받는다.
- SilverBullet 업스트림 이슈 게시(사용자 결정). 게시하면 운영 런북의 경고에 링크를 단다.
- `bm-diagnose`·`bm-recover` 스킬에 SilverBullet 컨테이너와 Serve 8443을 다루는 문장을 더할지 판단한다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
