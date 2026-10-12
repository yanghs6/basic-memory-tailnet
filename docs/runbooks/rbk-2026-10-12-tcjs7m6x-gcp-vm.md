# VM 만들기 (gcloud)

이 런북의 명령은 사용자가 자기 터미널에서 실행합니다. 에이전트는 VM, 방화벽, 클라우드 자원을 바꾸는 명령을 사용자의 OK 없이 실행하지 않습니다. 이 Mac의 활성 gcloud 설정은 회사 계정일 수 있으므로, **모든 gcloud 명령에 `--configuration=bm-personal`을 붙입니다**([accounts 1단계](rbk-2026-10-12-hqxjjqy8-accounts.md)).

## 0. 변수와 설정 확인

```bash
INSTANCE=agent-hub-01   # 현재 인스턴스 이름(재구축 뒤에는 새 이름). Tailscale 기기 이름(bm-node)과 달라도 됩니다.
ZONE=us-west1-b
gcloud config list --configuration=bm-personal
env | grep '^CLOUDSDK_'   # 아무것도 출력되지 않아야 합니다
```

Expected: `account`가 개인 계정이고 `project`가 이 저장소 전용 프로젝트입니다. 회사 계정이나 회사 프로젝트가 보이면 **여기서 멈추고** [accounts 1단계](rbk-2026-10-12-hqxjjqy8-accounts.md)를 다시 합니다. `env | grep '^CLOUDSDK_'`가 무언가 출력하면(`CLOUDSDK_CORE_PROJECT`, `CLOUDSDK_CORE_ACCOUNT` 등) 먼저 그 셸에서 해당 변수를 `unset`합니다. **Assumption:** gcloud 속성 우선순위(플래그 > 환경 변수 > 설정)에 따라 환경 변수가 `--configuration=bm-personal`의 값을 덮어씁니다.

인스턴스 이름은 바꿀 수 없으므로, 재구축이면 새 VM은 반드시 다른 `INSTANCE` 이름으로 만들고 옛 VM은 정지해 둡니다(옛 VM은 복원이 검증된 뒤에 지웁니다). 두 대의 e2-micro나 부트 디스크 두 개가 함께 있는 동안에는 무료 등급을 넘을 수 있습니다(무료 등급은 비선점형 e2-micro 1대의 월 사용 시간과 표준 영구 디스크 30GB-월이며, 정지된 VM의 디스크도 포함됩니다). 그러니 복원이 검증된 뒤 옛 VM과 디스크를 서둘러 지우고 [비용 점검](rbk-2026-10-12-t79ex2ny-operations.md#비용-점검)으로 청구를 확인합니다.

## 1. SSH 키

키가 없으면 만듭니다: `ssh-keygen -t ed25519`. 공개키는 `~/.ssh/id_ed25519.pub`입니다. 인스턴스 메타데이터에는 **공개키만** 둡니다.

**Verified (docs.cloud.google.com/compute/docs/connect/add-ssh-keys):** OS Login을 켜지 않았다면 VM은 메타데이터의 SSH 키를 씁니다. OS Login을 켜면 메타데이터 키는 무시됩니다. **Verified (2026-10-12, Command: `gcloud compute project-info describe --configuration=bm-personal`):** 이 프로젝트의 메타데이터에는 `enable-oslogin`이 없습니다. 아래 4단계에서 다시 확인합니다.

## 2. 인스턴스 생성

무료 조건을 명령에 고정합니다(**Verified**, docs.cloud.google.com/free/docs/free-cloud-features, 2026-10-12).

| 항목 | 값 | 이유 |
|---|---|---|
| 머신 | `e2-micro` (1GB) | 월 1대 무료 |
| 리전·존 | `us-west1-b` | 무료 리전(us-west1, us-central1, us-east1) 중 한국에서 가장 가까움 |
| 이미지 | `ubuntu-minimal-2604-lts-amd64` (프로젝트 `ubuntu-os-cloud`, X86_64) | **Verified** (2026-10-12, Command: `gcloud compute images describe-from-family ubuntu-minimal-2604-lts-amd64 --project=ubuntu-os-cloud --configuration=bm-personal`) |
| 부트 디스크 | `pd-standard` 30GB | 월 30GB 표준 영구 디스크 무료. balanced 디스크는 무료가 아님 |
| 프로비저닝 | `STANDARD` | Spot(preemptible) VM은 무료가 아님 |
| 네트워크 티어 | `PREMIUM`, ephemeral 외부 IPv4 | 기본값 |
| 관리자 계정 | 메타데이터 `ssh-keys=ubuntu:<공개키>` | GCP 게스트 에이전트가 `ubuntu`를 만듭니다. 스크립트의 `ADMIN_USER=ubuntu`를 그대로 씁니다 |

새 프로젝트는 Compute Engine API가 꺼져 있을 수 있습니다. 먼저 켭니다(이미 켜져 있으면 아무 일도 하지 않습니다). **Assumption:** API를 켜면 `default` 네트워크와 기본 방화벽 규칙이 만들어집니다.

```bash
gcloud services enable compute.googleapis.com --configuration=bm-personal
gcloud compute instances create "$INSTANCE" --configuration=bm-personal \
  --zone="$ZONE" --machine-type=e2-micro \
  --image-family=ubuntu-minimal-2604-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-type=pd-standard --boot-disk-size=30GB \
  --provisioning-model=STANDARD --network-tier=PREMIUM \
  --no-service-account --no-scopes \
  --metadata=ssh-keys="ubuntu:$(cat ~/.ssh/id_ed25519.pub)"
```

Expected: 인스턴스가 `RUNNING`으로 만들어지고 `EXTERNAL_IP`가 한 줄 보입니다.

**Assumption:** 게스트 에이전트의 `ssh-keys` 메타데이터 처리에는 서비스 계정이 필요 없으므로 `--no-service-account --no-scopes`로 VM 안에서 메타데이터 서버 토큰을 받을 수 없게 합니다. 이미 있는 `agent-hub-01`은 기본 서비스 계정을 유지하며, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)이 이를 기록합니다.

