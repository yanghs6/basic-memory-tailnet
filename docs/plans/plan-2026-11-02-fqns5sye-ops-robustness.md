---
status: active
id: fqns5sye
spec: none
---

# fqns5sye Ops Robustness Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 의미 검색 끄기가 문서가 아니라 테스트와 probe로 지켜지고, `make status`·`make verify`가 멈춘 서버·낡은 IP·복원할 수 없는 백업을 정상으로 보고하지 않게 한다.

**Architecture:**
- 재검토 보고서(2026-11-02, main 체크아웃 `.review-out/full-review-2026-11-02.md`, 저장소에 넣지 않음)의 W9, W15, W16을 묶는다. 다루는 지적은 F23~F27, P3-25, 감독 항목 "VM이 하루 넘게 쉰 뒤 점검 없음"이다.
- 모두 읽기 전용 검사나 로컬 검사를 더하는 변경이다. VM에 배포할 것이 없다(`compose.yaml`은 주석 한 줄만 바뀜). 그래서 결과 PR 없이, 같은 브랜치에서 VM 읽기 전용 실행(Task 9)까지 기록한다.
- 새 검사는 기존 진입점에 붙인다: 의미 검색은 `verify-mcp.sh`(verify, probe, local-verify가 모두 거침), IP 대조는 `verify-vm.sh`(verify, probe), 상태는 `show-status.sh`, 아카이브 항목 검사는 `scripts/lib/vm.sh`로 옮겨 backup, restore, backup-latest가 함께 쓴다.

**Spec:** 없음. 근거는 재검토 보고서 5장 W9·W15·W16 행과 2장 F23~F27, P3-25 행이다. 의미 검색 결정은 [semantic-search-off ADR](../decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md).

**Sequence:** 바로 시작할 수 있다. 1차에 P-A(샌드박스·가드·공개 텍스트), P-E(문서·계획 정리)와 함께 돈다. 파일 경계는 아래 Global Constraints.

## Global Constraints

- compose healthcheck는 TCP 연결 검사로 둔다. MCP 수준으로 바꾸면 복원 직후 `up --wait`가 실패해 restore가 롤백된다(보고서 F25). HTTP 응답은 `make status`가 본다.
- 새 검사는 모두 읽기 전용이다. 노트를 쓰지 않고, 컨테이너를 멈추지 않고, VM 설정을 바꾸지 않는다.
- IP 대조는 VM 외부 IP와 `.env`의 `BM_VM_PUBLIC_IP` 값을 출력하지 않는다. 다르다는 사실과 고칠 방법만 쓴다.
- `show-backup.sh`는 아카이브 항목 이름을 출력하지 않는다(노트 제목이 들어 있다). 이유 문구만 쓴다.
- 커밋 내용과 메시지에는 홈 디렉터리 절대 경로를 쓰지 않고 저장소 상대 경로를 쓴다(P-A 병합 뒤 `pr-rules`가 중간 커밋 diff까지 검사한다).
- 파일 경계(감독 결정, 2026-11-02):
  - P-A 소유라 고치지 않는다: `scripts/check-public-text.sh`, `scripts/lib/common.sh`, 가드, `review-branch.sh`, `post-review*.sh`, `check-git.sh`, `.claude/settings.json`, ADR zaptc3gp, `tests/repo-config.bats`의 제외 목록, `docs/ARCHITECTURE.md:70`.
  - `tests/repo-config.bats`는 basic-memory 서비스 테스트(`:134` 근처)와 release-notes-reader 테스트(`:444` 근처)만 고친다. 병합 충돌은 `git merge origin/main`으로 둘 다 살린다.
  - 운영 런북은 새 "재개 점검" 절만 더한다. 기존 줄(front matter `reviewed`, `:35`, `:37`, `:39`, `:50`, `:98`, `:171`, `:187-188`)은 P-E가 고친다. 고쳐야 하면 감독에 먼저 알린다.
  - `docs/ARCHITECTURE.md`는 `:63`(`make backup-latest`), `:100`(자동 검증 범위), `:109`(`make status` 스왑 경고), `:117`(`make verify` 흐름)을 이 계획이 고친다(감독 확인). front matter `reviewed`와 나머지 줄은 P-E가 고친다.
  - P-A가 `mktemp`를 바꾸는 파일(`verify-web.sh`, `verify-sb.sh`, `export-logs.sh`, `scripts/lib/mcp.sh` 등)은 고치지 않는다.
- 커밋 트레일러: `Assisted-by: claude-code claude-opus-5-5`, `Plan: fqns5sye`, `Task: <N|review|none>`.

## User decisions

**사용자 결정 (2026-11-02):** 계획 승인 때 아래 세 가지를 추천안대로 정했다.

