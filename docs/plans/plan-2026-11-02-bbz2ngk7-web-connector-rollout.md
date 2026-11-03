---
status: backlog
id: bbz2ngk7
spec: docs/specs/spec-2026-10-22-tn23wwmd-web-connector.md
---

# bbz2ngk7 Web Connector Rollout Implementation Plan

> [web-connector 계획](plan-2026-10-22-d3dpb00s-web-connector.md)의 Task 4(VM 배포와 claude.ai 확인)를 옮긴 계획이다. 2026-11-02 저장소 재검토 4장의 판단을 사용자가 승인했다. 시작 조건은 사용자의 도메인 구매 결정이다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 웹 커넥터의 이미지와 의존성을 다시 고정한 뒤 VM에 `BM_WEB=on`으로 배포하고, claude.ai 커넥터가 GitHub 계정 한 명에게만 Basic Memory 도구 18개를 여는 것을 확인한다.

**Architecture:**
- Task 1은 코드 PR이다. 2026-10-26에 고정한 Python 이미지, `cloudflared`, `fastmcp`, `pip-tools`를 그날의 stable로 다시 고정하고, web-connector 계획의 로컬 확인을 그대로 다시 통과시킨다.
- Task 2는 코드 PR이 병합된 뒤 VM에서 한다. web-connector 계획 Task 4의 Step을 그대로 옮겼고, 결과는 별도 결과 PR로 남긴다.

**Spec:** `docs/specs/spec-2026-10-22-tn23wwmd-web-connector.md` (§3.3 `BM_WEB`, §3.4 게이트웨이, §6 위험, §8 Open questions). 결정: `docs/decisions/adr-2026-10-22-fcvznmdc-web-connector.md`. 절차: `docs/runbooks/rbk-2026-10-27-x9h4zzdh-web-connector.md`.

**Sequence:** 다음을 모두 만족한 뒤 시작한다.
- 사용자가 공개 호스트명에 쓸 도메인을 사기로 정했다(스펙 §8 Open question 1). 사지 않기로 정하면 이 계획을 `dropped`로 닫고, 꺼진 게이트웨이 코드(`gateway/`, compose 프로필 `web`·`tunnel`)를 남길지 따로 정한다.
- GitHub OAuth App을 만들 계정과 통과시킬 계정의 숫자 id가 정해졌다(스펙 §8 Open question 2).
- Task 2는 Task 1의 코드 PR이 병합되고, 런북의 준비 절을 사용자가 마치고, 감독 세션이 VM 작업 창을 줄 때 한다. VM을 바꾸는 작업은 한 번에 하나만 한다.

## 배경

- **Verified:** web-connector 계획의 Task 1~3은 PR #24로 병합됐다(`01eb909`, 2026-10-27). `BM_WEB`이 비었거나 `off`면 웹 서비스는 뜨지 않고 Make 타깃 동작도 그대로다(스펙 §3.3).
- **Reported (2026-10-27, Task 4 작업 기록):** Task 4는 Step 1에서 멈췄다. main checkout `.env`에 웹 값이 없었고, 사용자는 도메인을 사는 것을 고려하지 않았다. VM은 바꾸지 않았다.
- **Verified (2026-11-02, `compose.yaml`, `gateway/requirements.in`, `Makefile`):** 지금 고정값은 `python:3.12.15-slim`, `cloudflare/cloudflared:2026.10.3`, `fastmcp==4.1.3`, `PIP_TOOLS_VERSION := 7.6.2`다. 고른 이유는 web-connector 계획 Progress log 2026-10-26 행에 있다.
- **Reported (스펙 §8):** `.com` 도메인은 연 약 $10~11이다. 제3자 가격이라 시작할 때 다시 확인한다.
- **Reported (2026-10-27, 같은 기록):** 옛 Task 4용 worktree(`work/web-connector-rollout`, `01eb909` 기준, 커밋과 push 없음)가 main checkout에 잠긴 채 남아 있다. 이 계획은 그 worktree를 쓰지 않는다. 지울지는 사용자가 정한다.

## Global Constraints

