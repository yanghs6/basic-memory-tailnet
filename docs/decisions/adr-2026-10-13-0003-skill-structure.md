---
status: accepted
date: 2026-10-13
---

# ADR 0003: 스킬 구조와 작성 규칙

## 맥락

이 저장소의 스킬은 Claude Code, Codex, Gemini CLI, Antigravity가 함께 씁니다. 정본은 `.agents/skills/`에 두고, Claude Code용 링크는 `.claude/skills/`에 둡니다. 2026-10-13 기준으로 스킬 5개가 모두 `SKILL.md` 한 파일이었습니다. 문제는 세 가지였습니다.

- **배포 값이 여러 스킬에 흩어져 있었습니다.**
  - 호스팅 전환(`a82df1c`)에서 스킬 3개를, Tailscale 노드 이름 변경(`d15506b`)에서 스킬 2개를 고쳐야 했습니다.
  - 남아 있던 하드코딩은 `agent-hub` 11곳과 zone `us-west1-b` 3곳이고, 클라우드 CLI 명령도 스킬 안에 있었습니다(**Command:** `grep -n -oE 'us-west1-b|agent-hub' .agents/skills/*/SKILL.md`).
- **본문이 길고 문단 단위로 뭉쳐 있었습니다.** 150단어가 넘는 단계가 여러 개였고, 스킬 전체 합계는 3,322단어였습니다(**Command:** `wc -w`). 그래서 한 단계만 고쳐도 문단 전체가 diff에 잡혔고, 병렬 브랜치끼리 충돌하기 쉬웠습니다.
- **새 스킬을 추가하는 규칙이 문서로 없었습니다.** 테스트는 표준 frontmatter 키, 이름과 폴더 일치, 링크, 500줄만 검사했습니다. 이 결정 이전 상태로 실험해 보니 에이전트가 README 목록, "Not for" 경계, 클라우드 명령 위치를 놓쳤습니다(아래 "검증").

## 근거