1. release-notes-reader 형식 줄은 bats로 고정하지 않는다(1-A). [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md) 결정 2가 문구·형식만 보는 테스트를 새로 쓰지 않게 한다. 실제 보호는 probe의 hybrid 검사(Task 2)와 compose 단언(Task 1)이 맡는다.
2. `make status`의 새 경고(HTTP 무응답, not running, 디스크·스왑 사용률)는 출력만 하고 exit 0으로 끝난다(2-A). 지금의 "스왑 없음" 경고와 같다. `make status probe`처럼 이어 쓸 때 probe가 계속 돌고, 멈춘 서버는 probe가 실패로 잡는다.
3. 경고 기준값은 디스크 80%, 스왑 80%다. 스왑 근거는 2026-10-28 멈춤 때 862~873/1023 MB(84~85%), 평소 89~487 MB다(운영 런북 Incident log).

## Review Focus

1. 의미 검색이 켜진 서버에서 hybrid 검색은 임베딩 모델을 처음 올리므로 1 GB VM에서 오래 걸릴 수 있다. 이때 probe는 `curl: (28)` 또는 "did not answer that semantic search is disabled"로 실패해야 하고, 통과하면 안 된다(Task 2의 실패 사례).
2. VM 외부 IP를 메타데이터에서 읽지 못할 때(외부 IP 없음, 메타데이터 서버 무응답) verify는 거짓 OK 없이 멈춰야 한다(Task 6의 실패 사례).
3. 데이터 루트에 링크가 생긴 VM에서 `make backup`은 컨테이너를 다시 띄우고 이번 실행의 파일을 하나도 남기지 않아야 한다(Task 4). 기존 백업은 건드리지 않는다.
4. `make status`는 배포 전 VM(app dir 없음)에서 지금처럼 `could not query containers`로 끝난다. 이 동작은 운영 런북 `:29`, `:137`과 bm-recover가 기대므로 바꾸지 않는다(Task 5).

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `tests/repo-config.bats` | basic-memory가 의미 검색을 끄는지 단언 | 1 |
| `scripts/verify-mcp.sh`, `tests/verify-mcp.bats`, `tests/fixtures/verify-mcp/{json,sse}/call_search_notes.body` | hybrid 검색이 "disabled"를 돌려주는지 확인 | 2 |
| `.claude/agents/release-notes-reader.md`, `.agents/skills/bm-upgrade/SKILL.md` | 형식에 의미 검색 스위치 줄, 스위치를 지킨다는 인용이 없으면 중단 | 3 |
| `scripts/lib/vm.sh`, `tests/lib-vm.bats` | `archive_entry_problem`, `check_archive_entries` | 4 |
| `scripts/restore-notes.sh`, `scripts/backup-notes.sh`, `scripts/show-backup.sh`, `tests/backup-notes.bats`, `tests/show-backup.bats` | 아카이브 항목 검사를 lib에서 호출 | 4 |
| `scripts/show-status.sh`, `tests/show-status.bats`, `tests/stubs/docker`, `tests/stubs/df`(새), `tests/stubs/uptime`(새), `compose.yaml`(주석) | HTTP 응답, uptime, 디스크, 스왑 사용률, not running | 5 |
| `scripts/verify-vm.sh`, `tests/verify-vm.bats`, `tests/stubs/curl` | 외부 IP 대조 | 6 |
| `Makefile` | `status`, `backup-latest`, `probe`/`verify` 설명 | 4, 5, 6 |
| 운영 런북 "재개 점검" 절, `docs/ARCHITECTURE.md`, bm-diagnose, bm-recover, script-authoring 스킬 | 문서 동반 갱신 | 7 |

---

### Start: branch, worktree, draft PR

- [x] `git fetch origin` 뒤 `origin/main`(89e9ef6)에서 만든 worktree `ops-robustness`의 브랜치를 `plan/fqns5sye-ops-robustness`로 바꿨다. `origin/plan/fqns5sye-*`는 없었다.
- [ ] 첫 커밋에서 이 계획을 `status: active`로 넣고 push한 뒤 초안 PR을 연다. 감독에 알린다.

### Task 1: compose의 의미 검색 끄기 고정 (W9, F23)

**Files:**
- Modify: `tests/repo-config.bats`

- [x] **Step 1: 실패하는 테스트 작성.** basic-memory 서비스 테스트 바로 뒤에 새 `@test`를 둔다.

```bash
@test "basic-memory turns semantic search off, or the 1 GB VM stalls on writes" {
  local bm
  bm="$(service_block basic-memory)"
  grep -qxF '      BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED: "false"' <<<"$bm" \
    || fail 'basic-memory must set BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED: "false" (docs/decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md)'
}
```

- [x] **Step 2: RED·GREEN 확인.** `compose.yaml`의 그 줄을 잠시 지우고 `make test`를 실행하면 이 테스트만 실패한다. `git checkout -- compose.yaml`로 되돌리고 다시 `make test`가 통과한다. 두 결과를 Progress log에 적는다.
- [x] **Step 3: `make check` 통과 후 커밋.** `test: pin semantic search off in compose.yaml` (`Task: 1`).

### Task 2: probe의 의미 검색 확인 (W9, F23)

**Files:**
- Modify: `scripts/verify-mcp.sh`, `tests/verify-mcp.bats`
- Create: `tests/fixtures/verify-mcp/json/call_search_notes.body`, `tests/fixtures/verify-mcp/sse/call_search_notes.body`

