---
status: accepted
id: y9fxhf7x
date: 2026-10-27
---

# ADR y9fxhf7x: PR이 `@test`를 줄이거나 `skip`을 더하면 PR 본문 트레일러 `Tests-Removed: <이유>`가 있어야 통과한다

- 설계: [GitHub PR 워크플로 설계](../specs/spec-2026-10-13-pr762r68-github-pr-workflow.md)
- 대체 범위: 위 설계 6절의 `pr-rules` 내용(`make check-git`과 `scripts/check-pr.sh`)에 세 번째 검사 `scripts/check-tests.sh`를 더한다. 6절의 나머지(이벤트 타입, 권한, `env:` 전달)는 그대로다.
- 계획: [invariant-enforcement 계획](../plans/plan-2026-10-22-m97w7hqe-invariant-enforcement.md) Task 2

## 맥락과 문제

- **Reported (2026-10-22 평가):** `AGENTS.md`의 "never weaken a test to make it pass" 규칙에 기계 검사가 없다. 주입 실행에서 불변식 테스트 삭제와 `skip` 추가가 `make check`를 통과했다. PR #16의 220 → 138 테스트 감소는 승인된 정리였지만 기계 신호 없이 병합됐다.
- 테스트를 지우거나 건너뛰는 것 자체는 막을 일이 아니다. [test-scope ADR](adr-2026-10-13-a878ypj5-test-scope.md)처럼 정리로 줄이는 일이 있다. 막을 것은 이유 없이 줄어드는 것이다.
- `make check`는 트리 하나만 보므로 "줄었다"를 알 수 없다. PR 단위 검사는 `pr-rules` 잡이 이미 하고, 그 잡은 PR 본문을 고치면 다시 돈다.

## 검토한 대안

1. 표지 없이 감소와 `skip`을 항상 실패로 둠: 단순하다. 승인된 정리도 막혀서 결국 검사를 끄게 된다.
2. 표지 둘(`Tests-Removed`는 감소, `Tests-Skipped`는 새 `skip`): 이유를 구분해 남긴다. 표지가 둘이라 외울 것과 파서 경우가 늘고, 둘 다 "테스트를 약하게 한 이유"라는 같은 뜻이다.
3. 표지 하나 `Tests-Removed: <이유>`(선택): 기존 트레일러(`Assisted-by`, `Plan`)와 같은 꼴이고 같은 파서로 읽는다. PR 본문 트레일러 문단에 있으면 squash 커밋에 남아 `main` 이력에서 이유를 찾을 수 있다. 감소와 `skip`을 구분하지 않는다.
4. PR 라벨이나 리뷰 승인으로 허용: 본문을 고치지 않아도 된다. 라벨은 squash 커밋에 남지 않고, 라벨 이벤트는 지금 `pr-rules`의 이벤트 타입에 없다.

## 결정

1. **Verified (2026-10-27):** 사용자가 계획의 Open question 1에서 대안 3을 골랐다. 표지는 트레일러 `Tests-Removed: <이유>` 하나이고, `@test` 수 감소와 새 `skip`을 모두 덮는다.
2. 표지는 `Assisted-by`와 같게 파싱한다. PR 제목, 빈 줄, 본문으로 만든 squash 커밋 메시지의 마지막(트레일러) 문단에 있고 값이 비어 있지 않아야 한다. 값이 빈 `Tests-Removed:`나 본문 중간 문단의 `Tests-Removed:`는 표지가 아니다. 파서는 `scripts/lib/git.sh`의 `pr_trailers`와 `trailer_values`이고 `scripts/check-pr.sh`와 함께 쓴다.
3. 기준점은 `git merge-base origin/main HEAD`다. 브랜치가 `git merge origin/main`으로 받은 `main` 쪽 삭제나, 브랜치가 아직 받지 않은 `main` 쪽 추가는 PR 탓이 아니기 때문이다. 기준점이 없으면 고칠 방법과 함께 실패한다.
4. 센다: 기준점과 `HEAD`의 `tests/*.bats`에서 `^@test `로 시작하는 줄 수. 줄었으면 위반이다.
5. 찾는다: 기준점과 `HEAD` 사이에 `tests/*.bats`와 `tests/helpers.bash`에 더해진 줄 가운데 `skip`이 명령 위치(줄 처음이나 `&&`, `||`, `;`, `|`, `{`, `(` 뒤, 그 사이에 `then`, `else`, `do`가 와도 됨)에 있고 뒤에 공백이나 줄 끝이 오는 줄. `[ "$(id -u)" -eq 0 ] && skip "…"`, `if …; then skip "…"; fi`, `{ skip "…"; }` 모양도 잡고, 테스트 이름의 `skips`나 문자열 `"skipping"`은 잡지 않는다.
6. 검사는 `scripts/check-tests.sh BASE`(입력 `PR_TITLE`, `PR_BODY`)이고 `pr-rules` 잡의 새 단계 "Test count and skips"가 `origin/main`으로 실행한다. 새 잡은 만들지 않는다. ruleset의 필수 검사 목록을 바꾸지 않기 위해서다.

## 결과

- 이유 없는 테스트 삭제와 `skip`이 PR에서 실패하고, 이유는 squash 커밋 트레일러로 `main`에 남는다. 이유를 쓰면 통과하므로 승인된 정리는 막지 않는다. 판단은 여전히 사람 리뷰가 한다.
- 알려진 한계:
  - 하나를 지우고 하나를 더한 PR은 수가 같아 통과한다. 수만 세고 어떤 테스트인지는 보지 않는다.
  - 단언을 약하게 바꾼 것(`assert_failure`를 지움, 기대값을 넓힘, 반복문 경우를 뺌)은 잡지 않는다.
  - 명령 위치 판단은 정규식이라 문자열 안의 `; skip x`나 `(skip x)` 같은 줄은 위반으로 잡힌다(오탐). 이런 줄은 변수로 만들어 피하거나 표지를 단다. `tests/check-tests.bats`는 `skip` 줄을 변수로 만든다.
  - `Makefile`의 커버리지 기준(`COVERAGE_MIN`)을 낮추는 변경은 범위 밖이다.
- 확인 방법: `tests/check-tests.bats`(통과 반복문: 그대로, 하나 더함, `main`이 더한 것을 받지 않음, `main`이 지운 것을 병합. 실패 반복문: 지움, `skip`, `&& skip`, `then skip`, `{ skip`, 이유 있는 지움은 통과, 빈 값과 중간 문단은 실패), `tests/lib-git.bats`의 `pr_trailers` 경우, PR마다 `pr-rules`의 "Test count and skips" 단계.
