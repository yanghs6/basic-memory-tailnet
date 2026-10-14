# 운영

사람은 VM 대상 Make 타깃(`deploy`, `verify`, `backup`, `restore` 등)을 main 체크아웃에서 실행합니다. 에이전트는 자기 worktree에서 실행해도 되며, 그때도 `.env`와 `backups/`는 main 체크아웃의 것을 씁니다. 에이전트가 worktree에서 `deploy`·`restore`를 할 때는 먼저 `git diff main -- compose.yaml`이 아무것도 출력하지 않는지 확인합니다(bm-upgrade의 사용자 승인 배포는 예외. 아래 "배포·복원 전 이미지 점검"도 함께).

## 일상 명령

| 목적 | 명령 |
|---|---|
| 상태 점검 (주 1회) | `make status` |
| 읽기 전용 검사 (노트를 쓰지 않음) | `make probe` |
| 종단 검증 (테스트 노트를 쓰고 지움) | `make verify` |
| 로그 | `make logs` |
| 배포 (compose 변경 후) | `make deploy verify` |
| 백업 (주 1회 + 업그레이드 전) | `make backup` |
| 복원 | `make restore BACKUP=<백업 파일의 절대 경로>` (사용자가 자기 터미널에서 `yes` 입력. 저장소의 compose.yaml도 함께 적용하고, 실패하면 이전 상태로 자동 롤백, 끝나면 verify 실행) |

에이전트는 `vm-bootstrap`, `deploy`, `restore` 전에 사용자의 OK를 받습니다. `probe`, `status`, `logs`, `verify`, `backup`은 OK 없이 실행할 수 있습니다(`verify`는 테스트 노트를 쓰고 지우며, `backup`은 컨테이너를 잠깐 멈춥니다).

**배포·복원 전 이미지 점검:** `make status`의 컨테이너 이미지와 `grep 'image:' compose.yaml`이 같은지 확인합니다. 다르면 멈추고 사용자에게 묻습니다. 업그레이드 리뷰 중에는 VM이 main이 고정하지 않은 이미지로 돌 수 있고, 이때 옛 이미지를 새 버전이 손댄 데이터 위에 배포하면 안 되기 때문입니다([bm-upgrade 스킬](../../.agents/skills/bm-upgrade/SKILL.md)). 새로 만든 VM처럼 아직 아무것도 배포하지 않았다면 `make status`가 `could not query containers`로 끝납니다. 정상이므로 이미지 비교는 건너뜁니다. 이때 에이전트는 `git diff main -- compose.yaml`이 아무것도 출력하지 않는지만 확인하고, 사람은 main 체크아웃에서 실행하는지 확인합니다.

## 백업

- 결과물은 main 체크아웃의 `backups/`에 저장됩니다(git ignore, worktree에서 실행해도 같음). Time Machine 등으로 Mac 밖에도 사본을 두세요.
- worktree를 지우기 전에 그 안에 `backups/`가 없는지 확인합니다. `git worktree remove`는 git ignore 파일을 경고 없이 지웁니다.
- 백업 중에는 컨테이너가 몇 초 멈춥니다. SQLite 파일이 쓰는 도중에 복사되지 않게 하기 위해서입니다.
- 백업마다 `.sha256`(아카이브 무결성)과 `.manifest`(데이터 파일별 체크섬)가 함께 저장됩니다. 둘 중 하나라도 없으면 `make restore`가 거부합니다.
- 임베딩 모델 캐시(`config/fastembed_cache/`)는 백업에 포함하지 않습니다. 다시 내려받을 수 있고 심볼릭 링크를 담고 있어 복원 검사가 거부하기 때문입니다. 복원 뒤 Basic Memory가 처음 쓸 때 모델을 다시 내려받으므로 첫 검색·인덱싱은 평소보다 오래 걸릴 수 있습니다.
- 복원은 임시 경로에 먼저 풀고 manifest와 대조한 뒤에만 교체합니다. 기존 데이터는 `/srv/basic-memory.prev-<시각>`으로 옮겨지고, 실패하면 자동으로 되돌아갑니다(실패한 복원본은 `.failed-<시각>`에 남음).
- `.prev-*`와 `.failed-*` 삭제는 **사람만** 합니다. 에이전트는 지우지 않습니다. 결과를 확인한 뒤 직접: `ssh ubuntu@agent-hub sudo rm -r /srv/basic-memory.prev-<시각>`

