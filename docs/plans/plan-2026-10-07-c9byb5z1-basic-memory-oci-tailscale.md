# Basic Memory on OCI + Tailscale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이 저장소만으로 Basic Memory MCP 서버를 로컬에서 검증하고, OCI Always Free VM에 올려 tailnet 안에서만 쓸 수 있게 만든다. 백업과 복원까지 포함한다.

**Architecture:**
- Mac이 유일한 제어 지점이다. `Makefile` 타깃이 `scripts/*.sh`를 호출하고, 스크립트는 SSH로 VM을 다룬다. 첫 부트스트랩만 공인 IP SSH를 쓰고, 이후에는 Tailscale SSH를 쓴다.
- VM에서는 같은 `compose.yaml`로 Basic Memory 컨테이너를 `127.0.0.1:8737`에 띄우고, Tailscale Serve가 이를 tailnet HTTPS로만 노출한다.
- 모든 동작은 bats 테스트로 검증한다. 테스트는 `tests/stubs/`의 가짜 ssh, docker, curl, tailscale을 쓴다. lint와 커버리지(kcov)는 고정 digest의 Docker 이미지에서 실행한다.

**Tech Stack:** Bash(macOS 3.2 호환), GNU Make, Docker Compose, Basic Memory 0.23.2, Tailscale(Serve, SSH), bats-core 1.14.0 + bats-support/assert, kcov, shellcheck 0.11.0, shfmt 3.12.0, jq, curl

**Spec:** `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md`

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
  - 매 커밋 전에 `make check`를 실행한다. Task 1의 Step 7부터 적용한다.
- 수명주기 작업은 Make 타깃으로만 한다. raw `docker compose`나 `ssh`는 실패 진단에만 쓰고, 그 이유를 기록한다.

## Review Focus

1. **macOS bash 3.2:** 사용자는 Mac 기본 bash로 `make`를 실행한다. bash 4+ 문법이 하나라도 섞이면 VM 작업 전체가 깨진다. → Task 1에서 `tests/repo.bats`에 금지 문법 검사 테스트를 추가한다.
2. **잘못된 `BM_TAILNET_DOMAIN`:** `https://`나 끝에 점이 붙은 값을 넣으면 URL이 깨지고, 원인을 알 수 없는 curl 실패만 남는다. 기대 동작은 형식 안내와 함께 즉시 실패하는 것이다. → Task 5에서 `verify-vm.sh` 테스트를 추가한다.
3. **새로 만든 VM에 복원:** 회수된 뒤 새로 만든 VM에는 `/srv/basic-memory`가 없을 수 있다. 이때도 restore가 성공해야 하고 `.prev-*` 디렉터리는 생기지 않아야 한다. → Task 6 테스트를 추가한다.
4. **따옴표가 들어간 `.env` 값:** Make의 `include`는 `BM_VM_HOST="bm-node"`의 따옴표를 값의 일부로 읽어 호스트 이름이 깨진다. → Task 2에서 `.env.example`에 따옴표가 없는지 검사하는 테스트를 추가하고, 예시 파일에 경고 주석을 넣는다.
5. **VM 재부팅 후 자동 복구:** 재부팅 뒤 컨테이너(`restart: unless-stopped`)와 Serve 설정(`--bg`)이 자동으로 돌아와야 한다. → Task 2에서 restart 정책 테스트를 추가하고, Task 10에서 재부팅 후 `make verify`를 수동으로 검증한다.

## File Structure

```
.gitignore .editorconfig .shellcheckrc        Task 1
Makefile                                       Task 1 (이후 Task 2~6에서 타깃 추가)
tools/Dockerfile tools/coverage.sh             Task 1  테스트 이미지와 커버리지 게이트
scripts/lib/common.sh                          Task 1  log/step/die/require_cmd/require_env/mask/remote/remote_compose/sha256_of
tests/helpers.bash                             Task 1  setup_stubs, use_vm_env
tests/stubs/{ssh,docker}                       Task 1
tests/common.bats tests/repo.bats              Task 1 (repo.bats는 Task 2, 7, 8에서 테스트 추가)
compose.yaml .env.example                      Task 2
scripts/verify-mcp.sh                          Task 3
tests/stubs/curl tests/fixtures/mcp-{sse,json}/ tests/verify_mcp.bats   Task 3
scripts/remote/bootstrap.sh scripts/bootstrap-vm.sh                     Task 4
tests/stubs/{sudo,tailscale,apt-get,dpkg,id,usermod} tests/fixtures/os-release tests/bootstrap.bats  Task 4
scripts/{deploy,verify-vm,status,logs}.sh                               Task 5
tests/stubs/{ss,free,nc} tests/vm_ops.bats                              Task 5
scripts/{backup,restore}.sh tests/backup_restore.bats                   Task 6
AGENTS.md CLAUDE.md .claude/settings.json .agents/skills/*/SKILL.md .claude/skills/* (symlinks)   Task 7
README.md docs/ARCHITECTURE.md docs/runbooks/*.md docs/decisions/*.md   Task 8
```

스펙 §5 대비 추가된 파일과 근거:
- `tools/`: 테스트 이미지 하나에 kcov, bats, jq, git, make를 담는다.
- `scripts/verify-vm.sh`, `scripts/logs.sh`: Make 레시피에 셸 로직을 넣지 않기 위해 분리한다.
- `scripts/remote/bootstrap.sh`: VM에서 실행되는 부분을 로컬에서 단위 테스트할 수 있게 분리한다.
- `fmt`와 `tools-image` 타깃.

스펙은 이 계획과 같은 커밋에서 갱신했다.

---

### Task 1: 개발 도구 체인과 공통 라이브러리

**Files:**
- Create: `.gitignore`, `.editorconfig`, `.shellcheckrc`, `tools/Dockerfile`, `tools/coverage.sh`, `Makefile`
- Create: `scripts/lib/common.sh`
- Create: `tests/helpers.bash`, `tests/stubs/ssh`, `tests/stubs/docker`
- Test: `tests/common.bats`, `tests/repo.bats`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `scripts/lib/common.sh`: 상수 `BM_REMOTE_APP_DIR`, `BM_REMOTE_DATA_ROOT`, `BM_CONTAINER_UID`, `SSH_CONNECT_TIMEOUT_SECONDS`, `HEALTH_TIMEOUT_SECONDS`
  - `common.sh` 함수: `log MSG`, `step MSG`, `die MSG`, `require_cmd CMD...`, `require_env VAR...`, `mask VALUE`, `remote CMD`, `remote_compose ARGS`, `sha256_of FILE`
  - `tests/helpers.bash`: `REPO_DIR`, `setup_stubs NAME...`(`STUB_BIN`, `STUB_LOG` export), `use_vm_env`
  - stub 규약: 모든 stub은 `<name> <args>` 한 줄을 `$STUB_LOG`에 추가한다. `ssh` stub은 마지막 인자를 `bash -c`로 로컬 실행하고, `SSH_STUB_FAIL_MATCH`에 맞는 명령이면 255로 실패한다. `docker` stub은 `DOCKER_STUB_FAIL_MATCH`에 맞으면 1로 실패하고, `ps` 호출에는 표를 출력한다.
  - Make 타깃: `help`, `tools-image`, `lint`, `fmt`, `test`, `coverage`, `check`

- [ ] **Step 1: 저장소 설정 파일 작성**

`.gitignore`:
```gitignore
# Local secrets and per-user settings (never commit)
.env
!.env.example
CLAUDE.local.md
.claude/settings.local.json
.claude/worktrees/
.memsearch/

# Generated data
.local-data/
backups/
.coverage/
```

`.editorconfig`:
```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[{*.sh,*.bash,tests/stubs/*}]
indent_style = space
indent_size = 2
switch_case_indent = true
binary_next_line = true

[Makefile]
indent_style = tab
```

`.shellcheckrc`:
```ini
external-sources=true
source-path=SCRIPTDIR
```

- [ ] **Step 2: 테스트 이미지와 커버리지 스크립트 작성**

`tools/Dockerfile`:
```dockerfile
# Test runner image: kcov (coverage) + bats-core with helper libraries + jq, git, make.
FROM bats/bats:1.14.0@sha256:5322b877351fda0cc435de8c6116de7d0a2ec79d7c680132a0ef329a633bc66f AS bats

FROM kcov/kcov:latest@sha256:481289ae32e55e5b733019515acd10948a4f76dfed381765577db909664fc603
RUN apt-get update \
  && apt-get install -y --no-install-recommends jq git make \
  && rm -rf /var/lib/apt/lists/*
COPY --from=bats /opt/bats /opt/bats
COPY --from=bats /usr/lib/bats /usr/lib/bats
RUN ln -s /opt/bats/bin/bats /usr/local/bin/bats \
  && git config --system --add safe.directory /repo
ENV BATS_LIB_PATH=/usr/lib/bats
ENTRYPOINT []
```

`tools/coverage.sh` (실행 권한 부여: `chmod +x tools/coverage.sh`):
```bash
#!/usr/bin/env bash
# Run the bats suite under kcov and enforce a minimum line coverage for scripts/.
# Usage (inside the tools image, repo mounted at /repo): tools/coverage.sh MIN_PERCENT
set -euo pipefail

readonly MIN_PERCENT="${1:?usage: tools/coverage.sh MIN_PERCENT}"
readonly REPO_DIR=/repo
readonly OUT_DIR="$REPO_DIR/.coverage"

rm -rf "$OUT_DIR"
kcov --include-path="$REPO_DIR/scripts" "$OUT_DIR" bats "$REPO_DIR/tests"

report="$(find "$OUT_DIR" -path '*/bats.*/coverage.json' | head -n 1)"
[[ -n "$report" ]] || {
  echo "kcov produced no coverage.json under $OUT_DIR" >&2
  exit 1
}
jq -r '.files[] | "\(.percent_covered)%\t\(.file)"' "$report"

missing=""
while IFS= read -r script; do
  if ! jq -e --arg f "$script" 'any(.files[]; .file == $f)' "$report" >/dev/null; then
    missing="$missing $script"
  fi
done < <(find "$REPO_DIR/scripts" -name '*.sh' -not -path '*/lib/*' | sort)
if [[ -n "$missing" ]]; then
  echo "never executed by any test (add bats tests):$missing" >&2
  exit 1
fi

total="$(jq -r '.percent_covered' "$report")"
echo "total line coverage: ${total}% (minimum ${MIN_PERCENT}%)"
if awk -v total="$total" -v min="$MIN_PERCENT" 'BEGIN { exit !(total + 0 < min + 0) }'; then
  echo "coverage below ${MIN_PERCENT}%: add tests for the uncovered lines (open .coverage/index.html)" >&2
  exit 1
fi
```

**Verified (2026-10-07 spike):** kcov는 bats가 실행한 스크립트와 source된 파일의 라인 커버리지를 수집한다. 결과는 `<out>/bats.<hash>/coverage.json`에 생긴다. `kcov-merged/coverage.json`은 생기지 않을 때가 있어서 쓰지 않는다.

- [ ] **Step 3: Makefile 작성**

