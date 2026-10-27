---
status: current
reviewed: 2026-10-27
---

# 아키텍처

## 토폴로지

```
[개인/회사 Mac] ── tailnet ──▶ https://agent-hub.<tailnet>.ts.net/mcp        에이전트 (MCP)
  에이전트, 브라우저,            └──▶ https://agent-hub.<tailnet>.ts.net:8443  브라우저 (로그인)
  make deploy/verify/backup          │ Tailscale Serve (HTTPS, tailnet 전용)
  (Tailscale SSH)                    ▼
                        GCP e2-micro (us-west1-b, Ubuntu 26.04 Minimal amd64, 1GB + 스왑 1GB)
                        인바운드 허용: VPC 내부(10.128.0.0/9)만
                          └ Docker 프로젝트 basic-memory
                              basic-memory:0.23.2@sha256       127.0.0.1:8737 → :8000 /mcp   네트워크 basic-memory
                                /srv/basic-memory/knowledge → /app/data
                                /srv/basic-memory/config    → /home/appuser/.basic-memory
                              silverbullet:2.12.1-slim@sha256  127.0.0.1:3000 → :3000        네트워크 silverbullet
                                /srv/basic-memory/knowledge/basic-memory → /data (노트 폴더만)
```

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

선택 기능 `BM_WEB=on`(claude.ai 웹 커넥터)은 위 두 모드와 독립이며, VM의 인바운드 규칙을 바꾸지 않습니다.

```
claude.ai 백엔드 (160.79.104.0/21) ──▶ Cloudflare edge https://<BM_WEB_HOST> (TLS)
                                          ▲ VM의 cloudflared가 아웃바운드로 연 연결
GCP e2-micro (인바운드 규칙 변화 없음)     │
  └ cloudflared-tunnel (네트워크 web, 포트 게시 없음) ─ http://gateway:8080 ─▶ gateway-server (네트워크 web + basic-memory, 127.0.0.1:8738)
                                                                                └─ http://basic-memory:8000/mcp (Authorization 없음)
```

GCP 인스턴스 이름(예: `agent-hub-01`)과 Tailscale 기기 이름(`agent-hub`)은 서로 다를 수 있습니다. 스크립트는 `BM_VM_HOST`만 씁니다(`tailscale` 모드는 Tailscale 이름, `ssh` 모드는 SSH 별칭).

## 구성 요소

