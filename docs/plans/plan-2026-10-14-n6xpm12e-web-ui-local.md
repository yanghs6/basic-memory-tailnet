# n6xpm12e Web UI Local Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Task 6 needs the user's browser login, so the controller runs it in the main session, not a subagent. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Basic Memory 옆에 SilverBullet 웹 UI 컨테이너를 더하고, 공간 파일·검증·글꼴 스크립트와 `deploy`·`restore`의 `SB_USER` 처리를 만들어 로컬에서 스펙 §1 완료 조건 1·3·4·5를 증거와 함께 충족한다. VM에서는 아무것도 실행하지 않는다.

**Architecture:**
- `compose.yaml`에 `silverbullet` 서비스를 더한다. 노트 폴더만 `/data`로 마운트하고, `SB_USER` 로그인, 셸 끄기, 별도 Docker 네트워크, `127.0.0.1` 바인딩을 쓴다.
- `silverbullet/`의 원본 세 개(`notes.gitignore`, `agent-hub.md`, `index.md`)를 `scripts/sb-space.sh`가 노트 폴더에 쓴다. 로컬은 `--local`, VM은 인자 없음이다. `.gitignore`를 바꿀 때는 먼저 표시 파일 `.gitignore.pending`을 만든다. 표시가 남아 있는 동안에는 `.gitignore`만 쓰고 `changed`를 출력한다. 호출자(`make local-up`, `deploy.sh`)는 Basic Memory를 먼저 다시 만들고, 성공한 뒤에만 표시를 지운 다음 `sb-space.sh`를 다시 실행해 관리 페이지와 `index.md`를 쓴다(`unchanged`). 실행 중인 Basic Memory는 재시작 전까지 예전 무시 패턴을 쓰고 이미 색인한 항목을 지우지 않으므로(스펙 §3), SilverBullet 전용 페이지는 새 `.gitignore`를 읽은 Basic Memory만 본다. 중간에 실패한 실행을 다시 돌려도 재생성을 건너뛰지 않는다.
- `scripts/verify-sb.sh`가 로그인·쿠키·셸을 검사한다. `scripts/sb-fonts.sh`는 D2Koding 글꼴을 WOFF2로 바꿔 공간에 올린다.
- `deploy.sh`와 `restore.sh`가 VM `.env`에 `SB_USER`를 권한 600으로 쓴다. `compose.yaml`이 `SB_USER`를 요구하게 되므로, 이 계획이 병합된 뒤에도 `main`은 배포할 수 있어야 한다.
- 공통 헬퍼(`in_notes_dir`, `write_notes_file`, `notes_dir_arg`, `require_sb_user`, `vm_env`)는 `scripts/lib/common.sh`에 둔다.

**Tech Stack:** bash 3.2 호환 셸, bats-core 1.14.0 + bats-assert(테스트 이미지 `bm-tools:local`), Docker Compose, SilverBullet `2.12.1-slim`(Space Lua, Space Style), Basic Memory 0.23.2, curl, jq, python3 + fontTools·brotli(Mac, `sb-fonts`만)

**Spec:** `docs/specs/spec-2026-10-14-cjerm8b4-silverbullet-web-ui.md` (특히 §3, §7, §8, §10)

