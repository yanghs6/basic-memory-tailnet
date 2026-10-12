# Basic Memory on OCI Always Free + Tailscale — 설계

- 상태: **대체됨 (2026-10-12)** → [GCP 설계](2026-10-12-basic-memory-gcp-tailscale-design.md). 호스팅을 OCI에서 GCP로 옮겼다. 이 문서는 완료된 계획 01~03의 기준으로만 남긴다.
- 이전 상태: 승인됨 (2026-10-07). 구현 계획은 순서대로 5개다. 진행 중인 계획은 `docs/plans/active/`, 대기 중인 계획은 `docs/plans/backlog/`에 있다. 모든 계획은 [git·리뷰 정책](2026-10-07-git-review-policy-design.md)을 따른다.
  1. `2026-10-07-01-local-foundation.md`: 도구 체인, compose, 로컬 MCP 검증, AGENTS.md 기본판(Git 섹션 포함)
  2. `2026-10-07-02-git-review-tooling.md`: `make check-git`, `make review`, 리뷰어 에이전트, git·리뷰 스킬
  3. `2026-10-07-03-vm-scripts.md`: 부트스트랩, 배포·검증·상태·로그, 백업·복원
  4. `2026-10-07-04-docs-skills.md`: 운영 스킬, README, 아키텍처, 런북, ADR, 로컬 전체 검증
  5. `2026-10-07-05-vm-rollout.md`: 실제 VM 배포(사용자와 함께)
- 범위: 첫 목표 `OCI Always Free + Tailscale + Basic Memory`
- 출처: ChatGPT 대화 "에이전트 기억 공유 제안"의 마지막 단계와, 2026-10-07에 공식 문서로 다시 검증한 사실

## 1. 목표와 완료 조건

여러 기기(개인 Mac, 회사 Mac)의 코딩 에이전트(Codex, Claude Code, Antigravity)가 함께 쓰는 Basic Memory MCP 서버를 OCI Always Free VM에 올린다. 이 서버는 tailnet 안에서만 접근할 수 있어야 한다.

**완료 조건**

1. `make verify`가 tailnet 안에서 `https://bm-node.<tailnet>.ts.net/mcp`로 MCP 왕복(initialize → tools/list → 노트 쓰기/읽기/삭제)을 통과한다.
2. 공개 노출이 없다. 두 가지를 모두 충족해야 한다.
   - 자동 검증: `make verify`로 VM의 공인 IP에서 22·80·443·8737번 포트가 닫혀 있고, Serve가 tailnet 전용(Funnel off)임을 확인한다.
   - 수동 점검: OCI 공개 인바운드 규칙이 0개이고 tailnet 정책에 `funnel` 속성이 없음을 확인해 기록한다(운영 런북의 Exposure audit). 이 둘은 VM에서 읽을 수 없어 자동 검증 범위 밖이다.
3. `make backup`으로 받은 백업을 `make restore`로 복원하면 백업 시점의 데이터 파일이 manifest와 일치하게 돌아오고, 백업 이후의 변경은 사라진다.
4. `make check`(lint + test + coverage ≥ 80%)가 통과한다.

**범위 밖 (다음 목표)**

- 에이전트별 MCP 클라이언트 연결 설정
- 자동·주기 백업
- `personal-context` GitHub 정본 연동, 지식 그래프·온톨로지
- 회사용 별도 인스턴스

