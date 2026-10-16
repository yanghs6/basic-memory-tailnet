---
status: approved
date: 2026-10-12
amended-by: [docs/specs/spec-2026-10-15-jr59pvyf-access-modes.md, docs/specs/spec-2026-10-15-sgpbx1gq-doc-system.md, docs/specs/spec-2026-10-15-d8q0b7bt-script-test-layout.md]
---

# Basic Memory on GCP Free Tier + Tailscale — 설계

- [OCI 설계](spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md)를 대체한다. 모든 계획은 [git·리뷰 정책](spec-2026-10-07-restd5vd-git-review-policy.md)을 따른다. 접속 방식은 [접속 방식 설계](spec-2026-10-15-jr59pvyf-access-modes.md)로 넓혔다(VM마다 Tailscale 또는 SSH 터널).
- 구현 계획 (계획은 `docs/plans/`, 상태는 각 계획의 front matter):
  1. `plan-2026-10-07-sqzn0teq-local-foundation.md` (완료): 도구 체인, compose, 로컬 MCP 검증, AGENTS.md 기본판
  2. `plan-2026-10-07-qq4h1djv-git-review-tooling.md` (완료): `make check-git`, `make review`, 리뷰어 에이전트, git·리뷰 스킬
  3. `plan-2026-10-07-dry1xr43-vm-scripts.md` (완료): 부트스트랩, 배포·검증·상태·로그, 백업·복원
  4. `plan-2026-10-07-hydaxf15-docs-skills.md` (완료, 이 설계로 확장): GCP 전환 코드 변경, worktree 백업 보호(C1), 이미지 불일치 점검(I3), 운영 스킬, README, 아키텍처, 런북, ADR, 로컬 전체 검증
  5. `plan-2026-10-07-qtvzskgx-vm-rollout.md` (다시 씀): 실제 VM 배포(사용자와 함께)
- 범위: 첫 목표 `GCP 무료 e2-micro + Tailscale + Basic Memory`
- 출처: OCI 설계, 2026-10-12 사용자와의 브레인스토밍, 같은 날 공식 문서와 실제 프로젝트에서 확인한 사실

## 0. OCI 설계에서 바뀐 것

| 항목 | OCI 설계 | 이 설계 | 이유 |
|---|---|---|---|
| 호스트 | OCI A1.Flex 1 OCPU / 4GB, Ubuntu 24.04 arm64 | GCP `e2-micro` (1GB), Ubuntu 26.04 LTS Minimal amd64 | A1 용량 부족으로 생성 실패. 춘천 리전은 A1 자체가 없음. 사용자는 무료만 허용 |
| VM 생성 | 콘솔 수동 | 런북의 gcloud 명령 (개인 gcloud 설정 `bm-personal`) | 무료 조건(리전·디스크·프로비저닝)을 명령에 고정. 회사 gcloud 설정과 분리 |
| 공개 차단 | OCI Security List | GCP VPC 방화벽 (`default` 네트워크의 기본 공개 규칙 삭제) | 개인 프로젝트에 이 VM만 있음 |
| 유휴 회수 | 메모리 20% 경고, 크기 조정 | 없음 | GCP 무료 등급에는 회수 정책이 없음 |
| 메모리 | 4GB | 1GB + 스왑 파일 1GB (부트스트랩이 만듦) | e2-micro 고정 크기 |
| 비용 확인 | 없음 | Budget 알림 + 다음 날 SKU별 청구 확인 | 외부 IPv4는 유료(월 약 $3.65, §3). [ipv6-egress 계획](../plans/plan-2026-10-13-gaewewkf-ipv6-egress.md)에서 IPv6로 전환 |
| `.env`·`backups/` 위치 | 실행한 체크아웃 | 항상 main 체크아웃 | worktree에서 만든 백업이 `git worktree remove`로 조용히 사라짐([docs-skills 계획](../plans/plan-2026-10-07-hydaxf15-docs-skills.md) 최종 리뷰 C1) |

## 1. 목표와 완료 조건

여러 기기(개인 Mac, 회사 Mac)의 코딩 에이전트(Codex, Claude Code, Antigravity)가 함께 쓰는 Basic Memory MCP 서버를 GCP 무료 등급 VM에 올린다. 이 서버는 tailnet 안에서만 접근할 수 있어야 한다.

**완료 조건**