**Sequence:** 스펙과 이 계획을 담은 `work/web-ui`가 `main`에 병합된 뒤 시작한다. [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md)(PR #2)은 `d354732`로 병합됐고, 이 계획의 줄 번호는 그 뒤의 `main` 기준이다. [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md)은 이 계획이 병합된 뒤 시작한다.

## Global Constraints

- 이미지: `ghcr.io/silverbulletmd/silverbullet:2.12.1-slim@sha256:7e24c16d31a3f4b4a4832ed64ec585e605a1e275b7c35917d385176f0b40415c`. 릴리스 노트(`gh release view 2.12.1 -R silverbulletmd/silverbullet`)를 읽고 `docker buildx imagetools inspect`로 digest를 다시 확인한 뒤에만 고정한다(AGENTS.md).
- SilverBullet 불변식(스펙 §8.1): `SB_USER: ${SB_USER:?…}`, `SB_SHELL_BACKEND: "off"`, `SB_RUNTIME_API: "0"`, Basic Memory와 다른 Docker 네트워크, `127.0.0.1` 바인딩, 노트 폴더(`…/knowledge/basic-memory`)만 마운트.
- 공간 파일 경로: `.gitignore`, `.gitignore.pending`(재생성 대기 표시, Basic Memory를 다시 만들면 지움. 표시가 있는 동안 `sb-space.sh`는 `.gitignore`만 쓴다), `Library/agent-hub/agent-hub.md`, `index.md`(없을 때만), `Library/agent-hub/fonts/D2KodingLigatureNerdFont-{Regular,Bold}.woff2`.
- `notes.gitignore`는 `/CONFIG.md`, `/index.md`, `/Library/`, `/Repositories/`, `/Journal/`, `/Inbox/` 여섯 줄이다. 모두 `/`로 시작하고 주석은 넣지 않는다.
- `SB_USER`는 `<user>:<password>` 형식이다. 사용자 이름은 `[A-Za-z0-9._-]`, 비밀번호는 `[A-Za-z0-9._~+/=-]`만 쓴다(스펙 §8.3). 값과 세션 쿠키는 출력하지 않고, 비밀번호를 명령 인자에 넣지 않는다(curl 표준입력, ssh 표준입력).
- 에이전트는 `.env`를 읽거나 worktree로 복사하지 않는다. `SB_USER`는 사용자가 main 체크아웃 `.env`에 직접 적는다. 확인할 때는 값이 아니라 "설정됨"만 출력한다.
- VM을 바꾸는 명령(`make deploy`, `make restore`, `make sb-fonts`(LOCAL 없이), `make vm-bootstrap`)은 이 계획에서 실행하지 않는다. VM 쪽 코드는 스텁 테스트로만 검증한다.
- AGENTS.md: 스크립트는 `#!/usr/bin/env bash` 다음 줄에 `set -euo pipefail`을 두고, `scripts/lib/common.sh`를 source하고, 실패는 `die`로 알린다. macOS bash 3.2에서 돈다. 이름 붙인 상수를 쓴다. 코드·주석·스크립트 메시지는 영어, ADR·README·ARCHITECTURE·런북은 한국어다.
- 테스트를 먼저 쓴다(RED 확인 후 GREEN). [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md)을 따른다: 대표 성공 경로 1개, 조용하거나 파괴적인 실패 경로, 불변식만 쓴다. 입력값만 다르면 반복문 하나로 묶는다. 기존 assertion을 지우거나 약하게 바꾸지 않는다. 동작이 바뀐 기대값만 고친다.
- 테스트는 `make test`/`make check`로만 돌린다. `docker run`으로 직접 돌리지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: n6xpm12e`, `Task: <N|review|none>`. `Co-authored-by`, `Signed-off-by`, `Claude-Session`, 세션 링크, `Generated with`는 넣지 않는다.
- PR 흐름(AGENTS.md Git): 머신 계정으로 push하고 초안 PR 하나를 연다. 제목은 `feat: add the SilverBullet web UI next to Basic Memory`, 본문 마지막 문단은 `Assisted-by`와 `Plan: n6xpm12e`이다. VM의 외부·tailnet IP를 어디에도 쓰지 않는다.
- 쓰기 대상: 아래 File Structure의 파일만 바꾼다.

## Review Focus

1. **`SB_USER`에 make나 compose가 바꾸는 문자가 들어감.** 예: `$`, `#`, 공백, 따옴표, 콜론 없음. make가 `.env`를 그대로 읽으므로 `#` 뒤가 잘리고 `$x`가 사라져, 사용자가 생각한 것과 다른 비밀번호가 쓰인다. → Task 3 `verify_sb.bats`의 거부 반복문. 서버에 접속하기 전에 실패한다. 같은 헬퍼를 `deploy`·`restore`가 쓴다(Task 5).
2. **이미 있는 VM `.env`의 권한이 664.** [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md)이 배포한 파일이다. `umask 077`은 새 파일에만 적용되므로 `SB_USER`가 남에게 읽힌다. → Task 5의 배포 테스트가 644 파일을 미리 두고 600을 확인한다. 복원 테스트도 같다.
3. **`index.md`가 있는지 확인하는 원격 호출이 실패함.** 예: ssh 끊김. 이를 "없음"으로 읽으면 사용자가 고친 대시보드를 덮어쓴다. → Task 2 `sb_space.bats`가 그 호출만 실패시키고 `index.md`가 그대로인지 본다.
4. **비밀번호가 틀려도 HTTP 200.** SilverBullet은 실패도 200 JSON `{"status":"error"}`로 답한다(`server/src/handlers/auth.rs:100-102`). 상태 코드만 보면 검증이 거짓으로 통과한다. → Task 3 실패 반복문의 `CURL_SB_AUTH_BODY` 사례.
5. **세션 쿠키 값이나 비밀번호가 출력·명령 인자로 샘.** → Task 3 성공 테스트가 출력과 스텁 로그(curl 인자)에 비밀번호와 쿠키 토큰이 없는지, 비밀번호가 표준입력으로만 갔는지 확인한다.

## File Structure

```
compose.yaml  .env.example  Makefile(SB_PORT, export)  tests/repo.bats                          Task 1
silverbullet/notes.gitignore  silverbullet/agent-hub.md  silverbullet/index.md (새 파일)
scripts/sb-space.sh (새 파일)  scripts/lib/common.sh  tests/stubs/sudo  Makefile(local-up)
tests/sb_space.bats (새 파일)                                                                   Task 2
scripts/verify-sb.sh (새 파일)  scripts/lib/common.sh  tests/stubs/curl  Makefile(local-verify)
tests/verify_sb.bats (새 파일)                                                                  Task 3
scripts/sb-fonts.sh (새 파일)  tests/stubs/python3 (새 파일)  Makefile(sb-fonts)
tests/sb_fonts.bats (새 파일)                                                                   Task 4
scripts/deploy.sh  scripts/restore.sh  scripts/lib/common.sh  tests/helpers.bash
tests/vm_ops.bats  tests/backup_restore.bats                                                    Task 5
silverbullet/agent-hub.md(확인 결과에 따라)  이 계획 파일(Progress log)  스펙 §3                  Task 6
docs/decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md (새 파일)  docs/ARCHITECTURE.md  README.md  AGENTS.md
docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md(한 줄)                                Task 7
```

---

### 전제: 사람 작업 (Task 1의 `make local-up` 전)

- [ ] **1. `SB_USER` 정하기 (사용자, 자기 터미널)**

main 체크아웃의 `.env`에 한 줄을 더한다. 에이전트는 이 값을 보거나 입력하지 않는다.

```bash
cd <main 체크아웃>
openssl rand -base64 24            # 출력을 비밀번호로 쓴다 (A-Z a-z 0-9 + / = 만 나온다)
# 편집기로 .env를 열어 다음 줄을 더한다: SB_USER=<사용자 이름>:<비밀번호>
```

에이전트 확인(값은 출력하지 않는다):

```bash
printf 'sb-user-check:\n\t@echo "SB_USER $(if $(SB_USER),is set,is missing)"\n' | make --no-print-directory -f Makefile -f - sb-user-check
```

Expected: `SB_USER is set`.

- [ ] **2. 로컬 포트·컨테이너 정리 (에이전트가 확인, 삭제는 사용자 승인 뒤)**

Run: `docker ps --format '{{.Names}} {{.Ports}}'`

Expected: `127.0.0.1:3000`이나 `127.0.0.1:8737`을 쓰는 컨테이너가 없다. 브레인스토밍 스파이크의 `sb-spike`나 다른 worktree의 `basic-memory-server`가 남아 있으면 사용자에게 알리고, 승인을 받은 뒤 정리한다. 스파이크 컨테이너는 `docker rm -f sb-spike`, 다른 worktree의 Basic Memory는 그 worktree에서 `make local-down`으로 정리한다.

### 시작: 브랜치, worktree, 초안 PR (에이전트)

- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/n6xpm12e-web-ui-local` 브랜치를 만든다(git-workflow 스킬의 Start).
- [ ] 첫 커밋으로 이 계획 파일을 `docs/plans/backlog/`에서 `docs/plans/active/`로 옮기고 push한다.

```bash
git mv docs/plans/plan-2026-10-14-n6xpm12e-web-ui-local.md docs/plans/plan-2026-10-14-n6xpm12e-web-ui-local.md
git commit -m "docs: start the web-ui-local plan" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: none"
git push -u origin plan/n6xpm12e-web-ui-local
```

- [ ] `.github/pull_request_template.md` 형식으로 본문을 써서 초안 PR을 연다.

```bash
gh pr create --draft --base main --title "feat: add the SilverBullet web UI next to Basic Memory" --body-file "$TMPDIR/pr-10.md"
```

Expected: PR URL이 출력되고 작성자는 머신 계정이다. PR 번호를 Progress log에 적는다.

---

### Task 1: compose `silverbullet` 서비스와 불변식

**Files:**
- Modify: `compose.yaml`(전체), `.env.example`(끝에 추가), `Makefile:12-13`과 `local-up`·`local-down` 설명
- Test: `tests/repo.bats`(헬퍼 추가, `compose_start_period_seconds` 범위 축소, 새 테스트 1개)

**Interfaces:**
- Produces:
  - compose 서비스 `silverbullet`(컨테이너 `silverbullet-server`, 호스트 `127.0.0.1:${SB_PORT:-3000}`)와 네트워크 `basic-memory`, `silverbullet`
  - Make 변수 `SB_PORT`(기본 3000). `SB_PORT`는 전역으로 export한다. `SB_USER`는 compose나 VM에 로그인을 넘기는 여섯 타깃(`local-up`, `local-down`, `local-logs`, `local-verify`, `deploy`, `restore`)에만 export한다. 전역 export는 `make review`가 띄우는 다른 벤더 CLI(`scripts/review.sh:129-141`)까지 닿기 때문이다.
  - `tests/repo.bats`의 헬퍼 `service_block NAME`: compose.yaml에서 서비스 NAME의 줄들을 출력한다.

- [ ] **Step 1: 이미지 확인**

```bash
gh release view 2.12.1 -R silverbulletmd/silverbullet
docker buildx imagetools inspect ghcr.io/silverbulletmd/silverbullet:2.12.1-slim | head -5
```

Expected: 릴리스 노트에 보안 경고나 slim 이미지 관련 주의가 없다. `Digest:`가 `sha256:7e24c16d31a3f4b4a4832ed64ec585e605a1e275b7c35917d385176f0b40415c`이고 `linux/amd64`가 목록에 있다. 다르면 멈추고 사용자에게 묻는다.

- [ ] **Step 2: 실패하는 테스트 작성 (`tests/repo.bats`)**

`compose_start_period_seconds`(현재 `:78-81`)를 아래로 바꾼다. 두 번째 서비스의 `start_period` 때문에 산술 비교가 깨지지 않게 범위를 Basic Memory 서비스로 좁히는 것이고, Basic Memory에 대한 검증 내용은 그대로다.

```bash
# service_block NAME -> the lines of service NAME in compose.yaml, up to the next service or top-level key.
service_block() {
  awk -v name="$1" '$0 == "  " name ":" { inside = 1; next } inside && (/^[^ ]/ || /^  [^ ]/) { exit } inside { print }' "$REPO_DIR/compose.yaml"
}

# compose_start_period_seconds: print the Basic Memory healthcheck start_period in whole seconds (empty if absent).
compose_start_period_seconds() {
  service_block basic-memory | sed -nE 's/^ +start_period: ([0-9]+)s$/\1/p'
}
```

"compose restarts the container after reboots" 테스트(현재 `:101-104`) 다음에 넣는다.

```bash
@test "SilverBullet is pinned, needs a login, has no shell or runtime API and shares no network or data beyond the notes" {
  local sb bm
  sb="$(service_block silverbullet)"
  bm="$(service_block basic-memory)"
  [[ -n "$sb" && -n "$bm" ]] || fail "compose.yaml must define the basic-memory and silverbullet services"
  grep -qE '^ +image: ghcr\.io/silverbulletmd/silverbullet:[0-9.]+-slim@sha256:[0-9a-f]{64}$' <<<"$sb" \
    || fail "pin the silverbullet -slim image by digest"
  grep -qF 'SB_USER: ${SB_USER:?' <<<"$sb" \
    || fail 'SB_USER must read ${SB_USER:?...} so compose refuses to start SilverBullet without a login'
  grep -qxF '      SB_SHELL_BACKEND: "off"' <<<"$sb" || fail 'silverbullet must set SB_SHELL_BACKEND: "off"'
  grep -qxF '      SB_RUNTIME_API: "0"' <<<"$sb" || fail 'silverbullet must set SB_RUNTIME_API: "0"'
  grep -qxF '    networks: [silverbullet]' <<<"$sb" || fail "silverbullet must use only its own network"
  grep -qxF '    networks: [basic-memory]' <<<"$bm" || fail "basic-memory must use only its own network"
  grep -qxF '      - "${BM_KNOWLEDGE_DIR:-./.local-data/knowledge}/basic-memory:/data"' <<<"$sb" \
    || fail "silverbullet must mount the notes folder at /data"
  if grep -q 'BM_CONFIG_DIR' <<<"$sb"; then
    fail "silverbullet must not mount the Basic Memory config and database"
  fi
}
```

- [ ] **Step 3: 실패 확인**

Run: `make test`
Expected: 새 테스트 1개만 `compose.yaml must define the basic-memory and silverbullet services`로 실패한다. 범위를 좁힌 `start_period` 두 테스트를 포함해 나머지는 PASS한다.

- [ ] **Step 4: 구현**

`compose.yaml` 전체:

```yaml
# Basic Memory MCP server and the SilverBullet web UI on the same notes folder. The same file runs locally
# (make local-up) and on the VM (make deploy). Defaults are the local values; on the VM, scripts/deploy.sh writes
# absolute paths and SB_USER into .env.
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
      # A cold start on the e2-micro VM took 161-192s. Failed checks inside start_period do not count, so a slow
      # start no longer turns the container unhealthy (which fails `up --wait` at once); start_interval still
      # marks it healthy within seconds of listening.
      start_period: 300s
      start_interval: 2s
    networks: [basic-memory]
    restart: unless-stopped
  silverbullet:
    # Web UI for the notes. It mounts only the notes folder, never the Basic Memory database or config.
    image: ghcr.io/silverbulletmd/silverbullet:2.12.1-slim@sha256:7e24c16d31a3f4b4a4832ed64ec585e605a1e275b7c35917d385176f0b40415c
    container_name: silverbullet-server
    # Loopback only: Tailscale Serve publishes it inside the tailnet on https port 8443.
    ports:
      - "127.0.0.1:${SB_PORT:-3000}:3000"
    volumes:
      - "${BM_KNOWLEDGE_DIR:-./.local-data/knowledge}/basic-memory:/data"
    environment:
      # Without a login, any web page the browser opens could run shell commands and use the proxy through this port.
      SB_USER: ${SB_USER:?set SB_USER in the main checkout .env, see .env.example}
      SB_SHELL_BACKEND: "off"
      SB_RUNTIME_API: "0"
    # Basic Memory creates the notes folder and reads the notes .gitignore before SilverBullet writes anything.
    depends_on:
      basic-memory:
        condition: service_healthy
    healthcheck:
      # The image checks /.instance, which needs a login once SB_USER is set; /.ping stays open.
      test: ["CMD", "curl", "--fail", "--silent", "http://localhost:3000/.ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
      start_interval: 2s
    networks: [silverbullet]
    restart: unless-stopped
networks:
  basic-memory:
  silverbullet:
```

`.env.example` 끝에 더한다.

```bash
# Loopback port SilverBullet (the web UI) listens on (local and VM)
SB_PORT=3000
# SilverBullet login as <user>:<password>; make local-up, deploy, restore and verify need it.
# This one is a secret: fill it in only in the main checkout .env (git-ignored), never here or in a commit.
# Use letters, digits and ._~+/=- only: make reads this file literally (# starts a comment, $ expands).
# A password that fits: openssl rand -base64 24
SB_USER=
```

`Makefile:12-13`을 바꾼다. `SB_USER`는 전역 export 목록에 넣지 않는다. 전역 export는 모든 레시피에 들어가 `make review`가 실행하는 `codex exec`·`claude -p`(`scripts/review.sh:129-141`)도 환경에서 비밀값을 보게 된다. make 3.81에서 타깃별 export는 이름을 적은 타깃에만 닿는다(Verified, 사전 점검). 레시피 인자로 넘기면 make가 명령을 출력하므로 그렇게 하지 않는다.

```make
BM_PORT := $(or $(BM_PORT),8737)
SB_PORT := $(or $(SB_PORT),3000)
export BM_VM_HOST BM_VM_USER BM_TAILNET_DOMAIN BM_VM_PUBLIC_IP BM_PORT SB_PORT
# Only the targets that hand the SilverBullet login to compose or the VM see it; make review's CLIs do not.
local-up local-down local-logs local-verify deploy restore: export SB_USER := $(SB_USER)
```

`local-up`과 `local-down`의 `##` 설명을 바꾼다(레시피는 Task 2에서 바꾼다).

```make
local-up: ## Start Basic Memory and SilverBullet locally (127.0.0.1:BM_PORT, SB_PORT) and wait until healthy
```

```make
local-down: ## Stop the local containers (data in .local-data/ is kept)
```

- [ ] **Step 5: 통과 확인**

Run: `make check`
Expected: exit 0. 새 테스트가 ok이고, 커버리지는 80% 이상이다.

- [ ] **Step 6: 로컬 기동 확인**

```bash
make local-up
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/.ping
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/.fs/index.md
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/.instance
make local-down
```

Expected:
- `make local-up`이 두 컨테이너 모두 healthy로 끝난다(`--wait`).
- 순서대로 `200`, `401`, `401`이다. `/.instance`가 401이라 이미지 기본 healthcheck를 덮어써야 한다는 근거다.
- 브라우저로는 아직 열지 않는다. 열면 SilverBullet이 Task 2의 시드보다 먼저 `index.md`를 만들 수 있다(스펙 §11).
- 결과를 Progress log에 `Verified`로 적는다.

- [ ] **Step 7: 커밋과 push**

```bash
git add compose.yaml .env.example Makefile tests/repo.bats
git commit -m "feat: run SilverBullet next to Basic Memory with a login and no shell" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 1"
git push
```

### Task 2: 공간 파일과 `sb-space.sh`

**Files:**
- Create: `silverbullet/notes.gitignore`, `silverbullet/agent-hub.md`, `silverbullet/index.md`, `scripts/sb-space.sh`(실행 권한), `tests/sb_space.bats`
- Modify: `scripts/lib/common.sh`(상수와 헬퍼 추가), `tests/stubs/sudo`(`-u USER`), `Makefile`(`local-up` 레시피)

**Interfaces:**
- Consumes: Task 1의 compose 서비스 이름 `basic-memory`
- Produces (`scripts/lib/common.sh`):
  - `SB_LOCAL_NOTES_DIR`: 로컬 노트 폴더 `<repo>/.local-data/knowledge/basic-memory`. 테스트만 덮어쓴다.
  - `SB_REMOTE_NOTES_DIR`: `$BM_REMOTE_DATA_ROOT/knowledge/basic-memory`
  - `SB_FONTS_REL_DIR=Library/agent-hub/fonts`: 노트 폴더 기준 글꼴 경로(Task 3·4가 쓴다)
  - `SB_GITIGNORE_PENDING=.gitignore.pending`: 노트 폴더 기준 표시 파일. 있으면 Basic Memory가 지금 `.gitignore`를 아직 읽지 않았다는 뜻이다(Task 5가 쓴다). 점 파일이라 Basic Memory(기본 무시 패턴 `.*`, v0.23.2 `ignore_utils.py:21-23`)와 SilverBullet 모두 보지 않는다.
  - `notes_dir_arg [--local]`: `--local`이면 로컬 노트 폴더 경로를 출력한다. 인자가 없으면 VM 설정을 검사하고 아무것도 출력하지 않는다(빈 값 = VM). 그 밖의 인자는 usage로 `die`.
  - `in_notes_dir LOCAL_DIR CMD`: 노트 폴더 안에서 sh 명령 CMD를 실행한다. LOCAL_DIR이 비면 VM에서 컨테이너 UID로 실행한다. 표준입력을 넘긴다. CMD에 작은따옴표를 넣지 않는다.
  - `write_notes_file LOCAL_DIR PATH`: 노트 폴더 기준 PATH(공백 없음)를 표준입력 내용으로 바꾼다.
- Produces: `scripts/sb-space.sh [--local]`. 표준출력은 한 줄이고, 로그는 표준에러로 간다.
  - `changed`: 표시 파일이 있어 `.gitignore`만 썼다. 호출자는 Basic Memory를 다시 만들고, 표시를 지우고, `sb-space.sh`를 다시 실행해 페이지를 쓴다.
  - `unchanged`: 표시 파일이 없어 관리 페이지와 (없을 때) `index.md`까지 썼다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/sb_space.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh sudo
  use_vm_env
  export SB_LOCAL_NOTES_DIR="$BATS_TEST_TMPDIR/local-notes"
  SB_SPACE="$REPO_DIR/scripts/sb-space.sh"
  SRC="$REPO_DIR/silverbullet"
  VM_NOTES="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
}

@test "local: writes only the .gitignore until Basic Memory was recreated, then the library page every run and index.md once" {
  local page="$SB_LOCAL_NOTES_DIR/Library/agent-hub/agent-hub.md"
  run "$SB_SPACE" --local
  assert_success
  assert_line changed
  run diff "$SRC/notes.gitignore" "$SB_LOCAL_NOTES_DIR/.gitignore"
  assert_success
  [[ ! -e "$page" && ! -e "$SB_LOCAL_NOTES_DIR/index.md" ]] \
    || fail "the pages must wait until Basic Memory loaded the new .gitignore, or it indexes them"

  # The caller failed before recreating Basic Memory, so the marker stays and the next run asks again.
  run "$SB_SPACE" --local
  assert_success
  assert_line changed
  [[ ! -e "$page" && ! -e "$SB_LOCAL_NOTES_DIR/index.md" ]] || fail "the pages must wait while the marker stays"

  # The caller recreated Basic Memory and removed the marker.
  rm "$SB_LOCAL_NOTES_DIR/.gitignore.pending"
  run "$SB_SPACE" --local
  assert_success
  assert_line unchanged
  run diff "$SRC/agent-hub.md" "$page"
  assert_success
  run diff "$SRC/index.md" "$SB_LOCAL_NOTES_DIR/index.md"
  assert_success

  echo "my dashboard" >"$SB_LOCAL_NOTES_DIR/index.md"
  echo "stale" >"$page"
  run "$SB_SPACE" --local
  assert_success
  assert_line unchanged
  run cat "$SB_LOCAL_NOTES_DIR/index.md"
  assert_output "my dashboard"
  run diff "$SRC/agent-hub.md" "$page"
  assert_success

  echo "/extra/" >>"$SB_LOCAL_NOTES_DIR/.gitignore"
  run "$SB_SPACE" --local
  assert_success
  assert_line changed
  run diff "$SRC/notes.gitignore" "$SB_LOCAL_NOTES_DIR/.gitignore"
  assert_success
  run grep -c '^ssh ' "$STUB_LOG"
  assert_output 0
}

@test "VM: writes the space files into the VM notes folder, always as the container user" {
  local total as_container
  run "$SB_SPACE"
  assert_success
  assert_line changed
  # The caller recreated Basic Memory and removed the marker; the second run writes the pages.
  rm "$VM_NOTES/.gitignore.pending"
  run "$SB_SPACE"
  assert_success
  assert_line unchanged
  run diff "$SRC/notes.gitignore" "$VM_NOTES/.gitignore"
  assert_success
  run diff "$SRC/agent-hub.md" "$VM_NOTES/Library/agent-hub/agent-hub.md"
  assert_success
  run diff "$SRC/index.md" "$VM_NOTES/index.md"
  assert_success
  total="$(grep -c '^sudo ' "$STUB_LOG")"
  as_container="$(grep -c '^sudo -n -u #1000 sh -c ' "$STUB_LOG")"
  ((total > 0 && total == as_container)) || fail "every VM write must run as uid 1000: $(grep '^sudo ' "$STUB_LOG")"
}

@test "VM: fails and leaves index.md alone when it cannot tell whether index.md exists" {
  mkdir -p "$VM_NOTES"
  # Basic Memory already loaded this .gitignore (no marker), so the run goes on to the index.md check.
  cp "$SRC/notes.gitignore" "$VM_NOTES/.gitignore"
  echo "my dashboard" >"$VM_NOTES/index.md"
  SSH_STUB_FAIL_MATCH="-e index.md" run "$SB_SPACE"
  assert_failure
  assert_output --partial "could not check for index.md"
  run cat "$VM_NOTES/index.md"
  assert_output "my dashboard"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `sb_space.bats` 3개가 실패하고 출력에 `scripts/sb-space.sh: No such file or directory`가 나온다. 세 번째 테스트는 실패 메시지(`could not check for index.md`)를 확인하므로 스크립트가 없어서 난 실패로는 통과하지 않는다. 나머지는 PASS한다.

- [ ] **Step 3: 원본 공간 파일 작성**

`silverbullet/notes.gitignore`:

```
/CONFIG.md
/index.md
/Library/
/Repositories/
/Journal/
/Inbox/
```

`silverbullet/index.md`:

```markdown
# Agent Hub

${agentHub.dashboard()}
```

`silverbullet/agent-hub.md`(스파이크 `CONFIG`의 글꼴·훅·저널 설정에 스펙 §7.2의 건너뛸 경로, 트리, 대시보드를 더한 것):

````markdown
# Agent Hub settings

Managed by `scripts/sb-space.sh` from `silverbullet/agent-hub.md` in the agent-share-poc repo. Changes here are overwritten by the next `make local-up` or `make deploy`; put your own settings in [[CONFIG]].

## Font

D2KodingLigature Nerd Font, served from this space (`make sb-fonts`) so every device shows the same font.

```space-style
@font-face {
  font-family: "D2Koding Space";
  src: url("/.fs/Library/agent-hub/fonts/D2KodingLigatureNerdFont-Regular.woff2") format("woff2");
  font-weight: 400;
  font-display: swap;
}
@font-face {
  font-family: "D2Koding Space";
  src: url("/.fs/Library/agent-hub/fonts/D2KodingLigatureNerdFont-Bold.woff2") format("woff2");
  font-weight: 700;
  font-display: swap;
}
:root {
  --editor-font: "D2Koding Space", "D2KodingLigature Nerd Font", "D2Coding", "Menlo", monospace;
  --ui-font: "D2Koding Space", "D2KodingLigature Nerd Font", "D2Coding", "Menlo", monospace;
}
```

## Theme

GitHub Light Default and Dark Default colors on SilverBullet's own theme variables, so `Editor: Toggle Dark Mode` switches between them as before.

```space-style
/* GitHub Light Default and Dark Default colors (@primer/primitives 10.7.0, MIT) on SilverBullet's theme variables. */
html {
  --ui-accent-color: #0969da;
  --ui-accent-contrast-color: #ffffff;
  --link-color: #0969da;
  --link-missing-color: #bc4c00;
  --link-invalid-color: #8250df;
  --meta-color: #cf222e;
  --meta-subtle-color: #59636e;
  --subtle-color: #59636e;
  --subtle-background-color: #818b981f;
  --ui-surface-border-color: #d1d9e0;
  --root-background-color: #ffffff;
  --root-color: #1f2328;
  --top-background-color: #f6f8fa;
  --top-border-color: #d1d9e0;
  --panel-background-color: #f6f8fa;
  --modal-background-color: #ffffff;
  --modal-help-background-color: #f6f8fa;
  --modal-help-color: #59636e;
  --modal-hint-background-color: #0969da;
  --modal-hint-color: #ffffff;
  --modal-hint-inactive-background-color: #818b981f;
  --modal-hint-inactive-color: #59636e;
  --action-button-color: #59636e;
  --action-button-hover-color: #0969da;
  --action-button-active-color: #0969da;
  --progress-index-color: #0969da;
  --editor-caret-color: #1f2328;
  --editor-selection-background-color: #0969da33;
  --editor-heading-color: #1f2328;
  --editor-list-bullet-color: #59636e;
  --editor-hashtag-background-color: #ddf4ff;
  --editor-hashtag-color: #0969da;
  --editor-hashtag-border-color: #0969da33;
  --editor-wiki-link-page-background-color: transparent;
  --editor-code-color: #1f2328;
  --editor-code-background-color: #818b981f;
  --editor-blockquote-background-color: transparent;
  --editor-blockquote-color: #59636e;
  --editor-blockquote-border-color: #d1d9e0;
  --editor-table-head-background-color: #f6f8fa;
  --editor-table-head-color: #1f2328;
  --editor-table-even-background-color: #f6f8fa;
  --editor-frontmatter-background-color: #f6f8fa;
  --editor-frontmatter-marker-color: #59636e;
  --editor-widget-background-color: #f6f8fa;
  --editor-command-button-background-color: #f6f8fa;
  --editor-command-button-border-color: #d1d9e0;
  --editor-struct-color: #cf222e;
  --editor-task-state-color: #9a6700;
  --editor-code-comment-color: #59636e;
  --editor-code-variable-color: #953800;
  --editor-code-typename-color: #6639ba;
  --editor-code-string-color: #0a3069;
  --editor-code-number-color: #0550ae;
  --editor-code-atom-color: #0550ae;
}
html[data-theme="dark"] {
  --ui-accent-color: #4493f8;
  --ui-accent-contrast-color: #0d1117;
  --link-color: #4493f8;
  --link-missing-color: #db6d28;
  --link-invalid-color: #ab7df8;
  --meta-color: #ff7b72;
  --meta-subtle-color: #9198a1;
  --subtle-color: #9198a1;
  --subtle-background-color: #656c7633;
  --ui-surface-border-color: #3d444d;
  --root-background-color: #0d1117;
  --root-color: #f0f6fc;
  --top-color: #f0f6fc;
  --top-background-color: #151b23;
  --top-border-color: #3d444d;
  --panel-background-color: #151b23;
  --panel-border-color: #3d444d;
  --bhs-background-color: #0d1117;
  --bhs-border-color: #3d444d;
  --modal-background-color: #151b23;
  --modal-help-background-color: #151b23;
  --modal-help-color: #9198a1;
  --modal-hint-background-color: #1f6feb;
  --modal-hint-color: #ffffff;
  --modal-hint-inactive-background-color: #656c7633;
  --modal-hint-inactive-color: #9198a1;
  --action-button-color: #9198a1;
  --action-button-hover-color: #4493f8;
  --action-button-active-color: #4493f8;
  --progress-index-color: #4493f8;
  --editor-caret-color: #f0f6fc;
  --editor-selection-background-color: #4493f84d;
  --editor-heading-color: #f0f6fc;
  --editor-list-bullet-color: #9198a1;
  --editor-hashtag-background-color: #388bfd1a;
  --editor-hashtag-color: #4493f8;
  --editor-hashtag-border-color: #1f6feb66;
  --editor-wiki-link-page-background-color: transparent;
  --editor-code-color: #f0f6fc;
  --editor-code-background-color: #656c7633;
  --editor-blockquote-background-color: transparent;
  --editor-blockquote-color: #9198a1;
  --editor-blockquote-border-color: #3d444d;
  --editor-table-head-background-color: #151b23;
  --editor-table-head-color: #f0f6fc;
  --editor-table-even-background-color: #151b23;
  --editor-frontmatter-background-color: #151b23;
  --editor-frontmatter-marker-color: #9198a1;
  --editor-widget-background-color: #151b23;
  --editor-command-button-background-color: #151b23;
  --editor-command-button-border-color: #3d444d;
  --editor-struct-color: #ff7b72;
  --editor-task-state-color: #d29922;
  --editor-code-comment-color: #9198a1;
  --editor-code-variable-color: #ffa657;
  --editor-code-typename-color: #d2a8ff;
  --editor-code-string-color: #a5d6ff;
  --editor-code-number-color: #79c0ff;
  --editor-code-atom-color: #79c0ff;
}
```

## Settings

Runs before the standard library (priority 5), so the journal commands never appear. The page tree opens on the left, and the page search (Cmd-K) and notes search (Cmd-Shift-F) open in the same left slot while you search: a sidebar slot shows one view at a time, and closing a search brings the tree back. The table of contents opens on the right. Each browser keeps its own choice once you move or close a panel.

```space-lua
-- priority: 5
config.set("journal.enabled", false)
-- Index every paragraph, not only tagged ones, so the notes search finds body text.
config.set("index.paragraph.all", true)
config.set("view.defaults", {
  ["std.spaceTree"] = { dock = "lhs", open = true },
  ["std.pages"] = { dock = "lhs" },
  ["std.toc"] = { dock = "rhs", open = true },
  -- SilverBullet treats Basic Memory observations as tasks; this list would offer state clicks that erase categories.
  ["std.linkedTasks"] = { open = false },
})
```

## New notes

New notes start with the frontmatter Basic Memory would otherwise insert while you type, which dropped a newline. SilverBullet-only pages and virtual pages get no frontmatter.

```space-lua
agentHub = agentHub or {}

-- Pages the notes .gitignore keeps out of Basic Memory.
local SB_ONLY_PREFIXES = { "Library/", "Repositories/", "Journal/", "Inbox/" }
local SB_ONLY_PAGES = { index = true, CONFIG = true }

function agentHub.isNote(name)
  if SB_ONLY_PAGES[name] then
    return false
  end
  for _, prefix in ipairs(SB_ONLY_PREFIXES) do
    if name:startsWith(prefix) then
      return false
    end
  end
  return true
end

event.listen {
  name = "editor:pageCreating",
  run = function(e)
    local name = e.data.name
    if not agentHub.isNote(name) then
      return nil
    end
    for _, def in pairs(config.get("virtualPages", {})) do
      if name:match(def.pattern) then
        return nil
      end
    end
    local title = name:match("([^/]+)$"):gsub("\"", "\\\"")
    local permalink = "main/" .. string.lower(name):gsub("[%s_]+", "-")
    return {
      text = "---\ntitle: \"" .. title .. "\"\ntype: note\npermalink: " .. permalink .. "\n---\n|^|",
      perm = "rw",
    }
  end,
}
```

## Reading and finding notes

Read-only helpers, nothing is written into the notes:

- A page-info line above every note: last update, word count, reading time, backlinks and the `memory://` URL agents use.
- `Search: Notes` (Cmd-Shift-F) searches headers, observations, list items and paragraphs in the left slot, because SilverBullet has no built-in full-text search.
- `Basic Memory: Copy memory:// Link` and `Navigate: Random Note`.

```space-style
.agent-hub-page-info {
  color: var(--subtle-color);
  font-size: 0.85em;
}
```

```space-lua
-- Blocks may load in any order, so this one creates the table too.
agentHub = agentHub or {}

local WORDS_PER_MINUTE = 200
local SEARCH_MIN_BYTES = 2
local SEARCH_MAX_ROWS = 100

local function pageObject(name)
  local pages = query[[from p = index.pages() where p.name == name limit 1]]
  return pages[1]
end

function agentHub.memoryUrl(name)
  local page = name and pageObject(name)
  if page and page.permalink then
    return "memory://" .. page.permalink
  end
  return nil
end

local function backlinkCount(name)
  local seen, count = {}, 0
  for _, r in ipairs(query[[from r = index.relations() where r.to == name and r.page != name and r.kind != "co-mention"]]) do
    if not seen[r.page] then
      seen[r.page] = true
      count = count + 1
    end
  end
  return count
end

local function wordCount(text)
  local body = text:gsub("^%-%-%-\n.-\n%-%-%-\n", "")
  local count = 0
  for _ in body:gmatch("%S+") do
    count = count + 1
  end
  return count
end

function agentHub.pageInfo()
  local name = editor.getCurrentPage()
  if not name or not agentHub.isNote(name) then
    return nil
  end
  local page = pageObject(name)
  local words = wordCount(editor.getText())
  local parts = {}
  if page and page.lastModified then
    table.insert(parts, "Updated " .. (string.sub(page.lastModified, 1, 16):gsub("T", " ")))
  end
  table.insert(parts, words .. " words")
  table.insert(parts, "~" .. math.max(1, math.ceil(words / WORDS_PER_MINUTE)) .. " min read")
  table.insert(parts, backlinkCount(name) .. " backlinks")
  local url = agentHub.memoryUrl(name)
  if url then
    table.insert(parts, "`" .. url .. "`")
  end
  return widget.new {
    markdown = table.concat(parts, " · "),
    cssClasses = { "agent-hub-page-info" },
  }
end

view.define {
  name = "agentHub.pageInfo",
  title = "Page info",
  dock = "page-top",
  supportedDocks = { "page-top", "page-bottom" },
  frame = "minimal",
  refreshOn = { "navigate", "index" },
  content = function()
    return agentHub.pageInfo()
  end,
}

local function addMatch(rows, obj, text, needle)
  if #rows >= SEARCH_MAX_ROWS or not text or not obj.page or not agentHub.isNote(obj.page) then
    return
  end
  if string.find(string.lower(text), needle, 1, true) then
    table.insert(rows, { page = obj.page, excerpt = text, ref = obj.ref })
  end
end

-- Tags live in their own field and only sometimes stay in the text, so add the missing ones back.
local function withTags(text, tags)
  if not text or not tags then
    return text
  end
  local lower = string.lower(text)
  for _, tag in ipairs(tags) do
    if not string.find(lower, "#" .. string.lower(tag), 1, true) then
      text = text .. " #" .. tag
    end
  end
  return text
end

function agentHub.searchRows(phrase)
  local needle = string.lower(phrase or "")
  if #needle < SEARCH_MIN_BYTES then
    return {}
  end
  local rows = {}
  for _, h in ipairs(query[[from h = index.headers()]]) do
    addMatch(rows, h, h.name, needle)
  end
  for _, t in ipairs(query[[from t = index.tasks()]]) do
    addMatch(rows, t, withTags("[" .. (t.state or "") .. "] " .. t.name, t.tags), needle)
  end
  for _, i in ipairs(query[[from i = index.items()]]) do
    addMatch(rows, i, withTags(i.text, i.tags), needle)
  end
  for _, p in ipairs(query[[from p = index.paragraphs()]]) do
    addMatch(rows, p, p.text, needle)
  end
  return rows
end

view.define {
  name = "agentHub.search",
  title = "Search notes",
  label = "Search",
  placeholder = "Text in notes",
  helpText = "Headers, observations, list items and paragraphs of Basic Memory notes. Paragraphs missing? Run Space: Reindex once in this browser.",
  command = "Search: Notes",
  key = "Ctrl-Shift-f",
  mac = "Cmd-Shift-f",
  dock = "lhs",
  supportedDocks = { "lhs", "rhs", "modal" },
  search = "source",
  source = function(ctx)
    return agentHub.searchRows(ctx.phrase)
  end,
  presentation = {
    mode = "list",
    row = {
      primary = "page",
      description = function(row)
        return { text = row.excerpt }
      end,
    },
  },
  onSelect = function(row)
    editor.navigate(row.ref)
  end,
}

command.define {
  name = "Basic Memory: Copy memory:// Link",
  run = function()
    local url = agentHub.memoryUrl(editor.getCurrentPage())
    if not url then
      editor.flashNotification("This page has no Basic Memory permalink", "warning")
      return
    end
    editor.copyToClipboard(url)
    editor.flashNotification("Copied " .. url)
  end,
}

command.define {
  name = "Navigate: Random Note",
  run = function()
    local notes = {}
    for _, p in ipairs(query[[from p = index.pages()]]) do
      if agentHub.isNote(p.name) then
        table.insert(notes, p.name)
      end
    end
    if #notes > 0 then
      editor.navigate(notes[math.random(#notes)])
    end
  end,
}
```

## Dashboard

`agentHub.dashboard()` renders the [[index]] page: recently changed notes, top folders, Basic Memory observations by category (SilverBullet indexes `- [decision] ...` as a task whose state is the category) and tags.

```space-lua
-- Blocks may load in any order, so this one creates the table too.
agentHub = agentHub or {}

local RECENT_NOTES = 10
local NOTES_PER_FOLDER = 3
local OBSERVATIONS_PER_CATEGORY = 10

local function bullets(lines, empty)
  if #lines == 0 then
    return "_" .. empty .. "_"
  end
  return table.concat(lines, "\n")
end

local function shortLink(name)
  return "[[" .. name .. "|" .. name:match("([^/]+)$") .. "]]"
end

local function recentNotes()
  local lines = {}
  for _, p in ipairs(query[[from p = index.pages() order by p.lastModified desc]]) do
    if agentHub.isNote(p.name) then
      table.insert(lines, "- [[" .. p.name .. "]]")
      if #lines == RECENT_NOTES then
        break
      end
    end
  end
  return bullets(lines, "No notes yet")
end

local function folders()
  local byFolder, names = {}, {}
  for _, p in ipairs(query[[from p = index.pages() order by p.lastModified desc]]) do
    local folder = p.name:match("^([^/]+)/")
    if folder and agentHub.isNote(p.name) then
      local entry = byFolder[folder]
      if not entry then
        entry = { count = 0, links = {} }
        byFolder[folder] = entry
        table.insert(names, folder)
      end
      entry.count = entry.count + 1
      if #entry.links < NOTES_PER_FOLDER then
        table.insert(entry.links, shortLink(p.name))
      end
    end
  end
  table.sort(names)
  local lines = {}
  for _, folder in ipairs(names) do
    local entry = byFolder[folder]
    table.insert(lines, "- **" .. folder .. "** (" .. entry.count .. "): " .. table.concat(entry.links, ", "))
  end
  return bullets(lines, "No folders yet")
end

local function observations(category)
  local lines = {}
  for _, t in ipairs(query[[from t = index.tasks() order by t.page]]) do
    if t.state == category and agentHub.isNote(t.page) then
      table.insert(lines, "- " .. t.name .. " (" .. shortLink(t.page) .. ")")
      if #lines == OBSERVATIONS_PER_CATEGORY then
        break
      end
    end
  end
  return bullets(lines, "None")
end

local function tagList()
  local counts, names = {}, {}
  for _, t in ipairs(query[[from t = index.tags()]]) do
    if t.page and agentHub.isNote(t.page) then
      if not counts[t.name] then
        counts[t.name] = 0
        table.insert(names, t.name)
      end
      counts[t.name] = counts[t.name] + 1
    end
  end
  table.sort(names, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)
  local items = {}
  for _, name in ipairs(names) do
    table.insert(items, "- #" .. name .. " (" .. counts[name] .. ")")
  end
  return bullets(items, "No tags yet")
end

function agentHub.dashboard()
  return table.concat({
    "## Recently changed", recentNotes(), "",
    "## Folders", folders(), "",
    "## Decisions", observations("decision"), "",
    "## Risks", observations("risk"), "",
    "## Open questions", observations("question"), "",
    "## Tags", tagList(), "",
    "## Maintenance", "[[Library/Std/Pages/Maintenance|Broken and ambiguous links]]",
  }, "\n")
end
```
````

- [ ] **Step 4: 공통 헬퍼 (`scripts/lib/common.sh`)**

`HEALTH_TIMEOUT_SECONDS`(현재 `:19`) 다음에 넣는다.

```bash
# SilverBullet space = the Basic Memory notes folder of project main. The local path is overridable only for tests.
SB_LOCAL_NOTES_DIR="${SB_LOCAL_NOTES_DIR:-$(dirname "$(dirname "$COMMON_LIB_DIR")")/.local-data/knowledge/basic-memory}"
readonly SB_LOCAL_NOTES_DIR
readonly SB_REMOTE_NOTES_DIR="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
# Where the managed library page (silverbullet/agent-hub.md) loads the WOFF2 fonts from.
readonly SB_FONTS_REL_DIR="Library/agent-hub/fonts"
# Marker in the notes folder: Basic Memory has not loaded the current .gitignore yet (it reads it only at start).
# sb-space.sh creates it before changing .gitignore and writes no pages while it exists; callers remove it only after
# recreating Basic Memory. Basic Memory skips dotfiles (default pattern .*) and SilverBullet cannot read them.
readonly SB_GITIGNORE_PENDING=".gitignore.pending"
```

`vm_env`(현재 `:64-69`) 다음에 넣는다.

```bash
# notes_dir_arg [--local] -> the local notes folder for --local; nothing (meaning the VM) without an argument, after
# checking the VM settings. Any other argument dies with the usage. Use: local_dir="$(notes_dir_arg "$@")" || exit 1
notes_dir_arg() {
  case "${1:-}" in
    "")
      require_cmd ssh
      require_env BM_VM_HOST BM_VM_USER
      ;;
    --local) printf '%s' "$SB_LOCAL_NOTES_DIR" ;;
    *) die "usage: $(basename "$0") [--local]" ;;
  esac
}

# in_notes_dir LOCAL_DIR CMD -> run the sh command CMD inside the notes folder, creating it first: LOCAL_DIR when set,
# else the VM folder as the container user, so Basic Memory and SilverBullet can rewrite the files. stdin reaches CMD.
# CMD must not contain single quotes.
in_notes_dir() {
  if [[ -n "$1" ]]; then
    mkdir -p "$1" && (cd "$1" && sh -c "$2")
  else
    remote "sudo -n -u '#$BM_CONTAINER_UID' sh -c 'mkdir -p $SB_REMOTE_NOTES_DIR && cd $SB_REMOTE_NOTES_DIR && $2'"
  fi
}

# write_notes_file LOCAL_DIR PATH -> replace PATH (relative to the notes folder, without spaces) with stdin.
write_notes_file() {
  in_notes_dir "$1" "mkdir -p $(dirname "$2") && cat > $2"
}
```

- [ ] **Step 5: `tests/stubs/sudo`가 `-u USER`를 건너뛰게 한다**

```bash
#!/usr/bin/env bash
# Test stub for sudo: drops leading options (-n, and -u with its user) and runs the rest with env
# (handles VAR=value cmd), as the current user.
set -euo pipefail
printf 'sudo %s\n' "$*" >>"$STUB_LOG"
while [[ "${1:-}" == -* ]]; do
  if [[ "$1" == -u ]]; then
    shift
  fi
  shift
done
exec env "$@"
```

- [ ] **Step 6: `scripts/sb-space.sh` 구현 (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Write the SilverBullet space files into the Basic Memory notes folder, locally (--local) or on the VM:
#   .gitignore                      keeps SilverBullet-only pages out of the Basic Memory index (always replaced)
#   Library/agent-hub/agent-hub.md  font, new-note frontmatter hook, journal off, tree, dashboard (replaced on every
#                                   run that prints "unchanged")
#   index.md                        the dashboard page (only when missing, so your edits stay)
# Basic Memory reads .gitignore only at start, keeps using the old patterns until then and never drops a file it
# already indexed. Before changing .gitignore, this script creates the $SB_GITIGNORE_PENDING marker. While the marker
# exists it writes only .gitignore and prints "changed": the caller recreates the Basic Memory container, removes the
# marker only after that succeeds, and runs this script again to write the pages. Without the marker it writes the
# library page (and index.md when missing) and prints "unchanged". A run that failed in between (a pull, the
# recreate) leaves the marker, so the next run asks again.
# Usage: sb-space.sh [--local]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly SOURCE_DIR="$REPO_DIR/silverbullet"
readonly LIBRARY_PAGE=Library/agent-hub/agent-hub.md

main() {
  local local_dir previous state pending where
  local_dir="$(notes_dir_arg "$@")" || exit 1
  where="${local_dir:-$BM_VM_HOST:$SB_REMOTE_NOTES_DIR}"

  previous="$(in_notes_dir "$local_dir" 'cat .gitignore 2>/dev/null || true' </dev/null)" \
    || die "could not read the notes folder $where"
  if [[ "$previous" != "$(cat "$SOURCE_DIR/notes.gitignore")" ]]; then
    in_notes_dir "$local_dir" "touch $SB_GITIGNORE_PENDING" </dev/null \
      || die "could not mark the .gitignore change in $where, so .gitignore was not written"
  fi
  write_notes_file "$local_dir" .gitignore <"$SOURCE_DIR/notes.gitignore" || die "could not write .gitignore in $where"

  pending="$(in_notes_dir "$local_dir" "if [ -e $SB_GITIGNORE_PENDING ]; then echo yes; else echo no; fi" </dev/null)" \
    || die "could not check for $SB_GITIGNORE_PENDING in $where"
  if [[ "$pending" == yes ]]; then
    # A running Basic Memory would index the pages under the old patterns and keep them after the recreate.
    log "the notes .gitignore changed since Basic Memory started: it must be recreated to load it"
    echo changed
    return 0
  fi

  write_notes_file "$local_dir" "$LIBRARY_PAGE" <"$SOURCE_DIR/agent-hub.md" || die "could not write $LIBRARY_PAGE in $where"
  state="$(in_notes_dir "$local_dir" 'if [ -e index.md ]; then echo present; else echo absent; fi' </dev/null)" \
    || die "could not check for index.md in $where, so it was not written"
  if [[ "$state" == absent ]]; then
    write_notes_file "$local_dir" index.md <"$SOURCE_DIR/index.md" || die "could not write index.md in $where"
    log "wrote the dashboard index.md"
  fi
  echo unchanged
}

main "$@"
```

- [ ] **Step 7: `Makefile`의 `local-up` 레시피 (스펙 §7.3 순서)**

`LOCAL_DATA_DIRS` 다음 줄에 변수를 하나 넣는다.

```make
# SB_LOCAL_NOTES_DIR/SB_GITIGNORE_PENDING in scripts/lib/common.sh: removed only after Basic Memory was recreated.
SB_LOCAL_PENDING := .local-data/knowledge/basic-memory/.gitignore.pending
```

```make
local-up: ## Start Basic Memory and SilverBullet locally (127.0.0.1:BM_PORT, SB_PORT) and wait until healthy
	mkdir -p $(LOCAL_DATA_DIRS)
	gitignore_state="$$(scripts/sb-space.sh --local)" || exit 1; \
	  if [[ "$$gitignore_state" == changed ]]; then \
	    $(COMPOSE) up -d --wait --force-recreate basic-memory && rm -f $(SB_LOCAL_PENDING) \
	      && gitignore_state="$$(scripts/sb-space.sh --local)" && [[ "$$gitignore_state" == unchanged ]]; fi
	$(COMPOSE) up -d --wait
```

- macOS의 GNU make 3.81은 `.SHELLFLAGS`(3.82부터)를 적용하지 않아 레시피 줄이 `-e` 없이 돈다(Verified, 사전 점검: `x="$$(false)"; echo still-ran`이 `still-ran`을 출력). 그래서 첫 `sb-space.sh` 대입 뒤에 `|| exit 1`을 붙여, 실패하면 SilverBullet을 띄우기 전에 레시피를 멈춘다.
- `[[ "$(…)" == … ]]`처럼 조건 안에서 명령 치환을 쓰면 실패가 조용히 넘어가므로 그렇게 쓰지 않는다.
- `if` 안은 `&&` 사슬이다. 재생성, 표시 파일 삭제, 페이지를 쓰는 두 번째 `sb-space.sh`(`unchanged`여야 함) 중 하나라도 실패하면 `if`의 종료 코드가 0이 아니게 되어 그 줄이 실패하고 레시피가 멈춘다. 재생성이 실패하면 표시 파일이 남아 다음 `local-up`이 다시 재생성한다.

- [ ] **Step 8: 통과 확인**

Run: `make check`
Expected: exit 0. `sb_space.bats` 3개가 ok이고, 커버리지 목록에 `/repo/scripts/sb-space.sh`가 나온다.

- [ ] **Step 9: 로컬 순서 확인**

```bash
make local-up 2>&1 | grep -c 'notes .gitignore changed'
make local-up 2>&1 | grep -c 'notes .gitignore changed'
```

Expected:
- 첫 번째는 `1`이다. Basic Memory를 다시 만든 뒤 페이지를 쓰고 SilverBullet이 뜬다.
- 두 번째는 `0`이다. `docker compose ps`에서 `basic-memory-server`의 Up 시간이 첫 실행 이후로 이어진다(다시 만들지 않음).
- 첫 실행 뒤 `.local-data/knowledge/basic-memory/`에 `Library/agent-hub/agent-hub.md`와 `index.md`가 있고 `.gitignore.pending`은 없다.
- 결과를 Progress log에 적는다.

- [ ] **Step 10: 커밋과 push**

```bash
git add silverbullet scripts/sb-space.sh scripts/lib/common.sh tests/stubs/sudo tests/sb_space.bats Makefile
git commit -m "feat: write the SilverBullet space files before the containers start" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 2"
git push
```

### Task 3: 로그인·셸 검증 (`verify-sb.sh`)과 `local-verify`

**Files:**
- Create: `scripts/verify-sb.sh`(실행 권한), `tests/verify_sb.bats`
- Modify: `scripts/lib/common.sh`(`require_sb_user`), `tests/stubs/curl`(SilverBullet 모드), `Makefile`(`local-verify`)

**Interfaces:**
- Consumes: Task 2의 `SB_FONTS_REL_DIR`
- Produces:
  - `require_sb_user`(`common.sh`): `SB_USER`가 없거나 형식이 틀리면 값을 출력하지 않고 `die`한다. Task 5의 `deploy.sh`·`restore.sh`가 쓴다.
  - `scripts/verify-sb.sh [--read-only] URL`: 통과하면 exit 0과 `OK: SilverBullet checks passed for <URL>`, `--read-only`는 `OK: SilverBullet answers and refuses requests without a login`. [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md)의 `verify-vm.sh`가 `https://<host>.<domain>:8443`으로 부른다.
  - curl 스텁의 SilverBullet 모드. 환경변수는 `CURL_SB_PING_STATUS`, `CURL_SB_FS_STATUS`, `CURL_SB_FONT_STATUS`, `CURL_SB_AUTH_STATUS`, `CURL_SB_SHELL_STATUS`, `CURL_SB_AUTH_BODY`, `CURL_SB_COOKIE`다. 로그인 표준입력은 `$STUB_LOG.stdin`에 쌓인다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/verify_sb.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs curl
  export SB_USER=admin:test-password
  VERIFY_SB="$REPO_DIR/scripts/verify-sb.sh"
}

@test "logs in with the password on stdin only, checks the cookie and the disabled shell, warns about fonts and logs out" {
  run "$VERIFY_SB" http://127.0.0.1:3000
  assert_success
  assert_output --partial "OK: SilverBullet checks passed for http://127.0.0.1:3000"
  refute_output --partial "WARNING"
  refute_output --partial "test-password"
  refute_output --partial "stub-session-token"
  run grep -F "test-password" "$STUB_LOG"
  assert_failure
  run cat "$STUB_LOG.stdin"
  assert_output "test-password"
  run grep -F "http://127.0.0.1:3000/.logout" "$STUB_LOG"
  assert_success

  CURL_SB_FONT_STATUS=404 run "$VERIFY_SB" http://127.0.0.1:3000
  assert_success
  assert_output --partial "WARNING: the font"
}

@test "fails when SilverBullet is down, open without a login, refuses the login, sets a weak cookie or runs shell commands" {
  local case
  for case in \
    "CURL_SB_PING_STATUS=000" \
    "CURL_SB_FS_STATUS=200" \
    'CURL_SB_AUTH_BODY={"status":"error","error":"Invalid username and/or password"}' \
    "CURL_SB_AUTH_STATUS=500" \
    "CURL_SB_COOKIE=" \
    "CURL_SB_COOKIE=set-cookie: auth_x=t; Path=/; HttpOnly" \
    "CURL_SB_COOKIE=set-cookie: auth_x=t; Path=/; SameSite=Lax" \
    "CURL_SB_SHELL_STATUS=200"; do
    run env "$case" "$VERIFY_SB" http://127.0.0.1:3000
    [[ "$status" -ne 0 ]] || fail "expected a failure with $case; got: $output"
  done
  # Over https the session cookie must also be Secure (Tailscale Serve sends X-Forwarded-Proto: https).
  run "$VERIFY_SB" https://agent-hub.example.ts.net:8443
  assert_failure
  CURL_SB_COOKIE="set-cookie: auth_x=t; Path=/; SameSite=Lax; HttpOnly; Secure" run "$VERIFY_SB" https://agent-hub.example.ts.net:8443
  assert_success
}

@test "--read-only stops before the login and needs no SB_USER" {
  unset SB_USER
  run "$VERIFY_SB" --read-only http://127.0.0.1:3000
  assert_success
  run grep -F "/.auth" "$STUB_LOG"
  assert_failure
}

@test "rejects an SB_USER that make or docker compose would change, before contacting the server" {
  local value
  for value in "" "admin" "admin:pa ss" 'admin:pa$ss' "admin:pa#ss" "admin:pa'ss" 'admin:pa"ss' "ad min:secret123"; do
    SB_USER="$value" run "$VERIFY_SB" http://127.0.0.1:3000
    [[ "$status" -ne 0 ]] || fail "expected SB_USER '$value' to be rejected"
    if [[ "$value" == *:* ]]; then
      refute_output --partial "${value#*:}"
    fi
  done
  run grep -c '^curl ' "$STUB_LOG"
  assert_output 0
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `verify_sb.bats` 4개가 `scripts/verify-sb.sh: No such file or directory`로 실패한다. 나머지는 PASS한다.

- [ ] **Step 3: `tests/stubs/curl`에 SilverBullet 모드 추가**

머리 주석, 변수, 인자 루프를 아래로 바꾸고 디스패치를 더한다. 그 아래(`if [[ -z "${CURL_FIXTURES:-}" ]]; then`부터 끝까지)의 MCP 모드와 다운로드 모드는 그대로 둔다.

```bash
#!/usr/bin/env bash
# Test stub for curl.
# MCP mode (CURL_FIXTURES set): answers JSON-RPC requests from fixture files named after the method:
#   initialize, notifications_initialized, tools_list, call_<tool> (.body and optional .status).
#   Request payloads are appended to $STUB_LOG.requests. CURL_STUB_EXIT=<n> simulates a transport error.
# SilverBullet mode (URL path /.ping, /.fs/..., /.auth, /.shell or /.logout): answers like a server with a login and
#   the shell off; see sb_response for the overrides.
# Download mode: writes "stub" to the -o file, or prints $CURL_STUB_SCRIPT (default "true") for `curl | sh`.
set -euo pipefail
printf 'curl %s\n' "$*" >>"$STUB_LOG"

headers_file=""
body_file=""
data=""
cookie_jar=""
url=""

# sb_response -> print the status code and write the headers and body of a SilverBullet answer. Overrides:
# CURL_SB_{PING,FS,FONT,AUTH,SHELL}_STATUS, CURL_SB_AUTH_BODY and CURL_SB_COOKIE (the login's Set-Cookie line, empty for
# none). The login's stdin (the password) is appended to $STUB_LOG.stdin.
sb_response() {
  local status=200 body="" headers=""
  local ok_body='{"status":"ok","redirect":"/"}'
  local cookie_line='set-cookie: auth_agent-hub=stub-session-token; Path=/; Max-Age=604800; SameSite=Lax; HttpOnly'
  case "$url" in
    */.ping) status="${CURL_SB_PING_STATUS:-200}" ;;
    */.fs/Library/agent-hub/fonts/*) status="${CURL_SB_FONT_STATUS:-200}" ;;
    */.fs/*) status="${CURL_SB_FS_STATUS:-401}" ;;
    */.shell) status="${CURL_SB_SHELL_STATUS:-405}" ;;
    */.logout) status=302 ;;
    */.auth)
      cat >>"$STUB_LOG.stdin"
      status="${CURL_SB_AUTH_STATUS:-200}"
      body="${CURL_SB_AUTH_BODY-$ok_body}"
      headers="${CURL_SB_COOKIE-$cookie_line}"
      if [[ -n "$headers" && -n "$cookie_jar" ]]; then
        echo "stub-jar" >"$cookie_jar"
      fi
      ;;
  esac
  if [[ -n "$headers_file" ]]; then
    printf 'HTTP/1.1 %s\r\n%s\r\n\r\n' "$status" "$headers" >"$headers_file"
  fi
  if [[ -n "$body_file" ]]; then
    printf '%s' "$body" >"$body_file"
  fi
  printf '%s' "$status"
}

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
    -c)
      cookie_jar="$2"
      shift 2
      ;;
    http://* | https://*)
      url="$1"
      shift
      ;;
    *) shift ;;
  esac
done

case "$url" in
  */.ping | */.fs/* | */.auth | */.shell | */.logout)
    sb_response
    exit 0
    ;;
esac
```

- [ ] **Step 4: `require_sb_user` (`scripts/lib/common.sh`, `require_env` 다음)**

```bash
# Characters that make (it includes .env literally), docker compose .env files and form encoding all keep as they are.
readonly SB_USER_PATTERN='^[A-Za-z0-9._-]+:[A-Za-z0-9._~+/=-]+$'

# require_sb_user -> dies unless SB_USER is set and looks like <user>:<password>. Never prints the value.
require_sb_user() {
  require_env SB_USER
  [[ "$SB_USER" =~ $SB_USER_PATTERN ]] \
    || die "SB_USER must be <user>:<password> made of letters, digits and ._~+/=- (make and docker compose change other characters): fix it in .env in the main checkout"
}
```

- [ ] **Step 5: `scripts/verify-sb.sh` 구현 (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Check a SilverBullet server: it answers, refuses requests without a login, accepts SB_USER, sets a SameSite=Lax
# HttpOnly session cookie (also Secure over https), keeps the shell disabled, and has the fonts (warning only).
# The session is signed out at the end, also after a failure. Never prints SB_USER or the session cookie.
# Usage: verify-sb.sh [--read-only] URL   (URL like http://127.0.0.1:3000; --read-only stops before the login)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly CURL_TIMEOUT_SECONDS=15
readonly FONT_PATH="/.fs/$SB_FONTS_REL_DIR/D2KodingLigatureNerdFont-Regular.woff2"
readonly SHELL_PROBE_BODY='{"cmd":"true","args":[]}'

URL=""
WORK=""

# http_status CURL_ARGS... -> the HTTP status of the request; 000 when the server cannot be reached.
http_status() {
  curl -sS -m "$CURL_TIMEOUT_SECONDS" -o /dev/null -w '%{http_code}' "$@" || true
}

# shellcheck disable=SC2317  # invoked via trap
cleanup() {
  if [[ -s "$WORK/cookies" ]]; then
    http_status -b "$WORK/cookies" "$URL/.logout" >/dev/null
  fi
  rm -rf "$WORK"
}

check_open_endpoints() {
  local status
  status="$(http_status "$URL/.ping")"
  [[ "$status" == 200 ]] \
    || die "SilverBullet does not answer at $URL/.ping (HTTP $status): start it with 'make local-up' (local) or check 'make status' (VM)"
  status="$(http_status "$URL/.fs/index.md")"
  [[ "$status" == 401 ]] \
    || die "SilverBullet answered $URL/.fs/index.md with HTTP $status instead of 401 without a login: SB_USER must be set when the container starts"
  log "OK: SilverBullet answers and refuses requests without a login"
}

# login -> sign in as SB_USER and keep the session cookie in $WORK/cookies. The password reaches curl on stdin.
# SilverBullet answers a wrong password with HTTP 200 too, so the JSON status and the cookie decide.
login() {
  local status result cookie
  status="$(printf '%s' "${SB_USER#*:}" | curl -sS -m "$CURL_TIMEOUT_SECONDS" -o "$WORK/login.json" \
    -D "$WORK/login.headers" -c "$WORK/cookies" -w '%{http_code}' \
    --data-urlencode "username=${SB_USER%%:*}" --data-urlencode "password@-" "$URL/.auth")" || true
  result="$(jq -r '.status // empty' "$WORK/login.json" 2>/dev/null)" || result=""
  [[ "$status" == 200 && "$result" == ok ]] \
    || die "login to $URL failed (HTTP $status): SB_USER in the main checkout .env must match the running container (after changing it, rerun 'make local-up' or 'make deploy')"
  cookie="$(grep -i '^set-cookie: auth_' "$WORK/login.headers" | tr -d '\r')" || cookie=""
  [[ -n "$cookie" ]] || die "login to $URL set no session cookie"
  [[ "$cookie" == *"SameSite=Lax"* && "$cookie" == *"HttpOnly"* ]] \
    || die "the session cookie from $URL lacks SameSite=Lax or HttpOnly"
  if [[ "$URL" == https://* && "$cookie" != *"Secure"* ]]; then
    die "the session cookie from $URL lacks Secure: check that Tailscale Serve forwards X-Forwarded-Proto: https"
  fi
  log "OK: SilverBullet login and session cookie flags"
}

check_signed_in_limits() {
  local status
  status="$(http_status -b "$WORK/cookies" -X POST -H 'Content-Type: application/json' -d "$SHELL_PROBE_BODY" "$URL/.shell")"
  [[ "$status" == 405 ]] \
    || die "SilverBullet answered a shell request with HTTP $status instead of 405: keep SB_SHELL_BACKEND off in compose.yaml"
  log "OK: the SilverBullet shell is disabled"
  status="$(http_status -b "$WORK/cookies" "$URL$FONT_PATH")"
  if [[ "$status" != 200 ]]; then
    log "WARNING: the font $FONT_PATH is missing (HTTP $status), so browsers fall back to other fonts: run 'make sb-fonts' (LOCAL=1 for the local stack)"
  fi
}

main() {
  local read_only=""
  if [[ "${1:-}" == --read-only ]]; then
    read_only=1
    shift
  fi
  URL="${1:-}"
  [[ "$URL" =~ ^https?://[^/]+$ ]] || die "usage: verify-sb.sh [--read-only] http(s)://HOST[:PORT]"
  require_cmd curl jq
  [[ -n "$read_only" ]] || require_sb_user

  step "check SilverBullet at $URL"
  check_open_endpoints
  [[ -z "$read_only" ]] || return 0
  WORK="$(mktemp -d)" || exit 1
  trap cleanup EXIT
  login
  check_signed_in_limits
  log "OK: SilverBullet checks passed for $URL"
}

main "$@"
```

- [ ] **Step 6: `Makefile`의 `local-verify`**

```make
local-verify: ## Verify the local MCP endpoint (plain and *.ts.net Host header) and the local SilverBullet login
	scripts/verify-mcp.sh "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-mcp.sh --host-header agent-hub.example.ts.net "http://127.0.0.1:$(BM_PORT)/mcp"
	scripts/verify-sb.sh "http://127.0.0.1:$(SB_PORT)"
```

- [ ] **Step 7: 통과 확인**

Run: `make check`
Expected: exit 0. `verify_sb.bats` 4개가 ok이고, curl 스텁을 쓰는 `verify_mcp.bats`·`bootstrap.bats`·`vm_ops.bats`도 PASS한다.

- [ ] **Step 8: 실제 서버로 확인**

Run: `make local-up local-verify`
Expected:
- `OK: MCP round trip passed` 두 번과 `OK: SilverBullet checks passed for http://127.0.0.1:3000`이 나온다.
- 로그인이 통과하면 `--data-urlencode "password@-"`가 표준입력의 비밀번호를 그대로 보낸다는 것이 확인된다(스펙 §3 Assumption).
- 글꼴을 아직 올리지 않았으므로 `WARNING: the font`가 나오는 것이 정상이다.
- 결과를 Progress log에 적는다.

- [ ] **Step 9: 커밋과 push**

```bash
git add scripts/verify-sb.sh scripts/lib/common.sh tests/stubs/curl tests/verify_sb.bats Makefile
git commit -m "feat: verify the SilverBullet login, cookie flags and disabled shell" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 3"
git push
```

### Task 4: 글꼴 (`sb-fonts.sh`, `make sb-fonts`)

**Files:**
- Create: `scripts/sb-fonts.sh`(실행 권한), `tests/stubs/python3`(실행 권한), `tests/sb_fonts.bats`
- Modify: `Makefile`(`sb-fonts` 타깃, `.PHONY`)

**Interfaces:**
- Consumes: Task 2의 `notes_dir_arg`, `write_notes_file`, `SB_FONTS_REL_DIR`
- Produces: `scripts/sb-fonts.sh [--local]`. 입력은 `${SB_FONT_DIR:-$HOME/Library/Fonts}/D2KodingLigatureNerdFont-{Regular,Bold}.ttf`, 출력은 노트 폴더의 `Library/agent-hub/fonts/D2KodingLigatureNerdFont-{Regular,Bold}.woff2`. Make 타깃은 `make sb-fonts`(VM)와 `make sb-fonts LOCAL=1`이다.

- [ ] **Step 1: 실패하는 테스트 작성 (`tests/sb_fonts.bats`)**

```bash
#!/usr/bin/env bats
load helpers

setup() {
  setup_stubs ssh sudo python3
  use_vm_env
  export SB_FONT_DIR="$BATS_TEST_TMPDIR/fonts"
  mkdir -p "$SB_FONT_DIR"
  echo ttf >"$SB_FONT_DIR/D2KodingLigatureNerdFont-Regular.ttf"
  echo ttf >"$SB_FONT_DIR/D2KodingLigatureNerdFont-Bold.ttf"
  SB_FONTS="$REPO_DIR/scripts/sb-fonts.sh"
  FONTS="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/fonts"
}

@test "converts Regular and Bold to WOFF2 and writes them into the VM notes folder as the container user" {
  run "$SB_FONTS"
  assert_success
  run cat "$FONTS/D2KodingLigatureNerdFont-Regular.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Regular.ttf"
  run cat "$FONTS/D2KodingLigatureNerdFont-Bold.woff2"
  assert_output "woff2 D2KodingLigatureNerdFont-Bold.ttf"
  run grep -F 'sudo -n -u #1000 sh -c' "$STUB_LOG"
  assert_success
}

@test "writes nothing when a font file or fontTools is missing" {
  rm "$SB_FONT_DIR/D2KodingLigatureNerdFont-Bold.ttf"
  run "$SB_FONTS"
  assert_failure
  assert_output --partial "SB_FONT_DIR"
  echo ttf >"$SB_FONT_DIR/D2KodingLigatureNerdFont-Bold.ttf"
  PYTHON3_STUB_NO_MODULES=1 run "$SB_FONTS"
  assert_failure
  assert_output --partial "pip install --user fonttools brotli"
  run grep -c '^ssh ' "$STUB_LOG"
  assert_output 0
  [[ ! -e "$FONTS" ]] || fail "nothing may be written when a check fails: $FONTS exists"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: `sb_fonts.bats` 2개가 실패한다(스크립트·스텁 없음). 나머지는 PASS한다.

- [ ] **Step 3: `tests/stubs/python3` (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Test stub for python3: `-c ...` (the fontTools import check) fails when PYTHON3_STUB_NO_MODULES is set;
# `-m fontTools.ttLib.woff2 compress ... -o OUT IN` writes "woff2 <basename of IN>" to OUT.
set -euo pipefail
printf 'python3 %s\n' "$*" >>"$STUB_LOG"
out=""
in=""
while (($#)); do
  case "$1" in
    -c)
      if [[ -n "${PYTHON3_STUB_NO_MODULES:-}" ]]; then
        echo "ModuleNotFoundError: No module named 'fontTools'" >&2
        exit 1
      fi
      exit 0
      ;;
    -o)
      out="$2"
      shift 2
      ;;
    *)
      in="$1"
      shift
      ;;
  esac
done
printf 'woff2 %s\n' "$(basename "$in")" >"$out"
```

- [ ] **Step 4: `scripts/sb-fonts.sh` 구현 (`chmod +x`)**

```bash
#!/usr/bin/env bash
# Convert the D2KodingLigature Nerd Font (Regular and Bold) to WOFF2 and write both files into the SilverBullet space,
# where the managed library page loads them with @font-face. The fonts stay out of git (4.7 MB, Nerd Fonts licenses).
# Usage: sb-fonts.sh [--local]   (reads the TTFs from $SB_FONT_DIR, default ~/Library/Fonts)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

readonly FONT_FILE_PREFIX=D2KodingLigatureNerdFont
readonly FONT_STYLES="Regular Bold"
readonly FONT_RELEASES_URL=https://github.com/ryanoasis/nerd-fonts/releases

WORK=""

main() {
  local local_dir font_dir="${SB_FONT_DIR:-$HOME/Library/Fonts}" style name
  local_dir="$(notes_dir_arg "$@")" || exit 1
  for style in $FONT_STYLES; do
    [[ -f "$font_dir/$FONT_FILE_PREFIX-$style.ttf" ]] \
      || die "missing $font_dir/$FONT_FILE_PREFIX-$style.ttf: install the D2Coding Nerd Font from $FONT_RELEASES_URL or point SB_FONT_DIR at the folder that has it"
  done
  require_cmd python3
  # Plain python3, not -I: -I drops the user site-packages, where the suggested pip install --user puts fontTools.
  python3 -c 'import fontTools.ttLib.woff2, brotli' 2>/dev/null \
    || die "python3 cannot write WOFF2 yet: python3 -m pip install --user fonttools brotli"

  WORK="$(mktemp -d)" || exit 1
  trap 'rm -rf "$WORK"' EXIT
  for style in $FONT_STYLES; do
    name="$FONT_FILE_PREFIX-$style.woff2"
    python3 -m fontTools.ttLib.woff2 compress -q -o "$WORK/$name" "$font_dir/$FONT_FILE_PREFIX-$style.ttf" \
      || die "could not convert $FONT_FILE_PREFIX-$style.ttf to WOFF2"
    write_notes_file "$local_dir" "$SB_FONTS_REL_DIR/$name" <"$WORK/$name" \
      || die "could not write $SB_FONTS_REL_DIR/$name into the notes folder"
    log "wrote $SB_FONTS_REL_DIR/$name"
  done
  log "done: reload SilverBullet in the browser"
}

main "$@"
```

- [ ] **Step 5: `Makefile`**

`.PHONY` 줄에 `sb-fonts`를 더하고, `logs` 타깃 다음에 넣는다.

```make
sb-fonts: ## Convert the D2Koding Nerd Font to WOFF2 and upload it to the VM notes folder (LOCAL=1: the local stack)
	scripts/sb-fonts.sh $(if $(LOCAL),--local)
```

- [ ] **Step 6: 통과 확인**

Run: `make check`
Expected: exit 0. `sb_fonts.bats` 2개가 ok이고, 커버리지 목록에 `sb-fonts.sh`가 나온다.

- [ ] **Step 7: 로컬 글꼴 확인**

```bash
ls ~/Library/Fonts/D2KodingLigatureNerdFont-Regular.ttf ~/Library/Fonts/D2KodingLigatureNerdFont-Bold.ttf
make sb-fonts LOCAL=1
make local-verify 2>&1 | grep -c 'WARNING: the font'
```

Expected:
- 두 TTF가 있다.
- `make sb-fonts LOCAL=1`이 `wrote Library/agent-hub/fonts/…woff2` 두 줄로 끝난다.
- 마지막 명령은 `0`이다.
- Mac의 `python3`에 fontTools·brotli가 없으면, 스크립트가 안내한 `pip` 명령을 사용자에게 알린다. 설치는 사용자가 한다.
- 결과를 Progress log에 적는다.

- [ ] **Step 8: 커밋과 push**

```bash
git add scripts/sb-fonts.sh tests/stubs/python3 tests/sb_fonts.bats Makefile
git commit -m "feat: upload the D2Koding web fonts into the SilverBullet space" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 4"
git push
```

### Task 5: `deploy`·`restore`의 `SB_USER`와 공간 파일

**Files:**
- Modify: `scripts/lib/common.sh`(`vm_env`), `scripts/deploy.sh`(전체), `scripts/restore.sh:95-101,110`
- Test: `tests/helpers.bash`(`use_vm_env`), `tests/vm_ops.bats`(배포 테스트), `tests/backup_restore.bats`(복원 테스트)

**Interfaces:**
- Consumes: Task 2의 `scripts/sb-space.sh`(표준출력 `changed`|`unchanged`), `in_notes_dir`, `SB_GITIGNORE_PENDING`, Task 3의 `require_sb_user`
- Produces:
  - `vm_env`가 다섯 줄을 출력한다: `BM_PORT`, `BM_KNOWLEDGE_DIR`, `BM_CONFIG_DIR`, `SB_PORT`, `SB_USER`. 호출자는 먼저 `require_sb_user`를 부른다.
  - `use_vm_env`(테스트 헬퍼)가 `SB_USER=admin:test-password`와 `SB_PORT=3000`을 export한다. [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md)의 VM 테스트도 이 값에 기댄다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/helpers.bash`의 `use_vm_env` 첫 줄 다음에 넣는다.

```bash
  export SB_USER=admin:test-password SB_PORT=3000
```

`tests/vm_ops.bats`의 배포 성공 테스트(현재 `:15-29`)를 아래로 바꾸고, 그다음에 두 테스트를 넣는다. 스텁 로그에는 같은 명령이 `ssh … <명령>` 줄과 `docker …` 줄로 두 번 남으므로, 개수는 `^docker ` 줄만 센다.

```bash
@test "deploy uploads compose.yaml, an owner-only VM .env with SB_USER and the space files, then pulls and waits for healthy" {
  install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  assert_output --partial "deployed. Next: make verify"
  refute_output --partial "test-password"
  run diff "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml"
  assert_success
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "BM_PORT=8737"
  assert_line "BM_KNOWLEDGE_DIR=$BM_REMOTE_DATA_ROOT/knowledge"
  assert_line "BM_CONFIG_DIR=$BM_REMOTE_DATA_ROOT/config"
  assert_line "SB_PORT=3000"
  assert_line "SB_USER=admin:test-password"
  run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
  assert_output "600"
  run diff "$REPO_DIR/silverbullet/notes.gitignore" "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/.gitignore"
  assert_success
  run diff "$REPO_DIR/silverbullet/agent-hub.md" "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md"
  assert_success
  run grep -F 'docker compose pull -q' "$STUB_LOG"
  assert_success
  run grep -F 'docker compose up -d --wait --wait-timeout 360' "$STUB_LOG"
  assert_success
}

@test "deploy recreates Basic Memory before starting SilverBullet only when the notes .gitignore changed, and writes the pages after the recreate" {
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
  run awk '/^docker compose .*--force-recreate basic-memory$/ { r = NR } /^docker compose up -d --wait --wait-timeout 360$/ { u = NR } END { exit !(r && u && r < u) }' "$STUB_LOG"
  assert_success
  # The first write of the library page comes after the recreate, so the old Basic Memory never indexes it.
  run awk '/^docker compose .*--force-recreate basic-memory$/ { r = NR } /^sudo .*Library\/agent-hub\/agent-hub\.md/ && !p { p = NR } END { exit !(r && p && r < p) }' "$STUB_LOG"
  assert_success
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
}

@test "deploy still recreates Basic Memory on the retry after the image pull failed behind a new notes .gitignore" {
  local page="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/Library/agent-hub/agent-hub.md"
  export DOCKER_STUB_FAIL_MATCH="pull -q"
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "0"
  [[ ! -e "$page" ]] || fail "the pages must wait until Basic Memory was recreated"
  unset DOCKER_STUB_FAIL_MATCH
  run "$REPO_DIR/scripts/deploy.sh"
  assert_success
  run grep -c '^docker compose .*--force-recreate basic-memory$' "$STUB_LOG"
  assert_output "1"
  [[ ! -e "$BM_REMOTE_DATA_ROOT/knowledge/basic-memory/.gitignore.pending" ]] \
    || fail "the marker must be removed once Basic Memory was recreated"
  [[ -e "$page" ]] || fail "the retry must write the pages after the recreate"
}

@test "deploy leaves the VM untouched without a valid SB_USER" {
  unset SB_USER
  run "$REPO_DIR/scripts/deploy.sh"
  assert_failure
  run grep -c '^ssh ' "$STUB_LOG"
  assert_output "0"
}
```

`tests/backup_restore.bats`의 "restore replaces the data, keeps the previous copy and fixes ownership"(현재 `:190`)를 고친다.
- `make_archive "from backup"` 다음 줄에 `install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env"`를 넣는다.
- 마지막 `assert_failure` 다음에 아래 줄을 넣는다.

```bash
  run cat "$BM_REMOTE_APP_DIR/.env"
  assert_line "SB_USER=admin:test-password"
  run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
  assert_output "600"
```

같은 파일의 "restore aborts without touching the VM unless the user types yes" 다음에 넣는다.

```bash
@test "restore stops before the confirmation without a valid SB_USER, so the VM .env never loses the login" {
  make_archive "x"
  unset SB_USER
  restore_with_answer yes
  assert_failure
  run grep -F 'ssh' "$STUB_LOG"
  assert_failure
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}
```

- [ ] **Step 2: 실패 확인**

Run: `make test`
Expected: 다음 테스트만 실패한다.
- 배포 테스트 4개: `.env`에 `SB_USER` 줄이 없음, `force-recreate` 없음(두 테스트), `SB_USER` 없이도 ssh가 실행됨
- 바꾼 복원 성공 테스트: `.env`에 `SB_USER` 없음, 권한 644
- 새 복원 테스트

나머지는 PASS한다.

- [ ] **Step 3: 구현**

`scripts/lib/common.sh`의 `vm_env`:

```bash
# vm_env -> the .env content for the VM: loopback ports, absolute data paths and the SilverBullet login (shared by
# deploy and restore; both run require_sb_user first).
vm_env() {
  printf 'BM_PORT=%s\n' "${BM_PORT:-8737}"
  printf 'BM_KNOWLEDGE_DIR=%s/knowledge\n' "$BM_REMOTE_DATA_ROOT"
  printf 'BM_CONFIG_DIR=%s/config\n' "$BM_REMOTE_DATA_ROOT"
  printf 'SB_PORT=%s\n' "${SB_PORT:-3000}"
  printf 'SB_USER=%s\n' "$SB_USER"
}
```

`scripts/deploy.sh` 전체:

```bash
#!/usr/bin/env bash
# Copy compose.yaml, a generated .env and the SilverBullet space files to the VM, then pull and start Basic Memory
# and SilverBullet. While sb-space.sh reports the notes .gitignore as changed it has written only .gitignore: Basic
# Memory reads it only at start, so it is recreated first, the marker is cleared only after that succeeds (a failed
# run asks again), and sb-space.sh runs again to write the pages the recreated Basic Memory now ignores.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

main() {
  local gitignore_state env_file="$BM_REMOTE_APP_DIR/.env"
  require_cmd ssh
  require_env BM_VM_HOST BM_VM_USER
  require_sb_user

  step "upload compose.yaml to $BM_VM_HOST:$BM_REMOTE_APP_DIR"
  remote "cat > $BM_REMOTE_APP_DIR/compose.yaml" <"$REPO_DIR/compose.yaml" \
    || die "upload failed: is $BM_VM_HOST reachable over Tailscale SSH? (ssh $BM_VM_USER@$BM_VM_HOST true)"

  step "write $env_file (owner only: it holds SB_USER)"
  # umask covers only new files, so an existing .env is made owner-only before the login goes in.
  vm_env | remote "touch $env_file && chmod 600 $env_file && cat > $env_file" \
    || die "could not write $env_file on the VM"

  step "write the SilverBullet space files"
  gitignore_state="$("$SCRIPT_DIR/sb-space.sh")" || die "could not write the SilverBullet space files on the VM"

  step "pull images"
  remote_compose "pull -q" || die "image pull failed on the VM: check its network, then 'make logs'"
  if [[ "$gitignore_state" == changed ]]; then
    step "recreate Basic Memory so it loads the new notes .gitignore (waits up to ${HEALTH_TIMEOUT_SECONDS}s)"
    remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS --force-recreate basic-memory" \
      || die "Basic Memory did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"
    in_notes_dir "" "rm -f $SB_GITIGNORE_PENDING" </dev/null \
      || die "could not remove $SB_GITIGNORE_PENDING on the VM: the next deploy recreates Basic Memory again"
    step "write the SilverBullet pages now that Basic Memory ignores them"
    gitignore_state="$("$SCRIPT_DIR/sb-space.sh")" || die "could not write the SilverBullet pages on the VM"
    [[ "$gitignore_state" == unchanged ]] \
      || die "the notes .gitignore changed again during the deploy, so the SilverBullet pages were not written: run 'make deploy' again"
  fi
  step "start Basic Memory and SilverBullet (waits up to ${HEALTH_TIMEOUT_SECONDS}s for healthy)"
  remote_compose "up -d --wait --wait-timeout $HEALTH_TIMEOUT_SECONDS" \
    || die "containers did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s: run 'make logs'"

  log "deployed. Next: make verify"
}

main "$@"
```

`scripts/restore.sh`:
- `require_env BM_VM_HOST BM_VM_USER`(현재 `:110`) 다음 줄에 `require_sb_user`를 넣는다.
- `upload_vm_file`(현재 `:95-101`)의 주석 끝에 한 문장을 더하고, 원격 명령 앞에 `umask 077 &&`를 붙인다.

```bash
# upload_vm_file TARGET PREV: keep a copy of TARGET at PREV, then replace TARGET with stdin. Both writes go to
# a temp name first and are moved into place only when complete, so a partial copy never replaces a good file
# or becomes the rollback source; on failure the temp files are removed. Files are written owner-only, because
# the VM .env holds SB_USER.
upload_vm_file() {
  local target="$1" prev="$2" tmp="$1.upload-$STAMP"
  remote "umask 077 && mkdir -p $BM_REMOTE_APP_DIR && { if [ -e $target ]; then cp $target $prev.partial && mv $prev.partial $prev; fi && cat > $tmp && mv $tmp $target; } || { rm -f $tmp $prev.partial; exit 1; }"
}
```

- [ ] **Step 4: 통과 확인**

Run: `make check`
Expected: exit 0. 바꾼 테스트와 새 테스트가 모두 ok다. "deploy reports an unhealthy container"는 `did not become healthy within 360s`로 계속 통과한다.

- [ ] **Step 5: 커밋과 push**

```bash
git add scripts/lib/common.sh scripts/deploy.sh scripts/restore.sh tests/helpers.bash tests/vm_ops.bats tests/backup_restore.bats
git commit -m "feat: deploy and restore the SilverBullet login and space files to the VM" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 5"
git push
```

### Task 6: 로컬 E2E (브라우저, 사용자와 함께)

컨트롤러가 메인 세션에서 진행한다. 비밀번호는 사용자가 직접 입력하고, 에이전트는 로그인한 브라우저의 새 탭만 쓴다.

**Files:**
- Modify: `silverbullet/agent-hub.md`(확인이 실패할 때만), 이 계획 파일(Progress log), 스펙 §3(해소한 Assumption)

**Interfaces:**
- Consumes: Task 1~5의 결과 전부
- Produces: 스펙 §1 완료 조건 1·3·4의 로컬 증거

- [ ] **Step 1: 스택 준비**

Run: `make local-up local-verify`
Expected: `OK: SilverBullet checks passed`, 글꼴 경고 없음(Task 4 이후).

- [ ] **Step 2: 사용자 로그인**

사용자에게 Chrome에서 `http://localhost:3000`을 열어 `SB_USER`로 로그인해 달라고 요청한다.
- `127.0.0.1`이 아니라 `localhost`를 쓴다. 스파이크 때 `127.0.0.1:3000`에 저장된 패널 배치가 남아 있으면 `view.defaults`를 시험할 수 없다.
- 로그인 뒤 에이전트는 `tabs_context_mcp`로 탭 목록을 보고, 새 탭에서 `http://localhost:3000/`을 연다. 쿠키를 공유하므로 새 탭도 로그인 상태다.

- [ ] **Step 3: 시드 노트 (브라우저의 `javascript_tool`, 세션 쿠키 사용)**

```js
const notes = {
  "projects/Agent Hub.md": "---\ntitle: Agent Hub\ntype: note\npermalink: main/projects/agent-hub\ntags:\n- sample\n---\n# Agent Hub\n\nBasic Memory server shared by agents over the tailnet.\n\n## Observations\n- [decision] Keep the server on one small VM #infra\n- [risk] 1GB RAM leaves little headroom #memory\n- [question] Should the web UI get its own tailnet device? #web-ui\n\n## Relations\n- uses [[tools/Basic Memory]]\n- documented_in [[research/Web UI Evaluation]]\n",
  "tools/Basic Memory.md": "---\ntitle: Basic Memory\ntype: note\npermalink: main/tools/basic-memory\ntags:\n- sample\n---\n# Basic Memory\n\n## Observations\n- [fact] Notes are plain Markdown files #storage\n- [decision] Keep the MCP port on loopback #security\n\n## Relations\n- part_of [[projects/Agent Hub]]\n",
  "research/Web UI Evaluation.md": "---\ntitle: Web UI Evaluation\ntype: note\npermalink: main/research/web-ui-evaluation\ntags:\n- sample\n---\n# Web UI Evaluation\n\n## Observations\n- [risk] Clicking a category label in SilverBullet clears it #web-ui\n- [question] Does the dashboard stay fast with many notes? #web-ui\n\n## Relations\n- for [[projects/Agent Hub]]\n",
};
const results = [];
for (const [path, text] of Object.entries(notes)) {
  const response = await fetch("/.fs/" + encodeURI(path), { method: "PUT", body: text });
  results.push(path + " " + response.status);
}
results.join("\n");
```

Expected: 세 줄 모두 `200`이다.

- [ ] **Step 4: 완료 조건 3 (레이아웃, 대시보드, 글꼴, 그래프)**

새로고침한 뒤 스크린샷으로 확인하고, 각 항목을 Progress log에 `Verified`로 적는다.
1. 왼쪽에 트리가 처음부터 열려 있다(`view.defaults`). 페이지를 열면 오른쪽에 목차가 있고, `tools/Basic Memory`의 아래쪽 Linked Mentions에 `projects/Agent Hub`가 보인다. Cmd-K를 누르면 페이지 검색이 왼쪽 칸에 열리고, Esc로 닫으면 트리가 돌아온다. **편집기에 글자를 치기 전에 포커스가 어디 있는지 스크린샷으로 확인한다.** 브레인스토밍 스파이크에서 명령 팔레트 입력칸이 포커스를 받지 못한 채 친 글자와 Enter가 편집기로 들어가 관찰 카테고리가 `[]`로 바뀐 적이 있다.
   - 테마: `javascript_tool`로 `getComputedStyle(document.documentElement).getPropertyValue("--root-background-color")`를 읽는다. 밝게는 `#ffffff`, `Editor: Toggle Dark Mode` 뒤 어둡게는 `#0d1117`이다. 관찰 카테고리 글자가 밝게 `#9a6700`, 어둡게 `#d29922`로 보인다.
   - 목차가 오른쪽에 처음부터 열려 있다. 노트 위에 흐린 정보 줄이 있다: `Updated <날짜 시각> · <n> words · ~<m> min read · <k> backlinks · memory://main/...`. `index`·`Library/…` 페이지에는 정보 줄이 없다.
   - Cmd-Shift-F로 `Search notes` 패널이 왼쪽에 열린다. `document.activeElement`의 placeholder가 `Text in notes`인지 확인한 뒤에 입력한다. `memory`를 입력하면 제목, 관찰(`[risk] … #memory`), 관계 줄이 결과로 나오고, 결과를 고르면 그 줄로 이동한다. Esc로 닫으면 트리가 돌아온다.
   - 본문 문단은 이 브라우저에서 `Space: Reindex`를 한 번 실행한 뒤에 검색된다(새 클라이언트도 같음, 스펙 §3). 실행하고 문단 문장(예: `tailne`)으로 다시 찾는다.
   - 명령 `Basic Memory: Copy memory:// Link`가 `Copied memory://main/projects/agent-hub` 알림을 띄우고, `Navigate: Random Note`가 노트 하나로 이동한다(SilverBullet 전용 페이지로는 가지 않음). 팔레트도 입력 전에 포커스를 확인한다.
   - 목차가 기본으로 열리지 않으면 SilverBullet `client/navigator/builtins.ts`(태그 `2.12.1`)에서 목차 뷰 이름을 찾는다. 그 이름을 `agent-hub.md`의 `view.defaults`에 `{ dock = "rhs", open = true }`로 더하고 Step 6으로 반영한다.
2. `index`의 대시보드에 일곱 절(Recently changed, Folders, Decisions, Risks, Open questions, Tags, Maintenance)이 있고 시드 내용이 보인다. Maintenance 링크는 SilverBullet 내장 페이지 `Library/Std/Pages/Maintenance`(끊긴 링크, 모호한 링크)를 연다.
   - Recently changed에는 세 노트만 있고 `index`·`Library/…`는 없다.
   - Folders는 `projects (1)`, `research (1)`, `tools (1)`이다.
   - Decisions·Risks·Open questions에 각각 2개가 있다.
   - Tags에 `#sample (3)`이 있다.
3. 글꼴: `javascript_tool`로 다음을 실행한다.

```js
await document.fonts.ready;
const faces = [...document.fonts].filter((f) => f.family.replace(/"/g, "") === "D2Koding Space").map((f) => f.weight + " " + f.status);
faces.join(", ") + " | " + getComputedStyle(document.querySelector(".cm-content")).fontFamily;
```

   Expected: `400 loaded, 700 loaded | "D2Koding Space", …`이다. 볼드 제목이 있는 대시보드에서 실행해야 700도 `loaded`가 된다.
4. 명령 팔레트(상단 `>_` 버튼)에서 `Graph: Explore`를 실행하면 `projects/Agent Hub` 주변 그래프가 그려진다.

- [ ] **Step 5: 완료 조건 4 (줄바꿈, frontmatter, 무시 목록)**

1. 페이지 선택기(Cmd-K)에 `research/Newline Check`를 입력하고 Enter로 새 페이지를 만든다. `first line`을 입력하고 Enter를 누른 뒤 3초 기다렸다가 `second line`을 입력한다. 10초 뒤 다음을 실행한다.

```js
await (await fetch("/.fs/research/Newline%20Check.md")).text();
```

   Expected: 정확히 다음 내용이다.

```
---
title: "Newline Check"
type: note
permalink: main/research/newline-check
---
first line
second line
```

2. MCP로 Basic Memory를 확인한다. 아래 일회용 스크립트를 이 세션의 scratchpad에 `mcp-call.sh`로 저장해 쓰고, 끝나면 지운다(저장소에 넣지 않음).

```bash
#!/usr/bin/env bash
# Throwaway: call one tool on the LOCAL Basic Memory MCP endpoint and print its text result.
# Usage: mcp-call.sh TOOL_NAME 'ARGUMENTS_JSON'
set -euo pipefail
URL="http://127.0.0.1:8737/mcp"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SID=""
post() {
  local -a h=(-sS -m 120 -D "$WORK/h" -o "$WORK/b" -w '%{http_code}' -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2025-06-18')
  [[ -n "$SID" ]] && h+=(-H "Mcp-Session-Id: $SID")
  curl "${h[@]}" -d "$1" "$URL"
}
body_json() {
  if grep -q '^data:' "$WORK/b"; then sed -n 's/^data: //p' "$WORK/b" | tail -1; else cat "$WORK/b"; fi
}
post '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"plan-10-e2e","version":"1"}}}' >/dev/null
SID="$(grep -i '^mcp-session-id:' "$WORK/h" | cut -d: -f2- | tr -d ' \r' || true)"
post '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
post "$(jq -cn --arg n "$1" --argjson a "$2" '{jsonrpc:"2.0", id:2, method:"tools/call", params:{name:$n, arguments:$a}}')" >/dev/null
body_json | jq -r 'if .error then "ERROR: " + .error.message else ([.result.content[]? | select(.type == "text") | .text] | join("\n")) end'
```

```bash
bash <scratchpad>/mcp-call.sh read_note '{"identifier":"main/research/newline-check"}'
bash <scratchpad>/mcp-call.sh search_notes '{"query":"agentHub"}'
bash <scratchpad>/mcp-call.sh search_notes '{"query":"Agent Hub"}'
```

   Expected:
   - `read_note`가 두 줄과 `permalink: main/research/newline-check`를 보여 준다. 1의 파일 내용이 그대로이므로 Basic Memory가 frontmatter를 다시 쓰지 않았다.
   - `agentHub` 검색 결과가 없다. 이 단어는 `index.md`와 `Library/agent-hub/agent-hub.md`에만 있다.
   - `Agent Hub` 검색에는 `projects/Agent Hub`가 나온다.

- [ ] **Step 6: 실패 시 고치기**

확인이 실패하면 원인을 찾는다. `Library/` 페이지의 Lua가 적용되지 않았는지, 질의 API의 이름·필드가 다른지, `table.sort` 같은 표준 함수가 없는지를 본다.
1. 먼저 SilverBullet 문서(`docs/Space Lua/Integrated Query.md`, 태그 `2.12.1`)를 확인한다.
2. `silverbullet/agent-hub.md`만 고치고 `make local-up`(관리 페이지를 덮어씀)과 새로고침으로 다시 확인한다.
3. `make check`도 다시 돌린다.
4. 고친 내용과 이유를 Progress log에 적는다.

- [ ] **Step 7: 기록과 정리**

- 스펙 §3의 "Assumption (web-ui-local 계획에서 확인)" 항목 중 확인한 것을 `Verified (web-ui-local 계획, <날짜>)`로 바꾼다. 확인 명령이나 화면 결과를 한 줄씩 붙인다.
- 시드 노트와 `research/Newline Check`는 로컬 테스트 데이터다(`.local-data`, git 제외). 지울지는 사용자에게 묻는다.
- scratchpad의 `mcp-call.sh`를 지운다.
- 브라우저 탭은 에이전트가 연 것만 닫는다.

- [ ] **Step 8: 커밋과 push**

```bash
git add docs/plans/plan-2026-10-14-n6xpm12e-web-ui-local.md docs/specs/spec-2026-10-14-cjerm8b4-silverbullet-web-ui.md
git commit -m "docs: record the local web UI checks of the web-ui-local plan" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 6"
git push
```

`silverbullet/agent-hub.md`를 고쳤다면 그 파일만 따로 커밋한다(`fix: <고친 내용>`, 같은 트레일러).

### Task 7: 문서

**Files:**
- Create: `docs/decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md`
- Modify: `docs/ARCHITECTURE.md`, `README.md`, `AGENTS.md:10,22`(사용자 승인 필요), `docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md:158`

**Interfaces:**
- Consumes: Task 6의 확인 결과(ADR 근거)
- Produces: [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md)이 VM 실측을 더할 [web-ui-silverbullet ADR](../decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md)의 "VM 측정" 절

- [ ] **Step 1: [web-ui-silverbullet ADR](../decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md) 작성 (`docs/decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md`)**

```markdown
# ADR f7n75bpv: 웹 UI로 SilverBullet

- 상태: Accepted (2026-10-14)
- 설계: [SilverBullet 웹 UI 설계](../specs/spec-2026-10-14-cjerm8b4-silverbullet-web-ui.md)

## 맥락

Self-hosted Basic Memory 0.23.2에는 웹 UI가 없습니다. REST API는 MCP 서버 프로세스 안에서만 쓰이고, 웹앱은 Basic Memory 클라우드 전용입니다. 요구는 두 가지입니다. tailnet 안의 브라우저에서 노트를 읽고 고치는 것(B), 그리고 백링크와 그래프로 둘러보는 것(C)입니다. VM은 1GB RAM e2-micro이고 Basic Memory가 이미 475~518 MiB를 씁니다.

## 결정

SilverBullet `2.12.1-slim` 컨테이너를 Basic Memory와 같은 compose 프로젝트에 두고, 같은 노트 폴더를 `/data`로 엽니다. tailnet HTTPS 8443을 Tailscale Serve로 `127.0.0.1:3000`에 연결합니다. 로그인(`SB_USER`)과 셸 끄기, 별도 Docker 네트워크를 함께 씁니다.

## 검토한 대안

| 대안 | 장점 | 버린 이유 |
|---|---|---|
| Mac의 Obsidian + 노트 동기화 | 기능이 가장 많음 | 노트를 VM 밖으로 동기화하는 경로(백업과 다른 두 번째 사본)가 생기고, 기기마다 앱을 설치해야 함 |
| Basic Memory 클라우드 웹앱 | 공식 UI | 유료 클라우드에 노트를 올려야 하고, 이 저장소의 self-hosted 구성과 맞지 않음 |
| 직접 만든 UI | 관계 타입까지 원하는 대로 표시 | 편집기·백링크·그래프를 새로 만들어야 하고, Basic Memory REST API가 프로세스 밖에 열려 있지 않음 |
| SilverBullet 전체 이미지 | 헤드리스 Chrome 등 추가 기능 | 필요 없는 런타임 API와 메모리. slim으로 충분 |

## 근거 (Verified, 2026-10-14 스파이크와 web-ui-local 계획)

- SilverBullet 서버는 1.7~10.6 MiB이고, 색인은 브라우저(IndexedDB)에서 합니다.
- 위키링크, Linked Mentions, `Graph: Explore`, 트리, 목차가 내장 기능만으로 동작합니다.
- 에이전트가 쓴 내용은 5초 안에 열린 페이지에 반영되고, SilverBullet에서 쓴 내용은 Basic Memory `search_notes`에 반영됩니다.
- 새 페이지 frontmatter를 SilverBullet 훅이 미리 채우면 Basic Memory가 파일을 다시 쓰지 않습니다. 그래서 줄바꿈이 사라지지 않습니다(훅 전 2/2 손실, 훅 뒤 0/2).
- 인증 없는 SilverBullet은 다른 사이트의 단순 POST로 셸을 실행하고 프록시를 엽니다. `SB_USER`와 `SB_SHELL_BACKEND=off`로 막습니다.
- web-ui-local 계획의 로컬 확인 결과는 web-ui-local 계획 파일(`docs/plans/plan-2026-10-14-n6xpm12e-web-ui-local.md`)의 Progress log에 있습니다.

## 결과

- 비밀값이 두 개가 됩니다: Tailscale 인증 키와 `SB_USER`. `SB_USER`는 main 체크아웃 `.env`와 VM `.env`(권한 600)에만 둡니다.
- SilverBullet은 Basic Memory 관계 타입을 그래프 엣지 이름으로 보여 주지 않습니다(모두 `mention`).
- 관찰 카테고리 글자(`[decision]`)를 누르면 카테고리가 지워집니다. 런북 경고와 업스트림 이슈로 대응합니다.
- SilverBullet 전용 페이지(`index`, `Library/`, `Inbox/` 등)는 노트 폴더의 `.gitignore`로 Basic Memory 색인에서 뺍니다.

## VM 측정

web-ui-vm-rollout 계획에서 두 컨테이너를 함께 띄운 뒤의 메모리·스왑 사용량을 여기에 기록합니다. OOM이 나면 [vm-sizing ADR](adr-2026-10-12-mdq5exsf-vm-sizing.md)을 다시 판단합니다.
```

- [ ] **Step 2: `docs/ARCHITECTURE.md`**

토폴로지 코드 블록(`:5-15`)을 다음으로 바꾼다. 브라우저 경로(8443)는 [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md)에서 더한다.

```
[개인/회사 Mac] ── tailnet ──▶ https://agent-hub.<tailnet>.ts.net/mcp
  에이전트, make deploy/verify/backup       │ Tailscale Serve (HTTPS, tailnet 전용)
  (Tailscale SSH)                           ▼
                        GCP e2-micro (us-west1-b, Ubuntu 26.04 Minimal amd64, 1GB + 스왑 1GB)
                        인바운드 허용: VPC 내부(10.128.0.0/9)만
                          └ Docker 프로젝트 basic-memory
                              basic-memory:0.23.2@sha256       127.0.0.1:8737 → :8000 /mcp   네트워크 basic-memory
                                /srv/basic-memory/knowledge → /app/data
                                /srv/basic-memory/config    → /home/appuser/.basic-memory
                              silverbullet:2.12.1-slim@sha256  127.0.0.1:3000 → :3000        네트워크 silverbullet
                                /srv/basic-memory/knowledge/basic-memory → /data (노트 폴더만)
```

구성 요소 표의 `compose.yaml` 행(`:25`)을 바꾸고, 그 아래에 한 행을 더한다.

```markdown
| `compose.yaml` | Mac(로컬 검증)·VM | Basic Memory와 SilverBullet(웹 UI) 컨테이너 정의 (같은 파일) |
| `silverbullet/` + `scripts/sb-space.sh`·`sb-fonts.sh`·`verify-sb.sh` | Mac → 노트 폴더 | SilverBullet 공간 파일(노트 `.gitignore`, 관리 페이지 `Library/agent-hub/agent-hub.md`, 대시보드 `index.md`)과 글꼴을 쓰고, 로그인·셸 꺼짐을 검사. [web-ui-silverbullet ADR](decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md) |
```

데이터 경로 표의 Markdown 노트 행(`:37`) 다음에 한 행을 더한다.

```markdown
| SilverBullet 공간 파일 | 노트 폴더 안 `.gitignore`, `index.md`, `Library/agent-hub/`(관리 페이지와 글꼴), `.silverbullet.browser-sessions.json`(로그인 세션) | 같음. Basic Memory는 `.gitignore`와 기본 무시 목록(`.*`)으로 이 파일들을 색인하지 않음 |
```

신뢰 경계의 비밀값 줄(`:52`)을 아래 두 줄로 바꾼다.

```markdown
- SilverBullet은 로그인(`SB_USER`)이 있어야 열리고, 셸 명령은 꺼져 있으며(`SB_SHELL_BACKEND=off`), Basic Memory와 다른 Docker 네트워크에 있습니다. 노트 폴더만 마운트해서 Basic Memory DB와 설정을 보지 못합니다.
- 비밀값은 두 가지입니다. Tailscale 인증 키는 저장소와 디스크에 남지 않습니다. SilverBullet 로그인 `SB_USER`는 main 체크아웃 `.env`(git ignore)와 VM `/opt/basic-memory/.env`(권한 600)에만 있고, 스크립트는 ssh·curl 표준입력으로만 넘깁니다.
```

주요 흐름의 배포 줄(`:63`)을 바꾼다.

```markdown
- **배포:** `make deploy` → compose와 VM용 `.env`(권한 600, `SB_USER` 포함) 전송 → 공간 파일 쓰기(`sb-space.sh`, 노트 `.gitignore`가 바뀌었으면 `.gitignore`만) → `docker compose pull` → `.gitignore`가 바뀌었으면 Basic Memory만 먼저 다시 만든 뒤 관리 페이지·`index.md` 쓰기 → `up -d --wait`
```

마지막 줄(`:68`)을 다음으로 바꾼다.

```markdown
관련 결정: [basic-memory-on-gcp-tailscale ADR](decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md), [vm-sizing ADR](decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md), [web-ui-silverbullet ADR](decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md)
```

- [ ] **Step 3: `README.md`**

결정 기록 줄(`:7`)을 다음으로 바꾼다.

```markdown
- 결정 기록: [basic-memory-on-gcp-tailscale ADR](docs/decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md), [vm-sizing ADR](docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md), [web-ui-silverbullet ADR](docs/decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md)
```

사전 요구사항의 리뷰 줄(`:14`) 앞에 넣는다.

```markdown
- 웹 UI 글꼴을 올릴 때만(`make sb-fonts`): `python3`와 `python3 -m pip install --user fonttools brotli`, D2Coding Nerd Font(`D2KodingLigatureNerdFont-Regular.ttf`·`-Bold.ttf`가 `~/Library/Fonts`에 있어야 함)
```

"빠르게 시작하기" 절 끝(`:31` 다음)에 넣는다.

```markdown
### 웹 UI (SilverBullet)

`make local-up`은 Basic Memory 옆에 SilverBullet을 같이 띄웁니다.
1. main 체크아웃 `.env`에 `SB_USER=<사용자>:<비밀번호>`를 적습니다(`.env.example` 참고, 비밀번호는 `openssl rand -base64 24`).
2. `http://127.0.0.1:3000`에서 로그인합니다.
3. 글꼴은 `make sb-fonts LOCAL=1`로 한 번 올립니다.

트리는 왼쪽(`Cmd-O`), 목차는 오른쪽에 있습니다. 페이지 이름 검색은 `Cmd-K`, 노트 본문 검색은 `Cmd-Shift-F`입니다(본문 문단은 브라우저마다 `Space: Reindex`를 한 번 실행한 뒤 검색됨). 그래프는 명령 팔레트의 `Graph: Explore`로 엽니다.

**주의:** 노트의 관찰 카테고리 글자(`[decision]`, `[fact]` 등)를 누르면 SilverBullet이 카테고리를 지웁니다. 실수했으면 바로 `Cmd+Z`로 되돌리세요.
```

- [ ] **Step 4: `AGENTS.md` (사용자 승인 뒤에만 커밋)**

바꿀 두 줄을 사용자에게 diff로 보여 주고 승인을 받는다.

`:10`(Local 줄)의 VM 변경 목록에 `sb-fonts`를 더한다.

```markdown
- Local: `make local-up local-verify local-down` (`make sb-fonts LOCAL=1` uploads the web fonts locally). `local-up` uses a fixed container name and port, so run it in one worktree at a time (`make check` is safe to run concurrently). VM changing (ask the user first, see Safety): `make vm-bootstrap deploy restore sb-fonts`. No OK needed: `make probe status logs verify backup` (`verify` writes and deletes a test note; `backup` stops the container briefly).
```

`:22`를 바꾼다.

```markdown
- Two secrets: the Tailscale auth key reaches the VM via `TS_AUTHKEY` or the hidden prompt; `SB_USER`, the SilverBullet login, lives only in the main checkout `.env` and the VM `.env` (mode 600), and scripts pass it on over SSH or curl stdin. Neither ever goes in a repo file or a command argument.
```

- [ ] **Step 5: GCP 설계 한 줄**

`docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md:158`("유일한 비밀값은 Tailscale 인증 키다…") 다음 줄에 넣는다.

```markdown
- 2026-10-14 갱신: [SilverBullet 웹 UI 설계](spec-2026-10-14-cjerm8b4-silverbullet-web-ui.md)가 두 번째 비밀값 `SB_USER`를 더한다(§8.3).
```

- [ ] **Step 6: 확인**

Run: `make check`
Expected: exit 0. `repo.bats`의 상대 링크 검사와 docs 경로 검사가 통과한다.

Run: `grep -rn 'only secret\|비밀값은 Tailscale 인증 키 하나' AGENTS.md docs/ARCHITECTURE.md README.md`
Expected: 출력 없음. 사용자가 AGENTS.md 변경을 승인하지 않았다면 `AGENTS.md:22` 한 줄만 나오고, 그 사실을 Progress log와 PR 본문에 적는다.

- [ ] **Step 7: 커밋과 push**

```bash
git add docs/decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md docs/ARCHITECTURE.md README.md docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md
git commit -m "docs: describe the SilverBullet web UI and its second secret" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 7"
git add AGENTS.md
git commit -m "docs: name SB_USER as the second secret in AGENTS.md" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: 7"
git push
```

AGENTS.md는 사용자가 승인한 뒤에만 두 번째 커밋을 만든다.

---

### 마무리: 리뷰, 넘기기 (git-workflow 스킬의 Review and merge)

- [ ] Progress log에 그날 `make check`가 출력한 테스트 수와 커버리지 %를 `Verified`로 적는다.
- [ ] 계획 파일을 `docs/plans/completed/`로 옮긴다. `make check`와 `make check-git`이 통과한 뒤 push한다.

```bash
git mv docs/plans/plan-2026-10-14-n6xpm12e-web-ui-local.md docs/plans/plan-2026-10-14-n6xpm12e-web-ui-local.md
git commit -m "docs: complete the web-ui-local plan" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: n6xpm12e" --trailer "Task: none"
git push
```

- [ ] 다른 벤더의 읽기 전용 리뷰를 받는다: `make review BRANCH=plan/n6xpm12e-web-ui-local REVIEWER=<다른 벤더>`.
  - 사용량이 드는 작업이므로 실행 전에 사용자 승인을 받는다.
  - PR 코멘트 게시도 사용자 승인을 받은 뒤 한다.
  - 게시 전에 리포트에서 VM IP와 세션 id를 가린다.
- [ ] 지적을 검증하고 하나당 커밋 하나로 고친다(`Review-Finding: R<n>-F<m>`). 2회차까지만 돈다.
- [ ] CI(`check`, `pr-rules`)가 통과하고 Review record에 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 PR 번호를 알린다. 승인과 squash 병합은 사람만 한다.
- [ ] 병합 뒤 git-workflow 스킬의 Clean up 절로 worktree를 정리한다. 지우기 전에 `ls <worktree>/backups <worktree>/.env`를 확인하고, 로컬 컨테이너는 `make local-down`으로 내린다.

## Follow-ups (이 계획 밖)

- SilverBullet 업스트림 이슈(관찰 카테고리를 누르면 `[]`가 됨): 문안은 브레인스토밍에서 준비했다. 게시는 사용자가 결정한다.
- `bm-diagnose`·`bm-recover` 스킬에 SilverBullet 컨테이너를 다루는 문장이 필요한지 [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md) 뒤에 판단한다.
- [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md): `verify`·`probe`의 SilverBullet·Serve 검사, Serve 8443, VM 배포.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-10-15 | Command | 시작: `plan/n6xpm12e-web-ui-local`을 `9b2fde1`에서 만들고 계획을 `active/`로 옮김(`a33dc52`). 초안 PR #5. 실행 방식은 사용자 결정대로 서브에이전트 구동, 의존성이 없는 태스크는 별도 worktree에서 병렬. |
| 2026-10-15 | Verified | 전제 2: 스파이크 컨테이너 `sb-spike` 삭제, `make local-down`, `.local-data` 삭제(사용자 승인). 전제 1: `SB_USER` 미설정. 원래 확인 명령 `make --eval`은 macOS GNU make 3.81에서 `unrecognized option`으로 실패해, 표준입력 makefile 방식으로 바꿈(값은 출력하지 않음). |
| 2026-10-15 | Verified | 실행 전 점검 판정(`b4e6edc`). make 3.81은 `.SHELLFLAGS`를 무시함(실험: `x="$$(false)"; echo still-ran`이 still-ran 출력) → `local-up`에 `\|\| exit 1`. `SB_USER`는 여섯 타깃에만 타깃별 export(3.81에서 `review`에 보이지 않음 확인). `sb-space.sh` 2단계화(실행 중 Basic Memory가 재생성 전에 페이지를 색인하지 않도록). Task 7의 `AGENTS.md:9`→`:10`. Progress log는 컨트롤러만 쓰고, 실제 스택 단계는 계획 worktree에서 병합 뒤 순서대로 실행. |
| 2026-10-15 | Verified | Task 1 `cc8d6b4`(병합 `8d380e1`): 2.12.1 릴리스 노트 확인, digest `sha256:7e24c16d…415c` 일치(amd64·arm64). `make check` 0 not ok / 164, 커버리지 96.62%. 태스크 리뷰 승인. Step 6(실제 스택)은 `SB_USER`가 없어 미실행. |
| 2026-10-15 | Verified | Task 2 `b0c3857`: `make check` exit 0, 커버리지 96.66%, `sb-space.sh` 100%. `agent-hub.md`가 계획 원문과 바이트 단위로 같음(리뷰어 diff). 태스크 리뷰 승인. Step 9 미실행. |
| 2026-10-15 | Verified | Task 3 `0ec6fc2` + `b6bb852`(`SDD-T3-F1`: 스크립트가 없어도 통과하던 `SB_USER` 거부 테스트에 메시지 확인 추가), Task 4 `767ba58`(Task 3과 병렬). 병합 `b091717`·`b4aa09d` 뒤 `make check` exit 0, 173 ok, 0 not ok, 커버리지 96.83%. 두 태스크 리뷰 승인. Task 3 Step 8, Task 4 Step 7 미실행. |
| 2026-10-15 | Verified | Task 5 `f5a3191`: `make check` exit 0, 177 ok, 커버리지 96.89%. 태스크 리뷰(opus) 승인. |
| 2026-10-15 | Verified | Task 7 `96dfaf5`(병합 `0e03725`): [web-ui-silverbullet ADR](../decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md), ARCHITECTURE, README, GCP 설계 한 줄. `make check` exit 0, 177 ok. 태스크 리뷰 승인. Step 4(AGENTS.md)는 사용자 승인 대기. |
| 2026-10-15 | Verified | 브랜치 전체 리뷰(opus, `9b2fde1..0e03725`): 수정 후 병합 가능. 고친 것: C1 `c6c1da9` 복원이 Basic Memory가 멈춘 동안 공간 파일을 씀(web-ui-local 계획 이전 백업에는 무시 목록이 없음), I1 `fde8106` make가 `.env`의 `#`·`$`를 바꾼 `SB_USER`를 원문 줄과 비교해 거부하고 `local-up`도 검사, I2 `cc1d5c6` 재시작 정책 테스트를 서비스별로. 범위 재리뷰 통과. `make check` exit 0, 181 ok, 0 not ok, 커버리지 96.84%. `make check-git` OK. 미룬 것: M4(복원 롤백 `up`에 `--remove-orphans` 없음, [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md) 또는 후속). |
| 2026-10-15 | Verified | 사용자가 AGENTS.md 수정을 승인함 → `e00ed9a`(Task 7 Step 4). `make check` exit 0, 181 ok, 커버리지 96.84%. 옛 문구 grep 0건. 사용자가 main 체크아웃 `.env`에 `SB_USER`를 넣음. 값을 출력하지 않고 형식(한 줄, 콜론 하나, 허용 문자, 16자 이상)을 확인했고, 표준입력 makefile로 `require_sb_user`가 통과함(make가 값을 바꾸지 않음). |
| 2026-10-15 | Verified | 미뤘던 실제 실행(병합된 브랜치에서 한 흐름으로). 첫 `make local-up`: `notes .gitignore changed` 1회, Basic Memory를 다시 만든 뒤 `wrote the dashboard index.md`, 두 컨테이너 healthy, 포트 `127.0.0.1:3000`·`127.0.0.1:8737`(Task 2 Step 9 첫 번째). curl `/.ping` 200, `/.fs/index.md` 401, `/.instance` **200**(Task 1 Step 6, 예상 401과 다름). 두 번째 `make local-up`: `changed` 0회, Basic Memory 가동 시간이 이어짐(Task 2 Step 9 두 번째). `make local-verify`: MCP 왕복 2회, 로그인과 쿠키, 셸 꺼짐, 글꼴 경고, `OK: SilverBullet checks passed`(Task 3 Step 8). 두 TTF 확인 뒤 `make sb-fonts LOCAL=1`이 woff2 두 개를 씀, 다시 `local-verify`에서 글꼴 경고 0(Task 4 Step 7). 모든 로그에 비밀번호 0회. |
| 2026-10-15 | Verified | `/.instance`는 2.12.1-slim에서 로그인 없이 200과 인스턴스 id·버전을 돌려줌. healthcheck는 인증 예외 목록에 있는 `/.ping`을 그대로 쓰고, 틀린 주석과 스펙 근거만 고침(`ea7d696`). |
| 2026-10-15 | Verified | Task 6. 사용자 로그인 뒤 `localhost:3000` 첫 화면에 `Lua error: attempt to call a nil value (field 'dashboard')`. 서버에는 없는 `CONFIG.md`가 그 origin의 브라우저 캐시에 남아 있었음(스파이크 흔적). 새로 띄운 탭에서는 오류 없음. 이후 확인은 새 origin `http://sb.localhost:3000`에서 함(사용자 재로그인). `agent-hub.md`는 고치지 않음. |
| 2026-10-15 | Verified | Task 6 Step 3: 계획의 `fetch("/.fs/…", PUT)`은 service worker 뒤에서 405(`allow: GET,HEAD`)를 받음. 사용자 허용 뒤 `client.space.writePage`로 시드 노트 셋을 씀(되읽기 같음, Basic Memory `search_notes`에 나옴). |
| 2026-10-15 | Verified | Task 6 Step 4(`sb.localhost:3000`): 트리 왼쪽, 목차 오른쪽이 열린 채 시작. 대시보드 일곱 절(최근 노트 셋, 폴더 `projects (1)`·`research (1)`·`tools (1)`, 결정·위험·질문 각 2, `#sample (3)`, Maintenance 링크가 `Library/Std/Pages/Maintenance`를 엶). 테마 어둡게 `#0d1117`·카테고리 `rgb(210,153,34)`, 밝게 `#ffffff`·`rgb(154,103,0)`. 글꼴 `400 loaded, 700 loaded \| "D2Koding Space", …`. 정보 줄 `Updated … · 28 words · ~1 min read · 1 backlinks · memory://main/tools/basic-memory`가 노트에만 있고 `index`·`Library` 페이지에는 없음. `tools/Basic Memory`의 Linked Mentions에 `Agent Hub`. Cmd-K는 포커스가 `Page` 입력칸, Esc로 트리 복귀. Cmd-Shift-F는 포커스가 `Text in notes`, `memory`로 제목·관찰·관계·문단이 나오고 문단을 고르면 10번째 줄로 이동. `tailne`도 Reindex 없이 문단을 찾음. 검색어는 왼쪽 칸 입력칸에 남아 트리를 거름(SilverBullet 내장 동작, 지우면 복귀). `Copy memory:// Link` → `Copied memory://main/projects/agent-hub`. `Navigate: Random Note` 18회는 노트 셋으로만 이동. `Graph: Explore`는 `Agent Hub`과 두 노트를 `mention`으로 그림. |
| 2026-10-15 | Verified | Task 6 Step 5: `research/Newline Check`를 URL로 열자 템플릿 frontmatter가 미리 들어감. `first line`, Enter, 3초 뒤 `second line`, 10초 뒤 편집기와 `client.space.readPage`, Basic Memory `read_note`가 모두 기대한 7줄과 같음(frontmatter 재작성 없음, 줄바꿈 보존). 페이지 `fetch("/.fs/…")` GET은 앱 HTML을 돌려줘서 쓰지 않음. 무시 목록: `search_notes` 기본 검색은 비슷한 노트 4건을 점수로 돌려주지만 `search_type: "text"`는 `agentHub` 0건, `list_directory`에는 노트 4개만 있음(`index`·`Library/`·`Repositories/` 없음). |
| 2026-10-15 | Verified | Task 6 Step 7: 스펙 §3의 web-ui-local 계획 Assumption 넷을 Verified로 바꾸고, 위 발견(캐시가 남은 origin, `/.fs` fetch, `search_notes` 기본 검색, 문단 색인, 공유 입력칸)을 적음. README의 Reindex 안내를 "문단이 안 나오면"으로, [web-ui-silverbullet ADR](../decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md) 근거에 web-ui-local 계획 로컬 결과를, [web-ui-vm-rollout 계획](plan-2026-10-14-a88datfz-web-ui-vm-rollout.md) Task의 `search_notes` 확인에 `search_type: "text"`를 더함. |
| 2026-10-15 | Verified | 보충(범위 리뷰 지적). Task 2 Step 9의 `.local-data` 목록은 에이전트에게 읽기가 막혀 있음. 대신 로그인한 클라이언트의 `/.fs/` 목록에 `Library/agent-hub/agent-hub.md`·`index.md`가 있었음. `.gitignore.pending`이 없다는 것은 레시피의 `rm -f … && sb-space.sh … unchanged` 연쇄가 exit 0으로 끝난 것으로 판단함(SilverBullet은 숨김 파일을 나열하지 않음). Task 6 Step 5의 `search_notes "Agent Hub"`는 `projects/Agent Hub`를 첫 결과(score 1.23)로 돌려줌. |
| 2026-10-15 | Verified | Task 6 Step 7 정리: scratchpad의 `mcp-call.sh`를 지우고, 에이전트가 연 탭 둘을 닫음. 시드 노트 셋과 `research/Newline Check`(로컬 `.local-data`, git 제외)를 지울지는 사용자 결정을 기다림. |
| 2026-10-15 | Verified | 마무리: 최종 리뷰 이후 커밋(`9409cb9..bfa3347`)의 범위 리뷰는 Spec ✅, 승인, P3 3건. `376fe12`(SDD-T6-F1·F2), `6df6709`(SDD-T6-F3)로 고쳤고 재리뷰에서 모두 반영 확인, 새 지적 0. `make check` exit 0, 181 ok, 0 not ok, 커버리지 96.84%. `make check-git` OK. 계획을 `completed/`로 옮김. 남은 일: PR #5 CI, Codex 리뷰(사용자 확인 뒤). |
| 2026-10-15 | Verified | PR #5 CI(`fa41b40`): `check` pass(1m17s), `pr-rules` pass, GitGuardian pass(`gh pr checks 5`). |
| 2026-10-15 | Verified | Codex R1(`gpt-6.1-sol`, base `origin/main`, head `fa41b40`): diff 리뷰는 결함 없음, plan 리뷰는 P1 1건(R1-F1: Progress log에 PR CI 통과 기록이 없음) → 위 행으로 고침. 두 리포트를 PR #5에 게시함. 사용자 결정대로 테스트 노트 넷을 Basic Memory `delete_note`로 지우고(`list_directory` 결과 0개) `make local-down`. |
