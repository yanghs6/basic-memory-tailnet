# ADR 0002: VM 크기 (e2-micro 1GB + 스왑 1GB)

- 상태: Proposed (2026-10-12). 계획 05에서 VM 실측 후 Accepted로 바꿉니다.

## 맥락

GCP 무료 등급의 VM은 `e2-micro`(1GB)뿐이고 크기를 바꿀 수 없습니다. 이 호스트에는 유휴 VM을 거두어 가는 정책이 없으므로 메모리를 일부러 채울 필요가 없습니다. 반대로 1GB는 컨테이너, dockerd, tailscaled, OS를 함께 올리기에 빠듯합니다.

## 근거

- **Verified (2026-10-07, Command: `docker stats --no-stream`):** 0.23.2 컨테이너 메모리 사용량은 기동 직후 212 MiB, `search_notes` 실행으로 임베딩 모델이 올라간 뒤 449 MiB입니다(Mac Docker Desktop 기준, arm64 이미지). VM은 amd64이므로 수치가 다를 수 있습니다(**Assumption**).
- **Assumption:** Ubuntu 26.04 Minimal + dockerd + tailscaled의 기본 사용량은 아직 재지 않았습니다. 계획 05에서 `make status`로 측정합니다.
- 산수: 임베딩 모델이 올라간 컨테이너만으로 449 / 1024 ≈ 44%입니다. 나머지 약 575 MiB에 OS, dockerd, tailscaled가 들어가야 하므로 여유가 작습니다. 그래서 스왑 파일 1GB를 둡니다.

## 결정

`e2-micro` 그대로 쓰고, 부트스트랩이 `/swapfile` 1GB를 만듭니다(Docker 설치 전, 이미 있으면 건너뜀). `make status`는 활성 스왑이 없으면 경고합니다.

## 재평가 기준

- 계획 05에서 배포 24시간 뒤, `make backup`으로 컨테이너를 재시작하고 `search_notes`로 임베딩 모델을 올린 상태에서 `make status`의 메모리·스왑 사용량을 기록합니다.
- 컨테이너가 OOM으로 재시작되거나(`make logs`, `make status`), 스왑 사용이 스왑 크기의 절반 이상으로 계속 유지되면 사용자가 결정합니다. 선택지는 현재 크기를 감수하는 것, 유료 소형 인스턴스(비용 발생), 다른 호스트입니다. **Assumption:** "스왑 크기의 절반 이상"이라는 기준값은 측정 후 조정합니다.
- 측정 결과를 이 ADR에 Verified로 추가하고 상태를 Accepted로 바꿉니다.
