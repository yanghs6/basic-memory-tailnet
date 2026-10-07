# qtvzskgx VM Rollout Plan

> **For agentic workers:** 이 계획은 사용자 계정과 클라우드 자원을 다룬다. 서브에이전트에 맡기지 말고 사용자와 같은 세션에서 진행하며(superpowers:executing-plans), 각 단계 전에 사용자 확인을 받는다. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [local-foundation](plan-2026-10-07-sqzn0teq-local-foundation.md)·[vm-scripts](plan-2026-10-07-dry1xr43-vm-scripts.md)·[docs-skills](plan-2026-10-07-hydaxf15-docs-skills.md) 계획의 결과물로 실제 OCI VM을 구축하고, 스펙 §1의 완료 조건 1~4를 증거와 함께 충족한다.

**Architecture:** 사용자는 콘솔 작업(계정, 정책, VM 생성, 보안 규칙)을 하고, 에이전트는 Make 타깃 실행과 결과 기록을 맡는다. 새 코드는 없다. 문제가 생기면 `bm-diagnose` 스킬로 원인을 찾고, 코드 수정이 필요하면 별도 계획으로 분리한다.

**Tech Stack:** OCI Always Free(A1.Flex), Tailscale(Serve, SSH), [local-foundation](plan-2026-10-07-sqzn0teq-local-foundation.md)·[vm-scripts](plan-2026-10-07-dry1xr43-vm-scripts.md)·[docs-skills](plan-2026-10-07-hydaxf15-docs-skills.md) 계획의 Make 타깃과 런북

**Spec:** `docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md`

**Sequence:** 계획 4/4. 전제: [docs-skills 계획](plan-2026-10-07-hydaxf15-docs-skills.md) 완료(테스트 85개, 런북과 스킬 준비됨).

## Global Constraints

- 에이전트는 사용자 대신 OCI·Tailscale 콘솔 작업을 하지 않는다. VM을 바꾸는 Make 타깃(`vm-bootstrap`, `deploy`, `restore`)은 사용자 확인 뒤에만 실행한다.
- Tailscale 인증 키는 사용자가 프롬프트에 직접 붙여 넣는다. 키를 대화, 파일, 명령 인자에 남기지 않는다.
- 결과는 이 계획의 Progress log와 [vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)에 `Verified` / `Command` 표기로 기록한다. 공인 IP와 tailnet 이름은 기록하지 않는다(`<공인 IP>`, `<tailnet>`으로 가린다).

## Review Focus

1. **22번 포트를 먼저 지워 접속 불가:** Tailscale SSH 확인 전에 22번 규칙을 지우면 시리얼 콘솔 말고는 들어갈 방법이 없다. 또 정책에 `tag:bm-server`용 `ssh` 규칙이 없으면 Tailscale SSH가 거부된다. → Step 4의 순서를 지키고, Step 1에서 정책을 함께 검토한다.
2. **재부팅 후 자동 복구:** 컨테이너(`restart: unless-stopped`)와 Serve 설정(`--bg`)이 재부팅 뒤 자동으로 돌아와야 한다. → Step 7에서 확인한다.
3. **유휴 회수:** 메모리 사용률이 20% 미만이면 7일 뒤 회수될 수 있다. → Step 8에서 24시간 뒤 측정하고 [vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)을 확정한다.

---

### Task 1: VM 실제 배포 (사용자와 함께, 수동 E2E)

**Files:**
- Modify: `.env`(로컬 전용, 커밋하지 않음)
- Modify: `docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md`, 이 계획 파일의 Progress log, 스펙의 Open question 해소 내용
- Move: 이 계획 → `docs/plans/completed/`

**Interfaces:**
- Consumes: 런북 4개, 모든 VM 타깃
- Produces: 스펙 §1 완료 조건 1~4의 증거

이 Task는 사용자 계정과 클라우드 자원을 다룹니다. **각 단계 전에 사용자 확인을 받습니다.** 에이전트는 사용자 대신 콘솔 작업을 하지 않습니다.

- [ ] **Step 1 (사용자):** `docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md` 1~4단계를 완료한다. 에이전트는 정책 JSON 편집을 함께 검토한다.
- [ ] **Step 2 (사용자):** `docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md`대로 VM을 만들고, `.env`에 `BM_TAILNET_DOMAIN`과 `BM_VM_PUBLIC_IP`를 채운다.
- [ ] **Step 3 (사용자 확인 후 실행):** 인증 키를 발급한 뒤 `make vm-bootstrap HOST=<공인 IP>`를 실행한다. 사용자가 프롬프트에 키를 붙여 넣는다.
  Expected: `[bootstrap] done`과 Next steps 안내.
  **Assumption 확인:** `tailscale set --hostname --ssh`가 동작하는지 같은 명령을 한 번 더 실행해 본다(멱등성 확인). 두 번째 실행은 키 없이 `already on the tailnet`으로 끝나야 한다.
- [ ] **Step 4:** `ssh ubuntu@bm-node true` 성공을 확인한다. → (사용자) OCI 22번 인바운드 규칙을 삭제한다.
- [ ] **Step 5 (사용자 확인 후):** `make deploy verify status`
  Expected: 완료 조건 1과 2 충족(`OK: MCP round trip passed`, `listens on 127.0.0.1 only`, `refuses ports 22 and 8737`).
- [ ] **Step 6:** `make backup` → `make restore BACKUP=<방금 파일>`(사용자가 `yes` 입력)
  Expected: 완료 조건 3 충족(restore 뒤 verify 통과).
- [ ] **Step 7 (사용자 확인 후):** `ssh ubuntu@bm-node sudo reboot` → 2분 대기 → `make verify status`
  Expected: 재부팅 뒤에도 통과한다(Review Focus 2).
- [ ] **Step 8:** 24시간 뒤 `make status`의 메모리 사용률을 측정한다. [vm-sizing ADR](../decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)의 재평가 기준대로 크기를 유지하거나 조정하고, Verified로 기록한 뒤 상태를 Accepted로 바꾼다.
- [ ] **Step 9:** 스펙 §3의 Open question 중 해소된 것을 Verified로 바꾼다. Progress log에 Step 3~8의 증거를 기록한다.
- [ ] **Step 10: Commit**
```bash
git mv docs/plans/plan-2026-10-07-qtvzskgx-vm-rollout.md docs/plans/completed/
git add docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md docs/plans/completed
git commit -m "docs: record VM rollout evidence and close milestone 1"
```


---

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
