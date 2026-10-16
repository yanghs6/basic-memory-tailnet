# 여러 코딩 에이전트가 같은 규칙으로 문서·스크립트·테스트를 만들게 하려면

- 상태: 조사 보고서 (2026-10-15 시점의 스냅샷). 이후 바뀐 사실은 반영하지 않는다.
- 기준 커밋: 저장소 안 사실은 `main` 54ea5f6 기준이다.
- 표기: 출처 링크가 붙은 문장은 `Verified`(그날 1차 출처에서 확인)다. "(추론)"은 `Assumption`, "(미확인)"은 1차 출처에서 찾지 못한 내용이다.
- 방법: 공식 문서, 공식 GitHub 저장소와 릴리스 API, 저장소 로컬 파일만 썼다. 이 조사를 근거로 [문서 체계 설계](../specs/spec-2026-10-15-sgpbx1gq-doc-system.md)와 [스크립트·테스트 구조 설계](../specs/spec-2026-10-15-d8q0b7bt-script-test-layout.md)를 썼다.

이 저장소는 Claude Code, Codex, Gemini CLI, Antigravity가 함께 작업한다. 조사 결과 세 가지가 분명했다. 첫째, 지침 파일을 읽는 방식이 도구마다 달라서 **Gemini CLI는 지금 이 저장소의 `AGENTS.md`를 읽지 않는다**. 둘째, 지침 파일은 짧은 지도로 두고 세부 규칙은 필요할 때 읽는 문서·스킬로 옮기며, 반드시 지켜야 할 규칙은 문장이 아니라 검사로 강제하는 쪽으로 업계가 수렴했다. 셋째, 문서 템플릿과 bash·bats 구조에는 검증된 형식이 이미 있어서 새로 만들 필요가 없다.

## 1. 지침 파일과 스킬을 읽는 방식은 도구마다 다르다

| 도구 | 지침 파일 | 이 저장소에서 | 스킬 경로 | 크기 한도 |
|---|---|---|---|---|
| Claude Code | `CLAUDE.md`(루트부터 cwd까지 이어 붙임), `@path` import(최대 4단계), `.claude/rules/*.md`(`paths:`로 범위 지정) | 읽음(`CLAUDE.md` = `@AGENTS.md`) | `.claude/skills`(심볼릭 링크 허용). `.agents/skills`는 읽지 않음 | 파일당 200줄 이하 권장 |
| Codex | 저장소 루트부터 cwd까지 폴더마다 `AGENTS.override.md` → `AGENTS.md` → 대체 이름 중 하나 | 읽음 | `.agents/skills`(cwd부터 루트까지), `~/.agents/skills` | `project_doc_max_bytes` 기본 32,768바이트(합계). 넘으면 경고 로그만 남기고 자름 |
| Gemini CLI | 기본 `GEMINI.md`. `context.fileName`으로 바꿀 수 있음, `@file` import(최대 5단계) | **읽지 않음** | `.gemini/skills` 또는 별칭 `.agents/skills` | 문서에 없음 |
| Antigravity | 모든 폴더의 `AGENTS.md`·`GEMINI.md`, `.agents/rules/*.md` | 읽음 | `.agents/skills`(예전 `.agent/skills`도 지원) | 규칙 파일당 24,000바이트, 항상 켜진 규칙 합계 20,000토큰 |

