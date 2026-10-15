# ADR 0006: VM마다 접속 방식 하나 (Tailscale 또는 SSH 터널)

- 상태: Accepted (계획 12 병합일)
- 설계: [접속 방식 설계](../specs/2026-10-15-access-modes-design.md)

## 맥락

- 사무실 네트워크는 HTTPS `controlplane.tailscale.com`을 막아 Tailscale로 VM에 닿을 수 없습니다. GCP IAP의 터널 엔드포인트(`tunnel.cloudproxy.app`)는 열려 있습니다(설계 §3, 2026-10-14~15 측정).
- 다른 사람도 이 저장소를 쓸 수 있어야 하므로, 한 사람의 네트워크 사정에 맞춘 예외 대신 설치할 때 고르는 구조가 필요합니다.
- 컨테이너는 VM의 `127.0.0.1`에만 열려 있고, IAP는 VM의 내부 IP로만 접속합니다. 그래서 IAP로는 sshd(22)를 거쳐 SSH 로컬 포워딩으로 들어가야 합니다.

## 결정

1. `.env`의 `BM_ACCESS`로 VM마다 접속 방식 하나를 고릅니다: `tailscale`(지금 구조) 또는 `ssh`(SSH 호스트 별칭과 `make tunnel`). 비어 있으면 `tailscale`입니다.
2. `make access-check`는 지금 네트워크에서 각 경로가 되는지 보고하고 추천만 합니다. 모드는 사람이 정합니다. 설치하는 기기는 지금 네트워크 하나만 보기 때문입니다.
3. 스크립트는 `ssh` 모드에서 SSH 별칭만 압니다. GCP에서 그 별칭을 IAP로 만드는 방법은 [VM 런북](../runbooks/gcp-vm.md) 8단계에 있습니다. 스크립트에는 클라우드 이름이 들어가지 않습니다.
4. `make tunnel`은 앞단에서 돌고, 끊기면 다시 붙지 않고 실패합니다. 로컬 포트는 18737(MCP)·13000(웹 UI)이고 `127.0.0.1`에만 바인딩합니다.
5. `ssh` 모드의 `verify`는 VM의 Tailscale이 로그인 상태가 아닌지와 sshd가 키 전용인지 검사합니다.
6. 지금 VM은 계획 12의 Task 8에서 `ssh` 모드로 옮깁니다.

## 결과

- `ssh` 모드에서 VPC 밖 인바운드는 IAP 대역(`35.235.240.0/20`)의 22번 하나입니다. 인증은 Google 계정 IAM과 SSH 키 두 겹이고, 새 비밀값은 없습니다.
- `ssh` 모드에서는 MCP를 쓰는 동안 각 기기가 `make tunnel`을 띄워 둬야 합니다. IAP는 한 시간 동안 활동이 없으면 연결을 끊습니다.
- Windows는 WSL2에서 Make 타깃을, PowerShell에서 터널 명령 한 줄을 씁니다. 검증하지 않았습니다(Assumption).
- 계획 12 Task 8의 확인 결과(IAP API 필요 여부, 무활동 끊김, 백업 시간)는 이 ADR의 "이전 결과" 절에 적습니다.

## 이전 결과

계획 12의 Task 8에서 채웁니다.
