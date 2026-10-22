---
status: backlog
spec: docs/specs/spec-2026-10-22-web-connector.md
---

# 25 Web Connector Implementation Plan

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** `BM_WEB=on`인 VM에서 claude.ai 커스텀 커넥터가 GitHub 로그인 한 명에게만 Basic Memory 도구 18개를 열고, `BM_WEB`이 없으면 모든 것이 지금과 같다.

**Architecture:**
- `gateway/`의 FastMCP 프록시가 GitHub OAuth, 소유자 확인(숫자 id), 도구 허용 목록, 감사 로그, 저장소 정리를 맡는다. compose 프로필 `web`에서 digest 고정 Python 이미지로 돌고, 의존성은 해시 고정 파일로 첫 기동 때 설치한다.
- `cloudflared`(프로필 `tunnel`)가 나가는 연결로 공개 호스트명을 게이트웨이에 잇는다. 프로필은 `COMPOSE_PROFILES`로 켠다(VM은 `.env`, 로컬은 Make).
- 셸 쪽은 `BM_WEB` 값 검사, `vm_env`, 배포, `verify`, `status`를 늘리고, 새 `scripts/verify-web.sh`가 로컬과 공개 URL의 OAuth 메타데이터를 같은 방식으로 확인한다.

**Spec:** `docs/specs/spec-2026-10-22-web-connector.md` (§3.3 `BM_WEB`, §3.4 게이트웨이, §5 테스트, §7 순서). 결정: `docs/decisions/adr-2026-10-22-0008-web-connector.md`.

**Sequence:** 계획 25. 다음을 모두 만족한 뒤 시작한다.
- 이 계획·스펙·ADR을 담은 docs PR이 병합됐다.
- Task 1~3(코드 PR)은 개선 백로그의 계획 18·22·23, 에이전트 기억 미러의 계획 24와 나란히 진행한다. 나중에 병합하는 쪽이 `git merge origin/main`으로 맞춘다.
- Task 4는 코드 PR이 병합되고, 스펙 §8의 사용자 준비물(도메인, GitHub 계정과 숫자 id)이 있고, 다른 계획이 같은 때 VM을 바꾸지 않을 때 한다(특히 계획 21의 Task 4).

## 배경

- **Verified (2026-10-22, Docker Compose v5.0.2):** VM `.env`의 `COMPOSE_PROFILES`가 프로필을 켜고, 환경변수 `COMPOSE_PROFILES`가 그보다 앞선다. 꺼진 프로필 서비스의 `${VAR:?}`도 compose 명령 전체를 실패시킨다(스펙 §3.3).
- **Verified:** `tests/repo-make.bats:69`는 `local-up`이 `docker compose -f compose.yaml up -d --wait`를 정확히 한 번 부르는지 본다. 그래서 compose 명령 문자열은 바꾸지 않는다.
- **Verified:** 배포는 `compose.yaml`과 `.env`만 올린다(`scripts/deploy-stack.sh:26-33`). 복원은 `vm_env`로 `.env`를 다시 쓰고(`scripts/restore-notes.sh:145`) 프로필 인자 없이 `stop`·`up`을 부른다(`:128`, `:157`).
- **Verified:** `verify-vm.sh`의 공인 IP 검사 포트는 `PUBLIC_PROBE_PORTS`(`:18`)이고, loopback 검사는 `check_loopback_binding PORT`(`:30`)다.
- **Verified (FastMCP 4.1.3 소스):** 시험용 `StaticTokenVerifier(tokens={토큰: {"client_id", "scopes", "sub"}})`는 `sub`를 `claims`에 담는다(`fastmcp/server/auth/providers/jwt.py:684-748`). GitHub 콜백 기본 경로는 `/auth/callback`이다(`oauth_proxy/proxy.py:498-499`). 나머지 API 위치는 스펙 §2에 있다.
- **Verified (2026-10-22, VM `tools/list`):** 허용 목록 18개는 `basic_memory_diagnostics`, `build_context`, `edit_note`, `fetch`, `list_directory`, `list_memory_projects`, `list_workspaces`, `move_note`, `read_content`, `read_note`, `recent_activity`, `schema_diff`, `schema_infer`, `schema_validate`, `search`, `search_notes`, `view_note`, `write_note`다. 막는 셋은 `delete_note`, `create_memory_project`, `delete_project`다.

## Global Constraints

