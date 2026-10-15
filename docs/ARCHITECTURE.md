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

GCP 인스턴스 이름(예: `agent-hub-01`)과 Tailscale 기기 이름(`agent-hub`)은 서로 다를 수 있습니다. 스크립트는 Tailscale 이름만 씁니다.

## 구성 요소

| 구성 요소 | 위치 | 역할 |
|---|---|---|
| `Makefile` + `scripts/` | Mac | VM 수명주기의 유일한 제어 지점. SSH로 VM을 다룸. gcloud는 쓰지 않음 |
| `scripts/remote/bootstrap.sh` | VM (root) | 스왑 파일 1GB, Docker·Tailscale 설치, 데이터 디렉터리, Serve 설정 |
| `compose.yaml` | Mac(로컬 검증)·VM | Basic Memory와 SilverBullet(웹 UI) 컨테이너 정의 (같은 파일) |
| `silverbullet/` + `scripts/sb-space.sh`·`sb-fonts.sh`·`verify-sb.sh` | Mac → 노트 폴더 | SilverBullet 공간 파일(노트 `.gitignore`, 관리 페이지 `Library/agent-hub/agent-hub.md`, 대시보드 `index.md`)과 글꼴을 쓰고, 로그인·셸 꺼짐을 검사. [web-ui-silverbullet ADR](decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md) |
| Tailscale Serve | VM | tailnet HTTPS 443 → `http://127.0.0.1:8737`(Basic Memory), 8443 → `http://127.0.0.1:3000`(SilverBullet) |
| Tailscale SSH | VM | 부트스트랩 이후의 유일한 관리 경로 |
| gcloud 명령 | Mac (사람이 실행) | VM 생성, 방화벽, 정지·시작. [VM 런북](runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md)의 명령. 항상 `--configuration=bm-personal` |
| `.env`, `backups/` | Mac, main 체크아웃 | 사용자 설정과 `make backup` 결과물 (둘 다 git ignore) |
| 리뷰·스킬 도구 | Mac | `scripts/check-git.sh`(git 정책 검사), `scripts/review.sh`와 `scripts/review-bash-guard.sh`(다른 벤더의 읽기 전용 리뷰), `.agents/skills/`(에이전트용 스킬; `.claude/skills/`는 링크, 구조 규칙은 `tests/skills.bats`와 [skill-structure ADR](decisions/adr-2026-10-13-m0xvj6rr-skill-structure.md)), `scripts/post-review.sh`·`scripts/review-record.sh`(리뷰 원문과 기록을 PR 코멘트로 게시), `docs/reviews/`([github-switch 계획](plans/plan-2026-10-13-k93wjt1a-github-switch.md)까지의 리뷰 기록) |
| GitHub `yanghs6/basic-memory-tailnet` | 원격 (공개) | PR과 squash 병합, CI `check`·`pr-rules`(`.github/workflows/`), ruleset `main`(`.github/rulesets/main.json`). 에이전트는 머신 계정으로 PR을 열고 사람만 승인·병합. [GitHub 런북](runbooks/rbk-2026-10-14-ppmby9v6-github.md) |

## 데이터 경로

| 데이터 | 로컬 | VM |
|---|---|---|
| Markdown 노트 | `.local-data/knowledge/basic-memory/` | `/srv/basic-memory/knowledge/basic-memory/` |
| SilverBullet 공간 파일 | 노트 폴더 안 `.gitignore`, `index.md`, `Library/agent-hub/`(관리 페이지와 글꼴), `.silverbullet.browser-sessions.json`(로그인 세션) | 같음. Basic Memory는 `.gitignore`와 기본 무시 목록(`.*`)으로 이 파일들을 색인하지 않음 |
| SQLite 인덱스·설정·임베딩 모델 캐시 | `.local-data/config/` | `/srv/basic-memory/config/` |
| `compose.yaml` | 명령을 실행한 체크아웃 루트(`make deploy`가 그 파일을 올림) | `/opt/basic-memory/` |
| `.env` | main 체크아웃 루트 | `/opt/basic-memory/` (VM용 `.env`는 `make deploy`가 생성) |
| 스왑 | 해당 없음 | `/swapfile` (1GB, `/etc/fstab`에 등록) |

기본 프로젝트 `main`은 `/app/data/basic-memory`에 생성됩니다(**Verified**, 0.23.2).

`.env`와 `backups/`는 main 체크아웃에만 둡니다(`.local-data/`는 `make local-up`을 실행한 체크아웃마다 생기는 로컬 테스트 데이터). Makefile은 어느 체크아웃에서 실행하든 main 체크아웃의 `.env`를 읽고, `backup`은 main 체크아웃의 `backups/`에 저장합니다.

## 신뢰 경계

