---
status: backlog
id: s1amnk1s
spec: none
---

# s1amnk1s External IPv4 Egress Decision Plan

> [ipv6-egress 계획](plan-2026-10-13-gaewewkf-ipv6-egress.md)을 `ssh` 접속 모드 기준으로 다시 쓴 계획이다. 2026-11-02 저장소 재검토 4장의 판단을 사용자가 승인했다. 이 계획은 결정까지만 한다. 외부 IPv4를 바꾸기로 정하면 구현은 brainstorming → 스펙 → 계획 순서로 따로 한다.

> **For agentic workers:** Task를 순서대로 하나씩 구현한다. 도구가 서브에이전트를 지원하면 Task마다 새 서브에이전트와 리뷰를 쓰고, 아니면 한 세션에서 실행한다. VM이나 클라우드를 바꾸는 Step은 메인 세션에서 사용자와 함께, 단계마다 OK를 받고 한다. Step은 체크박스(`- [ ]`)로 추적한다.

**Goal:** 외부 IPv4의 실제 청구 금액을 확인하고, 금액이 있으면 `ssh` 모드 VM의 송신 경로를 유지할지 바꿀지 ADR로 정한다.

**Architecture:**
- Step 0에서 사용자가 10월분 청구 보고서로 금액을 확인한다. 크레딧 적용 전에도 0원이면 이 계획을 `dropped`로 닫고, 근거를 ARCHITECTURE와 운영 런북에 `Verified`로 적는다.
- 금액이 있으면 세 선택지만 비교한다: A) 외부 IPv4 유지, B) 외부 IPv4를 없애고 Cloud NAT, C) 외부 IPv4를 없애고 Artifact Registry remote repository와 Private Google Access. 조사 노트 하나와 ADR 하나를 남긴다.
- VM과 클라우드 리소스는 바꾸지 않는다. 읽기 전용 `gcloud ... describe`·`list`만 쓴다.

**Spec:** none. 이유: 결정을 위한 조사와 ADR만 남기고 구성 요소를 바꾸지 않는다. 함께 읽을 곳: [GCP 스펙](../specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md) §3, [access-modes 스펙](../specs/spec-2026-10-15-jr59pvyf-access-modes.md) §2·§3, [semantic-search-off ADR](../decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md).

**Sequence:** Step 0은 언제든 할 수 있다. Task 1부터는 Step 0의 금액이 0보다 클 때만 한다.

## 배경

- **Verified (2026-10-13, GCP 스펙 §3):** 공식 가격표상 표준 VM의 외부 IPv4는 시간당 $0.005이고 무료 등급은 계정당 월 1시간뿐이라 월 약 $3.65다. 외부 IPv6는 무료다.
- **Verified (2026-10-14, [vm-rollout 계획](plan-2026-10-07-qtvzskgx-vm-rollout.md) Progress log):** STANDARD VM의 외부 IPv4는 38.23시간 동안 정가(할인 전 금액)부터 ₩0으로 집계됐다. 그래서 크레딧으로는 설명되지 않는다. 가격표와 다른 이유(무료 등급 적용인지, 집계 지연인지)는 확인하지 못했고, 10월 청구서로 다시 확인하기로 했다.
- **Assumption:** 38시간 표본이라 집계 지연일 수 있다. 그래서 한 달 치 금액을 본다. 청구 합계는 크레딧이 상쇄할 수 있으므로 크레딧 적용 전 SKU별 금액을 본다.
- **Verified (access-modes 스펙 `:71`):** IAP TCP forwarding은 VM의 기본 내부 IPv4로 접속하고 외부 IP가 없어도 된다. 그래서 옛 계획의 설계 질문 6(공인 IPv4 없이 첫 SSH)은 `ssh` 모드가 이미 풀었다.
- **Verified (semantic-search-off ADR):** 의미 검색이 꺼져 임베딩 모델을 내려받지 않는다. 옛 계획의 `cdn-lfs.huggingface.co` 경로(설계 질문 4)는 더 이상 필요하지 않다.
- **Verified (2026-10-13, 옛 계획):** `ghcr.io`에는 AAAA가 없다. 그래서 IPv6만으로는 Basic Memory·SilverBullet 이미지를 받을 수 없고, 이 계획은 IPv6 전환을 선택지에서 뺀다.
- **Verified (2026-11-02, `compose.yaml`, `scripts/remote/provision-vm.sh`):** VM의 송신은 apt(Ubuntu 미러, `download.docker.com`), 이미지 받기(`ghcr.io`의 basic-memory·silverbullet, `BM_WEB=on`이면 Docker Hub의 python·cloudflared), `BM_WEB=on`일 때 `cloudflared`의 Cloudflare 연결이다.
- **Verified (2026-11-02, `scripts/verify-vm.sh`):** `make verify`와 `make probe`는 `BM_VM_PUBLIC_IP`의 포트 차단을 검사한다. 외부 IPv4를 없애면 이 검사를 바꿔야 한다.

## Global Constraints