- 스크립트 규칙(`AGENTS.md` Invariants): `#!/usr/bin/env bash` 다음 줄 `set -euo pipefail`, `scripts/lib/` 라이브러리 source, 고칠 방법을 담은 `die`, macOS bash 3.2, `x="$(fn)"` 뒤 `|| exit 1`, 이름 붙인 상수. 새 스크립트는 `make new-script`로 짝 테스트와 함께 만든다(`script-authoring` 스킬).
- 테스트를 먼저 쓴다. 범위는 `docs/decisions/adr-2026-10-13-0004-test-scope.md`를 따른다. 기존 bats 테스트는 고치지 않는다(스펙 완료 조건 2).
- 이미지: `python:<3.12.x>-slim@sha256:<digest>`, `cloudflare/cloudflared:<버전>@sha256:<digest>`. 둘 다 `tests/repo-config.bats:10`의 형식이고, 릴리스 노트를 읽고 고른다.
- 게이트웨이 값(스펙 §3.4): 허용 목록은 위 18개 그대로, 소유자는 `sub == BM_WEB_GITHUB_USER_ID`(숫자만), `forward_incoming_headers=False`, `allowed_client_redirect_uris=["https://claude.ai/api/mcp/auth_callback"]`, 동의 화면 기본값(켜짐), `cache_ttl_seconds=300`.
- `cloudflared`는 `tunnel run`과 환경변수 토큰만 쓴다. `--url`과 `trycloudflare`는 어디에도 없다.
- 웹 서비스의 compose 변수는 `${VAR:-}`만 쓴다. 비밀값 셋(`BM_WEB_GITHUB_CLIENT_SECRET`, `BM_WEB_JWT_KEY`, `BM_WEB_TUNNEL_TOKEN`)은 출력·명령 인자·저장소에 두지 않는다.
- 스크립트는 `BM_WEB_HOST`와 그 호스트명이 풀리는 IP를 출력하지 않는다. Progress log와 PR에는 `mcp.<domain>` 자리표시자만 쓴다.
- `BM_WEB`이 없거나 `off`면 Make 타깃의 동작과 출력이 지금과 같다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 25`, `Task: <N|review|none>`.

## Review Focus

1. Basic Memory가 재시작하거나 죽어 있어도 게이트웨이의 OAuth 메타데이터는 10초 안에 답한다(claude.ai의 디스커버리 제한). Task 1의 `test_metadata_answers_while_backend_is_down`이 고정한다.
2. `sub`가 없거나, 숫자가 아니거나, 소유자의 사용자 이름(`login`)과 같은 토큰은 도구 0개로 거절되고 예외로 끝나지 않는다. Task 1의 `test_token_without_numeric_owner_sub_is_rejected`가 고정한다.
3. Basic Memory를 올려 백엔드에 새 도구가 생겨도 목록과 호출 어디에도 나오지 않는다. Task 1의 가짜 백엔드가 `new_tool`을 내고 테스트가 확인한다.
4. 감사 로그 한 줄에 노트 본문(`write_note`·`edit_note`의 `content`)이 들어가지 않는다. Task 1의 `test_audit_line_names_tool_and_note_without_content`가 고정한다.
5. `BM_WEB=on`인데 비밀값이 비었거나 `.env`에서 깨질 문자(공백, `#`, `$`)를 담으면, 배포와 복원은 ssh 전에 변수 이름만 대고 멈추며 값을 출력하지 않는다. Task 2의 `lib-vm.bats`·`deploy-stack.bats`·`restore-notes.bats` 테스트가 고정한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `gateway/requirements.in`, `gateway/requirements.txt` | `fastmcp==4.1.3` 하나와 그 해시 고정 결과 | 1 |
| `gateway/boot.py` | root로 의존성 설치(해시가 바뀐 때만), 데이터 디렉터리 소유자 설정, uid 1000으로 내려 `gateway.py` 실행 | 1 |
| `gateway/gateway.py` | 설정 읽기, 프록시 조립, 소유자 확인, 허용 목록, 감사 로그, 저장소와 `cull()` | 1 |
| `gateway/test_gateway.py` | 동작 테스트(`unittest`, 게이트웨이 컨테이너 안에서 실행) | 1 |
| `compose.yaml` | `gateway`·`cloudflared` 서비스, `web` 네트워크, `gateway-deps` 볼륨 | 1 |
| `tests/repo-config.bats` | 웹 서비스 구조 테스트 | 1 |
| `scripts/verify-web.sh`, `tests/verify-web.bats`, `tests/stubs/dig`, `tests/fixtures/verify-web/` | OAuth 메타데이터 네 가지와 공개 IPv4 확인 | 1 |
| `Makefile` | 웹 변수 export, `local-*`의 `COMPOSE_PROFILES`, `local-verify` 추가 줄, `gateway-lock` | 1 |
| `scripts/lib/common.sh` | `DEFAULT_BM_WEB_PORT=8738` | 1 |
| `scripts/lib/vm.sh`, `tests/lib-vm.bats` | `web_mode`, `require_web_settings`, `vm_env`의 웹 줄 | 2 |
| `scripts/deploy-stack.sh`, `scripts/restore-notes.sh` 및 각 bats | 웹 설정 확인, `gateway/` 업로드, 꺼질 때 웹 컨테이너 삭제 | 2 |
| `scripts/verify-vm.sh`, `scripts/show-status.sh` 및 각 bats | 공개 URL 확인, loopback·공인 포트, 저장소 크기 | 2 |
| `.env.example` | 웹 변수와 설명 | 2 |
| `AGENTS.md`, `docs/ARCHITECTURE.md`, `README.md`, 운영 런북, 새 웹 커넥터 런북, `.agents/skills/bm-upgrade/SKILL.md`, ADR 0008 | 규칙과 문서 | 3 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/25-web-connector` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Task 1: Gateway, compose services and local verification

**Files:**
- Create: `gateway/requirements.in`, `gateway/requirements.txt`, `gateway/boot.py`, `gateway/gateway.py`, `gateway/test_gateway.py`, `scripts/verify-web.sh`, `tests/verify-web.bats`, `tests/stubs/dig`, `tests/fixtures/verify-web/`
- Modify: `compose.yaml`, `Makefile:12-21`(변수), `:56-73`(`local-*`), `scripts/lib/common.sh`(기본 포트), `scripts/lib/vm.sh`(`web_mode`와 함수 목록 주석)
- Test: `tests/repo-config.bats`, `tests/verify-web.bats`, `tests/repo-make.bats`(새 테스트만), `tests/lib-vm.bats`(`web_mode`), `gateway/test_gateway.py`

**Interfaces:**
- Produces (compose): 서비스 `gateway`(프로필 `web`, 네트워크 `[basic-memory, web]`, 게시 `127.0.0.1:${BM_WEB_PORT:-8738}:8080`, 마운트 `./gateway:/app:ro`·`${BM_WEB_DATA_DIR:-./.local-data/gateway}:/data`·`gateway-deps:/deps`), 서비스 `cloudflared`(프로필 `tunnel`, 네트워크 `[web]`, 게시 없음, `TUNNEL_TOKEN: ${BM_WEB_TUNNEL_TOKEN:-}`).
- Produces (게이트웨이 환경변수): `BM_WEB_BASE_URL`, `BM_WEB_GITHUB_USER_ID`, `BM_WEB_GITHUB_CLIENT_ID`, `BM_WEB_GITHUB_CLIENT_SECRET`, `BM_WEB_JWT_KEY`. 백엔드는 고정값 `http://basic-memory:8000/mcp`, `FASTMCP_HOME=/data`, `PYTHONPATH=/deps/site`.
- Produces (`gateway/gateway.py`): `ALLOWED_TOOLS: frozenset[str]`, `CLAUDE_CALLBACK`, `GITHUB_CACHE_TTL_SECONDS = 300`, `CULL_INTERVAL_SECONDS`, `AUDIT_ARG_KEYS`, `Settings.from_env(env: Mapping[str, str]) -> Settings`(값이 없거나 형식이 틀리면 변수 이름만 담은 `SystemExit`), `is_owner(token: AccessToken | None, owner_id: str) -> bool`, `make_storage(data_dir: Path, jwt_key: str) -> tuple[AsyncKeyValue, FileTreeStore]`, `async cull_forever(store: FileTreeStore, interval_seconds: int) -> None`, `AuditMiddleware`, `build_gateway(settings: Settings, auth: AuthProvider) -> FastMCP`, `main() -> None`.
- Produces (`scripts/verify-web.sh`): `verify-web.sh [--public] BASE_URL`. 종료 코드 0이면 네 검사가 모두 통과했다. `--public`은 호스트명이 공개 IPv4로만 풀리는지도 보고, 호스트명과 IP는 출력하지 않는다.
- Produces (Make): `local-up`·`local-down`·`local-logs`·`local-verify`가 `BM_WEB=on`일 때 `COMPOSE_PROFILES=web`과 `BM_WEB_BASE_URL=http://127.0.0.1:$(BM_WEB_PORT)`를 받는다. 새 타깃 `gateway-lock`.
- Produces (`scripts/lib/vm.sh`): `web_mode -> on|off`. 비었으면 `off`이고, 다른 값이면 `die "BM_WEB must be on or off (got '…')"`. `access_mode`와 같은 모양이다.