| 구성 요소 | 위치 | 역할 |
|---|---|---|
| `Makefile` + `scripts/` | Mac | VM 수명주기의 유일한 제어 지점. SSH로 VM을 다룸. gcloud는 쓰지 않음. 공용 함수는 `scripts/lib/`(common, vm, sb, git, docs, layout, mcp, agent-memory)에 있고, 파일마다 첫머리에 함수 색인이 있음 |
| `scripts/remote/provision-vm.sh` | VM (root) | 스왑 파일 1GB, Docker·Tailscale 설치, 데이터 디렉터리, Serve 설정 |
| `compose.yaml` | Mac(로컬 검증)·VM | Basic Memory와 SilverBullet(웹 UI), `BM_WEB=on`일 때만 뜨는 `gateway`(프로필 `web`)·`cloudflared`(프로필 `tunnel`) 컨테이너 정의 (같은 파일) |
| `silverbullet/` + `scripts/sync-sb-space.sh`·`upload-sb-fonts.sh`·`verify-sb.sh` | Mac → 노트 폴더 | SilverBullet 공간 파일(노트 `.gitignore`, 관리 페이지 `Library/agent-hub/agent-hub.md`, 대시보드 `index.md`)과 글꼴을 쓰고, 로그인·셸 꺼짐을 검사. [web-ui-silverbullet ADR](decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md) |
| `scripts/check-local-stack.sh` | Mac | `make local-up`·`local-down`이 compose를 부르기 전에 실행. compose project(`compose.yaml`의 `name:`)의 컨테이너가 다른 worktree에서 시작됐으면(라벨 `com.docker.compose.project.working_dir`) 멈춤. 그 디렉터리가 이미 없으면 경고만 남김. `docker ps`만 부름 |
| `scripts/sync-agent-memory.sh`·`show-memory-index.sh`·`install-memory-hooks.sh` | Mac | Claude Code·Codex 기억 파일을 `agent-memory/`로 미러하고, 세션 시작 때 다른 Mac·에이전트 기억의 색인을 넣는 hook. [스펙](specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md) |
| `make access-check` | Mac | 지금 네트워크에서 Tailscale 조정 서버·터널 엔드포인트·SSH 별칭이 되는지 보고하고 모드를 추천 (`scripts/check-access.sh`) |
| `gateway/` + `gateway` 서비스 | VM·Mac(로컬 검증) | `BM_WEB=on`일 때만 도는 OAuth 게이트웨이(FastMCP). GitHub 로그인 한 계정(숫자 id)만 통과시키고 허용한 도구 18개만 Basic Memory `/mcp`로 넘김. 감사 로그는 표준 출력, 저장소는 `/srv/basic-memory/gateway/`. [web-connector ADR](decisions/adr-2026-10-22-fcvznmdc-web-connector.md), [런북](runbooks/rbk-2026-10-27-x9h4zzdh-web-connector.md) |
| `cloudflared` 서비스 | VM | `BM_WEB=on`일 때만. Cloudflare로 아웃바운드 터널을 열고 `gateway`에만 닿음 |
| `make tunnel` | Mac | `ssh` 모드에서 MCP(18737)·웹 UI(13000)를 `127.0.0.1`로 포워딩 (`scripts/open-tunnel.sh`) |
| Tailscale Serve | VM | tailnet HTTPS 443 → `http://127.0.0.1:8737`(Basic Memory), 8443 → `http://127.0.0.1:3000`(SilverBullet) |
| Tailscale SSH | VM | `tailscale` 모드에서 부트스트랩 이후의 유일한 관리 경로(`ssh` 모드는 SSH 별칭) |
| gcloud 명령 | Mac (사람이 실행) | VM 생성, 방화벽, 정지·시작. [VM 런북](runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md)의 명령. 항상 `--configuration=bm-personal` |
| `.env`, `backups/` | Mac, main 체크아웃 | 사용자 설정과 `make backup` 결과물 (둘 다 git ignore) |
| 리뷰·스킬 도구 | Mac | `scripts/check-git.sh`(git 정책 검사), `scripts/review-branch.sh`와 `scripts/guard-reviewer-bash.sh`(다른 벤더의 읽기 전용 리뷰), `.agents/skills/`(에이전트용 스킬; `.claude/skills/`는 링크, 구조 규칙은 `tests/repo-skills.bats`와 [skill-structure ADR](decisions/adr-2026-10-13-m0xvj6rr-skill-structure.md)), `scripts/post-review.sh`·`scripts/post-review-record.sh`(리뷰 원문과 기록을 PR 코멘트로 게시), `docs/reviews/`([github-switch 계획](plans/plan-2026-10-13-k93wjt1a-github-switch.md)까지의 리뷰 기록) |
| `scripts/check-public-text.sh` + `.public-text-exemptions` | Mac·CI | 저장소 밖으로 나가는 텍스트에서 허용 집합 밖의 IPv4, tailnet IPv6, ts.net 이름, 세션 링크, Generated with 줄을 찾아 값 없이 위치와 종류만 알림. 인자 없이 실행하면 tracked 파일과 새 파일을 검사하고 예외 목록(경로와 종류만, 값은 없음)을 적용하며, `make check`가 `tests/repo-public-text.bats`로 이렇게 실행. `check-git.sh`(커밋 메시지)와 `check-pr.sh`(PR 제목·본문)도 검사하고, `post-review.sh`·`post-review-record.sh`는 hit이 있으면 리뷰 보고서와 findings 파일을 게시하지 않음. [public-text-guard ADR](decisions/adr-2026-10-26-vtmqpsyx-public-text-guard.md) |
| GitHub `yanghs6/basic-memory-tailnet` | 원격 (공개) | PR과 squash 병합, CI `check`·`pr-rules`(`.github/workflows/`; `pr-rules`는 `check-git.sh`, `check-pr.sh`, `check-tests.sh`를 실행하고, `check-tests.sh`는 merge-base 대비 `@test` 수 감소나 새 `skip`에 PR 본문 트레일러 `Tests-Removed: <이유>`를 요구. [test-integrity-guard ADR](decisions/adr-2026-10-27-y9fxhf7x-test-integrity-guard.md)), ruleset `main`(`.github/rulesets/main.json`). 에이전트는 머신 계정으로 PR을 열고 사람만 승인·병합. [GitHub 런북](runbooks/rbk-2026-10-14-ppmby9v6-github.md) |