**Verified (2026-10-13 웹 조사):**
- **Agent Skills 명세**([agentskills.io/specification](https://agentskills.io/specification))
  - frontmatter 키는 여섯 개뿐입니다.
    - `name`: 1~64자, 소문자·숫자·하이픈, 폴더명과 일치
    - `description`: 1~1024자
    - `license`
    - `compatibility`: 500자 이하
    - `metadata`: 문자열 맵
    - `allowed-tools`: 실험적
  - 선택 폴더는 `scripts/`, `references/`, `assets/`입니다. 참조는 `SKILL.md`에서 한 단계 깊이까지만 둡니다.
  - 검증기 `skills-ref`가 허용하는 키도 같은 여섯 개입니다([skills-ref](https://github.com/agentskills/agentskills/tree/main/skills-ref)).
- **Anthropic**([best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), [Claude Code skills](https://code.claude.com/docs/en/skills))
  - `SKILL.md`는 500줄 미만으로 둡니다.
  - Claude Code는 압축 후 스킬마다 앞 5,000토큰만 남깁니다. 그래서 중요한 규칙을 맨 위에 둡니다.
  - 다단계 작업에는 복사용 체크리스트를 둡니다. 위험한 단계는 정확한 명령으로 씁니다. "Gotchas"는 가장 가치가 큰 내용입니다.
  - Claude 전용 키(`disable-model-invocation`, `when_to_use` 등)는 claude.ai·API 업로드에서 오류를 냅니다.
- **도구별 동작**
  - Codex([skills](https://developers.openai.com/codex/skills))
    - `.agents/skills`를 직접 읽습니다.
    - 스킬 목록이 문맥의 2% 또는 8,000자를 넘으면 description을 줄입니다.
    - 도구 전용 설정은 `agents/openai.yaml`에 둡니다.
  - Gemini CLI([skills](https://geminicli.com/docs/cli/skills/)): `.agents/skills/<name>/SKILL.md`를 한 단계 깊이에서만 찾습니다.
  - Claude Code: 이름이 같으면 개인 스킬(`~/.claude/skills`)이 프로젝트 스킬을 가립니다.
- **운영 사례**
  - Vercel 평가: 스킬이 호출되지 않은 경우가 56%였고, AGENTS.md의 색인이 더 안정적이었습니다([Vercel](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)).
  - description은 "Use when …", 사용자의 말과 증상, "Not for …" 경계로 씁니다([agentskills.io](https://agentskills.io/skill-creation/optimizing-descriptions), [Codex skill-creator](https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/skill-creator/SKILL.md)).
  - 스킬끼리 파일을 공유하지 않고 이름으로 참조하며, 값은 복사하지 않고 원본에 링크합니다([Cloudflare](https://github.com/cloudflare/skills/blob/main/CONTRIBUTING.md)).

## 결정

1. **표준만 씁니다.** frontmatter는 명세의 여섯 키만 씁니다. 도구 전용 정보는 `metadata`나 `agents/openai.yaml`에 둡니다.
2. **한 값은 한 곳에만 둡니다.**
   - 클라우드 명령, zone, 인스턴스 이름은 런북에만 둡니다. 스킬은 런북 섹션을 이름으로 가리킵니다.
   - 스크립트에 적용하던 클라우드 중립 검사(`tests/cloud_neutral.bats`)를 스킬에도 적용합니다.
   - 호스트와 사용자 이름은 `.env.example`의 변수와 기본값으로 밝힙니다(`BM_VM_HOST`, 기본값 `agent-hub`).
3. **본문 모양을 통일합니다.** 운영 스킬은 Rules → 복사용 Checklist → 정확한 명령의 Steps → Gotchas 순서로 씁니다. 무언가를 바꾸는 단계에는 "Ask first"를 붙입니다.
4. **일부 실행에만 필요한 내용은 `references/`로 분리하고, `SKILL.md`에는 언제 읽을지를 적습니다.**
   - 계속 늘어나는 오류 목록: `bm-diagnose/references/failure-messages.md`
   - 드문 롤백: `bm-upgrade/references/rollback.md`
   - 리뷰·머지 단계: `git-workflow/references/review-and-merge.md`
5. **description은 정해진 순서로 쓰고, 절차는 요약하지 않습니다.** 순서는 "무엇을 하는지 → Use when + 사용자 표현·증상 → Not for + 형제 스킬"입니다.
6. **AGENTS.md의 `## Skills`는 "상황 → 스킬" 형식으로 씁니다.** 스킬 선택은 항상 로드되는 색인에 맡깁니다.
7. **확장 경로를 만듭니다.**
   - `skill-authoring` 스킬과 템플릿 `assets/skill-template.md`를 추가합니다.
   - `tests/skills.bats`가 규칙을 검사합니다.
     - 명세 제약
     - 폴더 구성, 중첩 `SKILL.md` 금지
     - 고아 파일, 한 단계 참조
     - `.agents/skills`와 `.claude/skills` 링크 양방향
     - AGENTS.md·README 목록
   - 기존 키 검사가 밑줄이 든 키(`when_to_use`)를 놓치던 결함(계획 02에서 생김)도 이번에 고쳤습니다.

## 하지 않은 것

| 항목 | 이유 |
|---|---|
| `skills-ref validate`를 `make check`에 추가 | 검증기 README가 "demonstration purposes only"라고 적고 있고, PyPI 배포도 없습니다. 같은 규칙을 bats로 검사합니다. |
| Claude `disable-model-invocation`, Codex `allow_implicit_invocation: false` | 도구 간 공통 방법이 없습니다. 이 저장소는 바꾸는 단계마다 "Ask first"로 막습니다. `agents/` 폴더는 필요해지면 쓸 수 있도록 허용만 합니다. |
| `metadata.version`, lifecycle, owner | 스킬 6개에 사용자 1명이라 아직 필요가 없습니다. 스킬이 늘거나 공동 소유가 생기면 다시 봅니다. |
| 트리거 평가 자동화(`claude -p` 반복 실행) | 실행할 때마다 모델 비용이 듭니다. 대신 `skill-authoring`의 "Test the skill" 절차(기준선과 변경 후 비교)를 씁니다. |
| `git-workflow`, `branch-review` 이름에 접두사 붙이기 | 지금은 개인 스킬과 이름이 겹치지 않습니다(**Command:** `ls ~/.claude/skills ~/.agents/skills`). 이름을 바꾸면 스크립트, 테스트, 문서를 함께 고쳐야 합니다. 새 스킬부터 충돌을 확인합니다. |
| `bm-recover` 마지막 문단 분리 | `plan/05-vm-rollout`이 같은 문단을 고치고 있어 바이트 단위로 그대로 두었습니다. 계획 05가 병합된 뒤 Gotchas로 나눌 수 있습니다. |

## 검증

**에이전트 시나리오** (Claude Sonnet 서브에이전트, 읽기 전용, 2026-10-13). 기준선은 main 체크아웃(이 결정 이전)이고, 결과는 이 브랜치의 worktree입니다. 프롬프트에는 어떤 스킬을 쓰라는 말을 넣지 않았습니다.

| 시나리오 | 기준선 | 결과 |
|---|---|---|
| 백업 스킬을 새로 추가 | README 목록 누락. description에 "Not for" 없음. 스크립트가 하는 검사를 prose로 반복. 개인 스킬과 이름 충돌 미확인. | AGENTS.md 라우팅 줄과 README를 모두 갱신. "Not for"에 형제 스킬 명시. 충돌 확인. 시험 절차까지 계획. prose 검사가 남아 있어 "단계 = make 타깃·스크립트 호출 + 출력 확인" 레시피를 보강함. |
| `bm-diagnose`에 시리얼 콘솔 단계 추가 | 클라우드 CLI 명령과 `--zone=us-west1-b`를 스킬 본문에 하드코딩. | 명령은 런북의 새 섹션에 넣고, 스킬은 섹션 이름으로 가리킴. `tests/cloud_neutral.bats` 인용. |
| `make probe`가 `tools/list: missing tool` 출력 | — | `bm-diagnose` → `references/failure-messages.md` → `bm-upgrade` 순서로 찾음. 읽기 전용 유지. |
| 업그레이드 직후 verify 실패(마이그레이션 있음) | — | `references/rollback.md`를 찾음. 사용자 동의를 받고, 사용자가 직접 `yes`를 입력하게 하고, 새 고정값은 커밋하지 않음. |
| Codex 역할로 리뷰·머지 준비 | — | `references/review-and-merge.md`를 찾음. `REVIEWER=claude`, 머지 메시지 파일, 정리 순서를 정확히 따름. |

**검사의 실효성:** 위반 13가지를 섞은 임시 스킬을 넣고 `make test`를 실행했습니다(**Command:** `make test`). 위반 13가지는 다음과 같습니다.

- 비표준 키 `when_to_use`
- 이름의 대문자·밑줄
- 접힌 `compatibility`
- description의 `: `, 꺾쇠, "Use when" 누락
- 폴더 안 README
- 중첩 `SKILL.md`
- 고아 reference
- 형제 링크
- 클라우드 CLI 명령
- `.claude/skills` 링크 누락
- AGENTS.md·README 목록 누락

처음에는 `when_to_use`만 통과했고, 키 정규식을 고친 뒤에는 13가지가 모두 실패로 잡혔습니다. 임시 스킬은 지웠습니다.

**Claude Code 로딩:** 이 세션의 스킬 목록에 `bm-diagnose`, `bm-recover`, `bm-upgrade`, `skill-authoring`의 새 description이 그대로 나타났습니다. frontmatter가 정상 파싱된다는 뜻입니다. `git-workflow`와 `branch-review`의 새 description은 목록에서 확인하지 못했고, 형식은 `tests/skills.bats`로만 검사했습니다.