- [ ] **Step 1: 실패하는 구조 테스트 작성.** `tests/repo-config.bats`에 다음을 더한다. 18개 이름은 테스트 파일에 상수 `WEB_ALLOWED_TOOLS`로 따로 적는다.
  - "cloudflared runs a pinned cloudflared image as a remotely managed tunnel in the tunnel profile, publishes no port and joins only the web network": `image: cloudflare/cloudflared:`, 명령에 `tunnel`과 `run`, `--url` 없음, `TUNNEL_TOKEN: ${BM_WEB_TUNNEL_TOKEN:-}`, `ports:` 없음, `networks: [web]`, `profiles: [tunnel]`, `restart: unless-stopped`, 헬스체크.
  - "gateway runs the pinned python slim image in the web profile, joins basic-memory and web and mounts its code read-only": `image: python:…-slim@`, `profiles: [web]`, `networks: [basic-memory, web]`, `./gateway:/app:ro`, `restart: unless-stopped`, 헬스체크 명령에 `oauth-authorization-server`.
  - "web services never use a required-variable default": 두 서비스 블록에 `${` 다음 `:?`가 없다.
  - "nothing starts a quick tunnel": `compose.yaml`, `Makefile`, `scripts/`에 `trycloudflare`가 없다.
  - "gateway requirements pin every package with a hash": `gateway/requirements.txt`의 모든 요구 줄이 `==`로 고정되고 바로 뒤에 `--hash=sha256:` 줄이 하나 이상 있다.
  - "gateway.py strips client headers, opens only the allowed tools, checks the owner by numeric id and culls its store": `forward_incoming_headers=False`, `only=True`, `"sub"`, `cull(`가 있고, `ALLOWED_TOOLS = frozenset(`부터 `)`까지의 따옴표 이름 집합이 `WEB_ALLOWED_TOOLS`와 같다.
