---
status: accepted
id: 0svs72hp
date: 2026-10-27
---

# ADR 0svs72hp: `AGENTS.md` 규칙 가운데 검사가 보는 것과 보지 못하는 것을 이 ADR의 표 하나에 적고, `AGENTS.md`는 한 줄로 가리킨다

- 계획: [invariant-enforcement 계획](../plans/plan-2026-10-22-m97w7hqe-invariant-enforcement.md) Task 4

## 맥락과 문제

- **Reported (2026-10-22 평가):** D4의 엄격 기준 불변식 비율은 10/31(32%)이었다. 주입한 위반 여러 개(다른 스크립트의 raw `ssh -L`, 라이브러리를 source하지 않는 스크립트, digest 없는 이미지, 테스트 삭제와 `skip`)가 `make check`를 통과했다.
- `AGENTS.md`의 제목 `## Invariants (enforced by the tests/repo-*.bats files; …)`는 실제보다 많이 약속했다. 검사는 `tests/repo-*.bats`만이 아니라 짝 테스트, `tools/coverage.sh`, CI `pr-rules`, ruleset에 흩어져 있고, 어떤 규칙은 어디에도 검사가 없다. 에이전트가 제목을 믿으면 검사 없는 규칙도 기계가 막아 준다고 여긴다.
- 계획 Task 1~3이 검사를 더한 뒤에도 기계로 볼 수 없는 규칙이 남는다. 그 목록과 이유를 어디에 둘지 정해야 했다(계획 Open question 2).

## 검토한 대안

1. `AGENTS.md` Invariants 아래 절: 한 파일에서 보인다. 네 도구가 매 세션 읽는 컨텍스트가 늘고, 검사가 생겨 목록이 바뀔 때마다 `AGENTS.md` 수정 OK가 필요하다.
2. 새 ADR에 목록을 두고 `AGENTS.md`는 한 줄로 가리킴(선택): `AGENTS.md`가 짧게 남고, 목록이 바뀌어도 `AGENTS.md`를 고치지 않는다. 목록을 보려면 파일을 하나 더 연다.

## 결정

1. **Verified (2026-10-27):** 사용자가 계획의 Open question 2에서 대안 2를 골랐고, 아래 `AGENTS.md` 문구를 승인했다.
2. `AGENTS.md` Invariants 제목에서 "enforced by the tests/repo-*.bats files"를 빼고, 테스트를 지우거나 건너뛰는 PR은 트레일러 문단에 `Tests-Removed: <reason>`을 단다고 쓴다([test-integrity-guard ADR](adr-2026-10-27-y9fxhf7x-test-integrity-guard.md)). 절의 마지막 항목은 검사가 볼 수 있는 규칙은 `make check`와 CI `pr-rules`가 보고, 나머지는 이 ADR에 이유와 함께 있다고 말한다.
3. 아래 표가 `AGENTS.md`의 Commands(`make check`), Invariants, Safety, Git, Notes 규칙마다 상태와 보는 곳을 적는 정본이다. 상태는 셋이다.
   - 검사 있음: 위반하면 `make check`, CI `pr-rules`나 ruleset이 실패한다.
   - 일부: 규칙의 일부나 일부 경로만 검사가 본다.
   - 검사 없음: 저장소 검사가 볼 수 없다. 이유와, 대신 보는 사람이나 명령을 적는다.

### 목록