## 데이터 경로

| 데이터 | 로컬 | VM |
|---|---|---|
| Markdown 노트 | `.local-data/knowledge/basic-memory/` | `/srv/basic-memory/knowledge/basic-memory/` |
| SilverBullet 공간 파일 | 노트 폴더 안 `.gitignore`, `index.md`, `Library/agent-hub/`(관리 페이지와 글꼴), `.silverbullet.browser-sessions.json`(로그인 세션) | 같음. Basic Memory는 `.gitignore`와 기본 무시 목록(`.*`)으로 이 파일들을 색인하지 않음 |
| SQLite 인덱스·설정·임베딩 모델 캐시 | `.local-data/config/` | `/srv/basic-memory/config/` |
| `compose.yaml` | 명령을 실행한 체크아웃 루트(`make deploy`가 그 파일을 올림) | `/opt/basic-memory/` |
| `.env` | main 체크아웃 루트 | `/opt/basic-memory/` (VM용 `.env`는 `make deploy`가 생성) |
| 상태 파일 | `~/.local/state/bm-agent-memory/` | 해당 없음 |
| 스왑 | 해당 없음 | `/swapfile` (1GB, `/etc/fstab`에 등록) |
| 컨테이너 로그 (`make logs`) | Docker Desktop 안 | `/var/lib/docker/containers/<id>/<id>-json.log`. 두 경우 모두 `compose.yaml`의 `x-logging`이 컨테이너당 10MB × 3개(최대 30MB)로 제한 |
| Basic Memory 앱 로그 | `.local-data/config/basic-memory.log` | `/srv/basic-memory/config/basic-memory.log`. Basic Memory가 10MB마다 교체하고 5개를 보관 |

**Verified (0.23.2):** 기본 프로젝트 `main`은 `/app/data/basic-memory`에 생성됩니다.

**Verified (0.23.2):** Basic Memory 앱 로그의 교체 주기(10MB, 5개 보관)는 소스 `src/basic_memory/utils.py`의 `setup_logging`에서 확인했습니다.

`.env`와 `backups/`는 main 체크아웃에만 둡니다(`.local-data/`는 `make local-up`을 실행한 체크아웃마다 생기는 로컬 테스트 데이터). Makefile은 어느 체크아웃에서 실행하든 main 체크아웃의 `.env`를 읽고, `backup`은 main 체크아웃의 `backups/`에 저장합니다.

## 신뢰 경계