## 2. 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 자동화 수준 | VM은 콘솔에서 수동 생성하고, 저장소에는 스크립트·compose·Make·런북을 둔다 | A1 용량이 부족할 때 수동 재시도가 쉽다. IaC 상태 관리가 필요 없다 |
| 배포 방식 | Mac에서 SSH로 부트스트랩한 뒤 Tailscale SSH로 전환하고 OCI 22번 규칙을 삭제한다 | 디버깅이 쉽고 다시 실행해도 안전하다. 인스턴스 메타데이터에 비밀값이 남지 않는다 |
| 로컬 검증 | 같은 compose로 Mac Docker에서 먼저 검증한다 | VM에서의 시행착오를 줄이고 검증 스크립트를 재사용한다 |
| 호스트 포트 | `127.0.0.1:8737` (컨테이너 내부는 8000) | 8188은 ComfyUI 기본 포트라 제외. 8737은 IANA 미할당이고 알려진 기본 사용처가 없다 |
| 사용 범위 | 개인 기억만 저장하고, 개인 Mac과 회사 Mac이 tailnet에 참여한다 | 사용자 선택 |
| 백업 | 수동 `make backup` / `make restore` | 유휴 회수 위험에 대한 최소 대비. 자동화는 다음 목표 |
| 계정 | OCI·Tailscale 모두 신규 가입부터 시작한다 | 사용자 상태 |

## 3. 검증된 외부 사실 (2026-10-07)

- **Verified:** Basic Memory 이미지는 `ghcr.io/basicmachines-co/basic-memory:0.23.2`이다(`v` 접두사 없음). linux/arm64를 포함하고, index digest는 `sha256:939f1173d96626c280763e14622f2381d49fbbb7db17cae2e832f4f639405643`이다.
- **Verified:** 이미지의 기본 CMD는 `--transport sse`다. 따라서 `basic-memory mcp --transport streamable-http --host 0.0.0.0 --port 8000 --path /mcp`로 덮어써야 한다.
- **Verified:** 데이터는 `/app/data`, 설정과 인덱스는 `/home/appuser/.basic-memory`에 둔다. 컨테이너는 UID/GID 1000으로 실행된다. 기본 프로젝트 `main`은 `/app/data/basic-memory`에 생성된다.
- **Verified:** 변경 감지 환경변수의 현재 이름은 `BASIC_MEMORY_INDEX_CHANGES`, `BASIC_MEMORY_INDEX_DELAY`다.
- **Verified:** Basic Memory HTTP 엔드포인트에는 인증이 없다. 공식 문서는 공인 인터넷에 노출하지 말라고 경고한다. HTTP 헬스 엔드포인트는 없다.
- **Verified:** 시맨틱 검색은 FastEmbed 로컬 모델을 쓰므로 API 키가 필요 없다. 첫 사용 시 모델을 내려받는다.
- **Verified:** OCI Always Free A1 한도는 월 1,500 OCPU-시간 / 9,000 GB-시간(= 2 OCPU / 12GB)이고, 블록 볼륨은 부트 볼륨 포함 200GB다. 홈 리전은 변경할 수 없다.
- **Verified:** OCI 유휴 회수 기준: 7일 동안 CPU 95번째 백분위, 네트워크, 메모리(A1만 해당)가 **모두** 20% 미만이면 회수할 수 있다.
- **Verified:** `tailscale serve --bg http://127.0.0.1:<port>`는 tailnet 안에서 HTTPS 443으로 노출한다. HTTPS 인증서와 MagicDNS를 켜야 한다. 인증서가 발급된 기기 이름은 공개 CT 로그에 기록된다.
- **Verified (tailscale.com/docs/features/tailscale-funnel):** Tailscale Funnel은 기본 비활성이다. `tailscale funnel`을 실행해 승인하면 정책 `nodeAttrs`에 `funnel` 속성이 추가되어 사용 권한이 생긴다. 실제 공개 여부는 각 기기의 Serve/Funnel 설정이 정한다. (정정: 초기 조사의 "기본으로 켜짐"은 틀렸다.)
- **Verified:** 서버용으로는 사전 승인된 태그 인증 키를 권장한다. `tailscale set --ssh`를 켜면 공인 22번 포트를 닫을 수 있다.
- **Verified:** Tailscale Personal 요금제는 비상업 용도로 한정된다.
- **Open question:** 회사 Mac을 개인 tailnet에 참여시키는 것이 회사 보안 정책과 Tailscale Personal 약관에 맞는지는 사용자가 확인해야 한다.
- **Verified (2026-10-07, 로컬 0.23.2 컨테이너):** `Host: bm-node.example.ts.net` 헤더로 보낸 initialize가 200으로 응답했고, write/read/delete 왕복도 성공했다. 실제 Tailscale Serve 경유 동작은 VM 배포 단계에서 다시 확인한다.
- **Open question:** Pay As You Go로 전환한 계정에도 유휴 회수 정책이 적용되는지는 공식 문서에 명시돼 있지 않다.

