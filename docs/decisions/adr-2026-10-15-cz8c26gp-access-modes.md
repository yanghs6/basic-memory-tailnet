---
status: accepted
date: 2026-10-15
---

# ADR cz8c26gp: VM마다 접속 방식 하나 (Tailscale 또는 SSH 터널)

- 설계: [접속 방식 설계](../specs/spec-2026-10-15-jr59pvyf-access-modes.md)

## 맥락

- 사무실 네트워크는 HTTPS `controlplane.tailscale.com`을 막아 Tailscale로 VM에 닿을 수 없습니다. GCP IAP의 터널 엔드포인트(`tunnel.cloudproxy.app`)는 열려 있습니다(설계 §3, 2026-10-14~15 측정).
- 다른 사람도 이 저장소를 쓸 수 있어야 하므로, 한 사람의 네트워크 사정에 맞춘 예외 대신 설치할 때 고르는 구조가 필요합니다.
- 컨테이너는 VM의 `127.0.0.1`에만 열려 있고, IAP는 VM의 내부 IP로만 접속합니다. 그래서 IAP로는 sshd(22)를 거쳐 SSH 로컬 포워딩으로 들어가야 합니다.

## 결정

1. `.env`의 `BM_ACCESS`로 VM마다 접속 방식 하나를 고릅니다: `tailscale`(지금 구조) 또는 `ssh`(SSH 호스트 별칭과 `make tunnel`). 비어 있으면 `tailscale`입니다.
2. `make access-check`는 지금 네트워크에서 각 경로가 되는지 보고하고 추천만 합니다. 모드는 사람이 정합니다. 설치하는 기기는 지금 네트워크 하나만 보기 때문입니다.
3. 스크립트는 `ssh` 모드에서 SSH 별칭만 압니다. GCP에서 그 별칭을 IAP로 만드는 방법은 [VM 런북](../runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 8단계에 있습니다. 스크립트에는 클라우드 이름이 들어가지 않습니다.
4. `make tunnel`은 앞단에서 돌고, 끊기면 다시 붙지 않고 실패합니다. 로컬 포트는 18737(MCP)·13000(웹 UI)이고 `127.0.0.1`에만 바인딩합니다.
5. `ssh` 모드의 `verify`는 VM의 Tailscale이 로그인 상태가 아닌지와 sshd가 키 전용인지 검사합니다.
6. 지금 VM은 [access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md)의 Task 8에서 `ssh` 모드로 옮깁니다.

## 결과

- `ssh` 모드에서 VPC 밖 인바운드는 IAP 대역(`35.235.240.0/20`)의 22번 하나입니다. 인증은 Google 계정 IAM과 SSH 키 두 겹이고, 새 비밀값은 없습니다.
- `ssh` 모드에서는 MCP를 쓰는 동안 각 기기가 `make tunnel`을 띄워 둬야 합니다. IAP는 한 시간 동안 활동이 없으면 연결을 끊습니다.
- **Assumption:** Windows는 WSL2에서 Make 타깃을, PowerShell에서 터널 명령 한 줄을 씁니다. 검증하지 않았습니다.
- [access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md) Task 8의 확인 결과(IAP API 필요 여부, 무활동 끊김, 백업 시간)는 이 ADR의 "이전 결과" 절에 적습니다.

## 이전 결과

[access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md)의 Task 8(2026-10-15~16)에서 지금 VM(`agent-hub-01`)을 `ssh` 모드로 옮겼습니다. 명령과 출력은 access-modes 계획의 Progress log에 있습니다.

- **Verified (2026-10-15):** IAP API(`iap.googleapis.com`)를 켜지 않고도 터널이 열립니다. `ssh -o StrictHostKeyChecking=accept-new ubuntu@agent-hub-iap true`가 0으로 끝났고, 2026-10-16 `gcloud services list --enabled --configuration=bm-personal`에도 `iap.googleapis.com`은 없습니다.
- **Verified (2026-10-15~16):** IAP로 SSH 연결을 여는 데 3.75~4.04초가 걸려 `ConnectTimeout=10`보다 짧습니다. `make verify`의 임시 터널은 4초 만에 열렸고, `make access-check`는 12.8~13.6초 걸립니다(대부분 Tailscale 조정 서버 timeout 대기).
- **Verified (2026-10-15):** VM의 Tailscale이 로그인 상태일 때 `make status`가 `WARNING: Tailscale is still logged in on the VM`을 냈습니다(`BackendState` `Running`). `sudo tailscale serve reset && sudo tailscale logout` 뒤에는 `sudo -n tailscale status --json`이 0으로 끝나고 `BackendState`가 `NeedsLogin`이며, `make status`는 `tailscale: not installed or logged out`입니다. ubuntu 사용자는 암호 없이 `sudo -n`을 씁니다.
- **Verified (2026-10-15):** Ubuntu 26.04 Minimal의 `sshd -T`가 `passwordauthentication no`, `kbdinteractiveauthentication no`를 출력해 sshd 설정은 바꾸지 않았습니다.
- **Verified (2026-10-15):** `make backup`은 Tailscale 경로에서 61.2초, IAP 경로에서 83.3초(1.4배) 걸렸습니다.
- **Verified (2026-10-15~16):** 사무실 네트워크(Tailscale 조정 서버 `blocked (timeout)`, 터널 엔드포인트 `HTTP 404`)에서 `make tunnel`을 띄우고 `claude -p`와 `codex exec`가 `list_memory_projects`로 `main`을 받았습니다. 2026-10-16 `make verify`는 `OK: automated VM checks passed (access: ssh)`로 끝났습니다.
- **Reported (2026-10-16, 사용자):** 집 네트워크에서도 `make access-check`, `make tunnel`, 두 클라이언트의 도구 호출, 웹 UI 로그인이 됩니다. 이 Mac 말고 바꿀 기기는 없습니다.
- **Reported (2026-10-16, 사용자):** `make tunnel`을 띄운 채 70분 동안 MCP를 쓰지 않은 뒤에도 `claude -p` 호출이 `main`을 받았고 `tunnel closed`가 없었습니다. `ServerAliveInterval=30`이 IAP의 한 시간 무활동 끊김을 막는 것으로 봅니다.
- **Reported (2026-10-16, 사용자):** `make tunnel`을 Ctrl-C로 끝내도 `tunnel closed (exit 255) ... check the ProxyCommand` 안내가 나옵니다. [access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md)의 Follow-up으로 남깁니다.
- 패키지(설계 §14의 3): 사용자가 VM의 Tailscale은 로그아웃만 하고 패키지는 남기기로 정했습니다. 롤백할 때 새 인증 키로 `make vm-bootstrap`만 다시 하면 됩니다. Tailscale admin console의 `agent-hub` 기기는 사용자가 지웠습니다.
- **Verified (2026-10-16):** GCP 방화벽에서 VPC 밖 소스를 허용하는 인바운드 규칙은 `allow-iap-ssh`(`35.235.240.0/20`, `tcp:22`) 하나입니다.
