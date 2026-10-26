---
status: accepted
id: tgw26pj8
date: 2026-10-26
---

# ADR tgw26pj8: 문서는 순번 대신 무작위 ID로 구분하고, 승인 전 초안은 Basic Memory 초안 보드에 둔다

- 설계: [문서 고유 ID와 초안 보드 설계](../specs/spec-2026-10-23-q3jxc77k-doc-ids-and-draft-board.md)
- 대체 범위: 문서 체계 설계의 번호 규칙(계획 `NN`, ADR `NNNN`, `make new-doc`의 "가장 큰 번호 + 1"), 브랜치 이름 `plan/<NN>-<slug>`, 트레일러 `Plan: <NN|none>`.

## 맥락과 문제

- 여러 기기와 벤더의 에이전트가 서로의 승인 전 초안을 보지 못한다. 2026-10-22에는 커밋 전 스펙 본문에만 적힌 "계획 24"를 다른 세션의 `make new-doc`이 다시 내줘서, 한 계획의 번호를 손으로 바꿨다(설계 §2).
- 체크아웃마다 "가장 큰 번호 + 1"을 고르는 방식은, 할당을 한 곳에서 직렬화하지 않는 한 병렬 브랜치에서 반드시 충돌한다. adr-tools, Spec Kit과 여러 에이전트 저장소에서 같은 실패가 보고됐다(조사 노트 §1).
- 저장소는 공개라서 승인 전 초안을 push하면 영구히 공개된다(조사 노트 §4).

## 검토한 대안

1. 번호를 두고 승인 때 붙이기(조사 보고서의 추천 B): 기존 인용을 살린다. 승인 시점의 확인과 CI가 열린 PR까지 봐야 하고, 승인 전 초안에는 이름이 없다.
2. 이슈·PR 번호를 문서 번호로 쓰기: 서버가 원자적으로 할당한다. 번호가 듬성듬성해지고, 이슈를 만드는 일이 공개 게시다.
3. 초안을 공개 저장소에 일찍 push하기: 가장 단순하다. 승인 전 초안이 영구 공개되고, 초안 커밋은 승인을 받는다는 사용자 규칙과 부딪힌다.
4. 비공개 동반 저장소에 초안 두기: 수정 이력이 남고 터널이 필요 없다. 기기마다 두 번째 저장소가 필요하고, 잘못된 원격에 push할 위험이 생긴다.
5. 무작위 ID + Basic Memory 초안 보드(선택): 할당에 조율이 필요 없고 초안이 공개되지 않는다. 대신 기존 문서 62개의 이름과 인용을 모두 바꾸고, 초안을 보려면 터널이 필요하다.

## 결정

1. 모든 타입의 문서는 소문자·숫자 8자 ID(Crockford base32 소문자)로 구분한다. 이름은 `<코드>-<날짜>-<ID>-<slug>.md`이고, front matter `id`가 이름의 ID와 같아야 한다.
2. 계획 브랜치는 `plan/<ID>-<slug>`, 트레일러는 `Plan: <ID|none>`이다. `work/<slug>`는 그대로다.
3. 승인 전 스펙·계획·ADR 초안의 정본은 Basic Memory `main` 프로젝트의 `agent-drafts/<프로젝트 키>/`에 있는 노트다. 승인되면 같은 ID로 저장소 문서가 되고, 그 뒤의 정본은 저장소 문서다.
4. 기존 문서 전부에 소급한다. 이름, front matter 경로, 링크, 본문의 번호 인용, 완료된 계획과 리뷰 기록의 브랜치 이름과 트레일러까지 바꾼다. 증거 문장을 고치지 않는다는 규칙의 일회성 예외다.
5. git 이력은 설계 §3.5의 조건을 모두 만족할 때, 바꿀 수 있는 것을 모두 다시 쓴다. 대상은 경로, 모든 커밋의 파일 내용, 커밋 메시지, `main` 안의 SHA 인용, PR #1~#20의 제목·본문과 머신 계정 코멘트다. 조건을 만족하지 못하면 아래 대응표로 대신한다.

## 결과

- 문서 번호 충돌과 승인 전 번호 예약이 없어진다. 다른 기기와 벤더의 에이전트가 MCP로 승인 전 초안을 찾는다.
- 치르는 것:
  - 기존 인용(대화, 에이전트 메모리, GitHub의 옛 PR 제목과 본문)의 번호가 끊긴다. 대응표가 다리 역할을 한다.
  - 초안을 쓰고 읽으려면 터널이 필요하다. Codex 클라우드는 승인 전 초안을 보지 못한다.
  - 이력 재작성을 하면 모든 커밋 SHA가 바뀐다. `main` 안의 SHA 인용은 재작성 때 함께 바뀌지만, PR 참조와 GitHub 밖의 사본에 있는 옛 SHA는 남는다.
