---
status: completed
id: sqzn0teq
spec: docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md
---

# sqzn0teq Local Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 테스트 도구 체인과 공통 셸 라이브러리를 갖추고, Basic Memory를 로컬 Docker에서 띄워 MCP 왕복까지 자동으로 검증한다. 에이전트가 처음부터 저장소 규칙을 읽도록 `AGENTS.md` 기본판도 둔다.

**Architecture:**
- `Makefile`이 유일한 수명주기 인터페이스다.
- 테스트는 Docker 안의 bats와 kcov로 실행하고, lint는 고정 digest의 shellcheck·shfmt 이미지로 실행한다.
- `compose.yaml` 하나를 로컬과 VM이 함께 쓴다. VM 쪽은 [vm-scripts 계획](plan-2026-10-07-dry1xr43-vm-scripts.md)에서 다룬다.

**Tech Stack:** Bash(macOS 3.2 호환), GNU Make, Docker Compose, Basic Memory 0.23.2, Tailscale(Serve, SSH), bats-core 1.14.0 + bats-support/assert, kcov, shellcheck 0.11.0, shfmt 3.12.0, jq, curl

**Spec:** `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md`

**Sequence:** 계획 1/5. 다음 계획: `docs/plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md`

**Git:** 이 계획부터 `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`를 따른다. `make check-git`과 `make review`는 [git-review-tooling 계획](plan-2026-10-07-qq4h1djv-git-review-tooling.md)에서 생기므로, 이 계획은 규칙을 손으로 지키고 리뷰도 수동 명령으로 한다.

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
- Git (`docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`):
  - 이 계획은 `plan/sqzn0teq-local-foundation` 브랜치의 전용 worktree에서 진행한다. `main`에 직접 커밋하지 않고, force-push·히스토리 재작성·`git gc`를 하지 않는다.
  - 커밋 형식은 `<type>: <description>`(feat, fix, refactor, docs, test, chore)이고, 메시지 끝에 트레일러 `Assisted-by: <도구> <모델>`, `Plan: sqzn0teq`, `Task: N`을 단다. 커밋 명령은 시작 단계에서 정한 `AGENT_ID` 환경변수를 쓴다.
  - `Co-authored-by`와 `Signed-off-by`는 넣지 않는다(사용자 전역 설정과 저장소 정책).
  - 매 커밋 전에 `make check`를 실행한다. Task 1의 Step 10부터 적용한다.
- 수명주기 작업은 Make 타깃으로만 한다. raw `docker compose`나 `ssh`는 실패 진단에만 쓰고, 그 이유를 기록한다.

## Review Focus

1. **macOS bash 3.2:** 사용자는 Mac 기본 bash로 `make`를 실행한다. bash 4+ 문법이 하나라도 섞이면 이후 VM 작업이 모두 깨진다. → Task 1에서 `tests/repo.bats`에 금지 문법 검사 테스트를 추가한다.
2. **따옴표가 들어간 `.env` 값:** Make의 `include`는 `BM_VM_HOST="bm-node"`의 따옴표를 값의 일부로 읽어 호스트 이름이 깨진다. → Task 2에서 `.env.example`에 따옴표가 없는지 검사하는 테스트를 추가하고, 예시 파일에 경고 주석을 넣는다.
3. **재부팅 후 자동 복구:** 컨테이너는 `restart: unless-stopped`로 재부팅 뒤 자동으로 돌아와야 한다. → Task 2에서 restart 정책 테스트를 추가한다. 실제 VM 재부팅은 [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md)에서 확인한다.

## File Structure

```
.gitignore .editorconfig .shellcheckrc        Task 1
Makefile                                       Task 1 (Task 2, 3에서 타깃 추가)
tools/Dockerfile tools/coverage.sh             Task 1  테스트 이미지와 커버리지 게이트
scripts/lib/common.sh                          Task 1  log/step/die/require_cmd/require_env/mask/remote/remote_compose/sha256_of
tests/helpers.bash                             Task 1  setup_stubs, use_vm_env
tests/stubs/{ssh,docker}                       Task 1
tests/common.bats tests/repo.bats              Task 1 (repo.bats는 Task 2, 4에서 테스트 추가)
compose.yaml .env.example                      Task 2
scripts/verify-mcp.sh                          Task 3
tests/stubs/curl tests/fixtures/mcp-{sse,json}/ tests/verify_mcp.bats   Task 3
AGENTS.md CLAUDE.md .claude/settings.json      Task 4
```