- [ ] **Step 2: 실패하는 스크립트 테스트 작성.** `make new-script NAME=verify-web`으로 `scripts/verify-web.sh`와 `tests/verify-web.bats`를 만든다. curl 스텁 응답은 `tests/fixtures/verify-web/`, `dig` 스텁은 `tests/stubs/dig`에 둔다. 테스트:
  - "passes when the gateway answers 401 with resource_metadata, serves both metadata documents and refuses a foreign redirect URI": 각 검사의 `OK:` 줄을 확인한다.
  - 실패 경우 표(`@test` 하나에 case 반복): 토큰 없는 `POST /mcp`가 200, `WWW-Authenticate`에 `resource_metadata` 없음, 보호 리소스 메타데이터의 `resource`가 `BASE_URL/mcp`가 아님, `code_challenge_methods_supported`에 `S256` 없음, `client_id_metadata_document_supported`가 true가 아님, `token_endpoint_auth_methods_supported`에 `none` 없음, `/register`가 2xx. 모두 실패해야 한다.
  - "--public fails when the host resolves to a private, CGNAT or loopback address and never prints the host or the addresses": `dig` 스텁이 `10.0.0.5`, `100.64.1.2`, `127.0.0.1`을 돌려줄 때 실패한다. 공개 주소일 때는 통과한다. 두 경우 모두 출력에 호스트명과 주소가 없다.
- [ ] **Step 3: 실패하는 Make·라이브러리 테스트 작성.** `tests/lib-vm.bats`에 `web_mode`가 빈 값·`on`·`off`를 받고 `On`·`yes`를 거절하는 테스트를 더한다. `tests/repo-make.bats`에 새 테스트 하나를 더한다. "make local-up with BM_WEB=on hands COMPOSE_PROFILES=web to compose and runs the same compose command": docker 스텁이 받은 환경을 기록하게 하고, `COMPOSE_PROFILES=web`과 `docker compose -f compose.yaml up -d --wait` 줄을 확인한다. `BM_WEB=yes`면 compose 호출 전에 `BM_WEB must be on or off`로 실패한다. 기존 `:55` 테스트는 그대로 통과해야 한다.
- [ ] **Step 4: 실패 확인.** Run: `make test`. Expected: 새 테스트만 실패한다(서비스·파일·스크립트·Make 처리 없음).
- [ ] **Step 5: 게이트웨이 동작 테스트 작성(`gateway/test_gateway.py`, `unittest.IsolatedAsyncioTestCase`).** 가짜 백엔드는 21개 도구와 `new_tool`을 가진 FastMCP 서버다. 받은 요청 헤더와 호출된 도구 이름을 기록하며, 같은 프로세스의 uvicorn 스레드에서 빈 포트로 띄운다. 인증은 `StaticTokenVerifier`로 `owner`(sub `"4242"`), `other`(sub `"5151"`), `no-sub`, `login-sub`(sub `"octocat"`) 토큰을 만든다. 게이트웨이는 `build_gateway(settings, auth=verifier)`로 조립한다.
  - `test_owner_lists_exactly_the_allowed_tools`: 목록 이름 집합이 `ALLOWED_TOOLS`와 같다(18개).
  - `test_blocked_and_unknown_tools_are_hidden_and_refused_for_the_owner`: `delete_note`, `create_memory_project`, `delete_project`, `new_tool`이 목록에 없고, 직접 호출하면 오류이며, 백엔드는 그 호출을 받지 않는다.
  - `test_other_user_sees_no_tools_and_cannot_call`: 목록이 비고 `read_note` 호출이 거절된다.
  - `test_token_without_numeric_owner_sub_is_rejected`: `no-sub`, `login-sub` 모두 목록이 비고 호출이 거절된다. 예외가 테스트 밖으로 나오지 않는다.
  - `test_backend_never_receives_authorization`: 소유자 호출 뒤 백엔드가 기록한 헤더에 `authorization`이 없다.
  - `test_metadata_answers_while_backend_is_down`: 백엔드 URL을 닫힌 포트로 두고 `/.well-known/oauth-authorization-server`가 10초 안에 200을 준다.
  - `test_audit_line_names_tool_and_note_without_content`: `write_note(title="T", directory="d", content="BODY-7f3a")` 뒤 감사 줄에 `write_note`, `T`, `d`, 소유자 id가 있고 `BODY-7f3a`는 없다.
  - `test_settings_name_the_missing_or_malformed_variable_only`: `BM_WEB_GITHUB_USER_ID="octo"`나 빈 `BM_WEB_JWT_KEY`면 `SystemExit` 메시지에 변수 이름이 있고, 다른 비밀값 문자열은 없다.
  - `test_cull_removes_expired_records`: `make_storage`의 저장소에 TTL 1초 기록을 쓰고 만료 뒤 `cull()`을 부르면 파일이 사라지고, TTL 없는 기록은 남는다.
