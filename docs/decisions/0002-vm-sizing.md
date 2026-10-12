# ADR 0002: VM 크기 (A1.Flex 1 OCPU / 4 GB)

- 상태: Proposed (2026-10-07). 계획 05에서 VM 실측 후 Accepted로 바꿉니다.

## 맥락

OCI는 CPU(p95), 네트워크, 메모리가 **모두** 20% 미만이면 Always Free VM을 회수할 수 있습니다. 개인용 MCP 서버는 CPU와 네트워크가 거의 항상 20% 미만이므로, 회수를 피하려면 메모리 사용률을 20% 이상으로 유지해야 합니다.

## 근거

- **Verified (2026-10-07, Command: `docker stats --no-stream`):** 0.23.2 컨테이너 메모리 사용량은 기동 직후 212 MiB, `search_notes` 실행으로 임베딩 모델이 올라간 뒤 449 MiB입니다(Mac Docker Desktop 기준).
- **Assumption:** Ubuntu 24.04 + Docker + tailscaled 기본 사용량은 약 400~500 MB입니다. VM 실측(`make status`)으로 확인합니다.
- 추정 사용률: 4 GB에서 약 22~25%, 6 GB에서 약 15%(20% 미만이라 회수 위험)

## 결정

1 OCPU / 4 GB로 시작합니다. 무료 한도(2 OCPU / 12 GB) 안입니다.

## 재평가 기준

- 배포 24시간 뒤 `make status`의 메모리 사용률이 **25% 미만**이면, 콘솔에서 3 GB로 줄입니다(재시작 필요). 그 후 다시 측정합니다.
- 메모리 사용률이 **80% 이상**이면 6 GB로 늘리고, 회수 위험은 백업 주기로 보완합니다.
- 측정 결과를 이 ADR에 Verified로 추가하고 상태를 Accepted로 바꿉니다.