- VM, 방화벽, 서브넷, 라우터, NAT, Artifact Registry를 만들거나 바꾸지 않는다. `gcloud`는 `--configuration=bm-personal`로 읽기 전용 `describe`·`list`만 쓴다.
- 청구 금액은 사용자가 확인한다. 에이전트는 결제 계정 화면에 접근하지 않는다.
- 가격과 무료 등급은 기억으로 단정하지 않는다. 그날 공식 가격 페이지를 열고 원문과 링크를 적는다.
- VM의 외부·tailnet IP는 Progress log, ADR, PR에 쓰지 않는다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: s1amnk1s`, `Task: <N|review|none>`.

## Review Focus

1. 선택지 C는 Google API만 내부로 잇는다. apt 미러, Docker Hub 이미지, `BM_WEB=on`의 Cloudflare 연결이 C에서 어떻게 되는지 빠지면 결정이 틀린다. Task 1의 비교표가 경로마다 칸을 둔다.
2. 외부 IPv4를 없애면 `make verify`·`make probe`의 공인 IP 검사와 Exposure audit이 바뀐다. Task 2의 ADR "영향" 절이 적는다.

## File Structure

| 파일 | 책임 | Task |
|---|---|---|
| 이 계획 | Step 0 결과, Progress log, `status` | 0, 1, 2 |
| `docs/ARCHITECTURE.md`, 운영 런북 | 외부 IPv4 비용의 `Open question`을 결과로 바꿈 | 0 또는 2 |
| 새 조사 노트(`make new-doc TYPE=research`) | 세 선택지의 가격과 송신 경로별 동작 | 1 |
| 새 ADR(`make new-doc TYPE=adr`) | 사용자의 선택과 영향 | 2 |

---

### Start: branch, worktree, draft PR

- [ ] `git fetch origin` 뒤 `origin/main`에서 worktree와 `plan/s1amnk1s-ipv4-egress-decision` 브랜치를 만든다(`git-workflow` 스킬의 Start).
- [ ] 첫 커밋에서 front matter의 `status`를 `active`로 바꾸고 push한 뒤 초안 PR을 연다.

### Step 0: Billing check (user)

- [ ] 사용자가 10월분(2026-10-01~31) 청구 보고서에서 SKU `External IP Charge on a Standard VM`의 크레딧 적용 전 금액을 확인한다. 경로: Billing > Reports, 프로젝트 필터, Group by SKU, 크레딧(프로모션 등) 제외. 화면의 정확한 이름은 확인하지 않았다(**Assumption**). 에이전트는 결과(금액, 확인한 날, 크레딧 제외 여부)만 Progress log에 적는다.
  - 0원: ARCHITECTURE와 운영 런북의 외부 IPv4 비용 `Open question`을 이 결과로 바꿔 `Verified`로 적고, 이 계획을 `dropped`("크레딧 전에도 0원")로 닫는다. Task 1~2는 하지 않는다.
  - 0원보다 큼: Task 1로 간다.

### Task 1: Compare the three egress options

**Files:**
- Create: `docs/research/rsch-<날짜>-<id>-ipv4-egress-options.md`(`make new-doc TYPE=research SLUG=ipv4-egress-options`)

- [ ] **Step 1: 가격 조사.** 그날 공식 페이지에서 외부 IPv4, Cloud NAT(게이트웨이 시간, 처리 GB), Artifact Registry(저장, 송신, 무료 등급), Private Google Access 요금을 원문으로 적는다. 월 예상액은 이 VM의 사용량(이미지 갱신 빈도와 크기)으로 계산하고 계산식을 남긴다.
- [ ] **Step 2: 경로별 동작.** 선택지 B·C에서 apt(Ubuntu 미러, `download.docker.com`), `ghcr.io` 이미지, Docker Hub 이미지, `cloudflared`의 Cloudflare 연결, `bm-upgrade` 흐름, `make verify`·`make probe`가 각각 되는지 표로 적는다. 공식 문서로 확인한 칸은 `Verified`, 아니면 `Assumption`이다.
- [ ] **Step 3: 확인과 커밋.** Run: `make check`. Expected: exit 0. `git commit -m "docs: compare the egress options without an external IPv4" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: s1amnk1s" --trailer "Task: 1"`

### Task 2: Decision record

**Files:**
- Create: `docs/decisions/adr-<날짜>-<id>-ipv4-egress.md`(`make new-doc TYPE=adr SLUG=ipv4-egress`)
- Modify: `docs/ARCHITECTURE.md`, 운영 런북(비용 문장)

- [ ] **Step 1: 사용자 결정.** Task 1의 표와 월 예상액을 보이고 A·B·C 가운데 하나를 사용자가 고른다. 추천과 이유를 붙인다.
- [ ] **Step 2: ADR.** 결정, 고려한 대안, 영향(`make verify`·`make probe`, Exposure audit, `bm-upgrade`, `BM_WEB=on`)을 적는다. B나 C면 "구현은 새 스펙과 계획으로 한다"를 결과에 적는다.
- [ ] **Step 3: 비용 문장 갱신.** ARCHITECTURE와 운영 런북의 외부 IPv4 `Open question`을 Step 0 결과와 ADR 링크로 바꾼다.
- [ ] **Step 4: 확인과 커밋.** Run: `make check`. Expected: exit 0. `--trailer "Task: 2"`

### Finish: review and hand-off

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, 이 상자를 체크한 뒤 `status`를 `completed`로 바꿔 커밋·push한다(`Task: none`).

`completed` 커밋 뒤의 일은 계획 파일의 체크박스로 추적하지 않는다. 결과는 PR 본문 Verification과 PR 코멘트에 남긴다.
1. PR 본문 Verification에 `make check`와 CI(`check`, `pr-rules`) 결과를 적는다.
2. 다른 벤더의 읽기 전용 리뷰와 PR 코멘트 게시는 사용자 승인 후 한다(`git-workflow` 스킬의 Review and merge).
3. CI가 통과하고 열린 P0/P1이 없으면 사용자 OK를 받고 `gh pr ready <PR>`을 실행한다. 승인과 squash 병합은 사람만 한다.

## Follow-ups

- B나 C로 정하면 구현 스펙과 계획을 새로 쓴다(옛 계획의 설계 질문 1·2·5·7·9가 입력).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