**Interfaces:**
- Produces: `check_semantic_search_off` (verify-mcp.sh 안). `tools/list` 확인 바로 뒤, `--read-only` 분기 앞에서 부른다. 그래서 `make verify`, `make probe`, `make local-verify`, bm-diagnose가 모두 이 검사를 거친다.

**Verified (2026-11-02):** VM의 Basic Memory에 `search_notes(search_type="hybrid", output_format="json")`을 보내면 `{"result":"# Search Failed - Semantic Search Disabled\n\nYou requested ... search ..., but semantic search is disabled. ..."}`이 돌아온다(이 세션이 MCP로 직접 호출).

- [x] **Step 1: 실패하는 테스트 작성.**
  - fixture 두 개: `structuredContent.result`가 위 문자열인 응답(SSE는 `data:` 한 줄, JSON은 본문 그대로). 응답 id는 6이다.
  - 새 `@test "checks that a hybrid search answers that semantic search is disabled, with and without --read-only, and fails when it returns results or times out"`:
    - `--read-only`와 기본 모드 둘 다: 성공하고 `semantic search off ok`를 출력한다. `$STUB_LOG.requests`에 `search_type: "hybrid"`인 `search_notes` 요청이 하나 있다.
    - fixture를 결과 객체(`{"results":[],...}`)로 바꾸면 실패하고 `semantic search` 문구로 멈춘다.
    - 시간 초과는 `CURL_STUB_SLOW_MATCH=search_notes`와 `CURL_STUB_SLOW_SECONDS`를 `MCP_TIMEOUT_SECONDS`보다 크게 둬서 만든다. 실패해야 한다.
  - 기존 왕복 테스트(`:12`)의 기대값을 새 요청 하나만큼 고친다: `Mcp-Session-Id` 5→6, `Host` 6→7, tools/call 목록 맨 앞에 `search_notes`. 동작이 바뀐 만큼만 고치고 약하게 만들지 않는다.
- [x] **Step 2: `make test`로 실패 확인.** 새 테스트와 고친 왕복 테스트만 실패한다.
- [x] **Step 3: 구현.**

```bash
# The query of the semantic search probe: matches no note, so a server with semantic search on answers an empty result.
readonly SEMANTIC_PROBE_QUERY="bm-verify-semantic-probe"
# What Basic Memory 0.23.2 answers to a hybrid search while semantic search is off (mcp/tools/search.py).
readonly SEMANTIC_DISABLED_TEXT="Semantic Search Disabled"

# check_semantic_search_off -> dies unless a hybrid search_notes answers that semantic search is disabled. Writes
# nothing. With it on, writes stall the 1 GB VM (docs/decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md).
check_semantic_search_off() {
  local arguments payload
  arguments="$(jq -cn --arg query "$SEMANTIC_PROBE_QUERY-$VERIFY_ID" '{query: $query, search_type: "hybrid", output_format: "json"}')"
  payload="$(mcp_call_tool 6 search_notes "$arguments")" || exit 1
  jq -e --arg text "$SEMANTIC_DISABLED_TEXT" 'type == "string" and contains($text)' <<<"$payload" >/dev/null \
    || die "search_notes: a hybrid search did not answer that semantic search is disabled: check BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED in compose.yaml and the image version, then follow bm-diagnose (docs/decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md)"
  log "semantic search off ok"
}
```

  - 헤더 주석의 흐름 줄에 search_notes(hybrid) 확인을 더한다.
  - 같은 fixture 디렉터리를 쓰는 테스트(`verify-vm.bats`, `lib-mcp.bats`, `show-memory-index.bats`, `sync-agent-memory.bats`)가 새 fixture 파일 때문에 바뀌지 않는지 `make test`로 본다.
- [x] **Step 4: `make check` 통과.** 실제 서버 응답 모양은 Task 8의 `make local-verify`가 확인한다. 모양이 다르면 fixture를 실제 응답에 맞춘다.
- [x] **Step 5: 커밋.** `feat: check in verify and probe that semantic search is off` (`Task: 2`).

### Task 3: release-notes-reader 형식과 bm-upgrade 중단 조건 (W9, F24)

**Files:**
- Modify: `.claude/agents/release-notes-reader.md`, `.agents/skills/bm-upgrade/SKILL.md`

- [x] **Step 1:** reader 형식 목록 끝에 한 줄을 더한다: `- Semantic search switch (BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED): verbatim quotes that keep, rename, remove or change it, or "not mentioned"`.
- [x] **Step 2:** bm-upgrade 3단계를 고친다.
  - 다른 도구에서 사용자가 답하는 형식에도 같은 항목을 넣는다.
  - "Check in that answer and in the release's source" 문장을 바꾼다: 스위치 줄이 스위치를 그대로 둔다는 인용이 아니면(not mentioned, 제거, 이름·동작 변경) 여기서 멈추고 사용자에게 알린다. 그 ADR을 먼저 다시 연다(Rules).
  - Checklist 3번은 그대로 둔다("semantic search can still be turned off").