- **Verified:** Basic Memory에는 인증이 없습니다.
- 접근 제어는 `tailscale` 모드에서는 전적으로 Tailscale의 기기 인증과 정책에 맡기고, `ssh` 모드에서는 클라우드 IAM과 SSH 키에 맡깁니다.
- 컨테이너 포트는 `127.0.0.1`에만 바인딩하고, Serve는 tailnet 전용(Funnel off)이며, GCP 방화벽에는 VPC 밖의 소스를 허용하는 인바운드 규칙이 없습니다. `default-allow-rdp`·`default-allow-icmp`는 지우고, `default-allow-ssh`는 Tailscale SSH를 확인한 뒤 지웁니다. `default-allow-internal`은 VPC 내부(`10.128.0.0/9`) 전용이라 둡니다.
- `ssh` 모드는 Tailscale을 쓰지 않습니다. VPC 밖 인바운드는 IAP 대역의 22번 하나이고, 인증은 Google 계정 IAM과 SSH 키입니다. 모든 터널은 기기의 `127.0.0.1`에만 열리고, `verify`가 VM의 Tailscale 꺼짐과 sshd 키 전용을 검사합니다. 한 VM에서 두 모드를 함께 쓰지 않습니다([access-modes ADR](decisions/adr-2026-10-15-cz8c26gp-access-modes.md)).
- 자동 검증 범위: `tests/repo-config.bats`(설정 파일)와 `make verify`/`make probe`(8737·3000 바인딩, Serve 포트별 대상과 Funnel, SilverBullet 로그인·셸 꺼짐, 공인 IP의 22·80·443·8443·8737·3000). `BM_WEB=on`이면 게이트웨이 포트 8738의 `127.0.0.1` 바인딩과 공인 IP의 8738 차단, 공개 URL `https://<BM_WEB_HOST>`의 OAuth 검사(공개 IPv4로만 풀림, 토큰 없는 `401`과 `resource_metadata`, 보호 리소스·인가 서버 메타데이터, 외부 redirect URI 등록 거절)도 봅니다. `ssh` 모드의 `verify`는 Serve 검사 대신 VM의 Tailscale 꺼짐과 sshd 키 전용을 임시 터널로 검사합니다. 방화벽 규칙과 tailnet 정책은 VM에서 읽을 수 없어 [운영 런북](runbooks/rbk-2026-10-12-t79ex2ny-operations.md)의 Exposure audit으로 수동 점검합니다.
- SilverBullet은 로그인(`SB_USER`)이 있어야 열리고, 셸 명령은 꺼져 있으며(`SB_SHELL_BACKEND=off`), Basic Memory와 다른 Docker 네트워크에 있습니다. 노트 폴더만 마운트해서 Basic Memory DB와 설정을 보지 못합니다.
- 웹 커넥터(`BM_WEB=on`)는 신뢰 경계를 하나 더합니다. 공개되는 것은 Cloudflare 호스트명 하나이고, `cloudflared`는 `web` 네트워크에만 있어 `gateway`에만 닿습니다. `gateway`가 토큰, GitHub 사용자 id, 도구 허용 목록을 강제하고 클라이언트의 `Authorization`을 Basic Memory로 넘기지 않습니다. 차단은 세 겹입니다: `BM_WEB=off` 배포(또는 `cloudflared` 정지), `BM_WEB_JWT_KEY` 교체, claude.ai 커넥터와 GitHub OAuth App 삭제([런북](runbooks/rbk-2026-10-27-x9h4zzdh-web-connector.md)). 노트 내용은 Cloudflare edge에서 평문으로 지나갑니다.
- 회사 프로젝트의 기억도 VM에 저장됩니다. 색인과 에이전트가 읽는 노트는 지시가 아니라 참고 자료로 다룹니다([스펙](specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md) §4).
- 비밀값은 다섯 가지입니다. Tailscale 인증 키는 저장소와 디스크에 남지 않습니다. 나머지(SilverBullet 로그인 `SB_USER`, 웹 커넥터의 `BM_WEB_GITHUB_CLIENT_SECRET`·`BM_WEB_JWT_KEY`·`BM_WEB_TUNNEL_TOKEN`)는 main 체크아웃 `.env`(ignore 대상)와 VM `/opt/basic-memory/.env`(권한 600)에만 있고, 스크립트는 ssh·curl 표준입력으로만 넘깁니다.

## 자원과 비용

