# ADR 0001: Basic Memory를 OCI Always Free + Tailscale에 자체 호스팅

- 상태: Accepted (2026-10-07)
- 출처: [설계 스펙](../specs/2026-10-07-basic-memory-oci-tailscale-design.md)

## 맥락

여러 기기의 에이전트가 같은 Basic Memory를 써야 합니다. 비용은 0원이어야 하고, Basic Memory HTTP 엔드포인트에는 인증이 없습니다(**Verified**).

## 결정

- OCI Always Free A1 VM에서 Docker로 Basic Memory를 실행하고, Tailscale Serve로 tailnet 안에만 노출합니다.
- VM은 콘솔에서 수동으로 만들고, 나머지는 이 저장소의 스크립트와 Make 타깃으로 처리합니다.
- 공인 SSH는 부트스트랩에만 쓰고 이후 Tailscale SSH로 전환하며, TCP/UDP 인바운드 규칙을 두지 않습니다.

## 대안

- **GCP e2-micro:** RAM이 1 GB이고 무료 리전이 미국뿐이라 지연이 큽니다.
- **AWS:** 신규 계정 무료 기간이 최대 6개월입니다.
- **Koyeb Free:** 영구 볼륨을 쓸 수 없습니다.
- **Basic Memory Cloud:** MCP 엔드포인트에 유료 구독이 필요합니다.

## 결과

- 유휴 회수 위험이 있습니다 → 메모리 사용률 기준으로 크기를 정하고([ADR 0002](0002-vm-sizing.md)), 백업·복원 경로를 둡니다.
- Tailscale 계정이 단일 장애점이 됩니다. 대신 인증 없는 엔드포인트가 인터넷에 노출되지 않습니다.