- [x] **Step 3:** 사용자 결정 1-A에 따라 형식 줄을 검사하는 테스트는 더하지 않는다. `make check`로 기존 reader 테스트(`repo-config.bats:444`)가 계속 통과하는지만 본다.
- [x] **Step 4:** 커밋. `docs: stop bm-upgrade unless the release notes keep the semantic search switch` (`Task: 3`).

### Task 4: 아카이브 항목 검사를 lib로 (W16, F26)

**Files:**
- Modify: `scripts/lib/vm.sh`, `scripts/restore-notes.sh`, `scripts/backup-notes.sh`, `scripts/show-backup.sh`, `Makefile`(`backup-latest` 설명)
- Test: `tests/lib-vm.bats`, `tests/backup-notes.bats`, `tests/show-backup.bats`

**Interfaces:**
- Produces (vm.sh, 함수 색인에 추가):
  - `archive_entry_problem ARCHIVE` -> 항목이 일반 파일과 디렉터리뿐이고 절대 경로·`..`가 없으면 아무것도 출력하지 않는다. 아니면 이유 한 줄을 출력한다. tar가 목록을 못 읽으면 실패한다. 항목 이름은 출력하지 않는다.
  - `check_archive_entries ARCHIVE HINT` -> 문제가 있으면 `unsafe archive ARCHIVE: <이유>; HINT`로, 못 읽으면 `could not list the entries of ARCHIVE`로 die.
- `show-backup.sh`는 `common.sh` 대신 `vm.sh`를 source한다. vm.sh는 source할 때 상수만 정의하므로 VM 설정 없이 돈다.

- [x] **Step 1: 실패하는 테스트 작성.**
  - `lib-vm.bats`: `@test "archive_entry_problem accepts regular files and directories, names a symlink, a hard link, an absolute path or a '..' entry without printing entry names, and fails on an unreadable archive"`. 반복문 사례: 안전한 아카이브(빈 출력), 심볼릭 링크, 하드 링크, `-P`로 넣은 절대 경로, `../` 항목, tgz가 아닌 파일(실패). 항목 이름에 `SECRET`을 넣고 출력에 없음을 확인한다.
  - `backup-notes.bats`: `@test "backup stops before it keeps anything when the data root holds a symlink or a hard link, restarts the container and spares earlier backups"`. 데이터 루트(모델 캐시 밖)에 링크를 두고 backup이 실패한다. `unsafe archive`로 멈추고, `$BACKUP_DIR`에 이번 실행의 파일(`.partial` 포함)이 없고, 미리 둔 이전 백업은 그대로이며, `compose start`가 불렸다. 모델 캐시 안의 링크만 있으면 성공한다는 것은 기존 첫 restore 테스트가 이미 보이므로 반복하지 않는다.
  - `show-backup.bats`: `make_backup`이 실제 tgz(항목 이름에 `SECRET`)를 만들게 바꾼다. 기존 "reports a mismatched checksum..." 반복문에 `unsafe-entries` 사례(심볼릭 링크를 담은 아카이브, 체크섬·manifest는 정상)를 더한다: `entries: UNSAFE`와 `not restorable`을 출력하고 `SECRET`은 없다. 첫 테스트에 `entries: safe`와 `restorable: yes`를 더한다.
- [x] **Step 2: `make test`로 실패 확인.**
- [x] **Step 3: 구현.**
  - `restore-notes.sh`의 `check_archive_entries`를 vm.sh로 옮겨 두 함수로 나눈다. restore는 `check_archive_entries "$archive" "restore only archives made by 'make backup'"`으로 부른다. 메시지 앞부분(`unsafe archive ...: it holds an entry that is not a regular file or directory`, `an absolute path or a '..' component`)은 그대로 둬서 기존 restore 테스트가 바뀌지 않게 한다.
  - `backup-notes.sh`: 스트림을 받은 뒤, 체크섬을 쓰기 전에 `check_archive_entries "$ARCHIVE$PARTIAL_SUFFIX" "<힌트>"`를 부른다. 힌트: 데이터 루트(모델 캐시 제외)에 링크나 장치가 있어 이 백업은 복원되지 않는다, `ssh <user>@<host> sudo find <root> -path <root>/<cache> -prune -o ! -type f ! -type d -print`로 찾아 사용자에게 알린다, 아무것도 남기지 않았다. 실패하면 기존 trap이 이번 실행의 파일을 지우고 컨테이너를 다시 띄운다.
  - `show-backup.sh`: `entries: safe|UNSAFE (<이유>)|unreadable` 줄을 더하고, `restorable: yes`는 체크섬 일치, manifest 있음, 항목 안전일 때만 낸다. 헤더 주석에 "항목 목록을 읽되 이름은 출력하지 않는다"를 적는다.
  - Makefile `backup-latest` 설명에 항목 검사를 더한다.
- [x] **Step 4: `make check` 통과.**
- [x] **Step 5: 커밋.** `feat: check archive entries in backup and backup-latest, not only in restore` (`Task: 4`).

### Task 5: `make status` 보강 (W15, F25, P3-25)