1. `make verify`가 tailnet 안에서 `https://agent-hub.<tailnet>.ts.net/mcp`로 MCP 왕복(initialize → tools/list → 노트 쓰기/읽기/삭제)을 통과한다.
2. 공개 노출이 없다. 두 가지를 모두 충족해야 한다.
   - 자동 검증: `make verify`로 VM의 공인 IP에서 22·80·443·8737번 포트가 닫혀 있고, Serve가 tailnet 전용(Funnel off)임을 확인한다.
   - 수동 점검: 프로젝트의 인바운드 방화벽 규칙 중 VPC 밖의 소스를 허용하는 규칙이 0개(`default-allow-internal`의 `10.128.0.0/9`만 남음)이고, tailnet 정책에 `funnel` 속성이 없음을 확인해 기록한다(운영 런북의 Exposure audit). 이 둘은 VM에서 읽을 수 없어 자동 검증 범위 밖이다.
3. `make backup`으로 받은 백업을 `make restore`로 복원하면 백업 시점의 데이터 파일이 manifest와 일치하게 돌아오고, 백업 이후의 변경은 사라진다.
4. `make check`(lint + test + coverage ≥ 80%)가 통과한다.
5. 배포 다음 날 청구 보고서의 SKU별 금액(e2-micro, standard persistent disk, 외부 IP, 네트워크)이 0이다. 0이 아니면 사용자가 "그 금액을 감수"와 "다른 호스트" 중에서 결정한다.

**범위 밖 (다음 목표)**

- 에이전트별 MCP 클라이언트 연결 설정
- 자동·주기 백업
- `personal-context` GitHub 정본 연동, 지식 그래프·온톨로지
- 회사용 별도 인스턴스
- VM 생성·방화벽을 감싸는 Make 타깃이나 IaC (런북의 gcloud 명령으로 충분)

## 2. 결정 사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 호스트 | GCP `e2-micro`, `us-west1-b`, Ubuntu 26.04 LTS Minimal amd64, `pd-standard` 30GB, 프로비저닝 STANDARD(Spot 아님), Premium 티어, ephemeral 외부 IPv4 | 무료 등급 조건. 미국 무료 리전 중 한국에서 가장 가까움. 26.04 Minimal은 이미 만든 VM의 이미지이고 Docker·Tailscale 저장소가 지원함(사용자 선택) |
| GCP 계정 | 개인 계정의 전용 프로젝트. 로컬 gcloud는 비활성 설정 `bm-personal`로만 쓰고, 모든 명령에 `--configuration=bm-personal`을 붙인다 | 이 Mac의 활성 gcloud 설정은 회사 계정이다. 회사 설정을 바꾸거나 회사 프로젝트에 자원을 만들면 안 된다 |
| 자동화 수준 | VM과 방화벽은 런북의 gcloud 명령으로 만든다. 저장소에는 스크립트·compose·Make·런북을 둔다 | 한 번 만들고 거의 안 바꾸는 자원이다. IaC 상태 관리가 필요 없다 |
| 네트워크 | `default` 네트워크에서 `default-allow-rdp`·`default-allow-icmp`를 지우고, `default-allow-ssh`는 본인 IP/32로 좁혔다가 Tailscale SSH 확인 후 지운다. `default-allow-internal`은 VPC 내부 전용이라 둔다 | 전용 VPC와 같은 결과를 더 적은 단계로 얻는다 |
| 배포 방식 | Mac에서 공인 IP SSH로 부트스트랩한 뒤 Tailscale SSH로 전환하고 22번 규칙을 지운다 | 디버깅이 쉽고 다시 실행해도 안전하다. 인스턴스 메타데이터에는 공개키만 둔다 |
| 관리자 계정 | 인스턴스 메타데이터 `ssh-keys`에 `ubuntu:<공개키>`를 넣어 GCP 게스트 에이전트가 `ubuntu`를 만들게 한다 | 기존 스크립트의 `ADMIN_USER=ubuntu`를 그대로 쓴다 |
| 메모리 | 스왑 파일 1GB를 부트스트랩이 만든다. `status`는 스왑이 없으면 경고한다 | 컨테이너 449 MiB(실측) + dockerd + tailscaled + OS가 1GB에 빠듯하다 |
| 로컬 검증 | 같은 compose로 Mac Docker에서 먼저 검증한다 | VM에서의 시행착오를 줄이고 검증 스크립트를 재사용한다 |
| 호스트 포트 | `127.0.0.1:8737` (컨테이너 내부는 8000) | 8188은 ComfyUI 기본 포트라 제외. 8737은 IANA 미할당 |
| 사용 범위 | 개인 기억만 저장하고, 개인 Mac과 회사 Mac이 tailnet에 참여한다 | 사용자 선택 |
| Tailscale 기기 이름·태그 | 기기 이름 `agent-hub`, 태그 `tag:agent-hub` (2026-10-12, 처음 이름은 `bm-node`·`tag:bm-server`) | 이 서버를 Basic Memory 말고도 여러 에이전트 작업에 쓸 예정이라 일반적인 이름을 쓴다(사용자 결정) |
| 백업 | 수동 `make backup` / `make restore`. 아카이브는 항상 main 체크아웃의 `backups/`에 둔다 | VM 손실 대비. worktree 삭제로 백업을 잃지 않게 한다. 자동화는 다음 목표 |
| 비용 안전장치 | 생성 전에 Budget 알림(월 $1), 배포 다음 날 SKU별 청구 확인 | 무료 등급 밖 과금을 빨리 발견한다 |
| 메시지 표현 | 스크립트 메시지는 특정 클라우드 이름 대신 "the firewall rule that opens port 22"처럼 쓰고, 구체적인 방법은 런북을 가리킨다 | 호스트가 다시 바뀌어도 코드를 고치지 않는다 |