## 4. 아키텍처

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

신뢰 경계는 tailnet이다. Basic Memory에 인증이 없으므로, 접근 제어는 Tailscale의 기기 인증과 정책에 맡긴다. 컨테이너 포트는 어느 환경에서도 `127.0.0.1`에만 바인딩한다.

## 5. 저장소 구조

```
AGENTS.md            정본 에이전트 지침, 100줄 이하: 목적, make 타깃, 불변 규칙, 안전 규칙, 문서 안내
CLAUDE.md            `@AGENTS.md` 한 줄
README.md            사람용 입구: 개요, 사전 요구사항, `make help`
Makefile             유일한 수명주기 인터페이스, `help` 자동 생성
compose.yaml         Basic Memory 서비스
.env.example         사용자별 비밀이 아닌 값: BM_VM_HOST, BM_VM_USER, BM_TAILNET_DOMAIN, BM_PORT
.gitignore           .env*(.env.example 제외), .local-data/, backups/, CLAUDE.local.md, .claude/settings.local.json
.editorconfig  .shellcheckrc
.claude/settings.json            .env(.env.example은 읽기 가능), backups/, .local-data/ 읽기 거부, make lint/test/check 허용
.claude/skills/<name>            → ../../.agents/skills/<name> (스킬별 심볼릭 링크)
.agents/skills/bm-upgrade/SKILL.md
.agents/skills/bm-recover/SKILL.md
.agents/skills/bm-diagnose/SKILL.md
scripts/lib/common.sh            log/step/die/require_cmd/require_env/mask/remote/remote_compose/sha256_of
scripts/bootstrap-vm.sh          공인 IP SSH로 remote/bootstrap.sh를 올려 실행
scripts/remote/bootstrap.sh      VM에서 root로 실행 (로컬에서 stub으로 단위 테스트)
scripts/deploy.sh  verify-mcp.sh  verify-vm.sh  status.sh  logs.sh  backup.sh  restore.sh
tools/Dockerfile  tools/coverage.sh   테스트 이미지(kcov + bats + jq)와 커버리지 게이트
tests/helpers.bash               setup_stubs, use_vm_env
tests/stubs/                     ssh, docker, curl, tailscale, sudo, apt-get 등 가짜 명령
tests/fixtures/                  녹화한 MCP 응답(SSE, JSON), os-release
tests/scripts.bats               스크립트 단위 테스트
tests/repo.bats                  구조 테스트
docs/ARCHITECTURE.md             토폴로지, 데이터 경로, 신뢰 경계
docs/runbooks/accounts.md  oci-vm.md  bootstrap.md  operations.md
docs/specs/                      이 문서
docs/plans/active/  docs/plans/completed/   진행·결정 로그가 포함된 실행 계획
docs/decisions/                  ADR (예: 0001-basic-memory-on-oci.md, 0002-vm-sizing.md)
```

**에이전트 지침 규칙**

- **Verified:** Codex와 Antigravity는 `AGENTS.md`를 읽는다. Claude Code는 `CLAUDE.md`가 있으면 `AGENTS.md`를 읽지 않으므로, `CLAUDE.md`는 `@AGENTS.md` 한 줄로만 둔다.
- `GEMINI.md`와 `.agents/workflows/`는 만들지 않는다. 각각 `AGENTS.md`와의 우선순위가 문서화되지 않았고, Antigravity Workflows는 2026-10-19에 종료된다.
- 저장소 노트에는 `Verified` / `Command` / `Assumption` / `Open question` 표기를 쓴다.
- 비밀값, `.env`, 생성된 자격 증명, 사용자 데이터는 커밋하지 않는다.

**스킬**