- 확인 방법:
  - `make check`의 문서 검사(이름과 front matter의 ID 일치, 유일성)
  - `make check-git`과 `pr-rules`(ID 형식의 브랜치와 트레일러)
  - 설계 §3.5의 재작성 검증 다섯 가지
  - 설계 완료 조건 7의 초안 보드 확인

## 부록: 옛 번호 대응표

설계 §3.4의 이름 변경(2026-10-26)에서 채웠다. 옛 이름 열에는 각 문서가 이 계획 직전에 가진 이름을 적는다. 이력 재작성의 치환 규칙에 걸리지 않도록 경로와 확장자 없이 날짜, 번호, slug를 띄어 적고, 그보다 오래된 이름은 "그 전:" 뒤에 적는다. 리뷰 기록 이름의 `plan-NN-` 접두어는 `plan-NN`으로 적는다.

- 한 문서가 이력에서 가진 이름은 한 행에 있다. 코드 접두어(`plan-` 등)만 없거나 계획의 `backlog`·`active`·`completed` 하위 폴더에 있던 옛 이름은 날짜·번호·slug가 같아서 따로 적지 않는다. 그 밖의 옛 이름(날짜가 없던 이름, `-design`이 붙은 스펙, 번호를 바꾸기 전 이름)은 "그 전:" 뒤에 적는다.
- "삭제됨"은 HEAD에 없는 문서다. 새 이름의 파일은 없고, 이력 재작성이 그 문서의 옛 경로를 이 이름으로 바꾼다.
- ADR 번호 0001은 서로 다른 두 문서(OCI 시절 ADR, GCP ADR)가 썼으므로 행이 둘이다. vm-scripts·docs-skills·vm-rollout 계획은 번호를 바꾼 커밋(`750c7c3`) 전에 지금보다 하나 작은 번호를 썼다("그 전:"의 이름).