`Makefile`:
```make
# Single lifecycle interface for this repo. Run `make help`.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

-include .env
BM_PORT ?= 8737
export BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP BM_PORT

SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
SHFMT_IMAGE := mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d
TOOLS_IMAGE := bm-tools:local
COVERAGE_MIN := 80
DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo" -w /repo
SH_FILES = $(shell git ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' 'tests/stubs/*')

.PHONY: help tools-image lint fmt test coverage check

help: ## Show available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z0-9-]+:.*## / { printf "  %-14s %s\n", $$1, $$2 }' $(firstword $(MAKEFILE_LIST))

tools-image: ## Build the local test image (kcov + bats + jq)
	@docker build -q -t $(TOOLS_IMAGE) tools >/dev/null

lint: ## Check shell files with shellcheck and shfmt
	$(DOCKER_RUN) $(SHELLCHECK_IMAGE) $(SH_FILES)
	$(DOCKER_RUN) $(SHFMT_IMAGE) -d $(SH_FILES)

fmt: ## Rewrite shell files in place with shfmt
	$(DOCKER_RUN) $(SHFMT_IMAGE) -w $(SH_FILES)

test: tools-image ## Run all bats tests
	$(DOCKER_RUN) $(TOOLS_IMAGE) bats tests

coverage: tools-image ## Run tests under kcov; fail below COVERAGE_MIN% line coverage
	$(DOCKER_RUN) $(TOOLS_IMAGE) tools/coverage.sh $(COVERAGE_MIN)

check: lint coverage ## Lint + all tests + coverage gate (run before every commit)
```

- [ ] **Step 4: 테스트 헬퍼와 stub 작성**

`tests/helpers.bash`:
```bash
# shellcheck shell=bash
# Shared bats helpers. Every test file starts with: load helpers
bats_load_library bats-support
bats_load_library bats-assert

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export REPO_DIR

# setup_stubs NAME... : put tests/stubs/NAME first on PATH. Stubs log "<name> <args>" to $STUB_LOG.
setup_stubs() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$STUB_BIN"
  touch "$STUB_LOG"
  local name
  for name in "$@"; do
    ln -sf "$REPO_DIR/tests/stubs/$name" "$STUB_BIN/$name"
  done
  export STUB_BIN STUB_LOG PATH="$STUB_BIN:$PATH"
}

# use_vm_env: point scripts at a fake VM whose directories live in the test tmpdir.
use_vm_env() {
  export BM_VM_HOST=bm-node BM_VM_USER=ubuntu BM_TAILNET_DOMAIN=example.ts.net BM_PORT=8737
  export BM_REMOTE_APP_DIR="$BATS_TEST_TMPDIR/opt/basic-memory"
  export BM_REMOTE_DATA_ROOT="$BATS_TEST_TMPDIR/srv/basic-memory"
  mkdir -p "$BM_REMOTE_APP_DIR" "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config"
}
```

`tests/stubs/ssh` (실행 권한 부여):
```bash
#!/usr/bin/env bash
# Test stub for ssh: logs the call, then runs the remote command locally so other stubs on PATH
# act as the VM. SSH_STUB_FAIL_MATCH=<substring> makes matching remote commands fail with 255.
set -euo pipefail
printf 'ssh %s\n' "$*" >>"$STUB_LOG"
remote_cmd="${*: -1}"
if [[ -n "${SSH_STUB_FAIL_MATCH:-}" && "$remote_cmd" == *"$SSH_STUB_FAIL_MATCH"* ]]; then
  echo "ssh stub: simulated failure for: $remote_cmd" >&2
  exit 255
fi
exec bash -c "$remote_cmd"
```

`tests/stubs/docker` (실행 권한 부여):
```bash
#!/usr/bin/env bash
# Test stub for docker: logs the call. DOCKER_STUB_FAIL_MATCH=<substring> makes matching calls fail.
set -euo pipefail
printf 'docker %s\n' "$*" >>"$STUB_LOG"
if [[ -n "${DOCKER_STUB_FAIL_MATCH:-}" && "$*" == *"$DOCKER_STUB_FAIL_MATCH"* ]]; then
  echo "docker stub: simulated failure for: $*" >&2
  exit 1
fi
if [[ "$*" == *" ps"* ]]; then
  echo "NAME                  STATUS"
  echo "basic-memory-server   Up 5 minutes (healthy)"
fi
```

Run: `chmod +x tests/stubs/ssh tests/stubs/docker tools/coverage.sh`