- 정본은 `.agents/skills/<name>/SKILL.md`에 둔다(Codex·Antigravity). Claude용으로 `.claude/skills/<name>`을 스킬별 심볼릭 링크로 만든다(**Verified:** Claude Code는 스킬 폴더 심볼릭 링크를 따라간다).
- frontmatter는 Agent Skills 표준 필드(`name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`)만 쓴다. 표준에 `disable-model-invocation`이 없으므로, VM을 바꾸는 단계는 본문에 "실행 전 사용자 확인"을 명시한다.
- 스킬은 Make 타깃을 순서대로 엮고 판단 기준을 더할 뿐이다. 실제 동작은 Make 타깃과 스크립트에 있다.

| 스킬 | 사용 시점 | 절차 |
|---|---|---|
| `bm-upgrade` | Basic Memory 버전을 올릴 때 | 릴리스 노트에서 DB·설정 마이그레이션 확인 → 새 digest 조회 → `compose.yaml` 수정 → `make check local-up local-verify` → 사용자 확인 → `make backup`(롤백 지점) → `make deploy verify` → 롤백은 이전 `image:` 줄 + `make restore BACKUP=<롤백 지점>`(이미지와 데이터를 함께 되돌림. 이후 쓴 노트는 사라진다는 점을 먼저 알림) |
| `bm-recover` | VM이 회수·손상됐을 때 | `docs/runbooks/oci-vm.md`대로 VM 재생성(사용자 작업) → `make vm-bootstrap` → 사용자 확인 → `make deploy restore BACKUP=<파일>` (restore가 끝에 verify를 실행) |
| `bm-diagnose` | 연결·MCP 문제가 있을 때 | 읽기 전용: `tailscale status`, `make status`, `make logs`, `make probe`만 실행해 원인을 좁힘. 노트를 쓰거나 무언가를 시작하는 명령(`make verify`, `make local-up` 등)은 사용자에게 제안만 함 |

## 6. Make 타깃

| 분류 | 타깃 | 동작 |
|---|---|---|
| 개발 | `help` | 타깃 목록과 설명 |
| 개발 | `lint` | shellcheck, `shfmt -d` (Docker 이미지) |
| 개발 | `test` | bats 단위·구조 테스트 (Docker 이미지) |
| 개발 | `coverage` | kcov로 `scripts/` 라인 커버리지 측정, 80% 미만이면 실패 |
| 개발 | `check` | `lint` + `test` + `coverage` |
| 개발 | `fmt` | `shfmt -w`로 포맷 수정 |
| 개발 | `tools-image` | 테스트 이미지 빌드 (`test`, `coverage`가 자동 호출) |
| 로컬 | `local-up`, `local-down`, `local-logs` | Mac Docker에서 compose 실행·정지·로그 |
| 로컬 | `local-verify` | `verify-mcp.sh http://127.0.0.1:8737/mcp`에 ts.net Host 헤더 시나리오 포함 |
| VM | `vm-bootstrap HOST=<공인IP>` | 공인 IP로 SSH 접속해 첫 설정 |
| VM | `deploy` | compose와 VM env를 전송하고 pull/up, healthy 대기 |
| VM | `verify` | tailnet URL로 MCP 왕복(테스트 노트를 쓰고 지움) + 원격 포트 바인딩 + Serve tailnet 전용 + 공인 IP의 22·80·443·8737 차단. `BM_VM_PUBLIC_IP` 필수 |
| VM | `probe` | `verify`와 같은 검사를 노트 쓰기 없이 수행(initialize·tools/list만). 진단용 |
| VM | `status` | 컨테이너 상태, 메모리 사용률(20% 미만 경고), Serve 상태 |
| VM | `logs` | 원격 컨테이너 로그 |
| VM | `backup` | 백업을 `backups/bm-<시각>.tgz`, `.sha256`, `.manifest`로 저장 |
| VM | `restore BACKUP=<파일>` | 확인 입력 후 저장소 compose.yaml과 함께 복원(실패 시 자동 롤백) → verify |