**Files:**
- Modify: `scripts/show-status.sh`, `tests/show-status.bats`, `tests/stubs/docker`, `Makefile`(`status` 설명), `compose.yaml`(healthcheck 주석 한 줄)
- Create: `tests/stubs/df`, `tests/stubs/uptime`

**Interfaces:**
- 상수: `STATUS_HTTP_TIMEOUT_SECONDS=10`, `DISK_WARN_PERCENT=80`, `SWAP_WARN_PERCENT=80`(사용자 결정 3), 확인할 서비스 `STATUS_NOTE_SERVICES="basic-memory silverbullet"`.
- 출력(새 줄):
  - `running: basic-memory silverbullet`, 빠진 서비스마다 `WARNING: <service> is not running: run 'make logs' (bm-diagnose)`
  - `basic-memory http: answered (HTTP <code>)` 또는 `WARNING: Basic Memory did not answer HTTP on the VM's 127.0.0.1:<port> within 10s (Docker can still call it healthy): run 'make probe' and follow bm-diagnose`
  - `uptime: <uptime -p 출력>`
  - `disk used: <n>% of the data root's filesystem`, 80% 이상이면 `WARNING: ...`
  - `swap used: <used>/<total> MB (<n>%)`, 80% 이상이면 `WARNING: ...`. 기존 "스왑 없음" 경고는 그대로.
- 경고는 exit 0이다(사용자 결정 2-A).

- [x] **Step 1: 실패하는 테스트 작성.**
  - stub: `docker`는 `ps --services --status running`에 `DOCKER_STUB_RUNNING_SERVICES`(기본 `basic-memory`와 `silverbullet`, 한 줄에 하나)를 출력한다. `df`는 `DF_STUB_USE_PERCENT`(기본 34), `uptime`은 `-p`에 `up 3 days, 4 hours`를 출력한다. 각 stub은 호출을 `$STUB_LOG`에 남긴다.
  - HTTP 응답은 VM에서 도는 curl이다. ssh stub이 명령을 로컬에서 돌리므로 curl stub의 download 모드(`-o`와 `-w '%{http_code}'`면 `CURL_STUB_HTTP_CODE`)와 `CURL_STUB_FAIL_MATCH`(exit 28)를 쓴다.
  - 기존 첫 테스트 반복문을 넓힌다: `@test "status shows containers, running services, the HTTP answer, uptime, disk and swap use, and warns when a note service is not running, the server does not answer, or disk or swap is at 80% or more"`. 사례: 정상, silverbullet 빠짐, HTTP 시간 초과, 디스크 85%, 스왑 900/1023, 스왑 없음. 각 사례는 정해진 WARNING 하나만 내고 성공한다.
  - HTTP 검사가 `-m 10`을 넘기는지 `assert_stub_called`로 확인한다(시간 제한이 빠지면 status가 멈춘 서버에서 같이 멈춘다).
- [x] **Step 2: `make test`로 실패 확인.**
- [x] **Step 3: 구현.**
  - 컨테이너 단계: 기존 `remote_compose "ps"`는 그대로 출력한다(런북 이미지 점검이 이 출력을 본다). 그다음 `remote_compose "ps --services --status running"`으로 빠진 서비스를 경고한다. 배포 전 VM에서는 지금처럼 첫 `ps`에서 die한다(Review Focus 4).
  - HTTP 단계: `remote "curl -sS -o /dev/null -m $STATUS_HTTP_TIMEOUT_SECONDS -w '%{http_code}' http://127.0.0.1:$port/mcp"`. 코드가 나오면 answered, curl이 실패하면 경고. 코드는 무엇이든 응답으로 본다(멈춤은 응답이 없는 상태다).
  - uptime·디스크: `remote "uptime -p"`, `remote "df -P $BM_REMOTE_DATA_ROOT"`의 둘째 줄 Use%. 읽지 못하면 die(지금 메모리 단계와 같은 방식, 고칠 명령을 함께).
  - 스왑 사용률: `memory_swap_summary` 결과로 계산한다. 스왑 0이면 사용률 경고 대신 기존 경고만.
  - `compose.yaml` healthcheck 위에 주석 한 줄: TCP로 두는 이유(MCP 수준이면 복원 직후 `up --wait`가 실패해 restore가 롤백됨, HTTP 응답은 `make status`가 봄). 이미지 줄은 바꾸지 않는다.
  - Makefile `status` 설명을 새 항목에 맞춘다.
- [x] **Step 4: `make check` 통과.**
- [x] **Step 5: 커밋.** `feat: show the HTTP answer, uptime, disk and swap use and missing services in make status` (`Task: 5`).

### Task 6: verify의 외부 IP 대조 (W15, F27)

**Files:**
- Modify: `scripts/verify-vm.sh`, `tests/verify-vm.bats`, `tests/stubs/curl`, `Makefile`(`verify`/`probe` 설명)