- Basic Memory에는 인증이 없습니다(**Verified**). 접근 제어는 전적으로 Tailscale의 기기 인증과 정책에 맡깁니다.
- 컨테이너 포트는 `127.0.0.1`에만 바인딩하고, Serve는 tailnet 전용(Funnel off)이며, GCP 방화벽에는 VPC 밖의 소스를 허용하는 인바운드 규칙이 없습니다. `default-allow-rdp`·`default-allow-icmp`는 지우고, `default-allow-ssh`는 Tailscale SSH를 확인한 뒤 지웁니다. `default-allow-internal`은 VPC 내부(`10.128.0.0/9`) 전용이라 둡니다.
- 자동 검증 범위: `tests/repo.bats`(설정 파일)와 `make verify`/`make probe`(8737·3000 바인딩, Serve 포트별 대상과 Funnel, SilverBullet 로그인·셸 꺼짐, 공인 IP의 22·80·443·8443·8737·3000). 방화벽 규칙과 tailnet 정책은 VM에서 읽을 수 없어 [운영 런북](runbooks/rbk-2026-10-12-t79ex2ny-operations.md)의 Exposure audit으로 수동 점검합니다.
- SilverBullet은 로그인(`SB_USER`)이 있어야 열리고, 셸 명령은 꺼져 있으며(`SB_SHELL_BACKEND=off`), Basic Memory와 다른 Docker 네트워크에 있습니다. 노트 폴더만 마운트해서 Basic Memory DB와 설정을 보지 못합니다.
- 비밀값은 두 가지입니다. Tailscale 인증 키는 저장소와 디스크에 남지 않습니다. SilverBullet 로그인 `SB_USER`는 main 체크아웃 `.env`(git ignore)와 VM `/opt/basic-memory/.env`(권한 600)에만 있고, 스크립트는 ssh·curl 표준입력으로만 넘깁니다.

## 자원과 비용

- 1GB RAM에 스왑 1GB입니다. 부트스트랩이 스왑 파일을 만들고 `make status`는 스왑이 없으면 경고합니다([vm-sizing ADR](decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)).
- 무료 등급 조건: e2-micro 1대, 30GB 표준 영구 디스크, 월 1GB 아웃바운드(**Verified**, 2026-10-12). Spot VM과 balanced 디스크는 무료가 아닙니다.
- 정지 후 시작하면 외부 IP가 바뀝니다. `.env`의 `BM_VM_PUBLIC_IP`를 갱신해야 `verify`가 맞는 IP를 검사합니다.
- 외부 IPv4 요금이 무료 등급에 포함되는지는 **Open question**입니다. 배포 다음 날 SKU별 청구를 확인합니다([운영 런북](runbooks/rbk-2026-10-12-t79ex2ny-operations.md)의 비용 점검).

## 주요 흐름

- **배포:** `make deploy` → compose와 VM용 `.env`(권한 600, `SB_USER` 포함) 전송 → 공간 파일 쓰기(`sb-space.sh`, 노트 `.gitignore`가 바뀌었으면 `.gitignore`만) → `docker compose pull` → `.gitignore`가 바뀌었으면 Basic Memory만 먼저 다시 만든 뒤 관리 페이지·`index.md` 쓰기 → `up -d --wait`
- **검증:** `make verify` → tailnet URL로 MCP 왕복(initialize, tools/list, 쓰기·읽기·삭제) → 8443의 SilverBullet 로그인·쿠키·셸 꺼짐 → 포트 바인딩(8737, 3000) → Serve 포트별 대상, tailnet 전용 → 공인 IP 포트 차단. `make probe`는 노트를 쓰지 않고 SilverBullet에 로그인하지 않습니다.
- **백업:** `make backup` → 컨테이너 정지(재시작은 정지 전에 예약) → 파일별 체크섬 manifest → `/srv/basic-memory`를 tar로 받아옴(임베딩 모델 캐시 `config/fastembed_cache/`는 제외하며, 복원 뒤 첫 사용 때 Basic Memory가 다시 내려받음) → sha256 저장 → 세 파일을 최종 이름으로 rename → 컨테이너 재시작. 아카이브는 main 체크아웃의 `backups/`에 저장됩니다.
- **복원:** `make restore` → 정지 → 임시 경로에 압축 해제 → manifest 대조 → 저장소 compose.yaml 적용 → 데이터 교체(기존은 `.prev-*`) → Basic Memory가 멈춘 동안 공간 파일 쓰기(`sb-space.sh`) → 기동 → verify. 정지 이후 실패하면 이전 데이터와 compose로 자동 롤백

관련 결정: [basic-memory-on-gcp-tailscale ADR](decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md), [vm-sizing ADR](decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md), [web-ui-silverbullet ADR](decisions/adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md)