수명주기 작업은 Make 타깃으로만 한다. raw `docker compose`나 `ssh`는 Make 타깃 실패를 진단할 때만 쓰고, 그 이유를 기록한다.

## 7. 컴포넌트 동작

### 7.1 설정 값

- 로컬 기본값은 `compose.yaml` 안에 둔다(`BM_KNOWLEDGE_DIR=./.local-data/knowledge`, `BM_CONFIG_DIR=./.local-data/config`, `BM_PORT=8737`). 로컬은 `.env` 없이도 동작한다.
- VM용 값(`/srv/basic-memory/...`)은 `deploy.sh`가 원격 `/opt/basic-memory/.env`로 생성한다.
- 사용자별 값(`BM_VM_HOST`, `BM_VM_USER`, `BM_TAILNET_DOMAIN`)은 git ignore 대상인 `.env`에 두고, Makefile이 선택적으로 include한다.
- 유일한 비밀값은 Tailscale 인증 키다. 저장소에는 어떤 형태로도 두지 않는다.

### 7.2 `compose.yaml`

- `image: ghcr.io/basicmachines-co/basic-memory:0.23.2@sha256:939f1173…`
- `command`: `basic-memory mcp --transport streamable-http --host 0.0.0.0 --port 8000 --path /mcp`
- `ports`: `127.0.0.1:${BM_PORT:-8737}:8000`
- `volumes`: `${BM_KNOWLEDGE_DIR}:/app/data`, `${BM_CONFIG_DIR}:/home/appuser/.basic-memory`
- `environment`: `BASIC_MEMORY_DEFAULT_PROJECT=main`, `BASIC_MEMORY_INDEX_CHANGES=true`, `BASIC_MEMORY_LOG_LEVEL=INFO`
- `healthcheck`: 컨테이너 안의 `python`으로 `127.0.0.1:8000`에 TCP 연결을 시도한다(업스트림 `--version` 체크를 대체). 간격과 재시도는 compose에 명시한다.
- `restart: unless-stopped`

### 7.3 스크립트 공통

- 모든 스크립트는 `set -euo pipefail`로 시작하고 `scripts/lib/common.sh`를 source한다.
- 시작할 때 필요한 명령과 env를 확인한다. 없으면 설치·설정 방법을 담은 메시지와 함께 바로 종료한다.
- 원격 명령은 `remote()` 래퍼(`ssh $BM_VM_USER@$BM_VM_HOST`)로 실행한다. 실패하면 단계 이름과 다음에 확인할 명령을 출력한다.
- 대기와 재시도는 이름 붙은 상수(예: `HEALTH_TIMEOUT_SECONDS`)로 제한하고, 초과하면 실패로 끝낸다.
- 인증 키와 MCP 세션 ID는 `mask()`로 가린 뒤에만 출력한다.

### 7.4 `bootstrap-vm.sh HOST`

공인 IP로 SSH 접속해 원격 스크립트를 실행한다. 단계마다 이미 된 일은 건너뛰므로, 다시 실행해도 결과가 같다.

1. 공식 apt 저장소로 Docker Engine과 compose 플러그인을 설치하고, `ubuntu` 사용자를 docker 그룹에 추가한다.
2. Tailscale을 설치하고, 로그인되어 있지 않으면 `tailscale up --hostname=bm-node --ssh`를 실행한다. 인증 키 처리는 다음과 같다.
   - 숨김 입력(`read -s`)이나 `TS_AUTHKEY`로 받아 **stdin으로만** 원격에 넘긴다.
   - 원격 스크립트는 키를 `/run`(tmpfs)의 0600 임시 파일에 써서 `--auth-key=file:<경로>`로 넘기고 즉시 삭제한다(**Verified:** tailscale.com/kb/1241).
   - 로컬과 원격 어디에서도 명령 인자나 디스크에 남기지 않는다.
   - 이미 tailnet에 있으면 키 없이 `tailscale set --hostname=bm-node --ssh`만 실행한다.
