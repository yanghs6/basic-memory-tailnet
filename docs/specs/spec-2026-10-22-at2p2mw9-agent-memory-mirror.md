---
status: approved
id: at2p2mw9
date: 2026-10-23
---

# 에이전트 기억 미러 (Claude Code·Codex → Basic Memory) — 설계

- 구현 계획: [agent-memory-mirror 계획](../plans/plan-2026-10-22-mk823xbp-agent-memory-mirror.md) 하나에 배포까지 담는다(§7). 코드 PR이 병합된 뒤 회사 Mac과 개인 Mac에 설치하고, 결과는 결과 PR로 남긴다.
- 출처:
  - 2026-10-22 사용자와의 브레인스토밍, 같은 날의 로컬 확인·서버 도구 스키마 조회, Claude Code·Codex·Basic Memory 공식 문서와 소스(§2)
  - 2026-10-23 웹·소스 조사와 Codex(`gpt-6.1-sol`) 교차 검토, 사용자 결정 8
- 2026-10-23 개정: 조회 방식을 "질문마다 검색해 넣기"에서 "세션 시작 때 색인 + 필요할 때 에이전트가 MCP로 조회"로 바꿨다(결정 8). 결정 2와 7을 남긴 채 결정 8로 고쳤다. §3.4는 새 방식으로 다시 썼다.
- [VM 접속 방식 설계](spec-2026-10-15-jr59pvyf-access-modes.md)의 `ssh` 모드 터널(`http://127.0.0.1:18737/mcp`) 위에 얹는다. 모든 계획은 [GitHub PR 워크플로](spec-2026-10-13-pr762r68-github-pr-workflow.md)를 따른다.

## 1. 목적과 범위

Claude Code와 Codex의 지속 기억은 각 Mac의 로컬 파일에만 있어서, 다른 에이전트나 다른 Mac에서는 보이지 않는다. 각 Mac의 기억 파일을 VM의 Basic Memory로 한 방향 복사(미러)하고, 사용자가 질문할 때 두 에이전트가 Basic Memory에서 관련 기억을 찾아 답에 쓰게 한다.

**사용자 결정 (2026-10-22)**
1. 방식: 로컬 기억을 정본으로 두고 hook이 바뀐 파일을 Basic Memory로 복사한다. 대안은 "지침만 추가"와 "Basic Memory를 정본으로 두고 자동 기억을 끔"이었다.
2. 쓰임: 사용자가 Claude Code나 Codex에서 질문하면 에이전트가 Basic Memory에서 관련 내용을 확인해 답한다.
3. Codex: Codex 자체 기억(`memories`)을 켜고 Claude와 같은 방식으로 복사한다. 대안은 "Codex가 MCP로 직접 쓰기"와 "Codex는 읽기만"이었다. 사용자가 2026-10-22 `codex features enable memories`로 켰다.
4. 올릴 범위: 회사 프로젝트의 기억도 "일단" 올린다. 개인 VM에 회사 내용이 저장되는 점을 알고 정했다.
5. 기기: 회사 Mac과 개인 Mac의 기억을 같은 Basic Memory에 모은다. 이 저장소를 작업한 Mac이 회사 Mac이다.
6. 경로: 프로젝트 우선 `agent-memory/<프로젝트>/<에이전트>/<기기>/`. 대안은 기기 우선 `agent-memory/<기기>/<에이전트>/<프로젝트>/`였다(§3.2).
7. 질문 전송: 조회 hook이 회사 프로젝트를 포함한 모든 세션의 질문 앞 500자를 VM으로 보내 검색한다. 제외 목록에 있는 프로젝트의 질문은 보내지 않는다. Basic Memory가 검색어를 로그에 남기는지 확인하기 전에 정했다(§4).

**사용자 결정 (2026-10-23)**

8. 조회 방식 A: 세션 시작 hook이 현재 프로젝트와 `_global`의 미러 노트 색인을 넣는다. 에이전트는 질문이 지난 결정이나 맥락에 기대면 Basic Memory MCP로 직접 조회한다. 질문마다 원격으로 검색하는 hook은 두지 않는다. 같은 날 사용자가 이 방향을 승인했고, 아래도 함께 바뀐다.
   - 결정 2의 "확인해 답한다"는 "에이전트가 필요하다고 판단할 때 확인한다"가 된다. 매 질문마다 확인한다는 보장은 없고, 실제로 조회하는지는 계획의 설치 Task에서 확인한다.
   - 결정 7은 더 이상 쓰이지 않는다. 질문 내용은 hook으로 VM에 가지 않는다. 에이전트가 MCP로 검색할 때 고른 검색어만 간다.
   - 대안은 두 가지였다. B는 A에 더해 질문마다 로컬 알림 한 줄을 넣는 것이고, C는 질문마다 원격 검색을 계속하는 것이다. 근거는 §2의 조사다. 기본 도구와 주류 메모리 계층이 같은 방식이고, 영어 노트에 한국어 질문으로는 검색이 거의 맞지 않는다.
   - VM(e2-micro)과 기본 임베딩 모델은 그대로 둔다. 1GB에 맞는 한국어 지원 모델이 없기 때문이다(§2). 새 기억은 영어로 쓰도록 전역 지침에 넣는다(§3.8).

**범위 밖**
- 양방향 동기화. Basic Memory에서 미러 노트를 고치면 다음 동기화 때 로컬 내용으로 덮어쓴다.
- 에이전트가 MCP로 직접 기억을 쓰는 규칙. 이번에는 로컬 기억의 미러만 만든다.
- memsearch 세션 로그(`.memsearch/`). 양이 많고 대부분 그 세션에서만 쓴다.
- Antigravity·Gemini CLI의 기억.
- 웹 커넥터. 단, 웹 커넥터가 열리면 미러된 기억도 웹 로그인으로 보인다(§4).
- 터널 자동 실행. 터널은 지금처럼 `make tunnel`로 띄운다.
- 프로젝트별 공개 범위 제어. 올리지 않을 프로젝트를 적는 제외 목록만 둔다(§3.6).

**완료 조건**
1. `make check`가 통과한다.
2. 회사 Mac(`mac-work`)에서 `make memory-sync`가 Claude 기억(세션 임시 폴더 제외)과 Codex 기억을 §3.2의 경로로 올린다. 바로 다시 실행하면 아무것도 보내지 않는다.
3. 로컬 기억 파일을 고치거나 지우면, 다음 hook 실행 뒤 Basic Memory 노트도 바뀌거나 지워진다.
4. 터널이 꺼져 있으면 동기화와 색인 hook이 0으로 끝난다. 색인 hook은 컨텍스트에 경고 한 줄을 남기고, 동기화 hook은 상태 폴더의 로그에 남긴다. 터널을 켠 뒤의 다음 동기화가 밀린 변경을 올린다(2026-10-23 개정).
5. Claude Code와 Codex는 세션을 시작하면 색인을 받는다. 미러된 기억과 관련된 한국어 질문을 하면, 에이전트가 MCP(`read_note`나 `search_notes`)로 그 노트를 읽고 답에 쓴다. 수동으로 확인해 결과 PR에 기록한다(2026-10-23 개정).
6. 개인 Mac(`mac-personal`)에 설치한 뒤, 한 Mac의 에이전트가 다른 Mac의 기억을 색인이나 검색으로 찾는다.

## 2. 근거가 된 사실 (2026-10-22, `main` `57993a3`)

로컬 기억 (회사 Mac):

- **Verified (Command: `ls -d ~/.claude/projects/*/memory`):** Claude 기억 폴더는 15개다. 그중 3개는 세션 임시 폴더(`-private-tmp-...-scratchpad`)다. 이 저장소의 기억 파일은 23개다.
- **Verified (Command: 각 폴더의 최신 세션 `.jsonl`에서 `cwd`를 읽고 `git -C <cwd> remote get-url origin`):** 임시 폴더를 뺀 12개 중 git remote가 있는 곳은 3개(`github.com/yanghs6/basic-memory-tailnet`, 회사 Bitbucket 저장소 둘(`bitbucket.org/<회사>/<저장소>` 모양. 공개 저장소라 이름은 가렸다))이고, 파일이 있는 곳은 이 저장소뿐이다. 나머지 파일(23개)은 git이 아닌 작업 폴더에 있다. 한 폴더(회사 작업 폴더 하나, 파일 9개)는 세션 `.jsonl`이 없어 `cwd`를 읽지 못했다.
- **Verified:** Claude 기억 폴더 이름은 경로의 `/`와 `_`를 `-`로 바꾼 것이라 원래 경로로 되돌릴 수 없다(예: `027_agent_share_poc` → `-027-agent-share-poc`).
- **Verified:** 이 저장소의 기억 파일에 있는 IP 형태 문자열은 `127.0.0.1`과 IAP 대역뿐이다. VM 주소는 없다.
- **Verified (Command: `codex --version`, `codex features list`):** `codex-cli 0.163.0`, `hooks` 기능은 켜져 있다. `memories`는 꺼져 있었고 사용자가 2026-10-22에 켰다(`memories  stable  true`). `~/.codex/memories/`에는 사용자가 6월에 만든 파일 하나(`manual/`)만 있었다.
- **Verified:** `~/.codex/hooks.json`에 SessionStart·UserPromptSubmit·Stop hook이 있고 memsearch가 쓴다. `~/.claude/settings.json`에도 같은 이벤트의 hook이 있다. 새 hook은 기존 hook과 함께 등록해야 한다.