**Assumption ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)에서 확인):** 26.04 Minimal에 `ss`(iproute2)와 `free`(procps)가 기본으로 있고, 메타데이터 키로 만든 `ubuntu`에게 암호 없는 sudo가 있습니다.

## 3. 방화벽 정리

`default` 네트워크에는 `default-allow-ssh`(tcp:22), `default-allow-rdp`(tcp:3389), `default-allow-icmp`가 `0.0.0.0/0`으로, `default-allow-internal`이 `10.128.0.0/9`로 미리 들어 있습니다(**Verified**, docs.cloud.google.com/firewall/docs/firewalls). 규칙이 없으면 인바운드는 모두 차단됩니다.

```bash
gcloud compute firewall-rules delete default-allow-rdp default-allow-icmp --configuration=bm-personal
MY_IP="$(curl -4 -s https://ifconfig.me)"
gcloud compute firewall-rules update default-allow-ssh --source-ranges="$MY_IP/32" --configuration=bm-personal
```

재구축처럼 규칙이 이미 지워진 프로젝트에서는 `delete`가 "not found"로 실패하고 `update`도 실패합니다. 이때 rdp·icmp 삭제는 건너뛰고, 22번 규칙은 새로 만듭니다.

```bash
gcloud compute firewall-rules create default-allow-ssh --configuration=bm-personal --network=default --direction=INGRESS --allow=tcp:22 --source-ranges="$MY_IP/32"
```

- `default-allow-internal`은 VPC 내부 전용이라 둡니다. 8737과 443은 열지 않습니다.
- `default-allow-ssh`는 [부트스트랩](rbk-2026-10-12-ha5w72pm-bootstrap.md)에서 Tailscale SSH를 확인한 **뒤에** 지웁니다.
- 다른 네트워크에서 부트스트랩하면 내 IP가 바뀌므로 위 `update` 명령을 다시 실행합니다.
- 이 명령들은 [운영 런북](rbk-2026-10-12-t79ex2ny-operations.md)의 Exposure audit 기준(VPC 밖 소스를 허용하는 인바운드 규칙 0개)을 만족시키기 위한 것입니다. 마지막 확인은 거기서 합니다.

## 4. 생성 결과 확인

```bash
gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(scheduling.provisioningModel,machineType.basename(),networkInterfaces[0].accessConfigs[0].networkTier)'
gcloud compute disks describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(type.basename(),sizeGb)'
gcloud compute project-info describe --configuration=bm-personal --format='value(commonInstanceMetadata.items)'
```