## 3. 검증된 외부 사실

**OCI 설계에서 이어지는 사실 (2026-10-07)**

- **Verified:** Basic Memory 이미지는 `ghcr.io/basicmachines-co/basic-memory:0.23.2`이고 index digest는 `sha256:939f1173d96626c280763e14622f2381d49fbbb7db17cae2e832f4f639405643`이다. 기본 CMD는 `--transport sse`라서 `basic-memory mcp --transport streamable-http --host 0.0.0.0 --port 8000 --path /mcp`로 덮어쓴다.
- **Verified:** 데이터는 `/app/data`, 설정과 인덱스는 `/home/appuser/.basic-memory`에 둔다. 컨테이너는 UID/GID 1000으로 실행된다. 기본 프로젝트 `main`은 `/app/data/basic-memory`에 생성된다.
- **Verified:** 변경 감지 환경변수는 `BASIC_MEMORY_INDEX_CHANGES`, `BASIC_MEMORY_INDEX_DELAY`다.
- **Verified:** Basic Memory HTTP 엔드포인트에는 인증이 없고 공식 문서는 공인 인터넷 노출을 경고한다. HTTP 헬스 엔드포인트는 없다.
- **Verified:** 시맨틱 검색은 FastEmbed 로컬 모델을 쓰므로 API 키가 필요 없다. 첫 사용 시 모델을 내려받는다.
- **Verified:** `tailscale serve --bg http://127.0.0.1:<port>`는 tailnet 안에서 HTTPS 443으로 노출한다. HTTPS 인증서와 MagicDNS를 켜야 한다. 인증서가 발급된 기기 이름은 공개 CT 로그에 기록된다.
- **Verified (tailscale.com/docs/features/tailscale-funnel):** Funnel은 기본 비활성이다. `tailscale funnel`을 승인하면 정책 `nodeAttrs`에 `funnel` 속성이 추가된다.
- **Verified:** 서버용으로는 사전 승인된 태그 인증 키를 권장한다. `tailscale set --ssh`를 켜면 공인 22번 포트를 닫을 수 있다. Tailscale Personal 요금제는 비상업 용도로 한정된다.
- **Verified (2026-10-07, 로컬 0.23.2 컨테이너):** `Host: bm-node.example.ts.net` 헤더로 보낸 initialize가 200으로 응답했고 write/read/delete 왕복도 성공했다. 컨테이너 메모리는 212~449 MiB였다(`docker stats`, 임베딩 모델 로드 전후). (당시 기기 이름. 2026-10-12에 `agent-hub`로 바꿈)
- **Verified (2026-10-13, 사용자 확인):** 회사 보안 정책상 회사 Mac의 Tailscale 사용이 허용된다. 다만 사무실 네트워크가 `controlplane.tailscale.com`의 HTTPS(SNI)만 막아 사무실에서는 tailnet에 들어가지 못한다. 사용자가 네트워크 관리자에게 허용을 요청했다([vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Progress log).

**OCI를 포기한 근거 (2026-10-12)**

- **Verified (docs.oracle.com, Always Free Resources):** "You can create OCI Ampere A1 Compute instances in any availability domain, except South Korea North (Chuncheon)." 사용자 콘솔에서 A1 생성이 "Out of capacity for shape VM.Standard.A1.Flex in availability domain AD-1"로 실패했다.

**GCP (2026-10-12)**

- **Verified (docs.cloud.google.com/free/docs/free-cloud-features):** 무료 등급은 "1 non-preemptible e2-micro VM instance per month"(us-west1, us-central1, us-east1), "30 GB-months standard persistent disk", "1 GB of outbound data transfer from North America to all region destinations (excluding China and Australia) per month"다. 결제 계정이 필요하다. 따라서 Spot(preemptible) VM과 balanced 디스크는 무료가 아니다.
- **Verified (2026-10-13, cloud.google.com/vpc/network-pricing):** 외부 IPv4는 무료 등급에 들지 않는다. "Static and ephemeral IP addresses in use on standard VM instances $0.005 / 1 hour", 무료는 "one hour per month per account"뿐이라 월 약 $3.65가 든다. 외부 IPv6는 무료다("You are not charged for … external IPv6 addresses that are assigned to VM instances"). 2026-10-13까지의 청구액은 사용자 확인으로 20원 미만이었다(SKU별 금액은 기록하지 않음). 사용자 결정(2026-10-13): 외부 IPv4를 없애고 IPv6로 전환한다. [ipv6-egress 계획](../plans/plan-2026-10-13-gaewewkf-ipv6-egress.md)(`docs/plans/plan-2026-10-13-gaewewkf-ipv6-egress.md`)에서 설계부터 진행한다.
- **Verified (docs.cloud.google.com/firewall/docs/firewalls):** 규칙이 없으면 인바운드는 모두 차단되고 아웃바운드는 허용된다(implied rules). `default` 네트워크에는 `default-allow-ssh`(tcp:22), `default-allow-rdp`(tcp:3389), `default-allow-icmp`가 `0.0.0.0/0`으로, `default-allow-internal`이 `10.128.0.0/9`로 미리 들어 있다.
- **Verified (docs.cloud.google.com/compute/docs/connect/add-ssh-keys):** OS Login을 켜지 않았다면 VM은 메타데이터의 SSH 키를 쓴다. OS Login을 켜면 메타데이터 키는 무시된다.
- **Verified (2026-10-12, `docker manifest inspect`):** 고정한 Basic Memory 이미지는 linux/amd64와 linux/arm64를 모두 포함한다.
- **Verified (2026-10-12, HTTP 200):** `download.docker.com/linux/ubuntu/dists/resolute`와 `pkgs.tailscale.com/stable/ubuntu/resolute`가 있다. 부트스트랩은 OS 코드명과 아키텍처를 실행 시점에 읽는다(`UBUNTU_CODENAME`, `dpkg --print-architecture`).
- **Verified (2026-10-12, 실제 프로젝트):** `gcloud compute instances set-scheduling --provisioning-model=STANDARD`는 Spot VM에서 `preemptionNoticeDuration` 오류로 실패한다. `instances export` → scheduling 수정 → `instances update-from-file`로 바꿀 수 있다. 정지 후 시작하면 ephemeral 외부 IP가 바뀐다.
- **Verified (2026-10-12, 이 Mac에서 `nc`):** 방화벽이 막은 포트는 연결 시간 초과로 끝난다. `verify-vm.sh`는 timeout을 "닫힘"으로 판정한다.
- **Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 4):** 26.04 Minimal에 `ss`(`/usr/bin/ss`, iproute2-6.19.0)와 `free`(`/usr/bin/free`, procps-ng 4.0.4)가 기본으로 있다. 메타데이터 키로 만든 `ubuntu`는 암호 없는 sudo(`NOPASSWD`)를 가진다.
- **Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 13):** 게스트 OS 재부팅(`sudo -n systemctl reboot`) 뒤에도 ephemeral 외부 IP가 그대로다.
- **Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 14):** `default-allow-ssh`를 지워 22번이 닫힌 뒤에도 `make vm-bootstrap HOST=agent-hub`가 Tailscale SSH로 업로드·실행되어 `[bootstrap] done`으로 끝났다.
- **Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) 항목 30, Tailscale v1.104.1 소스 `cmd/tailscale/cli/serve_v2.go`):** `tailscale serve --bg`는 자기 포트(443)의 Funnel만 끄고 다른 포트의 Funnel은 그대로 둔다. 다른 포트에 남아 있으면 `tailscale serve reset`이 필요하다. 소스를 읽어 확인했고 Funnel을 켜서 시험하지는 않았다.
- **Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) `make verify`):** `https://agent-hub.<tailnet>/mcp`로 MCP 왕복(initialize, tools/list, write_note, read_note, delete_note)이 통과했다.