**Interfaces:**
- 상수: `METADATA_EXTERNAL_IP_URL=http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip`, `METADATA_TIMEOUT_SECONDS=5`.
- `check_public_ip_current` -> VM 안에서 메타데이터 서버(`Metadata-Flavor: Google` 헤더)로 외부 IP를 읽어 `BM_VM_PUBLIC_IP`와 비교한다. 다르면 `BM_VM_PUBLIC_IP in .env is not the VM's current external IP (stopped and started?): look up the new IP (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md, step 5) and update .env`로 die. 읽지 못하면 `could not read the VM's external IP from the metadata server: ...`로 die. 두 값 모두 출력하지 않는다.
- `validate_public_ip` 뒤, 터널을 열기 전에 부른다. verify와 probe가 모두 거친다.

**Assumption:** 메타데이터 경로는 GCP 문서의 predefined 키(`instance/network-interfaces/0/access-configs/0/external-ip`)다. Task 9의 실제 `make probe`로 확인한다.

- [x] **Step 1: 실패하는 테스트 작성.**
  - curl stub에 Metadata 모드: URL이 `metadata.google.internal`이면 `${CURL_STUB_EXTERNAL_IP-$BM_VM_PUBLIC_IP}`를 출력한다(빈 값이면 아무것도 출력하지 않는다). 헤더 주석에 모드를 적는다.
  - 새 `@test "verify and probe stop before any MCP request when the VM's external IP differs from BM_VM_PUBLIC_IP or cannot be read, and print neither address"`: 다른 IP, 빈 응답, 메타데이터 시간 초과(`CURL_STUB_FAIL_MATCH=metadata.google.internal`). 각각 실패하고, `$STUB_LOG.requests`에 MCP 요청이 없고, 출력에 VM 쪽 IP(`198.51.100.7`)가 없다. 같은 IP면 기존 테스트가 통과하는 것으로 성공 경로를 본다.
  - ssh 모드 테스트(`:110`)에서도 IP 검사가 터널을 열기 전에 도는지 `assert_log_order`로 확인한다.
- [x] **Step 2: `make test`로 실패 확인.**
- [x] **Step 3: 구현.** `remote "curl -sS -m $METADATA_TIMEOUT_SECONDS -H 'Metadata-Flavor: Google' $METADATA_EXTERNAL_IP_URL"`. 결과를 변수에만 두고 비교한다. 헤더 주석과 Makefile 설명에 IP 대조를 더한다.
- [x] **Step 4: `make check` 통과.**
- [x] **Step 5: 커밋.** `feat: compare the VM's external IP with BM_VM_PUBLIC_IP in verify and probe` (`Task: 6`).

### Task 7: 문서 동반 갱신 (W15 런북, W16)

**Files:**
- Modify: `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`(새 절만), `docs/ARCHITECTURE.md`(`:63`, `:100`, `:109`, `:117`), `.agents/skills/bm-diagnose/SKILL.md`, `.agents/skills/bm-diagnose/references/failure-messages.md`, `.agents/skills/bm-recover/SKILL.md`, `.agents/skills/script-authoring/SKILL.md`(vm.sh 설명)

- [ ] **Step 1: 운영 런북 "재개 점검" 절.** "정지된 VM" 절 뒤에 둔다. 하루 넘게 쓰지 않은 뒤, 첫 작업 전에 쓴다.
  1. `make access-check`: 지금 네트워크에서 되는 경로를 본다.
  2. `ssh` 모드면 `make tunnel`을 다시 띄운다(Mac이 잠들면 터널이 끊긴다).
  3. `make status`: 두 서비스가 running, `basic-memory http: answered`, uptime(예상 밖 재부팅인지), 디스크·스왑 80% 미만.
  4. `make probe`: MCP, 의미 검색 꺼짐, 외부 IP가 `.env`와 같음. IP가 다르면 "정지된 VM" 2단계처럼 `.env`를 고친다.
  5. `make backup-latest`: 최신 백업이 `restorable: yes`인지, 날짜가 1주보다 오래됐으면 사용자에게 `make backup`을 제안한다.
  6. 하나라도 실패하면 bm-diagnose를 쓰고, VM이 `TERMINATED`면 "정지된 VM"을 따른다. 실제 장애였을 때만 Incident log에 행을 더한다.
- [ ] **Step 2: ARCHITECTURE.** `:63` backup-latest 설명에 항목 검사 결과를 더한다. `:100`·`:117`에 의미 검색 확인과 외부 IP 대조를, `:109`에 status의 스왑 사용률 경고를 더한다. front matter `reviewed`는 건드리지 않는다.
- [ ] **Step 3: 스킬.** bm-diagnose 3·4단계에 새 status 줄(not running, HTTP 무응답, 디스크)과 probe의 의미 검색·IP 실패를 더한다. 실패 메시지 표(`references/failure-messages.md`)에 새 메시지 세 줄(hybrid 확인 실패, IP 불일치, 메타데이터 읽기 실패)을 더한다. bm-recover 2단계의 backup-latest 설명에 `entries` 줄을 더한다. script-authoring의 vm.sh 설명에 "the backup archive checks"를 더한다.
- [ ] **Step 4:** `make check` 통과 후 커밋. `docs: add the resume check and describe the new status, probe and backup checks` (`Task: 7`).

### Task 8: 로컬 스택 확인 (W9)