- [ ] **Step 6: 의존성 고정.** `gateway/requirements.in`에 `fastmcp==4.1.3` 한 줄을 쓴다. `Makefile`에 `gateway-lock` 타깃을 더한다. 이 타깃은 `compose.yaml`의 `gateway` 이미지 줄을 읽어(이미지 이름을 한 곳에만 둔다) 그 이미지에서 고정 버전의 `pip-tools`로 `pip-compile --generate-hashes --allow-unsafe`를 돌리고, `gateway/requirements.txt`를 쓴다. `make gateway-lock`을 실행하고 결과 파일을 커밋에 넣는다.
- [ ] **Step 7: 최소 구현.**
  - `compose.yaml`: Interfaces의 두 서비스, `networks: web:`, `volumes: gateway-deps:`. 두 서비스 모두 `logging: *bounded-logging`. `gateway`는 `command: ["python", "/app/boot.py"]`, `working_dir: /app`, `depends_on: basic-memory: condition: service_healthy`, 헬스체크는 `python -c` urllib로 `http://127.0.0.1:8080/.well-known/oauth-authorization-server`를 부른다. `start_period`는 첫 `pip install`을 감안해 구현자가 정한다. `cloudflared`는 `depends_on: gateway: condition: service_healthy`이고, 헬스체크는 이미지가 지원하는 방식(예: `--metrics`와 `/ready`)을 릴리스 문서에서 확인해 고른다.
  - `gateway/boot.py`: `requirements.txt`의 sha256이 `/deps/requirements.sha256`과 다를 때만 `pip install --require-hashes --no-deps --target <새 디렉터리>`로 설치한다. 설치가 끝나면 `/deps/site`로 바꿔 넣고 sha256을 기록한다. 이어서 `/data`의 소유자를 1000으로 맞추고, `setgroups([])`, `setgid(1000)`, `setuid(1000)` 뒤 `os.execv`로 `gateway.py`를 실행한다.
  - `gateway/gateway.py`: Interfaces의 이름으로 시제품 구성(스펙 §3.4)을 옮긴다. `make_storage`는 FastMCP 기본값과 같은 키 파생·경로·Fernet 래퍼를 만든다(`oauth_proxy/proxy.py:597-621`). 그 저장소를 `GitHubProvider(client_storage=...)`에 넘기고, 시작할 때와 `CULL_INTERVAL_SECONDS`마다 `cull()`을 부른다. `AuditMiddleware`는 `on_call_tool`에서 한 줄 JSON(`time`, `user`, `tool`, `note`, `ms`)을 표준 출력에 쓴다. `note`는 인자 중 `AUDIT_ARG_KEYS`(`identifier`, `title`, `directory`, `path`, `url`, `id`, `destination_path`, `destination_folder`, `dir_name`, `project`)만 담는다.
  - `scripts/lib/common.sh`: `DEFAULT_BM_WEB_PORT=8738`.
  - `Makefile`:
    - `BM_WEB_PORT := $(or $(BM_WEB_PORT),8738)`. `BM_WEB`, `BM_WEB_HOST`, `BM_WEB_PORT`, `BM_WEB_GITHUB_USER_ID`, `BM_WEB_GITHUB_CLIENT_ID`를 전역 export에 더한다.
    - 비밀값 셋은 `SB_USER`처럼 `local-*`·`deploy`·`restore`에만 target-specific으로 export한다.
    - `BM_WEB=on`일 때만 `local-*`에 `COMPOSE_PROFILES=web`과 `BM_WEB_BASE_URL`을 넘긴다. `local-up`은 첫 줄에서 `web_mode`로 값을 검사하고, `.local-data/gateway`를 만든다.
    - `local-verify`는 `BM_WEB=on`일 때 두 줄을 더 실행한다. `scripts/verify-web.sh "http://127.0.0.1:$(BM_WEB_PORT)"`와 `$(COMPOSE) exec -T gateway python -m unittest -v test_gateway`다.
  - `scripts/lib/vm.sh`: Interfaces의 `web_mode`.
  - `scripts/verify-web.sh`: `verify-mcp.sh`의 구조와 상수 이름을 따른다. 등록 검사는 `redirect_uris: ["https://example.invalid/callback"]`를 보내고 `400`과 `invalid_redirect_uri`를 기대한다. 그래서 아무것도 저장되지 않는다.