## 4. 아키텍처

```
[개인/회사 Mac] ── tailnet ──▶ https://agent-hub.<tailnet>.ts.net/mcp
  에이전트, make deploy/verify/backup       │ Tailscale Serve (HTTPS, tailnet 전용)
  (Tailscale SSH)                           ▼
                        GCP e2-micro (us-west1-b, Ubuntu 26.04 Minimal amd64, 1GB + swap 1GB)
                        인바운드 허용: VPC 내부(10.128.0.0/9)만
                          └ Docker: basic-memory:0.23.2@sha256
                              127.0.0.1:8737 → :8000 /mcp
                              /srv/basic-memory/knowledge → /app/data
                              /srv/basic-memory/config    → /home/appuser/.basic-memory
```

신뢰 경계는 tailnet이다. Basic Memory에 인증이 없으므로 접근 제어는 Tailscale의 기기 인증과 정책에 맡긴다. 컨테이너 포트는 어느 환경에서도 `127.0.0.1`에만 바인딩한다. GCP 인스턴스 이름(예: `agent-hub-01`)과 Tailscale 기기 이름(`agent-hub`)은 서로 다른 이름이다. 스크립트는 Tailscale 이름만 쓴다.

## 5. 저장소 구조

OCI 설계 §5와 같고 다음만 다르다.

