---
status: accepted
date: 2026-10-14
---

# ADR mdq5exsf: VM 크기 (e2-micro 1GB + 스왑 1GB)

- [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)의 VM 실측(아래 "측정")으로 확정했습니다. 처음 제안은 2026-10-12입니다.

## 맥락

GCP 무료 등급의 VM은 `e2-micro`(1GB)뿐이고 크기를 바꿀 수 없습니다. 이 호스트에는 유휴 VM을 거두어 가는 정책이 없으므로 메모리를 일부러 채울 필요가 없습니다. 반대로 1GB는 컨테이너, dockerd, tailscaled, OS를 함께 올리기에 빠듯합니다.

## 근거

- **Verified (2026-10-07, Command: `docker stats --no-stream`):** 0.23.2 컨테이너 메모리 사용량은 기동 직후 212 MiB, `search_notes` 실행으로 임베딩 모델이 올라간 뒤 449 MiB입니다(Mac Docker Desktop 기준, arm64 이미지). VM은 amd64이므로 수치가 다를 수 있습니다(**Assumption**).
- **Assumption (아래 Verified 값으로 계산):** Ubuntu 26.04 Minimal + dockerd + tailscaled는 약 350 MiB를 씁니다. 첫 배포 직후 `free -m` used 597 MiB에서 컨테이너 246.5 MiB를 뺀 값이며, 컨테이너 없이 따로 재지는 않았습니다.
- 산수: 임베딩 모델이 올라간 컨테이너만으로 449 / 1024 ≈ 44%입니다. 나머지 약 575 MiB에 OS, dockerd, tailscaled가 들어가야 하므로 여유가 작습니다. 그래서 스왑 파일 1GB를 둡니다.

## 측정 (2026-10-13~14, vm-rollout 계획)

- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 4):** 전체 메모리 952 MiB, 스왑 없음(부트스트랩 전).
- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 9, 첫 배포 직후, 임베딩 모델 로드 전):** `free -m` used 597 / available 355 MiB, 스왑 used 50 MiB, 컨테이너 246.5 MiB(`docker stats`).
- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 13, 재부팅 뒤):** used 558 / available 394 MiB, 스왑 used 18 MiB.
- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) `make verify` 뒤):** `make status` 메모리 사용률 64%, 스왑 224/1023 MB.
- **Verified (2026-10-13, 시험 노트가 있을 때 의미 검색 뒤):** 컨테이너 432.5 MiB, `free -m` used 729 / available 223 MiB, 스왑 used 131 MiB. 지금까지 잰 값 중 available이 가장 작습니다.
- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 15, 2026-10-14, 배포 24시간 뒤, 컨테이너 20시간 유휴):** `make status` 메모리 사용률 36%, 스왑 508/1023 MB. `free -m` used 336 / available 616 MiB. 컨테이너는 32 MiB로, 유휴 페이지가 스왑으로 나갔습니다. 스왑 508 MB 중 401 MB는 RAM에도 남아 있는 swap cache입니다(`vmstat -s`).
- **Verified (같은 날, 같은 컨테이너에서 첫 의미 검색 뒤):** 검색 25초, 컨테이너 187.8 MiB, used 457 / available 494 MiB.
- **Verified (같은 날, `make backup`으로 재시작하고 첫 의미 검색 뒤):** 검색 21초, 컨테이너 293.5 MiB, `free -m` used 651 / available 301 MiB, 스왑 used 191 MiB. 몇 초 뒤 `make status`는 메모리 사용률 60%, 스왑 276/1023 MB였습니다.
- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 9, 13, 15, 재배포):** 배포 뒤 24시간 동안과 배포, 재부팅, 재배포, 백업 재시작 때 OOM이 없었습니다(`dmesg` 없음, `OOMKilled=false`, `RestartCount=0`).
- **Verified ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 9, 13, 15, 재배포):** 컨테이너 시작부터 healthy까지 161초(첫 배포, 콜드), 192초(재부팅 뒤, 콜드), 26초(따뜻한 재배포), 36초 이내(백업 재시작).
- **Assumption:** 2026-10-14 측정 때는 노트가 없었습니다(시험 데이터를 지운 뒤라 검색 결과 0건). 노트가 늘면 인덱스와 검색 때문에 사용량이 늘 수 있습니다.

## 결정

`e2-micro` 그대로 쓰고, 부트스트랩이 `/swapfile` 1GB를 만듭니다(Docker 설치 전, 이미 있으면 건너뜀). `make status`는 활성 스왑이 없으면 경고합니다.

실측 근거: 배포 뒤 24시간 동안 OOM이 없었고, available은 가장 작을 때 223 MiB였습니다. 유휴 상태에서 스왑이 508 MB까지 찼지만 그때 available은 616 MiB였으므로 메모리 부족 때문이 아닙니다. 리눅스는 메모리가 남아도 스왑으로 내보낸 페이지를 쓰기 전까지 되돌리지 않습니다.

## 재평가 기준

- 측정 방법([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 15와 같음): `make backup`으로 컨테이너를 재시작하고 `search_notes`(semantic)로 임베딩 모델을 올린 뒤 `make status`와 `free -m`을 기록합니다.
- 컨테이너가 OOM으로 재시작되거나(`make logs`, `make status`), 스왑 사용이 스왑 크기의 절반 이상으로 계속 유지되면 사용자가 결정합니다. 선택지는 현재 크기를 감수하는 것, 유료 소형 인스턴스(비용 발생), 다른 호스트입니다.
- 스왑 기준값은 절반으로 유지합니다. 2026-10-14에 유휴 스왑이 절반 바로 아래(508/1023 MB)였지만 부족은 아니었습니다. 그러므로 기준을 넘으면 결정하기 전에 `free -m`의 available과 OOM 기록을 함께 봅니다.
