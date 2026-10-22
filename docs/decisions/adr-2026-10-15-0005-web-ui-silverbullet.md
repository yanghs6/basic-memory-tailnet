---
status: accepted
date: 2026-10-14
---

# ADR 0005: 웹 UI로 SilverBullet

- 설계: [SilverBullet 웹 UI 설계](../specs/spec-2026-10-14-silverbullet-web-ui.md)

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

## 근거

**Verified (2026-10-14 스파이크와 계획 10):**
- SilverBullet 서버는 1.7~10.6 MiB이고, 색인은 브라우저(IndexedDB)에서 합니다.
- 위키링크, Linked Mentions, `Graph: Explore`, 트리, 목차가 내장 기능만으로 동작합니다.
- 에이전트가 쓴 내용은 5초 안에 열린 페이지에 반영되고, SilverBullet에서 쓴 내용은 Basic Memory `search_notes`에 반영됩니다.
- 새 페이지 frontmatter를 SilverBullet 훅이 미리 채우면 Basic Memory가 파일을 다시 쓰지 않습니다. 그래서 줄바꿈이 사라지지 않습니다(훅 전 2/2 손실, 훅 뒤 0/2).
- 인증 없는 SilverBullet은 다른 사이트의 단순 POST로 셸을 실행하고 프록시를 엽니다. `SB_USER`와 `SB_SHELL_BACKEND=off`로 막습니다.
- 계획 10의 로컬 확인(2026-10-15, 새 브라우저 origin)에서 대시보드 일곱 절, 트리·목차 기본 배치, 테마, 글꼴, 정보 줄, 노트 검색, 그래프가 동작했습니다. 새 페이지의 줄바꿈이 남았고, Basic Memory에는 노트만 색인됐습니다.
- 계획 10의 로컬 확인 결과는 계획 10 파일(`docs/plans/plan-2026-10-14-10-web-ui-local.md`)의 Progress log에 있습니다.

## 결과

- 비밀값이 두 개가 됩니다: Tailscale 인증 키와 `SB_USER`. `SB_USER`는 main 체크아웃 `.env`와 VM `.env`(권한 600)에만 둡니다.
- SilverBullet은 Basic Memory 관계 타입을 그래프 엣지 이름으로 보여 주지 않습니다(모두 `mention`).
- 관찰 카테고리 글자(`[decision]`)를 누르면 카테고리가 지워집니다. 런북 경고와 업스트림 이슈로 대응합니다.
- SilverBullet 전용 페이지(`index`, `Library/`, `Inbox/` 등)는 노트 폴더의 `.gitignore`로 Basic Memory 색인에서 뺍니다.

## VM 측정

계획 11에서 두 컨테이너를 함께 띄운 뒤의 메모리·스왑 사용량을 여기에 기록합니다. OOM이 나면 [ADR 0002](adr-2026-10-12-0002-vm-sizing.md)를 다시 판단합니다.

**Verified (계획 11, 2026-10-15, `agent-hub-01` e2-micro amd64):**

컨테이너 열은 `docker stats`의 상주 메모리입니다. 스왑으로 나간 페이지는 세지 않습니다.

| 시점 | 명령 | SilverBullet | Basic Memory | 메모리 사용 | 스왑 사용 | OOM |
|---|---|---|---|---|---|---|
| 배포 전 | `make status` | - | - | 56% (`make status`는 %만 출력) | 490/1023 MB | - |
| 배포 직후 | `docker stats`, `free -m`, `dmesg` | 26.85 MiB | 252.4 MiB | 594/952 MB | 109/1023 MB | 없음 |
| 브라우저 확인 뒤 | 같음 | 6.6 MiB | 390.3 MiB | 695/952 MB | 402/1023 MB | 없음 |

- `make deploy`는 91초 걸렸습니다. Basic Memory를 다시 만들고 healthy가 되기까지 54초였습니다. 이미지가 캐시돼 있어서, 처음부터 받는 콜드 스타트(161~192초)보다 짧았습니다.
- 스왑 사용량은 배포 전 수준(490 MB)을 넘지 않았습니다.
- **Assumption:** 메모리 부담은 대부분 Basic Memory에서 옵니다. SilverBullet의 상주 메모리는 26.85 MiB에서 6.6 MiB로 줄었는데, 같은 때 스왑은 109 MB에서 402 MB로 늘었습니다. 그러니 6.6 MiB는 실제 사용량이 아니라 스왑으로 밀려난 결과일 수 있습니다. 다음에 잴 때는 컨테이너별 `memory.swap.current`도 기록합니다.