```
.env.example         BM_VM_HOST, BM_VM_USER, BM_TAILNET_DOMAIN, BM_VM_PUBLIC_IP, BM_PORT (설명에서 OCI 표현 제거)
docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md  rbk-2026-10-12-tcjs7m6x-gcp-vm.md  rbk-2026-10-12-ha5w72pm-bootstrap.md  rbk-2026-10-12-t79ex2ny-operations.md     (rbk-2026-10-12-vebvx40g-oci-vm.md 대신 rbk-2026-10-12-tcjs7m6x-gcp-vm.md)
docs/decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md                  (호스트 선택: OCI 포기 근거 포함)
docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md                                      (e2-micro 1GB + 스왑)
docs/specs/                      이 문서와 대체된 OCI 설계
```

Mac 의존성에 `gcloud`(Google Cloud SDK)가 추가된다. 스크립트는 gcloud를 쓰지 않고, 런북의 사람 작업에만 쓴다.

에이전트 지침 규칙과 스킬의 정본 위치·frontmatter 규칙은 OCI 설계 §5와 같다. 스킬 절차는 다음과 같다.

| 스킬 | 사용 시점 | 절차 |
|---|---|---|
| `bm-upgrade` | Basic Memory 버전을 올릴 때 | 릴리스 노트에서 DB·설정 마이그레이션 확인 → 새 digest 조회 → `compose.yaml` 수정 → `make check local-up local-verify` → 사용자 확인 → `make backup`(롤백 지점, main 체크아웃의 `backups/`에 저장됨) → `make deploy verify` → 사용자에게 "병합 전까지 VM은 main이 고정하지 않은 이미지로 돈다. 다른 체크아웃에서 deploy·restore 금지"를 알리고 리뷰·병합을 바로 요청 → 롤백은 이전 `image:` 줄 + `make restore BACKUP=<롤백 지점>` |
| `bm-recover` | VM이 사라지거나 쓸 수 없을 때 | VM이 **정지**돼 있으면 사용자가 시작하고(외부 IP가 바뀌면 `.env`의 `BM_VM_PUBLIC_IP` 갱신) `make status probe` 후 멈춘다. **삭제됐거나 시작되지 않거나 데이터가 손상됐을 때만** 재구축: `rbk-2026-10-12-tcjs7m6x-gcp-vm.md`대로 VM 재생성(사용자 작업) → `ssh-keygen -R <새 공인 IP>` → `make vm-bootstrap` → 사용자 확인 → `make status`의 이미지와 `compose.yaml`의 `image:` 비교(다르면 멈추고 사용자에게 질문) → `make deploy restore BACKUP=<파일>` → Exposure audit 다시 수행. 복원이 검증되기 전에는 옛 VM과 디스크를 지우지 않는다 |
| `bm-diagnose` | 연결·MCP 문제가 있을 때 | 읽기 전용: `tailscale status`, `make status`, `make logs`, `make probe`만 실행해 원인을 좁힘. 노트를 쓰거나 무언가를 시작하는 명령은 사용자에게 제안만 함 |