- [ ] **Step 8: 통과 확인.**
  - Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
  - Run: `.env`에 `BM_WEB=on`과 가짜 GitHub 값(`BM_WEB_GITHUB_USER_ID=4242`, client id·secret 아무 값, `BM_WEB_JWT_KEY=$(openssl rand -hex 32)`)을 넣고 `make local-up local-verify local-down`. 사용자가 main checkout `.env`에 직접 넣는다. Expected: `verify-web.sh`의 `OK:` 넷, `unittest`의 `OK`, 기존 MCP·SilverBullet 검사 통과. 결과를 Progress log에 `Verified`로 적는다.
  - Run: `BM_WEB` 줄을 지우고 `make local-up local-verify local-down`. Expected: 출력과 컨테이너가 계획 25 전과 같다(`gateway` 없음).
  - `docker stats --no-stream`의 게이트웨이 메모리를 Progress log에 적는다.
- [ ] **Step 9: 커밋.** `git commit -m "feat: add the OAuth gateway and tunnel services for the claude.ai web connector" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 25" --trailer "Task: 1"`

### Task 2: BM_WEB on the VM: settings, deploy, restore, verify and status

**Files:**
- Modify: `scripts/lib/vm.sh`(함수 목록 주석, `require_vm`, `vm_env`), `scripts/deploy-stack.sh`, `scripts/restore-notes.sh`, `scripts/verify-vm.sh`, `scripts/show-status.sh`, `.env.example`
- Test: `tests/lib-vm.bats`, `tests/deploy-stack.bats`, `tests/restore-notes.bats`, `tests/verify-vm.bats`, `tests/show-status.bats`

**Interfaces:**
- Consumes: Task 1의 compose 서비스, `scripts/verify-web.sh [--public] BASE_URL`, `DEFAULT_BM_WEB_PORT`, `web_mode`.
- Produces (`scripts/lib/vm.sh`):
  - `require_vm`이 `access_mode` 다음에 `web_mode`를 부른다.
  - `require_web_settings`. `on`일 때 `BM_WEB_HOST`(scheme 없는 호스트명), `BM_WEB_GITHUB_USER_ID`(숫자), `BM_WEB_GITHUB_CLIENT_ID`, 비밀값 셋(빈 값 금지, `[A-Za-z0-9._~+/=-]`만)을 검사하고, 틀리면 변수 이름만 대고 죽는다.
  - `vm_env`. `on`이면 기존 줄 뒤에 `COMPOSE_PROFILES=web,tunnel`, `BM_WEB_PORT`, `BM_WEB_DATA_DIR=$BM_REMOTE_DATA_ROOT/gateway`, `BM_WEB_BASE_URL=https://$BM_WEB_HOST`, 사용자 id, client id, 비밀값 셋을 쓴다. `off`면 지금과 한 글자도 다르지 않다.
- Produces (상수): `deploy-stack.sh`의 `GATEWAY_RUNTIME_FILES="boot.py gateway.py requirements.txt"`, `WEB_SERVICES="gateway cloudflared"`.