3. `/srv/basic-memory/{knowledge,config}`를 만들어 1000:1000으로 소유권을 주고, `/opt/basic-memory`는 `ubuntu` 소유로 만든다.
4. `tailscale serve --bg http://127.0.0.1:8737`
5. 다음 단계를 안내한다: `ssh ubuntu@bm-node true`로 Tailscale SSH 확인 → 성공한 뒤에만 OCI 22번 규칙 삭제.

### 7.5 `deploy.sh`

tailnet을 거쳐 `compose.yaml`과 생성한 `.env`를 `/opt/basic-memory`로 전송하고, `docker compose pull` → `up -d`를 실행한 뒤 healthy가 될 때까지 기다린다.

### 7.6 `verify-mcp.sh [--host-header H] [--read-only] URL`

curl과 jq로 MCP streamable HTTP를 직접 검증한다.

1. `initialize` 요청(`Accept: application/json, text/event-stream`)을 보내고 `Mcp-Session-Id`를 확보한 뒤 `notifications/initialized`를 보낸다.
2. `tools/list`에 `write_note`, `read_note`, `search_notes`가 있는지 확인한다.
3. `verify/` 폴더에 고유한 제목으로 노트를 쓰고, 읽어서 내용이 같은지 확인한 뒤 삭제한다.

- 응답은 JSON과 SSE(`data:` 줄) 두 형식을 모두 파싱한다.
- 실패하면 단계 이름과 응답 요약을 출력하고 0이 아닌 코드로 종료한다.
- `--read-only`는 1~2단계만 하고 노트를 쓰지 않는다(`make probe`, `bm-diagnose`용).
- `local-verify`는 이 스크립트를 두 번 실행한다. 기본 실행 한 번, `--host-header bm-node.example.ts.net`으로 한 번이다.
- VM용 `verify`와 `probe`(`verify-vm.sh [--read-only]`)는 tailnet HTTPS URL로 실행하고, 이어서 다음을 확인한다.
  - 원격 `ss -lnt`로 8737이 `127.0.0.1`에만 열려 있다.
  - `tailscale serve status`가 `tailnet only`이고 `Funnel on`이 아니다. **Assumption:** 출력 문구는 계획 05에서 실제 VM으로 확인한다.
  - `BM_VM_PUBLIC_IP`(필수)의 22·80·443·8737이 Mac에서 연결되지 않는다.
- OCI 인바운드 규칙과 tailnet 정책은 VM에서 읽을 수 없으므로 운영 런북의 Exposure audit으로 수동 점검한다.

### 7.7 `status.sh`

원격 컨테이너 상태와 health, VM 메모리 사용률, `tailscale serve status`를 출력한다. 메모리 사용률이 20% 미만이면 유휴 회수 위험 경고를 낸다.

### 7.8 `backup.sh`

1. 재시작 `trap`을 먼저 등록한 뒤 원격 컨테이너를 정지한다. 정지 응답이 끊겨도 재시작은 반드시 시도한다.
2. 정지 상태에서 데이터 파일별 sha256 목록(manifest)을 만든다.
3. `/srv/basic-memory`를 tar.gz로 스트리밍해 받는다.
4. 컨테이너를 다시 시작한다.
5. `backups/bm-<UTC 시각>.tgz`, `.sha256`, `.manifest`를 저장한다. 실패하면 반쪽 파일을 남기지 않는다.

SQLite 파일이 쓰는 도중에 복사되지 않도록 잠시 정지한다. 개인용이므로 수 초 중단은 허용한다.

### 7.9 `restore.sh BACKUP`