## 6. Make 타깃

OCI 설계 §6과 같고 다음만 다르다.

| 분류 | 타깃 | 동작 |
|---|---|---|
| VM | `status` | 컨테이너 상태, 메모리·스왑 사용량(스왑이 없으면 경고), Serve 상태 |

Makefile은 항상 main 체크아웃의 `.env`를 읽는다(§7.1). 수명주기 작업은 Make 타깃으로만 한다. raw `docker compose`나 `ssh`는 Make 타깃 실패를 진단할 때만 쓰고 그 이유를 기록한다.

## 7. 컴포넌트 동작

OCI 설계 §7과 같고 다음만 다르다.

### 7.1 설정 값

- 로컬 기본값은 `compose.yaml` 안에 둔다. 로컬은 `.env` 없이도 동작한다.
- VM용 값(`/srv/basic-memory/...`)은 `deploy.sh`가 원격 `/opt/basic-memory/.env`로 생성한다.
- 사용자별 값(`BM_VM_HOST`, `BM_VM_USER`, `BM_TAILNET_DOMAIN`, `BM_VM_PUBLIC_IP`)은 git ignore 대상인 `.env`에 둔다. **`.env`는 main 체크아웃에만 둔다.** Makefile은 어느 체크아웃에서 실행하든 main 체크아웃(`git rev-parse --path-format=absolute --git-common-dir`의 상위)의 `.env`를 include한다. worktree에 있는 `.env`는 읽지 않는다. `review.sh`가 `$MAIN_ROOT/.review-out`을 쓰는 것과 같은 방식이다.
- 유일한 비밀값은 Tailscale 인증 키다. 저장소에는 어떤 형태로도 두지 않는다.
- 2026-10-14 갱신: [SilverBullet 웹 UI 설계](spec-2026-10-14-cjerm8b4-silverbullet-web-ui.md)가 두 번째 비밀값 `SB_USER`를 더한다(§8.3).

### 7.4 `bootstrap-vm.sh HOST`

OCI 설계 §7.4의 단계에 **스왑 단계**를 더한다. 단계마다 이미 된 일은 건너뛰므로 다시 실행해도 결과가 같다.

1. **스왑:** 활성 스왑이 없으면 `/swapfile`을 `SWAP_SIZE_MB`(1024) 크기로 만들고 0600 권한, `mkswap`, `swapon`을 거쳐 `/etc/fstab`에 한 번만 등록한다. 활성 스왑이 있으면 건너뛴다. 1GB 머신에서는 apt와 dpkg가 메모리를 많이 쓰므로 가장 먼저 한다.
2. 공식 apt 저장소로 Docker Engine과 compose 플러그인을 설치하고, `ubuntu`를 docker 그룹에 추가한다.
3. Tailscale 설치와 tailnet 참여(인증 키는 stdin → `/run`의 0600 임시 파일 → `--auth-key=file:` → 즉시 삭제).
4. `/srv/basic-memory/{knowledge,config}`를 1000:1000으로, `/opt/basic-memory`를 `ubuntu` 소유로 만든다.
5. `tailscale serve --bg http://127.0.0.1:8737`을 적용하고 결과를 다시 읽어 확인한다.
6. 다음 단계를 안내한다: `ssh ubuntu@agent-hub true`로 Tailscale SSH 확인 → 성공한 뒤에만 22번을 여는 방화벽 규칙 삭제(`docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md`).

### 7.6 `verify-vm.sh` 메시지

검사 내용은 OCI 설계와 같다. 공인 IP를 찾는 안내는 런북(`rbk-2026-10-12-tcjs7m6x-gcp-vm.md`)을 가리키고, 열린 포트를 발견하면 "remove the firewall rule that allows it"로 안내한다. 방화벽 규칙과 tailnet 정책은 VM에서 읽을 수 없으므로 Exposure audit으로 수동 점검한다.

### 7.7 `status.sh`