- 1GB RAM에 스왑 1GB입니다. 부트스트랩이 스왑 파일을 만들고 `make status`는 스왑이 없으면 경고합니다([vm-sizing ADR](decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)).
- **Verified (2026-10-12):** 무료 등급 조건: e2-micro 1대, 30GB 표준 영구 디스크, 월 1GB 아웃바운드. Spot VM과 balanced 디스크는 무료가 아닙니다.
- 정지 후 시작하면 외부 IP가 바뀝니다. `.env`의 `BM_VM_PUBLIC_IP`를 갱신해야 `verify`가 맞는 IP를 검사합니다.
- **Open question:** 외부 IPv4 요금이 무료 등급에 포함되는지는 아직 확인하지 못했습니다. 배포 다음 날 SKU별 청구를 확인합니다([운영 런북](runbooks/rbk-2026-10-12-t79ex2ny-operations.md)의 비용 점검).

## 주요 흐름

- **배포:** `make deploy` → compose와 VM용 `.env`(권한 600, `SB_USER` 포함) 전송 → `docker compose pull` → 공간 파일 쓰기(`sync-sb-space.sh`. 노트 `.gitignore`가 바뀌었으면 `.gitignore`만 쓰고 Basic Memory만 다시 만든 뒤 관리 페이지·`index.md` 쓰기) → `up -d --wait`. `BM_WEB=on`이면 `gateway/` 파일도 올리고 `COMPOSE_PROFILES=web,tunnel`로 `gateway`·`cloudflared`를 띄우며, `off`면 남은 두 컨테이너를 지움
- **검증:** `make verify` → tailnet URL(`ssh` 모드는 임시 터널 `127.0.0.1:28737`·`23000`)로 MCP 왕복(initialize, tools/list, 쓰기·읽기·삭제) → 8443의 SilverBullet 로그인·쿠키·셸 꺼짐 → 포트 바인딩(8737, 3000) → Serve 포트별 대상, tailnet 전용 → 공인 IP 포트 차단. `make probe`는 노트를 쓰지 않고 SilverBullet에 로그인하지 않습니다. `BM_WEB=on`이면 공개 URL의 OAuth 검사(토큰 없는 401, 메타데이터, 외부 redirect URI 등록 거절, 공개 IPv4 해석)와 게이트웨이 포트 바인딩도 봅니다.
- **백업:** `make backup` → 컨테이너 정지(재시작은 정지 전에 예약) → 파일별 체크섬 manifest → `/srv/basic-memory`를 tar로 받아옴(임베딩 모델 캐시 `config/fastembed_cache/`는 제외하며, 복원 뒤 첫 사용 때 Basic Memory가 다시 내려받음) → sha256 저장 → 세 파일을 최종 이름으로 rename → 컨테이너 재시작. 아카이브는 main 체크아웃의 `backups/`에 저장됩니다.
- **기억 미러:** SessionStart·Stop hook → `make memory-sync HOOK=1` → Mac의 Claude Code·Codex 기억 파일(`*.md`)을 `agent-memory/<프로젝트 키>/<에이전트>/<기기>/`로 백그라운드 전송(바뀐 것만, 사라진 원본은 노트도 삭제). SessionStart → `make memory-index` → 다른 Mac·에이전트의 노트 색인(`Basic Memory index:`)을 에이전트 컨텍스트에 넣음. 터널이 없으면 경고 한 줄만 남기고 끝남
- **복원:** `make restore` → 정지 → 임시 경로에 압축 해제 → manifest 대조 → 저장소 compose.yaml 적용 → 데이터 교체(기존은 `.prev-*`) → Basic Memory가 멈춘 동안 공간 파일 쓰기(`sync-sb-space.sh`) → 기동 → verify. 정지 이후 실패하면 이전 데이터와 compose로 자동 롤백

관련 결정: [basic-memory-on-gcp-tailscale ADR](decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md), [vm-sizing ADR](decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md), [web-ui-silverbullet ADR](decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md), [access-modes ADR](decisions/adr-2026-10-15-cz8c26gp-access-modes.md), [web-connector ADR](decisions/adr-2026-10-22-fcvznmdc-web-connector.md)
