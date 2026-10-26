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

## 이전 결과

2026-10-26에 `main`의 git 이력을 한 번 재작성했다. 절차는 설계 §3.5, 계획의 Task 4다.

- **Verified:** 재작성했다. `main`의 끝이 재작성 전 a1d77be에서 829e77a로 바뀌었다. 커밋 160개, 병합 커밋 12개는 그대로다. 작성자, 커밋터, 날짜, 부모 관계, 파일 모드, 심볼릭 링크를 유지했고 문서 경로, 옛 계획·ADR 번호, `main`에 있는 앞선 커밋의 SHA 인용만 바꿨다. 같은 입력으로 세 번 따로 돌려 같은 829e77a가 나왔다.
- **Command:** 재작성은 저장소 clone이 아닌 별도의 `git clone --mirror` 두 개(백업, 작업)에서 `git commit-tree`로 커밋을 순서대로 다시 만들어 했다. 백업 clone은 끝까지 그대로였다(객체 수 3416 불변). 재작성 전 `main`의 SHA 160개와 새 SHA 160개의 대응은 아래 "부록: 재작성 전후 커밋 대응"에 있다.
- **Verified:** 설계 §3.5의 검증 다섯 가지를 마지막 실행에서 했다.
  1. 통과: 커밋 160개 대 160개, 병합 12 대 12, 작성자·커밋터·날짜·부모·모드·심볼릭 링크가 같다.
  2. 통과: 어느 커밋의 tree에도 대응표의 옛 문서 경로가 없다(문서 경로 196개를 160개 tree에서 확인했고 대응표에 없는 경로는 0개).
  3. 목록: 옛 번호 모양에 걸린 곳 264건에 줄마다 이유를 붙였다. HEAD에 170건(Task 2가 남긴 것과 같은 분류), 이력이나 커밋 메시지에만 있는 것 94건이다. 94건은 코드 리터럴 37, 옛 표기에서 파생된 이름 17, 목록 10, 분수 10, 테스트 주석 4, 인용 3, 사용자가 남기기로 한 곳 2, 개수 2, 연도 2, 외부 ADR 1, 대응표에 없는 것 1(PR #7 메시지의 "former plan 13"), OCI 시절 ADR 0001 1(docs-skills 계획에서 두 ADR을 함께 부르는 줄), 브랜치 줄임말 1, 4자리가 아닌 ADR 1, 범위 1, 두 자리 계획이 아닌 것 1이다.
  4. 통과: 재작성한 HEAD와 a1d77be의 tree는 49개 파일 162줄이 다르고, 그 차이는 모두 대응표의 SHA 쌍 때문이다(통제 세션과 감독 세션이 따로 다시 확인해 설명되지 않는 줄 0).
  5. 통과: 표본 커밋 21개(계획 번호를 바꾼 커밋 주변, OCI 시절 ADR 이름을 바꾼 커밋 주변, 정책 스펙을 더한 커밋 주변, PR #7과 #22, 무작위 3개)의 diff가 경로·이름·번호·ID·SHA를 가리면 원래와 같다.
- **Verified:** push는 `git push --force-with-lease=refs/heads/main:<a1d77be 전체 SHA>`로 했다(`+ a1d77be...829e77a`). 그 전에 `git ls-remote`로 원격 `main`이 a1d77be인지 확인했고, 로컬 bare 사본에서 잘못된 lease가 거절되는 것을 시험했다. 머신 계정은 저장소 관리자가 아니어서 사용자가 Ruleset `main`의 Enforcement를 끄고 push 뒤 다시 켰다. 켠 뒤 공개 규칙 API가 규칙 5개(삭제 금지, non-fast-forward 금지, 선형 이력 필수, pull request 필수, 필수 상태 검사)를 보여 준다. push 전후로 `refs/pull/*/head` 22개는 변하지 않았다.
- **Verified:** PR #1~#22의 제목, 본문, 머신 계정의 코멘트에 같은 치환을 했다(범위를 #1~#20에서 #1~#22로 넓혔다). 읽은 139건(제목 22, 본문 22, 코멘트 95) 중 98건이 바뀌었다. 제목 6, 본문 22, 코멘트 70건이고 치환은 272곳이다. 고친 뒤 GitHub에서 다시 읽은 글이 제안한 글과 같다. 사람 계정의 리뷰 24개, GitGuardian 코멘트 3개, PR의 head 커밋(`refs/pull`)과 그 SHA는 고치지 않았다. PR별 건수는 계획의 Progress log에 있다.
- **Verified:** 재작성하지 않은 것: PR head 커밋의 SHA(`refs/pull/*/head`)와 그 SHA를 가리키는 인용, `main`에 없는 커밋 SHA 612개와 어느 커밋도 아닌 16진 문자열 828개의 인용. 그래서 PR 코멘트의 "6f041cb..2e8c2a5" 같은 범위는 새 `main` SHA와 옛 PR head SHA를 이어 붙인 모양이 되었다. 설계가 예상한 비용이다.
- **Verified:** 부작용:
  - GitHub가 서명했던 squash 병합 커밋 23개가 서명을 잃어 Verified 표시가 없다.
  - 파일을 `backlog`·`active` 폴더 사이에서 옮기기만 한 커밋 3개는 내용 변경이 없어져 빈 커밋이 되었다. 커밋 수 160을 지키려고 남겼다.
  - 4dabf83(재작성 전 a82df1c)의 diff는 원래 건드리지 않던 docs-skills 계획 4줄을 건드린다. OCI 시절 ADR 번호를 쓰던 시대의 경계 때문이다.
  - 이력은 Task 2가 HEAD에서 손으로 고친 곳(예: git-review-policy 스펙의 번호 목록)을 규칙대로 쓴 형태로 가지고 있다.
  - 공유 규칙의 영어 문장이 어색하게 읽히는 곳이 있다(예: "new the git-review-tooling plan").
  - PR 제목·본문을 고치자 닫힌 PR에서 `pr-rules`가 다시 돌았고 28번 실패했다. 각 PR이 저장한 base가 옛 `main`이라 범위가 옛 이력 전체에 걸려 옛 squash 커밋에서 "missing trailer 'Task: …'" 등이 나왔다. 병합된 PR에는 영향이 없다.
- **Verified:** 뒷정리: 사용자가 메인 checkout을 `git fetch origin --prune`과 `git reset --hard origin/main`으로 맞췄다(HEAD 829e77a, 무시된 `.env`와 `backups/`는 남음). 다른 Mac에는 `git fetch origin --prune && git switch main && git reset --hard origin/main`과 옛 로컬 브랜치 삭제 명령을 알렸다. 옛 SHA와 새 SHA의 대응 파일은 백업 사본과 함께 저장소 밖에 두었고 사용자 메모리에 위치를 적었다.
- **Open question:** 남은 것은 다른 기기의 사본, GitHub 밖의 대화와 메모에 적힌 옛 SHA와 옛 번호다. 아래 "부록: 재작성 전후 커밋 대응"과 "부록: 옛 번호 대응표"로 찾는다.

## 부록: 옛 번호 대응표

설계 §3.4의 이름 변경(2026-10-26)에서 채웠다. 옛 이름 열에는 각 문서가 이 계획 직전에 가진 이름을 적는다. 이력 재작성의 치환 규칙에 걸리지 않도록 경로와 확장자 없이 날짜, 번호, slug를 띄어 적고, 그보다 오래된 이름은 "그 전:" 뒤에 적는다. 리뷰 기록 이름의 `plan-NN-` 접두어는 `plan-NN`으로 적는다.

- 한 문서가 이력에서 가진 이름은 한 행에 있다. 코드 접두어(`plan-` 등)만 없거나 계획의 `backlog`·`active`·`completed` 하위 폴더에 있던 옛 이름은 날짜·번호·slug가 같아서 따로 적지 않는다. 그 밖의 옛 이름(날짜가 없던 이름, `-design`이 붙은 스펙, 번호를 바꾸기 전 이름)은 "그 전:" 뒤에 적는다.
- "삭제됨"은 HEAD에 없는 문서다. 새 이름의 파일은 없고, 이력 재작성이 그 문서의 옛 경로를 이 이름으로 바꾼다.
- ADR 번호 0001은 서로 다른 두 문서(OCI 시절 ADR, GCP ADR)가 썼으므로 행이 둘이다. vm-scripts·docs-skills·vm-rollout 계획은 번호를 바꾼 커밋(`7a35cb3`) 전에 지금보다 하나 작은 번호를 썼다("그 전:"의 이름).

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

## 부록: 재작성 전후 커밋 대응

2026-10-26 재작성의 옛 SHA와 새 SHA(7자)다. `main`의 커밋 160개를 이력 순서로 적었다.

| 재작성 전 | 재작성 후 |
|---|---|
| 57d27f8 | 8af2f5f |
| dc73e64 | 1827258 |
| f6c4eec | 58903ed |
| bebcfd2 | 72cd315 |
| c88c56d | 496d060 |
| 750c7c3 | 7a35cb3 |
| 42c2b45 | b159684 |
| 20b7db2 | 3efcdab |
| 984df2c | 50bcc28 |
| 4e2ec21 | a5cb508 |
| bb98c02 | 5dc5e58 |
| 77951c3 | a21ff33 |
| 35f65d0 | 1d464d9 |
| 1fa3fce | 83b7f72 |
| f92411b | 315d50a |
| a1e9a71 | b09abae |
| bade74d | fb1bf28 |
| e034250 | b18a663 |
| 6b6f419 | f62396f |
| 6dfd1b4 | dbda608 |
| 6ee7823 | 6f5f02d |
| 26e5af2 | 7b27246 |
| 6417f00 | 55cdc4b |
| 504fa74 | b0f1141 |
| 20ae84e | 21f7113 |
| de7f265 | e2d6465 |
| 3cf3a83 | 286b8fa |
| db0c45b | d41c387 |
| e6146b4 | 6f42cec |
| dc423de | 80fa24b |
| 7cceb24 | 0dbc0a3 |
| 91cdb92 | 347f9ec |
| 46ea052 | 96ac8ea |
| 146447a | 16e7d88 |
| b61ddbf | 5a9c7d7 |
| c260ffc | ad7d0b1 |
| 37e9956 | dfeafbc |
| 0632ee9 | 49cb7df |
| 8184243 | 6105095 |
| 144a9f8 | 2fb6880 |
| e2acbb5 | 8931baf |
| b638c96 | 4a1a166 |
| 5887498 | a530c9e |
| 7db2e2c | 8c65679 |
| 058ca9c | a349fb4 |
| 1ebf820 | 32ac7d5 |
| 6fc3ea3 | de303eb |
| ce3efa2 | 7c4bc1a |
| 298a272 | 46733f2 |
| d83c80e | 2563e2c |
| 24ce10f | 6aa1686 |
| 585eae2 | 9fcd6e2 |
| 0db42f4 | 77d9ccc |
| ddca415 | eb948fc |
| 6243ad9 | 263f903 |
| bb16883 | 20d342b |
| dff0d27 | 74521cb |
| 1486e5b | d5f1db8 |
| 2a9bfe3 | 280dbaa |
| ce3be17 | 9963090 |
| 512c8ae | 83e92fb |
| 34a02a0 | a15638d |
| 2fa3e42 | b842519 |
| 8fd3926 | 9d1fe67 |
| 7471276 | 2f97140 |
| 01d3458 | 3ea1ef8 |
| 6368680 | f47b3cf |
| e73be4b | d15d641 |
| d5e64e6 | c2d505e |
| 0fae78e | bcc66c5 |
| b8ea75e | 2e09e2e |
| 36c7564 | 9c8b9e0 |
| 68d91e6 | f6a170d |
| abcb107 | f49f2d0 |
| d0553a0 | 58e42b1 |
| 80c26de | 2850fc5 |
| 490fc97 | bc2ba09 |
| 7aa6bfb | 9f87f40 |
| b627135 | 15cdeef |
| 54d6dcb | d07d31d |
| 69f45e6 | 2d67130 |
| f5ad88c | 241d82d |
| b695766 | 987a069 |
| 82d6a57 | 803caf5 |
| 90d3674 | 8d960d4 |
| a82df1c | 4dabf83 |
| 660a048 | 6038043 |
| 9f7ffcf | 1afc9d3 |
| 308d8fc | c965fc5 |
| d310ebc | 0a98c9e |
| e240c57 | 8c6f37f |
| d2907b2 | 176062f |
| 3884850 | 0167c5c |
| 006655d | cccd6fd |
| 62cc7a9 | 427b489 |
| 699b72c | ece9be2 |
| 543bd7e | 9376974 |
| 15bb4e2 | 2f7010e |
| d15506b | 8b8eea0 |
| a10601e | 2ee54e6 |
| 65cc7c0 | e2b505c |
| 43771b1 | c1d986a |
| 65567da | 0662d45 |
| 1cb382a | 6d7115a |
| 71ad51b | 56d3ab4 |
| 3d60453 | 21edef9 |
| 8ab9d72 | 49afdf9 |
| ab08bbc | 08dcd4d |
| c59b1a9 | 0a1acec |
| a2e1b78 | 5a42324 |
| 5561329 | a5781a4 |
| 5693ff3 | e2f525b |
| 0061153 | 789053a |
| 32e405c | b86f43c |
| ecc5fb2 | 01a40c5 |
| 3501ad7 | 10ecdcd |
| ac9429c | 34bf50f |
| 8a472a1 | 20b32b5 |
| 686ea6a | 1a495b5 |
| fb54cdb | d481ee4 |
| 8871863 | aa7564b |
| 6133782 | e57877f |
| 7d71b23 | a9706eb |
| c10fb5c | 1b333af |
| c3f0943 | d7af8f9 |
| aacb7a9 | a84bae1 |
| 8c9221c | acabbba |
| 58fff47 | 78f13c2 |
| 703be2a | 0ff9988 |
| 2ff27c1 | adeace1 |
| c0b570b | 9adb238 |
| bdf852b | aae9c83 |
| 5d05c76 | 5147137 |
| ca155f0 | 06b5f43 |
| 32cc27f | 5f66bff |
| 9f7e038 | 0d49cb9 |
| 8caac87 | 4d29143 |
| de91861 | 292f58b |
| d59bfed | 47ed954 |
| f0b4f9c | d354732 |
| ec46af9 | 5726ed1 |
| 945fd57 | 9b2fde1 |
| 3b87fa5 | 54ea5f6 |
| 4c84dba | e928776 |
| 4a184f1 | 9dbf963 |
| 87e86d4 | 9a43084 |
| 16aa61f | 251d84f |
| 03432a1 | 3d8e3f3 |
| 4cedf49 | ef67732 |
| eda0d92 | 0e41ed7 |
| e648d5a | c608d87 |
| 47dbbc7 | b53edc5 |
| 6452041 | e05f0c4 |
| 6e38c46 | 0fe5bd2 |
| 7a3748d | 57993a3 |
| 5c8c079 | 1d06037 |
| 6554406 | 42136db |
| a0493ad | 3697455 |
| 9dd11e2 | dfda20c |
| a1d77be | 829e77a |
