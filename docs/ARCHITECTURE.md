# 아키텍처

## 토폴로지

```
[개인/회사 Mac] ── tailnet ──▶ https://bm-node.<tailnet>.ts.net/mcp
  에이전트, make deploy/verify/backup       │ Tailscale Serve (HTTPS, tailnet 전용)
  (Tailscale SSH)                           ▼
                                  OCI A1 VM (Ubuntu 24.04 ARM64, TCP/UDP 인바운드 없음)
                                    └ Docker: basic-memory:0.23.2@sha256
                                        127.0.0.1:8737 → :8000 /mcp
                                        /srv/basic-memory/knowledge → /app/data
                                        /srv/basic-memory/config    → /home/appuser/.basic-memory
```

## 구성 요소

| 구성 요소 | 위치 | 역할 |
|---|---|---|
| `Makefile` + `scripts/` | Mac | VM 수명주기의 유일한 제어 지점. SSH로 VM을 다룸 |
| `scripts/remote/bootstrap.sh` | VM (root) | Docker·Tailscale 설치, 데이터 디렉터리, Serve 설정 |
| `compose.yaml` | Mac(로컬 검증)·VM | Basic Memory 컨테이너 정의 (같은 파일) |
| Tailscale Serve | VM | tailnet HTTPS → `http://127.0.0.1:8737` |
| Tailscale SSH | VM | 부트스트랩 이후의 유일한 관리 경로 |
| `backups/` | Mac | `make backup` 결과물 (git ignore) |
| 리뷰·스킬 도구 | Mac | `scripts/check-git.sh`(git 정책 검사), `scripts/review.sh`와 `scripts/review-bash-guard.sh`(다른 벤더의 읽기 전용 리뷰), `.agents/skills/`(에이전트용 스킬; `.claude/skills/`는 링크), `docs/reviews/`(리뷰 기록) |

## 데이터 경로

| 데이터 | 로컬 | VM |
|---|---|---|
| Markdown 노트 | `.local-data/knowledge/basic-memory/` | `/srv/basic-memory/knowledge/basic-memory/` |
| SQLite 인덱스·설정·임베딩 모델 캐시 | `.local-data/config/` | `/srv/basic-memory/config/` |
| compose와 `.env` | 저장소 루트 | `/opt/basic-memory/` |

기본 프로젝트 `main`은 `/app/data/basic-memory`에 생성됩니다(**Verified**, 0.23.2).

## 신뢰 경계

- Basic Memory에는 인증이 없습니다(**Verified**). 접근 제어는 전적으로 Tailscale의 기기 인증과 정책에 맡깁니다.
- 컨테이너 포트는 `127.0.0.1`에만 바인딩하고, Serve는 tailnet 전용(Funnel off)이며, OCI에는 TCP/UDP 인바운드 규칙이 없습니다. **Assumption:** OCI 기본 ICMP type 3 규칙은 남아 있습니다. 계획 05에서 확인합니다.
- 자동 검증 범위: `tests/repo.bats`(설정 파일)와 `make verify`/`make probe`(바인딩, Serve 상태, 공인 IP의 22·80·443·8737). OCI 인바운드 규칙과 tailnet 정책은 VM에서 읽을 수 없어 [운영 런북](runbooks/operations.md)의 Exposure audit으로 수동 점검합니다.
- 비밀값은 Tailscale 인증 키 하나뿐이며, 저장소와 디스크에 남지 않습니다.

## 주요 흐름

- **배포:** `make deploy` → compose와 VM용 `.env` 전송 → `docker compose pull` → `up -d --wait`
- **검증:** `make verify` → tailnet URL로 MCP 왕복(initialize, tools/list, 쓰기·읽기·삭제) → 포트 바인딩 → Serve tailnet 전용 → 공인 IP 포트 차단. `make probe`는 같은 검사를 노트 쓰기 없이 합니다.
- **백업:** `make backup` → 컨테이너 정지(재시작은 정지 전에 예약) → 파일별 체크섬 manifest → `/srv/basic-memory`를 tar로 받아옴 → sha256 저장 → 세 파일을 최종 이름으로 rename → 컨테이너 재시작
- **복원:** `make restore` → 정지 → 임시 경로에 압축 해제 → manifest 대조 → 저장소 compose.yaml 적용 → 데이터 교체(기존은 `.prev-*`) → 기동 → verify. 정지 이후 실패하면 이전 데이터와 compose로 자동 롤백

관련 결정: [ADR 0001](decisions/0001-basic-memory-on-oci-tailscale.md), [ADR 0002](decisions/0002-vm-sizing.md)