1. 로컬에서 `.sha256`을 검증하고, `.manifest`가 있는지 확인한다.
2. 사용자가 `yes`를 직접 입력해야 진행한다.
3. 롤백 `trap`을 등록하고 원격 컨테이너를 정지한다.
4. 임시 경로 `/srv/basic-memory.restore-<시각>`에 압축을 풀고, 파일 목록·체크섬을 manifest와 대조한 뒤 소유권을 1000:1000으로 맞춘다. 여기까지는 현재 데이터를 건드리지 않는다.
5. 저장소의 `compose.yaml`을 VM에 적용한다. 이전 파일은 성공할 때까지 보관한다. 이미지와 데이터를 함께 되돌려, 업그레이드 롤백 때 이전 이미지가 새 버전이 마이그레이션한 데이터 위에서 돌지 않게 한다.
6. 현재 데이터를 `/srv/basic-memory.prev-<시각>`으로 옮기고(삭제하지 않음), 복원본으로 교체한 뒤 컨테이너를 시작한다.
7. 정지 이후 어느 단계에서 실패해도 롤백한다. 이전 데이터와 compose를 되돌리고(실패한 복원본은 `.failed-<시각>`에 보관) 컨테이너를 다시 시작한다.
8. Make 레시피가 `verify`를 실행한다.

## 8. 운영 흐름 (런북)

1. **`accounts.md` (사용자):**
   - OCI 가입. 홈 리전은 변경할 수 없다. 서울(`ap-seoul-1`)과 춘천(`ap-chuncheon-1`)이 후보이며, A1 용량 부족 가능성을 안내한다.
   - Tailscale 가입 → MagicDNS와 HTTPS 인증서 켜기 → 정책에 `funnel` 속성이 있으면 제거(기본은 없음) → `tag:bm-server`와 Tailscale SSH 규칙 정의 → 사전 승인된 1회용 태그 인증 키 발급
2. **`oci-vm.md` (사용자, 콘솔):**
   - `VM.Standard.A1.Flex`, 표준 Canonical Ubuntu 24.04(Minimal 아님), 1 OCPU / 4GB, 부트 볼륨 50GB, SSH 공개키 등록
   - 4GB는 잠정값이고 ADR 0002로 확정한다. 로컬 실측(컨테이너 449 MiB)으로 보면 6GB에서는 메모리 사용률이 20% 미만이 될 가능성이 커서 4GB로 낮췄다.
   - Security List에는 본인 IP의 22번 포트만 임시로 연다.
3. **`bootstrap.md`:**
   - `make vm-bootstrap HOST=<공인IP>` → `ssh ubuntu@bm-node true` 확인 → 콘솔에서 22번 규칙 삭제 → `make deploy verify status`
   - `make verify`로 공인 IP의 22·80·443·8737 차단과 Serve tailnet 전용을 확인하고, Exposure audit(OCI 인바운드 규칙 0개, 정책에 `funnel` 없음)을 수동으로 마친다.
   - 비상 경로는 OCI 시리얼 콘솔이다.
4. **`operations.md`:**
   - 배포: `make deploy verify`
   - 점검: `make status`
   - 백업: `make backup` (중요 작업 전 + 주 1회 권장)
   - 업그레이드, 복구, 진단은 각각 `bm-upgrade`, `bm-recover`, `bm-diagnose` 스킬을 쓴다.
   - Exposure audit: 배포 직후와 정책·네트워크를 바꾼 뒤 OCI 인바운드 규칙 0개와 정책의 `funnel` 속성 부재를 수동 점검하고 기록한다.
   - 유휴 회수 대응: 메모리 사용률 경고 시 조치, 백업을 최신으로 유지

## 9. 테스트와 검증

- **도구:** shellcheck, shfmt, bats(bats-support/assert 포함), kcov를 고정 태그의 Docker 이미지로 실행한다. Mac 의존성은 Docker, make, ssh, curl, jq, tailscale이다.
- **단위 (`tests/scripts.bats`):** `helpers.bash`가 PATH 앞쪽에 `ssh`, `docker`, `curl`, `tailscale` 스텁을 둔다. 스텁은 받은 인자를 기록하고 정해진 응답을 돌려준다. 스크립트마다 다음을 검증한다.
  - 정상 경로
  - 필수 명령이나 env 누락
  - 원격 단계 실패
  - 제한 시간 초과
  - restore에서 확인 입력 거부
  - sha256 불일치