- 이미지는 `<이름>:<버전>@sha256:<digest>` 형식이다(`tests/repo-config.bats`의 digest 형식 테스트). 고정값은 릴리스 노트를 읽은 뒤에만 바꾸고, `make check local-up local-verify`를 통과해야 한다(`AGENTS.md` Invariants).
- 게이트웨이 값은 스펙 §3.4 그대로다: 허용 목록 18개, 소유자는 `sub == BM_WEB_GITHUB_USER_ID`(숫자만), `forward_incoming_headers=False`, `allowed_client_redirect_uris=["https://claude.ai/api/mcp/auth_callback"]`, 동의 화면 켜짐, `cache_ttl_seconds=300`.
- `cloudflared`는 `tunnel run`과 환경변수 토큰만 쓴다. `--url`과 `trycloudflare`는 쓰지 않는다.
- 비밀값 셋(`BM_WEB_GITHUB_CLIENT_SECRET`, `BM_WEB_JWT_KEY`, `BM_WEB_TUNNEL_TOKEN`)은 출력, 명령 인자, 저장소, 대화에 두지 않는다. 사용자가 main checkout `.env`에 직접 쓴다.
- `BM_WEB_HOST`와 그 호스트명이 풀리는 IP는 Progress log, PR, 코멘트에 쓰지 않는다. `mcp.<domain>` 자리표시자만 쓴다.
- 로컬 확인의 가짜 웹 값은 make 명령줄로만 넘긴다. main checkout `.env`는 고치지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: bbz2ngk7`, `Task: <N|review|none>`.

## Review Focus

1. 재고정 뒤에도 web-connector 계획 Review Focus 1~5가 그대로 지켜진다: 백엔드가 죽어도 OAuth 메타데이터가 10초 안에 답함, 숫자 `sub`가 아닌 토큰 거절, 백엔드의 새 도구 숨김, 감사 줄에 노트 본문 없음, 깨진 비밀값에서 ssh 전에 멈춤. `fastmcp`가 바뀌면 `StaticTokenVerifier`, OAuth 프록시 저장소 경로(`make status`의 등록 수 패턴, web-connector 계획 Progress log 2026-10-27), `forward_incoming_headers`가 달라질 수 있다. Task 1 Step 3의 `gateway/test_gateway.py`와 bats가 고정한다.
2. 그사이 Basic Memory 이미지가 바뀌었으면 실제 `tools/list`가 허용 18개와 차단 3개의 합과 다를 수 있다. Task 1 Step 4가 확인한다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| `compose.yaml` | `gateway`·`cloudflared` 이미지 줄 | 1 |
| `gateway/requirements.in`, `gateway/requirements.txt` | `fastmcp` 고정과 해시 고정 결과(`make gateway-lock`) | 1 |
| `Makefile` | `PIP_TOOLS_VERSION` | 1 |
| `gateway/gateway.py`, `gateway/test_gateway.py` | `fastmcp` API가 바뀐 경우에만 | 1 |
| 이 계획, `docs/decisions/adr-2026-10-22-fcvznmdc-web-connector.md` | Progress log, `status`, ADR "이전 결과" 절 | 2 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/bbz2ngk7-web-connector-rollout` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고, Progress log 첫 행에 사용자의 도메인 결정(날짜만, 도메인 이름은 쓰지 않음)을 적는다. push한 뒤 초안 PR을 연다.

### Task 1: Re-pin images and gateway dependencies

**Files:**
- Modify: `compose.yaml`, `gateway/requirements.in`, `gateway/requirements.txt`, `Makefile`
- Modify(필요할 때만): `gateway/gateway.py`, `gateway/test_gateway.py`, 관련 bats

