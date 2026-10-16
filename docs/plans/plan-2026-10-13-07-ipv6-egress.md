---
status: backlog
spec: none
---

# 07 IPv6 Egress Plan (backlog)

> 계획 05([완료된 계획](plan-2026-10-07-05-vm-rollout.md))가 머지된 뒤에 brainstorming → 스펙 → 계획 순서를 거쳐야 실행할 수 있습니다. 이 문서는 실행 계획이 아니라 조사 결과와 질문 목록입니다.

**Goal:** 유료 외부 IPv4를 없애고, 무료인 외부 IPv6만으로 VM이 계속 동작하게 한다(Tailscale, apt, Docker, 이미지 업데이트, 모델 다운로드, 복구).

## 배경

- 공식 가격표 https://cloud.google.com/vpc/network-pricing 원문: "Static and ephemeral IP addresses in use on standard VM instances $0.005 / 1 hour", 무료 등급은 "one hour per month per account". 월 약 $3.65입니다.
- 같은 페이지 원문: "You are not charged for external IPv6 address ranges that are assigned to subnets or for external IPv6 addresses that are assigned to VM instances."
- 2026-10-13 사용자 결정: 나중에 IPv6로 전환하고, 지금은 백로그에만 등록합니다. 근거와 조회 결과는 계획 05의 Progress log(항목 25 사전 조사, IPv4 Open question 행)에 있습니다.

## 확인된 사실