- **보안 불변 규칙 테스트:**
  - 인증 키가 명령 인자나 출력에 나타나지 않는다.
  - 포트는 `127.0.0.1`에만 바인딩된다.
  - backup이 실패해도(정지 응답 유실 포함) 컨테이너가 다시 시작된다.
  - restore는 압축 해제·manifest 대조·교체·기동 중 어디서 실패해도 이전 데이터와 compose로 롤백한다.
  - `BM_VM_PUBLIC_IP`가 없으면 `verify`가 실패하고, Funnel이 켜져 있으면 실패한다.
  - `--read-only`/`probe`는 `tools/call`을 보내지 않는다.
- **`verify-mcp.sh` 파싱 테스트:** `tests/fixtures/`의 녹화된 MCP 응답(JSON, SSE)으로 검증한다.
- **구조 (`tests/repo.bats`):**
  - 모든 스크립트에 `set -euo pipefail`이 있다.
  - `AGENTS.md`는 100줄 이하이고, `CLAUDE.md`는 `@AGENTS.md`다.
  - 모든 Make 타깃이 `help`에 나오고, 문서의 상대 링크가 유효하다.
  - 이미지가 digest로 고정돼 있고, `.env`가 git에 추적되지 않는다.
  - 모든 스킬에 Claude용 링크가 있고, frontmatter는 표준 필드만 쓰며, `SKILL.md`는 500줄 이하다.
  - 실패 메시지에는 고치는 방법을 포함한다.
- **커버리지:** kcov로 `scripts/` 라인 커버리지 80% 이상이어야 하고, `scripts/` 아래 모든 실행 스크립트가 최소 한 테스트에서 실행돼야 한다. **Verified (2026-10-07 spike):** kcov 컨테이너는 bats가 실행하거나 source한 스크립트의 라인 커버리지를 수집한다.
- **통합 (로컬, 실제 컨테이너):** `make local-up local-verify`. Host 헤더 시나리오를 포함한다. 이 단계에서 컨테이너 메모리 사용량을 측정해 VM 메모리 크기를 ADR 0002로 확정한다. 기준은 평소 사용률이 20% 이상이 되는 크기다.
- **E2E (VM, 수동):** `make deploy verify status`와 외부 노출 점검을 실행하고, 결과를 `docs/plans/` 진행 로그에 `Verified` / `Command` 표기로 기록한다. 계정이 필요하므로 CI로 자동화하지 않는다.

## 10. 위험과 대응

| 위험 | 대응 |
|---|---|
| OCI 유휴 회수로 VM 손실 | 메모리 사용률 20% 이상이 되도록 크기 선정, `status` 경고, 수동 백업, `bm-recover` 스킬 |
| A1 용량 부족으로 생성 실패 | 런북에 시간대를 바꾼 재시도 안내(서울·춘천 리전은 AD가 각각 1개뿐). 홈 리전 선택 시 주의사항 명시 |
| Tailscale SSH 전환 실패로 접속 상실 | Tailscale SSH 확인 후에만 22번 삭제를 안내. 비상 경로는 시리얼 콘솔 |
| Host 헤더 거부로 MCP 연결 실패 | 로컬 Host 헤더 시나리오로 사전 확인. 실패 시 대안을 설계에 추가하고 사용자에게 보고 |
| 인증 없는 엔드포인트 노출 | `127.0.0.1` 바인딩, Serve tailnet 전용(Funnel off), 공개 인바운드 0개. 설정은 구조 테스트, 기기 상태는 `make verify`, OCI 규칙과 정책은 Exposure audit(수동)으로 확인 |
| 복원·업그레이드 롤백 중 데이터 손상 | 임시 경로에 풀고 manifest 대조 후 교체, 실패 시 자동 롤백, 이미지(compose)와 데이터를 함께 복원 |
| 기기 이름의 CT 로그 공개 | 일반적인 이름 `bm-node` 사용 |
| 회사 기기의 개인 tailnet 참여 | Open question으로 남기고, 사용자가 회사 정책과 약관을 확인 |