---

### 시작: 브랜치와 worktree

- [ ] 이 계획을 진행할 에이전트를 기록한다: `export AGENT_ID="<도구> <모델 ID>"` (예: `claude-code claude-opus-5-5`). 도구 값은 `claude-code`, `codex`, `antigravity`, `gemini-cli` 중 하나다.
- [ ] 전용 worktree와 브랜치를 만든다. 한 계획 브랜치는 한 번에 한 worktree에서만 진행한다.
  - Claude Code: `claude --worktree plan-01-local-foundation`로 시작하거나 세션 안에서 worktree에 들어간 뒤 `git branch -m plan/sqzn0teq-local-foundation`
  - 그 밖의 도구: `git worktree add ../027_agent_share_poc-wt/plan-01-local-foundation -b plan/sqzn0teq-local-foundation main` 후 그 디렉터리에서 작업
- [ ] 이 계획 파일은 정책 이전에 `main`의 `docs/plans/active/`에 이미 있으므로 옮기지 않는다.

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
.review-out/
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
git commit -m "chore: add test toolchain, Makefile and shared shell library" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: sqzn0teq" --trailer "Task: 1"
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
git commit -m "feat: add Basic Memory compose service and local lifecycle targets" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: sqzn0teq" --trailer "Task: 2"
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
  - CLI: `scripts/verify-mcp.sh [--host-header HOST] [--read-only] URL`. 성공하면 0과 `OK: MCP round trip passed`, 실패하면 1과 `ERROR: <step>: <원인>`.
  - `--read-only`: initialize와 tools/list만 하고 노트를 쓰지 않는다. 성공 시 `OK: MCP read-only probe passed (no notes written)`. [vm-scripts 계획](plan-2026-10-07-dry1xr43-vm-scripts.md)의 `make probe`와 [docs-skills 계획](plan-2026-10-07-hydaxf15-docs-skills.md)의 `bm-diagnose`가 쓴다.
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

@test "read-only mode stops after tools/list and writes nothing" {
  run "$VERIFY" --read-only "$URL"
  assert_success
  assert_output --partial "OK: MCP read-only probe passed (no notes written)"
  run grep -F '"method":"tools/call"' "$STUB_LOG.requests"
  assert_failure
}

@test "rejects a missing URL" {
  run "$VERIFY"
  assert_failure
  assert_output --partial "usage: verify-mcp.sh [--host-header HOST] [--read-only] URL"
}

@test "rejects unknown options" {
  run "$VERIFY" --bogus "$URL"
  assert_failure
  assert_output --partial "usage:"
}
```

- [ ] **Step 4: 실패 확인**

Run: `make test`
Expected: FAIL. `verify_mcp.bats`의 테스트 16개가 `scripts/verify-mcp.sh: No such file or directory`로 실패한다.

- [ ] **Step 5: `scripts/verify-mcp.sh` 구현 (실행 권한 부여)**

```bash
#!/usr/bin/env bash
# End-to-end check of a Basic Memory MCP endpoint over streamable HTTP:
# initialize -> tools/list -> write_note -> read_note -> delete_note.
# --read-only stops after tools/list and writes nothing (make probe, bm-diagnose).
# Usage: verify-mcp.sh [--host-header HOST] [--read-only] URL
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
READ_ONLY=""

usage() { die "usage: verify-mcp.sh [--host-header HOST] [--read-only] URL"; }

parse_args() {
  while (($#)); do
    case "$1" in
      --host-header)
        [[ -n "${2:-}" ]] || usage
        HOST_HEADER="$2"
        shift 2
        ;;
      --read-only)
        READ_ONLY=1
        shift
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
  if [[ -n "$READ_ONLY" ]]; then
    log "OK: MCP read-only probe passed (no notes written)"
    return 0
  fi
  check_write "$title" "$marker"
  check_read "$title" "$marker"
  check_delete "$title"
  log "OK: MCP round trip passed"
}

