# 운영

## 일상 명령

| 목적 | 명령 |
|---|---|
| 상태 점검 (주 1회) | `make status` |
| 읽기 전용 검사 (노트를 쓰지 않음) | `make probe` |
| 종단 검증 (테스트 노트를 쓰고 지움) | `make verify` |
| 로그 | `make logs` |
| 배포 (compose 변경 후) | `make deploy verify` |
| 백업 (주 1회 + 업그레이드 전) | `make backup` |
| 복원 | `make restore BACKUP=backups/bm-<시각>.tgz` (사용자가 자기 터미널에서 `yes` 입력. 저장소의 compose.yaml도 함께 적용하고, 실패하면 이전 상태로 자동 롤백, 끝나면 verify 실행) |

에이전트는 `vm-bootstrap`, `deploy`, `restore` 전에 사용자의 OK를 받습니다. `probe`, `status`, `logs`, `verify`, `backup`은 OK 없이 실행할 수 있습니다(`verify`는 테스트 노트를 쓰고 지우며, `backup`은 컨테이너를 잠깐 멈춥니다).

## 백업

- 결과물은 이 Mac의 `backups/`에만 있습니다(git ignore). Time Machine 등으로 Mac 밖에도 사본을 두세요.
- 백업 중에는 컨테이너가 몇 초 멈춥니다. SQLite 파일이 쓰는 도중에 복사되지 않게 하기 위해서입니다.
- 백업마다 `.sha256`(아카이브 무결성)과 `.manifest`(데이터 파일별 체크섬)가 함께 저장됩니다. 둘 중 하나라도 없으면 `make restore`가 거부합니다.
- 복원은 임시 경로에 먼저 풀고 manifest와 대조한 뒤에만 교체합니다. 기존 데이터는 `/srv/basic-memory.prev-<시각>`으로 옮겨지고, 실패하면 자동으로 되돌아갑니다(실패한 복원본은 `.failed-<시각>`에 남음).
- `.prev-*`와 `.failed-*` 삭제는 **사람만** 합니다. 에이전트는 지우지 않습니다. 결과를 확인한 뒤 직접: `ssh ubuntu@bm-node sudo rm -r /srv/basic-memory.prev-<시각>`

## 업그레이드·복구·진단

에이전트에게 스킬을 쓰라고 요청합니다.
- 업그레이드: `bm-upgrade`
- VM 회수·손상 후 복구: `bm-recover`
- 연결·MCP 문제: `bm-diagnose` (읽기 전용)

## Exposure audit

`make verify`/`make probe`는 VM 쪽에서 확인할 수 있는 것만 자동으로 검사합니다: `127.0.0.1` 바인딩, Serve가 tailnet 전용인지(Funnel off), 공인 IP의 22·80·443·8737 차단. 나머지 두 가지는 VM에서 읽을 수 없으므로, 배포 직후와 정책·네트워크를 바꾼 뒤에 손으로 점검하고 결과를 Incident log 아래 "점검 기록"에 남깁니다.

1. OCI 콘솔 → VCN → Security Lists(와 NSG가 있다면 NSG)에 **TCP/UDP Ingress rule이 없는지** 확인합니다. **Assumption:** 기본 ICMP type 3 규칙은 남아 있습니다(계획 05에서 확인).
2. Tailscale admin console → Access controls의 정책 `nodeAttrs`에 **`"funnel"`이 없는지** 확인합니다.

스크립트가 `Funnel is on for this node`라고 하면 먼저 정책의 `funnel` 속성을 지워 Funnel을 끄고, VM의 Serve 상태를 확인합니다(`ssh ubuntu@bm-node sudo tailscale serve status`). 그다음 Serve를 다시 설정합니다. **Assumption (계획 05에서 확인):** 부트스트랩 뒤에는 22번이 닫혀 있으므로 `make vm-bootstrap HOST=bm-node`를 Tailscale SSH로 실행해 Serve를 다시 설정합니다. 이 명령은 VM을 바꾸므로 사용자의 OK가 필요합니다.

## Idle reclamation

OCI는 7일 동안 CPU(95번째 백분위), 네트워크, 메모리(A1만 해당)가 **모두** 20% 미만인 Always Free VM을 회수할 수 있습니다(**Verified**).

- `make status`가 메모리 사용률 20% 미만 경고를 내면, 최신 백업이 있는지 먼저 확인하세요.
- VM 크기는 평소 메모리 사용률이 20%를 넘도록 정했습니다([ADR 0002](../decisions/0002-vm-sizing.md)). 경고가 계속되면 ADR 0002의 재평가 기준을 따르세요.
- 회수 알림 메일을 받거나 VM이 사라지면 `bm-recover` 스킬을 씁니다.

## Incident log

| 날짜 | 원인 | 사용한 백업 | 데이터 손실 구간 | 비고 |
|---|---|---|---|---|

### 점검 기록 (Exposure audit)

| 날짜 | OCI TCP/UDP 인바운드 규칙 수 | 정책 funnel 속성 | `make verify` | 점검자 |
|---|---|---|---|---|