- [ ] **Step 5: 실패하는 테스트 작성 (`tests/common.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh docker
  use_vm_env
  # shellcheck source=../scripts/lib/common.sh
  . "$REPO_DIR/scripts/lib/common.sh"
}

@test "die prints an error and exits 1" {
  run die "boom"
  assert_failure 1
  assert_output "ERROR: boom"
}

@test "step logs a timestamped marker" {
  run step "deploy"
  assert_success
  assert_output --regexp '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ==> deploy$'
}

@test "require_cmd passes when every command exists" {
  run require_cmd bash jq
  assert_success
}

@test "require_cmd names the missing command" {
  run require_cmd definitely-not-installed
  assert_failure
  assert_output --partial "missing command 'definitely-not-installed'"
}

@test "require_env passes when variables are set" {
  BM_TEST_VALUE=x
  run require_env BM_TEST_VALUE BM_VM_HOST
  assert_success
}

@test "require_env names the missing variable" {
  unset BM_TEST_MISSING
  run require_env BM_TEST_MISSING
  assert_failure
  assert_output --partial "missing env BM_TEST_MISSING"
}

@test "mask keeps only a 4-character prefix of long values" {
  run mask "tskey-auth-abcdef123456"
  assert_output "tske****"
}

@test "mask hides short values completely" {
  run mask "short"
  assert_output "****"
}

@test "remote runs ssh in batch mode against BM_VM_USER@BM_VM_HOST" {
  run remote "echo hi"
  assert_success
  assert_output "hi"
  run cat "$STUB_LOG"
  assert_output "ssh -o BatchMode=yes -o ConnectTimeout=10 ubuntu@bm-node echo hi"
}

@test "remote_compose runs docker compose inside the VM app dir" {
  run remote_compose "ps"
  assert_success
  assert_output --partial "basic-memory-server"
  run grep -F "cd $BM_REMOTE_APP_DIR && docker compose ps" "$STUB_LOG"
  assert_success
}

@test "sha256_of prints only the hex digest" {
  printf 'abc' >"$BATS_TEST_TMPDIR/f"
  run sha256_of "$BATS_TEST_TMPDIR/f"
  assert_output "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}
```

- [ ] **Step 6: 테스트가 실패하는지 확인**

Run: `make test`
Expected: FAIL. `scripts/lib/common.sh`가 없어서 `setup`의 source가 `No such file or directory`로 실패한다.

- [ ] **Step 7: `scripts/lib/common.sh` 구현**

```bash
#!/usr/bin/env bash
# Shared helpers for scripts/*.sh. Source it; callers already run with set -euo pipefail:
#   . "$SCRIPT_DIR/lib/common.sh"
# Must stay compatible with macOS bash 3.2.
# shellcheck disable=SC2034  # constants below are used by the scripts that source this file

# VM layout. Overridable only so tests can point at a temp dir.
readonly BM_REMOTE_APP_DIR="${BM_REMOTE_APP_DIR:-/opt/basic-memory}"
readonly BM_REMOTE_DATA_ROOT="${BM_REMOTE_DATA_ROOT:-/srv/basic-memory}"
readonly BM_CONTAINER_UID=1000
readonly SSH_CONNECT_TIMEOUT_SECONDS=10
readonly HEALTH_TIMEOUT_SECONDS=180

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

step() { log "==> $*"; }

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing command '$cmd': install it (see README.md, Prerequisites)"
  done
}

require_env() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || die "missing env $name: copy .env.example to .env and set it"
  done
}

# mask VALUE -> first 4 characters + ****, or **** for short values. Use before printing secrets or ids.
mask() {
  local value="$1"
  if ((${#value} <= 8)); then
    printf '****'
  else
    printf '%s****' "${value:0:4}"
  fi
}

# remote CMD -> run CMD on the VM over Tailscale SSH.
remote() {
  ssh -o BatchMode=yes -o ConnectTimeout="$SSH_CONNECT_TIMEOUT_SECONDS" "${BM_VM_USER}@${BM_VM_HOST}" "$@"
}

# remote_compose ARGS -> docker compose ARGS inside the VM app dir.
remote_compose() {
  remote "cd $BM_REMOTE_APP_DIR && docker compose $*"
}

# sha256_of FILE -> hex digest (sha256sum on Linux, shasum on macOS).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
```

- [ ] **Step 8: 테스트가 통과하는지 확인**

Run: `make test`
Expected: PASS(11 tests). `ok 1 die prints an error and exits 1` … `ok 11 sha256_of prints only the hex digest`.

- [ ] **Step 9: 구조 테스트 작성 (`tests/repo.bats`)**

```bash
#!/usr/bin/env bats
load helpers

shell_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- '*.sh' '*.bash' 'tests/stubs/*'
}

@test "every executable shell file enables strict mode" {
  local file missing=""
  while IFS= read -r file; do
    case "$file" in
      *.bash | scripts/lib/*) continue ;;
    esac
    grep -qx 'set -euo pipefail' "$REPO_DIR/$file" || missing="$missing $file"
  done < <(shell_files)
  [[ -z "$missing" ]] || fail "add 'set -euo pipefail' right after the shebang in:$missing"
}

@test "every script and stub is executable" {
  local file missing=""
  while IFS= read -r file; do
    case "$file" in
      *.bash | scripts/lib/*) continue ;;
    esac
    [[ -x "$REPO_DIR/$file" ]] || missing="$missing $file"
  done < <(shell_files)
  [[ -z "$missing" ]] || fail "run: chmod +x$missing"
}

@test "scripts avoid bash 4+ features (macOS ships bash 3.2)" {
  run grep -rnE 'mapfile|readarray|declare -A|local -A|inherit_errexit|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)' "$REPO_DIR/scripts"
  assert_failure
}

@test "every Make target has a ## description" {
  local missing
  missing="$(grep -E '^[a-z0-9-]+:([^=]|$)' "$REPO_DIR/Makefile" | grep -v '## ' | cut -d: -f1 || true)"
  [[ -z "$missing" ]] || fail "add '## <description>' to these Makefile targets: $missing"
}

@test "make help lists every documented target" {
  run make -s -C "$REPO_DIR" help
  assert_success
  local target
  for target in $(grep -oE '^[a-z0-9-]+:.*## ' "$REPO_DIR/Makefile" | cut -d: -f1); do
    assert_output --partial "  $target "
  done
}
```

Run: `make test`
Expected: PASS(16 tests).

- [ ] **Step 10: lint와 커버리지 게이트 확인**

Run: `make check`
Expected:
- shellcheck와 shfmt가 출력 없이 통과한다. 포맷 차이가 나오면 `make fmt` 후 다시 실행한다.
- 커버리지 표에 `/repo/scripts/lib/common.sh`가 나오고, `total line coverage: <N>% (minimum 80%)`가 출력된다.
  - `N`은 80 이상이어야 한다(`shasum` 분기 2줄만 미실행).
  - "never executed" 검사 대상(`scripts/` 아래 lib 외 `.sh`)이 아직 없으므로 그 오류는 나오지 않는다.

- [ ] **Step 11: Commit**

```bash
git add .gitignore .editorconfig .shellcheckrc tools Makefile scripts/lib/common.sh tests
git commit -m "chore: add test toolchain, Makefile and shared shell library"
```

---

### Task 2: compose 파일과 로컬 실행 타깃

**Files:**
- Create: `compose.yaml`, `.env.example`
- Modify: `Makefile`(`local-up`, `local-down`, `local-logs` 추가)
- Test: `tests/repo.bats`(compose와 env 테스트 추가)

**Interfaces:**
- Consumes: Task 1 Makefile 변수(`BM_PORT`), `tests/helpers.bash`
- Produces:
  - `compose.yaml` 서비스 `basic-memory`, 컨테이너 이름 `basic-memory-server`
  - 환경변수 `BM_PORT`, `BM_KNOWLEDGE_DIR`, `BM_CONFIG_DIR`. 기본값은 로컬용 `./.local-data/...`이다.
  - `.env.example` 키: `BM_VM_HOST`, `BM_VM_USER`, `BM_TAILNET_DOMAIN`, `BM_VM_PUBLIC_IP`, `BM_PORT`

- [ ] **Step 1: 실패하는 테스트 추가 (`tests/repo.bats` 끝에 append)**

```bash
@test "compose pins the Basic Memory image by digest" {
  run grep -E '^ +image: ghcr\.io/basicmachines-co/basic-memory:[0-9.]+@sha256:[0-9a-f]{64}$' "$REPO_DIR/compose.yaml"
  assert_success
}

@test "compose publishes ports on 127.0.0.1 only" {
  local ports
  ports="$(awk '/^ +ports:/ { p = 1; next } p && /^ +- / { print; next } p { p = 0 }' "$REPO_DIR/compose.yaml")"
  [[ -n "$ports" ]] || fail "compose.yaml has no ports entries"
  if grep -vqE '^ +- "127\.0\.0\.1:' <<<"$ports"; then
    fail "every published port must start with \"127.0.0.1: (Basic Memory has no auth): $ports"
  fi
}

@test "compose overrides the image's default SSE command with streamable-http on /mcp" {
  run grep -F '"--transport", "streamable-http"' "$REPO_DIR/compose.yaml"
  assert_success
  run grep -F '"--path", "/mcp"' "$REPO_DIR/compose.yaml"
  assert_success
}

@test "compose restarts the container after reboots" {
  run grep -E '^ +restart: unless-stopped$' "$REPO_DIR/compose.yaml"
  assert_success
}

@test ".env is never tracked by git" {
  run bash -c "git -C '$REPO_DIR' ls-files | grep -E '(^|/)\.env$'"
  assert_failure
}

@test ".env.example has only comments and unquoted KEY=value lines" {
  local bad
  bad="$(grep -vE '^(#.*|[A-Z][A-Z0-9_]*=[^"'"'"' ]*|)$' "$REPO_DIR/.env.example" || true)"
  [[ -z "$bad" ]] || fail "make reads quotes and spaces literally; fix these .env.example lines: $bad"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. compose와 `.env.example` 관련 테스트 5개가 파일 없음으로 실패한다(`.env is never tracked`는 통과).

- [ ] **Step 3: `compose.yaml` 작성**

```yaml
# Basic Memory MCP server. The same file runs locally (make local-up) and on the VM (make deploy).
# Defaults are the local values; on the VM, scripts/deploy.sh writes absolute paths into .env.
name: basic-memory
services:
  basic-memory:
    image: ghcr.io/basicmachines-co/basic-memory:0.23.2@sha256:939f1173d96626c280763e14622f2381d49fbbb7db17cae2e832f4f639405643
    container_name: basic-memory-server
    # The image default is `--transport sse`; agents connect over streamable HTTP at /mcp.
    command: ["basic-memory", "mcp", "--transport", "streamable-http", "--host", "0.0.0.0", "--port", "8000", "--path", "/mcp"]
    # Basic Memory has no authentication: never bind anything but loopback.
    ports:
      - "127.0.0.1:${BM_PORT:-8737}:8000"
    volumes:
      - "${BM_KNOWLEDGE_DIR:-./.local-data/knowledge}:/app/data"
      - "${BM_CONFIG_DIR:-./.local-data/config}:/home/appuser/.basic-memory"
    environment:
      BASIC_MEMORY_DEFAULT_PROJECT: main
      BASIC_MEMORY_INDEX_CHANGES: "true"
      BASIC_MEMORY_LOG_LEVEL: INFO
    healthcheck:
      # Upstream checks `basic-memory --version`, which passes even when the server is down.
      test: ["CMD", "python", "-c", "import socket; socket.create_connection(('127.0.0.1', 8000), timeout=5).close()"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
      start_interval: 2s
    restart: unless-stopped
```

- [ ] **Step 4: `.env.example` 작성**

```bash
# Copy to .env (git-ignored) and fill in. No secrets belong here.
# Write values without quotes or spaces: make reads them literally.

# Tailscale machine name of the VM (MagicDNS short name)
BM_VM_HOST=bm-node
# SSH user on the VM (Canonical Ubuntu images use ubuntu)
BM_VM_USER=ubuntu
# Your tailnet DNS name, e.g. tail1234.ts.net (admin console > DNS); no https:// and no trailing dot
BM_TAILNET_DOMAIN=
# Optional: VM public IPv4; make verify then checks ports 22 and BM_PORT are closed from outside
BM_VM_PUBLIC_IP=
# Loopback port Basic Memory listens on (local and VM)
BM_PORT=8737
```

- [ ] **Step 5: Makefile에 로컬 타깃 추가**

`.PHONY` 줄을 다음으로 바꾼다.
```make
.PHONY: help tools-image lint fmt test coverage check local-up local-down local-logs
```
파일 끝에 다음을 추가한다.
```make
COMPOSE := docker compose -f compose.yaml
LOCAL_DATA_DIRS := .local-data/knowledge .local-data/config

local-up: ## Start Basic Memory locally on 127.0.0.1:BM_PORT and wait until healthy
	mkdir -p $(LOCAL_DATA_DIRS)
	$(COMPOSE) up -d --wait

local-down: ## Stop the local container (data in .local-data/ is kept)
	$(COMPOSE) down

local-logs: ## Show recent local container logs
	$(COMPOSE) logs --tail=200
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `make test`
Expected: PASS(22 tests).

- [ ] **Step 7: 실제 컨테이너로 확인 (통합)**

Run: `docker compose -f compose.yaml config -q && make local-up && lsof -nP -iTCP:8737 -sTCP:LISTEN`
Expected:
- `local-up`이 `Container basic-memory-server Healthy`로 끝난다.
- `lsof` 출력에 `127.0.0.1:8737`만 보이고, `*:8737`은 없다.

Run: `make local-down`
Expected: `Container basic-memory-server Removed`

- [ ] **Step 8: Commit**

Run: `make check` (PASS)
```bash
git add compose.yaml .env.example Makefile tests/repo.bats
git commit -m "feat: add Basic Memory compose service and local lifecycle targets"
```

---

### Task 3: MCP 종단 검증 스크립트 (`verify-mcp.sh`)

**Files:**
- Create: `scripts/verify-mcp.sh`, `tests/stubs/curl`
- Create: `tests/fixtures/mcp-sse/{headers.txt,initialize.body,notifications_initialized.status,tools_list.body,call_write_note.body,call_read_note.body,call_delete_note.body}`
- Create: `tests/fixtures/mcp-json/` (같은 파일 이름)
- Modify: `Makefile`(`local-verify` 추가)
- Test: `tests/verify_mcp.bats`

**Interfaces:**
- Consumes: `common.sh`의 `log`, `step`, `die`, `require_cmd`, `mask`
- Produces:
  - CLI: `scripts/verify-mcp.sh [--host-header HOST] URL`. 성공하면 0과 `OK: MCP round trip passed`, 실패하면 1과 `ERROR: <step>: <원인>`.
  - 환경변수 `VERIFY_ID`(테스트용 고정 ID. 기본값은 `<UTC 시각>-$RANDOM`)
  - curl stub 규약:
    - MCP 모드(`CURL_FIXTURES` 설정 시): 요청 method로 픽스처를 고른다. 이름은 `initialize`, `notifications_initialized`, `tools_list`, `call_<tool>`이고 `.body`와 선택적 `.status` 파일을 쓴다. 요청 본문은 `$STUB_LOG.requests`에 기록하고, `CURL_STUB_EXIT`를 설정하면 그 코드로 실패한다.
    - 다운로드 모드(`CURL_FIXTURES` 미설정): `-o FILE`이면 FILE에 `stub`을 쓰고, 아니면 `$CURL_STUB_SCRIPT`(기본 `true`)를 출력한다.

**Verified (2026-10-07, 0.23.2 로컬 컨테이너, Command: curl):**
- `initialize` 응답은 `text/event-stream`이고 `mcp-session-id` 헤더가 붙는다.
- `notifications/initialized`는 HTTP 202를 돌려준다.
- 도구 결과는 `.result.structuredContent.result`에 있다. `write_note`는 `action: created`, `read_note`는 `content`, `delete_note`는 `deleted: true`를 담는다.
- `Host: bm-node.example.ts.net`도 200을 돌려준다.

- [ ] **Step 1: 픽스처 작성 (실제 응답에서 줄인 것)**

`tests/fixtures/mcp-sse/headers.txt`:
```
HTTP/1.1 200 OK
content-type: text/event-stream
mcp-session-id: test-session-0123456789
```

`tests/fixtures/mcp-sse/initialize.body`:
```
event: message
data: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":true}},"serverInfo":{"name":"Basic Memory","version":"4.0.0b1"}}}

```

`tests/fixtures/mcp-sse/notifications_initialized.status`:
```
202
```

`tests/fixtures/mcp-sse/tools_list.body`:
```
event: message
data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"write_note"},{"name":"read_note"},{"name":"search_notes"},{"name":"delete_note"},{"name":"edit_note"}]}}

```

`tests/fixtures/mcp-sse/call_write_note.body`:
```
event: message
data: {"jsonrpc":"2.0","id":3,"result":{"_meta":{"fastmcp":{"wrap_result":true}},"content":[{"text":"{\"title\":\"bm-verify-test1\",\"permalink\":\"main/verify/bm-verify-test1\",\"file_path\":\"verify/bm-verify-test1.md\",\"checksum\":null,\"action\":\"created\"}","type":"text"}],"isError":false,"structuredContent":{"result":{"title":"bm-verify-test1","permalink":"main/verify/bm-verify-test1","file_path":"verify/bm-verify-test1.md","checksum":null,"action":"created"}}}}

```

`tests/fixtures/mcp-sse/call_read_note.body`:
```
event: message
data: {"jsonrpc":"2.0","id":4,"result":{"_meta":{"fastmcp":{"wrap_result":true}},"content":[{"text":"{}","type":"text"}],"isError":false,"structuredContent":{"result":{"title":"bm-verify-test1","permalink":"main/verify/bm-verify-test1","file_path":"verify/bm-verify-test1.md","content":"\nbm-verify marker test1","frontmatter":{"title":"bm-verify-test1","type":"note","permalink":"main/verify/bm-verify-test1"}}}}}

```

`tests/fixtures/mcp-sse/call_delete_note.body`:
```
event: message
data: {"jsonrpc":"2.0","id":5,"result":{"_meta":{"fastmcp":{"wrap_result":true}},"content":[{"text":"{}","type":"text"}],"isError":false,"structuredContent":{"result":{"deleted":true,"title":"bm-verify-test1","permalink":"main/verify/bm-verify-test1","file_path":"verify/bm-verify-test1.md"}}}}

```

`tests/fixtures/mcp-json/`에는 plain JSON 본문을 둔다. `structuredContent`가 없으므로 `content[0].text` 대체 경로를 검증한다.

`headers.txt`:
```
HTTP/1.1 200 OK
content-type: application/json
mcp-session-id: test-session-0123456789
```
`initialize.body`:
```
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"Basic Memory","version":"4.0.0b1"}}}
```
`notifications_initialized.status`:
```
202
```
`tools_list.body`:
```
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"write_note"},{"name":"read_note"},{"name":"search_notes"},{"name":"delete_note"}]}}
```
`call_write_note.body`:
```
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{\"title\":\"bm-verify-test1\",\"action\":\"created\"}"}],"isError":false}}
```
`call_read_note.body`:
```
{"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"{\"title\":\"bm-verify-test1\",\"content\":\"bm-verify marker test1\"}"}],"isError":false}}
```
`call_delete_note.body`:
```
{"jsonrpc":"2.0","id":5,"result":{"content":[{"type":"text","text":"{\"deleted\":true}"}],"isError":false}}
```

- [ ] **Step 2: curl stub 작성 (`tests/stubs/curl`, 실행 권한 부여)**

```bash
#!/usr/bin/env bash
# Test stub for curl.
# MCP mode (CURL_FIXTURES set): answers JSON-RPC requests from fixture files named after the method:
#   initialize, notifications_initialized, tools_list, call_<tool> (.body and optional .status).
#   Request payloads are appended to $STUB_LOG.requests. CURL_STUB_EXIT=<n> simulates a transport error.
# Download mode: writes "stub" to the -o file, or prints $CURL_STUB_SCRIPT (default "true") for `curl | sh`.
set -euo pipefail
printf 'curl %s\n' "$*" >>"$STUB_LOG"

headers_file=""
body_file=""
data=""
while (($#)); do
  case "$1" in
    -D)
      headers_file="$2"
      shift 2
      ;;
    -o)
      body_file="$2"
      shift 2
      ;;
    -d)
      data="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done

if [[ -z "${CURL_FIXTURES:-}" ]]; then
  if [[ -n "$body_file" ]]; then
    echo stub >"$body_file"
  else
    printf '%s\n' "${CURL_STUB_SCRIPT:-true}"
  fi
  exit 0
fi

if [[ -n "${CURL_STUB_EXIT:-}" ]]; then
  echo "curl: (7) Failed to connect (stub)" >&2
  exit "$CURL_STUB_EXIT"
fi

printf '%s\n' "$data" >>"$STUB_LOG.requests"
key="$(jq -r 'if .method == "tools/call" then "call_" + .params.name else (.method | gsub("/"; "_")) end' <<<"$data")"
if [[ -n "$headers_file" ]]; then
  cp "$CURL_FIXTURES/headers.txt" "$headers_file"
fi
if [[ -f "$CURL_FIXTURES/$key.body" ]]; then
  cp "$CURL_FIXTURES/$key.body" "$body_file"
else
  : >"$body_file"
fi
if [[ -f "$CURL_FIXTURES/$key.status" ]]; then
  tr -d '\n' <"$CURL_FIXTURES/$key.status"
else
  printf '200'
fi
```

- [ ] **Step 3: 실패하는 테스트 작성 (`tests/verify_mcp.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl
  export VERIFY_ID=test1
  FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  cp -R "$REPO_DIR/tests/fixtures/mcp-sse" "$FIXTURES"
  export CURL_FIXTURES="$FIXTURES"
  VERIFY="$REPO_DIR/scripts/verify-mcp.sh"
  URL=http://127.0.0.1:8737/mcp
}

@test "passes a full round trip against SSE responses" {
  run "$VERIFY" "$URL"
  assert_success
  assert_output --partial "OK: MCP round trip passed"
}

@test "passes a full round trip against plain JSON responses" {
  export CURL_FIXTURES="$REPO_DIR/tests/fixtures/mcp-json"
  run "$VERIFY" "$URL"
  assert_success
}

@test "sends the session id from initialize on every later request" {
  run "$VERIFY" "$URL"
  assert_success
  run grep -c 'Mcp-Session-Id: test-session-0123456789' "$STUB_LOG"
  assert_output 5
}

@test "never prints the full session id" {
  run "$VERIFY" "$URL"
  refute_output --partial "test-session-0123456789"
  assert_output --partial "session test****"
}

@test "sends the Host header on every request when --host-header is given" {
  run "$VERIFY" --host-header bm-node.example.ts.net "$URL"
  assert_success
  run grep -c 'Host: bm-node.example.ts.net' "$STUB_LOG"
  assert_output 6
}

@test "writes, reads and deletes the same uniquely named note" {
  run "$VERIFY" "$URL"
  assert_success
  run jq -r 'select(.method == "tools/call") | "\(.params.name) \(.params.arguments.title // .params.arguments.identifier)"' "$STUB_LOG.requests"
  assert_output $'write_note bm-verify-test1\nread_note bm-verify-test1\ndelete_note bm-verify-test1'
}

@test "fails with the server message when a tool reports an error" {
  cat >"$FIXTURES/call_write_note.body" <<'EOF'
event: message
data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Note already exists"}],"isError":true}}
EOF
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "write_note: tool error: Note already exists"
}

@test "fails when a required tool is missing" {
  cat >"$FIXTURES/tools_list.body" <<'EOF'
data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"write_note"},{"name":"read_note"},{"name":"search_notes"}]}}
EOF
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "tools/list: missing tool 'delete_note'"
}

@test "fails on a non-200 HTTP status" {
  echo 503 >"$FIXTURES/initialize.status"
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "initialize: HTTP 503"
}

@test "fails on a JSON-RPC error response" {
  echo 'data: {"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid request"}}' >"$FIXTURES/initialize.body"
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial 'initialize: JSON-RPC error {"code":-32600,"message":"Invalid request"}'
}

@test "fails when the body is not JSON-RPC" {
  echo '<html>Bad gateway</html>' >"$FIXTURES/initialize.body"
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "initialize: response is not JSON-RPC"
}

@test "deletes the note during cleanup when read-back fails" {
  cat >"$FIXTURES/call_read_note.body" <<'EOF'
data: {"jsonrpc":"2.0","id":4,"result":{"content":[],"isError":false,"structuredContent":{"result":{"title":"bm-verify-test1","content":"something else"}}}}
EOF
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "read_note: content of 'bm-verify-test1' does not contain 'bm-verify marker test1'"
  assert_output --partial "cleanup: deleting leftover note 'bm-verify-test1'"
  run grep -c '"name":"delete_note"' "$STUB_LOG.requests"
  assert_output 1
}

@test "explains how to start the server when curl cannot connect" {
  export CURL_STUB_EXIT=7
  run "$VERIFY" "$URL"
  assert_failure
  assert_output --partial "initialize: request to $URL failed"
}

@test "rejects a missing URL" {
  run "$VERIFY"
  assert_failure
  assert_output --partial "usage: verify-mcp.sh [--host-header HOST] URL"
}

@test "rejects unknown options" {
  run "$VERIFY" --bogus "$URL"
  assert_failure
  assert_output --partial "usage:"
}
```

- [ ] **Step 4: 실패 확인**

Run: `make test`
Expected: FAIL. `verify_mcp.bats`의 테스트들이 `scripts/verify-mcp.sh: No such file or directory`로 실패한다.

- [ ] **Step 5: `scripts/verify-mcp.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# End-to-end check of a Basic Memory MCP endpoint over streamable HTTP:
# initialize -> tools/list -> write_note -> read_note -> delete_note.
# Usage: verify-mcp.sh [--host-header HOST] URL
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly PROTOCOL_VERSION="2025-06-18"
readonly REQUEST_TIMEOUT_SECONDS=30
readonly REQUIRED_TOOLS="write_note read_note search_notes delete_note"
readonly VERIFY_DIRECTORY="verify"
readonly VERIFY_ID="${VERIFY_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM}"

URL=""
HOST_HEADER=""
SESSION_ID=""
WORK_DIR=""
NOTE_WRITTEN=""

usage() { die "usage: verify-mcp.sh [--host-header HOST] URL"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --host-header)
        [[ -n "${2:-}" ]] || usage
        HOST_HEADER="$2"
        shift 2
        ;;
      -*) usage ;;
      *)
        URL="$1"
        shift
        ;;
    esac
  done
  [[ -n "$URL" ]] || usage
}

# post PAYLOAD -> prints the HTTP status; response headers and body land in $WORK_DIR.
post() {
  local -a args=(-sS -m "$REQUEST_TIMEOUT_SECONDS" -D "$WORK_DIR/headers" -o "$WORK_DIR/body" -w '%{http_code}'
    -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream'
    -H "MCP-Protocol-Version: $PROTOCOL_VERSION")
  if [[ -n "$HOST_HEADER" ]]; then
    args+=(-H "Host: $HOST_HEADER")
  fi
  if [[ -n "$SESSION_ID" ]]; then
    args+=(-H "Mcp-Session-Id: $SESSION_ID")
  fi
  curl "${args[@]}" -d "$1" "$URL"
}

# extract_message ID -> the JSON-RPC message with that id from a JSON or SSE response body.
extract_message() {
  local id="$1" body="$WORK_DIR/body"
  if grep -q '^data:' "$body"; then
    sed -n 's/^data: \{0,1\}//p' "$body" | jq -c --argjson id "$id" 'select(.id == $id)' | tail -n 1
  else
    jq -c --argjson id "$id" 'select(.id == $id)' "$body"
  fi
}

# rpc ID METHOD PARAMS_JSON -> prints the JSON-RPC result object.
rpc() {
  local id="$1" method="$2" params="$3" payload status message
  payload="$(jq -cn --argjson id "$id" --arg method "$method" --argjson params "$params" \
    '{jsonrpc: "2.0", id: $id, method: $method, params: $params}')"
  status="$(post "$payload")" \
    || die "$method: request to $URL failed (is the server running? try 'make local-up' or 'make status')"
  [[ "$status" == 200 ]] || die "$method: HTTP $status from $URL: $(head -c 300 "$WORK_DIR/body")"
  message="$(extract_message "$id" 2>/dev/null)" \
    || die "$method: response is not JSON-RPC: $(head -c 300 "$WORK_DIR/body")"
  [[ -n "$message" ]] || die "$method: no response with id $id: $(head -c 300 "$WORK_DIR/body")"
  if jq -e 'has("error")' <<<"$message" >/dev/null; then
    die "$method: JSON-RPC error $(jq -c '.error' <<<"$message")"
  fi
  jq -c '.result' <<<"$message"
}

notify() {
  local method="$1" status
  status="$(post "$(jq -cn --arg method "$method" '{jsonrpc: "2.0", method: $method}')")" \
    || die "$method: request to $URL failed"
  [[ "$status" == 200 || "$status" == 202 ]] || die "$method: unexpected HTTP $status"
}

# call_tool ID NAME ARGUMENTS_JSON -> prints the tool's structured result object.
call_tool() {
  local id="$1" name="$2" arguments="$3" params result
  params="$(jq -cn --arg name "$name" --argjson arguments "$arguments" '{name: $name, arguments: $arguments}')"
  result="$(rpc "$id" tools/call "$params")" || exit 1
  if jq -e '.isError == true' <<<"$result" >/dev/null; then
    die "$name: tool error: $(jq -r '.content[0].text // ""' <<<"$result" | head -c 300)"
  fi
  jq -c '.structuredContent.result // (.content[0].text | fromjson)' <<<"$result"
}

initialize() {
  local params
  params="$(jq -cn --arg version "$PROTOCOL_VERSION" \
    '{protocolVersion: $version, capabilities: {}, clientInfo: {name: "bm-verify", version: "1"}}')"
  rpc 1 initialize "$params" >/dev/null
  SESSION_ID="$(grep -i '^mcp-session-id:' "$WORK_DIR/headers" | cut -d: -f2- | tr -d ' \r' || true)"
  log "initialized (session $(mask "${SESSION_ID:-none}"))"
  notify notifications/initialized
}

check_tools() {
  local result names tool
  result="$(rpc 2 tools/list '{}')" || exit 1
  names="$(jq -r '.tools[].name' <<<"$result")"
  for tool in $REQUIRED_TOOLS; do
    grep -qx "$tool" <<<"$names" \
      || die "tools/list: missing tool '$tool' (did the Basic Memory image change? see compose.yaml)"
  done
  log "tools/list ok"
}

check_write() {
  local title="$1" content="$2" arguments payload
  arguments="$(jq -cn --arg title "$title" --arg content "$content" --arg directory "$VERIFY_DIRECTORY" \
    '{title: $title, content: $content, directory: $directory, output_format: "json"}')"
  payload="$(call_tool 3 write_note "$arguments")" || exit 1
  [[ "$(jq -r '.action' <<<"$payload")" == created ]] || die "write_note: expected action=created, got $payload"
  NOTE_WRITTEN="$title"
  log "write_note ok ($VERIFY_DIRECTORY/$title)"
}

check_read() {
  local title="$1" marker="$2" payload
  payload="$(call_tool 4 read_note "$(jq -cn --arg id "$title" '{identifier: $id, output_format: "json"}')")" || exit 1
  jq -e --arg marker "$marker" '.content | contains($marker)' <<<"$payload" >/dev/null \
    || die "read_note: content of '$title' does not contain '$marker'"
  log "read_note ok"
}

check_delete() {
  local title="$1" payload
  payload="$(call_tool 5 delete_note "$(jq -cn --arg id "$title" '{identifier: $id, output_format: "json"}')")" || exit 1
  [[ "$(jq -r '.deleted' <<<"$payload")" == true ]] || die "delete_note: '$title' was not deleted: $payload"
  NOTE_WRITTEN=""
  log "delete_note ok"
}

cleanup() {
  local exit_code=$?
  if [[ -n "$NOTE_WRITTEN" ]]; then
    log "cleanup: deleting leftover note '$NOTE_WRITTEN'"
    (check_delete "$NOTE_WRITTEN") \
      || log "WARNING: could not delete '$NOTE_WRITTEN'; remove it from the $VERIFY_DIRECTORY/ folder by hand"
  fi
  rm -rf "$WORK_DIR"
  exit "$exit_code"
}

main() {
  parse_args "$@"
  require_cmd curl jq
  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT
  local title="bm-verify-$VERIFY_ID" marker="bm-verify marker $VERIFY_ID"
  step "MCP round trip against $URL${HOST_HEADER:+ (Host: $HOST_HEADER)}"
  initialize
  check_tools
  check_write "$title" "$marker"
  check_read "$title" "$marker"
  check_delete "$title"
  log "OK: MCP round trip passed"
}

main "$@"
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `make test`
Expected: PASS(`verify_mcp.bats` 15개 포함, 총 37 tests).

- [ ] **Step 7: Makefile에 `local-verify` 추가**

`.PHONY`에 `local-verify`를 추가하고, 파일 끝에 다음을 붙인다.
```make
local-verify: ## Verify the local MCP endpoint (plain and *.ts.net Host header)
	scripts/verify-mcp.sh "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-mcp.sh --host-header bm-node.example.ts.net "http://127.0.0.1:$(BM_PORT)/mcp"
```

- [ ] **Step 8: 실제 컨테이너로 확인 (통합, macOS bash 3.2)**

Run: `make local-up local-verify && docker stats --no-stream --format '{{.MemUsage}}' basic-memory-server && make local-down`
Expected:
- `OK: MCP round trip passed`가 두 번 출력된다(두 번째 줄 앞에 `(Host: bm-node.example.ts.net)`).
- 메모리 수치(예: `~450MiB`)를 이 계획의 Progress log에 `Verified`로 기록한다.

- [ ] **Step 9: Commit**

Run: `make check` (PASS, 커버리지 80% 이상)
```bash
git add scripts/verify-mcp.sh tests/stubs/curl tests/fixtures tests/verify_mcp.bats Makefile
git commit -m "feat: add end-to-end MCP verification script and local-verify target"
```

---

### Task 4: VM 부트스트랩 (`remote/bootstrap.sh`, `bootstrap-vm.sh`)

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
Expected: PASS(총 50 tests).

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

### Task 5: 배포, 검증, 상태, 로그 (`deploy`, `verify-vm`, `status`, `logs`)

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
  - `scripts/verify-vm.sh`: Task 6의 `restore` 레시피도 호출한다.
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
Expected: PASS(총 66 tests).

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

### Task 6: 백업과 복원

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
Expected: PASS(총 76 tests).

- [ ] **Step 6: Makefile에 백업과 복원 타깃 추가**

`.PHONY`에 `backup restore`를 추가하고, 파일 끝에 다음을 붙인다.
```make
backup: ## Download a consistent backup of VM data into backups/ (brief container stop)
	scripts/backup.sh

restore: ## Restore BACKUP=backups/bm-<stamp>.tgz to the VM (asks for yes), then verify
	scripts/restore.sh "$(BACKUP)"
	scripts/verify-vm.sh
```

- [ ] **Step 7: Commit**

Run: `make check` (PASS)
```bash
git add scripts/backup.sh scripts/restore.sh tests/backup_restore.bats Makefile
git commit -m "feat: add VM backup and restore with checksum and confirmation"
```

---

### Task 7: 에이전트 지침과 저장소 전용 스킬

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`
- Create: `.agents/skills/bm-upgrade/SKILL.md`, `.agents/skills/bm-recover/SKILL.md`, `.agents/skills/bm-diagnose/SKILL.md`
- Create (symlink): `.claude/skills/bm-upgrade`, `.claude/skills/bm-recover`, `.claude/skills/bm-diagnose`
- Test: `tests/repo.bats`(에이전트와 스킬 테스트 추가)

**Interfaces:**
- Consumes: 모든 Make 타깃 이름(Task 1~6)
- Produces: 스킬 이름 `bm-upgrade`, `bm-recover`, `bm-diagnose`. Task 8의 `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`에는 "Incident log" 섹션이 있어야 한다(`bm-recover`가 참조).

- [ ] **Step 1: 실패하는 테스트 추가 (`tests/repo.bats` 끝에 append)**

```bash
skill_dirs() {
  find "$REPO_DIR/.agents/skills" -mindepth 1 -maxdepth 1 -type d | sort
}

frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1"
}

@test "AGENTS.md stays a short map (at most 100 lines)" {
  local lines
  lines="$(wc -l <"$REPO_DIR/AGENTS.md")"
  ((lines <= 100)) || fail "AGENTS.md has $lines lines; move detail into docs/ and point to it"
}

@test "CLAUDE.md only imports AGENTS.md" {
  run cat "$REPO_DIR/CLAUDE.md"
  assert_output "@AGENTS.md"
}

@test "at least one repository skill exists" {
  run skill_dirs
  assert_success
  refute_output ""
}

@test "skills use only Agent Skills standard frontmatter keys" {
  local dir key bad=""
  for dir in $(skill_dirs); do
    for key in $(frontmatter "$dir/SKILL.md" | grep -oE '^[a-z-]+:' | tr -d ':'); do
      case "$key" in
        name | description | license | compatibility | metadata | allowed-tools) ;;
        *) bad="$bad $(basename "$dir"):$key" ;;
      esac
    done
  done
  [[ -z "$bad" ]] || fail "non-standard frontmatter keys (Codex/Antigravity may reject them):$bad"
}

@test "skill names match their directories and have descriptions" {
  local dir name
  for dir in $(skill_dirs); do
    name="$(frontmatter "$dir/SKILL.md" | sed -n 's/^name: *//p')"
    [[ "$name" == "$(basename "$dir")" ]] || fail "$dir/SKILL.md: name '$name' must equal the directory name"
    frontmatter "$dir/SKILL.md" | grep -qE '^description: .+' || fail "$dir/SKILL.md: add a description"
  done
}

@test "every skill is linked for Claude Code under .claude/skills" {
  local dir name link
  for dir in $(skill_dirs); do
    name="$(basename "$dir")"
    link="$REPO_DIR/.claude/skills/$name"
    [[ -L "$link" ]] || fail "missing link; run: ln -s ../../.agents/skills/$name .claude/skills/$name"
    [[ "$(readlink "$link")" == "../../.agents/skills/$name" ]] || fail "$link must point to ../../.agents/skills/$name"
  done
}

@test "every SKILL.md is at most 500 lines" {
  local dir lines
  for dir in $(skill_dirs); do
    lines="$(wc -l <"$dir/SKILL.md")"
    ((lines <= 500)) || fail "$dir/SKILL.md has $lines lines; move reference material into separate files"
  done
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `AGENTS.md`, `CLAUDE.md`, `.agents/skills`가 없어서 실패한다.

- [ ] **Step 3: `AGENTS.md`와 `CLAUDE.md` 작성**

`AGENTS.md`:
```markdown
# Agent instructions

This repo deploys a Basic Memory MCP server on an OCI Always Free VM that is reachable only inside a Tailscale tailnet.
Read first: `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md`, then `docs/ARCHITECTURE.md`.
Active work: `docs/plans/active/`.

## Commands
- `make help` lists every target. Do lifecycle work through Make targets only; use raw `docker compose` or `ssh` only to diagnose a failing target, and record why.
- `make check` (lint + all tests + coverage >= 80%) must pass before every commit. `make fmt` fixes shfmt findings.
- Local: `make local-up local-verify local-down`. VM: `make deploy verify status logs backup restore`.

## Invariants (enforced by tests/repo.bats; never weaken a test to make it pass)
- Basic Memory has no auth: publish its port on `127.0.0.1` only, never enable Tailscale Funnel, keep zero public ingress on the VM.
- Pin container images by digest. Upgrade Basic Memory only through the `bm-upgrade` skill.
- Scripts: `#!/usr/bin/env bash` then `set -euo pipefail`; source `scripts/lib/common.sh`; fail with an actionable message via `die`.
- Scripts must run on macOS bash 3.2: no `mapfile`, associative arrays, `${x,,}`, `inherit_errexit`, or empty array expansion. After `x="$(fn)"` where `fn` can fail, add `|| exit 1`.
- Name constants instead of magic numbers. Never print secrets or session ids; use `mask`.
- Write the bats test first (tests/*.bats; fake commands live in tests/stubs/, recorded MCP responses in tests/fixtures/).

## Safety
- Never commit secrets, `.env`, Tailscale auth keys, `backups/`, `.local-data/`, or note content.
- The only secret is the Tailscale auth key. It reaches the VM via `TS_AUTHKEY` or the hidden prompt, never via a file in the repo or a command argument.
- Ask the user before anything that changes the VM or cloud resources: `vm-bootstrap`, `deploy`, `restore`, resizing, OCI security rules, Tailscale policy.
- Never delete `backups/` or `/srv/basic-memory.prev-*` directories.

## Notes and language
- Label repository notes `Verified`, `Command`, `Assumption`, or `Open question`.
- Code, comments, script messages, this file and skills are English. README, runbooks, ARCHITECTURE and ADRs are Korean.
- Record evidence (command + result) in the active plan's Progress log or an ADR in `docs/decisions/`.

## Map
- `scripts/` lifecycle scripts; `scripts/remote/` runs on the VM; `scripts/lib/common.sh` shared helpers.
- `tests/` bats tests; `tools/` test image and coverage gate.
- `docs/runbooks/` accounts, VM creation, bootstrap, operations (incident log).
- `docs/specs/`, `docs/plans/{active,completed}/`, `docs/decisions/`.
- `.agents/skills/` skills for Codex and Antigravity; `.claude/skills/<name>` symlinks for Claude Code.

## Skills
- `bm-upgrade`: bump the pinned Basic Memory image and roll it out safely.
- `bm-recover`: rebuild after the VM is reclaimed or broken, then restore the latest backup.
- `bm-diagnose`: read-only troubleshooting of MCP, Tailscale and container problems.
```

`CLAUDE.md` (한 줄, 끝 줄바꿈 포함):
```markdown
@AGENTS.md
```

- [ ] **Step 4: `.claude/settings.json` 작성**

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(make help)",
      "Bash(make lint)",
      "Bash(make fmt)",
      "Bash(make test)",
      "Bash(make coverage)",
      "Bash(make check)",
      "Bash(make local-verify)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./backups/**)",
      "Read(./.local-data/**)"
    ]
  }
}
```

- [ ] **Step 5: 스킬 작성**

`.agents/skills/bm-upgrade/SKILL.md`:
```markdown
---
name: bm-upgrade
description: Upgrade the pinned Basic Memory container image (version and digest) and roll it out to the VM safely. Use when asked to update, bump or patch Basic Memory.
---

# Upgrade Basic Memory

This changes what runs against real notes. Follow the steps in order and ask the user before step 6.

1. Current pin: `grep 'image:' compose.yaml`. Keep this line for rollback.
2. Pick the target release on https://github.com/basicmachines-co/basic-memory/releases. Read the notes between the current and target versions for changes to: the `mcp` CLI flags (`--transport streamable-http --path /mcp`), `BASIC_MEMORY_*` env vars, data paths (`/app/data`, `/home/appuser/.basic-memory`), and the tools `write_note`, `read_note`, `search_notes`, `delete_note`. Summarize them for the user.
3. Resolve the multi-arch digest (image tags have no `v` prefix) and confirm arm64 is included:
   `docker buildx imagetools inspect ghcr.io/basicmachines-co/basic-memory:<version>`
   Use the `Digest:` line of the index and check the list contains `linux/arm64`.
4. Change only the `image:` line in `compose.yaml` to `ghcr.io/basicmachines-co/basic-memory:<version>@<digest>`.
5. Verify locally: `make check local-up local-verify`, then `make local-down`. If anything fails, stop and report; do not deploy.
6. Ask the user to approve the rollout, then run `make backup deploy verify status`.
7. If `deploy` or `verify` fails: put the old `image:` line back and run `make deploy verify`. If notes look damaged, restore the backup from step 6 with `make restore BACKUP=<file>` (user types yes).
8. Commit `compose.yaml` as `chore: upgrade basic-memory to <version>` and record the outcome (Verified/Command) in the active plan or a new ADR.
```

`.agents/skills/bm-recover/SKILL.md`:
```markdown
---
name: bm-recover
description: Rebuild the Basic Memory VM after OCI reclaims it or it becomes unusable, then restore the latest backup. Use when the VM is terminated, permanently unreachable, or its data is corrupted.
---

# Recover the Basic Memory VM

Each step changes cloud resources or data. Confirm with the user before steps 3, 5 and 6.

1. Confirm the VM is really gone: `make status` fails and the user sees the instance stopped or terminated in the OCI console. For anything transient, use `bm-diagnose` instead.
2. Choose the newest backup with a checksum: `ls -t backups/bm-*.tgz | head -n 1` and check `<file>.sha256` exists. If there is none, tell the user the notes cannot be restored and continue with an empty VM only if they agree.
3. The user creates a new VM following `docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md` (temporary port 22 rule) and removes the old `bm-node` machine in the Tailscale admin console so the new VM can take the name. Ask for the new public IP and update `BM_VM_PUBLIC_IP` in `.env`.
4. The user creates a new one-off auth key (`docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md`). Run `make vm-bootstrap HOST=<new-public-ip>`; the user pastes the key at the prompt.
5. Check `ssh ubuntu@bm-node true`, then ask the user to delete the port 22 ingress rule.
6. Run `make deploy`, then `make restore BACKUP=<file from step 2>`; the user types yes and the target runs verify.
7. Run `make status` and add a row to "Incident log" in `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md` (date, cause, backup used, data loss window).
```

`.agents/skills/bm-diagnose/SKILL.md`:
```markdown
---
name: bm-diagnose
description: Read-only troubleshooting for the Basic Memory MCP endpoint, Tailscale Serve, Tailscale SSH and the VM container. Use when an agent cannot reach Basic Memory, make verify fails, or the VM seems unhealthy.
---

# Diagnose Basic Memory

Read-only: do not deploy, restart, restore or change any setting while diagnosing. Propose the fix to the user.

Work top-down and stop at the first layer that fails:

1. Tailnet: `tailscale status | grep bm-node` on this machine. Missing or offline: the VM is down or logged out; check the OCI console (terminated means `bm-recover`).
2. SSH: `ssh ubuntu@bm-node true`. Failing while the tailnet is fine: check the Tailscale policy `ssh` rule for `tag:bm-server` (docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md).
3. Container: `make status`. Not `(healthy)`: run `make logs` and quote the first error.
4. Memory warning from `make status`: idle-reclaim risk; see "Idle reclamation" in docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md.
5. Serve: `make status` must show `proxy http://127.0.0.1:8737`. Missing: bootstrap step `configure_serve` did not run.
6. MCP: `make verify` and read the failing step:
   - `initialize: request ... failed`: DNS or HTTPS; check MagicDNS and HTTPS certificates in the Tailscale admin console.
   - `initialize: HTTP 4xx`: Host header or path; compare with `make local-up local-verify`.
   - `tools/list: missing tool`: the image changed; see `bm-upgrade`.
   - `write_note` or `read_note` errors: data permissions (`ssh ubuntu@bm-node ls -ln /srv/basic-memory`, owner must be 1000) or a full disk (`ssh ubuntu@bm-node df -h /srv`).
7. Report the failing layer, the evidence (command and output excerpt) and the proposed fix.
```

- [ ] **Step 6: Claude Code용 스킬 링크 생성**

Run:
```bash
mkdir -p .claude/skills
ln -s ../../.agents/skills/bm-upgrade .claude/skills/bm-upgrade
ln -s ../../.agents/skills/bm-recover .claude/skills/bm-recover
ln -s ../../.agents/skills/bm-diagnose .claude/skills/bm-diagnose
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 83 tests).

- [ ] **Step 8: Commit**

Run: `make check` (PASS)
```bash
git add AGENTS.md CLAUDE.md .claude/settings.json .claude/skills .agents tests/repo.bats
git commit -m "docs: add agent instructions and repo skills for upgrade, recovery and diagnosis"
```

---

### Task 8: 사람용 문서 (README, 아키텍처, 런북, ADR)

**Files:**
- Create: `README.md`, `docs/ARCHITECTURE.md`
- Create: `docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md`, `docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md`, `docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md`, `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`
- Create: `docs/decisions/adr-2026-10-12-b229z2y6-basic-memory-on-oci-tailscale.md`, `docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md`
- Test: `tests/repo.bats`(Markdown 링크 검사 추가)

**Interfaces:**
- Consumes: Make 타깃 이름, 스킬 이름, 스펙의 사실 목록
- Produces: `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`의 "Idle reclamation"과 "Incident log" 섹션(`status.sh`, `bm-recover`, `bm-diagnose`가 참조)

- [ ] **Step 1: 실패하는 테스트 추가 (`tests/repo.bats` 끝에 append)**

```bash
markdown_files() {
  git -C "$REPO_DIR" ls-files --cached --others --exclude-standard -- '*.md'
}

@test "relative links in markdown files resolve" {
  local file link target broken=""
  while IFS= read -r file; do
    while IFS= read -r link; do
      link="${link%%#*}"
      if [[ -z "$link" ]]; then
        continue
      fi
      target="$(cd "$REPO_DIR/$(dirname "$file")" && realpath -m "$link")"
      [[ -e "$target" ]] || broken="$broken $file->$link"
    done < <(awk '/^```/ { fence = !fence; next } !fence' "$REPO_DIR/$file" \
      | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\((.*)\)$/\1/' | grep -vE '^(https?:|mailto:)' || true)
  done < <(markdown_files)
  [[ -z "$broken" ]] || fail "broken relative links:$broken"
}

@test "runbooks contain the sections scripts and skills point to" {
  run grep -E '^## (Idle reclamation|Incident log)' "$REPO_DIR/docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md"
  assert_line --partial "Idle reclamation"
  assert_line --partial "Incident log"
}
```

Run: `make test`
Expected: FAIL. `runbooks contain…`가 파일 없음으로 실패한다. 링크 테스트는 아직 링크가 없으므로 통과한다.

- [ ] **Step 2: `README.md` 작성**

````markdown
# agent-share-poc: Basic Memory on OCI + Tailscale

여러 기기의 코딩 에이전트(Codex, Claude Code, Antigravity)가 같은 기억을 쓰도록, Basic Memory MCP 서버를 OCI Always Free VM에 올리고 Tailscale tailnet 안에서만 접근하게 만드는 저장소입니다.

- 설계: [docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md](docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md)
- 구조: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 에이전트 지침: [AGENTS.md](AGENTS.md)

## 사전 요구사항 (Prerequisites)

- macOS + Docker Desktop (실행 중이어야 함), `make`
- `ssh`, `curl`, `jq`, `nc` (`brew install jq`; 나머지는 macOS 기본 포함)
- VM 작업용: 이 Mac에 Tailscale 앱 설치·로그인 ([accounts 런북](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md))

## 빠르게 시작하기

```bash
make help                          # 전체 타깃
make check                         # lint + 테스트 + 커버리지
make local-up local-verify         # 로컬 컨테이너로 MCP 왕복 확인
make local-down
```

## VM 구축 순서

1. [계정 준비](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md): OCI, Tailscale, 정책, 인증 키
2. [VM 만들기](docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md): A1.Flex, Ubuntu 24.04, 임시 22번 규칙
3. [부트스트랩](docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md): `make vm-bootstrap` → 22번 규칙 삭제 → `make deploy verify status`
4. [운영](docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md): 백업, 복원, 업그레이드, 유휴 회수 대응

## 범위 밖 (다음 목표)

에이전트별 MCP 연결 설정, 자동 백업, `personal-context` GitHub 정본 연동, 회사용 별도 인스턴스
````

- [ ] **Step 3: `docs/ARCHITECTURE.md` 작성**

````markdown
# 아키텍처

## 토폴로지

```
[개인/회사 Mac] ── tailnet ──▶ https://bm-node.<tailnet>.ts.net/mcp
  에이전트, make deploy/verify/backup       │ Tailscale Serve (HTTPS, tailnet 전용)
  (Tailscale SSH)                           ▼
                                  OCI A1 VM (Ubuntu 24.04 ARM64, 공개 인바운드 0개)
                                    └ Docker: basic-memory:0.23.2@sha256
                                        127.0.0.1:8737 → :8000 /mcp
                                        /srv/basic-memory/knowledge → /app/data
                                        /srv/basic-memory/config    → /home/appuser/.basic-memory
```

## 구성 요소

| 구성 요소 | 위치 | 역할 |
|---|---|---|
| `Makefile` + `scripts/` | Mac | 유일한 제어 지점. SSH로 VM을 다룸 |
| `scripts/remote/bootstrap.sh` | VM (root) | Docker·Tailscale 설치, 데이터 디렉터리, Serve 설정 |
| `compose.yaml` | Mac(로컬 검증)·VM | Basic Memory 컨테이너 정의 (같은 파일) |
| Tailscale Serve | VM | tailnet HTTPS → `http://127.0.0.1:8737` |
| Tailscale SSH | VM | 부트스트랩 이후의 유일한 관리 경로 |
| `backups/` | Mac | `make backup` 결과물 (git ignore) |

## 데이터 경로

| 데이터 | 로컬 | VM |
|---|---|---|
| Markdown 노트 | `.local-data/knowledge/basic-memory/` | `/srv/basic-memory/knowledge/basic-memory/` |
| SQLite 인덱스·설정·임베딩 모델 캐시 | `.local-data/config/` | `/srv/basic-memory/config/` |
| compose와 `.env` | 저장소 루트 | `/opt/basic-memory/` |

기본 프로젝트 `main`은 `/app/data/basic-memory`에 생성됩니다(**Verified**, 0.23.2).

## 신뢰 경계

- Basic Memory에는 인증이 없습니다(**Verified**). 접근 제어는 전적으로 Tailscale의 기기 인증과 정책에 맡깁니다.
- 컨테이너 포트는 `127.0.0.1`에만 바인딩합니다. Funnel은 끄고, OCI 공개 인바운드 규칙은 0개입니다. `tests/repo.bats`와 `make verify`가 이를 확인합니다.
- 비밀값은 Tailscale 인증 키 하나뿐이며, 저장소와 디스크에 남지 않습니다.

## 주요 흐름

- **배포:** `make deploy` → compose와 VM용 `.env` 전송 → `docker compose pull` → `up -d --wait`
- **검증:** `make verify` → tailnet URL로 MCP 왕복(initialize, tools/list, 쓰기·읽기·삭제) → VM의 포트 바인딩 확인 → (`BM_VM_PUBLIC_IP` 설정 시) 공인 포트가 닫혔는지 확인
- **백업:** `make backup` → 컨테이너 정지 → `/srv/basic-memory`를 tar로 받아옴 → 컨테이너 재시작 → sha256 저장

관련 결정: [basic-memory-on-oci-tailscale ADR](decisions/adr-2026-10-12-b229z2y6-basic-memory-on-oci-tailscale.md), [vm-sizing ADR](decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)
````

- [ ] **Step 4: `docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md` 작성**

````markdown
# 계정 준비: OCI와 Tailscale

## 1. OCI 가입

1. https://signup.cloud.oracle.com 에서 가입합니다. **Assumption:** 본인 확인용 카드 등록이 필요합니다(Always Free 자원만 쓰면 과금되지 않음).
2. **홈 리전은 나중에 바꿀 수 없습니다**(**Verified**). 한국 리전은 `ap-seoul-1`(서울)과 `ap-chuncheon-1`(춘천)이며, 둘 다 가용 도메인(AD)이 1개입니다. A1 용량이 부족하면 VM 생성이 실패할 수 있습니다.
3. Pay As You Go로 업그레이드하지 않습니다. 업그레이드 계정에 유휴 회수 정책이 적용되는지는 **Open question**입니다.

## 2. Tailscale 가입

1. https://login.tailscale.com/start 에서 **개인 계정**으로 가입합니다. 회사 도메인 이메일로 가입하면 tailnet이 회사 소유가 됩니다(**Verified**).
2. **Open question:** 회사 Mac을 개인 tailnet에 참여시키는 것이 회사 보안 정책과 Tailscale Personal 약관(비상업 용도)에 맞는지 직접 확인하세요.
3. 이 Mac에 Tailscale 앱을 설치하고 로그인합니다(`brew install --cask tailscale` 또는 App Store).

## 3. DNS와 HTTPS

Admin console → **DNS**에서 다음을 켭니다.
- **MagicDNS**
- **HTTPS Certificates**: 인증서가 발급된 기기 이름은 공개 Certificate Transparency 로그에 기록됩니다(**Verified**). 그래서 기기 이름을 일반적인 `bm-node`로 씁니다.

tailnet DNS 이름(예: `tail1234.ts.net`)을 `.env`의 `BM_TAILNET_DOMAIN`에 적습니다.

## 4. 접근 정책 (Access controls)

Admin console → **Access controls**에서 정책 파일을 편집합니다.

1. `tagOwners`에 서버 태그를 추가합니다.
2. `ssh`에 태그 서버로의 접속 규칙을 추가합니다. 기본 규칙의 `autogroup:self`는 태그가 붙은 기기를 포함하지 않으므로 별도 규칙이 필요합니다.
3. **Funnel을 끕니다**: 기본 정책의 `nodeAttrs`에서 `"funnel"` 속성을 지웁니다(**Verified:** Funnel은 기본으로 켜져 있음).

```json
{
  "tagOwners": {
    "tag:bm-server": ["autogroup:admin"]
  },
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:bm-server"],
      "users": ["ubuntu"]
    }
  ]
}
```

**Assumption:** 이 조각은 기존 정책 파일의 해당 섹션에 합쳐 넣는 것입니다. 저장할 때 편집기가 문법을 검증하니, 오류가 나면 메시지대로 고치세요.

## 5. 인증 키 (부트스트랩 직전에 발급)

Settings → **Keys** → **Generate auth key**:
- Reusable: **끔** (1회용)
- Ephemeral: **끔** (서버는 계속 유지)
- Pre-approved: **켬**
- Tags: `tag:bm-server`
- Expiration: 1일

키는 어디에도 저장하지 말고, `make vm-bootstrap` 프롬프트에 붙여 넣습니다.
````

- [ ] **Step 5: `docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md` 작성**

````markdown
# VM 만들기 (OCI 콘솔)

## 1. SSH 키

키가 없으면 만듭니다: `ssh-keygen -t ed25519`. 공개키는 `~/.ssh/id_ed25519.pub`입니다.

## 2. 인스턴스 생성

Compute → Instances → **Create instance**:

| 항목 | 값 |
|---|---|
| Name | `bm-node` |
| Image | Canonical Ubuntu 24.04 (**Minimal 아님**, aarch64) |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU / 4 GB ([the vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)) |
| Networking | 새 VCN + public subnet, public IPv4 할당 |
| SSH keys | 1단계의 공개키 업로드 |
| Boot volume | 기본 50 GB |

A1 무료 한도는 합계 2 OCPU / 12 GB, 블록 볼륨 합계 200 GB입니다(**Verified**). 한도를 넘기지 마세요.

"Out of capacity" 오류가 나면 시간대를 바꿔 다시 시도합니다(서울·춘천 리전은 AD가 1개뿐).

## 3. 임시 SSH 규칙

Networking → VCN → Security Lists → Default security list → Ingress rules:
- 22번 규칙의 Source를 **본인 IP/32**로 바꿉니다(`curl -s https://ifconfig.me`로 확인). **Assumption:** 기본 보안 목록에는 `0.0.0.0/0`의 22번 허용 규칙이 있습니다.
- 22번 외의 인바운드 규칙은 추가하지 않습니다. 8737과 443은 열지 않습니다.

## 4. 기록

인스턴스의 Public IPv4를 `.env`의 `BM_VM_PUBLIC_IP`에 적고, [부트스트랩](rbk-2026-10-12-ha5w72pm-bootstrap.md)으로 넘어갑니다.
````

- [ ] **Step 6: `docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md` 작성**

````markdown
# 부트스트랩: VM을 tailnet에 올리고 배포하기

## 준비

```bash
cp .env.example .env    # BM_TAILNET_DOMAIN, BM_VM_PUBLIC_IP 채우기
```

[accounts 런북 5단계](rbk-2026-10-12-hqxjjqy8-accounts.md)대로 1회용 인증 키를 발급해 둡니다.

## 순서

1. `make vm-bootstrap HOST=<공인 IP>` → 프롬프트에 인증 키를 붙여 넣습니다(화면에 표시되지 않음).
   - Docker·Tailscale 설치, tailnet 참여(`bm-node`, Tailscale SSH), 데이터 디렉터리 생성, Serve 설정까지 합니다.
   - 여러 번 실행해도 안전합니다.
2. `ssh ubuntu@bm-node true` → Tailscale SSH로 접속되는지 확인합니다.
3. **2단계가 성공한 뒤에만** OCI 콘솔에서 22번 인바운드 규칙을 삭제합니다. 이제 공개 인바운드가 0개입니다.
4. `make deploy verify status`

## 완료 조건

- [ ] `make verify`가 `OK: MCP round trip passed`, `listens on 127.0.0.1 only`, `refuses ports 22 and 8737`을 모두 출력한다.
- [ ] `make status`에 `(healthy)`, `proxy http://127.0.0.1:8737`이 보인다.
- [ ] `make backup`이 `backups/bm-*.tgz`와 `.sha256`을 만든다.

## 문제 해결

| 증상 | 확인 |
|---|---|
| `upload failed` | 공인 IP, SSH 키, 22번 규칙의 Source IP |
| `tailscale up failed` | 키 만료·재사용 여부, Pre-approved, `tag:bm-server`의 `tagOwners` |
| `ssh ubuntu@bm-node` 실패 | 정책의 `ssh` 규칙([accounts 4단계](rbk-2026-10-12-hqxjjqy8-accounts.md)) |
| 22번을 지운 뒤 접속 불가 | OCI 콘솔 → 인스턴스 → **Console connection**(시리얼 콘솔)으로 들어가 `sudo tailscale status` 확인 |
````

- [ ] **Step 7: `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md` 작성**

````markdown
# 운영

## 일상 명령

| 목적 | 명령 |
|---|---|
| 상태 점검 (주 1회) | `make status` |
| 종단 검증 | `make verify` |
| 로그 | `make logs` |
| 배포 (compose 변경 후) | `make deploy verify` |
| 백업 (주 1회 + 업그레이드 전) | `make backup` |
| 복원 | `make restore BACKUP=backups/bm-<시각>.tgz` (`yes` 입력 필요, 끝나면 verify 실행) |

## 백업

- 결과물은 이 Mac의 `backups/`에만 있습니다(git ignore). Time Machine 등으로 Mac 밖에도 사본을 두세요.
- 백업 중에는 컨테이너가 몇 초 멈춥니다. SQLite 파일이 쓰는 도중에 복사되지 않게 하기 위해서입니다.
- 복원하면 기존 데이터는 `/srv/basic-memory.prev-<시각>`으로 옮겨집니다. 복원 결과를 확인한 뒤에만 직접 지우세요: `ssh ubuntu@bm-node sudo rm -r /srv/basic-memory.prev-<시각>`

## 업그레이드·복구·진단

에이전트에게 스킬을 쓰라고 요청합니다.
- 업그레이드: `bm-upgrade`
- VM 회수·손상 후 복구: `bm-recover`
- 연결·MCP 문제: `bm-diagnose`

## Idle reclamation

OCI는 7일 동안 CPU(95번째 백분위), 네트워크, 메모리(A1만 해당)가 **모두** 20% 미만인 Always Free VM을 회수할 수 있습니다(**Verified**).

- `make status`가 메모리 사용률 20% 미만 경고를 내면, 최신 백업이 있는지 먼저 확인하세요.
- VM 크기는 평소 메모리 사용률이 20%를 넘도록 정했습니다([vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)). 경고가 계속되면 vm-sizing ADR의 재평가 기준을 따르세요.
- 회수 알림 메일을 받거나 VM이 사라지면 `bm-recover` 스킬을 씁니다.

## Incident log

| 날짜 | 원인 | 사용한 백업 | 데이터 손실 구간 | 비고 |
|---|---|---|---|---|
````

- [ ] **Step 8: ADR 작성**

`docs/decisions/adr-2026-10-12-b229z2y6-basic-memory-on-oci-tailscale.md`:
```markdown
# ADR b229z2y6: Basic Memory를 OCI Always Free + Tailscale에 자체 호스팅

- 상태: Accepted (2026-10-07)
- 출처: [설계 스펙](../specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md)

## 맥락

여러 기기의 에이전트가 같은 Basic Memory를 써야 합니다. 비용은 0원이어야 하고, Basic Memory HTTP 엔드포인트에는 인증이 없습니다(**Verified**).

## 결정

- OCI Always Free A1 VM에서 Docker로 Basic Memory를 실행하고, Tailscale Serve로 tailnet 안에만 노출합니다.
- VM은 콘솔에서 수동으로 만들고, 나머지는 이 저장소의 스크립트와 Make 타깃으로 처리합니다.
- 공인 SSH는 부트스트랩에만 쓰고 이후 Tailscale SSH로 전환하며, 공개 인바운드 규칙을 0개로 둡니다.

## 대안

- **GCP e2-micro:** RAM이 1 GB이고 무료 리전이 미국뿐이라 지연이 큽니다.
- **AWS:** 신규 계정 무료 기간이 최대 6개월입니다.
- **Koyeb Free:** 영구 볼륨을 쓸 수 없습니다.
- **Basic Memory Cloud:** MCP 엔드포인트에 유료 구독이 필요합니다.

## 결과

- 유휴 회수 위험이 있습니다 → 메모리 사용률 기준으로 크기를 정하고([vm-sizing ADR](adr-2026-10-12-mdq5exsf-vm-sizing.md)), 백업·복원 경로를 둡니다.
- Tailscale 계정이 단일 장애점이 됩니다. 대신 인증 없는 엔드포인트가 인터넷에 노출되지 않습니다.
```

`docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md`:
```markdown
# ADR mdq5exsf: VM 크기 (A1.Flex 1 OCPU / 4 GB)

- 상태: Proposed (2026-10-07). Task 10에서 VM 실측 후 Accepted로 바꿉니다.

## 맥락

OCI는 CPU(p95), 네트워크, 메모리가 **모두** 20% 미만이면 Always Free VM을 회수할 수 있습니다. 개인용 MCP 서버는 CPU와 네트워크가 거의 항상 20% 미만이므로, 회수를 피하려면 메모리 사용률을 20% 이상으로 유지해야 합니다.

## 근거

- **Verified (2026-10-07, Command: `docker stats --no-stream`):** 0.23.2 컨테이너 메모리 사용량은 기동 직후 212 MiB, `search_notes` 실행으로 임베딩 모델이 올라간 뒤 449 MiB입니다(Mac Docker Desktop 기준).
- **Assumption:** Ubuntu 24.04 + Docker + tailscaled 기본 사용량은 약 400~500 MB입니다. VM 실측(`make status`)으로 확인합니다.
- 추정 사용률: 4 GB에서 약 22~25%, 6 GB에서 약 15%(20% 미만이라 회수 위험)

## 결정

1 OCPU / 4 GB로 시작합니다. 무료 한도(2 OCPU / 12 GB) 안입니다.

## 재평가 기준

- 배포 24시간 뒤 `make status`의 메모리 사용률이 **25% 미만**이면, 콘솔에서 3 GB로 줄입니다(재시작 필요). 그 후 다시 측정합니다.
- 메모리 사용률이 **80% 이상**이면 6 GB로 늘리고, 회수 위험은 백업 주기로 보완합니다.
- 측정 결과를 이 ADR에 Verified로 추가하고 상태를 Accepted로 바꿉니다.
```

- [ ] **Step 9: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 85 tests). 링크 테스트가 README, ARCHITECTURE, 런북, ADR의 상대 링크를 모두 확인한다.

- [ ] **Step 10: Commit**

Run: `make check` (PASS)
```bash
git add README.md docs/ARCHITECTURE.md docs/runbooks docs/decisions tests/repo.bats
git commit -m "docs: add README, architecture, runbooks and ADRs"
```

---

### Task 9: 로컬 전체 검증

**Files:**
- Modify: 이 계획 파일의 Progress log

**Interfaces:**
- Consumes: Task 1~8의 모든 타깃
- Produces: 로컬 증거 기록(Verified/Command)

- [ ] **Step 1: 깨끗한 상태에서 전체 검사**

Run: `git status --short && make check`
Expected:
- `git status`는 아무것도 출력하지 않는다.
- `make check`가 PASS하고, 커버리지 출력에 `scripts/` 아래 실행 스크립트 9개(`bootstrap-vm`, `remote/bootstrap`, `verify-mcp`, `verify-vm`, `deploy`, `status`, `logs`, `backup`, `restore`)와 `lib/common.sh`가 모두 나오며, 전체가 80% 이상이다.

- [ ] **Step 2: 로컬 종단 검증과 재시작 내구성**

Run: `make local-up local-verify && docker restart basic-memory-server && sleep 20 && make local-verify && make local-down`
Expected: `OK: MCP round trip passed`가 네 번 출력된다(재시작 전 2번, 후 2번).

- [ ] **Step 3: Progress log에 기록하고 커밋**

이 파일 맨 아래 Progress log에 날짜, 명령, 결과(테스트 수, 커버리지 %, 메모리)를 `Verified`로 추가한다.
```bash
git add docs/plans/plan-2026-10-07-c9byb5z1-basic-memory-oci-tailscale.md
git commit -m "docs: record local verification evidence"
```

---

### Task 10: VM 실제 배포 (사용자와 함께, 수동 E2E)

**Files:**
- Modify: `.env`(로컬 전용, 커밋하지 않음)
- Modify: `docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md`, 이 계획 파일의 Progress log, 스펙의 Open question 해소 내용
- Move: 이 계획 → `docs/plans/completed/`

**Interfaces:**
- Consumes: 런북 4개, 모든 VM 타깃
- Produces: 스펙 §1 완료 조건 1~4의 증거

이 Task는 사용자 계정과 클라우드 자원을 다룹니다. **각 단계 전에 사용자 확인을 받습니다.** 에이전트는 사용자 대신 콘솔 작업을 하지 않습니다.

- [ ] **Step 1 (사용자):** `docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md` 1~4단계를 완료한다. 에이전트는 정책 JSON 편집을 함께 검토한다.
- [ ] **Step 2 (사용자):** `docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md`대로 VM을 만들고, `.env`에 `BM_TAILNET_DOMAIN`과 `BM_VM_PUBLIC_IP`를 채운다.
- [ ] **Step 3 (사용자 확인 후 실행):** 인증 키를 발급한 뒤 `make vm-bootstrap HOST=<공인 IP>`를 실행한다. 사용자가 프롬프트에 키를 붙여 넣는다.
  Expected: `[bootstrap] done`과 Next steps 안내.
  **Assumption 확인:** `tailscale set --hostname --ssh`가 동작하는지 같은 명령을 한 번 더 실행해 본다(멱등성 확인). 두 번째 실행은 키 없이 `already on the tailnet`으로 끝나야 한다.
- [ ] **Step 4:** `ssh ubuntu@bm-node true` 성공을 확인한다. → (사용자) OCI 22번 인바운드 규칙을 삭제한다.
- [ ] **Step 5 (사용자 확인 후):** `make deploy verify status`
  Expected: 완료 조건 1과 2 충족(`OK: MCP round trip passed`, `listens on 127.0.0.1 only`, `refuses ports 22 and 8737`).
- [ ] **Step 6:** `make backup` → `make restore BACKUP=<방금 파일>`(사용자가 `yes` 입력)
  Expected: 완료 조건 3 충족(restore 뒤 verify 통과).
- [ ] **Step 7 (사용자 확인 후):** `ssh ubuntu@bm-node sudo reboot` → 2분 대기 → `make verify status`
  Expected: 재부팅 뒤에도 통과한다(Review Focus 5).
- [ ] **Step 8:** 24시간 뒤 `make status`의 메모리 사용률을 측정한다. [vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)의 재평가 기준대로 크기를 유지하거나 조정하고, Verified로 기록한 뒤 상태를 Accepted로 바꾼다.
- [ ] **Step 9:** 스펙 §3의 Open question 중 해소된 것을 Verified로 바꾼다. Progress log에 Step 3~8의 증거를 기록한다.
- [ ] **Step 10: Commit**
```bash
git mv docs/plans/plan-2026-10-07-c9byb5z1-basic-memory-oci-tailscale.md docs/plans/completed/
git add docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md docs/plans/completed
git commit -m "docs: record VM rollout evidence and close milestone 1"
```

---

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-07 | Verified | kcov(latest@sha256:4812…) + bats 1.14.0 조합이 실행·source된 스크립트의 라인 커버리지를 수집함 (throwaway spike) |
| 2026-10-07 | Verified | basic-memory 0.23.2 로컬 컨테이너: `Host: bm-node.example.ts.net`으로 initialize 200, write/read/delete 왕복 성공, 응답 형식은 픽스처와 같음 |
| 2026-10-07 | Verified | 컨테이너 메모리: 기동 직후 212 MiB, 시맨틱 검색 후 449 MiB (`docker stats --no-stream`) |
| 2026-10-07 | Verified | macOS `/bin/bash` 3.2.57에서 계획의 문법(`"$@"`, `local -a`, `${v:0:4}`, `${!n:-}`, `x="$(f)" \|\| …`)과 BSD sed `\{0,1\}`가 동작함 |
| 2026-10-07 | Verified | `tailscale up --auth-key=file:<path>` 지원 (tailscale.com/kb/1241) |