## 업그레이드·복구·진단

에이전트에게 스킬을 쓰라고 요청합니다.
- 업그레이드: `bm-upgrade`
- VM이 삭제됐거나 쓸 수 없을 때(정지만 된 VM은 아래 "정지된 VM"): `bm-recover`
- 연결·MCP 문제: `bm-diagnose` (읽기 전용)

## 정지된 VM

VM이 정지돼 있으면(`TERMINATED`) 다시 만들지 않고 시작합니다. 디스크의 데이터가 그대로 있어서, 재구축하면 마지막 백업 이후의 노트를 잃습니다.

1. 사용자가 상태를 확인하고 시작합니다. 새 셸이면 먼저 [rbk-2026-10-12-tcjs7m6x-gcp-vm.md](rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 0단계의 `INSTANCE`, `ZONE`을 설정합니다.

   ```bash
   gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(status)'
   gcloud compute instances start "$INSTANCE" --zone="$ZONE" --configuration=bm-personal
   ```

2. 정지 후 시작하면 외부 IP가 바뀝니다([rbk-2026-10-12-tcjs7m6x-gcp-vm.md](rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 5단계의 조회 명령). 새 IP를 `.env`의 `BM_VM_PUBLIC_IP`에 적습니다.
3. `make status`와 `make probe`로 확인합니다. 실제 장애였다면 Incident log에 행을 추가합니다.

## VM 재구축 순서

VM이 삭제됐거나 시작되지 않거나 데이터가 손상됐을 때만 합니다(에이전트의 `bm-recover` 스킬이 같은 순서를 따릅니다).

1. 최신 백업(`.sha256`과 `.manifest` 포함)이 main 체크아웃의 `backups/`에 있는지 확인합니다.
2. [rbk-2026-10-12-tcjs7m6x-gcp-vm.md](rbk-2026-10-12-tcjs7m6x-gcp-vm.md)대로 VM을 다시 만들고 방화벽을 정리합니다. 옛 인스턴스와 디스크는 복원이 검증되기 전에는 지우지 않습니다.
3. [rbk-2026-10-12-ha5w72pm-bootstrap.md](rbk-2026-10-12-ha5w72pm-bootstrap.md) 1단계(옛 `agent-hub` 기기 삭제, 호스트 키 정리)와 2~4단계(부트스트랩, Tailscale SSH 확인, `default-allow-ssh` 삭제)를 합니다.
4. 배포 전에 `make status`의 이미지와 `compose.yaml`의 `image:`를 비교합니다(위의 이미지 점검). 아직 아무것도 배포하지 않은 VM에서는 `make status`가 `could not query containers`로 끝나는 것이 정상이며 비교는 건너뜁니다(에이전트는 `git diff main -- compose.yaml`이 비어 있는지만 확인). 그다음 `make deploy`, `make restore BACKUP=<절대 경로>`를 합니다.
5. Exposure audit을 다시 합니다(방화벽을 새로 만들었으므로).
6. Incident log와 점검 기록에 행을 추가합니다.

## Exposure audit

`make verify`/`make probe`는 VM 쪽에서 확인할 수 있는 것만 자동으로 검사합니다: `127.0.0.1` 바인딩, Serve가 tailnet 전용인지(Funnel off), 공인 IP의 22·80·443·8737 차단. 나머지 두 가지는 VM에서 읽을 수 없으므로, 배포 직후와 방화벽·정책을 바꾼 뒤(VM 재구축 포함)에 손으로 점검하고 결과를 Incident log 아래 "점검 기록"에 남깁니다.

1. 방화벽 규칙 중 **VPC 밖의 소스를 허용하는 인바운드 규칙이 0개인지** 확인합니다. `default-allow-internal`의 `10.128.0.0/9`만 남아야 합니다.

   ```bash
   gcloud compute firewall-rules list --configuration=bm-personal --format='table(name,direction,disabled,sourceRanges.list(),allowed[].map().firewall_rule().list())'
   ```

   `direction`이 `INGRESS`, `disabled`가 `False`이면서 소스가 `10.128.0.0/9`가 아닌 행이 없어야 합니다(`default-allow-ssh`는 부트스트랩이 끝나면 지워져 있어야 함). **Assumption:** 기본 `default` 네트워크 하나만 쓰는 프로젝트입니다.
2. Tailscale admin console → Access controls의 정책 `nodeAttrs`에 **`"funnel"`이 없는지** 확인합니다.

스크립트가 `Funnel is on for this node`라고 하면 먼저 정책의 `funnel` 속성을 지워 Funnel을 끄고, VM의 Serve 상태를 확인합니다(`ssh ubuntu@agent-hub sudo tailscale serve status`). 그다음 Serve를 다시 설정합니다. **Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 14):** 부트스트랩 뒤에는 22번이 닫혀 있으므로 `make vm-bootstrap HOST=agent-hub`를 Tailscale SSH로 실행해 Serve를 다시 설정합니다. 노드가 이미 tailnet에 있으면 키 프롬프트에 아무것도 넣지 않고 Enter만 누릅니다. 이 명령은 VM을 바꾸므로 사용자의 OK가 필요합니다. 또한 **Verified (2026-10-13, Tailscale v1.104.1 소스 `cmd/tailscale/cli/serve_v2.go`의 `applyFunnel`):** `serve --bg`는 자기가 설정하는 포트(443)의 Funnel만 끄고(`Removing Funnel for ...` 출력) 다른 포트의 Funnel은 그대로 둡니다. 그래서 `tailscale funnel status`에 443 말고 다른 포트의 Funnel이 남아 있으면 `ssh ubuntu@agent-hub sudo tailscale serve reset`을 사용자 OK 후에 실행하고, Serve를 다시 설정합니다.

## 비용 점검

GCP 무료 등급에서 과금이 생기지 않는지 확인합니다. 외부 IPv4 요금($0.005/h, 약 $3.65/월)이 무료 등급에 포함되는지는 **Open question**입니다.

- 배포 **다음 날**과 **매월 초**에 청구 보고서를 SKU별로 봅니다: Cloud Console → Billing → Reports에서 프로젝트로 필터링하고 Group by를 SKU로 둡니다(**Assumption:** 메뉴 이름은 바뀔 수 있고, 보고서에는 하루쯤 지연이 있음).
- e2-micro 인스턴스, standard persistent disk, 외부 IP, 네트워크(아웃바운드) SKU의 금액이 모두 0이어야 합니다. Budget 알림(월 $1)이 오면 같은 보고서를 확인합니다.
- 0이 아니면 사용자가 "그 금액을 감수"와 "다른 호스트" 중에서 결정합니다. 결과는 [basic-memory-on-gcp-tailscale ADR](../decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md)에 Verified로 남깁니다.
- 무료 아웃바운드는 월 1GB(북미 → 전 세계, 중국·호주 제외)입니다. Tailscale DERP 중계 트래픽도 포함되므로 같은 보고서로 확인합니다.

## Incident log

| 날짜 | 원인 | 사용한 백업 | 데이터 손실 구간 | 비고 |
|---|---|---|---|---|

### 점검 기록 (Exposure audit)

| 날짜 | VPC 밖 소스를 허용하는 인바운드 규칙 수 | 정책 funnel 속성 | `make verify` | 점검자 |
|---|---|---|---|---|
| 2026-10-13 | 0 (`default-allow-ssh` 삭제 후 `default-allow-internal` `10.128.0.0/9`만 남음) | 없음: 2026-10-12에 사용자가 붙여 준 정책 JSON의 `nodeAttrs`에 없음, 2026-10-13 VM 노드 `CapMap`에 funnel 권한 없음 | 통과 (MCP 왕복, 127.0.0.1 바인딩, Serve tailnet only, 22·80·443·8737 차단) | claude-code, 사용자 |
