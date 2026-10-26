---
status: accepted
id: vtmqpsyx
date: 2026-10-26
---

# ADR vtmqpsyx: 저장소 밖으로 나가는 텍스트는 패턴 검사기 하나로 IP, tailnet 이름, 세션 링크, Generated with 줄을 막는다

- 설계: [GitHub PR 워크플로 설계](../specs/spec-2026-10-13-pr762r68-github-pr-workflow.md)
- 대체 범위: 위 설계의 6절 `scripts/check-pr.sh` 검사 목록(세션 링크 문자열 하나만 찾던 항목)과 11절 마지막 문장("자동 검사는 GitHub secret scanning과 push protection에 맡긴다")을 보완한다. 비밀값 검사는 그대로 GitHub과 GitGuardian에 맡기고, 이 ADR은 인프라 식별자와 세션 흔적의 자동 검사를 더한다.
- 계획: [public-text-guard 계획](../plans/plan-2026-10-22-v9whrbs6-public-text-guard.md)

## 맥락과 문제

- **Reported (2026-10-22 평가):** `AGENTS.md`의 "VM IP를 커밋·PR·저장소 파일에 쓰지 않는다" 규칙에 자동 검사가 없다. 주입 실행에서 tailnet 대역 주소가 런북(`make check`), 커밋 메시지(`scripts/check-git.sh`), PR 본문(`scripts/check-pr.sh`)을 모두 통과했다. 커밋 메시지의 세션 트레일러, Generated with 줄, ts.net 이름도 통과했다.
- 설계 11절은 "실제 값을 넣어 검사하면 그 값이 공개된다"는 이유로 자동 검사를 GitHub에 맡겼다. 실제 값 없이 모양(패턴)과 허용 집합만으로 검사하면 그 근거와 충돌하지 않는다.
- 저장소에는 규칙을 설명하는 문장, 문서용 예시 주소, 완료된 계획의 증거가 많다. 문자열을 그대로 찾으면 오탐이 많아서 아무도 검사를 켜 두지 않는다([계획](../plans/plan-2026-10-22-v9whrbs6-public-text-guard.md) 배경의 오탐 표).

## 검토한 대안

1. 문자열 그대로 검사(지금의 `claude.ai/code/session` 포함 여부, 11절의 grep): 단순하다. 규칙 설명 문장과 문서용 주소, 버전 문자열까지 걸려서 `make check`에 넣을 수 없다.
2. `origin/main` 이후 바뀐 줄만 검사: 기존 기록의 오탐이 없다. CI `check` job은 `fetch-depth`를 정하지 않아 base가 없고, 커밋 메시지와 PR 본문에는 "바뀐 줄"이 없다.
3. 비밀값 스캐너(GitHub push protection, GitGuardian, gitleaks)에 맡기기: 이미 있다. 이 스캐너들은 자격증명 모양을 찾고, VM IP·tailnet 이름·세션 링크는 비밀값으로 보지 않는다. 우리만 아는 허용 집합(문서용 대역, IAP 대역, 자리표시자)을 넣을 수도 없다.
4. 패턴 검사기 하나와 tracked 모드 전용 예외 파일(선택): 오탐을 허용 집합과 자리표시자 규칙으로 줄이고, 남는 완료 기록과 must-fail fixture만 예외로 둔다. 예외 파일에 있는 파일에서는 같은 종류의 새 값을 놓친다.

## 결정

1. `scripts/check-public-text.sh [--label NAME] [FILE|-]...` 하나가 패턴, 허용 집합, 자리표시자 규칙, 예외 적용을 모두 가진다. 다른 스크립트는 이 스크립트를 부른다.
2. 종류는 다섯 가지이고, 예외 파일에서 쓰는 짧은 id가 있다.

   | 종류(출력 이름) | id | 걸리는 모양 |
   |---|---|---|
   | `IPv4 address` | `ipv4` | 점으로 이은 숫자 네 개. 앞에 숫자나 "숫자 + 점"이 없고, 뒤에 "점 + 숫자"가 없으며, 옥텟이 모두 0~255인 것. 허용 집합 밖의 주소 |
   | `tailnet IPv6 address` | `tailnet-ipv6` | Tailscale ULA 접두사(`fd7a:115c:a1e0::/48`, 대소문자 무시) 뒤에 주소 그룹이 더 붙은 것. 접두사만 쓴 대역 표기는 통과 |
   | `ts.net host name` | `ts-net` | `.ts.net`으로 끝나는 호스트 이름 가운데 자리표시자가 아닌 것 |
   | `session link` | `session-link` | Claude Code 세션 URL 경로 뒤에 `session_`과 영숫자 id가 붙은 것, 또는 첫 글자가 세션 트레일러 키(`Claude-Session`)로 시작하는 줄. 둘 다 대소문자를 무시한다. id 없는 경로는 통과 |
   | `Generated with line` | `generated-with` | 공백, 목록·인용 기호(`-`, `*`, `>`, `1.`), 이모지 같은 비ASCII 기호 뒤에 바로 `Generated with`로 시작하는 줄. 줄 중간의 언급은 통과 |