- Claude Code는 v2.1.277부터 `CLAUDE.md`가 없을 때만 `AGENTS.md`를 직접 읽는다. `CLAUDE.md`에 `@AGENTS.md` 한 줄을 두는 방식이 공식 문서의 공유 패턴이다 ([Claude Code memory](https://code.claude.com/docs/en/memory)).
- Codex의 탐색 순서와 크기 한도: [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md). 기본값은 `codex-rs/config/defaults.toml`, 자르는 동작은 `codex-rs/core/src/agents_md.rs`에서 확인했다.
- Gemini CLI의 기본 파일 이름은 소스에서 `DEFAULT_CONTEXT_FILENAME = 'GEMINI.md'`다. `AGENTS.md`를 읽게 하려면 `.gemini/settings.json`에 `{"context":{"fileName":["AGENTS.md"]}}`를 둔다 ([GEMINI.md](https://geminicli.com/docs/cli/gemini-md/), [설정](https://geminicli.com/docs/reference/configuration/), [agents.md](https://agents.md/)).
- 이 저장소에는 `.gemini/`와 `GEMINI.md`가 없고, 사용자 전역 `~/.gemini/settings.json`에도 `context.fileName`이 없다. 2026-10-15에 로컬에서 확인했다.
- Antigravity 규칙과 한도: [Antigravity rules](https://antigravity.google/docs/rules). Antigravity workflows는 2026-10-19에 동작을 멈추고 스킬로 옮겨야 한다 ([workflows](https://antigravity.google/docs/ide/workflows)). 이 저장소는 workflows를 쓰지 않는다.
- Agent Skills 명세: `name`(디렉터리 이름과 같음)과 `description`(1,024자 이하)이 필수이고, 본문은 500줄 이하, 참조는 한 단계까지다 ([명세](https://agentskills.io/specification)). 네 도구 모두 이 저장소의 스킬을 읽는다. Claude Code는 `.claude/skills` 심볼릭 링크로 읽는다 ([Claude Code skills](https://code.claude.com/docs/en/skills), [Codex skills](https://learn.chatgpt.com/docs/build-skills), [Gemini CLI skills](https://geminicli.com/docs/cli/skills/), [Antigravity skills](https://antigravity.google/docs/skills)).
- AGENTS.md 형식은 2025-12-09부터 Linux Foundation 산하 Agentic AI Foundation이 관리한다. 필수 필드나 크기 한도는 없고, 편집하는 파일에 가장 가까운 `AGENTS.md`가 우선한다 ([agents.md](https://agents.md/)).

## 2. 지침 파일은 지도로, 세부는 문서로, 꼭 지킬 규칙은 검사로

- OpenAI "Harness engineering"(2026-02-11)은 큰 `AGENTS.md` 하나가 실패한 이유를 이렇게 정리한다. 작업 맥락을 밀어내고, 모든 것이 "중요"해지고, 바로 낡고, 기계적으로 검사하기 어렵다. 대안은 다음과 같다 ([원문](https://openai.com/index/harness-engineering/)).
  - 약 100줄의 `AGENTS.md`를 지도로 쓴다.
  - `docs/`를 기록의 정본으로 둔다. `design-docs/index.md`(검증 상태 포함), `exec-plans/{active,completed}/`, `tech-debt-tracker.md`를 둔다.
  - 전용 linter와 CI가 문서의 최신성, 교차 링크, 구조를 검사한다. 주기적으로 도는 "doc-gardening" 에이전트가 수정 PR을 연다.
  - lint 오류 메시지에 고치는 방법을 담는다. 문서가 부족하면 규칙을 코드로 올린다.
- OpenAI Codex 쿡북의 ExecPlan(`PLANS.md`, 현재 보관 처리됨)은 계획을 스스로 완결된 살아 있는 문서로 쓴다 ([ExecPlan](https://developers.openai.com/cookbook/articles/codex_exec_plans)).
  - 계속 갱신하는 필수 절: Progress(UTC 시각이 붙은 체크박스), Surprises & Discoveries, Decision Log, Outcomes & Retrospective.
  - 체크리스트는 Progress에서만 쓴다. 고칠 때마다 맨 아래에 이유를 남긴다.
- Anthropic은 지침 파일의 각 줄에 "이 줄을 지우면 실수하는가?"를 묻게 한다. 길어진 지침 파일은 실제 지침을 무시하게 만든다. 가끔만 필요한 지식은 스킬로, 예외 없이 지켜야 할 일은 훅으로 옮긴다 ([best practices](https://code.claude.com/docs/en/best-practices)). 맥락은 "가장 작은 고신호 토큰 집합"으로 유지하고, 파일 경로로 필요할 때 불러온다 ([context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)). 100줄이 넘는 참조 파일에는 목차를 둔다 ([skill best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)).
- 플러그인은 자기 기본 경로에 문서를 쓴다. superpowers v7.0.0은 스펙을 `docs/superpowers/specs/`에, 계획을 `docs/superpowers/plans/`에 쓰고, "사용자 설정이 이 기본값보다 우선한다"고 적는다 ([writing-plans](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md)). 이 저장소의 `AGENTS.md`에는 그런 우선 규칙이 없다.

## 3. 문서 타입마다 검증된 템플릿이 있다

| 문서 타입 | 후보 형식 | 필수 절 | 상태 값 |
|---|---|---|---|
| ADR | MADR 4.0.0(2024-09-17, 최신) | Context and Problem Statement, Considered Options, Decision Outcome(+Consequences) | proposed, rejected, accepted, deprecated, superseded by ADR-NNNN |
| 설계 스펙 | superpowers 스펙 + Google 설계 문서 | 맥락, 목표와 비목표, 제약, 설계, 대안, 보안, 미결 질문 | Draft → Approved → Superseded |
| 구현 계획 | superpowers 계획 + ExecPlan | Goal, Spec, Task별 체크박스 Step, 검증, 진행 기록 | 대기 → 진행 → 완료 |
| 런북 | Diátaxis how-to | 언제 쓰나, 사전 조건, 절차, 검증, 되돌리기 | 계속 갱신 |
| ARCHITECTURE | matklad | 조감도, 코드 지도, 불변 조건, 경계 | 계속 갱신(1년에 두 번쯤 점검) |
| 조사 | 날짜 고정 스냅샷 | 질문, 방법, 발견, 시사점 | 작성일 이후 고정 |

- MADR의 front matter 필드는 모두 선택이다(`status`, `date`, `decision-makers`, `consulted`, `informed`). 대체 관계는 `status` 문자열로 적는다 ([MADR](https://adr.github.io/madr/), [템플릿](https://github.com/adr/madr/blob/4.0.0/template/adr-template.md)). Nygard 원형은 Title, Context, Decision, Status, Consequences다 ([원문](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)).
- adr-tools 3.0.0(2018)은 사실상 멈췄고, 본문의 `## Status` 절을 awk로 고치는 방식이라 front matter와 맞지 않는다 ([adr-tools](https://github.com/npryce/adr-tools)). log4brains는 2024-12 이후 커밋이 없다 ([log4brains](https://github.com/thomvaill/log4brains)).
- GitHub Spec Kit v1.2.0(2026-10-13): `templates/`의 spec, plan, tasks, constitution 템플릿을 쓴다. 기능 번호는 기존 최대값 + 1이고, 메타데이터는 본문에 둔다(`**Status**: Draft`). 일관성 검사는 CLI가 아니라 에이전트가 실행하는 명령이다 ([Spec Kit](https://github.com/github/spec-kit)).
- Kiro: `.kiro/specs/<name>/`의 requirements(EARS 표기), design, tasks 세 문서를 승인 관문과 함께 쓴다. steering 파일은 front matter `inclusion`으로 언제 읽을지 정한다 ([specs](https://kiro.dev/docs/specs/), [steering](https://kiro.dev/docs/steering/)).
- OpenSpec v1.14.2(2026-10-15): `openspec/specs/`가 정본이고 변경은 `changes/<id>/`의 델타로 제안한 뒤 보관 시 병합한다. 실제 검증 CLI(`openspec validate --all --strict`)가 있다 ([OpenSpec](https://github.com/Fission-AI/OpenSpec)).
- BMAD-METHOD v6.12.4는 페르소나 워크플로가 무겁고 v7 알파가 진행 중이다 ([BMAD](https://github.com/bmad-code-org/BMAD-METHOD)). 이 저장소 규모에는 맞지 않는다(추론).
- Diátaxis는 문서를 tutorial, how-to, reference, explanation으로 나눈다. 런북은 how-to, ADR과 ARCHITECTURE는 explanation에 가깝다 ([compass](https://diataxis.fr/compass/)). 스펙·계획·리뷰는 Diátaxis 바깥의 프로젝트 기록이다(추론).
- ARCHITECTURE.md는 짧게 쓰고, 파일은 링크보다 이름으로 가리키고, 불변 조건(없는 것 포함)을 적는다 ([matklad](https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html)). Google 설계 문서는 맥락과 범위, 목표와 비목표, 설계, 검토한 대안, 교차 관심사로 이뤄진다 ([Design docs at Google](https://www.industrialempathy.com/posts/design-docs-at-google/)).
- front matter와 본문 메타데이터 중 어느 쪽을 LLM이 더 잘 읽는지에 대한 엄밀한 연구는 찾지 못했다. 형식(YAML, Markdown, JSON)이 정확도에 유의한 차이를 내지 않았다는 연구가 가장 가깝다 ([arXiv 2602.05447](https://arxiv.org/abs/2602.05447)). 기계가 검사할 필드(상태, 날짜, 대체 관계)는 front matter에 두는 편이 검사하기 쉽다(추론).

## 4. 문서 검사 도구

| 도구 | 버전 | 할 수 있는 일 | 이 저장소에 맞는 정도 |
|---|---|---|---|
| bats + awk | bats 1.14.0(테스트 이미지에 있음) | front matter 값, 파일 이름, 경로 존재 검사 | 새 의존성 없음. `tests/helpers.bash`에 `frontmatter` 함수가 이미 있다 |
| yq | v4.54.1 | `--front-matter=extract`로 front matter 추출 | 바이너리 하나 추가 |
| markdownlint-cli2 | v0.23.3 | MD043 규칙으로 문서 타입별 필수 헤딩 검사 | Node가 필요하다. 공식 Docker 이미지가 있다 |
| lychee | v0.24.2 | `--offline --include-fragments`로 로컬 링크와 앵커 검사 | 바이너리 하나 추가 |
| Vale | v3.24.0 | 문체 검사 | 구조 검사에는 어색하다 |
| check-jsonschema | 0.38.2 | JSON Schema로 YAML 검증 | Python과 front matter 추출이 필요하다 |

- 출처: [markdownlint MD043](https://github.com/DavidAnson/markdownlint/blob/main/doc/md043.md), [yq front matter](https://mikefarah.gitbook.io/yq/usage/front-matter), [lychee](https://lychee.cli.rs/guides/cli/), [Vale occurrence](https://docs.vale.sh/checks/occurrence), [check-jsonschema](https://github.com/python-jsonschema/check-jsonschema).
- remark-lint-frontmatter-schema는 2023-10 이후 릴리스가 없다. mdschema(v0.15.5)는 구조와 front matter 검사, 생성까지 한 바이너리로 하지만 1.0 전이다.

## 5. bash·bats 저장소는 대부분 평평한 tests와 공유 라이브러리를 쓴다

- bats-core v1.14.0(2026-07-21)에서 `run`이 함수 안의 `set -e`를 따르도록 바뀌었고, 테스트가 없으면 실패한다 ([릴리스](https://github.com/bats-core/bats-core/releases)). 공식 튜토리얼은 `test/*.bats`와 `test/test_helper/`를 쓴다 ([tutorial](https://bats-core.readthedocs.io/en/stable/tutorial.html)).
- `bats`는 `-r` 없이는 최상위 파일만 실행한다. `setup_suite.bash`는 실행되는 첫 `.bats` 파일의 폴더에서만 찾는다 ([usage](https://bats-core.readthedocs.io/en/stable/usage.html), [writing tests](https://bats-core.readthedocs.io/en/stable/writing-tests.html)).
- 테스트 파일은 n+1번 평가되므로 함수 밖에 코드를 두지 않는다. bash 3.2에서는 실패한 `[[ ]]`가 테스트를 실패시키지 않으므로 `|| false`를 붙인다 ([FAQ](https://bats-core.readthedocs.io/en/stable/faq.html), [gotchas](https://bats-core.readthedocs.io/en/stable/gotchas.html)).
- `bats/bats` 이미지에는 bats-support 0.3.0, bats-assert 2.1.0, bats-file 0.4.0이 `/usr/lib/bats`에 들어 있다 ([docker usage](https://bats-core.readthedocs.io/en/stable/docker-usage.html)).
- 명령 스텁은 PATH 앞에 가짜 실행 파일을 두는 직접 만든 방식이 여전히 일반적이다. ruby-build와 rbenv도 bats-mock 대신 자체 `stub`을 쓴다(추론, 두 저장소의 `test/test_helper.bash`).
- kcov v43의 `--include-path`는 경로 접두어로 맞추므로 `scripts/` 아래 하위 폴더도 자동으로 포함한다 ([filter.cc](https://raw.githubusercontent.com/SimonKagstrom/kcov/master/src/filter.cc)).
- Google Shell Style Guide: 라이브러리는 `.sh` 확장자에 실행 권한이 없다. 함수가 둘 이상인 스크립트는 `main "$@"`로 끝난다. 상수는 대문자 `readonly`다. 파일마다 머리 주석을 둔다 ([style guide](https://google.github.io/styleguide/shellguide.html)).
- 실제 저장소의 배치:
  - rbenv는 명령마다 `libexec/rbenv-<cmd>` 하나와 `test/<cmd>.bats` 하나를 1:1로 둔다.
  - kubernetes `hack/`은 동사 접두어(`verify-*`, `update-*`)가 붙은 평평한 스크립트와 `hack/lib/*.sh`를 쓰고, 이중 source를 표지 함수로 막는다 ([init.sh](https://raw.githubusercontent.com/kubernetes/kubernetes/master/hack/lib/init.sh)).
  - bats-core, asdf, dokku도 테스트 폴더가 평평하다.
- shfmt v3.14.1은 `.editorconfig`의 `language_dialect = bats`를 읽는다. 명령줄에 서식 옵션을 하나라도 주면 `.editorconfig`를 무시한다 ([shfmt](https://raw.githubusercontent.com/mvdan/sh/master/cmd/shfmt/shfmt.1.scd)). 이 저장소의 shfmt는 v3.12.0이고, 그 버전이 bats 방언을 지원하는지는 확인하지 못했다(미확인).

## 시사점

1. Gemini CLI용 `.gemini/settings.json`을 커밋해 네 도구가 같은 `AGENTS.md`를 읽게 한다.
2. `AGENTS.md`는 지도로 두고, 문서·스크립트·테스트 규칙의 세부는 스킬과 `docs/` 색인으로 옮긴다. 하위 폴더의 `AGENTS.md`는 도구마다 읽는 시점이 달라서 쓰지 않는다.
3. 문서 타입, 위치, 파일 이름, 상태 값, 템플릿을 한 곳(레지스트리)에 두고, 검사와 생성 명령이 그 한 곳을 읽게 한다. 그러면 새 타입을 더하는 일이 행 하나와 템플릿 하나로 끝난다.
4. 검사는 bats + awk로 한다. 새 도구가 필요 없고, 기존 `frontmatter` 도우미를 쓸 수 있다.
5. 템플릿은 검증된 형식(MADR, 기존 superpowers 계획 골격, Diátaxis how-to, matklad)을 이 저장소 말투로 옮긴다. Spec Kit·Kiro·OpenSpec·BMAD처럼 폴더 체계 자체를 바꾸는 방식은 쓰지 않는다.
6. 스크립트와 테스트는 평평하게 두고 이름 규칙으로 짝을 맞춘다. 공유 함수는 관심사별 라이브러리로 나누고 이중 source를 막는다.