| 타입 | 옛 이름 (날짜 번호 slug) | 새 ID | 새 이름 |
|---|---|---|---|
| spec | 2026-10-07 basic-memory-oci-tailscale (그 전: 2026-10-07 basic-memory-oci-tailscale-design) | p7h3jvpf | spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md |
| spec | 2026-10-07 git-review-policy (그 전: 2026-10-07 git-review-policy-design) | restd5vd | spec-2026-10-07-restd5vd-git-review-policy.md |
| spec | 2026-10-12 basic-memory-gcp-tailscale (그 전: 2026-10-12 basic-memory-gcp-tailscale-design) | p5nmsc4m | spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md |
| spec | 2026-10-13 github-pr-workflow (그 전: 2026-10-13 github-pr-workflow-design) | pr762r68 | spec-2026-10-13-pr762r68-github-pr-workflow.md |
| spec | 2026-10-14 silverbullet-web-ui (그 전: 2026-10-14 silverbullet-web-ui-design) | cjerm8b4 | spec-2026-10-14-cjerm8b4-silverbullet-web-ui.md |
| spec | 2026-10-15 access-modes (그 전: 2026-10-15 access-modes-design) | jr59pvyf | spec-2026-10-15-jr59pvyf-access-modes.md |
| spec | 2026-10-15 doc-system (그 전: 2026-10-15 doc-system-design) | sgpbx1gq | spec-2026-10-15-sgpbx1gq-doc-system.md |
| spec | 2026-10-15 script-test-layout (그 전: 2026-10-15 script-test-layout-design) | d8q0b7bt | spec-2026-10-15-d8q0b7bt-script-test-layout.md |
| spec | 2026-10-22 agent-memory-mirror | at2p2mw9 | spec-2026-10-22-at2p2mw9-agent-memory-mirror.md |
| spec | 2026-10-22 web-connector | tn23wwmd | spec-2026-10-22-tn23wwmd-web-connector.md |
| spec | 2026-10-23 doc-ids-and-draft-board | q3jxc77k | spec-2026-10-23-q3jxc77k-doc-ids-and-draft-board.md |
| plan (삭제됨) | 2026-10-07 basic-memory-oci-tailscale | c9byb5z1 | plan-2026-10-07-c9byb5z1-basic-memory-oci-tailscale.md |
| plan | 2026-10-07 01 local-foundation | sqzn0teq | plan-2026-10-07-sqzn0teq-local-foundation.md |
| plan | 2026-10-07 02 git-review-tooling | qq4h1djv | plan-2026-10-07-qq4h1djv-git-review-tooling.md |
| plan | 2026-10-07 03 vm-scripts (그 전: 2026-10-07 02 vm-scripts) | dry1xr43 | plan-2026-10-07-dry1xr43-vm-scripts.md |
| plan | 2026-10-07 04 docs-skills (그 전: 2026-10-07 03 docs-skills) | hydaxf15 | plan-2026-10-07-hydaxf15-docs-skills.md |
| plan | 2026-10-07 05 vm-rollout (그 전: 2026-10-07 04 vm-rollout) | qtvzskgx | plan-2026-10-07-qtvzskgx-vm-rollout.md |
| plan | 2026-10-13 06 test-pruning | g57mry4b | plan-2026-10-13-g57mry4b-test-pruning.md |
| plan | 2026-10-13 07 ipv6-egress | gaewewkf | plan-2026-10-13-gaewewkf-ipv6-egress.md |
| plan | 2026-10-13 08 github-switch | k93wjt1a | plan-2026-10-13-k93wjt1a-github-switch.md |
| plan | 2026-10-13 09 review-posting | znbc3ase | plan-2026-10-13-znbc3ase-review-posting.md |
| plan | 2026-10-14 10 web-ui-local | n6xpm12e | plan-2026-10-14-n6xpm12e-web-ui-local.md |
| plan | 2026-10-14 11 web-ui-vm-rollout | a88datfz | plan-2026-10-14-a88datfz-web-ui-vm-rollout.md |
| plan | 2026-10-15 12 access-modes | ctv444ep | plan-2026-10-15-ctv444ep-access-modes.md |
| plan | 2026-10-16 13 doc-system-foundation | wyz3h870 | plan-2026-10-16-wyz3h870-doc-system-foundation.md |
| plan | 2026-10-16 14 doc-rename-and-checks | pqffvttt | plan-2026-10-16-pqffvttt-doc-rename-and-checks.md |
| plan | 2026-10-16 15 doc-body-backfill | hyajr3k3 | plan-2026-10-16-hyajr3k3-doc-body-backfill.md |
| plan | 2026-10-20 16 script-cleanup | c2vxa7kp | plan-2026-10-20-c2vxa7kp-script-cleanup.md |
| plan | 2026-10-21 17 test-cleanup | hf9kadp3 | plan-2026-10-21-hf9kadp3-test-cleanup.md |
| plan | 2026-10-22 18 public-text-guard | v9whrbs6 | plan-2026-10-22-v9whrbs6-public-text-guard.md |
| plan | 2026-10-22 19 invariant-enforcement | m97w7hqe | plan-2026-10-22-m97w7hqe-invariant-enforcement.md |
| plan | 2026-10-22 20 agent-sandbox | k3bd8k47 | plan-2026-10-22-k3bd8k47-agent-sandbox.md |
| plan | 2026-10-22 21 recovery-drill | zw0shxee | plan-2026-10-22-zw0shxee-recovery-drill.md |
| plan | 2026-10-22 22 agent-guidance | x4d2x4eq | plan-2026-10-22-x4d2x4eq-agent-guidance.md |
| plan | 2026-10-22 23 review-and-local-isolation | z064dkcv | plan-2026-10-22-z064dkcv-review-and-local-isolation.md |
| plan | 2026-10-22 24 agent-memory-mirror | mk823xbp | plan-2026-10-22-mk823xbp-agent-memory-mirror.md |
| plan | 2026-10-22 25 web-connector | d3dpb00s | plan-2026-10-22-d3dpb00s-web-connector.md |
| plan | 2026-10-26 26 doc-ids | e3svnr3h | plan-2026-10-26-e3svnr3h-doc-ids.md |
| adr | 2026-10-12 0001 basic-memory-on-gcp-tailscale (그 전: 0001 basic-memory-on-gcp-tailscale) | m4yy1sb7 | adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md |
| adr (삭제됨) | 0001 basic-memory-on-oci-tailscale | b229z2y6 | adr-2026-10-12-b229z2y6-basic-memory-on-oci-tailscale.md |
| adr | 2026-10-12 0002 vm-sizing (그 전: 0002 vm-sizing) | mdq5exsf | adr-2026-10-12-mdq5exsf-vm-sizing.md |
| adr | 2026-10-13 0003 skill-structure (그 전: 0003 skill-structure) | m0xvj6rr | adr-2026-10-13-m0xvj6rr-skill-structure.md |
| adr | 2026-10-13 0004 test-scope (그 전: 0004 test-scope) | a878ypj5 | adr-2026-10-13-a878ypj5-test-scope.md |
| adr | 2026-10-15 0005 web-ui-silverbullet (그 전: 0005 web-ui-silverbullet) | f7n75bpv | adr-2026-10-15-f7n75bpv-web-ui-silverbullet.md |
| adr | 2026-10-15 0006 access-modes (그 전: 0006 access-modes) | cz8c26gp | adr-2026-10-15-cz8c26gp-access-modes.md |
| adr | 2026-10-16 0007 structure-checks | q36rwq5s | adr-2026-10-16-q36rwq5s-structure-checks.md |
| adr | 2026-10-22 0008 web-connector | fcvznmdc | adr-2026-10-22-fcvznmdc-web-connector.md |
| adr | 2026-10-23 0009 doc-ids-and-draft-board | tgw26pj8 | adr-2026-10-23-tgw26pj8-doc-ids-and-draft-board.md |
| runbook | 2026-10-12 accounts (그 전: accounts) | hqxjjqy8 | rbk-2026-10-12-hqxjjqy8-accounts.md |
| runbook | 2026-10-12 bootstrap (그 전: bootstrap) | ha5w72pm | rbk-2026-10-12-ha5w72pm-bootstrap.md |
| runbook | 2026-10-12 gcp-vm (그 전: gcp-vm) | tcjs7m6x | rbk-2026-10-12-tcjs7m6x-gcp-vm.md |
| runbook (삭제됨) | oci-vm | vebvx40g | rbk-2026-10-12-vebvx40g-oci-vm.md |
| runbook | 2026-10-12 operations (그 전: operations) | t79ex2ny | rbk-2026-10-12-t79ex2ny-operations.md |
| runbook | 2026-10-14 github (그 전: github) | ppmby9v6 | rbk-2026-10-14-ppmby9v6-github.md |
| research | 2026-10-13 agent-oss-git-strategies | djx2fzm5 | rsch-2026-10-13-djx2fzm5-agent-oss-git-strategies.md |
| research | 2026-10-15 agent-repo-conventions | f20fshxg | rsch-2026-10-15-f20fshxg-agent-repo-conventions.md |
| research | 2026-10-22 web-connector-exposure | ayedpfen | rsch-2026-10-22-ayedpfen-web-connector-exposure.md |
| research | 2026-10-23 multi-agent-draft-sharing | fak5h16f | rsch-2026-10-23-fak5h16f-multi-agent-draft-sharing.md |
| review | 2026-10-07 plan-01 local-foundation (그 전: plan-01 local-foundation) | bwvfm8bx | rev-2026-10-07-bwvfm8bx-local-foundation.md |
| review | 2026-10-08 plan-02 git-review-tooling (그 전: plan-02 git-review-tooling) | tscgvpsz | rev-2026-10-08-tscgvpsz-git-review-tooling.md |
| review | 2026-10-08 plan-03 vm-scripts (그 전: plan-03 vm-scripts) | ejeb10qw | rev-2026-10-08-ejeb10qw-vm-scripts.md |
| review | 2026-10-12 plan-04 docs-skills (그 전: plan-04 docs-skills) | aqhzgwq1 | rev-2026-10-12-aqhzgwq1-docs-skills.md |
| review | 2026-10-12 work-rename-agent-hub (그 전: work-rename-agent-hub) | qyfzj5ht | rev-2026-10-12-qyfzj5ht-work-rename-agent-hub.md |
| review | 2026-10-13 plan-06 test-pruning (그 전: plan-06 test-pruning) | g6358b35 | rev-2026-10-13-g6358b35-test-pruning.md |
| review | 2026-10-13 work-backup-skip-model-cache (그 전: work-backup-skip-model-cache) | agxyktrn | rev-2026-10-13-agxyktrn-work-backup-skip-model-cache.md |
| review | 2026-10-13 work-skill-best-practices (그 전: work-skill-best-practices) | ycht90mr | rev-2026-10-13-ycht90mr-work-skill-best-practices.md |
| review | 2026-10-13 work-slow-start-health (그 전: work-slow-start-health) | af5vkb8q | rev-2026-10-13-af5vkb8q-work-slow-start-health.md |
| review | 2026-10-13 work-workflow-alignment (그 전: work-workflow-alignment) | aqjax47t | rev-2026-10-13-aqjax47t-work-workflow-alignment.md |