- **Verified (2026-10-13, `dig @1.1.1.1 AAAA`):** AAAA가 있는 호스트: `controlplane.tailscale.com`, `derp10-all.tailscale.com`, `pkgs.tailscale.com`, `download.docker.com`, `huggingface.co`, `us-west1.gce.archive.ubuntu.com`, `security.ubuntu.com`, `pkg-containers.githubusercontent.com`.
- **Verified (2026-10-13, `dig @1.1.1.1 AAAA`):** AAAA가 없는 호스트: `ghcr.io`, `cdn-lfs.huggingface.co`. IPv6 전용 VM은 이 둘에 직접 닿지 못합니다(이미지 pull, 모델 파일 다운로드).
- **Verified (2026-10-13, https://docs.cloud.google.com/vpc/docs/subnets):** "Subnets with IPv6 address ranges aren't supported on auto mode VPC networks or legacy networks." IPv6 서브넷은 custom mode에서만 됩니다. 추가하려면 "you must first convert an auto mode VPC network to custom mode". 이 변환이 되돌릴 수 없는지는 해당 페이지에 없습니다(**Open question**).
- **Verified (같은 페이지):** 서브넷 스택 타입은 IPv4 전용, 듀얼 스택, IPv6 전용 세 가지입니다. IPv4 전용 → 듀얼 스택 변경은 됩니다. "You can't change a dual-stack or IPv4-only subnet to IPv6-only."
- **Verified (https://docs.cloud.google.com/compute/docs/ip-addresses/configure-ipv6-address):** 기존 VM은 `gcloud compute instances network-interfaces update INSTANCE_NAME --stack-type=IPV4_IPV6 --zone=ZONE`로 듀얼 스택이 됩니다. VM 중지 요구는 페이지에 없습니다(서브넷을 바꿀 때만 중지). 서브넷의 IPv6 access type이 인스턴스에 상속됩니다. "IPv6-only instances are supported with only Ubuntu and Debian OS images." "You can't change the stack type of an IPv6-only instance." 따라서 기존 VM을 IPv6 전용으로 바꾸는 것은 불가능하고, 재생성이 필요합니다.
- **Assumption:** 현재 Ubuntu 26.04 Minimal이 IPv6 전용 VM 이미지 조건을 만족하는지는 확인하지 못했습니다.
- **Assumption:** 외부 IPv4 제거는 `gcloud compute instances delete-access-config`로 할 수 있을 것입니다. 위 페이지에는 접근 설정 제거 절차가 없어 공식 문서로 확인하지 못했습니다.
- **Verified (https://docs.cloud.google.com/compute/docs/metadata/overview):** 메타데이터 서버 주소는 `metadata.google.internal`, `169.254.169.254`, IPv6 `fd20:ce::254`입니다. IPv6 주소는 "(only for IPv6-only VMs)"로 표시됩니다.
- **Verified (https://docs.cloud.google.com/iap/docs/using-tcp-forwarding):** "Your VM instance doesn't require an external IP address for IAP TCP forwarding." 방화벽은 `35.235.240.0/20`에서의 ingress를 허용해야 하고, "For IPv6 VMs, use the following IP range: `2600:2d00:1:7::/64`". 이 페이지에는 요금 언급이 없습니다(**Open question**).
- **Verified (https://docs.cloud.google.com/artifact-registry/docs/repositories/remote-overview):** Artifact Registry remote repository는 Docker 업스트림으로 `https://ghcr.io`를 지정할 수 있습니다. 무료 등급·요금은 해당 페이지에 없고 Artifact Registry 가격 페이지를 가리킵니다(**Open question**). VM에서 Artifact Registry에 IPv6로 닿는지도 확인하지 못했습니다(**Assumption**).
- **Verified (https://tailscale.com/kb/1082/firewall-ports):** DERP와 제어 서버 접속은 TCP 443 아웃바운드이고 IPv6 대역도 문서에 나옵니다. IPv6 전용 환경에서 `tailscaled`가 동작하는 것은 직접 확인하지 못했습니다(**Assumption**).
- **Open question:** Cloud NAT/NAT64 요금과 NAT64 지원 조건. 가격 페이지(https://cloud.google.com/nat/pricing)는 자동 조회로 본문을 읽지 못했습니다. 무료가 아니라는 점만 알려져 있고 금액은 미확인입니다. NAT64 문서도 읽지 못했습니다.
- **Assumption:** 사용자 사무실 네트워크에 IPv6가 없을 수 있습니다. 그러면 Mac에서 VM의 IPv6로 하는 노출 검사가 불가능합니다.

## 설계 질문

1. VPC 모드: `default` auto-mode를 custom으로 변환할 것인가, 새 custom VPC를 만들 것인가? 변환의 되돌림 가능 여부와 기존 방화벽 규칙(`default-allow-*`)의 운명은?
2. 스택 타입: 기존 VM을 듀얼 스택(내부 IPv4 유지, 외부 IPv4만 제거)으로 둘 것인가, IPv6 전용 VM으로 재생성할 것인가? 후자는 데이터 디스크 이전과 `restore`가 필요하고 메타데이터 서버 IPv6 접근 등 부작용이 있습니다.
3. 외부 IPv4 없이 `ghcr.io`(AAAA 없음)에서 이미지 업데이트를 어떻게 받을 것인가? Cloud NAT(요금 확인 필요), Artifact Registry remote repository(요금 확인 필요), Mac에서 pull 후 전송 중 무엇인가? `bm-upgrade` 흐름이 어떻게 바뀌는가?
4. 임베딩 모델 다운로드: `cdn-lfs.huggingface.co`(AAAA 없음)를 어떻게 받을 것인가? 모델 캐시 백업과 복구 경로에는 어떤 영향이 있는가?
5. `verify`/`probe`: IPv6 주소로 22·80·443·`BM_PORT` 차단을 어떻게 검사할 것인가? `BM_VM_PUBLIC_IP` 검증(IPv4 전용)을 IPv6로 확장하거나 대체할 때, IPv6가 없는 Mac에서는 검사를 건너뛸지 실패시킬지 정해야 합니다. 건너뛰면 노출 검증이 약해집니다.
6. 부트스트랩과 `bm-recover`: 공인 IPv4 없이 첫 SSH를 어떻게 할 것인가? IPv6 SSH(Mac의 IPv6 필요), IAP TCP forwarding, 콘솔 직렬 포트 중 무엇인가? IAP를 쓰면 방화벽에 `35.235.240.0/20`(IPv6 VM은 `2600:2d00:1:7::/64`)을 열어야 하는데 "제로 공개 ingress" 불변식과 어떻게 양립시킬 것인가?
7. IPv6 방화벽: 기본 규칙 구성은? Exposure audit(런북의 방화벽·tailnet 정책 수동 점검)에 IPv6 규칙 점검을 어떻게 넣을 것인가?
8. 비용: NAT/레지스트리/IAP 옵션 중 어느 것이 실제로 0원인가? 계획 05 완료 조건 5(SKU별 청구 0)와 같은 방식으로 어떻게 검증할 것인가?
9. 롤백: 전환 실패 시 외부 IPv4를 다시 붙이는 절차와, 그 사이 Tailscale 접속이 끊기지 않는지 확인하는 방법은?

## 영향 범위

외부 IPv4를 전제하는 위치(2026-10-13 `grep` 결과, 이 브랜치 기준):

- `.env.example:10-12` (`BM_VM_PUBLIC_IP` 설명과 값)
- `Makefile:13` (`export ... BM_VM_PUBLIC_IP`), `Makefile:69` (`vm-bootstrap`, `HOST=<public-ip>`)
- `scripts/verify-vm.sh:3`, `:14` (`PUBLIC_PROBE_PORTS`), `:45-47` (`nc -z -G`/`-w` 프로브), `:51-63` (`validate_public_ip`, IPv4 전용), `:84-90` (공인 IP 포트 차단 검사), `:100-103` (`require_env BM_VM_PUBLIC_IP`)
- `scripts/bootstrap-vm.sh:2`, `:33` (`HOST=<public-ip>` usage), `:43`, `:50` (`upload failed` 안내)
- `scripts/status.sh:34` (`make vm-bootstrap HOST=<public-ip>` 안내)
- `tests/vm_ops.bats:7`, `:84-87`, `:112-116`, `:131`, `:142-168` (공인 IP 검증 테스트), `tests/bootstrap.bats:170-173`
- `docs/runbooks/rbk-2026-10-12-gcp-vm.md:35` (ephemeral 외부 IPv4), `:91-107` (공인 IP 조회, 정지 후 IP 변경)
- `docs/runbooks/rbk-2026-10-12-bootstrap.md:7`, `:16-17`, `:42`, `:45`, `:49`
- `docs/runbooks/rbk-2026-10-12-operations.md:48`, `:64`, `:79-82`
- `docs/runbooks/rbk-2026-10-12-accounts.md:23`, `docs/ARCHITECTURE.md:50`, `:57-58`, `:63`, `docs/decisions/adr-2026-10-12-0001-basic-memory-on-gcp-tailscale.md:29-30`
- `.agents/skills/bm-diagnose/SKILL.md:22`, `.agents/skills/bm-recover/SKILL.md:11`, `:15-16`, `.agents/skills/bm-upgrade` (ghcr.io 이미지 pull 경로; 줄 번호는 설계 때 확인)
- GCP 스펙 `docs/specs/spec-2026-10-12-basic-memory-gcp-tailscale.md:22`, `:33`, `:37`, `:51`, `:55`, `:88`, `:96-97`, `:122`, `:136`, `:157`, `:173`, `:194-197`, `:216`, `:222-225`

## 완료 조건 (초안)

1. VM에 외부 IPv4가 없다(`gcloud compute instances describe`의 `accessConfigs`에 IPv4 NAT 항목이 없음).
2. 전환 다음 날 청구 보고서에서 외부 IP SKU 금액이 0이다.
3. `make verify`와 `make probe`가 통과하고, IPv6 노출 검사 방식이 문서와 테스트에 반영돼 있다.
4. 이미지 업데이트(`bm-upgrade`), 모델 다운로드, `make backup`/`restore` 경로가 외부 IPv4 없이 동작한다.
5. 부트스트랩과 `bm-recover`가 공인 IPv4 없이 가능하다.
6. 롤백 절차가 문서화돼 있다.
7. `make check`가 통과한다.