3. IPv4 허용 집합은 loopback(`127.0.0.0/8`), `0.0.0.0`, 문서용 대역 세 개(RFC 5737), IAP TCP 포워딩 대역(`35.235.240.0/20`, [접근 모드 설계](../specs/spec-2026-10-15-jr59pvyf-access-modes.md)), RFC 1918 사설 대역, link-local(`169.254.0.0/16`)이다. 스크립트에 이름 있는 상수로 둔다.
4. 대역 표기(`a.b.c.d/n`)는 `a.b.c.d`가 그 접두사의 네트워크 주소(호스트 비트가 모두 0)이고 접두사가 `/24` 이하일 때만 통과한다. 어느 대역이든 같다(예: CGNAT 대역 `100.64.0.0/10`). 호스트 비트가 0이 아니거나 접두사가 `/25`~`/32`이면 낱개 주소로 검사한다. `/30`·`/31` 같은 좁은 대역은 호스트 주소와 거의 같고, `/32`는 호스트 하나다. 상한 `/24`는 스크립트 상수(`MAX_NETWORK_PREFIX`)이고, **Verified (2026-10-26):** 저장소 문서가 네트워크 주소 형식으로 쓰는 접두사 가운데 가장 긴 것이 `/24`다(접두사 길이만 셌다).
5. CGNAT(tailnet) 대역의 낱개 주소는 어떤 저장소 파일에도 쓰지 않는다. 테스트는 이런 주소를 실행 중에 만든다(사용자 결정 2026-10-26).
6. ts.net 이름은 `<`, `*`, `{` 가운데 하나가 들어 있거나, 점으로 나눈 라벨 하나가 `example`, `tail1234`, `tailnet` 가운데 하나이거나 `example-`로 시작하면 자리표시자로 보고 통과시킨다. `example`이 라벨 중간에 들어 있기만 한 이름은 걸린다.
7. 걸리면 `<라벨 또는 경로>:<줄>: <종류>`를 줄과 종류마다 한 줄씩 stderr에 쓰고, 가리는 방법을 한 줄 안내한 뒤 exit 1로 끝낸다. 걸린 값과 그 줄의 내용은 출력하지 않는다. 줄 끝의 CR은 지우고 검사하므로 CRLF 텍스트(GitHub이 보내는 PR 본문)도 똑같이 걸린다.
8. 인자가 없으면 `git rev-parse --show-toplevel`의 저장소에서 tracked 파일과 새 파일(`git ls-files -co --exclude-standard`) 가운데 일반 텍스트 파일만 검사한다. 심볼릭 링크(`.claude/skills/<이름>` 디렉터리 링크 포함), 지운 파일, 바이너리 파일은 건너뛴다.
9. 예외 파일은 저장소 루트의 `.public-text-exemptions`이다(Open question 1 A안, 사용자 결정 2026-10-26). 한 줄에 `<저장소 기준 경로> <종류 id>`를 적고 값은 적지 않는다. `#` 주석과 빈 줄을 쓸 수 있다. 한 줄은 그 파일의 그 종류만 면제한다. 형식이 틀린 줄이 있으면 검사기가 그 줄 번호를 알리고 exit 1로 멈춘다. 파일이 없으면 예외도 없다.
   - 읽을 수 없는 파일(권한, 읽기 오류)은 통과시키지 않는다. `<경로>: unreadable`을 알리고 exit 1로 끝낸다. 인자 모드와 인자 없는 모드가 같다.
10. 예외는 인자 없는 tracked 모드에만 적용한다. 명시한 파일과 stdin(`-`)에는 적용하지 않는다. 커밋 메시지, PR 텍스트, 리뷰 보고서에는 예외가 없다.
11. 검사하는 곳은 다음과 같다(계획 Task 2~4).
    - `make check`: repo 테스트가 인자 없이 실행해 tracked 파일과 새 파일을 검사한다.
    - `scripts/check-git.sh`: 커밋 메시지 전체(제목, 본문, 트레일러)를 짧은 SHA 라벨로 검사한다.
    - `scripts/check-pr.sh`: PR 제목과 본문 전체를 검사한다. 6절의 세션 링크 항목은 이 검사로 바뀐다.
    - `scripts/post-review.sh`, `scripts/post-review-record.sh`: 게시 직전의 보고서 본문을 검사하고, 걸리면 `gh`를 부르지 않는다.
12. 11절 공개 전 점검의 IP·ts.net 확인은 `git log -p <ref> | scripts/check-public-text.sh -`로 한다. `tskey-`, 개인키, 메일 주소를 찾는 grep과 실제 값을 넣는 사용자 터미널 점검은 그대로 둔다.

## 결과

- 좋아지는 것: VM IP, tailnet 이름, 세션 링크, Generated with 줄이 파일, 커밋, PR, 리뷰 코멘트로 나가기 전에 기계적으로 멈춘다. 출력에 값이 없으므로 검사 로그가 다시 새는 길이 되지 않는다.
- 치르는 것: 예외 파일에 오른 파일에서는 같은 종류의 새 값을 놓친다. 완료된 기록과 fixture만 올리므로 위험은 작다. 허용 집합 밖의 문서용 예시(예: 실제 공개 DNS 리졸버)는 자리표시자나 문서용 대역으로 써야 한다. 글자가 붙은 4부분 버전 문자열(예: `v` 뒤에 숫자 네 개)은 주소로 걸린다.
- 버전 문자열을 통과시키는 대가로(계획 Review Focus 3), 점으로 이은 숫자 바로 뒤에 붙은 실제 주소는 놓친다. 예를 들어 주소 앞에 `1.`이 붙으면 다섯 부분짜리 숫자로 보고 건너뛴다.
- 예외 파일은 칸을 공백으로 나누므로, 공백이 들어간 경로는 예외로 적을 수 없다. 그런 파일은 값을 자리표시자로 바꾼다.
- 패턴으로 구별할 수 없는 GCP 프로젝트 ID와 VM 외부 IPv6는 이 검사 밖이다. 11절의 사용자 터미널 점검을 그대로 쓴다.
- 확인 방법: `tests/check-public-text.bats`(종류별 must-fail, 허용 형식, 예외 범위)와 계획 Task 2의 `tests/repo-public-text.bats`(인자 없는 실행이 `make check`에서 exit 0)이다.
