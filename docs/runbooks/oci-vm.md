# VM 만들기 (OCI 콘솔)

## 1. SSH 키

키가 없으면 만듭니다: `ssh-keygen -t ed25519`. 공개키는 `~/.ssh/id_ed25519.pub`입니다.

## 2. 인스턴스 생성

Compute → Instances → **Create instance**:

| 항목 | 값 |
|---|---|
| Name | `bm-node` |
| Image | Canonical Ubuntu 24.04 (**Minimal 아님**, aarch64) |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU / 4 GB ([ADR 0002](../decisions/0002-vm-sizing.md)) |
| Networking | 새 VCN + public subnet, public IPv4 할당 |
| SSH keys | 1단계의 공개키 업로드 |
| Boot volume | 콘솔 기본값 (약 47 GB, 콘솔 표시 46.6 GB) |

A1 무료 한도는 합계 2 OCPU / 12 GB, 블록 볼륨 합계 200 GB입니다(**Verified**). 한도를 넘기지 마세요.

"Out of capacity" 오류가 나면 시간대를 바꿔 다시 시도합니다(서울·춘천 리전은 AD가 1개뿐).

## 3. 임시 SSH 규칙

Networking → VCN → Security Lists → Default security list → Ingress rules:
- 22번 규칙의 Source를 **본인 IP/32**로 바꿉니다(`curl -s https://ifconfig.me`로 확인). **Assumption:** 기본 보안 목록에는 `0.0.0.0/0`의 22번 허용 규칙이 있습니다.
- 22번 외의 TCP/UDP 인바운드 규칙은 추가하지 않습니다. 8737과 443은 열지 않습니다. **Assumption:** 기본 ICMP type 3 규칙은 남아 있습니다. 계획 05에서 확인합니다.

## 4. 기록

인스턴스의 Public IPv4를 `.env`의 `BM_VM_PUBLIC_IP`에 적고(사용자가 직접 편집), [부트스트랩](bootstrap.md)으로 넘어갑니다.