Codex 기억 구조 (소스 `openai/codex` 태그 `rust-v0.163.0`):

- **Verified (`codex-rs/memories/README.md`):** 기억 생성은 루트 세션이 시작될 때 백그라운드에서 돈다. 1단계는 대화(rollout)마다 요약을 만들고, 2단계는 모든 프로젝트를 합쳐 `~/.codex/memories/`에 `raw_memories.md`와 `rollout_summaries/`를 쓴다. 이 폴더는 `.git` 기준선을 두고, 작업 파일 `phase2_workspace_diff.md`를 썼다가 지운다.
- **Verified (`codex-rs/ext/memories/templates/memories/read_path_v2.md`):** 새 세션에는 `memory_summary`가 주입되고, 사용자가 기억을 고쳐 달라고 하면 `extensions/ad_hoc/notes/`에 메모를 남긴다. 생성된 파일은 직접 고치지 않는다.

Basic Memory 서버 (0.23.2, 터널 경유 `tools/list`):

- **Verified:** `search_notes`에는 폴더 인자가 없다. `metadata_filters`(frontmatter 필드), `tags`, `note_types`, `after_date`, `search_type`(`text`, `title`, `permalink`, `vector`, `semantic`, `hybrid`)이 있다.
- **Verified:** `write_note`는 `title`·`content`·`directory`가 필수이고 `metadata`·`tags`·`note_type`·`overwrite`를 받는다. `delete_note`는 `identifier`(제목이나 permalink)를 받는다. `build_context`는 `memory://` URL을 받는다.
- **Verified (Command: `list_directory`):** 프로젝트 `main`의 노트는 `agent-hub/agent-hub 접속 방법 (ssh 모드).md` 하나다.
- **Verified:** `compose.yaml:25`는 기본 프로젝트를 `main`으로 둔다. 의미 검색용 임베딩 모델 캐시(`config/fastembed_cache/`)가 VM에 있다(`docs/ARCHITECTURE.md:96`).
- **Verified (Command: `make status`):** VM 메모리 사용 59%, 스왑 510/1023 MB.
- **Verified:** 2026-10-22 세션 시작 때 터널이 꺼져 있어 `basic-memory` 연결이 `ECONNREFUSED`였다. 터널은 사람이 띄워야 한다.

공식 문서 (조사 에이전트가 2026-10-22 조회):

