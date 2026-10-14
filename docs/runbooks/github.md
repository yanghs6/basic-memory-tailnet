# GitHub 운영: 머신 계정, 첫 push, 저장소 설정

정책: [GitHub PR 워크플로 스펙](../specs/2026-10-13-github-pr-workflow-design.md). 저장소: `https://github.com/yanghs6/basic-memory-tailnet` (공개). 이 런북의 명령은 사용자가 자기 터미널에서 실행합니다. `gh auth login`은 대화형이라 별도 터미널 앱에서 실행합니다.

## 1. 머신 계정과 토큰

1. 새 이메일로 GitHub 계정을 만들고 2FA를 켭니다(이 저장소의 머신 계정은 `yanghs6-bot`). 약관상 사람이 직접 만들고, 자동화 작업에만 씁니다(**Verified**, GitHub 약관 B(3)).
2. 개인 계정으로 머신 계정을 이 저장소의 협업자(권한 Write)로 초대하고, 머신 계정으로 수락합니다. 머신 계정에는 다른 저장소 권한을 주지 않고, 머신 계정으로 저장소를 만들지 않습니다. classic 토큰의 실제 범위는 계정 권한으로 정해지기 때문입니다.
3. 머신 계정에서 classic 토큰을 만듭니다. Settings → Developer settings → Personal access tokens (classic)에서 범위는 `public_repo`와 `workflow`, 만료는 90일로 둡니다. 남의 공개 저장소에 쓰려면 classic 토큰이어야 합니다(**Verified**, GitHub 토큰 문서).
4. 이 Mac에 등록합니다. 토큰은 숨김 프롬프트에만 붙여 넣고, 채팅·파일·명령 인자·파이프에 넣지 않습니다.

```bash
gh auth login            # GitHub.com → HTTPS → Paste an authentication token
gh auth status           # 머신 계정이 보여야 합니다
cd <main 체크아웃>
git config --local credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper '!gh auth git-credential'
```

- credential 설정은 이 저장소에만 적용됩니다. 모든 worktree가 main 체크아웃의 설정을 공유합니다.
- 기본 `gh`는 머신 계정입니다. 사용자가 관리자 작업을 할 때는 개인 계정용 설정 디렉터리를 따로 씁니다. 처음 한 번 `GH_CONFIG_DIR="$HOME/.config/gh-yanghs6" gh auth login`으로 로그인합니다.

## 2. 공개 전 점검

처음 공개하는 이력(첫 push의 `main`, 처음 push하는 브랜치)마다 실행합니다. `<ref>`는 공개할 브랜치입니다.

```bash
git log -p <ref> | grep -nE 'tskey-[A-Za-z0-9]{10,}|PRIVATE KEY|([0-9]{1,3}\.){3}[0-9]{1,3}|[a-z0-9-]+\.ts\.net|@[A-Za-z0-9.-]+\.[a-z]{2,}'
git log -p <ref> | grep -cF '<실제 VM 외부 IP>'
git log -p <ref> | grep -cF '<실제 VM Tailscale IP>'
git log -p <ref> | grep -cF '<GCP 프로젝트 ID>'
```

- 첫 명령에 걸린 줄이 테스트용 자리표시자인지 하나씩 확인합니다. 예: `127.0.0.1`, `203.0.113.10`, `tail1234.ts.net`, `agent@example.com`, `tskey-auth-test123`.
- 나머지 명령은 모두 `0`이어야 합니다.
- **실제 값이 걸리면 push하지 않습니다.** 현재 파일만 고쳐도 과거 커밋에는 값이 남습니다. 공개를 허용할지, 이력을 정리할지를 사용자가 정합니다(스펙 11절). 실제 자격증명이면 공개 여부와 관계없이 폐기하고 교체합니다.
- `plan/05-vm-rollout`은 push하지 않습니다. 커밋 하나에 VM Tailscale IP가 있습니다. 계획 05는 스펙 11절의 `plan/05-vm-rollout-public` 절차로 공개합니다.

## 3. 처음 push

원격 `main`에는 `LICENSE` 커밋 하나가 있고, 로컬 이력과 공통 조상이 없습니다. main 체크아웃에서 한 번만 실행합니다. force push는 쓰지 않습니다.