- [ ] **Step 0: compose 동작 확인.** 로컬에서 `COMPOSE_PROFILES` 없이 `docker compose -f compose.yaml rm --stop --force gateway cloudflared`가 프로필 서비스 컨테이너를 지우는지 본다(Task 1의 `local-up`으로 `gateway`를 띄운 뒤). 결과를 Progress log에 `Verified`로 적는다. 지우지 못하면 `COMPOSE_PROFILES=web,tunnel`을 그 명령에만 붙이는 방식으로 바꾸고, 그것도 적는다.
- [ ] **Step 1: 실패하는 테스트 작성.**
  - `lib-vm.bats`:
    - `require_vm`은 `BM_WEB=yes`일 때 ssh 스텁을 부르기 전에 실패한다.
    - `require_web_settings`의 실패 표: 호스트에 `https://`가 붙은 경우, 숫자가 아닌 사용자 id, 빈 비밀값, `#`·`$`·공백이 든 비밀값. 출력에 값이 없다.
    - `vm_env`: `off`면 기존 다섯 줄만 나오고, `on`이면 위 줄이 나온다.
  - `deploy-stack.bats`:
    - "with BM_WEB=on uploads the gateway runtime files and writes the web settings into the VM .env without printing a secret": ssh 스텁 로그에 `gateway/boot.py` 등 세 파일의 업로드와 `COMPOSE_PROFILES=web,tunnel`이 있고, 출력에 비밀값 세 개가 없다.
    - "with BM_WEB=on and a missing secret stops before ssh": 변수 이름만 출력한다.
    - "with BM_WEB=off removes leftover web containers after the stack is up": `rm --stop --force gateway cloudflared` 호출이 `up` 뒤에 있다.
  - `restore-notes.bats`: "with BM_WEB=on and a malformed secret stops before ssh".
  - `verify-vm.bats`: `BM_WEB=on`이면 `verify-web.sh --public "https://<host>"`를 `verify`와 `probe` 모두에서 부르고, `BM_WEB_PORT`의 loopback 검사와 공인 IP 검사를 한다. `off`면 셋 다 하지 않는다.
  - `show-status.bats`: `BM_WEB=on`이면 `gateway store: <N> KiB, <M> client registrations` 줄이 나온다. 원격 명령은 `du -sk`와, `mcp-oauth-proxy-clients`가 들어간 경로의 파일 수다. `off`면 그 줄이 없다.
- [ ] **Step 2: 실패 확인.** Run: `make test`. Expected: 새 테스트만 실패하고 기존 테스트는 통과한다.
- [ ] **Step 3: 최소 구현.**
  - `deploy-stack.sh`: `require_sb_user` 다음에 `require_web_settings`를 부른다. `compose.yaml`을 올린 뒤 `on`이면 `$BM_REMOTE_APP_DIR/gateway`를 만들고 `GATEWAY_RUNTIME_FILES`를 같은 방식(`remote "cat > …" <파일`)으로 올린다. `up` 뒤 `off`면 `remote_compose "rm --stop --force $WEB_SERVICES"`(Step 0 결과대로)를 부른다.
  - `restore-notes.sh`: `require_sb_user` 다음에 `require_web_settings`를 부른다. 나머지는 `vm_env`가 맡는다.
  - `verify-vm.sh`: `on`이면 `PUBLIC_PROBE_PORTS`에 `BM_WEB_PORT`를 더하고, `check_loopback_binding "$BM_WEB_PORT"`와 `verify-web.sh --public`을 부른다.
  - `show-status.sh`: `on`이면 `gateway_store_summary -> "<KiB> <registrations>"`를 한 번의 `remote`로 읽어 한 줄로 알린다. 컨테이너 목록은 VM `.env`의 프로필로 기존 `ps`에 함께 나온다.
  - `.env.example`: 스펙 §3.3의 표 순서로 변수와 한 줄 설명을 쓴다. 비밀값은 빈 값으로 두고 만드는 명령을 주석으로 단다.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0, 커버리지 80% 이상.
- [ ] **Step 5: 커밋.** `git commit -m "feat: deploy, verify and report the web connector behind BM_WEB" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 25" --trailer "Task: 2"`

### Task 3: Rules and documents

**Files:**
- Modify: `AGENTS.md:13`, `:22`, `docs/ARCHITECTURE.md`(스펙 §3.6의 네 곳), `README.md`, `docs/runbooks/rbk-2026-10-12-operations.md`(Exposure audit), `.agents/skills/bm-upgrade/SKILL.md`, `docs/decisions/adr-2026-10-22-0008-web-connector.md`(front matter)
- Create: 새 런북(`make new-doc TYPE=runbook SLUG=web-connector`)

**Interfaces:**
- Consumes: Task 1~2의 Make 타깃, 변수, 출력 문구(런북이 그대로 인용한다).

- [ ] **Step 1: 규칙.** `AGENTS.md:13`의 첫 문장을 스펙 §3.6의 영어 문장으로 바꾸고, `:22`에 비밀값 세 개를 더한다. `make check`의 `AGENTS.md` 크기 테스트(`tests/repo-config.bats:135`)가 통과해야 한다.
- [ ] **Step 2: 런북.** `doc-authoring` 스킬로 만든다. 다음 절을 쓴다.
  - 준비: 도메인을 Cloudflare DNS로, remotely-managed tunnel과 공개 호스트명(`http://gateway:8080`), GitHub OAuth App(callback `https://<BM_WEB_HOST>/auth/callback`), 숫자 id 조회.
  - `.env` 값: 사용자가 main checkout `.env`에 직접 쓴다.
  - 켜기: `make backup`, `make deploy`, `make verify`.
  - Cloudflare rate limit 규칙(`/register`, `/authorize`, `/consent`), Bot Fight Mode 확인, `160.79.104.0/21` 예외.
  - claude.ai 커넥터 등록과 도구별 권한("Always allow" 금지).
  - 비밀값 교체, 게이트웨이 저장소 비우기(스펙 §3.4), 차단 세 겹, 끄기(`BM_WEB=off` 배포).