- [ ] `make local-up`이 다른 worktree의 스택이라며 거부하면 감독에 묻는다.
- [ ] `make check`, `make local-up`, `make local-verify`, `make local-down`을 각각 단독 명령으로 실행한다. `local-verify` 출력에 `semantic search off ok`가 두 번(plain, `*.ts.net` Host) 나와야 한다. 결과를 Progress log에 적는다.

### Task 9: VM 읽기 전용 실행 (W15, W16)

- [ ] 실행 전에 감독에 한 줄 알린다(다른 세션 VM 작업과 겹치지 않게).
- [ ] `make status`, `make probe`, `make verify`, `make backup-latest`를 각각 실행한다. 새 줄(HTTP 응답, uptime, 디스크, 스왑 사용률, running, 의미 검색 꺼짐, IP 대조, entries)을 Progress log에 `Verified`로 적는다. IP·노트 제목은 적지 않는다.
- [ ] `make backup`은 컨테이너를 잠깐 멈추므로 감독이 정한 시간에 한 번 실행하고, 이어서 `make backup-latest`가 `entries: safe`, `restorable: yes`인지 본다. 감독이 시간을 주지 않으면 건너뛰고 Follow-ups에 남긴다.
- [ ] 실패하면 고치지 말고 bm-diagnose로 원인을 본 뒤 사용자에게 알린다.

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).
- [ ] PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
- [ ] `make review`로 Codex 읽기 전용 리뷰를 돌린다. 리뷰 게시와 `gh pr ready`는 사용자 OK를 받는다. 리뷰가 끝나면, 그리고 ready 전(최종 head, CI, 게시 내용)에 감독에 알린다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 사용자 OK 뒤 `gh pr ready <PR>`을 실행한다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- `BM_WEB=on`일 때 `make status`가 gateway·cloudflared의 running도 확인하기. 지금은 웹 커넥터가 보류 중(d3dpb00s Task 4)이라 노트 서비스 두 개만 본다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
| 2026-11-02 | Verified | `git fetch origin` 뒤 `origin/plan/fqns5sye-*` 없음. 브랜치 `worktree-ops-robustness`를 `plan/fqns5sye-ops-robustness`로 바꿈(`.git/config` 잠금 오류가 났지만 옛 이름의 branch 설정이 없어 잃은 것 없음) |
| 2026-11-02 | Verified | VM에 `search_notes(search_type="hybrid")`를 보내면 "Search Failed - Semantic Search Disabled" 안내가 돌아옴 |
| 2026-11-02 | Verified | 사용자가 계획을 승인하고 결정 1-A, 2-A, 기준값 80%를 정함 |
| 2026-11-02 | Verified | Task 1 RED: `compose.yaml`의 `BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED` 줄을 잠시 지우고 `make test`를 실행함. 278개 중 `not ok 136 basic-memory turns semantic search off, or the 1 GB VM stalls on writes` 하나만 실패했고 make는 exit 2로 끝남 |
| 2026-11-02 | Verified | Task 1 GREEN: `git checkout -- compose.yaml`로 되돌린 뒤 `make test`가 278개 모두 ok, exit 0 |
| 2026-11-02 | Verified | Task 1 `make check`: lint 통과, 278개 모두 ok, `total line coverage: 89.30% (minimum 80%)`, exit 0 |
| 2026-11-02 | Verified | Task 3 `make check`: 278개 모두 ok(기존 reader 테스트 `ok 150 the release-notes reader has no shell or write tool and bm-upgrade hands step 3 to it` 포함), `total line coverage: 89.30% (minimum 80%)`, exit 0. 결정 1-A대로 새 테스트는 없음 |
| 2026-11-02 | Verified | Task 2 RED: fixture 두 개와 새 테스트, 고친 왕복 테스트를 넣고 `make test`를 실행함. 279개 중 `not ok 255`(왕복 테스트, `Mcp-Session-Id` 기대 6·실제 5)와 `not ok 258`(새 테스트, `semantic search off ok` 없음) 두 개만 실패했고 exit 2 |
| 2026-11-02 | Verified | Task 2 구현 뒤 `make test`: 278개 ok, `not ok 268 probe runs every check without writing notes, logging in or needing SB_USER` 하나만 실패, exit 2. verify-mcp, lib-mcp, show-memory-index, sync-agent-memory 테스트는 새 fixture로도 모두 통과 |
| 2026-11-02 | Verified | 계획이 `tests/verify-vm.bats:105-106`의 단언을 빠뜨렸음. probe 테스트가 `grep -F '"method":"tools/call"'`의 실패로 "tools/call 없음"을 요구했지만, 이제 probe도 읽기 전용 `search_notes` 호출을 보냄. 감독 승인을 받아 두 줄을 `tools/call` 이름 목록이 정확히 `search_notes` 하나인지 보는 `assert_equal` 한 줄로 바꿈. 쓰기·읽기·삭제 도구를 부르지 않는다는 보장은 그대로이고, 파일의 다른 줄은 Task 6 몫이라 고치지 않음 |
| 2026-11-02 | Verified | Task 2 `make check`: lint 통과, 279개 모두 ok, `scripts/verify-mcp.sh` 97.33%, `total line coverage: 89.33% (minimum 80%)`, exit 0 |
| 2026-11-03 | Verified | Task 4 RED: 새 lib-vm·backup-notes 테스트와 고친 show-backup 테스트 두 개를 넣고 `make test`를 실행함. 281개 중 `not ok 3`(링크가 있는 데이터 루트에서 backup이 성공함), `not ok 118`(`archive_entry_problem: command not found`, status 127), `not ok 215`(`entries: safe` 없음), `not ok 216`(unsafe-entries 사례에 `entries: UNSAFE` 없음) 네 개만 실패했고 exit 2 |
| 2026-11-03 | Verified | Task 4 구현 뒤 `make test`: 281개 모두 ok, exit 0. `tests/restore-notes.bats`는 바꾸지 않았고 그 거부 테스트도 통과함. 테스트 이미지는 GNU tar라서, 같은 `archive_entry_problem`을 macOS bsdtar로 만든 아카이브 여섯 개(안전, 심볼릭 링크, 하드 링크, `..`, 절대 경로, tgz 아님)에도 임시 스크립트로 돌려 같은 결과를 봄 |
| 2026-11-03 | Verified | 계획의 backup 힌트 find 명령(`! -type f ! -type d -print`)은 하드 링크를 찾지 못함(하드 링크는 `-type f`). 테스트가 하드 링크 사례를 요구하므로 힌트에 `! -type d -links +1 -print -o`를 더함 |
| 2026-11-03 | Verified | Task 4 `make check`: lint 통과, 281개 모두 ok, `scripts/lib/vm.sh` 97.28%, `scripts/backup-notes.sh` 95.16%, `scripts/restore-notes.sh` 96.30%, `scripts/show-backup.sh` 93.48%, `total line coverage: 89.35% (minimum 80%)`, exit 0 |
| 2026-11-03 | Verified | Task 1~3 읽기 전용 리뷰(별도 서브에이전트, 1d98c96·4b632f1·0268cc9): P0·P1 없음, 승인. P3 한 건(SDD-T3-F1): bm-upgrade Rules가 "끌 수 없으면 멈춤"만 말해 3단계의 not mentioned 중단과 어긋남. Rules에 "릴리스 노트가 스위치를 지킨다고 인용하지 않으면"을 더해 고침 |
| 2026-11-03 | Verified | Task 4 읽기 전용 리뷰(별도 서브에이전트, b396a8b): P0·P1·P2 없음, 승인. P3 한 건(검사 동안 컨테이너가 멈춘 시간이 압축 해제만큼 늘어남)은 노트 아카이브가 작아 고치지 않음 |
| 2026-11-03 | Verified | Task 5 RED: 새 `df`와 `uptime` stub, `docker` stub의 running 목록, 넓힌 첫 show-status 테스트를 넣고 `make test`를 실행함. 281개 중 `not ok 222`(새 테스트, `running: basic-memory silverbullet` 없음) 하나만 실패했고 exit 2. 바뀐 `docker` stub으로도 다른 테스트는 모두 통과함 |
| 2026-11-03 | Verified | Task 5 구현 뒤 `make test`: 281개 모두 ok, exit 0 |
| 2026-11-03 | Verified | Task 5 `make check`: lint 통과. 281개 모두 ok이고 `scripts/show-status.sh` 100.00%. `total line coverage: 89.49% (minimum 80%)`, exit 0 |
| 2026-11-03 | Verified | Task 6 RED: curl stub의 Metadata 모드와 새 verify-vm 테스트, ssh 모드 테스트의 `assert_log_order`를 넣고 `make test`를 실행함. 282개 중 `not ok 269`(새 테스트, verify가 성공함)와 `not ok 272`(ssh 모드, 메타데이터 호출 없음) 두 개만 실패했고 exit 2 |
| 2026-11-03 | Verified | Task 6 구현 뒤 첫 `make test`는 `not ok 133`(scripts에 클라우드 이름이 없는지 보는 테스트) 하나만 실패함. 새 주석 두 줄에서 클라우드 이름을 지움. 메타데이터 호스트와 헤더는 그 테스트의 단어 목록에 없어 그대로 둠. 다시 `make test`: 282개 모두 ok, exit 0 |
| 2026-11-03 | Verified | Task 6 `make check`: lint 통과. 282개 모두 ok이고 `scripts/verify-vm.sh` 97.67%. `total line coverage: 89.53% (minimum 80%)`, exit 0 |
| 2026-11-03 | Reported | 메타데이터 문서(predefined-metadata-keys, 2026-11-03 조회)는 `access-configs/0/external-ip`를 인터페이스의 외부 IP로 설명함. 필요한 헤더와 오류 상태 코드는 그 페이지에 없음(서브에이전트가 읽음) |
| 2026-11-03 | Assumption | 외부 IP가 없는 VM에서는 그 키가 오류 상태로 답한다고 봄. 그래서 계획의 메타데이터 명령에 curl `-f`를 더해 오류 본문을 주소로 비교하지 않고 "could not read"로 멈추게 함. 런북 안내는 저장소 관례대로 "step 5" 대신 "section 5"로 씀 |
