# 12 Access Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Nothing in this plan touches the VM or cloud resources. Task 7 edits `AGENTS.md` only after the user approves the wording. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `.env`의 `BM_ACCESS=tailscale|ssh`로 VM마다 접속 방식 하나를 고르게 하고, `make access-check`·`make tunnel`과 모드별 부트스트랩·`status`·`verify`, 런북·ADR 0006을 더한다. 모두 스텁으로 검증한다.

**Architecture:**
- `scripts/lib/common.sh`에 `access_mode`·`access_hint`·`forward_spec`·`vm_tailscale_logged_in`을 둔다.
- `ssh` 모드에서 스크립트가 아는 것은 `BM_VM_USER@BM_VM_HOST`로 닿는 SSH뿐이다. 별칭이 IAP를 쓰는지는 사용자의 `~/.ssh/config`가 정하고, GCP 런북이 그 설정을 안내한다. 그래서 스크립트에는 클라우드 이름이 들어가지 않는다.
- `verify-vm.sh`는 `ssh` 모드에서 임시 `ssh -N -L`(127.0.0.1:28737, 23000)을 띄워 MCP·웹 UI를 검사하고, Serve 검사 대신 "VM의 Tailscale 꺼짐"과 "sshd 키 전용"을 본다.
- `tailscale` 모드(또는 `BM_ACCESS` 없음)의 동작은 계획 11 병합 시점과 같다.

**Tech Stack:** bash 3.2 호환 셸, bats-core + bats-assert, OpenSSH 로컬 포워딩(`-N -L`, `ExitOnForwardFailure`, `ServerAliveInterval`), curl, nc, 계획 10·11의 스크립트

**Spec:** `docs/specs/2026-10-15-access-modes-design.md` (특히 §2, §6, §8, §11)

**Sequence:** 계획 12. 다음을 모두 만족한 뒤 시작한다.
- 계획 10과 계획 11이 `main`에 병합됐다(`docs/plans/completed/`에 두 계획 파일이 있다).
- 이 계획의 코드 조각은 계획 10·11이 쓴 `verify-vm.sh`·`deploy.sh`·`tests/stubs/curl`·`tests/helpers.bash`를 전제로 한다. 시작 절의 확인이 다르게 나오면 그 Step을 실제 코드에 맞춰 고치고 Progress log에 적는다.

## Global Constraints

- 스크립트와 스킬에 `oci|oracle|gcp|gcloud`를 쓰지 않는다(`tests/cloud_neutral.bats`). 클라우드 쪽 안내는 `docs/runbooks/gcp-vm.md`를 가리킨다.
- 런북·README·ARCHITECTURE·스킬의 모든 `gcloud <명령>` 줄에 `--configuration=bm-personal`을 쓴다(`tests/repo.bats`).
- 모드 값은 `tailscale` 또는 `ssh`뿐이다. 비어 있으면 `tailscale`. 그 밖의 값(대소문자 다름 포함)은 VM에 닿기 전에 `die`한다.
- 로컬 포트: `make tunnel` 18737(MCP)·13000(웹 UI), `verify` 임시 터널 28737·23000. 모든 `-L`은 `forward_spec`을 거쳐 `127.0.0.1:LOCAL:127.0.0.1:REMOTE` 모양이다.
- `ssh` 모드에서 `make tunnel`은 다시 붙지 않는다. ssh가 끝나면 종료 코드를 알리고 실패한다.
- AGENTS.md 스크립트 규칙: `#!/usr/bin/env bash` 다음 `set -euo pipefail`, `common.sh` source, `die`, macOS bash 3.2(연관 배열·`mapfile`·빈 배열 확장 금지), 이름 붙인 상수, `x="$(fn)" || exit 1`. 코드·주석·스크립트 메시지는 영어, 런북·ADR·README·ARCHITECTURE는 한국어.
- 테스트 먼저(RED → GREEN), ADR 0004 범위. 기존 assertion을 약하게 바꾸지 않는다. 기존 `vm_ops.bats`·`bootstrap.bats` 테스트는 고치지 않고 통과해야 한다(스펙 §1 완료 조건 2).
- 테스트는 `make test`/`make check`로만 돌린다.
- 공인 IP, tailnet 이름, 프로젝트 id를 커밋·PR·문서에 쓰지 않는다. 테스트는 `203.0.113.10`, `example.ts.net`, `tunnel.example.test`를 쓴다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 12`, `Task: <N|review|none>`. `Co-authored-by`, `Signed-off-by`, `Claude-Session`, 세션 링크, `Generated with`는 넣지 않는다.
- PR: 머신 계정으로 push하고 초안 PR 하나. 제목 `feat: choose Tailscale or an SSH tunnel per VM (BM_ACCESS)`, 본문 마지막 문단은 `Assisted-by`와 `Plan: 12`.

## Review Focus

1. **`BM_ACCESS`가 없는 기존 `.env`를 쓰는 사람이 Tailscale이 막힌 네트워크에서 `make access-check`를 실행함.** 모드를 정하지 않았으므로 보고만 하고 0으로 끝나야 한다. → Task 1 첫 테스트(`BM_ACCESS` 없음, 조정 서버 timeout, 성공).
2. **`BM_ACCESS=SSH`나 `Ssh`처럼 대소문자가 다른 값.** 조용히 `tailscale`로 돌아가면 사용자는 엉뚱한 경로를 검사한다. → Task 4 "verify rejects a BM_ACCESS it does not know" 테스트(`SSH`, ssh 호출 없음).
3. **`verify` 도중 MCP 검사가 실패함.** 임시 터널 프로세스가 남아 28737을 잡고 있으면 다음 `verify`가 포트 충돌로 실패한다. → Task 4 "closes its tunnel even when a check fails" 테스트.
4. **`BM_TUNNEL_MCP_PORT=80`처럼 특권 포트이거나, 다른 `make tunnel`이 이미 13000을 씀.** 알 수 없는 ssh 오류 대신 원인을 말하고 ssh를 부르지 않아야 한다. → Task 2 거부 테스트.
5. **클라이언트를 `http://localhost:18737/mcp`로 등록함.** 터널은 `127.0.0.1`(IPv4)에만 바인딩하므로, `localhost`가 `::1`로 풀리면 연결이 거부된다. → Task 6 operations 런북 "에이전트 연결"에 `127.0.0.1`을 쓰라는 문장과 이유(자동 테스트 없음, 리뷰어가 문구를 확인).

---

### 시작: 브랜치, worktree, 초안 PR, 전제 확인 (에이전트)

- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/12-access-modes` 브랜치를 만든다(git-workflow 스킬의 Start).
- [ ] 계획 10·11 병합과 이 계획이 기대는 코드 모양을 확인한다.

```bash
ls docs/plans/completed/ | grep -E '^2026-10-14-1[01]-'
grep -nE '^(serve_proxy|check_serve|check_public_closed)\(\)|^readonly SB_HTTPS_PORT' scripts/verify-vm.sh
grep -n 'SB_PORT' Makefile tests/helpers.bash
grep -n 'https://\*' scripts/verify-sb.sh
grep -n 'url=""' tests/stubs/curl
grep -n 'over Tailscale SSH' scripts/*.sh scripts/lib/common.sh
```

Expected:
- 완료 계획 두 개(10, 11)가 보인다.
- `verify-vm.sh`에 `serve_proxy`, `check_serve`, `check_public_closed`와 `SB_HTTPS_PORT`가 있다(계획 11 Task 1).
- `Makefile`의 `export` 줄과 `tests/helpers.bash`의 `use_vm_env`에 `SB_PORT`가 있다(계획 10).
- `verify-sb.sh`는 `https://*` URL에서만 쿠키 `Secure`를 요구한다(계획 10 Task 3). 그래서 Task 4의 http 터널 URL에서는 `Secure`가 필요 없다.
- `tests/stubs/curl`에 `url=""`이 있다(계획 10의 SilverBullet 모드).
- 마지막 명령은 `common.sh`의 `remote()` 주석과 `deploy.sh`·`restore.sh`·`bootstrap-vm.sh`의 안내 줄을 보인다. 이 목록을 Task 5에서 쓴다.
- 하나라도 다르면 해당 Task의 코드를 실제 모양에 맞춘다. 차이와 판단을 Progress log에 `Verified`로 적는다.

- [ ] 첫 커밋으로 이 계획 파일을 `active/`로 옮기고 push한 뒤 초안 PR을 연다.

```bash
git mv docs/plans/backlog/2026-10-15-12-access-modes.md docs/plans/active/2026-10-15-12-access-modes.md
git commit -m "docs: start plan 12 access modes" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: none"
git push -u origin plan/12-access-modes
gh pr create --draft --base main --title "feat: choose Tailscale or an SSH tunnel per VM (BM_ACCESS)" --body-file "$TMPDIR/pr-12.md"
```

---

### Task 1: 모드 설정과 `make access-check`

**Files:**
- Create: `scripts/access-check.sh`(실행 권한), `tests/access.bats`
- Modify: `scripts/lib/common.sh`(`access_mode`, `access_hint`), `tests/stubs/curl`(실패 흉내, 상태 코드), `.env.example`, `Makefile`(export, `access-check` 타깃, `.PHONY`)

**Interfaces:**
- Produces (`common.sh`):
  - `access_mode` → stdout `tailscale` 또는 `ssh`. 다른 값이면 `die "BM_ACCESS must be tailscale or ssh (got '<값>'): ..."`. 호출은 `mode="$(access_mode)" || exit 1`.
  - `access_hint` → stdout 한 줄. `ssh` 모드: `check the ProxyCommand for <host> in ~/.ssh/config and its login (docs/runbooks/gcp-vm.md)`. 그 밖: `is <host> reachable over Tailscale SSH? (ssh <user>@<host> true)`.
- Produces (curl 스텁): `CURL_STUB_FAIL_MATCH=<부분 문자열>`(인자에 있으면 `CURL_STUB_FAIL_EXIT`, 기본 28로 실패), 다운로드 모드에서 `-w '%{http_code}'`가 있으면 `CURL_STUB_HTTP_CODE`(기본 200)를 출력한다.
- Produces: `make access-check`, `.env`의 `BM_ACCESS`, `BM_ACCESS_CHECK_URL`, `BM_TUNNEL_MCP_PORT`, `BM_TUNNEL_WEB_PORT`(Makefile이 export).

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/access.bats`, 새 파일)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl ssh nc
  use_vm_env
  unset BM_ACCESS
  export BM_ACCESS_CHECK_URL=https://tunnel.example.test/ CURL_STUB_HTTP_CODE=404
  ACCESS_CHECK="$REPO_DIR/scripts/access-check.sh"
  TUNNEL="$REPO_DIR/scripts/tunnel.sh"
}

# --- access-check ---

@test "access-check reports each path on this network and recommends ssh when only the tunnel endpoint answers" {
  export CURL_STUB_FAIL_MATCH=controlplane.tailscale.com
  run "$ACCESS_CHECK"
  assert_success
  assert_output --partial "this network only: run it on every network your clients use"
  assert_output --partial "tailscale control plane: blocked (timeout)"
  assert_output --partial "tunnel endpoint https://tunnel.example.test/: reachable (HTTP 404)"
  assert_output --partial "recommendation for this network: ssh"
  run grep -F 'curl -sS -o /dev/null --max-time 8 -w %{http_code} https://controlplane.tailscale.com/' "$STUB_LOG"
  assert_success
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
}

@test "access-check fails only when the mode chosen in BM_ACCESS does not work on this network" {
  export CURL_STUB_FAIL_MATCH=controlplane.tailscale.com CURL_STUB_FAIL_EXIT=6 BM_ACCESS=tailscale
  run "$ACCESS_CHECK"
  assert_failure
  assert_output --partial "tailscale control plane: blocked (dns)"
  assert_output --partial "BM_ACCESS=tailscale does not work on this network"

  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap
  run "$ACCESS_CHECK"
  assert_success
  assert_output --partial "ssh ubuntu@agent-hub-iap: ok"

  export SSH_STUB_FAIL_MATCH=true
  run "$ACCESS_CHECK"
  assert_failure
  assert_output --partial "ssh ubuntu@agent-hub-iap: failed: check the ProxyCommand for agent-hub-iap in ~/.ssh/config"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `access.bats`의 두 테스트가 `scripts/access-check.sh: No such file or directory`로 실패한다. 나머지는 PASS.

- [ ] **Step 3: `tests/stubs/curl`**

머리 주석의 `# Download mode:` 줄을 아래 네 줄로 바꾼다.

```bash
# Download mode: writes "stub" to the -o file, or prints $CURL_STUB_SCRIPT (default "true") for `curl | sh`; with
#   -w '%{http_code}' it also prints CURL_STUB_HTTP_CODE (default 200), like a reachability probe.
# CURL_STUB_FAIL_MATCH=<substring>: calls whose arguments contain it fail with CURL_STUB_FAIL_EXIT (default 28 =
#   timeout; 6 = DNS), like a network that blocks that host.
```

`printf 'curl %s\n' "$*" >>"$STUB_LOG"` 바로 다음에 넣는다.

```bash
if [[ -n "${CURL_STUB_FAIL_MATCH:-}" && "$*" == *"$CURL_STUB_FAIL_MATCH"* ]]; then
  echo "curl: (${CURL_STUB_FAIL_EXIT:-28}) simulated failure (stub)" >&2
  exit "${CURL_STUB_FAIL_EXIT:-28}"
fi
wants_code=""
if [[ "$*" == *'%{http_code}'* ]]; then
  wants_code=1
fi
```

다운로드 모드 분기(`if [[ -z "${CURL_FIXTURES:-}" ]]; then`부터 그 `fi`까지)를 바꾼다.

```bash
if [[ -z "${CURL_FIXTURES:-}" ]]; then
  if [[ -n "$body_file" ]]; then
    echo stub >"$body_file"
    if [[ -n "$wants_code" ]]; then
      printf '%s' "${CURL_STUB_HTTP_CODE:-200}"
    fi
  else
    printf '%s\n' "${CURL_STUB_SCRIPT:-true}"
  fi
  exit 0
fi
```

- [ ] **Step 4: `scripts/lib/common.sh`**

`remote()` 앞에 넣는다.

```bash
# access_mode -> tailscale or ssh: BM_ACCESS, or tailscale when it is unset (.env files from before the ssh mode).
# Any other value, another case included, stops here so no script falls back to the wrong path.
# Call it as mode="$(access_mode)" || exit 1.
access_mode() {
  local mode="${BM_ACCESS:-tailscale}"
  case "$mode" in
    tailscale | ssh) printf '%s\n' "$mode" ;;
    *) die "BM_ACCESS must be tailscale or ssh (got '$mode'): set it in .env in the main checkout (docs/runbooks/bootstrap.md)" ;;
  esac
}

# access_hint -> what to check when SSH to the VM fails, for the current access mode.
access_hint() {
  if [[ "${BM_ACCESS:-tailscale}" == ssh ]]; then
    printf 'check the ProxyCommand for %s in ~/.ssh/config and its login (docs/runbooks/gcp-vm.md)\n' "$BM_VM_HOST"
  else
    printf 'is %s reachable over Tailscale SSH? (ssh %s@%s true)\n' "$BM_VM_HOST" "$BM_VM_USER" "$BM_VM_HOST"
  fi
}
```

`remote()` 위 주석을 바꾼다.

```bash
# remote CMD -> run CMD on the VM over SSH: Tailscale SSH, or the ssh access mode's host alias.
```

- [ ] **Step 5: `scripts/access-check.sh` (새 파일, `chmod +x`)**

```bash
#!/usr/bin/env bash
# Report which access path works from the network this machine is on: the Tailscale control plane, the ssh mode's
# tunnel endpoint (BM_ACCESS_CHECK_URL) and, with BM_ACCESS=ssh, the SSH host alias. The recommendation covers this
# network only: run it on every network your clients use, then set BM_ACCESS (docs/runbooks/bootstrap.md).
# Exits 1 only when BM_ACCESS is set and that mode does not work here.
# Usage: access-check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly TAILSCALE_CONTROL_URL=https://controlplane.tailscale.com/
readonly ACCESS_CHECK_TIMEOUT_SECONDS=8
readonly CURL_EXIT_DNS=6
readonly CURL_EXIT_TIMEOUT=28

# url_state URL -> "reachable (HTTP <code>)" when any HTTP answer comes back (404 included: the network let the TLS
# connection through), otherwise "blocked (<reason>)".
url_state() {
  local code rc=0
  code="$(curl -sS -o /dev/null --max-time "$ACCESS_CHECK_TIMEOUT_SECONDS" -w '%{http_code}' "$1" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) printf 'reachable (HTTP %s)\n' "$code" ;;
    "$CURL_EXIT_DNS") printf 'blocked (dns)\n' ;;
    "$CURL_EXIT_TIMEOUT") printf 'blocked (timeout)\n' ;;
    *) printf 'blocked (curl exit %s)\n' "$rc" ;;
  esac
}

# recommendation TAILSCALE_OK TUNNEL_OK -> the mode to choose on this network (each argument is yes or no).
recommendation() {
  case "$1 $2" in
    "yes yes") echo "both work here; choose tailscale unless another network your clients use blocks it" ;;
    "no yes") echo "ssh" ;;
    "yes no") echo "tailscale" ;;
    *) echo "neither works here: ask the network admin" ;;
  esac
}

main() {
  local mode chosen="${BM_ACCESS:-}" state tailscale_ok=no tunnel_ok=no ssh_ok=no
  mode="$(access_mode)" || exit 1
  require_cmd curl
  log "this network only: run it on every network your clients use"

  state="$(url_state "$TAILSCALE_CONTROL_URL")"
  log "tailscale control plane: $state"
  if [[ "$state" == reachable* ]]; then
    tailscale_ok=yes
  fi

  if [[ -n "${BM_ACCESS_CHECK_URL:-}" ]]; then
    state="$(url_state "$BM_ACCESS_CHECK_URL")"
    log "tunnel endpoint $BM_ACCESS_CHECK_URL: $state"
    if [[ "$state" == reachable* ]]; then
      tunnel_ok=yes
    fi
  else
    log "tunnel endpoint: not set (BM_ACCESS_CHECK_URL in .env)"
  fi

  if [[ "$mode" == ssh ]]; then
    require_cmd ssh
    require_env BM_VM_HOST BM_VM_USER
    if remote true; then
      ssh_ok=yes
      log "ssh $BM_VM_USER@$BM_VM_HOST: ok"
    else
      log "ssh $BM_VM_USER@$BM_VM_HOST: failed: $(access_hint)"
    fi
  fi

  log "recommendation for this network: $(recommendation "$tailscale_ok" "$tunnel_ok")"
  case "$chosen" in
    tailscale) [[ "$tailscale_ok" == yes ]] || die "BM_ACCESS=tailscale does not work on this network" ;;
    ssh) [[ "$ssh_ok" == yes ]] || die "BM_ACCESS=ssh does not work on this network: $(access_hint)" ;;
  esac
}

main "$@"
```

- [ ] **Step 6: `.env.example`과 `Makefile`**

`.env.example` 맨 위 두 줄 다음에 `BM_ACCESS`를 넣고, `BM_VM_HOST`·`BM_TAILNET_DOMAIN` 주석을 바꾸고, 끝에 나머지를 넣는다.

```bash
# Access mode, one per VM: tailscale (tailnet + Serve) or ssh (SSH host alias + make tunnel). Empty means tailscale.
# Run make access-check on every network your clients use, then choose (docs/runbooks/bootstrap.md)
BM_ACCESS=

# tailscale mode: Tailscale machine name of the VM (MagicDNS short name); ssh mode: the Host alias in ~/.ssh/config
BM_VM_HOST=agent-hub
```

```bash
# tailscale mode only: your tailnet DNS name, e.g. tail1234.ts.net (admin console > DNS); no https:// and no trailing dot
BM_TAILNET_DOMAIN=
```

```bash
# make access-check: the ssh mode's tunnel endpoint (this one is GCP IAP's; docs/runbooks/gcp-vm.md, section 8)
BM_ACCESS_CHECK_URL=https://tunnel.cloudproxy.app/
# ssh mode: local ports make tunnel opens on 127.0.0.1 for MCP and the web UI
BM_TUNNEL_MCP_PORT=18737
BM_TUNNEL_WEB_PORT=13000
```

`Makefile`의 `export BM_VM_HOST …` 줄(계획 10이 `SB_USER SB_PORT`를 더한 줄) 끝에 `BM_ACCESS BM_ACCESS_CHECK_URL BM_TUNNEL_MCP_PORT BM_TUNNEL_WEB_PORT`를 더한다. `.PHONY`에 `access-check`를 더하고, `check-git` 타깃 앞에 넣는다.

```make
access-check: ## Report which access path (tailscale or ssh) works on this network; run it on every network you use
	scripts/access-check.sh
```

- [ ] **Step 7: 통과 확인**

Run: `make check`
Expected: exit 0. `access.bats` 두 테스트가 ok다. `repo.bats`의 ".PHONY와 ## 설명" 검사와 `cloud_neutral.bats`가 통과한다. 기존 `bootstrap.bats`의 tailscale 설치 테스트(curl 다운로드 모드)도 그대로 통과한다.

- [ ] **Step 8: 커밋과 push**

```bash
git add scripts/access-check.sh scripts/lib/common.sh tests/access.bats tests/stubs/curl .env.example Makefile
git commit -m "feat: add BM_ACCESS and make access-check" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 1"
git push
```

### Task 2: `make tunnel`

**Files:**
- Create: `scripts/tunnel.sh`(실행 권한)
- Modify: `scripts/lib/common.sh`(`forward_spec`), `tests/stubs/ssh`(`-N`), `tests/stubs/nc`(`NC_STUB_OPEN_MATCH`), `Makefile`(`tunnel` 타깃, `.PHONY`)
- Test: `tests/access.bats`

**Interfaces:**
- Consumes: Task 1의 `access_mode`, `access_hint`, `tests/access.bats`의 `setup`과 `$TUNNEL`
- Produces:
  - `forward_spec LOCAL_PORT REMOTE_PORT` → stdout `127.0.0.1:LOCAL:127.0.0.1:REMOTE`
  - ssh 스텁: 인자에 `-N`이 있으면 원격 명령을 실행하지 않는다. `SSH_STUB_TUNNEL_EXIT=<n>`이면 바로 n으로 끝나고, 없으면 pid를 `$STUB_LOG.tunnel-pids`에 적고 `exec sleep 300`.
  - nc 스텁: `NC_STUB_OPEN_MATCH=<부분 문자열>`이 인자에 있으면 0(열림).
  - `make tunnel`

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/access.bats` 끝에 추가)**

```bash
# --- tunnel ---

@test "tunnel forwards both ports on 127.0.0.1 only over the SSH alias and fails with the exit code when ssh ends" {
  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap SSH_STUB_TUNNEL_EXIT=255
  run "$TUNNEL"
  assert_failure
  assert_output --partial "MCP: http://127.0.0.1:18737/mcp  web UI: http://127.0.0.1:13000"
  assert_output --partial "tunnel closed (exit 255): rerun 'make tunnel'; check the ProxyCommand for agent-hub-iap"
  run grep -Fx 'ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:18737:127.0.0.1:8737 -L 127.0.0.1:13000:127.0.0.1:3000 ubuntu@agent-hub-iap' "$STUB_LOG"
  assert_success
}

@test "tunnel refuses the tailscale mode, a privileged port and a local port in use, before it runs ssh" {
  run "$TUNNEL"
  assert_failure
  assert_output --partial "make tunnel is for BM_ACCESS=ssh"

  export BM_ACCESS=ssh
  BM_TUNNEL_MCP_PORT=80 run "$TUNNEL"
  assert_failure
  assert_output --partial "BM_TUNNEL_MCP_PORT must be a port number from 1024 to 65535 (got '80')"

  NC_STUB_OPEN_MATCH=13000 run "$TUNNEL"
  assert_failure
  assert_output --partial "port 13000 is in use on 127.0.0.1: another 'make tunnel'? or set BM_TUNNEL_WEB_PORT in .env"

  run grep -F 'ssh -N' "$STUB_LOG"
  assert_failure
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 새 두 테스트가 `scripts/tunnel.sh: No such file or directory`로 실패한다.

- [ ] **Step 3: 스텁**

`tests/stubs/ssh`의 머리 주석 끝에 두 줄을 더한다.

```bash
# A tunnel (-N) runs no remote command: SSH_STUB_TUNNEL_EXIT=<n> ends it at once with n (forwarding failed);
# otherwise it records its pid in $STUB_LOG.tunnel-pids and stays up like an open tunnel until it is killed.
```

`printf 'ssh %s\n' "$*" >>"$STUB_LOG"` 바로 다음에 넣는다.

```bash
for arg in "$@"; do
  if [[ "$arg" == -N ]]; then
    if [[ -n "${SSH_STUB_TUNNEL_EXIT:-}" ]]; then
      exit "$SSH_STUB_TUNNEL_EXIT"
    fi
    echo "$$" >>"$STUB_LOG.tunnel-pids"
    exec sleep 300
  fi
done
```

`tests/stubs/nc` 전체:

```bash
#!/usr/bin/env bash
# Test stub for nc: exits NC_STUB_EXIT (default 1 = connection refused) and prints NC_STUB_STDERR to stderr.
# open: NC_STUB_EXIT=0; refused: default; timeout: NC_STUB_STDERR="nc: connect to ... port 22 (tcp) timed out";
# option error: NC_STUB_STDERR="nc: invalid option -- G" (or "usage: nc ...").
# NC_STUB_OPEN_MATCH=<substring>: calls whose arguments contain it exit 0 (open), e.g. 127.0.0.1 for a local
# tunnel while the public IP stays closed.
set -euo pipefail
printf 'nc %s\n' "$*" >>"$STUB_LOG"
if [[ -n "${NC_STUB_OPEN_MATCH:-}" && "$*" == *"$NC_STUB_OPEN_MATCH"* ]]; then
  exit 0
fi
if [[ -n "${NC_STUB_STDERR:-}" ]]; then
  printf '%s\n' "$NC_STUB_STDERR" >&2
fi
exit "${NC_STUB_EXIT:-1}"
```

- [ ] **Step 4: `forward_spec` (`scripts/lib/common.sh`, `access_hint` 다음)**

```bash
# forward_spec LOCAL_PORT REMOTE_PORT -> an ssh -L argument that binds LOCAL_PORT on 127.0.0.1 only and forwards it to
# REMOTE_PORT on the VM's loopback. Every -L goes through here, so no tunnel listens beyond this machine.
forward_spec() {
  printf '127.0.0.1:%s:127.0.0.1:%s\n' "$1" "$2"
}
```

- [ ] **Step 5: `scripts/tunnel.sh` (새 파일, `chmod +x`)**

```bash
#!/usr/bin/env bash
# ssh access mode: forward Basic Memory and the web UI on the VM to 127.0.0.1 on this machine over the SSH host alias,
# in the foreground (Ctrl-C stops it). It does not reconnect: when ssh ends, it fails with ssh's exit code; rerun it.
# Usage: tunnel.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly DEFAULT_TUNNEL_MCP_PORT=18737
readonly DEFAULT_TUNNEL_WEB_PORT=13000
readonly MIN_LOCAL_PORT=1024
readonly MAX_LOCAL_PORT=65535
readonly SERVER_ALIVE_INTERVAL_SECONDS=30
readonly SERVER_ALIVE_COUNT_MAX=3

# require_free_port NAME PORT -> dies unless PORT is an unprivileged port number that nothing on 127.0.0.1 listens on.
require_free_port() {
  local name="$1" port="$2"
  if ! [[ "$port" =~ ^[1-9][0-9]*$ ]] || ((port < MIN_LOCAL_PORT || port > MAX_LOCAL_PORT)); then
    die "$name must be a port number from $MIN_LOCAL_PORT to $MAX_LOCAL_PORT (got '$port')"
  fi
  if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    die "port $port is in use on 127.0.0.1: another 'make tunnel'? or set $name in .env"
  fi
}

main() {
  local mode status=0
  local mcp_port="${BM_TUNNEL_MCP_PORT:-$DEFAULT_TUNNEL_MCP_PORT}" web_port="${BM_TUNNEL_WEB_PORT:-$DEFAULT_TUNNEL_WEB_PORT}"
  local -a cmd
  mode="$(access_mode)" || exit 1
  [[ "$mode" == ssh ]] \
    || die "make tunnel is for BM_ACCESS=ssh; in tailscale mode clients use https://<host>.<tailnet>.ts.net/mcp (docs/runbooks/operations.md)"
  require_cmd ssh nc
  require_env BM_VM_HOST BM_VM_USER
  require_free_port BM_TUNNEL_MCP_PORT "$mcp_port"
  require_free_port BM_TUNNEL_WEB_PORT "$web_port"

  cmd=(ssh -N -o ExitOnForwardFailure=yes -o "ServerAliveInterval=$SERVER_ALIVE_INTERVAL_SECONDS"
    -o "ServerAliveCountMax=$SERVER_ALIVE_COUNT_MAX"
    -L "$(forward_spec "$mcp_port" "${BM_PORT:-8737}")" -L "$(forward_spec "$web_port" "${SB_PORT:-3000}")"
    "$BM_VM_USER@$BM_VM_HOST")
  log "running: ${cmd[*]}"
  log "MCP: http://127.0.0.1:$mcp_port/mcp  web UI: http://127.0.0.1:$web_port  (Ctrl-C stops the tunnel)"
  "${cmd[@]}" || status=$?
  die "tunnel closed (exit $status): rerun 'make tunnel'; $(access_hint)"
}

main "$@"
```

`BatchMode`를 쓰지 않는 이유: 첫 접속의 호스트 키 수락과 키 암호 입력을 사용자가 할 수 있어야 한다(스펙 §8.3).

- [ ] **Step 6: `Makefile`**

`.PHONY`에 `tunnel`을 더하고 `access-check` 다음에 넣는다.

```make
tunnel: ## ssh mode: forward MCP and the web UI to 127.0.0.1:BM_TUNNEL_MCP_PORT and BM_TUNNEL_WEB_PORT (Ctrl-C stops)
	scripts/tunnel.sh
```

- [ ] **Step 7: 통과 확인**

Run: `make check`
Expected: exit 0. `access.bats` 네 테스트가 ok다. `vm_ops.bats`의 공인 IP 검사 테스트(nc 스텁 기본값)도 그대로 통과한다.

- [ ] **Step 8: 커밋과 push**

```bash
git add scripts/tunnel.sh scripts/lib/common.sh tests/stubs/ssh tests/stubs/nc tests/access.bats Makefile
git commit -m "feat: add make tunnel for the ssh access mode" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 2"
git push
```

### Task 3: 모드별 부트스트랩

**Files:**
- Modify: `scripts/bootstrap-vm.sh`(`main`, 다음 단계 안내), `scripts/remote/bootstrap.sh`(상수, `main`), `Makefile`(`vm-bootstrap` 설명)
- Test: `tests/bootstrap.bats`

**Interfaces:**
- Consumes: Task 1의 `access_mode`
- Produces: 원격 환경의 첫 변수 `BM_ACCESS=<mode>`. 원격 스크립트는 `BM_ACCESS=ssh`일 때 `install_tailscale`·`join_tailnet`·`configure_serve`를 부르지 않고 `access mode ssh: skipping Tailscale`을 남긴다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/bootstrap.bats`, "fails when the Serve config has Funnel on" 다음)**

```bash
@test "ssh mode skips the Tailscale install, join and Serve but still sets up docker and the data dirs" {
  export BM_ACCESS=ssh
  run_bootstrap_with_key ""
  assert_success
  assert_output --partial "access mode ssh: skipping Tailscale"
  run grep -E '^tailscale |tailscale\.com/install\.sh' "$STUB_LOG"
  assert_failure
  run grep -F 'docker-ce' "$STUB_LOG"
  assert_success
  run stat -c '%u:%g' "$BM_REMOTE_DATA_ROOT/knowledge"
  assert_output "1000:1000"
}
```

"bootstrap-vm refuses an unexpected temp path from the VM" 다음에 넣는다.

```bash
@test "bootstrap-vm in ssh mode never asks for a key, passes the mode to the VM and points to make tunnel" {
  export BM_ACCESS=ssh BM_VM_USER=root
  unset TS_AUTHKEY
  run "$WRAPPER" agent-hub-iap </dev/null
  assert_success
  refute_output --partial "Tailscale auth key"
  refute_output --partial "delete the firewall rule that opens port 22"
  assert_output --partial "make tunnel, then connect the agents"
  run grep -F 'sudo BM_ACCESS=ssh ' "$STUB_LOG"
  assert_success
  run grep -E '^tailscale ' "$STUB_LOG"
  assert_failure
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 두 테스트가 실패한다. 첫째는 `tailscale` 호출이 남아서, 둘째는 키 프롬프트와 `BM_ACCESS` 없는 원격 환경 때문이다.

- [ ] **Step 3: `scripts/remote/bootstrap.sh`**

`readonly ADMIN_USER=…` 다음에 넣는다.

```bash
# tailscale (join the tailnet, Serve) or ssh (reached over an SSH host alias; Tailscale is not installed or touched).
readonly BM_ACCESS="${BM_ACCESS:-tailscale}"
```

`main`을 바꾼다.

```bash
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
```

- [ ] **Step 4: `scripts/bootstrap-vm.sh`**

머리 주석의 두 줄(첫 줄과 Usage 줄)을 바꾼다.

```bash
# First-time VM setup before the access path exists (public SSH), or over the SSH host alias in ssh mode. Safe to rerun.
# Usage: bootstrap-vm.sh HOST   (HOST: the public IP, or the SSH host alias in ssh mode; in tailscale mode the
#        Tailscale auth key comes from $TS_AUTHKEY or a hidden prompt)
```

`remove_remote_script` 다음에 넣는다.

```bash
# print_next_steps MODE USER -> what to do after a successful bootstrap.
print_next_steps() {
  log "Next steps:"
  if [[ "$1" == ssh ]]; then
    log "  1. make deploy verify status"
    log "  2. make tunnel, then connect the agents (docs/runbooks/operations.md)"
    return 0
  fi
  log "  1. ssh $2@$TS_HOSTNAME true    # must succeed over Tailscale SSH"
  log "  2. only then delete the firewall rule that opens port 22 (docs/runbooks/bootstrap.md)"
  log "  3. make deploy verify status"
}
```

`main`을 바꾼다. 바뀌는 곳은 키 읽기, 두 `upload failed` 안내, 단계 이름, `remote_env` 첫머리, 끝의 안내다. 나머지는 계획 11 뒤의 모양 그대로다.

```bash
main() {
  local remote_script host="${1:-}" user="${BM_VM_USER:-ubuntu}" key="" remote_env mode upload_hint
  [[ -n "$host" ]] || die "usage: make vm-bootstrap HOST=<public-ip, or the SSH host alias in ssh mode>"
  mode="$(access_mode)" || exit 1
  require_cmd ssh
  if [[ "$mode" == tailscale ]]; then
    key="$(read_auth_key)" || exit 1
    if [[ -n "$key" ]]; then
      log "using auth key $(mask "$key")"
    fi
    upload_hint="check the public IP, your SSH key, and that a firewall rule allows port 22 from your IP (docs/runbooks/gcp-vm.md)"
  else
    upload_hint="check the ProxyCommand for $host in ~/.ssh/config, its login and the firewall rule for the tunnel range (docs/runbooks/gcp-vm.md)"
  fi

  step "upload bootstrap script to $user@$host"
  # mktemp gives an unpredictable path and mode 0600, so no other VM user can swap the file root runs.
  remote_script="$(ssh_public "$user@$host" "mktemp $REMOTE_SCRIPT_TEMPLATE")" || die "upload failed: $upload_hint"
  # The path is spliced into later remote commands, so accept only what mktemp should print.
  [[ "$remote_script" =~ ^/tmp/bm-bootstrap\.[A-Za-z0-9]{6}$ ]] \
    || die "unexpected temp path from mktemp on the VM: '$remote_script'"
  ssh_public "$user@$host" "cat > $remote_script" <"$SCRIPT_DIR/remote/bootstrap.sh" \
    || {
      remove_remote_script "$user@$host" "$remote_script"
      die "upload failed: $upload_hint"
    }

  step "run bootstrap on the VM (access: $mode)"
  remote_env="BM_ACCESS=$mode BM_PORT=${BM_PORT:-8737} SB_PORT=${SB_PORT:-3000} BM_REMOTE_DATA_ROOT=$BM_REMOTE_DATA_ROOT BM_REMOTE_APP_DIR=$BM_REMOTE_APP_DIR"
  remote_env="$remote_env ADMIN_USER=$user TS_HOSTNAME=$TS_HOSTNAME"
  printf '%s\n' "$key" | ssh_public "$user@$host" "sudo $remote_env bash $remote_script" \
    || {
      remove_remote_script "$user@$host" "$remote_script"
      die "bootstrap failed on the VM: rerun 'make vm-bootstrap HOST=$host' (it is safe to repeat)"
    }
  remove_remote_script "$user@$host" "$remote_script"
  print_next_steps "$mode" "$user"
}
```

`ssh` 모드에서는 `key`가 비어 있으므로 빈 줄 하나만 보낸다.

`Makefile`의 `vm-bootstrap` 설명을 바꾼다.

```make
vm-bootstrap: ## First-time VM setup (HOST=<public-ip>, or the SSH host alias in ssh mode; tailscale mode asks for an auth key)
```

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected: exit 0. 새 두 테스트와 기존 `bootstrap.bats` 전체가 ok다(기존 테스트는 `BM_ACCESS`가 없어 `tailscale` 모드로 돈다).

- [ ] **Step 6: 커밋과 push**

```bash
git add scripts/bootstrap-vm.sh scripts/remote/bootstrap.sh tests/bootstrap.bats Makefile
git commit -m "feat: bootstrap the VM without Tailscale in the ssh access mode" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 3"
git push
```

### Task 4: `verify`·`probe`의 `ssh` 모드

**Files:**
- Create: `tests/stubs/sshd`(실행 권한)
- Modify: `scripts/lib/common.sh`(`SSH_FAILURE_EXIT`, `vm_tailscale_logged_in`), `scripts/verify-vm.sh`(머리 주석, 상수, 새 함수, `main`)
- Test: `tests/vm_ops.bats`(setup의 스텁 목록, 헬퍼, 새 테스트)

**Interfaces:**
- Consumes: Task 1의 `access_mode`·`access_hint`, Task 2의 `forward_spec`·ssh 스텁 `-N`·nc 스텁 `NC_STUB_OPEN_MATCH`, 계획 11의 `check_serve`·`check_public_closed`·`check_loopback_binding`·`validate_public_ip`·`SB_HTTPS_PORT`, 계획 10의 `verify-sb.sh`
- Produces:
  - `common.sh`: `readonly SSH_FAILURE_EXIT=255`, `vm_tailscale_logged_in` → 0(로그인), 1(없음·로그아웃·정지), VM에 닿지 못하면 `die`
  - `verify-vm.sh`: `open_verify_tunnel BM_PORT SB_PORT`, `close_verify_tunnel`, `check_tailscale_off`, `check_sshd_auth`
  - sshd 스텁: `sshd -T`가 `passwordauthentication ${SSHD_STUB_PASSWORD:-no}`, `kbdinteractiveauthentication no`를 출력
  - `tests/vm_ops.bats`의 `use_ssh_mode` 헬퍼(Task 5도 쓴다)

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/vm_ops.bats`)**

`setup`의 `setup_stubs` 목록 끝에 `sshd`를 더한다. `# --- deploy ---` 앞에 헬퍼를 넣는다.

```bash
# use_ssh_mode: the ssh access mode over an SSH alias, with the verify tunnel opening at once and Tailscale on the VM
# logged out.
use_ssh_mode() {
  export BM_ACCESS=ssh BM_VM_HOST=agent-hub-iap NC_STUB_OPEN_MATCH=127.0.0.1 TS_STUB_STATUS_EXIT=1
  unset BM_TAILNET_DOMAIN
}
```

"probe runs every check without writing notes, logging in or needing SB_USER" 다음에 넣는다.

```bash
@test "ssh mode: probe checks through a verify tunnel on 127.0.0.1 and leaves no tunnel behind" {
  use_ssh_mode
  run "$REPO_DIR/scripts/verify-vm.sh" --read-only
  assert_success
  assert_output --partial "OK: MCP read-only probe passed"
  assert_output --partial "OK: Tailscale does not expose the VM"
  assert_output --partial "OK: sshd accepts keys only"
  assert_output --partial "public IP 203.0.113.10 refuses ports 22 80 443 8443 8737 3000"
  assert_output --partial "OK: automated VM checks passed (access: ssh)"
  run grep -Fx 'ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ConnectTimeout=10 -L 127.0.0.1:28737:127.0.0.1:8737 -L 127.0.0.1:23000:127.0.0.1:3000 ubuntu@agent-hub-iap' "$STUB_LOG"
  assert_success
  run grep -F 'tailscale serve' "$STUB_LOG"
  assert_failure
  run kill -0 "$(cat "$STUB_LOG.tunnel-pids")"
  assert_failure
}

@test "ssh mode: verify closes its tunnel even when a check fails" {
  use_ssh_mode
  export CURL_STUB_EXIT=7
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  run kill -0 "$(cat "$STUB_LOG.tunnel-pids")"
  assert_failure
}

@test "ssh mode: verify fails while Tailscale is logged in on the VM, sshd takes passwords or the tunnel does not open" {
  use_ssh_mode
  local case
  # The failed tunnel also leaves the local port closed, or nc could report it open before the stub exits.
  for case in "TS_STUB_STATUS_EXIT=0" "SSHD_STUB_PASSWORD=yes" "SSH_STUB_TUNNEL_EXIT=255 NC_STUB_OPEN_MATCH="; do
    run env $case "$REPO_DIR/scripts/verify-vm.sh" --read-only
    [[ "$status" -ne 0 ]] || fail "expected a failure with $case; got: $output"
  done
}

@test "verify rejects a BM_ACCESS it does not know, also in another case, before it contacts the VM" {
  export BM_ACCESS=SSH
  run "$REPO_DIR/scripts/verify-vm.sh"
  assert_failure
  assert_output --partial "BM_ACCESS must be tailscale or ssh (got 'SSH')"
  run grep -F 'ssh ' "$STUB_LOG"
  assert_failure
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 새 네 테스트가 실패한다(sshd 스텁 없음, `ssh` 모드 분기 없음, `BM_ACCESS` 검사 없음). 기존 테스트는 PASS.

- [ ] **Step 3: `tests/stubs/sshd` (새 파일, `chmod +x`)**

```bash
#!/usr/bin/env bash
# Test stub for sshd: `sshd -T` prints the effective auth settings. SSHD_STUB_PASSWORD=yes turns password logins on.
set -euo pipefail
printf 'sshd %s\n' "$*" >>"$STUB_LOG"
printf 'passwordauthentication %s\n' "${SSHD_STUB_PASSWORD:-no}"
printf 'kbdinteractiveauthentication no\n'
printf 'permitrootlogin without-password\n'
```

- [ ] **Step 4: `scripts/lib/common.sh`**

상수 블록의 `SSH_CONNECT_TIMEOUT_SECONDS` 다음에 넣는다.

```bash
# Exit code ssh uses for its own failures (connection, authentication), as opposed to the remote command's.
readonly SSH_FAILURE_EXIT=255
```

`remote_compose` 다음에 넣는다.

```bash
# vm_tailscale_logged_in -> exit 0 when Tailscale on the VM is logged in, 1 when it is missing, logged out or
# stopped. Dies when the VM cannot be reached. The ssh access mode expects 1 (one access path per VM).
vm_tailscale_logged_in() {
  local rc=0
  remote "command -v tailscale >/dev/null 2>&1 && sudo -n tailscale status >/dev/null 2>&1" || rc=$?
  ((rc != SSH_FAILURE_EXIT)) || die "could not check Tailscale on $BM_VM_HOST: $(access_hint)"
  ((rc == 0))
}
```

- [ ] **Step 5: `scripts/verify-vm.sh`**

머리 주석의 `# Usage:` 줄 앞에 넣는다.

```bash
# In the ssh access mode it runs the same checks through a temporary SSH tunnel on 127.0.0.1 and, instead of Serve,
# checks that Tailscale does not expose the VM and that sshd accepts keys only.
```

상수 블록(`readonly PUBLIC_PROBE_PORTS=…` 다음)에 넣는다.

```bash
# ssh access mode: local ends of the verify tunnel, apart from make tunnel's 18737/13000 so both can run at once.
readonly VERIFY_TUNNEL_MCP_PORT=28737
readonly VERIFY_TUNNEL_WEB_PORT=23000
readonly TUNNEL_READY_TIMEOUT_SECONDS=20

# Global so the EXIT trap can still see it.
tunnel_pid=""
```

`check_serve` 다음에 넣는다.

```bash
close_verify_tunnel() {
  if [[ -n "$tunnel_pid" ]]; then
    kill "$tunnel_pid" 2>/dev/null || true
    wait "$tunnel_pid" 2>/dev/null || true
  fi
}

# open_verify_tunnel BM_PORT SB_PORT -> forwards VERIFY_TUNNEL_MCP_PORT and VERIFY_TUNNEL_WEB_PORT on 127.0.0.1 to the
# VM's loopback ports over the SSH alias, in the background until this script exits.
open_verify_tunnel() {
  local waited=0
  step "open a verify tunnel to $BM_VM_USER@$BM_VM_HOST on 127.0.0.1:$VERIFY_TUNNEL_MCP_PORT and :$VERIFY_TUNNEL_WEB_PORT"
  ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" \
    -L "$(forward_spec "$VERIFY_TUNNEL_MCP_PORT" "$1")" -L "$(forward_spec "$VERIFY_TUNNEL_WEB_PORT" "$2")" \
    "$BM_VM_USER@$BM_VM_HOST" &
  tunnel_pid=$!
  trap close_verify_tunnel EXIT
  while ((waited < TUNNEL_READY_TIMEOUT_SECONDS)); do
    kill -0 "$tunnel_pid" 2>/dev/null \
      || die "verify tunnel exited before it opened (is port $VERIFY_TUNNEL_MCP_PORT or $VERIFY_TUNNEL_WEB_PORT in use?): $(access_hint)"
    if nc -z 127.0.0.1 "$VERIFY_TUNNEL_MCP_PORT" >/dev/null 2>&1; then
      log "verify tunnel is open"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  die "verify tunnel did not open within ${TUNNEL_READY_TIMEOUT_SECONDS}s: $(access_hint)"
}

check_tailscale_off() {
  step "check Tailscale does not expose the VM (BM_ACCESS=ssh)"
  if vm_tailscale_logged_in; then
    die "Tailscale is logged in on the VM but BM_ACCESS=ssh: log it out (docs/runbooks/operations.md, Access mode change)"
  fi
  log "OK: Tailscale does not expose the VM (missing, logged out or stopped)"
}

check_sshd_auth() {
  local config
  step "check sshd accepts keys only (BM_ACCESS=ssh)"
  config="$(remote "sudo -n sshd -T")" || die "could not read the sshd config on $BM_VM_HOST: $(access_hint)"
  grep -qx 'passwordauthentication no' <<<"$config" \
    || die "sshd on the VM accepts passwords: set PasswordAuthentication no (docs/runbooks/gcp-vm.md, section 8)"
  grep -qx 'kbdinteractiveauthentication no' <<<"$config" \
    || die "sshd on the VM accepts keyboard-interactive logins: set KbdInteractiveAuthentication no (docs/runbooks/gcp-vm.md, section 8)"
  log "OK: sshd accepts keys only"
}
```

`main`(계획 11 Task 1의 모양)을 바꾼다.

```bash
main() {
  local port="${BM_PORT:-8737}" sb_port="${SB_PORT:-3000}" mode url sb_url
  case "${1:-}" in
    "" | --read-only) ;;
    *) die "usage: verify-vm.sh [--read-only]" ;;
  esac
  mode="$(access_mode)" || exit 1
  require_cmd ssh curl jq nc
  require_env BM_VM_HOST BM_VM_USER BM_VM_PUBLIC_IP
  validate_public_ip "$BM_VM_PUBLIC_IP"
  if [[ "$mode" == ssh ]]; then
    open_verify_tunnel "$port" "$sb_port"
    url="http://127.0.0.1:$VERIFY_TUNNEL_MCP_PORT/mcp"
    sb_url="http://127.0.0.1:$VERIFY_TUNNEL_WEB_PORT"
  else
    require_env BM_TAILNET_DOMAIN
    [[ "$BM_TAILNET_DOMAIN" =~ ^[a-z0-9-]+\.ts\.net$ ]] \
      || die "BM_TAILNET_DOMAIN must look like tail1234.ts.net (no https://, no trailing dot): '$BM_TAILNET_DOMAIN'"
    url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}/mcp"
    sb_url="https://${BM_VM_HOST}.${BM_TAILNET_DOMAIN}:$SB_HTTPS_PORT"
  fi

  if [[ "${1:-}" == --read-only ]]; then
    "$SCRIPT_DIR/verify-mcp.sh" --read-only "$url"
    "$SCRIPT_DIR/verify-sb.sh" --read-only "$sb_url"
  else
    "$SCRIPT_DIR/verify-mcp.sh" "$url"
    "$SCRIPT_DIR/verify-sb.sh" "$sb_url"
  fi
  check_loopback_binding "$port"
  check_loopback_binding "$sb_port"
  if [[ "$mode" == ssh ]]; then
    check_tailscale_off
    check_sshd_auth
  else
    check_serve "$port" "$sb_port"
  fi
  check_public_closed "$port" "$sb_port"
  if [[ "$mode" == ssh ]]; then
    log "OK: automated VM checks passed (access: ssh); audit firewall rules by hand (docs/runbooks/operations.md, Exposure audit)"
  else
    log "OK: automated VM checks passed; audit firewall rules and the tailnet policy by hand (docs/runbooks/operations.md, Exposure audit)"
  fi
}
```

`tailscale` 모드의 출력 문구와 순서는 계획 11과 같다. `require_env BM_TAILNET_DOMAIN`만 `tailscale` 분기로 옮겼다.

- [ ] **Step 6: 통과 확인**

Run: `make check`
Expected: exit 0. 새 네 테스트와 기존 `vm_ops.bats` 전체가 ok다. `restore` 뒤의 `verify-vm.sh` 호출(`backup_restore.bats`)도 PASS.

- [ ] **Step 7: 커밋과 push**

```bash
git add scripts/verify-vm.sh scripts/lib/common.sh tests/stubs/sshd tests/vm_ops.bats
git commit -m "feat: verify the VM through a temporary SSH tunnel in the ssh access mode" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 4"
git push
```

### Task 5: `status`와 원격 실패 안내

**Files:**
- Modify: `scripts/status.sh`(전체), `scripts/deploy.sh`·`scripts/restore.sh`(시작 절에서 찾은 `over Tailscale SSH` 안내 줄), `Makefile`(`status` 설명)
- Test: `tests/vm_ops.bats`

**Interfaces:**
- Consumes: `access_mode`, `access_hint`, `vm_tailscale_logged_in`, Task 4의 `use_ssh_mode`
- Produces: `ssh` 모드 `status`의 `==> access: ssh`, `tailscale: not installed or logged out` 또는 `WARNING: Tailscale is still logged in on the VM; …`

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/vm_ops.bats`, "status warns to rerun vm-bootstrap when no swap is active" 다음)**

```bash
@test "ssh mode: status shows the access mode instead of Serve and warns while Tailscale is logged in on the VM" {
  use_ssh_mode
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "access: ssh"
  assert_output --partial "tailscale: not installed or logged out"
  refute_output --partial "proxy http://127.0.0.1:8737"
  export TS_STUB_STATUS_EXIT=0
  run "$REPO_DIR/scripts/status.sh"
  assert_success
  assert_output --partial "WARNING: Tailscale is still logged in on the VM; BM_ACCESS=ssh expects it off"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 새 테스트만 실패한다(`access: ssh` 없음, Serve 출력이 나옴).

- [ ] **Step 3: `scripts/status.sh` (전체)**

```bash
#!/usr/bin/env bash
# Show VM container state, memory and swap use, and how the VM is reached: tailscale serve config, or in the ssh
# access mode whether Tailscale is still logged in on the VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# memory_swap_summary -> "<memory used %> <swap used MB> <swap total MB>" from one `free -m` run on the VM.
# Memory used is total minus available. Exits 1 when free prints no Mem: or no Swap: line, or a zero memory total.
memory_swap_summary() {
  remote "free -m" | awk '/^Mem:/ { if ($2 > 0) mem = int(($2 - $7) * 100 / $2) } /^Swap:/ { swap_total = $2; swap_used = $3 } END { if (mem == "" || swap_total == "") exit 1; printf "%d %d %d\n", mem, swap_used, swap_total }'
}

# show_access MODE -> the Serve config (tailscale), or whether Tailscale is still logged in on the VM (ssh).
show_access() {
  if [[ "$1" == ssh ]]; then
    step "access: ssh"
    if vm_tailscale_logged_in; then
      log "WARNING: Tailscale is still logged in on the VM; BM_ACCESS=ssh expects it off (docs/runbooks/operations.md, Access mode change)"
    else
      log "tailscale: not installed or logged out"
    fi
    return 0
  fi
  step "tailscale serve"
  remote "sudo -n tailscale serve status" \
    || die "tailscale serve is not configured: rerun 'make vm-bootstrap HOST=<public-ip>' (docs/runbooks/bootstrap.md)"
}

main() {
  local summary used swap_used swap_total mode
  mode="$(access_mode)" || exit 1
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER

  step "containers"
  remote_compose "ps" || die "could not query containers on $BM_VM_HOST: $(access_hint)"

  step "memory and swap"
  summary="$(memory_swap_summary)" || die "could not read memory usage on $BM_VM_HOST (try: ssh $BM_VM_USER@$BM_VM_HOST free -m)"
  read -r used swap_used swap_total <<<"$summary"
  log "memory used: ${used}%"
  log "swap used: ${swap_used}/${swap_total} MB"
  if ((swap_total == 0)); then
    log "WARNING: no active swap on this 1GB VM; it can run out of memory: rerun 'make vm-bootstrap' (docs/runbooks/bootstrap.md)"
  fi

  show_access "$mode"
}

main "$@"
```

- [ ] **Step 4: `deploy.sh`·`restore.sh`의 안내**

시작 절의 `grep -n 'over Tailscale SSH' …`이 보인 두 파일의 줄에서 `is $BM_VM_HOST reachable over Tailscale SSH? (ssh $BM_VM_USER@$BM_VM_HOST true)`와 `is it reachable over Tailscale SSH? (ssh $BM_VM_USER@$BM_VM_HOST true)`를 `$(access_hint)`로 바꾼다. 결과 모양:

```bash
    || die "upload failed: $(access_hint)"
```

```bash
    || die "could not reach $BM_VM_HOST: $(access_hint)"
```

`Makefile`의 `status` 설명을 바꾼다.

```make
status: ## Show VM containers, memory and swap use, and tailscale serve (ssh mode: whether Tailscale is off)
```

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected: exit 0. 새 테스트와 기존 `status`·`deploy`·`restore` 테스트가 ok다.

Run: `grep -rn 'over Tailscale SSH' scripts`
Expected: `scripts/lib/common.sh`의 `access_hint` 한 줄만 나온다.

- [ ] **Step 6: 커밋과 push**

```bash
git add scripts/status.sh scripts/deploy.sh scripts/restore.sh tests/vm_ops.bats Makefile
git commit -m "feat: show the access mode in make status and point SSH failures to it" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 5"
git push
```

### Task 6: 런북, ARCHITECTURE, README, ADR 0006

**Files:**
- Create: `docs/decisions/0006-access-modes.md`
- Modify: `docs/runbooks/gcp-vm.md`, `docs/runbooks/bootstrap.md`, `docs/runbooks/accounts.md`, `docs/runbooks/operations.md`, `docs/ARCHITECTURE.md`, `README.md`, `docs/specs/2026-10-12-basic-memory-gcp-tailscale-design.md`(상태 줄)

**Interfaces:**
- Consumes: Task 1~5의 타깃 이름과 출력 문구(`recommendation for this network`, `MCP: http://127.0.0.1:18737/mcp`, `OK: Tailscale does not expose the VM`, `OK: sshd accepts keys only`, `Access mode change`)
- Produces: 스크립트 메시지가 가리키는 절. `docs/runbooks/gcp-vm.md`의 "8. IAP로 접속하기", `docs/runbooks/operations.md`의 "접속 방식 바꾸기 (Access mode change)"

- [ ] **Step 1: `docs/decisions/0006-access-modes.md` (새 파일)**

```markdown
# ADR 0006: VM마다 접속 방식 하나 (Tailscale 또는 SSH 터널)

- 상태: Accepted (계획 12 병합일)
- 설계: [접속 방식 설계](../specs/2026-10-15-access-modes-design.md)

## 맥락

- 사무실 네트워크는 HTTPS `controlplane.tailscale.com`을 막아 Tailscale로 VM에 닿을 수 없습니다. GCP IAP의 터널 엔드포인트(`tunnel.cloudproxy.app`)는 열려 있습니다(설계 §3, 2026-10-14~15 측정).
- 다른 사람도 이 저장소를 쓸 수 있어야 하므로, 한 사람의 네트워크 사정에 맞춘 예외 대신 설치할 때 고르는 구조가 필요합니다.
- 컨테이너는 VM의 `127.0.0.1`에만 열려 있고, IAP는 VM의 내부 IP로만 접속합니다. 그래서 IAP로는 sshd(22)를 거쳐 SSH 로컬 포워딩으로 들어가야 합니다.

## 결정

1. `.env`의 `BM_ACCESS`로 VM마다 접속 방식 하나를 고릅니다: `tailscale`(지금 구조) 또는 `ssh`(SSH 호스트 별칭과 `make tunnel`). 비어 있으면 `tailscale`입니다.
2. `make access-check`는 지금 네트워크에서 각 경로가 되는지 보고하고 추천만 합니다. 모드는 사람이 정합니다. 설치하는 기기는 지금 네트워크 하나만 보기 때문입니다.
3. 스크립트는 `ssh` 모드에서 SSH 별칭만 압니다. GCP에서 그 별칭을 IAP로 만드는 방법은 [VM 런북](../runbooks/gcp-vm.md) 8단계에 있습니다. 스크립트에는 클라우드 이름이 들어가지 않습니다.
4. `make tunnel`은 앞단에서 돌고, 끊기면 다시 붙지 않고 실패합니다. 로컬 포트는 18737(MCP)·13000(웹 UI)이고 `127.0.0.1`에만 바인딩합니다.
5. `ssh` 모드의 `verify`는 VM의 Tailscale이 로그인 상태가 아닌지와 sshd가 키 전용인지 검사합니다.
6. 지금 VM은 계획 13에서 `ssh` 모드로 옮깁니다.

## 결과

- `ssh` 모드에서 VPC 밖 인바운드는 IAP 대역(`35.235.240.0/20`)의 22번 하나입니다. 인증은 Google 계정 IAM과 SSH 키 두 겹이고, 새 비밀값은 없습니다.
- `ssh` 모드에서는 MCP를 쓰는 동안 각 기기가 `make tunnel`을 띄워 둬야 합니다. IAP는 한 시간 동안 활동이 없으면 연결을 끊습니다.
- Windows는 WSL2에서 Make 타깃을, PowerShell에서 터널 명령 한 줄을 씁니다. 검증하지 않았습니다(Assumption).
- 계획 13의 확인 결과(IAP API 필요 여부, 무활동 끊김, 백업 시간)는 이 ADR의 "이전 결과" 절에 적습니다.

## 이전 결과

계획 13에서 채웁니다.
```

- [ ] **Step 2: `docs/runbooks/gcp-vm.md`**

3단계 첫 문단 다음에 넣는다.

```markdown
접속 방식에 따라 22번 규칙이 다릅니다(`.env`의 `BM_ACCESS`, [부트스트랩 런북](bootstrap.md)).

- `tailscale`: 아래처럼 `default-allow-ssh`를 내 IP/32로 좁혀 부트스트랩에 쓰고, Tailscale SSH를 확인한 뒤 지웁니다.
- `ssh`: 공인 SSH가 필요 없습니다. rdp·icmp와 함께 `default-allow-ssh`도 지우고, 8단계의 `allow-iap-ssh`를 만듭니다.
```

파일 끝에 새 절을 넣는다.

````markdown
## 8. IAP로 접속하기 (`BM_ACCESS=ssh`)

IAP TCP 포워딩은 Google 계정 인증을 거쳐 VM의 22번으로 터널을 엽니다. VM에 외부 IP가 없어도 되고, 컨테이너는 `127.0.0.1`에만 있으므로 SSH 로컬 포워딩(`make tunnel`)으로 들어갑니다(**Verified**, docs.cloud.google.com/iap/docs/using-tcp-forwarding, 2026-10-15).

1. 방화벽 규칙(사용자 OK 후). IAP가 쓰는 대역에서 22번만 엽니다.

   ```bash
   gcloud compute firewall-rules create allow-iap-ssh --configuration=bm-personal --network=default --direction=INGRESS --allow=tcp:22 --source-ranges=35.235.240.0/20
   ```

2. 권한. 프로젝트 소유자는 이미 가집니다. 다른 사람에게는 [accounts 7단계](accounts.md)를 따릅니다.
3. `~/.ssh/config` (macOS·Linux·WSL). `HostName`은 인스턴스 이름입니다.

   ```
   Host agent-hub-iap
     HostName agent-hub-01
     User ubuntu
     ProxyCommand gcloud --configuration=bm-personal compute start-iap-tunnel %h 22 --listen-on-stdin --zone=us-west1-b --verbosity=warning
   ```

   Windows(PowerShell, OpenSSH)는 `%USERPROFILE%\.ssh\config`에 같은 블록을 넣고 `ProxyCommand`의 `gcloud`를 `gcloud.cmd`로 바꿉니다(**Assumption**, 검증하지 않음).
4. 첫 접속은 대화형으로 해서 호스트 키를 수락합니다: `ssh ubuntu@agent-hub-iap true`. 그다음 `.env`에 `BM_ACCESS=ssh`, `BM_VM_HOST=agent-hub-iap`를 넣고 `make access-check`가 `ssh ubuntu@agent-hub-iap: ok`를 출력하는지 봅니다.
5. 터널이 API나 권한 오류로 열리지 않으면 IAP API를 켭니다(사용자 OK 후). 켜야 하는지는 **Open question**이고, 계획 13에서 확인합니다.

   ```bash
   gcloud services enable iap.googleapis.com --configuration=bm-personal
   ```

6. sshd는 키 전용이어야 합니다. `make verify`가 `sshd -T`로 `passwordauthentication no`와 `kbdinteractiveauthentication no`를 확인합니다. 실패하면 `/etc/ssh/sshd_config.d/`에 두 설정을 `no`로 둔 파일을 만들고 `sudo systemctl reload ssh`를 실행합니다(사용자 OK 후).
7. 로그인이 만료되면 `ProxyCommand`가 실패하고 스크립트는 `check the ProxyCommand for agent-hub-iap in ~/.ssh/config and its login`을 출력합니다. `gcloud auth login --configuration=bm-personal`로 다시 로그인합니다.

IAP 터널은 대량 전송용이 아니고, 한 시간 동안 활동이 없으면 끊깁니다. `make tunnel`은 30초마다 keepalive를 보내고, 끊기면 종료하므로 다시 실행합니다.
````

- [ ] **Step 3: `docs/runbooks/bootstrap.md`**

제목 아래 첫 문단 다음에 넣는다.

```markdown
접속 방식(`.env`의 `BM_ACCESS`)을 먼저 정합니다. 클라이언트가 쓸 네트워크(사무실, 집 등)마다 `make access-check`를 실행하고, 어느 한 곳이라도 Tailscale이 막히고 터널 엔드포인트가 열리면 `ssh`, 모두 Tailscale이 되면 `tailscale`(비워 두어도 같음)을 고릅니다. 아래 "순서"와 "완료 조건"은 `tailscale` 모드이고, `ssh` 모드는 "ssh 모드 순서"를 따릅니다.
```

"## 완료 조건" 앞에 새 절을 넣는다.

```markdown
## ssh 모드 순서

1. [VM 런북](gcp-vm.md) 3단계와 8단계: `default-allow-ssh`를 지우고 `allow-iap-ssh`를 만들고, `~/.ssh/config`에 `agent-hub-iap`를 넣고, 대화형 `ssh ubuntu@agent-hub-iap true`로 호스트 키를 수락합니다.
2. `.env`: `BM_ACCESS=ssh`, `BM_VM_HOST=agent-hub-iap`. `BM_TAILNET_DOMAIN`은 필요 없습니다. `make access-check`가 `ssh ubuntu@agent-hub-iap: ok`를 출력해야 합니다.
3. `make vm-bootstrap HOST=agent-hub-iap` → 인증 키를 묻지 않고 스왑·Docker·데이터 디렉터리만 준비합니다(`access mode ssh: skipping Tailscale`).
4. `make deploy sb-fonts verify status`
5. 다른 터미널에서 `make tunnel`을 띄우고 [운영 런북](operations.md)의 "에이전트 연결"대로 클라이언트를 등록합니다.

완료 조건(ssh 모드):

- [ ] `make verify`가 `OK: MCP round trip passed`, `OK: SilverBullet checks passed`, `OK: Tailscale does not expose the VM`, `OK: sshd accepts keys only`, `refuses ports 22 80 443 8443 8737 3000`, `(access: ssh)`를 출력한다.
- [ ] Exposure audit(수동)에서 VPC 밖 소스를 허용하는 규칙이 `allow-iap-ssh` 하나뿐이다.
- [ ] `make status`에 두 컨테이너의 `(healthy)`와 `access: ssh`, `tailscale: not installed or logged out`이 보인다.
- [ ] `make backup`이 성공한다.
```

"## 문제 해결" 표 끝에 행을 넣는다.

```markdown
| `BM_ACCESS must be tailscale or ssh` | `.env`의 `BM_ACCESS`를 소문자 `tailscale`이나 `ssh`로 고치거나 비웁니다 |
| `ssh` 모드에서 `upload failed: check the ProxyCommand ...` | [VM 런북](gcp-vm.md) 8단계: `allow-iap-ssh` 규칙, `~/.ssh/config`의 별칭, `gcloud` 로그인 |
| `Tailscale is logged in on the VM but BM_ACCESS=ssh` | 모드를 바꾸는 중이면 [운영 런북](operations.md)의 "접속 방식 바꾸기" 5단계를 마칩니다 |
```

- [ ] **Step 4: `docs/runbooks/accounts.md`**

제목 아래에 넣는다.

```markdown
2~5단계(Tailscale)는 `BM_ACCESS=tailscale`일 때만 합니다. `BM_ACCESS=ssh`는 Tailscale 계정이 필요 없고, 7단계의 IAP 권한을 씁니다.
```

6단계 다음에 새 절을 넣는다.

```markdown
## 7. IAP 터널 권한 (`BM_ACCESS=ssh`)

프로젝트 소유자는 IAP 터널 권한을 이미 가집니다. 다른 사람이 같은 VM에 붙어야 하면 그 Google 계정에 `roles/iap.tunnelResourceAccessor`를 주고, 그 사람의 공개키를 인스턴스 메타데이터 `ssh-keys`에 더합니다(둘 다 클라우드 변경이므로 사용자 OK 후). 최소 권한 조합은 **Open question**입니다. 터널 설정은 [VM 런북](gcp-vm.md) 8단계에 있습니다.
```

- [ ] **Step 5: `docs/runbooks/operations.md`**

"일상 명령" 표의 첫 행 다음에 두 행을 넣는다.

```markdown
| 지금 네트워크에서 되는 접속 경로 | `make access-check` |
| `ssh` 모드에서 MCP·웹 UI 터널 (작업하는 동안 띄워 둠) | `make tunnel` |
```

표 아래 "OK 없이 실행할 수 있습니다" 문장의 목록에 `access-check`, `tunnel`을 더한다.

"## 웹 UI (SilverBullet)" 절 다음에 두 절을 넣는다.

````markdown
## 에이전트 연결

Claude Code와 Codex는 각 기기에서 `basic-memory`라는 이름으로 한 번 등록합니다. URL은 접속 방식에 따라 다릅니다.

| `BM_ACCESS` | URL | 미리 할 일 |
|---|---|---|
| `tailscale` | `https://agent-hub.<tailnet>.ts.net/mcp` | 이 기기가 tailnet에 연결돼 있어야 함 |
| `ssh` | `http://127.0.0.1:18737/mcp` | `make tunnel`을 띄워 둠 |

```bash
claude mcp add --transport http -s user basic-memory <URL>
codex mcp add basic-memory --url <URL>
```

- `ssh` 모드에서는 `localhost`가 아니라 `127.0.0.1`을 씁니다. 터널은 IPv4 `127.0.0.1`에만 열리는데, `localhost`가 IPv6 `::1`로 풀리면 연결이 거부됩니다.
- 웹 UI는 `tailscale` 모드에서 `https://agent-hub.<tailnet>.ts.net:8443`, `ssh` 모드에서 `http://127.0.0.1:13000`입니다.
- 확인: `claude mcp get basic-memory`가 `Connected`, Codex 세션의 `/mcp`에 `basic-memory`가 보입니다. VM에 닿지 않을 때 시작한 세션에는 도구가 없으므로 `/mcp`로 다시 연결하거나 새로 시작합니다.
- Windows: PowerShell에서 `make tunnel`이 출력하는 `ssh -N ...` 명령을 그대로 실행하고 같은 URL을 등록합니다([VM 런북](gcp-vm.md) 8단계의 Windows 설정, **Assumption**).

## 접속 방식 바꾸기 (Access mode change)

`tailscale` → `ssh` 순서입니다. 2·5단계는 VM·클라우드를 바꾸므로 사용자 OK 후 진행합니다.

1. `make backup` (롤백 지점)
2. [VM 런북](gcp-vm.md) 8단계 1번의 `allow-iap-ssh` 규칙
3. `~/.ssh/config`에 별칭을 넣고 대화형 `ssh ubuntu@agent-hub-iap true`. 실패하면 멈추고 2단계 규칙을 지웁니다(Tailscale 경로는 그대로).
4. `.env`: `BM_ACCESS=ssh`, `BM_VM_HOST=agent-hub-iap`. `make access-check`는 `ok`, `make status`는 Tailscale 로그인 경고(예상)를 냅니다.
5. `ssh ubuntu@agent-hub-iap 'sudo tailscale serve reset && sudo tailscale logout'`, Tailscale admin console에서 VM 기기 삭제
6. `make probe verify status`
7. 기기마다 `claude mcp remove basic-memory -s user`, `codex mcp remove basic-memory` 후 "에이전트 연결"대로 터널 URL로 다시 등록
8. Exposure audit을 하고 점검 기록과 Incident log에 남깁니다.

롤백: 5단계 전이면 `.env`를 되돌리고 `allow-iap-ssh`를 지웁니다. 5단계 뒤 IAP가 안 되면 [부트스트랩 런북](bootstrap.md) 문제 해결의 "22번을 지운 뒤 접속 불가" 행대로 내 IP/32 규칙을 만들고, `BM_ACCESS=tailscale`과 새 인증 키로 `make vm-bootstrap HOST=<공인 IP>`를 실행합니다.
````

Exposure audit 1번 항목의 첫 문장을 바꾼다. 명령과 그 아래 문장은 둔다.

```markdown
1. 방화벽 규칙 중 **VPC 밖의 소스를 허용하는 인바운드 규칙**을 확인합니다. `tailscale` 모드는 0개(`default-allow-internal`의 `10.128.0.0/9`만), `ssh` 모드는 `allow-iap-ssh`(`35.235.240.0/20`, `tcp:22`) 하나만 있어야 합니다.
```

Exposure audit 2번 항목 끝에 ``(`tailscale` 모드만)``을 붙인다. 첫 문단 끝에 한 문장을 더한다.

```markdown
`ssh` 모드에서는 Serve 검사 대신 VM의 Tailscale이 로그인 상태가 아닌지와 sshd가 키 전용인지 검사합니다.
```

"## 비용 점검" 끝에 넣는다.

```markdown
`ssh` 모드에서는 IAP 터널 트래픽이 무료 송신 한도(월 1GB)에 들어가는지 **Open question**입니다. 이전한 다음 달 SKU별 청구에서 확인합니다.
```

- [ ] **Step 6: `docs/ARCHITECTURE.md`**

토폴로지 코드 블록 다음에 넣는다.

````markdown
`BM_ACCESS=ssh`일 때(VM 안은 같음):

```
[개인/회사 Mac] ── make tunnel: ssh -N -L 127.0.0.1:18737, :13000 ──┐
  에이전트 → http://127.0.0.1:18737/mcp                               │ ~/.ssh/config Host agent-hub-iap
  브라우저 → http://127.0.0.1:13000                                   │ ProxyCommand: IAP 터널 (Google 계정 인증)
  make deploy/verify/backup → ssh ubuntu@agent-hub-iap ─────────────┤
                                                                     ▼
                        GCP e2-micro sshd :22 (인바운드: VPC 내부 + IAP 35.235.240.0/20의 22번)
                          └ 127.0.0.1:8737 Basic Memory, 127.0.0.1:3000 SilverBullet
```
````

구성 요소 표에 두 행을 더한다.

```markdown
| `make access-check` | Mac | 지금 네트워크에서 Tailscale 조정 서버·터널 엔드포인트·SSH 별칭이 되는지 보고하고 모드를 추천 (`scripts/access-check.sh`) |
| `make tunnel` | Mac | `ssh` 모드에서 MCP(18737)·웹 UI(13000)를 `127.0.0.1`로 포워딩 (`scripts/tunnel.sh`) |
```

신뢰 경계의 둘째 항목(포트 바인딩·Serve·방화벽 문장) 다음에 넣는다.

```markdown
- `ssh` 모드는 Tailscale을 쓰지 않습니다. VPC 밖 인바운드는 IAP 대역의 22번 하나이고, 인증은 Google 계정 IAM과 SSH 키입니다. 모든 터널은 기기의 `127.0.0.1`에만 열리고, `verify`가 VM의 Tailscale 꺼짐과 sshd 키 전용을 검사합니다. 한 VM에서 두 모드를 함께 쓰지 않습니다([ADR 0006](decisions/0006-access-modes.md)).
```

- [ ] **Step 7: `README.md`와 GCP 설계 상태 줄**

README 첫 문단의 "Tailscale tailnet 안에서만 접근하게 만드는"을 "Tailscale tailnet 또는 SSH 터널(GCP IAP) 중 VM마다 고른 한 경로로만 접근하게 만드는"으로 바꾼다. 결정 기록 줄에 ADR 0006 링크(대상 `docs/decisions/0006-access-modes.md`, 링크 글자 `ADR 0006`)를 더한다.

사전 요구사항의 "VM 작업용" 첫 항목(Tailscale 앱 줄)을 바꾼다.

```markdown
  - 접속 방식(`.env`의 `BM_ACCESS`)에 따라: `tailscale`이면 Tailscale 앱 설치·로그인과 `tailscale` 명령([accounts 런북](docs/runbooks/accounts.md)), `ssh`이면 아래 `gcloud`와 `~/.ssh/config`의 IAP 별칭([VM 런북](docs/runbooks/gcp-vm.md) 8단계). 어느 쪽인지는 `make access-check`로 정합니다.
```

"VM 구축 순서" 첫 항목 앞에 넣는다(번호는 그대로 두고 0번으로 넣는다).

```markdown
0. 접속 방식 정하기: 클라이언트가 쓸 네트워크마다 `make access-check`, 결과에 따라 `.env`의 `BM_ACCESS`([부트스트랩 런북](docs/runbooks/bootstrap.md))
```

"범위 밖" 줄에서 `에이전트별 MCP 연결 설정, `을 지우고, 그 절 위에 한 줄을 넣는다.

```markdown
Claude Code·Codex 연결은 [운영 런북](docs/runbooks/operations.md)의 "에이전트 연결"에 있습니다.
```

`docs/specs/2026-10-12-basic-memory-gcp-tailscale-design.md`의 상태 줄 끝에 한 문장을 더한다.

```markdown
접속 방식은 [접속 방식 설계](2026-10-15-access-modes-design.md)로 넓혔다(VM마다 Tailscale 또는 SSH 터널).
```

- [ ] **Step 8: 확인**

Run: `make check`
Expected: exit 0. 상대 링크, docs 경로, `gcloud` 설정 검사가 통과한다.

Run: `grep -rnE 'gcloud [a-z]' docs/runbooks README.md docs/ARCHITECTURE.md | grep -v 'configuration=bm-personal' | grep -vE 'configurations (create|list)'`
Expected: 출력 없음.

- [ ] **Step 9: 커밋과 push**

```bash
git add docs/decisions/0006-access-modes.md docs/runbooks docs/ARCHITECTURE.md README.md docs/specs/2026-10-12-basic-memory-gcp-tailscale-design.md
git commit -m "docs: document the access modes in the runbooks, architecture and ADR 0006" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 6"
git push
```

### Task 7: 스킬과 `AGENTS.md`

**Files:**
- Modify: `.agents/skills/bm-diagnose/SKILL.md`(Rules, Layers 1·5), `.agents/skills/bm-recover/SKILL.md`(Rules, 단계 3~5), `AGENTS.md`(사용자 승인 후)

**Interfaces:**
- Consumes: Task 6의 런북 절 이름(gcp-vm 8단계, operations "에이전트 연결"·"접속 방식 바꾸기", bootstrap "ssh 모드 순서")
- Produces: 없음

스킬을 고치기 전에 `skill-authoring` 스킬을 불러 규칙을 따른다. 스킬에는 클라우드 이름을 쓰지 않고 런북 절을 가리킨다.

- [ ] **Step 1: `bm-diagnose`**

Rules 첫 항목을 바꾼다.

```markdown
- Run only `make probe`, `make status`, `make logs` and `make access-check`, plus `tailscale status` (tailscale mode) and `ssh <user>@<host> true` on this machine.
```

Rules 끝에 넣는다.

```markdown
- The access mode is `BM_ACCESS` in the user's `.env` (empty means tailscale). You cannot read `.env`: ask the user which mode the VM uses, or read it from `make status` (`access: ssh` or `tailscale serve`).
```

Layers 1을 바꾼다.

```markdown
1. Path to the VM.
   - tailscale mode: `tailscale status | grep agent-hub` on this machine. Missing or offline means the VM is stopped, deleted or logged out: ask the user to check the instance state with the command in "정지된 VM" in docs/runbooks/operations.md. When this machine itself shows `offline` with a coordination server warning, the network blocks Tailscale: run `make access-check` and report it.
   - ssh mode: `make access-check` and `ssh ubuntu@agent-hub-iap true` (the alias is `BM_VM_HOST`). A failure points to the alias, its login or the firewall rule for the tunnel range: docs/runbooks/gcp-vm.md, section 8.
   - `TERMINATED` (stopped): the user starts it and updates `BM_VM_PUBLIC_IP` (same section). Do not rebuild.
   - Deleted or unusable: use `bm-recover`.
```

Layers 5(Serve) 끝에 넣는다.

```markdown
   In ssh mode there is no Serve: `make status` must show `tailscale: not installed or logged out`.
```

- [ ] **Step 2: `bm-recover`**

Rules 끝에 넣는다.

```markdown
- In ssh mode (`make status` printed `access: ssh` before, or the user says so) there is no Tailscale node, auth key or Serve: follow "ssh 모드 순서" in docs/runbooks/bootstrap.md for steps 3 to 5.
```

단계 3 끝에 넣는다.

```markdown
   In ssh mode the user deletes `default-allow-ssh` and creates the tunnel rule instead (docs/runbooks/gcp-vm.md, sections 3 and 8), and there is no Tailscale machine to remove.
```

단계 4 끝에 넣는다.

```markdown
   In ssh mode the user clears the alias's old host key (`ssh-keygen -R agent-hub-iap`), accepts the new one with an interactive `ssh ubuntu@agent-hub-iap true`, and runs `make vm-bootstrap HOST=agent-hub-iap` without a key.
```

단계 5 끝에 넣는다.

```markdown
   In ssh mode skip this step: there is no Tailscale SSH, and port 22 is open only to the tunnel range.
```

- [ ] **Step 3: `AGENTS.md` (사용자에게 문구를 보이고 승인받은 뒤)**

아래 다섯 곳의 바꿀 문구를 사용자에게 보이고 승인을 받는다. 승인 전에는 커밋하지 않는다.

1. 첫 줄의 `that is reachable only inside a Tailscale tailnet.`를 `that is reachable through one access mode per VM (BM_ACCESS): inside a Tailscale tailnet, or through an SSH tunnel (GCP IAP).`로 바꾼다.
2. Read first 줄 끝에 `For the access modes, read docs/specs/2026-10-15-access-modes-design.md.`를 더한다.
3. Commands의 No OK needed 목록 `make probe status logs verify backup`에 `access-check tunnel`을 더한다.
4. Invariants 첫 항목 끝에 한 문장을 더한다: `In ssh mode the only inbound rule from outside the VPC is the tunnel range to port 22, every ssh -L binds 127.0.0.1 (forward_spec), and a VM never runs both modes.`
5. Safety의 비밀값 문장(계획 10이 고친 문구) 끝에 한 문장을 더한다: `The ssh mode adds no secret: access is the user's cloud identity plus their SSH key.`

실제로 쓸 때는 식별자에 백틱을 붙인다(`BM_ACCESS`, `ssh -L`, `127.0.0.1`, `forward_spec`, 경로).

- [ ] **Step 4: 확인**

Run: `make check`
Expected: exit 0. `skills.bats`(머리말, 500줄, 링크)와 `cloud_neutral.bats`(스킬에 클라우드 이름 없음)와 `repo.bats`의 AGENTS.md·docs 경로 검사가 통과한다.

- [ ] **Step 5: 커밋과 push**

```bash
git add .agents/skills/bm-diagnose/SKILL.md .agents/skills/bm-recover/SKILL.md AGENTS.md
git commit -m "docs: teach the diagnose and recover skills and AGENTS.md about the access modes" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 12" --trailer "Task: 7"
git push
```

---

### 마무리: 리뷰, 넘기기 (git-workflow 스킬의 Review and merge)

- [ ] Progress log에 그날 `make check`의 테스트 수와 커버리지 %를 `Verified`로 적고, 계획 파일을 `docs/plans/completed/`로 옮겨 커밋·push한다(`Task: none`).
- [ ] 다른 벤더의 읽기 전용 리뷰(`make review BRANCH=plan/12-access-modes REVIEWER=<다른 벤더>`)는 사용자 승인 후 실행한다. PR 코멘트 게시도 승인 후 한다.
- [ ] 지적을 검증하고 하나당 커밋 하나로 고친다. 2회차까지만 돈다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.
- [ ] 병합 뒤 Clean up 절로 worktree를 정리한다.

## Follow-ups (이 계획 밖)

- 계획 13: 지금 VM을 `ssh` 모드로 옮기고 실제 네트워크에서 확인한다.
- 터널 자동 실행(launchd)·자동 재연결은 써 본 뒤 판단한다(스펙 범위 밖).
- Windows 확인(기기가 생기면).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