Expected:
- 첫 명령: `STANDARD`, `e2-micro`, `PREMIUM`. `SPOT`이 나오면 6단계로 갑니다.
- 둘째 명령: `pd-standard`와 `30`. **Assumption:** 부트 디스크 이름은 인스턴스 이름과 같습니다.
- 셋째 명령 출력에 `enable-oslogin`이 없습니다. `TRUE`로 있으면 메타데이터 키가 무시되므로 먼저 해결합니다.

## 5. 공인 IP 기록, 정지와 시작

```bash
gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(networkInterfaces[0].accessConfigs[0].natIP)'
```

이 값을 main 체크아웃 `.env`의 `BM_VM_PUBLIC_IP`에 적습니다(사용자가 직접 편집). 그다음 [부트스트랩](rbk-2026-10-12-ha5w72pm-bootstrap.md)으로 넘어갑니다.

**Verified (2026-10-12, 실제 프로젝트):** 정지 후 시작하면 ephemeral 외부 IP가 바뀝니다. **Assumption ([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)에서 확인):** 게스트 OS 재부팅으로는 바뀌지 않습니다.

```bash
gcloud compute instances stop "$INSTANCE" --zone="$ZONE" --configuration=bm-personal
gcloud compute instances start "$INSTANCE" --zone="$ZONE" --configuration=bm-personal
gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(status)'
```

- 정지된 VM의 `status`는 `TERMINATED`입니다. 시작한 뒤에는 위 IP 조회 명령으로 새 IP를 읽어 `.env`의 `BM_VM_PUBLIC_IP`를 바꿉니다. `verify`가 옛 IP로 검사하지 않게 하려면 이 값을 반드시 맞춰 둡니다.
- 정지된 VM은 지우거나 다시 만들지 않고 시작합니다. 디스크의 데이터가 그대로 있습니다([운영 런북](rbk-2026-10-12-t79ex2ny-operations.md)).

## 6. Spot으로 잘못 만든 경우

`set-scheduling --provisioning-model=STANDARD`는 Spot VM에서 `preemptionNoticeDuration` 오류로 실패합니다(**Verified**, 2026-10-12, 실제 프로젝트). 대신 내보내기 → 수정 → 갱신으로 바꿉니다.

```bash
gcloud compute instances stop "$INSTANCE" --zone="$ZONE" --configuration=bm-personal
EXPORT_FILE="${TMPDIR:-/tmp}/$INSTANCE.yaml"
gcloud compute instances export "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --destination="$EXPORT_FILE"
```

`$EXPORT_FILE`의 `scheduling:` 블록을 다음으로 바꿉니다. **Assumption:** Spot 전용 항목(`instanceTerminationAction`, `preemptionNoticeDuration` 등)이 남아 있으면 지웁니다.

```yaml
scheduling:
  automaticRestart: true
  onHostMaintenance: MIGRATE
  preemptible: false
  provisioningModel: STANDARD
```

```bash
gcloud compute instances update-from-file "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --source="$EXPORT_FILE" --most-disruptive-allowed-action=RESTART
gcloud compute instances start "$INSTANCE" --zone="$ZONE" --configuration=bm-personal
```

그다음 4단계로 다시 확인하고, 5단계로 새 IP를 기록합니다. 내보낸 파일은 저장소에 두지 않습니다.

## 7. 재구축할 때의 정리

VM을 다시 만드는 경우 옛 인스턴스와 디스크는 **복원이 검증되기 전에는 지우지 않습니다**. 복원 검증 뒤에 지울 때는 사용자가 직접 인스턴스 삭제 명령을 실행합니다(`--configuration=bm-personal`을 붙이고 `--zone`을 확인). 옛 VM과 디스크가 남아 있는 동안은 무료 등급을 넘을 수 있으므로(정지된 VM의 디스크도 30GB-월에 포함) 지체하지 말고 지운 뒤 [비용 점검](rbk-2026-10-12-t79ex2ny-operations.md#비용-점검)으로 청구를 확인합니다. 전체 순서는 [운영 런북](rbk-2026-10-12-t79ex2ny-operations.md)의 "VM 재구축 순서"에 있습니다.