main "$@"
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `make test`
Expected: PASS(`verify_mcp.bats` 16개 포함, 총 38 tests).

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
git commit -m "feat: add end-to-end MCP verification script and local-verify target" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: sqzn0teq" --trailer "Task: 3"
```


---

### Task 4: 에이전트 지침 기본판 (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`)

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`
- Test: `tests/repo.bats`(에이전트 지침 테스트 추가)

**Interfaces:**
- Consumes: Task 1~3의 Make 타깃 이름
- Produces: `AGENTS.md`의 섹션 구조(`Commands`, `Invariants`, `Safety`, `Git`, `Notes and language`, `Map`). [git-review-tooling 계획](plan-2026-10-07-qq4h1djv-git-review-tooling.md)은 `Code Review Rules`와 `Skills` 섹션을, [vm-scripts 계획](plan-2026-10-07-dry1xr43-vm-scripts.md)은 `Commands`에 VM 타깃 줄을, [docs-skills 계획](plan-2026-10-07-hydaxf15-docs-skills.md)은 `bm-*` 스킬 줄과 `Map` 항목을 추가한다. `.claude/settings.json`의 `attribution.commit = ""`는 Claude Code가 자동 `Co-authored-by` 트레일러를 넣지 않게 한다.

이후 계획을 구현하는 에이전트가 처음부터 저장소 규칙을 읽도록, 지금 존재하는 것만 담은 기본판을 둔다.

- [ ] **Step 1: 실패하는 테스트 추가 (`tests/repo.bats` 끝에 append)**

```bash
@test "AGENTS.md stays a short map (at most 100 lines)" {
  local lines
  lines="$(wc -l <"$REPO_DIR/AGENTS.md")"
  ((lines <= 100)) || fail "AGENTS.md has $lines lines; move detail into docs/ and point to it"
}