**Verified (2026-10-27):** 이 ADR을 더한 커밋의 트리에서 각 행의 테스트와 스크립트를 열어 확인했다. 줄 번호는 그 커밋의 `AGENTS.md`와 파일 기준이다. **Verified (2026-10-27):** 같은 브랜치가 `origin/main`(`0619c19`, PR #27·#29)을 병합한 뒤 다시 확인해 밀린 인용 두 개(`tests/repo-make.bats:151`, `tests/post-review.bats:41`)를 고쳤다.

| `AGENTS.md` | 규칙 | 상태 | 보는 곳, 또는 검사가 없는 이유 |
|---|---|---|---|
| `:9` | 커밋마다 `make check` | 일부 | CI `check` 잡(`.github/workflows/ci.yml`)이 PR head에서 `make check`를 돌리고 ruleset이 필수 검사로 요구한다(`.github/rulesets/main.json:28-35`). 커밋마다 막으려면 도구별 hook이 필요하다. |
| `:12` | 테스트를 약하게 하지 않음, `Tests-Removed` | 일부 | `scripts/check-tests.sh`(pr-rules "Test count and skips", `tests/check-tests.bats:31`, `:58`)가 `@test` 감소와 새 `skip`을 본다. 지우고 같은 수를 더함, 단언 약화는 리뷰가 본다. |
| `:13` | 포트를 `127.0.0.1`에만 publish | 검사 있음 | `tests/repo-config.bats:88` "compose publishes ports on 127.0.0.1 only". VM에서는 `make verify`가 loopback 바인딩을 본다. |
| `:13` | Tailscale Funnel 금지 | 검사 있음 | `tests/repo-scripts.bats:69` "no script enables Tailscale Funnel". VM에서는 provision이 Funnel이 켜져 있으면 실패하고(`tests/remote-provision-vm.bats:79`), `make verify`도 본다(`tests/verify-vm.bats:81`). |
| `:13` | 공개 인그레스 0, 모드별 인바운드 규칙 하나 | 검사 없음 | 방화벽은 클라우드 상태라 저장소 검사가 볼 수 없다. `make verify`가 공인 IP의 포트 차단을 보고(`tests/verify-vm.bats:244`), 규칙 목록은 운영 런북의 Exposure audit을 손으로 점검한다([운영 런북](../runbooks/rbk-2026-10-12-t79ex2ny-operations.md)). |
| `:13` | 웹 커넥터: 밖으로만 dial, gateway가 GitHub 계정 하나와 허용 도구만 | 일부 | 저장소 쪽은 `tests/repo-config.bats:229`(cloudflared는 포트를 publish하지 않음), `:281`(quick tunnel 없음), `:314`(gateway가 숫자 id로 소유자 확인, 허용 도구만). 허용 id 값과 tunnel 설정은 `.env`와 클라우드 상태라 `make verify`(`tests/verify-vm.bats:175`)와 웹 커넥터 런북이 본다. |
| `:13` | 모든 `ssh -L`은 `forward_spec`로 `127.0.0.1` | 검사 있음 | `tests/repo-scripts.bats:176` "every ssh -L in scripts/ and the Makefile goes through forward_spec". |
| `:13` | VM 하나에 접속 모드 하나 | 검사 없음 | VM 상태다. ssh 모드의 `make verify`는 VM의 Tailscale이 로그인 상태면 실패한다(`tests/verify-vm.bats:135`). |
| `:14` | 이미지를 digest로 고정 | 검사 있음 | `tests/repo-config.bats:66` "every image in compose.yaml, the Makefile and tools/Dockerfile is pinned by digest". |
| `:14` | 릴리스 노트를 읽은 뒤에만 고정 변경, `bm-upgrade`로만 업그레이드 | 검사 없음 | 산출물이 남지 않는 절차다. `bm-upgrade` 스킬과 리뷰가 본다. |
| `:15` | shebang과 `set -euo pipefail` | 검사 있음 | `tests/repo-scripts.bats:48` "every executable shell file starts with #!/usr/bin/env bash and enables strict mode". |
| `:15` | 라이브러리 source, `scripts/remote/`는 source 없음 | 검사 있음 | `tests/repo-scripts.bats:118`(스크립트), `:107`(라이브러리는 `common.sh`), `:102`(remote). |
| `:15` | 고칠 방법이 있는 메시지로 `die` | 검사 없음 | 메시지가 고칠 방법을 말하는지는 판단이다. 리뷰가 본다. |
| `:16` | bash 4+ 기능 금지 | 검사 있음 | `tests/repo-scripts.bats:65` "scripts avoid bash 4+ features (macOS ships bash 3.2)". |
| `:16` | 빈 배열 전개 금지, 실패할 수 있는 `$(fn)` 뒤 `\|\| exit 1` | 검사 없음 | 배열이 빌 수 있는지, `fn`이 실패할 수 있는지는 실행 경로에 달려 grep으로 정할 수 없다. 리뷰가 본다. |
| `:17` | 이름 붙인 상수 | 검사 없음 | 어떤 숫자가 뜻 있는 값인지는 판단이다. |
| `:17` | 비밀값과 세션 id를 출력하지 않음, `mask` | 일부 | 기존 경로마다 동작 테스트가 있다: `tests/lib-common.bats:9`(`mask`), `tests/verify-mcp.bats:12`(세션 id), `tests/lib-sb.bats:28`, `tests/lib-vm.bats:143`, `:208`, `tests/repo-make.bats:55`. 새 출력 경로를 보는 일반 검사는 없다. 값을 모르는 검사는 출력에서 그것을 찾을 수 없다. |
| `:18` | 짝 테스트 | 검사 있음 | `tests/repo-scripts.bats:73` "every script and library has its pair test, …". |
| `:18` | 테스트 먼저 | 검사 없음 | 순서는 이력에만 있다. Progress log의 실패 확인 기록과 리뷰가 본다. |
| `:22` | 비밀값, `.env`, `backups/`, `.local-data/`, 노트 내용을 커밋하지 않음 | 일부 | `.env`: `tests/repo-config.bats:160`(추적 안 됨, ignore됨). `backups/`, `.local-data/`는 `.gitignore`뿐이다. 비밀값은 GitHub push protection과 GitGuardian(저장소 밖 설정, [GitHub 런북](../runbooks/rbk-2026-10-14-ppmby9v6-github.md))이 보고, `make secret-scan`(gitleaks, `tests/repo-make.bats:151`)은 손으로 돌리며 `make check`나 CI에는 없다. 노트 내용은 모양으로 구분할 수 없다. |
| `:23` | 비밀값은 `.env`에만, SSH나 curl stdin으로 전달 | 일부 | 기존 경로의 동작 테스트(`tests/lib-vm.bats:208`, `tests/lib-sb.bats:28`). 명령 인자나 저장소 파일에 넣지 않는 것을 보는 일반 검사는 없다. |
| `:24` | VM·클라우드를 바꾸기 전에 사용자에게 물음 | 일부 | `.claude/settings.json`의 ask 규칙과 `scripts/guard-agent-bash.sh`가 Claude Code 세션에서 `make deploy`·`restore`·`vm-bootstrap`·`sb-fonts`, VM 스크립트 직접 호출, `gcloud` 생성·삭제를 묻는다(`tests/repo-config.bats`의 "the Claude Code settings keep the sandbox on, …", `tests/guard-agent-bash.bats`의 "asks before a direct call of a VM-changing script, …"). 우회 형태와 다른 도구(Codex, Gemini, Antigravity)의 작성 세션은 행동이다. [agent-trifecta ADR](adr-2026-10-28-zaptc3gp-agent-trifecta.md) |
| `:25` | `backups/`, `/srv/basic-memory.prev-*` 삭제 금지 | 일부 | Claude Code 세션에서 `permissions.deny`의 `rm` 규칙과 훅이 막는다(`tests/guard-agent-bash.bats`의 "denies deleting backups or the basic-memory.prev directories, also in wrapped forms", `tests/repo-config.bats`의 설정 사례). `rm`이 아닌 삭제 수단과 다른 도구의 세션은 행동이다. [agent-trifecta ADR](adr-2026-10-28-zaptc3gp-agent-trifecta.md) |
| `:26` | `.env`와 `backups/`는 main checkout에만 | 일부 | 워크트리의 make가 main checkout의 `.env`를 읽는다(`tests/repo-make.bats:41`). 워크트리에 만들거나 복사하지 않는 것은 행동이다. |
| `:27` | `gcloud`는 `--configuration=bm-personal`로만 | 일부 | 런북·README·ARCHITECTURE의 명령: `tests/repo-docs.bats:195`. 스크립트와 스킬은 `gcloud`를 아예 쓰지 않는다(`tests/repo-cloud-neutral.bats:28`). 에이전트가 직접 치는 명령은 행동이다. |
| `:28` | auth key와 restore `yes`는 사용자 터미널에서 | 일부 | restore의 `yes`는 `scripts/restore-notes.sh`가 `/dev/tty`에서만 읽는다(`tests/restore-notes.bats`의 "restore refuses before any ssh when the answer is not yes, …"). 에이전트가 `script`·`expect`로 pty를 만들면 훅이 묻기만 한다. auth key는 에이전트와 사용자의 행동이다. [agent-trifecta ADR](adr-2026-10-28-zaptc3gp-agent-trifecta.md) |
| `:29` | VM IP를 커밋·PR·코멘트·파일에 쓰지 않음 | 검사 있음 | `scripts/check-public-text.sh`([public-text-guard ADR](adr-2026-10-26-vtmqpsyx-public-text-guard.md)): 파일은 `tests/repo-public-text.bats:6`(`make check`), 커밋 메시지는 `scripts/check-git.sh`(`tests/check-git.bats:83`), PR은 `scripts/check-pr.sh`(`tests/check-pr.bats:109`), 리뷰 게시는 `tests/post-review.bats:41`, `tests/post-review-record.bats:33`. |
| `:32` | 자기 워크트리, `plan/`·`work/` 브랜치, `origin/main`에서 분기 | 일부 | 브랜치 이름과 detached HEAD: `scripts/check-git.sh`(`tests/check-git.bats:47`, pr-rules). 워크트리 하나에 에이전트 하나, 분기 기준은 검사가 없다. |
| `:33` | `main`에 커밋·push 금지 | 검사 있음 | ruleset이 `main`에 PR, 삭제 금지, fast-forward만을 요구하고(`.github/rulesets/main.json:13-26`, `tests/repo-github.bats:27`), `scripts/check-git.sh`가 `main` 위의 작업을 실패로 본다(`tests/check-git.bats:47`). |
| `:33` | `main` 밖의 force-push·rebase·이력 재작성, `git gc`, 다른 에이전트 브랜치 삭제 | 일부 | force-push는 Claude Code 세션에서 ask 규칙과 훅이 묻는다(`tests/guard-agent-bash.bats`의 "asks before a force-push in every spelling, …"). `HEAD:+x` 같은 refspec 형태는 못 잡는다. ruleset은 기본 브랜치만 지킨다(`.github/rulesets/main.json:6-11`). rebase, 이력 재작성, `git gc`, 브랜치 삭제는 로컬 행동이다. [agent-trifecta ADR](adr-2026-10-28-zaptc3gp-agent-trifecta.md) |
| `:33` | `extensions.worktreeConfig` 금지 | 검사 있음 | `scripts/check-git.sh`(`tests/check-git.bats:131`). |
| `:34` | `Assisted-by`, `Plan`, `Task` 트레일러, `Co-authored-by`·`Signed-off-by` 금지 | 검사 있음 | `scripts/check-git.sh`(`tests/check-git.bats:83`, pr-rules), 금지 목록은 `scripts/lib/git.sh:29`. |
| `:34` | `Review-Finding`, `SDD-T…` 형식 | 검사 없음 | 이력에 `SDD-final-I1` 같은 값이 있어 형식부터 정해야 한다. 계획 Follow-ups. |
| `:35` | PR 제목 `<type>: <description>`, 본문 트레일러, CI 통과 | 검사 있음 | `scripts/check-pr.sh`(`tests/check-pr.bats:37`, `:56`), 필수 검사 `check`·`pr-rules`(`tests/repo-github.bats:27`). |
| `:36` | 세션 트레일러·링크, `Generated with` 줄 금지 | 검사 있음 | `scripts/check-public-text.sh`와 금지 트레일러(`scripts/lib/git.sh:29`): `tests/check-git.bats:83`, `tests/check-pr.bats:56`, 리뷰 게시 테스트(`:29` 행과 같음). |
| `:37` | 사람만 승인·병합, 에이전트는 Update branch를 누르지 않음 | 일부 | ruleset: 승인 1, 마지막 push 뒤 승인, squash만(`.github/rulesets/main.json:16-26`, `tests/repo-github.bats:27`). Update branch를 누르지 않는 것은 행동이다. |
| `:40-41` | 레이블과 언어 | 검사 없음 | [structure-checks ADR](adr-2026-10-16-q36rwq5s-structure-checks.md) 결정 2가 레이블·언어 검사를 금지한다. |
| `:42` | 증거와 결정을 남기는 곳 | 검사 없음 | 무엇이 증거이고 결정인지는 판단이다. 리뷰 규칙 3이 Progress log의 `make check` 기록을 본다. |
| `:43` | `make new-doc`, 등록된 폴더, 문서 id | 검사 있음 | `tests/repo-docs.bats:188`(이름, front matter, 템플릿 빈칸), `:87`(id 중복). |
| `:44` | 승인 전 초안은 Basic Memory 초안 보드에 | 검사 없음 | 저장소 밖 상태다. |

## 결과

- `AGENTS.md`의 제목이 검사 범위를 과장하지 않는다. 검사가 있다고 믿어도 되는 규칙과 리뷰가 지켜야 하는 규칙을 이 표에서 구분한다. 매 세션 읽는 `AGENTS.md`는 한 줄만 늘었다.
- 치르는 것: 표의 줄 번호와 테스트 위치는 파일이 바뀌면 밀린다. 테스트 이름으로 다시 찾는다.
- 목록을 바꾸는 법: 검사를 더하거나 넓히는 PR이 같은 PR에서 이 표의 행 상태와 보는 곳을 고친다. 상태가 바뀌어도 `AGENTS.md`는 고치지 않는다. 이 ADR의 결정 문장(1~3)은 그대로 두고 표만 고친다.
- 확인 방법: 검사를 더한 PR의 리뷰가 이 표가 함께 바뀌었는지 본다(코드 리뷰 규칙 5). 새 테스트는 없다([structure-checks ADR](adr-2026-10-16-q36rwq5s-structure-checks.md) 결정 2).
