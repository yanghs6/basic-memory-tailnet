---
status: accepted
date: 2026-10-12
---

# ADR 0001: Basic Memory를 GCP 무료 e2-micro + Tailscale에 자체 호스팅

- 2026-10-07의 OCI Always Free 결정을 대체합니다.
- 출처: [설계 스펙](../specs/spec-2026-10-12-basic-memory-gcp-tailscale.md)

## 맥락

여러 기기의 에이전트가 같은 Basic Memory를 써야 합니다. 비용은 0원이어야 합니다.

**Verified:** Basic Memory HTTP 엔드포인트에는 인증이 없습니다.

처음에는 OCI Always Free A1 VM을 골랐지만 만들지 못했습니다. 사용자 콘솔에서 A1 생성이 "Out of capacity for shape VM.Standard.A1.Flex in availability domain AD-1"로 실패했습니다.

**Verified (docs.oracle.com, Always Free Resources: "…in any availability domain, except South Korea North (Chuncheon)"):** 춘천 리전은 A1 자체가 없습니다.

사용자는 무료만 허용합니다.

## 결정

- GCP 무료 등급의 `e2-micro`(us-west1-b, Ubuntu 26.04 LTS Minimal amd64, `pd-standard` 30GB, STANDARD 프로비저닝)에서 Docker로 Basic Memory를 실행하고, Tailscale Serve로 tailnet 안에만 노출합니다.
- VM과 방화벽은 [런북](../runbooks/rbk-2026-10-12-gcp-vm.md)의 gcloud 명령으로 만듭니다(개인 gcloud 설정 `bm-personal`). 나머지는 이 저장소의 스크립트와 Make 타깃으로 처리합니다.
- 공인 SSH는 부트스트랩에만 쓰고 이후 Tailscale SSH로 전환하며, VPC 밖 소스를 허용하는 인바운드 규칙을 두지 않습니다.

## 대안

- **OCI Always Free A1:** 위 맥락의 이유로 만들 수 없었습니다.
- **AWS:** 신규 계정 무료 기간이 최대 6개월입니다.
- **Koyeb Free:** 영구 볼륨을 쓸 수 없습니다.
- **Basic Memory Cloud:** MCP 엔드포인트에 유료 구독이 필요합니다.

## 결과

- RAM이 1GB로 고정이라 스왑 1GB를 부트스트랩이 만듭니다([ADR 0002](adr-2026-10-12-0002-vm-sizing.md)).
- 무료 리전이 미국뿐이라 한국에서는 지연이 큽니다.
- 정지 후 시작하면 외부 IP가 바뀝니다. 런북이 IP 조회와 `.env` 갱신을 안내합니다.
- **Open question:** 외부 IPv4 요금($0.005/h, 2024-02-01부터)이 무료 등급에 포함되는지는 공식 문서에 없습니다. 배포 다음 날 청구 보고서를 SKU별로 확인합니다([운영 런북](../runbooks/rbk-2026-10-12-operations.md)의 비용 점검).
- Tailscale 계정이 단일 장애점이 됩니다. 대신 인증 없는 엔드포인트가 인터넷에 노출되지 않습니다.