```bash
git remote add origin https://github.com/yanghs6/basic-memory-tailnet.git
git fetch origin
git merge --allow-unrelated-histories origin/main -m "Merge the GitHub repository's initial commit"
git push -u origin main
```

## 4. 저장소 설정과 ruleset

두 번에 나눠 적용합니다. 저장소 설정은 계획 08의 PR을 병합하기 **전에**, ruleset은 병합한 **뒤에** 적용합니다. 저장소 설정 전의 squash 메시지 기본값은 커밋 메시지 목록(`COMMIT_MESSAGES`)이라, 그대로 병합하면 브랜치 커밋 메시지가 `main`에 남습니다. 필수 체크는 워크플로가 `main`에 들어간 뒤에 걸어야 합니다. 그 전에 걸면 어떤 PR도 병합할 수 없습니다.

### 4-1. 병합 전: 저장소 설정

```bash
export GH_CONFIG_DIR="$HOME/.config/gh-yanghs6"
R=repos/yanghs6/basic-memory-tailnet
gh api -X PATCH "$R" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F allow_auto_merge=false -F delete_branch_on_merge=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
gh api -X PATCH "$R" -f 'security_and_analysis[secret_scanning][status]=enabled' -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
gh api -X PUT "$R/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
gh api -X PUT "$R/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors
unset GH_CONFIG_DIR
```

- secret scanning 명령이 실패하면(플랜이 지원하지 않음) 그 사실을 Progress log에 적습니다. 이때는 계정 단위 push protection(기본 켜짐)에 맡깁니다.
- 확인은 접근 권한이 있는 누구나 할 수 있습니다.

```bash
gh api repos/yanghs6/basic-memory-tailnet --jq '{squash_merge_commit_title, squash_merge_commit_message, delete_branch_on_merge, allow_merge_commit, allow_rebase_merge}'
```

Expected: `PR_TITLE`, `PR_BODY`, `true`, `false`, `false`

### 4-2. 병합 후: ruleset

```bash
cd <main 체크아웃>
git pull --ff-only
export GH_CONFIG_DIR="$HOME/.config/gh-yanghs6"
R=repos/yanghs6/basic-memory-tailnet
gh api "$R/commits/<병합 전 PR의 마지막 head SHA>/check-runs" --jq '.check_runs[] | "\(.name) \(.app.id) \(.app.slug)"'
gh api -X POST "$R/rulesets" --input .github/rulesets/main.json
unset GH_CONFIG_DIR
```

- ruleset 파일(`.github/rulesets/main.json`)은 병합한 뒤에야 main 체크아웃에 들어오므로 먼저 `git pull --ff-only`를 합니다.
- check-run 명령의 출력은 `check 15368 github-actions`, `pr-rules 15368 github-actions` 형태여야 합니다. 앱 ID가 15368이 아니면 `main.json`의 `integration_id`를 고치는 PR을 먼저 병합합니다.
- 확인은 로그인 없이 공개 API로 합니다.

```bash
curl -sS https://api.github.com/repos/yanghs6/basic-memory-tailnet/rules/branches/main | jq -r '.[].type'
```

Expected: `deletion`, `non_fast_forward`, `required_linear_history`, `pull_request`, `required_status_checks`

## 5. 토큰 교체

90일 만료 전에, 또는 유출이 의심되면 바로 합니다.

1. 머신 계정에서 새 classic 토큰을 만듭니다(범위와 만료는 1절과 같음).
2. `gh auth login`으로 다시 등록하고 `gh auth status`로 확인합니다.
3. 이전 토큰을 머신 계정 설정에서 삭제합니다.

## 6. 긴급 변경

ruleset의 우회 목록은 비어 있어서, 사용자도 `main`에 직접 push할 수 없습니다. 꼭 필요할 때만 다음 순서로 합니다.

1. Settings → Rules → Rulesets → `main` → Enforcement를 Disabled로 바꿉니다.
2. 필요한 변경을 합니다.
3. Enforcement를 Active로 되돌리고, 4절의 확인 명령으로 규칙 5개가 다시 보이는지 확인합니다.
4. 무엇을 왜 했는지 [운영 런북](operations.md)의 Incident log에 적습니다.
