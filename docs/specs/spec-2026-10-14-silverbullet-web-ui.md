---
status: approved
date: 2026-10-14
amended-by: docs/specs/spec-2026-10-15-access-modes.md
---

# Basic Memory 웹 UI (SilverBullet) — 설계

- [GCP 설계](spec-2026-10-12-basic-memory-gcp-tailscale.md)에 웹 UI를 더한다. 모든 계획은 [GitHub PR 워크플로](spec-2026-10-13-github-pr-workflow.md)와 [git·리뷰 정책](spec-2026-10-07-git-review-policy.md)을 따른다.
- 구현 계획:
  1. `plan-2026-10-14-10-web-ui-local.md`: compose 서비스, 공간 파일, 스크립트, `deploy`·`restore`의 `SB_USER` 처리, 테스트, 문서. VM에서는 아무것도 실행하지 않고 모두 로컬과 스텁으로 검증한다. `compose.yaml`에 SilverBullet이 들어가는 순간 VM `.env`에도 `SB_USER`가 있어야 하므로, `deploy`·`restore` 변경을 이 계획에 넣어 `main`을 계속 배포할 수 있는 상태로 둔다.
  2. `plan-2026-10-14-11-web-ui-vm-rollout.md`: `verify`·`probe`의 SilverBullet·Serve 검사, 부트스트랩의 Serve 8443, 실제 배포(사용자와 함께). 계획 10이 병합된 뒤 시작한다. 계획 05(PR #2, `f0b4f9c`)와 계획 08(`d59bfed`)은 병합됐다.
- 범위: tailnet 안의 브라우저에서 Basic Memory 노트를 읽고 편집하고(B), 백링크와 그래프로 탐색한다(C).
- 출처: 2026-10-14 사용자와의 브레인스토밍, 같은 날 로컬 스파이크(Basic Memory 0.23.2 + SilverBullet 2.12.1-slim, Mac arm64), 두 프로젝트의 소스(태그 `v0.23.2`, `2.12.1`)와 공식 문서.

## 1. 목표와 완료 조건

Self-hosted Basic Memory 0.23.2에는 웹 UI가 없다. REST API는 MCP 서버 프로세스 안에서만 쓰이고, 웹앱은 클라우드 전용이다. 같은 노트 폴더를 여는 SilverBullet 컨테이너를 더해 브라우저에서 노트를 보고 고칠 수 있게 한다.

**완료 조건**

1. `make local-up local-verify`가 기존 MCP 왕복과 SilverBullet 검사(§7.5)를 통과한다.
2. `make verify`가 기존 검사에 더해 다음을 통과한다.
   - `https://agent-hub.<tailnet>.ts.net:8443`에서 SilverBullet 검사(§7.5, 쿠키 `Secure` 포함)
   - 3000번 포트가 `127.0.0.1`에만 바인딩됨
   - 공인 IP의 8443·3000번이 닫힘
   - Serve가 443→`127.0.0.1:8737`, 8443→`127.0.0.1:3000`이고 Funnel off
3. Mac 브라우저에서 로그인한 뒤 다음을 확인해 진행 로그에 기록한다: 3단 레이아웃(트리 왼쪽, 목차 오른쪽, Linked Mentions 아래), Cmd-K 페이지 검색과 Cmd-Shift-F 노트 검색이 왼쪽에 열림, 노트 위 정보 줄, `memory://` 복사 명령, GitHub 테마(밝게·어둡게), 대시보드 네 구역과 유지보수 링크(§7.2), D2Koding 글꼴(Regular·Bold), `Graph: Explore`.
4. SilverBullet에서 새 페이지를 만들고 첫 줄 → Enter → 3초 대기 → 둘째 줄을 입력해도 줄바꿈이 남고, Basic Memory가 그 파일을 다시 쓰지 않는다. SilverBullet 전용 페이지(`index`, `Library/…`)가 `search_notes`에 나오지 않는다.
5. `make check`가 통과한다.
6. VM에서 두 컨테이너가 함께 돌 때의 메모리·스왑 사용량을 `make status`로 재서 ADR 0005에 기록한다. OOM이 나면 ADR 0002를 다시 판단한다.

**범위 밖**

- Basic Memory 관계 타입(`uses`, `depends_on`)을 그래프 엣지 이름으로 보여 주기. SilverBullet 그래프는 모든 링크를 `mention`으로 표시한다.
- 관찰 카테고리 클릭 문제(§3, §11)를 자동으로 되돌리는 Space Lua. 업스트림 수정 뒤에도 사고가 반복되면 다시 판단한다.
- SilverBullet API 토큰(`SB_AUTH_TOKEN`), 다중 사용자, 공개 노출
- VM 기본 서비스 계정 제거(권장, 별도 승인. §8.6)
- SilverBullet 업그레이드 스킬. 첫 업그레이드 때 필요하면 만든다.

## 2. 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 웹 UI | SilverBullet `2.12.1-slim` 컨테이너를 Basic Memory와 같은 compose 프로젝트에 둔다 | 같은 Markdown 폴더를 그대로 열고 편집·백링크·그래프를 제공한다. slim 서버는 수 MiB다(§3). 대안 비교는 ADR 0005 |
| 범위 | 읽기·편집(B)과 백링크·그래프(C) | 사용자 선택 |
| 노출 | 같은 tailnet 주소의 HTTPS 8443을 Serve로 `127.0.0.1:3000`에 연결한다 | 기존 443(Basic Memory)과 그 검증을 건드리지 않는다. 경로 방식은 Serve의 접두어 처리가 문서에 없고, 별도 tailnet 기기는 인증 키가 하나 더 필요하다 |
| 인증 | `SB_USER` 로그인, `SB_SHELL_BACKEND=off`, 별도 Docker 네트워크 | 인증 없는 SilverBullet은 다른 사이트의 단순 요청으로도 셸을 실행하고 프록시를 연다(§3) |
| 비밀값 | Tailscale 인증 키와 `SB_USER` 두 가지 | 인증 결정의 결과. 전달 경로는 §8.3 |
| 새 페이지 frontmatter | `editor:pageCreating` 훅이 `title`·`type`·`permalink`를 미리 채운다 | Basic Memory가 입력 중에 frontmatter를 끼워 넣으면 줄바꿈이 사라졌다(2/2). 훅 적용 뒤 0/2 |
| SilverBullet 전용 페이지 | 노트 폴더의 `.gitignore`로 Basic Memory 색인에서 빼고, 저널을 끈다 | 에이전트 검색 결과에 설정·저널·Quick Note 페이지가 섞였다(§3) |
| 레이아웃 | 내장 3단(트리·목차·Linked Mentions)과 대시보드 `index` | 사용자 선택. 커뮤니티에서 흔한 구성이고 내장 기능만 쓴다 |
| 대시보드 | 최근 수정 노트, 최상위 폴더, 카테고리별 관찰(`decision`·`risk`·`question`), 태그 | 사용자 선택. SilverBullet이 관찰을 `state`가 카테고리인 작업으로 색인한다(§3) |
| 글꼴 | `D2KodingLigature Nerd Font` Regular·Bold를 WOFF2로 바꿔 공간에서 `@font-face`로 제공한다 | 사용자 선택(모든 기기에서 같은 글꼴). WOFF2 합계 4.7MB |
| 테마 | 기본 테마의 색 변수만 GitHub Light Default·Dark Default 색(`@primer/primitives` 10.7.0, MIT)으로 바꾼다. 밝게·어둡게 전환은 SilverBullet 기본 기능 그대로 | 사용자 요청(기본 테마만 조정, 웹 조사 후 반영). VS Code Marketplace에서 설치 수가 가장 많은 테마(2026-10-14 기준 2,035만)이고, 밝은·어두운 공식 변형이 함께 있으며, Markdown을 읽을 때 GitHub에서 보던 색과 같다(§3) |
| 검색 | 페이지 검색(`std.pages`, Cmd-K)을 왼쪽 칸에 연다. 평소에는 트리가 있고, 검색하는 동안만 같은 칸이 검색으로 바뀌었다가 닫으면 트리로 돌아온다 | 사용자 요청(검색 바를 왼쪽에). 사이드바 칸마다 뷰는 하나만 열린다(§3) |
| 목차 | 내장 목차(`std.toc`)를 오른쪽에 기본으로 연다. 새 노트 템플릿에 목차를 넣지 않는다 | 사용자 요청(기본으로 목차). 노트 파일은 에이전트와 함께 쓰므로, 템플릿에 SilverBullet 위젯 문법을 넣으면 에이전트에게는 날 문법으로 보인다. 화면에서만 그리면 파일이 깨끗하다. Obsidian Outline, Docusaurus 오른쪽 목차와 같은 배치다 |
| 읽기·찾기 보조 | 노트 위 정보 줄(수정 시각, 단어 수, 읽기 시간, 백링크 수, `memory://` 주소), 전체 텍스트 검색 `Search: Notes`(Cmd-Shift-F, 왼쪽 칸), 명령 `Basic Memory: Copy memory:// Link`와 `Navigate: Random Note`, 대시보드의 유지보수 링크. 모두 Space Lua이고 노트 파일을 쓰지 않는다 | 사용자 요청(레퍼런스에서 많이 쓰는 요소를 Lua로). Obsidian 코어 플러그인(Search, Word count, Random note, Backlinks)과 다운로드 상위 플러그인(Omnisearch 200만), 문서 사이트의 "마지막 수정"을 근거로 골랐다. SilverBullet 2.12.1에는 전체 텍스트 검색이 없다(§3). 이미 내장된 것(질의, 표 편집, 강조 상자, 태그 목록, 그래프)과 이 저장소에 맞지 않는 것(칸반, 캘린더, 할 일)은 넣지 않는다 |
| Linked Tasks | 내장 Linked Tasks(`std.linkedTasks`)를 기본으로 닫는다 | Basic Memory 관찰은 SilverBullet에게 작업이다. 이 목록은 다른 페이지의 작업을 상태 클릭이 되는 채로 보여 주므로 카테고리 손실(§3) 위험을 넓힌다 |
| 관찰 카테고리 클릭 문제 | SilverBullet 업스트림 이슈와 런북 경고 | 근본 원인이 SilverBullet 코드에 있다. 이슈 게시는 사용자가 결정한다 |
| 계획 분할 | 계획 10(로컬)과 계획 11(VM) | 각 계획을 독립적으로 검증한다 |

## 3. 검증된 사실 (2026-10-14)

**Basic Memory 0.23.2**

- **Verified (`services/note_preparation.py:208-214`):** frontmatter의 `permalink`가 다른 파일과 겹치지 않으면 그 값을 그대로 쓴다. Basic Memory의 생성 규칙과 같을 필요가 없다.
- **Verified (`indexing/batch_indexer.py:397-422`):** frontmatter가 없으면 `title`·`type`·`permalink`를 써 넣고, frontmatter가 있으면 `permalink`가 다를 때만 그 줄을 고친다.
- **Verified (`utils.py:123-129`, 스파이크):** 한글은 Basic Memory의 CJK 범위에 없어 에이전트가 만든 노트의 permalink는 `unidecode`로 로마자가 된다. 훅이 만든 한글 permalink(`main/research/한글-테스트`)도 `read_note`와 `search_notes`로 조회된다.
- **Verified (`ignore_utils.py:21-23`, `:188-221`, `:240-276`):** 노트 폴더(프로젝트 루트)의 `.gitignore` 패턴을 기본 무시 목록(`.*` 포함, 그래서 점 파일은 기본으로 색인하지 않음)에 더한다. `/`로 시작하는 패턴은 루트 기준이고, 그렇지 않은 패턴은 경로의 어느 부분과도 맞춘다.
- **Verified (스파이크, `index/watch_service.py:129-133`):** 감시 프로세스가 무시 패턴을 캐시하므로 `.gitignore` 변경은 재시작 뒤에 적용된다. 이미 색인된 항목은 재시작해도 남는다.

**SilverBullet 2.12.1-slim**

- **Verified (`docker buildx imagetools inspect`):** index digest `sha256:7e24c16d31a3f4b4a4832ed64ec585e605a1e275b7c35917d385176f0b40415c`, linux/amd64·arm64·arm/v7 포함. 이미지 기본 healthcheck는 `curl --fail "http://localhost:$SB_PORT/.instance"`다.
- **Verified (스파이크, `docker stats`):** SilverBullet 서버 1.7~10.6 MiB(사용 뒤 2.5 MiB), 같은 때 Basic Memory 475~518 MiB (Mac arm64). 색인은 브라우저(IndexedDB)에서 한다.
- **Verified (스파이크):** 노트 폴더를 `/data`에 마운트하면 노트가 그대로 보인다. 위키링크, Linked Mentions(백링크), `Graph: Explore`, `Graph: Global Page Map`이 동작하고, 그래프 엣지는 모두 `mention`이다. 2.12.1에는 `Navigate: Tree`(왼쪽 사이드바)와 오른쪽 목차, 페이지 아래 Linked Mentions가 내장돼 있다.
- **Verified (스파이크):** 에이전트가 `edit_note`로 쓴 내용이 열린 페이지에 새로고침 없이 5초 안에 반영된다. 사용자와 에이전트가 같은 노트를 동시에 편집해도 양쪽 내용이 남는다. SilverBullet에서 쓴 내용은 Basic Memory `search_notes`에 반영된다(Docker Desktop 포함).
- **Verified (스파이크, `client/content_manager.ts:540-556`):** `editor:pageCreating` 리스너가 돌려준 텍스트가 없는 페이지의 초기 내용이 된다. 응답이 둘 이상이면 무시되므로 가상 페이지 패턴과 겹치면 안 된다.
- **Verified (스파이크):** 인증이 없으면 다른 origin의 `text/plain` POST로 `/.shell`이 명령을 실행하고(`{"stdout":"shell-probe\n"}`), `/.proxy/<host>`가 요청을 대신 보낸다. `/.fs`는 CORS 허용 헤더가 없어 다른 사이트가 읽거나 PUT할 수 없다(preflight 405).
- **Verified (스파이크, `server/src/shell.rs:1-23`):** `SB_SHELL_BACKEND`가 `local`이 아니면 셸이 꺼지고 `/.shell`이 405 `Shell commands are disabled`를 낸다(로그인 상태 포함).
- **Verified (스파이크, `server/src/handlers/auth.rs:122`):** `SB_USER`를 주면 로그인 전 `/.fs`·`/.shell`·`/.proxy`가 401이다. 세션 쿠키는 `SameSite=Lax; HttpOnly`다. 세션은 공간 루트의 `.silverbullet.browser-sessions.json`에 저장된다(`server/src/auth/browser_sessions.rs:10`).
- **Verified (`server/src/router.rs:349-353`, `:614-616`):** 인증 없이 열리는 경로 목록은 `/.ping`, `/.logout`, `/.auth*`, `robots.txt`, `sitemap.xml`과 클라이언트 번들이다. healthcheck는 이 목록에 있는 `/.ping`을 쓴다.
- **Verified (계획 10, 2026-10-15, 로컬 2.12.1-slim, `curl`):** 로그인 전 `/.fs/index.md`는 401이지만, 목록에 없는 `/.instance`는 200과 `{"instance":"<uuid>","version":"2.12.1-…"}`를 돌려준다. 그러니 이미지 기본 healthcheck도 지금 버전에서는 인증을 켜도 통과할 것으로 본다(추정, 직접 돌려 보지는 않음). 목록 밖 경로에 기대지 않으려고 `/.ping`으로 덮어쓴다.
- **Verified (`server/src/handlers/auth.rs:81-137`, `:163-212`):** `POST /.auth`는 성공과 실패 모두 HTTP 200 JSON으로 답한다(`{"status":"ok"}` 또는 `{"status":"error"}`). 성공일 때만 `auth_`로 시작하는 세션 쿠키를 붙인다. `GET /.logout`은 세션을 폐기하고 302로 답한다.
- **Verified (`server/src/auth/cookie.rs:49-57`, `:84-85`, tailscale `ipn/ipnlocal/serve.go:1088-1091`):** 세션 쿠키의 `Secure`는 요청에 `X-Forwarded-Proto: https`가 있을 때만 붙고, Tailscale Serve가 이 헤더를 붙인다. VM에서의 확인은 계획 11에서 한다.
- **Verified (`client/navigator/view_defaults.ts`, `client/navigator/builtins.ts:31-41`, `views/space_tree.ts:164-170`, 스파이크):** 트리 뷰 이름은 `std.spaceTree`이고, `config.set("view.defaults", {["std.spaceTree"] = {dock = "lhs", open = true}})`로 처음부터 왼쪽에 연다. 브라우저에 저장된 사용자 선택이 이 값보다 앞선다. 저장된 선택이 없는 새 origin(`localhost:3000`)에서 트리가 왼쪽에 열렸다.
- **Verified (`client/navigator/panel_lifecycle.ts:361-381`, `views/pages.ts:202-206`, 스파이크):** 사이드바 칸(`lhs`·`rhs`·`bhs`)에는 뷰가 하나만 열린다. 같은 칸에 기본으로 여는 뷰가 둘이면 하나는 경고와 함께 무시된다. 페이지 검색 `std.pages`는 `modal`·`lhs`·`rhs`·`bhs`에 놓일 수 있고, `["std.pages"] = { dock = "lhs" }`로 두면 Cmd-K가 왼쪽 칸에서 열린다. 트리가 열린 상태에서 Cmd-K를 누르면 검색이 트리 자리를 쓰고, Esc로 닫으면 트리가 돌아온다. 목차 `std.toc`는 오른쪽(`rhs`), Linked Mentions는 페이지 아래(`page-bottom`)가 기본이라 겹치지 않는다(`libraries/Library/Std/Widgets/Widgets.md:22-23`).
- **Verified (`client/styles/theme.scss:5-358`, 스파이크):** 기본 테마는 밝은 색을 `html`에, 어두운 색을 `html[data-theme="dark"]`에 CSS 변수(`--root-background-color`, `--link-color`, `--editor-task-state-color` 등)로 둔다. `space-style`에서 같은 선택자로 덮어쓰면 두 모드 모두 바뀐다.
- **Verified (`docs/Full Text Search.md`, `plugs/` 목록):** 2.12.1 코어에는 전체 텍스트 검색이 없다. 공식 문서는 커뮤니티 라이브러리(Silversearch, basic-search) 설치를 권한다. 이 설계는 외부 코드를 공간에 들이지 않고 `view.define`의 `search = "source"`(입력할 때마다 `source(ctx)`를 다시 부름, `silverbullet/docs/API/widget.md:225-226`)로 직접 만든다.
- **Verified (`libraries/Library/Std/Widgets/Widgets.md`, `silverbullet/docs/API/view.md:39-58`, 스파이크):** 사용자 뷰는 `view.define`으로 등록하고 `lhs`·`rhs`·`page-top` 등에 둔다. `frame = "minimal"`인 `page-top` 뷰는 제목줄 없이 본문처럼 보이고 내용이 없으면 숨는다. Linked Tasks는 다른 페이지의 작업을 체크·상태 변경이 되는 채로 `page-top`에 보여 주며 기본으로 열려 있다.
- **Verified (스파이크, 2026-10-14):**
  - 색인 객체의 필드: 페이지 `lastModified`는 `2026-10-14T11:49:06.750`처럼 로컬 시각 문자열이고, 프론트매터의 `permalink`도 들어 있다. 목록 항목은 `text`·`tags`·`ref`(`페이지@위치`), 헤더는 `name`·`ref`다. 관찰 줄은 목록 항목이 아니라 작업(`index.tasks()`, `state`·`name`·`tags`)으로 색인된다.
  - 문단은 `config.set("index.paragraph.all", true)`가 있어야 색인된다. 스파이크에서는 이미 색인한 브라우저와 처음 연 브라우저 모두 `Space: Reindex`를 한 번 실행한 뒤에야 문단이 검색됐다. 계획 10(2026-10-15)에서는 관리 페이지가 처음부터 있는 공간을 새 origin(`sb.localhost:3000`)으로 열었을 때 Reindex 없이 문단이 검색됐다. 스파이크의 누락은 설정을 나중에 더한 데서 생긴 것으로 본다(Assumption). 문단이 안 나올 때의 Reindex 안내는 그대로 둔다.
  - Space Lua에서 `query[[…]][1]`처럼 질의 결과를 바로 인덱싱하면 블록 전체가 파싱 오류가 된다. 변수에 담은 뒤 인덱싱한다.
  - `memory://main/projects/agent-hub`를 Basic Memory `build_context`에 넘기면 그 노트와 관찰·관계가 돌아온다.
  - 검색 패널이 트리를 밀어낸 상태에서 Esc로 닫으면 트리가 돌아온다. 검색 패널을 연 채로 새로고침하면 검색이 그 칸의 주인이 되어, 닫으면 칸이 비고 Cmd-O로 트리를 다시 연다.
  - (계획 10, Verified) 왼쪽 칸의 뷰들은 입력칸 하나를 함께 쓴다. 노트 검색어는 닫은 뒤에도 남아 트리와 Cmd-K 페이지 검색을 거르고, 지우면 원래대로 돌아온다(SilverBullet 내장 동작).
- **Verified (`obsidianmd/obsidian-releases` 통계, 2026-10-14):** Obsidian 커뮤니티 플러그인 다운로드 상위는 Excalidraw 850만, Templater 590만, Dataview 514만, Tasks 441만, Git 329만, Advanced Tables 328만, Calendar 319만이고, 전체 텍스트 검색 Omnisearch는 200만, Homepage 138만, Recent Files 121만이다. 코어 플러그인에는 Outline, Backlinks, Outgoing links, Search, Word count, Random note, Tags view 등이 있다(obsidian.md/help/plugins).
- **Verified (VS Code Marketplace 공개 API, 2026-10-14):** 테마 확장 설치 수는 GitHub Theme 20,347,397, One Dark Pro 12,829,109, Dracula 11,049,248, Tokyo Night 2,975,536, Catppuccin 1,449,733, Nord 1,293,571이다. One Dark Pro와 Dracula는 어두운 테마만 있다. GitHub 색값은 `@primer/primitives` 10.7.0(MIT)의 `dist/css/functional/themes/{light,dark}.css`에서 가져왔다.
- **Verified (스파이크):** 숨김 파일은 SilverBullet API로 읽거나 쓸 수 없다(404).
- **Verified (스파이크):** `space-style`로 `--editor-font`·`--ui-font`를 바꾸면 편집기와 UI에 적용된다. 공간의 WOFF2를 `@font-face`로 불러오면 Regular·Bold가 `loaded`가 되고, 두 번째 로드부터 동기화 캐시에서 읽는다. `python3 -m fontTools.ttLib.woff2 compress`로 Regular 6.3MB→2.3MB, Bold 6.5MB→2.4MB.
- **Verified (스파이크, `plugs/index/task.ts:108-117`):** 관찰 카테고리 글자(`[question]`)를 누르면 `[]`로 바뀌어 저장되고, Basic Memory는 그 관찰을 카테고리 `note`로 다시 색인한다. `taskStates`가 비어 있으면 다음 상태가 없어서 빈 값이 들어간다. `.sb-task-state`에 `pointer-events: none`을 줘도 막지 못하고, 순환 코드는 내장 플러그 안에 있다. 같은 문제를 다룬 열린 이슈는 없다.
- **Verified (스파이크):** SilverBullet은 관찰을 작업 객체로 색인하고 카테고리를 `state`에 둔다(`index.tasks()`의 `state`·`page`·`name`).
- **Verified (스파이크):** `config.set("journal.enabled", false)`로 저널 명령이 사라진다. Quick Note(`Inbox/<날짜>/<시각>`)에는 끄는 설정이 없다.
- **Verified (계획 10, 2026-10-15, 로컬):**
  - `Library/` 아래 페이지의 `space-lua`·`space-style`도 루트 페이지처럼 적용된다. 대시보드, 정보 줄, 테마(`--root-background-color` 어둡게 `#0d1117`, 밝게 `#ffffff`), 글꼴(`400 loaded, 700 loaded`)이 모두 `Library/agent-hub/agent-hub`에서 왔다.
  - SilverBullet이 `index.md`를 만들기 전에 배포가 먼저 두면 그대로 쓴다. `make local-up`이 SilverBullet보다 먼저 `wrote the dashboard index.md`를 냈고, `index`가 그 대시보드를 보여 줬다.
  - 대시보드 질의 API(`index.pages()`·`index.tasks()`·`index.tags()`의 필드, `table.sort`)가 문서대로 동작한다. 시드 노트 셋으로 일곱 절이 기대한 개수(폴더 셋, 결정·위험·질문 각 2개, `#sample (3)`)로 나왔다.
  - curl의 `--data-urlencode "password@-"`가 표준입력의 비밀번호를 그대로 보낸다. 실제 `SB_USER`로 `make local-verify`의 로그인이 통과했다.
  - 스파이크 때 쓴 origin(`localhost:3000`)에는 브라우저 캐시(`CONFIG.md` 등)가 남아, 첫 화면이 예전 스크립트로 그려져 `attempt to call a nil value (field 'dashboard')`가 났다. 새로고침한 탭과 새 origin(`sb.localhost:3000`)에서는 오류가 없었다. VM은 새 origin이므로 해당하지 않는다.
  - 2.12.1의 service worker 뒤에서는 페이지의 `fetch("/.fs/…")`가 파일을 읽고 쓰지 못한다(PUT은 405 `allow: GET,HEAD`, GET은 앱 HTML). 확인용 쓰기·읽기는 `client.space.writePage`·`readPage`로 한다.
  - Basic Memory `search_notes`의 기본 검색은 글자가 일치하지 않는 노트도 점수를 매겨 돌려준다. 무시 목록 확인은 `search_type: "text"`(0건)와 `list_directory`(노트만 있음)로 한다.
- **Verified (계획 11, 2026-10-15, `agent-hub-01`):**
  - Serve 뒤에서 쿠키에 `Secure`가 붙는다. `make verify`가 `https://…:8443`에서 로그인 쿠키 검사를 통과했다.
  - `sudo -n -u '#1000'`로 노트 폴더에 쓸 수 있다. `make deploy`가 공간 파일과 페이지를 오류 없이 썼다.
  - SilverBullet 컨테이너는 Basic Memory에 닿지 못한다. 컨테이너 안에서 `curl`로 `127.0.0.1:8737`, `silverbullet` 네트워크 게이트웨이의 `:8737`, `basic-memory-server:8000`을 불렀더니 모두 `000`이 나왔다.
  - amd64에서 `docker stats` 상주 메모리(스왑 제외)는 SilverBullet 6.6~26.9 MiB, Basic Memory 252~390 MiB이고 OOM은 없다(ADR 0005 "VM 측정").
  - `tailscale serve --bg --https=8443`은 기존 443 설정을 지우지 않는다(`serve status --json`에 두 포트가 모두 있음).
  - `serve status --json`의 모양은 테스트 스텁과 같다: `Web."<host>:<port>".Handlers["/"].Proxy`이고, Funnel이 꺼져 있으면 `AllowFunnel`이 없다.
  - Mac에서 tailnet 왕복이 300ms쯤이면 새 TLS 연결이 2초를 넘을 수 있다(`/.ping` 2.6초). 그러면 새 기기에서 처음 열 때 클라이언트의 2초 ping이 시간을 넘겨, 상단 막대가 빨갛게(`sb-sync-error`) 되고 글꼴 요청이 503을 받아 기본 글꼴로 보인다. 몇 초 뒤 새로고침하면 둘 다 정상이 된다.
- **Verified (계획 05 진행 로그 2026-10-13 Step 14, `docs/plans/plan-2026-10-07-05-vm-rollout.md:293`):** 22번이 닫힌 뒤에도 `make vm-bootstrap HOST=agent-hub </dev/null`이 Tailscale SSH로 키 없이 다시 실행되고 Serve를 다시 적용한다. 계획 11은 이 경로로 8443을 더한다.
- **Verified (tailscale `ipn/serve.go:53-76`, `:125-172`, `cmd/tailscale/cli/serve_v2.go:259-264`):** `tailscale serve status --json`은 `Web`(키 `<호스트>:<포트>`, 값의 `Handlers["/"].Proxy`)과 `AllowFunnel`(키 `<호스트>:<포트>`)을 담은 설정을 출력한다. 계획 11의 `verify`가 포트별 대상과 Funnel을 이 JSON으로 검사한다.

**Tailscale과 VM**

- **Verified (tailscale.com/kb/1242/tailscale-serve):** Serve 문서에는 HTTPS 포트 제한이 없다. `--set-path`가 접두어를 떼고 넘기는지는 문서에 없다.
- **Verified (tailscale.com/kb/1153/enabling-https):** HTTPS 인증서를 받은 기기 이름은 공개 CT 로그에 남는다.
- **Verified (`docs/runbooks/rbk-2026-10-12-gcp-vm.md:53`):** 기존 VM `agent-hub-01`은 기본 서비스 계정을 유지한다.

## 4. 아키텍처

```
[개인/회사 Mac] ── tailnet ──▶ https://agent-hub.<tailnet>.ts.net/mcp     에이전트 (MCP)
                          └──▶ https://agent-hub.<tailnet>.ts.net:8443    브라우저 (로그인)
                                      │ Tailscale Serve (HTTPS, tailnet 전용)
                                      ▼
GCP e2-micro (1GB + 스왑 1GB), Docker 프로젝트 basic-memory
  ├ basic-memory-server   127.0.0.1:8737 → :8000 /mcp      네트워크 basic-memory
  │    /srv/basic-memory/knowledge → /app/data
  │    /srv/basic-memory/config    → /home/appuser/.basic-memory
  └ silverbullet-server   127.0.0.1:3000 → :3000           네트워크 silverbullet
       /srv/basic-memory/knowledge/basic-memory → /data    (노트 폴더만)
```

- 신뢰 경계는 tailnet이다. Basic Memory는 지금처럼 tailnet에만 의존하고, SilverBullet은 여기에 로그인을 더한다.
- 두 컨테이너는 같은 노트 폴더를 공유한다. SilverBullet은 Basic Memory의 DB와 설정(`config/`)을 보지 못한다.
- 두 컨테이너는 같은 compose 프로젝트에 있다. `backup`·`restore`는 프로젝트 단위로 멈추고 시작하므로(`scripts/backup.sh:98`, `scripts/restore.sh:125`) SilverBullet도 함께 멈춘다.
- SilverBullet은 `/data` 소유자에서 실행 UID를 정한다. 부트스트랩이 데이터 루트를 1000:1000으로 만드므로(`scripts/remote/bootstrap.sh:116-121`) 두 컨테이너가 쓰는 파일의 소유자가 같고, 복원의 단일 UID `chown`(`scripts/restore.sh:137`)도 그대로 유효하다.

## 5. 저장소 구조 (변경분)

```
compose.yaml                     silverbullet 서비스, 두 네트워크 (§7.1)
silverbullet/notes.gitignore     노트 폴더 .gitignore의 원본 (§7.2)
silverbullet/agent-hub.md        관리 라이브러리 페이지의 원본 (§7.2)
silverbullet/index.md            대시보드 시드 (§7.2)
scripts/sb-space.sh              공간 파일 쓰기 (--local 또는 VM). .gitignore가 바뀌면 그 사실을 알림 (§7.3)
scripts/sb-fonts.sh              TTF → WOFF2 변환과 업로드 (--local 또는 VM) (§7.4)
scripts/verify-sb.sh             SilverBullet 검사, URL 인자 (§7.5)
scripts/deploy.sh  restore.sh  lib/common.sh   (§7.3, §8.3) — 계획 10
scripts/verify-vm.sh  bootstrap-vm.sh  remote/bootstrap.sh   (§7.6, §7.7) — 계획 11
Makefile                         sb-fonts 추가, local-up·local-verify 변경, SB_PORT export, SB_USER는 일곱 타깃에만 export (§8.3)
.env.example                     SB_PORT=3000, 빈 SB_USER= ("main 체크아웃 .env에만 적고 커밋 금지" 주석)
tests/*.bats, tests/stubs/       §10 (curl·sudo·tailscale 스텁 확장, python3 스텁 추가)
docs/decisions/0005-web-ui-silverbullet.md  docs/ARCHITECTURE.md  docs/runbooks/operations.md  README.md  AGENTS.md
```

저장소 안에 `.gitignore`라는 이름을 두면 저장소 자체의 무시 규칙이 되므로 원본은 `notes.gitignore`로 둔다. 글꼴 파일은 저장소에 넣지 않는다. 공개 저장소에 4.7MB 바이너리가 들어가고, Nerd Fonts 아이콘 세트의 저작자 표시 의무(CC BY 4.0 등)가 따라오기 때문이다.

## 6. Make 타깃

| 타깃 | 동작 |
|---|---|
| `local-up` | 노트 폴더를 만들고 `sb-space.sh --local`을 실행한 뒤 두 서비스를 올린다 (§7.3과 같은 순서) |
| `local-verify` | 기존 MCP 검증에 `verify-sb.sh http://127.0.0.1:$(SB_PORT)`를 더한다 |
| `sb-fonts` (신규) | Mac 글꼴을 WOFF2로 바꿔 VM 노트 폴더에 올린다. VM을 바꾸므로 사용자 승인이 필요하다. `make sb-fonts LOCAL=1`은 로컬 |
| `deploy` | §7.3 순서 (계획 10) |
| `verify` | §7.6 (계획 11) |
| `probe` | 로그인 없는 SilverBullet 검사(§7.5 `--read-only`)와 Serve 검사를 더한다. 노트와 세션을 만들지 않는다 (계획 11) |
| `status`, `logs`, `local-down` | 변경 없음 (`compose ps`·`logs`·`down`이 두 서비스를 함께 다룬다) |
| `backup` | 코드 변경 없음 (§4) |
| `restore` | 시작 전에 `SB_USER`를 검사하고, VM에 올리는 파일을 `umask 077`로 쓴다. 복원도 VM `.env`를 새로 쓰기 때문이다(§8.3) |

## 7. 컴포넌트 동작

### 7.1 compose `silverbullet` 서비스

```yaml
  silverbullet:
    image: ghcr.io/silverbulletmd/silverbullet:2.12.1-slim@sha256:7e24c16d31a3f4b4a4832ed64ec585e605a1e275b7c35917d385176f0b40415c
    container_name: silverbullet-server
    ports:
      - "127.0.0.1:${SB_PORT:-3000}:3000"
    volumes:
      - "${BM_KNOWLEDGE_DIR:-./.local-data/knowledge}/basic-memory:/data"
    environment:
      SB_USER: ${SB_USER:?set SB_USER in the main checkout .env}
      SB_SHELL_BACKEND: "off"
      SB_RUNTIME_API: "0"
    depends_on:
      basic-memory:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:3000/.ping"]
    networks: [silverbullet]
    restart: unless-stopped
```

- `basic-memory` 서비스에는 `networks: [basic-memory]`를 붙인다. 두 네트워크는 서로 다르다.
- `depends_on`으로 Basic Memory가 노트 폴더(`basic-memory/`)를 만들고 무시 패턴을 읽은 뒤에 SilverBullet이 뜬다. Linux Docker가 없는 바인드 경로를 root 소유로 만드는 일도 막는다.
- 실제 digest는 계획 10에서 릴리스 노트를 읽고 다시 확인한 뒤 고정한다. 헬스체크는 `interval: 30s`, `timeout: 5s`, `retries: 3`, `start_period: 30s`, `start_interval: 2s`로 둔다. SilverBullet은 몇 초 안에 뜨므로 `up --wait`가 첫 `interval`(30초)을 기다리지 않게 한다.

### 7.2 공간 파일

| 노트 폴더 안 경로 | 원본 | 정책 |
|---|---|---|
| `.gitignore` | `silverbullet/notes.gitignore` | 매번 덮어쓴다. 내용이 바뀌면 Basic Memory를 다시 만든다(§7.3) |
| `Library/agent-hub/agent-hub.md` | `silverbullet/agent-hub.md` | 매번 덮어쓴다 |
| `index.md` | `silverbullet/index.md` | 없을 때만 만든다 |
| `Library/agent-hub/fonts/D2KodingLigatureNerdFont-{Regular,Bold}.woff2` | Mac 글꼴 (`make sb-fonts`) | 한 번 올리고 이후는 백업으로 보존 |

**`notes.gitignore`:** `/CONFIG.md`, `/index.md`, `/Library/`, `/Repositories/`, `/Journal/`, `/Inbox/`. 모두 루트 기준(`/`로 시작)으로 쓴다. `/` 없이 `index.md`라고 쓰면 `projects/index.md`까지 빠진다. 세션 파일 같은 숨김 파일은 기본 무시 목록(`.*`)이 막는다.

**`agent-hub.md` (관리 라이브러리 페이지):** 사용자용 `CONFIG.md`를 덮어쓰지 않도록 스타일과 Lua를 이 페이지에 둔다.

- **글꼴:** `@font-face`로 Regular(400)·Bold(700) WOFF2를 `/.fs/Library/agent-hub/fonts/…`에서 불러오고, `--editor-font`·`--ui-font`를 `"D2Koding Space", "D2KodingLigature Nerd Font", "D2Coding", "Menlo", monospace`로 둔다.
- **새 페이지 훅 (`editor:pageCreating`):**
  - 가상 페이지 패턴(`config.get("virtualPages")`)에 맞는 이름과 `notes.gitignore`가 빼는 페이지(`index`, `CONFIG`, `Library/`·`Repositories/`·`Journal/`·`Inbox/` 아래)는 건너뛴다.
  - 그 밖의 새 페이지는 다음 내용으로 시작한다. `title`은 이름의 마지막 부분이고 YAML 큰따옴표로 감싼다. `permalink`는 `main/` 뒤에 이름을 소문자로 바꾸고 공백·밑줄 묶음을 `-`로 바꾼 값이다. `main`은 `BASIC_MEMORY_DEFAULT_PROJECT`다.

    ```
    ---
    title: "<마지막 부분>"
    type: note
    permalink: main/<소문자-하이픈 이름>
    ---
    |^|
    ```
- **저널 끄기:** `config.set("journal.enabled", false)`를 저널 라이브러리의 명령 정의(`priority: -1`)보다 먼저 실행되는 우선순위로 둔다.
- **대시보드 함수 `agentHub.dashboard()`:** 마크다운 문자열을 돌려준다.
  1. 최근 수정 노트 10개 (`notes.gitignore`의 경로와 `index`, `CONFIG` 제외)
  2. 최상위 폴더 바로가기
  3. 카테고리별 관찰 `decision`·`risk`·`question` (각 최대 10개, 페이지 링크 포함)
  4. 태그 목록
- **레이아웃 1:** 트리를 왼쪽에 기본으로 열고, 페이지 검색(`std.pages`)과 노트 검색(`agentHub.search`)도 왼쪽 칸에 둔다. 목차(`std.toc`)는 오른쪽에 기본으로 열고, Linked Mentions(아래)는 내장 기본값, Linked Tasks는 기본으로 닫는다(`view.defaults`).
- **읽기·찾기 보조 (노트 파일은 쓰지 않음):**
  - 정보 줄 `agentHub.pageInfo`(`page-top`, `frame = "minimal"`, 흐린 작은 글씨): `Updated <수정 시각> · <단어 수> words · ~<분> min read · <백링크 수> backlinks · memory://<permalink>`. Basic Memory 노트가 아닌 페이지에는 그리지 않는다. 읽기 시간은 분당 200단어로 셈한다.
  - 노트 검색 `Search: Notes`(Cmd-Shift-F, Ctrl-Shift-F): 헤더, 관찰(`[카테고리] 내용 #태그`), 목록 항목(태그 포함), 문단에서 대소문자를 무시한 부분 문자열로 찾는다. 2바이트 이상부터, 최대 100건. 결과를 고르면 그 줄로 이동한다. 문단 색인을 위해 `index.paragraph.all`을 켠다.
  - 명령 `Basic Memory: Copy memory:// Link`: 현재 노트의 `memory://<permalink>`를 클립보드에 복사한다(HTTPS·localhost에서만 동작). 에이전트에게 노트를 가리킬 때 쓴다.
  - 명령 `Navigate: Random Note`: Basic Memory 노트 중 하나를 연다.
  - 대시보드 끝에 SilverBullet 내장 유지보수 페이지(`Library/Std/Pages/Maintenance`, 끊긴 링크·모호한 링크) 링크.
- **테마:** `space-style`로 `html`(밝게)과 `html[data-theme="dark"]`(어둡게)의 색 변수를 GitHub Light Default·Dark Default 색으로 바꾼다. 배경·패널·테두리·글자·링크·태그·인용·표·코드·검색 안내·관찰 카테고리(`--editor-task-state-color`, 밝게 `#9a6700`, 어둡게 `#d29922`)가 대상이다. 글꼴 변수는 위의 글꼴 설정을 그대로 쓴다.

**`index.md`:** 제목 한 줄과 `${agentHub.dashboard()}`만 둔다. 대시보드를 고칠 때는 관리 페이지만 바꾸면 되고, 사용자가 `index.md`에 더한 내용은 배포가 지우지 않는다.

**Quick Note:** 그대로 둔다. 결과물이 `Inbox/`에 쌓여 SilverBullet 전용 메모가 된다.

### 7.3 공간 파일 쓰기와 배포 순서

`scripts/sb-space.sh`가 로컬(`.local-data/knowledge/basic-memory/`)과 VM(`/srv/basic-memory/knowledge/basic-memory/`)에 같은 규칙으로 쓴다. VM에서는 컨테이너 UID(`sudo -n -u '#1000'`)로 쓴다.

실행 중인 Basic Memory는 재시작 전까지 예전 무시 패턴을 쓰고, 이미 색인한 항목은 재시작 뒤에도 지우지 않는다(§3). 그래서 `.gitignore`가 바뀌는 실행은 두 단계로 나눈다. 먼저 `.gitignore`만 쓰고, 호출자가 Basic Memory를 다시 만든 뒤 다시 실행해서 페이지를 쓴다.

1. 노트 폴더가 없으면 만든다.
2. `.gitignore`의 기존 내용을 읽는다. 원본과 다르면 표시 파일 `.gitignore.pending`을 먼저 만든 뒤 원본으로 덮어쓴다. 점 파일이라 Basic Memory(기본 무시 패턴 `.*`)와 SilverBullet 모두 보지 않는다.
3. 표시 파일이 있으면 표준출력에 `changed`를 쓰고 여기서 끝낸다. 관리 페이지와 `index.md`는 쓰지 않는다. 표시 파일은 호출자가 Basic Memory를 다시 만든 뒤에만 지우므로, pull이나 재생성이 실패한 실행을 다시 돌려도 `changed`가 나오고 페이지는 계속 기다린다.
4. 표시 파일이 없으면 관리 라이브러리 페이지를 쓴다.
5. `index.md`가 없을 때만 쓴다. 있는지 확인하지 못하면 쓰지 않고 실패한다.
6. 표준출력에 `unchanged`를 쓴다.

`deploy.sh` 순서:

1. `SB_USER`를 검사한다(§8.3). 값이 없거나 형식이 틀리면 VM을 건드리기 전에 멈춘다.
2. `compose.yaml`을 올린다.
3. VM `.env`를 쓴다. 내용은 `vm_env`의 기존 세 줄에 `SB_PORT`·`SB_USER`를 더한 것이다. `umask`는 새 파일에만 적용되므로, 이미 있는 `.env`(권한 664)를 위해 `chmod 600`을 내용보다 먼저 한다.
4. `sb-space.sh`(VM)를 실행한다.
5. `pull -q`
6. `sb-space.sh`가 `changed`를 냈으면 `up -d --wait --force-recreate basic-memory`로 Basic Memory만 먼저 다시 만들고, 성공하면 표시 파일을 지운 뒤 `sb-space.sh`를 다시 실행해 관리 페이지와 `index.md`를 쓴다. 두 번째 실행이 `unchanged`를 내지 않으면 멈춘다. VM 콜드 스타트는 161~192초다. 첫 반영 때와 무시 목록을 바꿀 때(그 배포를 다시 시도할 때 포함)만 일어난다.
7. `up -d --wait`로 SilverBullet까지 올린다.

`local-up`도 같은 순서를 로컬에서 따른다(2·3·5 단계 제외. 1단계 `SB_USER` 검사는 첫 레시피 줄이 한다). `sb-space.sh --local`이 `changed`를 내면 Basic Memory를 다시 만들고 표시 파일을 지운 뒤 `sb-space.sh --local`을 다시 실행하며, 어느 단계든 실패하거나 두 번째 실행이 `unchanged`가 아니면 SilverBullet을 올리기 전에 멈춘다. macOS의 GNU make 3.81은 `.SHELLFLAGS`를 적용하지 않아 레시피가 `-e` 없이 돌므로, 레시피 줄이 `|| exit 1`과 `&&`로 실패를 직접 전한다.

`restore.sh` 순서(정지·압축 해제·manifest 대조·`compose.yaml`과 VM `.env` 적용 다음):

1. 데이터를 교체한다(기존 데이터는 `.prev-*`). 두 컨테이너는 멈춰 있다.
2. Basic Memory가 멈춘 동안 `sb-space.sh`(VM)를 실행한다. 멈춘 Basic Memory는 기동할 때 `.gitignore`를 읽으므로 다시 만들 필요가 없다. `changed`가 나오면 표시 파일을 바로 지우고 `sb-space.sh`를 다시 실행해 관리 페이지와 `index.md`를 쓴다. 두 번째 실행이 `unchanged`를 내지 않으면 멈춘다.
3. `up -d --wait`로 두 컨테이너를 올린다.

2단계가 실패하면 교체 뒤의 다른 실패처럼 이전 데이터·`compose.yaml`·`.env`로 롤백하므로, 반쯤 쓴 공간으로 컨테이너가 뜨지 않는다. 그래서 계획 10 이전의 백업(노트 `.gitignore`와 관리 페이지가 없음)을 복원해도 Basic Memory가 SilverBullet 전용 페이지를 색인하지 않는다(완료 조건 4). 공간 파일이 기동 전에 모두 있으므로 SilverBullet이 `index.md`를 먼저 만드는 경합도 없다.

### 7.4 `sb-fonts.sh`

- 입력: `${SB_FONT_DIR:-$HOME/Library/Fonts}/D2KodingLigatureNerdFont-{Regular,Bold}.ttf`. 없으면 Nerd Fonts 릴리스에서 설치하라고 안내하고 멈춘다.
- `python3`과 `fontTools`·`brotli`가 없으면 `python3 -m pip install --user fonttools brotli`를 안내하고 멈춘다.
- 임시 디렉터리에서 WOFF2로 바꾼 뒤 `Library/agent-hub/fonts/`에 올린다. VM에는 ssh 표준입력으로, 로컬(`--local`)에는 파일 복사로 쓴다.

### 7.5 `verify-sb.sh [--read-only] URL`

1. `GET /.ping`이 200이다.
2. 쿠키 없이 `GET /.fs/index.md`가 401이다. (`--read-only`는 여기까지이며 `SB_USER`가 필요 없다)
3. `SB_USER`로 `POST /.auth`가 200이고 본문이 `{"status":"ok"}`이며, `auth_` 세션 쿠키에 `SameSite=Lax`와 `HttpOnly`가 있다. 비밀번호가 틀려도 200이 오므로 상태 코드만 보지 않는다(§3). URL이 `https`이면 `Secure`도 있어야 한다. 비밀번호는 curl의 표준입력으로 넘기고, `SB_USER`와 쿠키 값은 출력하지 않는다.
4. 세션으로 `POST /.shell`이 405다.
5. 글꼴 파일 `GET`이 200이 아니면 실패하지 않고 `make sb-fonts`를 안내하는 경고만 낸다.
6. 끝나거나 중간에 실패해도 `GET /.logout`으로 세션을 정리한다.

### 7.6 `verify-vm.sh`

- `check_loopback_binding "$SB_PORT"`를 더한다.
- 공인 IP 점검 포트(`PUBLIC_PROBE_PORTS`)에 8443과 `SB_PORT`를 더한다.
- Serve 검사를 엄격하게 바꾼다: `tailscale serve status --json`을 jq로 읽어 `AllowFunnel`에 켜진 항목이 없고, 443→`http://127.0.0.1:${BM_PORT}`, 8443→`http://127.0.0.1:${SB_PORT}`가 모두 있어야 한다(§3). 지금 검사는 대상이나 포트를 보지 않는다(`scripts/verify-vm.sh:27-36`).
- `verify-sb.sh https://agent-hub.<domain>:8443`을 실행한다(`probe`는 `--read-only`).

### 7.7 부트스트랩 `configure_serve`

`tailscale serve --bg --https=8443 "http://127.0.0.1:${SB_PORT}"`를 더하고, `tailscale serve status`에 두 대상(`127.0.0.1:${BM_PORT}`, `127.0.0.1:${SB_PORT}`)이 모두 보이는지 확인한다. VM에는 jq가 없으므로 포트별 대상 검사는 `verify`(§7.6)가 맡는다. 기존 VM에는 `make vm-bootstrap HOST=agent-hub`를 다시 실행해 적용한다(§3).

## 8. 보안

1. **SilverBullet 불변식 (테스트로 강제):** `SB_USER: ${SB_USER:?…}`(값이 없으면 compose가 실행을 거부), `SB_SHELL_BACKEND: "off"`, `SB_RUNTIME_API: "0"`, Basic Memory와 다른 Docker 네트워크, `127.0.0.1` 바인딩, digest 고정.
2. **로그인:** 세션 쿠키는 `SameSite=Lax; HttpOnly`라 다른 사이트의 POST에는 붙지 않는다. 로그인 실패 잠금은 기본값(10회, 60초)을 쓴다.
3. **`SB_USER`(`user:password`)의 흐름:**
   - 사용자가 main 체크아웃의 `.env`에 직접 적는다. 채팅이나 명령 인자로는 다루지 않는다.
   - 문자는 영문자, 숫자, `._~+/=-`만 쓴다(사용자 이름은 `._-`까지). make는 `.env`를 그대로 읽어 `#`을 주석으로, `$`를 변수로 해석하고, docker compose `.env`도 `$`를 해석하기 때문이다. `require_sb_user`가 형식을 검사한다. 비밀번호 예: `openssl rand -base64 24`.
   - make가 이미 바꾼 값은 형식 검사를 통과할 수 있다(예: `admin:abc#def`는 `admin:abc`로 잘리고, `$s`는 빈 값으로 펼쳐진다). 그래서 `SB_USER`를 받는 일곱 타깃은 값이 아닌 경로 `SB_ENV_FILE`(main 체크아웃 `.env`)도 타깃별로 export하고, `require_sb_user`는 그 파일의 마지막 `SB_USER=` 줄을 그대로 읽어(접두어와 줄 끝 CR만 뗀다) 받은 값과 비교한다. 다르면 두 값을 출력하지 않고 파일 경로와 허용 문자를 알리며 멈춘다. `SB_ENV_FILE`이 없으면(스크립트를 직접 실행할 때) 비교를 건너뛴다. `local-up`은 compose를 부르기 전 첫 레시피 줄에서 `scripts/lib/common.sh`를 읽어 `require_sb_user`를 실행한다.
   - Makefile의 export 목록(`Makefile:13`)에는 `SB_PORT`만 더한다. `SB_USER`는 compose나 VM에 로그인을 넘기거나 로그인해 검사하는 일곱 타깃(`local-up`, `local-down`, `local-logs`, `local-verify`, `deploy`, `restore`, 계획 11에서 더한 `verify`)에만 타깃별로 export한다. 읽기 전용 `probe`는 받지 않는다(`<타깃들>: export SB_USER := $(SB_USER)`). 전역 export는 모든 레시피 환경에 들어가, `make review`가 실행하는 다른 벤더 CLI(`codex exec`, `claude -p`, `scripts/review.sh:129-141`)도 비밀값을 보게 되기 때문이다. GNU make 3.81(macOS 기본)에서 타깃별 export는 이름을 적은 타깃에만 닿는다(계획 10 사전 점검에서 확인). 레시피 인자로 넘기면 make가 명령을 출력하므로 쓰지 않는다.
   - VM `.env`는 배포·복원 때마다 `vm_env`가 새로 쓰므로(`scripts/lib/common.sh:65-69`, `scripts/deploy.sh:19`, `scripts/restore.sh:142`) 여기에 넣는다. 전송은 지금처럼 ssh 표준입력이다. 파일 권한은 `600`이다(배포는 내용보다 `chmod`를 먼저, 복원은 `umask 077`).
   - 컨테이너 재시작에는 필요 없다(Docker가 저장된 설정으로 다시 띄운다). 그래도 VM `.env`에 남겨 두는 이유는 `backup`의 stop·start, `status`, `logs`가 VM에서 compose 파일을 읽을 때 `${SB_USER:?}`가 값을 요구하기 때문이다.
   - 스크립트는 값을 출력하지 않고, 필요하면 `mask`를 쓴다. 로그인 확인(§7.5)은 비밀번호를 명령 인자가 아니라 curl 표준입력으로 넘긴다.
   - 로컬도 같은 값으로 인증을 켠다. 로컬 포트도 브라우저를 거친 다른 사이트의 요청을 받을 수 있기 때문이다.
4. **세션 파일:** `.silverbullet.browser-sessions.json`은 노트 폴더 루트에 생기고 Basic Memory 기본 무시 목록에 걸린다. 백업에는 포함되며, 백업은 지금처럼 main 체크아웃의 `backups/`(git 제외)에만 둔다.
5. **공개 노출:** 지금처럼 없다. GCP 방화벽은 바꾸지 않는다. 8443은 Serve로 tailnet 안에서만 열린다. Funnel 금지 테스트(`tests/repo.bats:163-166`)를 유지한다.
6. **VM 기본 서비스 계정 (범위 밖, 권장):** 로그인한 사용자는 `/.proxy`로 메타데이터 서버에 닿을 수 있다. 서비스 계정을 떼면 이 경로의 가치가 사라진다. VM을 멈춰야 하는 클라우드 변경이므로 별도로 승인받는다.

## 9. 운영 흐름 (런북)

**`rbk-2026-10-12-operations.md`에 더할 내용**

- 웹 UI: `https://agent-hub.<tailnet>.ts.net:8443`, 로그인. 트리는 `Cmd-O`, 페이지 검색은 `Cmd-K`, 노트 본문 검색은 `Cmd-Shift-F`, 그래프는 `Graph: Explore`. 에이전트에게 노트를 알려 줄 때는 `Basic Memory: Copy memory:// Link`.
- 노트 검색에 본문 문단이 안 나오면 그 브라우저에서 `Space: Reindex`를 한 번 실행한다. 왼쪽에 트리가 안 보이면 `Cmd-O`.
- **관찰 카테고리 경고:** `[fact]`·`[decision]` 같은 카테고리 글자를 누르면 카테고리가 지워진다. 실수하면 바로 `Cmd+Z`. 업스트림 이슈 링크(게시한 경우).
- 비밀번호 교체: main 체크아웃 `.env`의 `SB_USER`를 바꾸고 `make deploy`. `.env`가 바뀌면 compose가 SilverBullet을 다시 만든다.
- 글꼴: 새 VM이거나 글꼴을 바꿀 때 `make sb-fonts`. 복원하면 백업의 글꼴이 돌아온다.
- 무시 목록 변경: `silverbullet/notes.gitignore`를 고치고 `make deploy`(Basic Memory 재생성 포함). 이미 색인된 항목은 남는다.
- Exposure audit에 8443을 더한다.

**VM 반영 순서 (계획 11, 단계마다 사용자 승인)**

1. `make backup`
2. Serve 8443 적용: `make vm-bootstrap HOST=agent-hub` (키 프롬프트는 빈 값으로 Enter, §3)
3. `make deploy`
4. `make sb-fonts`
5. `make verify status` — 메모리·스왑을 ADR 0005에 기록
6. Mac 브라우저에서 완료 조건 3·4 확인

## 10. 테스트와 검증

bats 테스트를 먼저 쓴다(AGENTS.md). 스텁은 `tests/stubs/`, 기록된 응답은 `tests/fixtures/`에 둔다.

- **`tests/repo.bats`:**
  - SilverBullet 이미지가 digest로 고정돼 있다.
  - `silverbullet` 서비스에 `SB_SHELL_BACKEND: "off"`, `SB_RUNTIME_API: "0"`, `${SB_USER:?`가 있다.
  - 두 서비스의 `networks`가 다르다.
  - 모든 `ports`가 `127.0.0.1`이다(기존 테스트가 그대로 적용).
  - `start_period` 테스트(`tests/repo.bats:79-97`)는 Basic Memory 서비스로 범위를 좁힌다. 두 번째 서비스의 healthcheck 때문에 실패하지 않게 하는 것이고, Basic Memory에 대한 검증 내용은 그대로 둔다.
  - 부트스트랩에 8443 Serve 매핑이 있고 Funnel이 없다.
- **`sb-space.sh`:** `.gitignore`는 덮어쓰고, 내용이 같으면 "바뀜"을 알리지 않는다. "바뀜"인 동안에는 페이지를 쓰지 않는다. 관리 페이지는 덮어쓰고 `index.md`는 있으면 건드리지 않는다. `index.md`가 있는지 확인하지 못하면 쓰지 않고 실패한다. VM에서는 컨테이너 UID로 쓴다.
- **`deploy.sh`:** `.gitignore`가 바뀔 때만 Basic Memory를 다시 만들고, 관리 페이지는 그 뒤에 쓴다. VM `.env`에 `SB_USER`가 들어가고, 이미 있던 `.env`도 권한이 600이 된다. 출력에 `SB_USER` 값이 없다. `SB_USER`가 없으면 VM을 건드리지 않는다.
- **`restore.sh`:** `SB_USER`가 없으면 확인 질문 전에 멈춘다. 복원한 VM `.env`는 권한 600이고 `SB_USER`를 담는다. 공간 파일을 정지 뒤·첫 기동 전에 쓰고 표시 파일을 남기지 않으며, 백업에 있던 `index.md`는 그대로 둔다. 공간 파일 쓰기가 실패하면 복원한 데이터로 컨테이너를 올리지 않고 롤백한다.
- **`sb-fonts.sh`:** 글꼴·`fontTools`가 없으면 아무것도 올리지 않고 멈춘다. 변환 결과를 올바른 경로에 올린다.
- **`verify-sb.sh`:** 꺼진 서버, 로그인 없이 열린 서버, 거절된 로그인(HTTP 200 + `status: error`), 쿠키 속성 누락, https에서 `Secure` 누락, 셸 405가 아님을 모두 실패로 본다. `--read-only`는 로그인하지 않고 `SB_USER`도 요구하지 않는다. 비밀번호는 명령 인자에 없고, `SB_USER`와 쿠키 값을 출력하지 않는다. make·compose가 바꿀 문자가 든 `SB_USER`는 서버에 접속하기 전에 거부한다. `SB_ENV_FILE`의 원래 줄과 다른 값(make가 `#`에서 자르거나 `$`를 펼친 값)도 두 값을 출력하지 않고 거부한다.
- **`make local-up`:** make가 main 체크아웃 `.env`의 `SB_USER`를 바꿨으면 compose를 부르기 전에 멈추고, 맞는 값이면 끝까지 진행한다(`tests/main_checkout.bats`).
- **`verify-vm.sh`:** 3000 바인딩, 8443·3000 공인 포트, Serve 포트별 대상과 포트별 Funnel 검사(JSON). `probe`는 로그인하지 않는다.
- **클라우드 중립 (`tests/cloud_neutral.bats`):** 새 스크립트에도 적용된다.
- **E2E (수동):** 로컬은 계획 10에서 완료 조건 1·3·4를, VM은 계획 11에서 완료 조건 2·3·4·6을 확인해 진행 로그에 기록한다.

## 11. 위험과 대응

| 위험 | 대응 |
|---|---|
| 관찰 카테고리 클릭으로 카테고리 손실 | 런북 경고와 `Cmd+Z`, 업스트림 이슈. 반복되면 자동 되돌리기 Space Lua를 다시 판단 |
| 훅이 적용되지 않는 페이지(템플릿으로 만든 페이지)의 frontmatter 경합 | 저널을 끄고 Quick Note는 무시 경로(`Inbox/`)에 둔다. 남는 경우는 줄바꿈 하나 수준 |
| `.gitignore`보다 먼저 색인된 SilverBullet 페이지가 남음 | 배포가 SilverBullet보다 먼저 `.gitignore`만 두고 Basic Memory를 다시 만든 뒤에 관리 페이지와 `index.md`를 쓴다. 복원은 Basic Memory가 멈춘 동안 공간 파일을 모두 쓴 뒤에 기동한다(§7.3) |
| SilverBullet이 배포보다 먼저 `index.md`를 만듦 | 배포 순서로 막는다(§3, 계획 10에서 확인) |
| 이미지 기본 healthcheck(`/.instance`)가 인증 예외 목록 밖이라 버전에 따라 401이 될 수 있음 | 목록에 있는 `/.ping`으로 덮어쓰기(§7.1) |
| 두 번째 비밀값 유출 | `.env`(git 제외)와 VM `.env`(600)에만 둔다. 출력 금지 테스트, `mask`, 비밀번호는 curl 표준입력으로만 |
| `SB_USER`의 `#`·`$`를 make가 주석·변수로 바꿔 다른 비밀번호가 쓰임 | 허용 문자를 정하고 `require_sb_user`가 형식을 검사하며, make가 바꾼 값은 `SB_ENV_FILE`의 원래 줄과 비교해 잡는다(§8.3). `.env.example`에 적는다 |
| `SB_USER`가 없으면 compose 파일을 읽는 모든 명령(`local-down`, `status`, `backup`의 stop·start)이 실패 | 의도한 동작이다(인증 없는 SilverBullet 방지). 오류 메시지가 main 체크아웃 `.env`를 가리키게 하고, 런북과 `.env.example`에 적는다 |
| 로그인 사용자의 `/.proxy`로 메타데이터 접근 | 셸 끄기와 네트워크 분리. 서비스 계정 제거 권장(§8.6) |
| 1GB RAM 부족 | SilverBullet 서버는 수 MiB(§3). 계획 11에서 실측하고 ADR 0005에 기록 |
| 노트가 많아지면 노트 검색이 느려짐 | 검색은 브라우저 색인을 입력마다 훑는다(입력 지연 처리, 2바이트 이상, 최대 100건). 수천 노트에서 느려지면 커뮤니티 검색 라이브러리(Silversearch)를 검토한다(**Assumption**: 수백 노트까지는 충분) |
| 노트 검색의 문단 누락 | 브라우저마다 `Space: Reindex` 한 번(§3). 검색 패널 안내문과 런북에 적는다 |
| 글꼴로 인한 아웃바운드 증가 | 기기당 처음 한 번 약 4.7MB (무료 1GB/월) |
| SilverBullet의 빠른 릴리스 주기 | digest 고정. 올릴 때 릴리스 노트를 읽고 `make check local-up local-verify` |
| 계획 05·08과의 스크립트 충돌 | 계획 11은 두 계획 병합 뒤 시작 |

## 12. 문서 갱신

- **`AGENTS.md`(사용자 승인 필요):**
  - Safety의 "The only secret is the Tailscale auth key"(`AGENTS.md:22`)를 "두 비밀값: Tailscale 인증 키와 `SB_USER`"로 바꾸고 각각의 전달 경로를 적는다.
  - Commands에 `sb-fonts`(VM 변경, 승인 필요)를 더한다.
- **`docs/ARCHITECTURE.md`:** 토폴로지, 구성 요소, 데이터 경로(노트 폴더의 SilverBullet 파일), 신뢰 경계와 비밀값(`:52`), 배포 흐름(`:63`)은 계획 10에서, Serve 대상(`:26`), 공인 IP 점검 포트(`:51`), 검증 흐름(`:64`)은 계획 11에서 고친다.
- **ADR 0005 "웹 UI로 SilverBullet":** 검토한 대안(Mac의 Obsidian + 동기화, Basic Memory 클라우드 웹앱, 직접 만든 UI)과 §3의 스파이크 근거를 담는다.
- **`docs/runbooks/rbk-2026-10-12-operations.md`:** §9 (계획 11).
- **`README.md`:** 웹 UI 한 단락(로컬 사용, 카테고리 경고), 사전 요구사항에 `sb-fonts`용 `python3`·`fonttools`·`brotli`.
- **`.env.example`:** `SB_PORT`, 빈 `SB_USER=`와 주석. 첫 줄 "No secrets belong here"는 유지한다.
- **GCP 설계(`2026-10-12-…:154`):** "유일한 비밀값" 문장 옆에 이 설계를 가리키는 한 줄을 단다. 완료된 계획 문서는 당시 기록이므로 고치지 않는다.