원격 컨테이너 상태와 health, 메모리 사용률과 스왑 사용량, `tailscale serve status`를 출력한다. 활성 스왑이 없으면 "rerun make vm-bootstrap"을 안내하는 경고를 낸다. 유휴 회수 경고는 없다.

### 7.8 `backup.sh`

OCI 설계와 같고, 기본 저장 위치 `BACKUP_DIR`이 **main 체크아웃의 `backups/`** 다. worktree에서 실행해도 아카이브는 main 체크아웃에 남는다. 출력하는 저장 경로는 절대 경로다.

## 8. 운영 흐름 (런북)

1. **`rbk-2026-10-12-hqxjjqy8-accounts.md` (사용자):**
   - GCP: 개인 Google 계정으로 결제 계정과 전용 프로젝트를 만든다. Budget 알림(월 $1)을 먼저 만든다.
   - 로컬 gcloud: `gcloud config configurations create bm-personal --no-activate` → `gcloud auth login --configuration=bm-personal` → `gcloud config set project <프로젝트> --configuration=bm-personal`. 회사 설정은 활성 상태로 둔다. `gcloud config configurations activate`와 `gcloud auth application-default ...`는 실행하지 않는다.
   - Tailscale: 가입 → MagicDNS와 HTTPS 인증서 켜기 → 정책에 `funnel` 속성이 있으면 제거 → `tag:agent-hub`와 Tailscale SSH 규칙 정의 → 인증 키는 부트스트랩 직전에 발급(사전 승인, 1회용, 태그).
   - `.env`는 main 체크아웃에서 `.env.example`을 복사해 만든다.
2. **`rbk-2026-10-12-tcjs7m6x-gcp-vm.md` (사용자, gcloud):** 모든 명령에 `--configuration=bm-personal`을 붙이고, 첫 단계에서 `gcloud config list --configuration=bm-personal`로 계정과 프로젝트를 확인한다.
   - 생성(재구축 포함): `e2-micro`, `us-west1-b`, Ubuntu 26.04 LTS Minimal amd64, `pd-standard` 30GB, `--provisioning-model=STANDARD`, Premium 티어, 메타데이터 `ssh-keys=ubuntu:<공개키>`.
   - 확인: `scheduling.provisioningModel`이 `STANDARD`, 디스크 종류가 `pd-standard`, 프로젝트 메타데이터에 `enable-oslogin=TRUE`가 없음.
   - 방화벽: `default-allow-rdp`·`default-allow-icmp` 삭제, `default-allow-ssh`를 본인 IP/32로 제한.
   - 공인 IP 조회 명령과 `.env`의 `BM_VM_PUBLIC_IP` 갱신(정지 후 시작하면 IP가 바뀜).
   - Spot으로 잘못 만들었을 때의 전환 절차(§3의 export → 수정 → update-from-file).
3. **`rbk-2026-10-12-ha5w72pm-bootstrap.md`:**
   - `make vm-bootstrap HOST=<공인IP>` → `ssh ubuntu@agent-hub true` 확인 → `default-allow-ssh` 삭제 → `make deploy verify status`
   - Exposure audit을 수동으로 마친다.
   - 비상 경로: 22번 규칙을 gcloud로 다시 추가하거나 GCP 시리얼 콘솔을 쓴다.
4. **`rbk-2026-10-12-t79ex2ny-operations.md`:**
   - VM 대상(`deploy`, `verify`, `backup`, `restore` 등)은 main 체크아웃에서 실행하는 것이 기본이다. worktree에서 실행해도 `.env`와 `backups/`는 main 체크아웃 것을 쓴다.
   - 배포·복원 전: `make status`의 이미지와 `compose.yaml`의 `image:`가 같은지 확인한다. 다르면 멈추고 사용자에게 묻는다.
   - 점검: `make status`. 백업: `make backup` (중요 작업 전 + 주 1회 권장)
   - Exposure audit: 배포 직후와 방화벽·정책을 바꾼 뒤 `gcloud compute firewall-rules list --configuration=bm-personal`과 tailnet 정책을 점검하고 기록한다.
   - 비용 점검: 배포 다음 날과 매월 초 청구 보고서를 SKU별로 확인한다.
   - VM이 정지돼 있으면 시작한다. `bm-recover`의 재구축은 삭제됐거나 쓸 수 없는 VM에만 쓴다.

## 9. 테스트와 검증