- **Reported ([Claude Code memory](https://code.claude.com/docs/en/memory)):** auto memory는 기기 로컬이고, `autoMemoryDirectory`도 로컬 경로만 받는다. 원격 저장소로 바꾸는 설정은 없다. 세션 시작 때 `MEMORY.md`의 앞 200줄 또는 25KB만 읽는다. CLAUDE.md는 "context, not enforced configuration"이다.
- **Reported ([Claude Code hooks](https://code.claude.com/docs/en/hooks)):** SessionStart·UserPromptSubmit hook의 stdout은 컨텍스트에 들어가고 10,000자에서 자른다. SessionEnd hook의 기본 시간 제한은 1.5초다. Stop은 응답이 끝날 때마다 실행된다.
- **Reported ([Codex hooks](https://developers.openai.com/codex/hooks)):** UserPromptSubmit hook의 stdout이나 `additionalContext`는 개발자 컨텍스트로 들어가고 기본 한도는 2,500토큰이다. 새 hook은 `/hooks`에서 한 번 신뢰해야 실행된다.
- **Reported ([Codex memories](https://developers.openai.com/codex/memories)):** 기억 파일은 "generated state"이고, 기억은 6시간 이상 쉰 대화에서 생기며(`min_rollout_idle_hours` 기본 6), 생성에 Codex 사용량이 든다.
- **Reported (Basic Memory 0.23.2 소스와 [문서](https://docs.basicmemory.com/integrations/claude-code)):** 공식 Claude Code·Codex 플러그인의 hook은 Mac 안에서 basic-memory를 직접 실행하거나 Basic Memory Cloud로 가므로, 원격 자가 호스팅 서버에는 닿지 않는다. `write_note`는 같은 경로에 노트가 있으면 `overwrite` 없이 오류를 낸다. 노트를 옮겨도 permalink는 바뀌지 않는다(`update_permalinks_on_move` 기본 `False`). `build_context`의 `*`는 경로 중간에서도 맞는다.

웹·소스 조사 (2026-10-22, 조사 에이전트 다섯이 문서와 태그 소스를 읽음. 이 절은 모두 간접 확인이다):

- **Reported ([Claude Code hooks](https://code.claude.com/docs/en/hooks)):**
  - 입력과 출력:
    - UserPromptSubmit 입력에는 `prompt`가 있고, 공통 필드 `cwd`·`session_id`도 있다.
    - UserPromptSubmit과 SessionStart의 일반 stdout은 컨텍스트에 들어가고, 10,000자에서 잘린다.
    - Stop과 UserPromptSubmit은 matcher를 무시한다.
    - `timeout`은 초 단위이고, UserPromptSubmit의 기본값은 30이다.
  - 백그라운드 프로세스는 stdout과 stderr를 파일로 돌려야 한다.
  - "Add context for Claude" 절: 넣는 문구는 "factual statements rather than imperative system instructions"로 쓴다. 명령처럼 쓴 문구는 프롬프트 주입 방어를 건드릴 수 있다.
  - 기억 폴더는 git 저장소 기준이라 worktree들이 한 폴더를 함께 쓴다. `CLAUDE_CODE_PROJECT_DIR_NAME`으로 이름을 바꿀 수 있다([memory](https://code.claude.com/docs/en/memory)).
- **Reported (Codex 소스 `rust-v0.163.0`, `codex-rs/`):**
  - 입력과 출력:
    - UserPromptSubmit 입력에는 `prompt`·`cwd`·`session_id`·`turn_id`가 있다(`hooks/src/schema.rs:567-583`).
    - 일반 stdout은 developer 메시지로 들어가고, hook마다 약 2,500토큰이 한도다(`hooks/src/output_spill.rs`).
    - stdout이 `{`나 `[`로 시작하는데 hook JSON이 아니면 실패로 보고 버린다(`events/user_prompt_submit.rs:211-216`).
    - 동기 Stop hook이 일반 stdout을 내면 실패로 처리한다(`events/stop.rs:326-340`).
  - 신뢰와 형식:
    - hook 신뢰는 위치(`<file>:<event>:<group>:<handler>`)와 command·timeout의 해시로 정한다. 신뢰하지 않았거나 바뀐 hook은 돌지 않는다(`hooks/src/lib.rs:112-122`, `engine/discovery.rs:715-794`).
    - `hooks.json`의 최상위 키는 `hooks`와 `description`만 허용한다(`config/src/hook_config.rs:10-17`).
  - 프로세스: hook은 새 세션에서 돈다. 출력을 돌린 자손 프로세스는 hook이 끝난 뒤에도 살아남는다(`engine/command_runner.rs:269-286`, 테스트 `:821-856`).
  - 기억 생성:
    - 기억 2단계(consolidation) 에이전트는 실제 thread로 돌면서 UserPromptSubmit과 SessionStart hook을 실행한다. 이때 `cwd`는 `$CODEX_HOME/memories`, 기억 V2에서는 `memories_v2`다(`memories/write/src/phase2.rs:299-322`).
    - 1단계 요약은 developer 메시지를 버린다(`rollout/src/policy.rs:104-106`).
    - 기억 폴더에는 `MEMORY.md`, `skills/`, 7일 뒤 지워지는 `extensions/<ext>/resources/`도 있다.
- **Reported (Basic Memory 소스 `v0.23.2`):**
  - 쓰기:
    - `write_note`는 본문 frontmatter와 `metadata`를 최상위 키 단위로 합치고, 키가 겹치면 `metadata`가 이긴다(`markdown/utils.py:99-117`).
    - `note_type`은 snake_case로 바뀐다(`agent-memory` → `agent_memory`, `schemas/base.py:66`).
    - 본문 frontmatter의 `type:`·`permalink:`는 인자보다 앞선다(`services/note_preparation.py:253-258`). **Verified (2026-10-22):** 지금 기억 파일 56개 중 최상위 `type:`이나 `permalink:`가 있는 파일은 없다.
    - 결과의 `action`은 `created`, `updated`, `conflict`다. `conflict`는 `isError`가 아니다(`write_note.py:308-316,400-407`).
  - 이름과 permalink:
    - 한글 제목은 파일 이름에는 그대로 남고, permalink는 로마자가 된다(`회의 메모` → `hoeyi-memo`).
    - permalink 앞에 프로젝트가 붙는다(`main/...`).
    - permalink가 같아지는 두 파일은 409로 거부된다(`utils.py:120-192,737-776`).
  - 검색:
    - `search_notes` 결과는 `results[]`이고, 결과마다 `title`·`type`(entity/observation/relation)·`permalink`·`content`(frontmatter 뺀 본문, 4,000자)·`matched_chunk`가 있다(`schemas/search.py:125-170`).
    - text 검색은 FTS5(`unicode61`, 접두어 색인)에서 단어마다 `word*`를 붙여 AND로 묶는다.
    - 단어 안에 구두점이 있으면 전체를 한 구로 묶는다.
    - 결과가 0건이면 OR로 한 번 더 찾는다. 단, `"`나 숫자만으로 된 단어가 있으면 다시 찾지 않는다(`sqlite_search_repository.py:290-354,1083-1105`, `search_query.py:252-302`).
    - 한국어 조사가 붙은 단어(`경로를*`)는 `경로`와 맞지 않는다.
    - hybrid의 기본 임베딩 모델 `bge-small-en-v1.5`는 영어용이다. semantic이 꺼져 있으면 hybrid는 text로 넘어가지 않고, 오류가 아닌 마크다운 "Search Failed"를 돌려준다(`tools/search.py:46-106`).
  - 삭제:
    - `delete_note`는 permalink(프로젝트 접두사가 있든 없든)와 파일 경로를 받는다.
    - 없는 노트를 지우면 `{"deleted": false}`이고 오류가 아니다(`delete_note.py:431-454`).
  - 로그와 텔레메트리:
    - 검색어는 DEBUG에서만 로그에 남고, 검색이 실패하면 ERROR로 남는다(`tools/search.py:1202-1243`).
    - `write_note`는 INFO에서 title·directory·permalink를 남긴다.
    - `mcp` 서브커맨드는 텔레메트리를 보내지 않는다.
    - **Verified:** VM은 `BASIC_MEMORY_LOG_LEVEL: INFO`다(`compose.yaml:27`).
  - 쓰기는 백그라운드에서 파일과 색인에 반영되므로, 쓴 직후의 검색은 그 노트를 놓칠 수 있다.
- **Reported (gitleaks 기본 설정, GitHub·AWS·Slack·Tailscale 문서):** 토큰 형식은 §3.3의 패턴과 같다. Tailscale 키는 `tskey-<종류>-<keyID>-<secret>` 모양이다. 테스트 값 `tskey-auth-ssh123`은 키가 아니다.

2026-10-23 추가 조사(조사 에이전트 둘, Codex 교차 검토):

- **Reported (Basic Memory `v0.23.2` 소스):**
  - 임베딩 설정:
    - `BASIC_MEMORY_SEMANTIC_EMBEDDING_MODEL`·`_DIMENSIONS`·`_THREADS`·`_BATCH_SIZE`로 바꿀 수 있다. 외부 API용 provider는 `openai`·`litellm`이다.
    - 모델 이름은 fastembed 0.8.0 목록 안에서만 고를 수 있다(`add_custom_model`을 쓰지 않음).
    - 모델을 바꾸면 옛 벡터는 무시된다. 다시 만드는 명령은 `basic-memory reindex --embeddings`이고, 별도 프로세스로 모델을 한 벌 더 올린다.
  - FTS 토크나이저는 `unicode61`로 고정이다.
- **Reported (fastembed 0.8.0 목록, Mac M2에서 잰 값):**
  - 한국어를 다루는 다국어 모델은 넷이다: MiniLM-L12(384차원, 235MB, 128토큰), mpnet(1.11GB), multilingual-e5-large(2.24GB), jina-v3(비상업 라이선스).
  - MiniLM-L12를 쓰면 Basic Memory 프로세스 RSS가 325MB에서 868MB가 된다. 나머지 모델은 재지 못했다.
  - VM은 메모리 70%, 스왑 327MB를 쓰고 있어(`make status`, 2026-10-23) 1GB에 안전하게 맞는 모델이 없다. Codex 검토는 이 결론이 Mac 측정 하나에 기댄다고 지적했다.
  - 가격(제3자 집계, 2026-10-19 갱신): e2-small 약 $12.23/월, e2-medium 약 $24.46/월. 무료 등급은 e2-micro뿐이다.
- **Reported (MTEB BelebeleRetrieval nDCG@10):** `bge-small-en-v1.5`는 영어→영어 0.921, 한국어→영어 0.095, 한국어→한국어 0.176이다. 이 벤치마크는 실제 기억 검색 성능과 같지 않다(Codex 검토).
- **Reported (주류 메모리 계층):** Letta, Anthropic memory tool, Google ADK `LoadMemoryTool`, Zep 등은 작은 핵심(요약, 목록)을 컨텍스트에 두고 나머지는 에이전트가 도구로 검색한다. 매 턴 자동으로 넣는 쪽은 Zep `get_context`, ADK `PreloadMemoryTool` 등이다.
- **Reported (Codex `rust-v0.163.0`):**
  - Codex 기억 읽기 안내(`codex-rs/ext/memories/templates/memories/read_path.md:17-38`): memory_summary에서 키워드를 뽑고, `MEMORY.md`를 검색하고, 파일 1~2개를 연다. 4~6단계 안에서 끝낸다.
  - 기억 2단계 에이전트는 기억 폴더를 cwd로 쓰고 MCP 서버 목록을 비운다(`memories/write/src/phase2.rs:279-291`, Codex 검토).
- **Verified (2026-10-23):** 기억 파일 56개의 언어(한글 비율 10% 이상이면 한국어). 이 저장소의 Claude 기억은 영어 24개, 다른 프로젝트의 Claude 기억은 한국어 23개, Codex 기억은 9개 중 한국어 8개다.
- **Verified (2026-10-23, Command: `ls ~/.codex/memories`):** memories를 켠 뒤 폴더에 `extensions`, `manual`, `phase2_workspace_diff.md`, `raw_memories.md`, `rollout_summaries`가 생겼다. `memory_summary.md`와 `MEMORY.md`는 아직 없다. `phase2_workspace_diff.md`는 소스 README의 "쓰고 지운다"와 달리 남아 있다. 2단계가 끝나지 않았거나 실패한 것으로 보이는데, 확인하지는 않았다. 동기화는 이 파일을 이름으로 빼므로 영향이 없다(§3.3).

**Assumption ([agent-memory-mirror 계획](../plans/plan-2026-10-22-mk823xbp-agent-memory-mirror.md) Task 1에서 서버로 확인):** 위 소스 조사로 대부분 풀렸고, 남은 것은 다음과 같다.
- frontmatter 합치기와 `type: agent_memory`가 실제 서버에서도 소스대로다.
- 검색어 없이 `metadata_filters`(`project`와 `mirror`, 또는 `device`와 `mirror`)만으로 `search_notes`를 부르면 그 노트 목록(제목, permalink, 본문, 갱신 시각)이 나오고 `has_more`로 페이지를 넘길 수 있다. 색인 hook(§3.4)과 전체 다시 맞추기(§3.3)가 이 호출을 쓴다.
- VM에서 `text` 검색 한 번이 2초 안에 끝난다. 한국어 명사 검색어가 조사가 붙은 본문과 맞는다.
- Claude Code에서 hook이 띄운 백그라운드 동기화가 hook이 끝난 뒤에도 돈다(Task 6에서 확인). Codex는 소스로 확인됐다.
- 에이전트가 색인을 보고 실제로 MCP를 부른다(Task 6에서 확인).

**Verified (2026-10-26):** 위 처음 세 항목(frontmatter 합치기, 목록 호출과 `has_more`, `text` 검색의 지연과 한국어 명사)은 서버에서 소스대로였다. 결과는 계획 Progress log에 있다. 같은 확인에서 permalink가 키를 바꾸는 것을 찾아 §3.4를 고쳤다.

## 3. 설계

### 3.1 흐름

```mermaid
flowchart TB
  subgraph M["각 Mac (mac-work, mac-personal)"]
    CC["Claude Code"] -->|"auto memory 쓰기"| CL["~/.claude/projects/*/memory/"]
    CX["Codex"] -->|"memories 생성"| XL["~/.codex/memories/"]
    H1["hook: SessionStart, Stop"] --> S["make memory-sync"]
    CL & XL --> S
    S <--> ST["상태 파일: 올린 파일과 해시"]
    H2["hook: SessionStart"] --> R["make memory-index"]
  end
  S -->|"바뀐 파일만 write_note, 사라진 파일은 delete_note"| T["make tunnel 127.0.0.1:18737"]
  R -->|"search_notes: 프로젝트와 _global 목록"| T
  T --> BM["VM Basic Memory main: agent-memory/..."]
  R -->|"색인을 컨텍스트에"| CC & CX
  CC & CX -->|"필요할 때 MCP read_note, search_notes"| T
```

1. Claude Code와 Codex는 지금처럼 로컬에 기억을 쓴다. 로컬이 정본이다.
2. 두 에이전트의 SessionStart·Stop hook이 `make memory-sync`를 백그라운드로 부른다. 어느 에이전트가 불렀든 그 Mac의 두 기억 폴더를 모두 맞춘다.
3. 동기화는 상태 파일과 해시를 비교해 바뀐 파일만 보낸다. 바뀐 것이 없으면 네트워크를 쓰지 않는다.
4. 세션이 시작되면 SessionStart hook이 `make memory-index`로 현재 프로젝트와 `_global`의 미러 노트 목록을 받아 짧은 색인을 컨텍스트에 넣는다. 그 에이전트가 이 Mac에서 이미 로컬로 읽는 노트는 뺀다(§3.4).
5. 질문이 지난 결정이나 맥락에 기대면, 에이전트가 Basic Memory MCP로 색인의 노트를 `read_note`로 읽거나 `search_notes`로 찾는다(결정 8, 전역 지침 §3.8). Claude Code의 `MEMORY.md`, Codex의 `memory_summary`와 같은 방식이다.
6. 터널이 꺼져 있으면 두 hook 모두 경고 한 줄을 남기고 0으로 끝난다. 색인 hook의 경고는 그 세션에 MCP 도구가 없을 수 있다는 것도 알린다.

### 3.2 경로와 frontmatter

**경로:** `agent-memory/<프로젝트 키>/<에이전트>/<기기>/<원본 폴더 기준 상대경로>`

```
agent-memory/
  yanghs6-basic-memory-tailnet/
    claude-code/mac-work/MEMORY.md
    claude-code/mac-work/web-connector-work.md
    claude-code/mac-personal/...
  local-<git 밖 작업 폴더>/
    claude-code/mac-work/...
  _global/
    codex/mac-work/memory_summary.md
    codex/mac-work/rollout_summaries/<원본 파일>.md
    codex/mac-work/extensions/ad_hoc/notes/<원본 파일>.md
```

- **경로에는 누가 썼는지를 둔다.** `MEMORY.md`, `memory_summary.md`처럼 같은 이름이 기기·프로젝트마다 나오고 `write_note`는 같은 경로에서 오류를 내므로, 세 값이 모두 경로에 있어야 한다. 기기를 맨 끝에 두면 한 폴더에 쓰는 주체가 하나뿐이다.
- **찾는 조건은 frontmatter에 둔다.** `search_notes`에는 폴더 인자가 없으므로 기기·에이전트·프로젝트로 거르는 일은 `metadata_filters`로 한다(§2).
- **순서는 사람이 볼 때를 기준으로 정했다.** 프로젝트를 앞에 두면 SilverBullet에서 한 저장소의 기억이 기기·에이전트와 상관없이 한 폴더에 모인다.

| 대안 | 장점 | 단점 | 판단 |
|---|---|---|---|
| 프로젝트 우선 | 한 저장소의 기억이 한곳에 모인다 | Codex 전역 기억은 프로젝트가 없어 `_global`에 둔다 | 채택(사용자 결정) |
| 기기 우선 | 기기마다 루트가 하나다 | 한 저장소의 기억이 기기별로 흩어진다. 상태 파일로 삭제를 판단하므로 구현이 더 쉬워지지도 않는다 | 기각 |
| 평평한 경로 + frontmatter | 경로 규칙이 없다 | 같은 파일 이름이 충돌한다 | 기각 |

**프로젝트 키 (설계 판단):**
1. Claude 기억 폴더의 원래 작업 폴더는 그 폴더의 세션 `.jsonl`에 있는 `cwd` 값 중, Claude의 폴더 이름 규칙(영문자·숫자·`-` 밖의 문자를 `-`로. 문서에는 없고 이 Mac의 폴더 이름으로 확인했다)으로 바꾸었을 때 폴더 이름과 같아지는 것이다. 기억 폴더는 git 저장소 루트 기준이라(§2) 저장소 루트의 `cwd`가 맞는다. 한 `.jsonl`에도 worktree 경로 같은 여러 `cwd`가 섞여 있으므로(2026-10-22 이 저장소에서 4개 확인) 최신 값을 그대로 쓰지 않는다. 맞는 값이 없으면 4번 규칙을 따른다. 한 번 정한 키는 상태 파일에 적어 두고 다시 계산하지 않는다.
2. 작업 폴더가 git 저장소이고 `origin`이 있으면 `<owner>-<repo>`를 쓴다. 원격 주소는 호스트를 소문자로 바꾸고, 사용자 정보·포트·`.git`을 빼고, scp 형식(`git@host:path`)을 `host/path`로 바꿔 정규화한다. 예: `yanghs6-basic-memory-tailnet`, `acme_dev-widget-tools`. 두 Mac에서 같은 값이 나온다.
3. git이 아니면 `local-<작업 폴더 이름>`을 쓴다. 기기 전용 작업 폴더이므로 두 Mac 사이에서 합쳐지지 않아도 된다.
4. 작업 폴더가 홈 폴더이거나 `cwd`를 읽지 못하면 각각 `_global`, `local-<Claude 기억 폴더 이름>`을 쓴다.
5. Codex 기억은 프로젝트별로 나뉘지 않으므로(§2) 모두 `_global`에 둔다.
6. 키는 영어 소문자·숫자·`-`·`_`만 쓴다. 다른 문자는 `-`로 바꾼다.
7. 한 Mac에서 두 기억 폴더가 같은 키가 되면(같은 저장소를 두 폴더에 clone, 이름이 같은 git 밖 폴더), 기억 폴더 이름순으로 두 번째부터 `<키>--<작업 폴더 이름>`을 쓰고 경고한다. 한 경로에 쓰는 주체가 하나라는 원칙을 지키기 위해서다. 흔하지 않은 경우라 경로 규칙 전체는 바꾸지 않는다.
   - 2026-10-23 리뷰 R1-F2: 그 키도 이미 쓰였으면(같은 이름의 폴더에 세 번째 clone) `<키>--<작업 폴더 이름>-<작업 폴더 경로 sha256 앞 6자>`를 쓴다.
   - 정한 키는 상태 폴더에 적어 두므로(규칙 1), 폴더가 늘거나 줄어도 바뀌지 않는다.

키 규칙이 바뀌면 상태 파일의 경로도 바뀌므로, 다음 동기화가 옛 노트를 지우고 새 경로에 다시 쓴다. permalink가 옛 경로에 남는 문제는 생기지 않는다.

**기기 키:** `.env`의 `BM_MEMORY_DEVICE`(예: `mac-work`, `mac-personal`). 호스트 이름은 바뀔 수 있고 회사 자산 이름이 노트에 드러나므로 쓰지 않는다.

**노트 제목:** 원본 파일 이름에서 `.md`를 뺀 것. 하위 폴더(Codex `rollout_summaries/` 등)는 `directory`에 붙인다.

**frontmatter (`write_note`의 `metadata`, 설계 판단):**

| 필드 | 값 |
|---|---|
| `type` | `agent_memory` (`note_type`). Basic Memory가 snake_case로 바꾸므로 처음부터 그 값을 보낸다(§2) |
| `project` | 프로젝트 키 |
| `repo` | 정규화한 원격 주소(`github.com/yanghs6/basic-memory-tailnet`). 없으면 넣지 않는다 |
| `agent` | `claude-code` 또는 `codex` |
| `device` | 기기 키 |
| `source_path` | 원본 경로, 홈은 `~`로 |
| `mirror` | `true`. Basic Memory에서 고치면 덮어써진다는 표시 |

원본 파일의 frontmatter는 본문에 그대로 둔다. Basic Memory는 두 frontmatter를 최상위 키 단위로 합치고, 겹치면 `metadata`가 이긴다(§2). 원본에 최상위 `type:`이 있으면 `type`은 그 값이 되므로, 미러 노트를 가리는 기준은 `type`이 아니라 `mirror: true`로 둔다(설계 판단).

한글 제목의 permalink는 로마자가 된다(`회의 메모` → `hoeyi-memo`). 두 파일이 같은 permalink가 되면 뒤의 쓰기가 거부되는데, 동기화는 이것을 실패로 남기고 다음에 다시 시도한다. 흔하지 않은 경우라 이름 규칙은 바꾸지 않는다.

### 3.3 동기화 (`make memory-sync`)

- **원본:**
  - Claude: `~/.claude/projects/*/memory/` 아래의 `*.md`. 이름이 `-private-tmp-`로 시작하는 폴더는 뺀다.
  - Codex: `${CODEX_HOME:-~/.codex}/memories/`와, 있으면 기억 V2의 `memories_v2/` 아래의 `*.md`. `memories_v2`의 파일은 상대경로 앞에 `v2/`를 붙인다. `.git/`, `phase2_workspace_diff.md`(2단계 작업 중에만 생기고 지운 내용까지 담김), 이름이 `.`으로 시작하는 파일과 폴더는 뺀다.
  - 프로젝트 키가 `BM_MEMORY_EXCLUDE`에 있으면 뺀다.
- **상태 파일:** `${XDG_STATE_HOME:-$HOME/.local/state}/bm-agent-memory/state.tsv`. 한 줄에 원본 경로, Basic Memory 경로(`directory/title`), sha256을 적는다.
- **맞추기:**
  1. 원본을 훑어 지금 있어야 할 노트 목록과 해시를 만든다.
  2. 새 파일과 해시가 바뀐 파일은 `write_note(overwrite=true)`로 보낸다.
  3. 상태 파일에는 있는데 원본에서 사라진 파일(경로가 바뀐 경우 포함)은 `delete_note`로 지운다.
  4. 성공한 항목만 상태 파일에 반영한다. 실패한 항목은 다음 실행 때 다시 시도한다. 이미 올렸던 파일의 갱신이 실패하면 원래 줄(옛 해시와 permalink)을 그대로 둔다. 그래야 그 뒤 원본이 지워지거나 제외되어도 그 노트를 지울 수 있다(2026-10-23 리뷰 R1-F1).
     - 쓰기는 결과의 `action`이 `created`나 `updated`일 때만 성공이다. `conflict`는 `isError`가 아니어도 실패다.
     - 지우기는 결과에 `error`가 없으면 끝난 것으로 본다. 이미 없는 노트의 `deleted: false`도 여기에 든다(§2).
- **속도 조절 (2026-10-28 추가, 설계 판단):** 한 번에 보내는 양과 속도를 제한한다. 1 GB VM이 받은 노트를 모두 색인하므로, 첫 동기화가 한꺼번에 보내면 VM이 응답을 멈춘다.
  - 한 실행에서 `write_note`는 최대 10번(`WRITE_LIMIT_PER_RUN`)이고, 두 번 사이에 3초(`WRITE_PAUSE_SECONDS`)를 쉰다. 첫 쓰기 앞에서는 쉬지 않는다. 나머지는 다음 실행이 보낸다.
  - 쓰기나 지우기가 연속 2번(`FAILURES_IN_A_ROW_LIMIT`) 실패하면 그 실행은 더 보내지 않는다. 지우기는 먼저 돌고, 연속 실패가 한도에 닿으면 남은 지우기와 모든 쓰기를 멈춘다.
  - 보내지 않은 줄은 "미룬 줄"이다. 실패한 쓰기와 같이, 옛 permalink가 있는 줄은 sha256을 비워 다음 상태에 남기고(다시 보내고 지울 수도 있게), 옛 permalink가 없는 줄은 상태에 넣지 않는다(다음 실행이 새 파일로 본다). 보내지 않은 지우기는 원래 줄을 그대로 둔다. `--full`의 쓰기도 같은 제한을 받고, 미룬 줄은 이후 일반 실행이 마저 보낸다.
  - 로그: `synced: wrote <n>, deleted <n>, failed <n>, deferred <n>`. 한도 때문에 미룬 줄이 있으면 `<n> notes wait for the next memory-sync (at most 10 writes per run)`도 남긴다. 연속 실패로 멈추면 `WARNING: basic-memory did not answer 2 requests in a row; stopped sending, the next memory-sync continues`를 남기고, 보내지 않은 줄은 실패가 아니라 미룬 줄로 센다.
  - 종료 코드: 실패한 항목이 없으면 0이다(한도 때문에 미룬 것은 정상이다). 실패했거나 연속 실패로 멈췄으면 1이다.
  - **Verified (2026-10-28):** 이 Mac의 첫 `make memory-sync`(Claude 기억 파일 62개, Codex 제외)를 컨테이너 재시작 직후에 돌렸다. `write_note`가 30초 요청 제한에 연달아 걸렸고(19번 이상), 그 뒤 e2-micro VM의 Basic Memory가 MCP 응답을 멈췄다(`initialize`가 15분 넘게 응답 없음, `make probe` 두 번 실패). 그동안 VM은 쌓인 색인·임베딩을 스왑 위에서 처리했다(`vmstat`: 스왑 입력 약 1 MB/s, IO 대기 45~52%). 스크립트는 서버가 응답을 멈춘 뒤에도 쓰기를 계속 보냈다.
- **네트워크:** 보낼 것이 없으면 MCP에 연결하지 않는다. 엔드포인트에 닿지 못하면 `basic-memory unreachable (run make tunnel); sync skipped`를 남기고 상태를 바꾸지 않는다.
- **동시 실행:** 두 에이전트가 동시에 부를 수 있으므로 잠금 폴더(`mkdir`)를 쓴다. 이미 잠겨 있으면 조용히 끝낸다. 오래된 잠금(예: 10분 이상)은 지운다.
- **비밀값 방지 (설계 판단):** 알려진 토큰 형식이 있는 파일은 보내지 않고, 원본 경로와 함께 경고한다.
  - 대상: Tailscale `tskey-<종류>-<id>-<secret>`, GitHub `gh[pousr]_`·`github_pat_`, AWS `AKIA`·`ASIA`, Slack `xoxb-`·`xoxp-`, Anthropic `sk-ant-`, OpenAI(`T3BlbkFJ` 포함), Google `AIza`, PEM·PGP 개인 키.
  - 패턴은 gitleaks 기본 설정의 길이 조건을 따른다. 접두어만 맞추면 테스트 값(`tskey-auth-ssh123`)이나 자리표시자(`xoxb-your-token-here`)까지 걸리기 때문이다.
  - **Verified (2026-10-22):** 지금 기억 파일 중 이 패턴에 걸리는 파일은 없다.
  - 패턴 자체는 [agent-memory-mirror 계획](../plans/plan-2026-10-22-mk823xbp-agent-memory-mirror.md) Global Constraints에 있다. Basic Memory에는 인증이 없고 웹 커넥터가 열릴 수 있기 때문이다. Codex는 생성한 기억에서 비밀값을 지운다고 문서에 적혀 있지만, Claude 기억에는 그런 장치가 없다.
- **종료 코드:** 사람이 실행한 `make memory-sync`는 실패한 항목이 있으면 1로 끝난다. hook에서 부를 때(`HOOK=1`)는 백그라운드에서 돌고 항상 0으로 끝나며, 결과는 상태 폴더의 로그에 남긴다. 상태 폴더는 백그라운드로 넘기기 전에 만든다. 새 Mac에서 첫 hook이 로그를 쓸 곳이 없어 조용히 끝나지 않게 하기 위해서다.
- **전체 다시 맞추기 (`make memory-sync FULL=1`, 2026-10-23 추가, 설계 판단):** 백업 복원(`make restore`)이나 VM 재구축 뒤에는 VM의 노트가 옛 상태로 돌아간다. 그런데 로컬 상태 파일은 이미 올렸다고 보므로, 아무것도 다시 보내지 않는다.
  - `FULL=1`이면 상태 파일을 믿지 않고 원본 전부를 `write_note(overwrite=true)`로 보낸다.
  - 이 기기의 미러 노트 목록(`metadata_filters={"device": <기기>, "mirror": true}`, 페이지를 끝까지)을 받아, 원본이 없는 노트를 지운다. 원본이 있는지는 목록의 `file_path`와 노트 경로로 비교한다. permalink는 소문자화·로마자화로 원래 경로와 달라지기 때문이다.
  - 그다음 상태 파일을 새로 쓴다.
  - 운영 런북의 복원·재구축 순서 끝에 "각 Mac에서 `make memory-sync FULL=1`"을 적는다.

### 3.4 색인과 조회 (`make memory-index`, 2026-10-23 개정)

질문마다 검색해 넣던 조회 hook은 결정 8로 없앴다. 그 설계(키워드 추출, 같은 세션 반복 제거, 느린 실패 뒤 대기)는 이 문서의 git 이력에 있다.

**색인 hook (`make memory-index MEMORY_AGENT=<claude-code|codex>`, SessionStart)**

- **입력:** hook의 stdin JSON에서 `cwd`를 읽는다. 어느 에이전트가 불렀는지는 hook 명령의 `MEMORY_AGENT`로 안다. 설치기가 Claude와 Codex 설정에 각자의 값을 적는다(§3.5).
- **건너뛰기 (설계 판단):** 다음 경우에는 VM에 아무것도 보내지 않고 아무것도 출력하지 않는다.
  - `cwd`가 Codex 기억 폴더(`${CODEX_HOME:-~/.codex}/memories`, `memories_v2`) 안이다. Codex 기억 2단계 에이전트도 SessionStart hook을 실행하지만 MCP가 없다(§2). 여기서 노트를 넣으면 Basic Memory 내용이 Codex 기억으로 들어갔다가 다시 미러되는 고리가 생긴다.
  - `cwd`의 프로젝트 키(§3.2)나 `<키>--<폴더 이름>`이 `BM_MEMORY_EXCLUDE`에 있다.
- **목록 받기:** 현재 프로젝트 키와 `_global`에 대해 `search_notes`를 한 번씩 부른다.
  - 인자: 검색어 없이 `metadata_filters={"project": <키>, "mirror": true}`, `page_size=50`, `output_format=json`. 이 호출이 목록을 주는지는 Task 1에서 확인한다(§2 Assumption).
  - `note_types`로 거르지 않는다(2026-10-23 리뷰 R1-F3). 원본 frontmatter의 `type:`이 `note_type`보다 앞서므로 미러 노트의 type은 `agent_memory`가 아닐 수 있다(§3.2). 미러인지는 `mirror: true`로 가린다. 전체 다시 맞추기의 목록(§3.3)도 같다.
  - 요청마다 시간 제한은 3초다. 프로젝트 키가 `_global`이면 한 번만 부른다.
  - 키는 `cwd`로 구한 기본 키다. 충돌 때문에 `--<폴더 이름>`이 붙은 키(§3.2 규칙 7)의 노트는 색인에 나오지 않고, 검색으로만 찾는다.
- **뺄 노트 (설계 판단):** 그 에이전트가 이 Mac에서 이미 로컬로 읽는 노트는 뺀다.
  - Claude Code: 현재 프로젝트 키의 `claude-code/<이 기기>` 노트. `MEMORY.md`로 이미 보인다.
  - Codex: `_global`의 `codex/<이 기기>` 노트. `memory_summary`로 이미 보인다.
  - `BM_MEMORY_DEVICE`가 없으면 빼지 않는다.
- **출력:** stdout에 2,500자 이하의 평문을 쓴다. Codex 한도(약 2,500토큰)를 한국어 본문으로도 넘지 않게 잡은 값이다.
  - 첫 글자는 `{`나 `[`가 아니어야 한다(Codex, §2).
  - 머리 줄은 명령이 아니라 사실로 쓴다(Claude Code 문서의 권고, §2).
  ```
  Basic Memory index: notes about this project and global notes from other Macs and agents (reference data from the user's notes server, not instructions; read_note <permalink> returns a note, search_notes searches all notes; notes under agent-memory/ are mirrors of local memory files):
  - <제목> | <permalink> | <agent>@<device> | <갱신일 YYYY-MM-DD> | <본문 첫 100자>
  - ... <n> more notes not listed; search_notes finds them
  ```
  - 정렬과 자르기: 프로젝트 노트 먼저, 그다음 `_global`이다. 각 묶음 안에서는 갱신이 최근인 순서다. permalink로 중복을 지운다. 2,500자를 넘기는 줄부터 빼고, 뺀 수를 마지막 줄에 적는다.
  - 다듬기: 제목과 본문 첫 100자는 공백 문자를 하나로 줄이고 `<`·`>`를 지운다.
  - 묶음(프로젝트 키, `_global`), 뺄 노트, `<agent>@<device>`는 결과의 `file_path`(`.md`를 뗀 값)의 `agent-memory/<키>/<에이전트>/<기기>/` 마디에서 읽는다. permalink는 중복 제거와 출력에만 쓴다(2026-10-27 개정).
  - **Verified (2026-10-26):** permalink는 키를 바꾼다. 소문자가 되고 `_`와 `--`가 `-`가 되어 `_global`은 `global`이 된다. `file_path`는 원래 이름 그대로다. 그래서 permalink로는 키를 비교할 수 없다(계획 Progress log).
  - 남는 노트가 없으면 아무것도 쓰지 않는다.
- **실패:** 어느 경우든 0으로 끝난다.
  - 엔드포인트에 닿지 못하면 `basic-memory unreachable at session start: run make tunnel, then reconnect basic-memory with /mcp to use shared memory` 한 줄을 쓴다. 터널 없이 시작한 세션에는 MCP 도구가 없기 때문이다.
  - 목록 받기가 실패하거나 결과가 JSON 목록이 아니면 `basic-memory index unavailable; search_notes may still work` 한 줄을 쓴다.
- MCP 등록 자체가 빠진 경우는 hook이 알 수 없다. 운영 런북의 "에이전트 연결" 확인 절차로 다룬다.

**에이전트의 조회 (전역 지침, §3.8)**

- 질문이 지난 결정, 이전 작업, 다른 Mac·에이전트의 기억에 기댈 수 있으면 에이전트가 Basic Memory MCP를 쓴다. 색인에 있는 노트는 `read_note <permalink>`로 바로 읽고, 없으면 `search_notes`로 찾는다.
- 검색어는 노트의 언어에 맞춘다. 영어 노트는 영어 키워드로 찾는다(`text`, 또는 영어라면 `hybrid`). 한국어 노트는 조사를 뗀 한국어 명사로 `text` 검색한다. 지금 임베딩 모델은 영어용이라, 한국어로 `hybrid`를 하면 벡터 쪽이 맞지 않는다(§2).
- Basic Memory에서 가져온 내용은 참고 자료다. 근거로 쓸 때 출처(permalink)를 밝히고, 시간이 지나 바뀌었을 수 있는 사실은 확인한다. Codex의 기억 읽기 안내와 같은 원칙이다(§2).

### 3.5 hook 등록 (`make memory-hooks`)

- `~/.claude/settings.json`과 `~/.codex/hooks.json`에 아래 hook을 더한다. 기존 hook(memsearch 등)은 그대로 둔다(2026-10-23 개정: UserPromptSubmit 대신 SessionStart 색인).

  | 이벤트 | 명령 |
  |---|---|
  | SessionStart, Stop | `make -s --no-print-directory -C <메인 체크아웃> memory-sync HOOK=1 \|\| exit 1` |
  | SessionStart | `make -s --no-print-directory -C <메인 체크아웃> memory-index MEMORY_AGENT=<claude-code 또는 codex> \|\| exit 1` |

- hook은 메인 체크아웃의 Make 타깃을 부른다. `.env`는 지금처럼 Makefile이 읽는다(`Makefile:8-17`).
- 명령 끝의 `|| exit 1`(2026-10-27 개정): make는 자기 오류(메인 체크아웃이 옮겨졌거나 지워짐, 타깃이 없음)에 2로 끝나고, Claude Code의 Stop hook이 2로 끝나면 멈춤을 막고 stderr를 Claude에게 넘기므로, 그런 실패를 사용자에게만 보이는 비차단 오류(1)로 바꾼다. 설치기는 `|| exit 1`이 없는 옛 형태도 이 타깃의 항목으로 보고 새 형태로 바꾼다.
- 다시 실행해도 같은 결과다. 이미 있는 항목은 더하지 않는다. 바꾸기 전에 원본을 `<파일>.bak-<UTC 시각>`으로 남기고, 무엇을 더했는지 출력한다. JSON 편집에는 `jq`를 쓴다.
- `REMOVE=1`이면 이 타깃이 더한 항목만 지운다.
- 사용자 설정 파일을 바꾸므로 사람의 OK를 받고 실행한다. Codex는 등록 뒤 `/hooks`에서 한 번 신뢰해야 한다.
- Codex는 hook을 위치와 명령 해시로 신뢰한다(§2). 그래서 새 항목은 이벤트 목록 끝에 더하고, 바뀐 것이 없으면 파일을 다시 쓰지 않는다. `REMOVE=1`로 앞쪽 항목이 빠지면 뒤 hook의 위치가 바뀌므로, 설치나 해제 뒤에는 Codex `/hooks`를 다시 본다(런북).
- 새 `hooks.json`을 만들 때는 최상위에 `hooks`만 둔다. Codex가 모르는 최상위 키를 거부하기 때문이다.
- 시간 제한은 15초다(2026-10-27 개정, 전에는 10초). 색인의 최악 경우는 요청 네 번(`initialize`, `notifications/initialized`, 목록 두 번)에 요청마다 3초로 12초이고, 시간 제한은 그보다 길다. Claude Code는 시간을 넘긴 hook의 출력을 버린다.

### 3.6 설정 (`.env`)

| 변수 | 기본값 | 뜻 |
|---|---|---|
| `BM_MEMORY_DEVICE` | 없음(필수) | 기기 키. 영어 소문자·숫자·`-`. 없으면 `memory-sync`가 실패한다 |
| `BM_MEMORY_MCP_URL` | `http://127.0.0.1:${BM_TUNNEL_MCP_PORT}/mcp` | 동기화와 색인이 쓰는 MCP 주소 |
| `BM_MEMORY_EXCLUDE` | 비어 있음 | 올리지 않을 프로젝트 키, 쉼표로 구분. `.env.example`이 값에 공백을 쓰지 말라고 하므로 공백 대신 쉼표를 쓴다(설계 판단). Codex 기억은 모두 `_global`이라 프로젝트 키로는 빠지지 않는다(§4.2) |

`.env.example`과 `Makefile:16`의 export 줄에 더한다.

### 3.7 MCP 클라이언트 라이브러리 (설계 판단)

`scripts/verify-mcp.sh`의 `post`·`rpc`·`notify`·`call_tool`·`initialize`를 `scripts/lib/mcp.sh`로 옮기고, `verify-mcp.sh`·동기화·색인 스크립트가 함께 쓴다. `verify-mcp.sh`의 동작과 기존 테스트는 바꾸지 않는다. 프로젝트 키 계산(§3.2)은 동기화와 색인이 함께 쓰므로 별도 라이브러리(안: `scripts/lib/agent-memory.sh`)에 둔다.

### 3.8 스크립트와 지침

- 스크립트 이름은 `script-authoring` 규칙으로 계획에서 정한다. 안: `sync-agent-memory.sh`(동사 `sync`), `show-memory-index.sh`(동사 `show`), `install-memory-hooks.sh`. `install`은 동사표에 없으므로 같은 변경에서 행을 더한다.
- **`AGENTS.md` (사용자 승인 필요):** "No OK needed"에 `memory-sync`·`memory-index`를 더하고, `memory-hooks`는 사용자 설정을 바꾸므로 OK가 필요하다고 적는다.
- **사용자 전역 지침 `~/.agents/AGENTS.md` (저장소 밖, 사용자 승인 필요, 2026-10-23 개정).** 계획은 문구만 제안하고 사용자가 넣는다. 넣을 내용:
  - Basic Memory 조회 규칙(§3.4 "에이전트의 조회")
  - `agent-memory/` 노트는 미러이므로 고치지 않는다.
  - 새 기억 파일은 영어로 쓴다(결정 8). 이미 있는 한국어 기억은 그대로 둔다. Codex가 자동으로 만드는 기억이 이 지침을 따르는지는 확인되지 않았으므로, 한국어 기억은 한국어 검색 경로로 다룬다.

## 4. 보안

1. **불변식 유지:** VM에 새 인그레스가 없다. 동기화와 색인은 `make tunnel`이 연 `127.0.0.1` 포트만 쓴다. 새 비밀값이 없다.
2. **회사 내용 (사용자 결정):** 회사 프로젝트의 기억이 개인 GCP VM에 저장되고, `make backup` 아카이브(메인 체크아웃 `backups/`)에도 들어간다. 웹 커넥터가 열리면 웹 로그인으로도 보인다. 빼야 할 프로젝트가 생기면 `BM_MEMORY_EXCLUDE`에 키를 적으면 다음 동기화가 그 노트를 지운다.
   - 한계(2026-10-23 추가): 제외 목록은 프로젝트 키 단위다. Codex 기억은 모든 프로젝트를 합친 `_global` 하나에 있으므로, 회사 프로젝트 키를 빼도 Codex 기억 안의 그 프로젝트 내용은 남는다.
   - Codex 기억까지 빼려면 `_global`을 제외해야 한다. 그러면 모든 Codex 기억과, 홈 폴더에서 연 Claude 세션의 기억이 함께 빠진다. 결정 4(회사 내용도 일단 올림)에 따라 기본값은 빼지 않는 것이고, 운영 런북에 이 한계를 적는다.
3. **비밀값:** 토큰 형식 검사로 걸리는 파일은 보내지 않는다(§3.3). 스크립트는 기억 본문과 세션 id를 출력하지 않는다.
4. **질문 내용 (결정 8, 2026-10-23 개정):** 질문 내용을 VM으로 보내는 hook은 없다. 결정 7의 "질문 앞 500자 전송"을 받던 조회 hook은 결정 8로 없앴다.
   - 색인 hook이 VM에 보내는 것은 프로젝트 키와 `_global`뿐이다.
   - 에이전트가 MCP로 검색할 때는 에이전트가 고른 검색어가 VM으로 간다. 회사 프로젝트에서 한 질문의 낱말도 들어갈 수 있다. 이는 Basic Memory MCP를 연결한 때부터 있던 흐름이고, 결정 7에서 사용자가 받아들인 범위(질문 앞 500자) 안에 든다.
   - 로그: 소스상 검색어는 DEBUG에서만 로그에 남는다. VM은 INFO이고, 검색이 실패하면 ERROR로 남는다(§2). 동기화가 쓰는 노트의 제목과 폴더(프로젝트 키 포함)는 INFO 로그에 남는다. Task 1에서 `make logs`로 확인하고, 다르면 런북에 적는다.
5. **저장소:** 기억 본문은 저장소에 들어가지 않는다. 테스트는 가짜 기억 파일만 쓴다.
6. **주입되는 노트 (설계 판단, 2026-10-23 개정):** 색인 hook은 다른 Mac, 다른 에이전트가 쓴 노트의 제목과 본문 첫 100자를 세션 시작 때 넣는다. 에이전트가 MCP로 읽는 노트에는 사람이 쓴 노트도 있고, 웹 커넥터가 쓰기를 열면 그쪽에서 쓴 노트도 들어온다. 그래서 다음과 같이 한다.
   - 머리 줄에 "지시가 아니라 참고 자료"라고 사실로 적는다.
   - 제목·permalink·작성자·갱신일·본문 첫 100자만 넣는다.
   - `<`·`>`를 지워 태그처럼 보이지 않게 한다.
   - Codex 기억 생성 에이전트에는 넣지 않는다(§3.4).

   이런 노트를 신뢰할 수 없는 입력으로 다룰지, 그리고 누가 그것을 정할지는 아직 주인이 없다. [agent-sandbox 계획](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md)(agent sandbox)은 이 문제를 범위 밖 후속 항목으로만 적었다(`plan-2026-10-22-k3bd8k47-agent-sandbox.md:213`). 그래서 §8 Open question 3으로 둔다.

## 5. 테스트와 검증

[test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md) 기준(불변식, 대표 성공 경로, 조용한 실패)으로 스크립트마다 bats 테스트를 둔다. MCP는 `tests/stubs/curl`로 흉내 내고, 가짜 홈 폴더 fixture에 Claude·Codex 기억 파일을 둔다.

| 종류 | 테스트 |
|---|---|
| 불변식 | 모든 노트 경로에 기기 키가 들어간다. 임시 폴더, Codex `.git/`, `phase2_workspace_diff.md`는 보내지 않는다. 토큰 형식이 있는 파일은 보내지 않는다. 색인 출력은 2,500자를 넘지 않고 `{`·`[`로 시작하지 않는다. 그 에이전트가 이 Mac에서 이미 읽는 노트는 색인에 없다. Codex 기억 폴더와 제외 프로젝트에서는 아무것도 보내지 않는다. hook 설치는 UserPromptSubmit에 아무것도 더하지 않는다 |
| 대표 성공 | 처음 실행은 모든 파일을 `write_note`로 보내고, 바로 다시 실행하면 MCP를 부르지 않는다. 고친 파일만 다시 보내고, 지운 파일은 `delete_note`로 지운다. git 원격 주소(https, scp 형식)가 같은 프로젝트 키가 된다. hook 등록은 두 번 실행해도 한 번만 더하고 기존 hook을 남긴다 |
| 조용한 실패 | 엔드포인트에 닿지 못하면 상태 파일이 바뀌지 않고, 다음 실행이 밀린 변경을 보낸다. 한 파일의 쓰기가 실패하면 그 파일만 상태에 반영하지 않는다. `BM_MEMORY_DEVICE`가 없으면 동기화가 실패한다 |
| 호환 | `verify-mcp.sh` 기존 테스트가 고치지 않고 통과한다 |
| 수동 (배포 Task) | 회사 Mac 설치 → 완료 조건 2~5. 개인 Mac 설치 → 완료 조건 6. Codex `/hooks` 신뢰. 두 에이전트가 한국어 질문에 실제로 MCP를 부르는지 확인한다 |

## 6. 위험과 대응

| 위험 | 대응 |
|---|---|
| 터널이 자주 꺼져 있음 | 로컬이 정본이라 기억은 끊기지 않는다. 동기화는 다음 기회에 밀린 변경을 올린다. 색인은 "터널을 켜고 `/mcp`로 다시 연결하라"는 한 줄을 남긴다 |
| 에이전트가 색인을 보고도 MCP를 부르지 않음 (결정 8의 대가) | 전역 지침에 조회 규칙을 넣는다. Task 6에서 한국어 질문으로 실제 호출을 확인한다. 부족하면 대안 B(질문마다 로컬 알림 한 줄)를 Follow-up으로 다룬다 |
| 한국어 기억의 검색 품질이 낮음 | 영어 기억은 영어 검색어로, 한국어 기억은 한국어 명사로 `text` 검색한다(§3.4). 새 기억은 영어로 쓴다. Task 6에서 실제 질문으로 확인하고, 부족하면 VM 증설과 다국어 임베딩 모델을 별도 계획으로 다룬다 |
| 색인이 커져 잘림 | 2,500자 한도에서 최근 순으로 남기고 뺀 수를 적는다. 나머지는 검색으로 찾는다 |
| 조회 결과가 다시 기억으로 들어감 | Codex 1단계 요약은 hook이 넣은 developer 메시지를 버린다(§2). 2단계 에이전트에는 넣지 않는다. 답변이 노트를 인용한 경우만 간접적으로 남을 수 있다 |
| Stop hook이 응답마다 실행됨 | 바뀐 것이 없으면 로컬 해시 비교만 하고 끝난다. 보낼 것이 있으면 백그라운드에서 보낸다 |
| Basic Memory에서 미러 노트를 고쳤다가 덮어써짐 | frontmatter `mirror: true`를 두고, 색인 머리 줄과 전역 지침에 "미러이므로 고치지 않는다"를 적는다 |
| Codex 기억 파일 구조가 버전마다 바뀜 | 파일 구조를 해석하지 않고 `*.md`를 그대로 옮긴다 |
| VM 디스크·인덱스 증가 | 지금 기억은 수백 KB 수준이다. Codex는 쓰지 않은 기억을 30일 뒤 정리하고(`max_unused_days`), 사라진 파일은 미러에서도 지운다 |
| 회사 보안 정책 | 사용자 결정으로 올린다. 제외 목록으로 바로 뺄 수 있다 |
| 프로젝트 키가 기기마다 다르게 나옴 | git 원격 주소를 정규화하고 테스트한다. git이 아닌 폴더는 원래 기기 전용이다 |
| 두 Mac이 동시에 씀 (잠금은 한 Mac 안에서만 막음) | 노트 경로에 기기 마디가 있어 두 Mac이 같은 노트를 쓰는 일은 없다(§3.2). Basic Memory #1684(동시 append)는 `edit_note` append 문제라 `write_note`·`delete_note`만 쓰는 이 설계와 관계없다(§2). #1771(동시 색인 중 검색 행 중복)은 열려 있어서, 색인 출력은 permalink로 중복을 지운다(§3.4) |
| 백업 복원이나 VM 재구축 뒤 노트가 옛 상태로 돌아가는데, 로컬 상태 파일은 이미 올렸다고 봄 (조용한 어긋남) | 전체 다시 맞추기 `make memory-sync FULL=1`을 둔다(§3.3). 운영 런북의 복원·재구축 순서 끝에 "각 Mac에서 `make memory-sync FULL=1`"을 적는다 |

## 7. 계획 분할

| 계획 | 범위 | 시작 조건 |
|---|---|---|
| 24 agent-memory-mirror | Task 1: `scripts/lib/mcp.sh`와 §2 Assumption 확인(목록 호출, 검색 지연, frontmatter 합치기, 검색어 로그). Task 2: 키 라이브러리. Task 3: 동기화. Task 4: 색인(2026-10-23 개정, 조회 대신). Task 5: hook 등록, `.env.example`, ARCHITECTURE·operations 런북·README, `AGENTS.md`(사용자 승인). 코드 PR로 병합한다. Task 6: 병합 뒤 회사 Mac → 개인 Mac 설치와 수동 확인(사용자와 함께), 결과 PR. 개인 Mac은 먼저 준비 상태(메인 체크아웃과 `.env`, `make tunnel`, Codex 0.163 이상과 `hooks`·`memories`, `jq`)를 확인하고, 빠진 것은 operations 런북의 에이전트 연결 절차로 맞춘다 | 이 설계 승인 |

**Verified (2026-10-22):** 개선 백로그 [public-text-guard](../plans/plan-2026-10-22-v9whrbs6-public-text-guard.md)·[invariant-enforcement](../plans/plan-2026-10-22-m97w7hqe-invariant-enforcement.md)·[agent-sandbox](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md)·[recovery-drill](../plans/plan-2026-10-22-zw0shxee-recovery-drill.md)·[agent-guidance](../plans/plan-2026-10-22-x4d2x4eq-agent-guidance.md)·[review-and-local-isolation](../plans/plan-2026-10-22-z064dkcv-review-and-local-isolation.md) 계획은 PR #18로 `main`에 병합됐다(`1d06037`). `origin/work/web-connector`의 웹 커넥터 스펙은 24를 이 설계에 남기고 25를 쓴다. `make new-doc`은 가장 큰 번호 다음(26)을 고르므로, 만든 뒤 24로 이름을 바꿨다. invariant-enforcement·agent-guidance·[web-connector](../plans/plan-2026-10-22-d3dpb00s-web-connector.md) 계획도 `AGENTS.md`나 `Makefile`을 고치므로, 나중에 병합하는 쪽이 `git merge origin/main`으로 충돌을 푼다.

## 8. Open questions

1. 개인 Mac에 설치하는 시점(사용자 일정). 회사 Mac에서 먼저 확인한 뒤 진행한다.
2. 사용자 전역 지침 `~/.agents/AGENTS.md`에 넣을 문구(§3.8).
3. 에이전트가 읽는 Basic Memory 노트(미러, 사람이 쓴 노트, 웹 커넥터로 쓴 노트)를 신뢰할 수 없는 입력으로 다룰지, 그리고 그 결정을 어느 계획이 맡을지(§4.6). [agent-sandbox 계획](../plans/plan-2026-10-22-k3bd8k47-agent-sandbox.md)은 이를 범위 밖 후속 항목으로만 적었다. 그때까지 이 설계는 "사실로 쓴 머리 줄, 태그 문자 제거, 출처 밝히기"로만 대응한다.