- [ ] **Step 3: 나머지 문서.**
  - 운영 런북 Exposure audit: 공개 호스트명 하나, OAuth App 콜백, 커넥터 목록, 저장소 크기·등록 수를 더한다.
  - `bm-upgrade` 스킬(`skill-authoring` 스킬로 편집): 업그레이드 뒤 `tools/list`와 `ALLOWED_TOOLS`를 비교하고, `BM_WEB=on`이면 `make verify`의 웹 검사를 확인한다.
  - ARCHITECTURE·README: 스펙 §3.6.
  - ADR 0008: `status: accepted`, `date`를 그날로.
- [ ] **Step 4: 통과 확인.** Run: `make check`. Expected: exit 0. 문서 링크·경로 테스트(`tests/repo-docs.bats:100`) 통과.
- [ ] **Step 5: 커밋.** `git commit -m "docs: document the web connector and redefine the public ingress invariant" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 25" --trailer "Task: 3"`

### Code PR: review and merge

- [ ] PR 본문 Verification에 Task 1~3의 `make check`, `make local-up local-verify` 결과(`BM_WEB` 켬과 끔)와 CI(`check`, `pr-rules`)를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge). `AGENTS.md` Invariants와 `compose.yaml`을 바꾸므로 전체 깊이로 리뷰한다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.

### Task 4: VM rollout and claude.ai check (with the user, OK at every step)

**Files:**
- Modify: 이 계획(Progress log, `status`), `docs/decisions/adr-2026-10-22-0008-web-connector.md`(이전 결과 절)

- [ ] **Step 1: 준비 확인.** 런북의 준비 절을 사용자가 마쳤는지, main checkout `.env`에 웹 값이 있는지 확인한다. 값을 대화로 받지 않는다. `make status`로 현재 메모리·스왑을 적는다.
- [ ] **Step 2: 백업.** `make backup`. 결과 파일 이름을 Progress log에 적는다.
- [ ] **Step 3: 배포(OK).** `BM_WEB=on`으로 `make deploy`. Expected: 네 컨테이너 healthy.
- [ ] **Step 4: 확인.** `make verify`. Expected: 기존 검사와 웹 검사 통과. `gcloud compute firewall-rules list --configuration=bm-personal`로 VPC 밖 허용 규칙이 `allow-iap-ssh` 하나뿐인지 확인한다.
- [ ] **Step 5: Cloudflare 설정(사용자).** rate limit 규칙을 만들고, 한 규칙으로 세 경로를 묶을 수 있는지 Progress log에 적는다(스펙 §3.4의 Assumption).
- [ ] **Step 6: claude.ai 확인(사용자와 함께).**
  - 커넥터를 등록하고 소유자 GitHub 계정으로 연결한다.
  - 도구 목록에 막은 셋이 없음을 확인한다.
  - 테스트 노트를 쓰고 읽고 고친다.
  - `make tunnel`을 거친 Claude Code로 그 노트를 지운다.
  - `make logs`의 감사 줄에 세 호출이 있는지 본다.
- [ ] **Step 7: 24시간 관찰.** 다음 날 `make status`(메모리, 스왑, 저장소 크기)와 `make logs`의 감사 줄 `ms` 중앙값을 적는다. OOM이 있었거나 스왑이 가득 찼으면 `BM_WEB=off`로 배포하고(OK) 스펙 §6대로 사용자와 다시 정한다. 읽기 중앙값이 500 ms를 넘으면 Follow-ups에 적는다.
- [ ] **Step 8: 결과 PR.** ADR 0008에 "이전 결과" 절을 더하고, 이 계획의 `status`를 `completed`로 바꿔 `work/web-connector-rollout` 브랜치에서 커밋·push하고 PR을 연다(`Task: 4`). 호스트명과 IP는 쓰지 않는다.

## Follow-ups

- ChatGPT 연결은 별도 스펙으로 다룬다(스펙 §1 범위 밖).
- 읽기 지연 중앙값이 500 ms를 넘으면, 백엔드 연결을 재사용하는 클라이언트로 바꾸는 work 브랜치를 만든다(스펙 §3.4).
- 개선 백로그의 계획 19 Task 4와 계획 20은 이 계획이 바꾼 `AGENTS.md:13`과 신뢰 경계를 기준으로 쓴다(그 계획들의 몫).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