- [ ] **Step 1: 이미지·의존성 재고정.** 그날의 stable을 고른다: Python 3.12.x slim(보안 릴리스), `cloudflared` 최신 릴리스, `fastmcp` 최신 4.x, `pip-tools`. 4.1.3 이후 `fastmcp` 릴리스 노트에서 OAuth 프록시, 토큰 검증, 프록시 클라이언트, 저장소 변경을 읽고 Progress log에 링크와 함께 적는다. 메이저 버전이 바뀌거나 스펙 §3.4의 값을 지킬 수 없으면 멈추고 사용자에게 묻는다. digest는 multi-arch index digest를 쓴다.
- [ ] **Step 2: 실패 확인.** `compose.yaml`·`requirements.in`·`Makefile`을 고치고 `make gateway-lock`을 실행한 뒤, Run: `make check`, 이어서 가짜 값으로 `make local-up local-verify local-down BM_WEB=on BM_WEB_GITHUB_USER_ID=4242 BM_WEB_GITHUB_CLIENT_ID=fake-client BM_WEB_GITHUB_CLIENT_SECRET=fake-secret BM_WEB_JWT_KEY=<openssl rand -hex 32>`. Expected: 통과하면 Step 3으로 간다. API가 바뀌어 게이트웨이 테스트가 실패하면 실패한 테스트 이름과 원인을 Progress log에 적는다.
- [ ] **Step 3: 최소 수정과 통과 확인.** 실패가 있었으면 `gateway/`만 최소로 고친다. 기존 테스트는 약하게 바꾸지 않는다. Run: `make check`, 위 `local-up local-verify local-down BM_WEB=on`, `BM_WEB` 없이 `make local-up local-verify local-down`. Expected: `make check` exit 0과 커버리지 80% 이상. `BM_WEB=on`은 `verify-web.sh`의 `OK:` 줄과 uid 1000의 `Ran N tests ... OK`가 나오고 출력에 가짜 값이 없다. `BM_WEB` 없이는 basic-memory·silverbullet만 뜬다.
- [ ] **Step 4: 도구 목록 대조.** `compose.yaml`의 Basic Memory 이미지가 0.23.2가 아니면 로컬 `tools/list` 이름을 허용 18개와 차단 3개(`delete_note`, `create_memory_project`, `delete_project`)와 비교한다. 새 도구가 있으면 허용 목록을 바꾸지 말고 사용자에게 묻는다.
- [ ] **Step 5: 커밋.** Progress log에 Step 1~4의 명령과 결과를 적고 같은 커밋에 넣는다. `git commit -m "chore: re-pin the web connector images and gateway dependencies" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: bbz2ngk7" --trailer "Task: 1"`

### Code PR: review and merge

- [ ] PR 본문 Verification에 Task 1의 `make check`, `make local-up local-verify` 결과(`BM_WEB` 켬과 끔)와 CI(`check`, `pr-rules`)를 적는다.
- [ ] 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
- [ ] CI가 통과하고 열린 P0/P1이 없으면 사용자 OK를 받고 `gh pr ready <PR>`을 실행한다. 승인과 squash 병합은 사람만 한다.

### Task 2: VM rollout and claude.ai check (with the user, OK at every step)

**Files:**
- Modify: 이 계획(Progress log, `status`), `docs/decisions/adr-2026-10-22-fcvznmdc-web-connector.md`(이전 결과 절)

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
- [ ] **Step 8: 결과 PR.** web-connector ADR에 "이전 결과" 절을 더하고, 이 계획의 `status`를 `completed`로 바꿔 새 `plan/bbz2ngk7-<slug>` 브랜치에서 커밋·push하고 PR을 연다(`Task: 2`). 호스트명과 IP는 쓰지 않는다.

## Follow-ups

- 서비스가 직접 JSON 로그를 내게 하는 일: `cloudflared`는 `tunnel --output json`(환경변수 `TUNNEL_LOG_OUTPUT=json`), 게이트웨이는 `FASTMCP_LOG_ENABLED=false`와 uvicorn `log_config`로 stdlib JSON formatter를 쓴다. 근거는 [json-log-export 조사](../research/rsch-2026-10-27-k2zsffqn-json-log-export.md) §2와 시사점 2(2026-10-27 사용자 결정: 후속으로 미룸)다. 웹 커넥터가 VM에서 돈 뒤 별도 work 브랜치로 한다(아직 없음).
- ChatGPT 연결은 별도 스펙으로 다룬다(스펙 §1 범위 밖). web-connector 계획에서 옮겼다.
- 읽기 지연 중앙값이 500 ms를 넘으면 백엔드 연결을 재사용하는 클라이언트로 바꾸는 work 브랜치를 만든다(스펙 §3.4). web-connector 계획에서 옮겼다.

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