OCI 설계 §9와 같고 다음을 더한다. 다만 OCI §9의 테스트 요구 중 어떤 것이 대체됐는지는 [test-scope ADR](../decisions/adr-2026-10-13-a878ypj5-test-scope.md)을 따른다.

- **스왑 (`tests/bootstrap.bats`):** 활성 스왑이 없으면 파일을 만들고 켜며 fstab에 한 번만 등록한다. 활성 스왑이 있으면 아무것도 하지 않는다. 다시 실행해도 fstab 줄이 늘지 않는다. 스텁: `swapon`, `fallocate`, `mkswap`.
- **`status` (`tests/vm_ops.bats`):** 메모리·스왑을 출력하고, 스왑이 없으면 경고한다. 유휴 회수 테스트는 지운다.
- **클라우드 중립 (`tests/cloud_neutral.bats`):** `scripts/` 아래 모든 파일(주석 포함)에 `OCI`, `Oracle`, `GCP`, `gcloud`가 단어 단위로, 대소문자 구분 없이 나오지 않는다. 유일한 예외는 스크립트가 런북을 가리키는 경로 `docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md`다.
- **main 체크아웃 기준 경로:** worktree에서 실행해도 `backup.sh`가 main 체크아웃의 `backups/`에 저장하고, Makefile이 worktree의 `.env`가 아니라 main 체크아웃의 `.env`를 읽는다.
- **E2E (VM, 수동, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)):** §3의 Assumption, 스왑 활성, 재부팅 뒤 외부 IP 유지, Tailscale SSH만으로 `vm-bootstrap` 재실행, 완료 조건 5(청구)를 확인하고 진행 로그에 기록한다.

## 10. 위험과 대응

| 위험 | 대응 |
|---|---|
| 외부 IPv4 과금 | Budget 알림, 다음 날 SKU 확인(완료 조건 5). 공식 가격표로 유료임을 확인했고, 사용자가 IPv6 전환을 결정했다([ipv6-egress 계획](../plans/plan-2026-10-13-gaewewkf-ipv6-egress.md)) |
| 1GB RAM 부족(OOM) | 스왑 1GB, `status` 경고. 반복되면 [vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)에서 재판단 |
| 무료 아웃바운드 1GB/월 초과 | 노트는 작다. DERP 중계 트래픽도 포함되므로 청구 보고서로 확인 |
| 정지 후 시작 시 외부 IP 변경 | 런북의 IP 조회와 `.env` 갱신 안내. `verify`가 옛 IP로 검사하지 않도록 `BM_VM_PUBLIC_IP` 필수 유지 |
| 22번 규칙이 특정 IP에 묶임 | 다른 곳에서 부트스트랩하면 규칙 수정. Tailscale SSH 확인 후 삭제 |
| 회사 gcloud 설정 오사용 | 모든 명령에 `--configuration=bm-personal`, 런북 첫 단계에서 계정·프로젝트 확인 |
| 26.04 Minimal에 필요한 도구 없음 | [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) 첫 단계에서 확인. 없으면 부트스트랩에 패키지 설치 추가 |
| OS Login이 켜져 메타데이터 키 무시 | [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)에서 프로젝트 메타데이터 확인 |
| Tailscale SSH 전환 실패로 접속 상실 | Tailscale SSH 확인 후에만 22번 삭제. 비상 시 gcloud로 규칙 재추가 또는 시리얼 콘솔 |
| worktree 삭제로 백업 손실 | `backups/`와 `.env`를 main 체크아웃에 고정(§7.1, §7.8). git-workflow 정리 단계에서 worktree의 `backups/`를 먼저 확인 |
| 업그레이드 리뷰 중 옛 이미지로 deploy·restore | 배포·복원 전 이미지 비교(§8.4), `bm-upgrade`의 경고 |
| 인증 없는 엔드포인트 노출 | `127.0.0.1` 바인딩, Serve tailnet 전용, 외부 소스 인바운드 0개. 구조 테스트, `make verify`, Exposure audit |
| 복원·업그레이드 롤백 중 데이터 손상 | 임시 경로에 풀고 manifest 대조 후 교체, 실패 시 자동 롤백, 이미지와 데이터를 함께 복원 |
| 기기 이름의 CT 로그 공개 | 일반적인 이름 `agent-hub` 사용 |
| 회사 기기의 개인 tailnet 참여 | Open question으로 남기고 사용자가 확인 |