@test "CLAUDE.md only imports AGENTS.md" {
  run cat "$REPO_DIR/CLAUDE.md"
  assert_output "@AGENTS.md"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: FAIL. `AGENTS.md`와 `CLAUDE.md`가 없어서 두 테스트가 실패한다.

- [ ] **Step 3: `AGENTS.md` 작성**

```markdown
# Agent instructions

This repo deploys a Basic Memory MCP server on an OCI Always Free VM that is reachable only inside a Tailscale tailnet.
Read first: `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md`.
Active work: `docs/plans/active/` (upcoming plans wait in `docs/plans/backlog/`).

## Commands
- `make help` lists every target. Do lifecycle work through Make targets only; use raw `docker compose` or `ssh` only to diagnose a failing target, and record why.
- `make check` (lint + all tests + coverage >= 80%) must pass before every commit. `make fmt` fixes shfmt findings.
- Local: `make local-up local-verify local-down`.

## Invariants (enforced by tests/repo.bats; never weaken a test to make it pass)
- Basic Memory has no auth: publish its port on `127.0.0.1` only, never enable Tailscale Funnel, keep zero public ingress on the VM.
- Pin container images by digest; change the pin only after reading the release notes and passing `make check local-up local-verify`.
- Scripts: `#!/usr/bin/env bash` then `set -euo pipefail`; source `scripts/lib/common.sh`; fail with an actionable message via `die`.
- Scripts must run on macOS bash 3.2: no `mapfile`, associative arrays, `${x,,}`, `inherit_errexit`, or empty array expansion. After `x="$(fn)"` where `fn` can fail, add `|| exit 1`.
- Name constants instead of magic numbers. Never print secrets or session ids; use `mask`.
- Write the bats test first (tests/*.bats; fake commands live in tests/stubs/, recorded MCP responses in tests/fixtures/).

## Safety
- Never commit secrets, `.env`, Tailscale auth keys, `backups/`, `.local-data/`, or note content.
- The only secret is the Tailscale auth key. It reaches the VM via `TS_AUTHKEY` or the hidden prompt, never via a file in the repo or a command argument.
- Ask the user before anything that changes the VM or cloud resources: `vm-bootstrap`, `deploy`, `restore`, resizing, OCI security rules, Tailscale policy.
- Never delete `backups/` or `/srv/basic-memory.prev-*` directories.

## Git (policy: docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md)
- Work only in your own git worktree on `plan/<NN>-<slug>` or `work/<slug>`; one agent per worktree, never in the main checkout. Rename tool default branches (`worktree-*`, `codex/*`) before review.
- Never commit to `main`, force-push, rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.
- End every commit message with the trailers `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>`, `Plan: <NN|none>` and `Task: <N|review|none>`; add `Review-Finding: R<n>-F<m>` to review fixes. Never add `Co-authored-by` or `Signed-off-by`.
- A reviewer from another vendor reviews each branch read-only; findings go to `docs/reviews/`; only the human merges, with `git merge --no-ff`.

## Notes and language
- Label repository notes `Verified`, `Command`, `Assumption`, or `Open question`.
- Code, comments, script messages, this file and skills are English. README, runbooks, ARCHITECTURE and ADRs are Korean.
- Record evidence (command + result) in the active plan's Progress log or an ADR in `docs/decisions/`.

## Map
- `scripts/` lifecycle scripts; `scripts/lib/common.sh` shared helpers.
- `tests/` bats tests; `tools/` test image and coverage gate.
- `docs/specs/`, `docs/plans/{active,backlog,completed}/`.
```

- [ ] **Step 4: `CLAUDE.md`와 `.claude/settings.json` 작성**

`CLAUDE.md` (한 줄, 끝 줄바꿈 포함):
```markdown
@AGENTS.md
```

`.claude/settings.json`:
```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": ""
  },
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

- [ ] **Step 5: 테스트 통과 확인**

Run: `make test`
Expected: PASS(총 40 tests).

- [ ] **Step 6: Commit**

Run: `make check` (PASS)
```bash
git add AGENTS.md CLAUDE.md .claude/settings.json tests/repo.bats
git commit -m "docs: add baseline agent instructions" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: sqzn0teq" --trailer "Task: 4"
```

---

### 마무리: 리뷰, 기록, 병합

- [ ] `make check`가 PASS하는지 확인한다.
- [ ] Progress log에 결과(테스트 수, 커버리지 %, 특이사항)를 `Verified`로 기록하고, 이 계획 파일을 `completed/`로 옮긴다.

```bash
git mv docs/plans/plan-2026-10-07-sqzn0teq-local-foundation.md docs/plans/completed/
git add docs/plans/plan-2026-10-07-sqzn0teq-local-foundation.md
git commit -m "docs: complete the local-foundation plan" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: sqzn0teq" --trailer "Task: none"
```

- [ ] 1차 리뷰(작성자와 다른 벤더, 읽기 전용). `make review`는 [git-review-tooling 계획](plan-2026-10-07-qq4h1djv-git-review-tooling.md)에서 생기므로 이번만 손으로 실행한다. 사용량이 드는 작업이므로 실행 전에 사용자에게 알린다.
  - 작성 도구가 Claude Code면 Codex로:

```bash
OUT="$(pwd)/.review-out"; WT=../027_agent_share_poc-wt/review-plan-01-local-foundation-r1
mkdir -p "$OUT" && git worktree add --detach "$WT" plan/sqzn0teq-local-foundation
(cd "$WT" && codex exec review --base main) >"$OUT/plan-01-local-foundation-r1-codex-diff.md"
(cd "$WT" && codex exec --sandbox read-only -o "$OUT/plan-01-local-foundation-r1-codex-plan.md" "Review branch plan/sqzn0teq-local-foundation (changes since main) against docs/plans/plan-2026-10-07-sqzn0teq-local-foundation.md, using the checklist in docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md section 5. Read-only: do not modify files or commit. Answer with one verdict line, then one finding per line: [P0|P1|P2|P3] path:line - failure scenario - suggested fix.")
git worktree remove --force "$WT"
```

  - 작성 도구가 Codex·Antigravity·Gemini면 Claude로: 위와 같되 두 명령을 `claude -p --permission-mode plan --no-session-persistence "/code-review main...HEAD"`와 `claude -p --permission-mode plan --no-session-persistence "<위 프롬프트>"`로 바꾸고, 출력 파일 이름의 `codex`를 `claude`로 바꾼다.
- [ ] 원문을 `docs/reviews/rev-2026-10-07-bwvfm8bx-local-foundation.md`로 옮겨 적는다. 형식은 git 정책 스펙 5절의 "리뷰 기록"(라운드 표: 리뷰어·base·리뷰한 head·판정, 지적 표: ID·등급·위치·요약·상태)을 따른다.

```bash
git add docs/reviews/rev-2026-10-07-bwvfm8bx-local-foundation.md
git commit -m "docs: record review of the local-foundation plan" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: sqzn0teq" --trailer "Task: review"
```

- [ ] 지적마다 재현하거나 근거를 인용해 검증하고, 받아들인 지적은 하나당 커밋 하나로 고친다(`--trailer "Review-Finding: R1-F<n>"`). 거절은 근거와 함께 기록한다.
- [ ] 고친 것이 있으면 2차 리뷰: `git branch review-base/plan-01-local-foundation-r2 <리뷰한 head>`를 만든 뒤 위 명령의 `--base main`을 `--base review-base/plan-01-local-foundation-r2`로, `-r1`을 `-r2`로 바꿔 실행하고, 끝나면 `git branch -D review-base/plan-01-local-foundation-r2`. 2회차 뒤 남은 이견은 사람이 결정한다.
- [ ] 병합 메시지를 `.review-out/merge-plan-01-local-foundation.txt`에 쓴다(형식: git 정책 스펙 6절):

```
Merge plan/sqzn0teq-local-foundation

Reviewed-by: yanghs6
Review-Agent: <리뷰 도구> <모델 ID>
Review-Record: docs/reviews/rev-2026-10-07-bwvfm8bx-local-foundation.md
Reviewed-Head: <리뷰한 head sha>
```
- [ ] 사람에게 병합을 요청한다. 에이전트는 병합하지 않는다. 사람은 `main` 체크아웃에서 `git merge --no-ff plan/sqzn0teq-local-foundation -F <그 파일의 절대 경로>`를 실행한다.
- [ ] 병합 뒤 worktree와 브랜치를 정리한다: `git worktree remove <경로>` → `git branch -d plan/sqzn0teq-local-foundation`

---

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-07 | Verified | kcov(latest@sha256:4812…) + bats 1.14.0 조합이 실행·source된 스크립트의 라인 커버리지를 수집함 (throwaway spike) |
| 2026-10-07 | Verified | basic-memory 0.23.2 로컬 컨테이너: `Host: bm-node.example.ts.net`으로 initialize 200, write/read/delete 왕복 성공, 응답 형식은 픽스처와 같음 |
| 2026-10-07 | Verified | 컨테이너 메모리: 기동 직후 212 MiB, 시맨틱 검색 후 449 MiB (`docker stats --no-stream`) |
| 2026-10-07 | Verified | macOS `/bin/bash` 3.2.57에서 계획의 문법(`"$@"`, `local -a`, `${v:0:4}`, `${!n:-}`, `x="$(f)" \|\| …`)과 BSD sed `\{0,1\}`가 동작함 |
| 2026-10-07 | Verified | local-foundation 계획 완료 (Command: `make check`): bats 42개 통과, `scripts/` 라인 커버리지 95.31%, shellcheck·shfmt 경고 없음 (HEAD `bade74d`) |
| 2026-10-07 | Verified | Task 2 통합 (Command: `make local-up`, `lsof -nP -iTCP:8737 -sTCP:LISTEN`): 컨테이너 Healthy, `127.0.0.1:8737`만 LISTEN, `make local-down` 후 남은 컨테이너 없음 |
| 2026-10-07 | Verified | Task 3 통합 (Command: `make local-up local-verify`, macOS bash 3.2): MCP 왕복 2회 OK(기본, `Host: bm-node.example.ts.net`), 유휴 메모리 275.1 MiB (`docker stats --no-stream`) |
| 2026-10-07 | Verified | git worktree에서 테스트 컨테이너가 git을 쓰려면 메인 `.git`을 같은 절대 경로로 읽기 전용 마운트해야 함 (Makefile `GIT_COMMON_DIR`, 이미지 `safe.directory '*'`). repo.bats 구조 테스트가 git 실패 시 크게 실패하도록 바꿔 증명함 |
| 2026-10-07 | Verified | SDD 진행: Task 1·3은 리뷰 수정 1회씩, 최종 전체 리뷰(opus) 수정 1회(F1~F8). 계획과 달라진 판단은 R1(worktree git 마운트), R4·R5(빈 목록에도 통과하는 테스트 금지), R7(검증 노트 정리 시점), R8(도구 이름 오류 라벨), R9(SDD 리뷰 지적 ID `SDD-T<task>-F<n>`), R10(최종 수정 범위) |
