# 13 Access Mode Migration Implementation Plan

> **For agentic workers:** This plan changes the VM and cloud resources. Run it in the main session with the user (superpowers:executing-plans), never in a subagent, and get the user's OK before each step marked "사용자 OK". The user runs every cloud command and every interactive SSH command in their own terminal. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 지금 VM(`agent-hub-01`)을 `tailscale` 모드에서 `ssh` 모드(IAP 터널)로 옮기고, 사무실과 다른 네트워크에서 Claude Code·Codex·웹 UI가 동작하는 것을 증거와 함께 확인한다. 스펙 §1 완료 조건 5와 §3의 Assumption을 해소한다.

**Architecture:**
- 계획 12가 만든 `BM_ACCESS=ssh`, `make access-check`, `make tunnel`과 런북의 "접속 방식 바꾸기 (Access mode change)" 순서를 실제 VM에 적용한다.
- IAP 경로를 먼저 열고 확인한 뒤에만 VM의 Tailscale을 로그아웃한다. 두 경로가 함께 열린 구간은 이 세션 안에서 끝낸다.
- 이 계획의 커밋은 기록뿐이다(Progress log, ADR 0006 "이전 결과", 스펙 §3, 운영 런북 점검 기록).

**Tech Stack:** 계획 12의 Make 타깃, OpenSSH + `gcloud compute start-iap-tunnel`(사용자의 `~/.ssh/config`), GCP 방화벽, Tailscale admin console, Claude Code·Codex CLI

**Spec:** `docs/specs/2026-10-15-access-modes-design.md` (특히 §1, §3, §9.5, §10.3, §14)

**Sequence:** 계획 13. 다음을 모두 만족한 뒤 시작한다.
- 계획 12가 `main`에 병합됐다.
- 사용자가 사무실 네트워크와 다른 네트워크(집 또는 핫스폿)를 같은 날 오갈 수 있다(Step 8).
- 시작할 때 이 Mac은 Tailscale이 되는 네트워크에 있다(Step 1~4는 기존 경로로 롤백할 수 있어야 한다).

## Global Constraints

- 사용자 OK 없이 하지 않는 일: 방화벽 규칙 추가·삭제, API 켜기, VM에서의 `sudo` 변경(`tailscale serve reset`, `tailscale logout`, sshd 설정), Tailscale admin console 변경, `make vm-bootstrap`·`deploy`·`restore`.
- OK가 필요 없는 일: `make access-check probe status logs verify backup tunnel`, 읽기 전용 `gcloud … list/describe`(`--configuration=bm-personal`).
- `gcloud`는 `--configuration=bm-personal`로만 실행한다. VM을 정지하지 않는다(외부 IP가 바뀜).
- 에이전트는 `.env`를 읽거나 고치지 않는다. 사용자가 고치고, 에이전트는 `make access-check` 출력으로 확인한다.
- 사용자의 `~/.ssh/config`는 사용자가 고친다. 에이전트는 넣을 블록을 보여 준다.
- 공인 IP, tailnet 이름·IP, 프로젝트 id를 커밋·PR·코멘트·문서에 쓰지 않는다. 기록할 때 `<공인 IP>`, `<tailnet>`, `<프로젝트>`로 가린다.
- 커밋 트레일러: `Assisted-by: <tool> <model>`, `Plan: 13`, `Task: <N|review|none>`. 금지 트레일러는 계획 12와 같다.
- PR: 초안 PR 하나. 제목 `docs: record the move of the VM to the ssh access mode`, 본문 마지막 문단은 `Assisted-by`와 `Plan: 13`.
- 결과는 Progress log와 ADR 0006 "이전 결과"에 `Verified` / `Command` / `Assumption` / `Open question`으로 기록한다.

## Review Focus

1. **IAP 경로를 확인하기 전에 Tailscale을 로그아웃함.** 두 경로가 모두 닫혀 직렬 콘솔이나 공인 SSH 규칙 없이는 들어갈 수 없다. → Step 5는 Step 3의 대화형 `ssh ubuntu@agent-hub-iap true`와 Step 4의 `make access-check`(`ssh ... ok`)가 성공한 뒤에만 진행한다.
2. **`.env`의 `BM_VM_HOST`가 아직 `agent-hub`인 채 `BM_ACCESS=ssh`로 바꿈.** 스크립트가 Tailscale 이름으로 SSH를 시도하고, 사무실에서 실패한다. → Step 4의 `make access-check`가 `ssh ubuntu@agent-hub-iap: ok`(별칭 이름 포함)를 출력해야 한다.
3. **클라이언트 한 대를 옛 tailnet URL로 남겨 둠.** 그 기기의 에이전트 세션에서 도구가 조용히 사라진다. → Step 7·8에서 기기마다 `claude mcp get basic-memory`의 URL과 도구 호출 결과를 기록한다.
4. **터널이 한 시간 무활동으로 끊긴 것을 모름.** 에이전트가 MCP 오류를 낸다. → Step 9의 70분 무활동 시험.
5. **이전 중 노트가 바뀜.** 롤백 지점이 낡는다. → Step 1의 `make backup`과 Step 6의 `make verify`(쓰기·읽기·삭제) 사이에는 에이전트가 노트를 쓰지 않는다. 사용자에게 이 구간에 다른 에이전트 세션을 쓰지 말라고 알린다.

## 실제 VM에서만 확인할 수 있는 항목

해당 Step에서 Progress log에 `Verified`(명령 포함)로 적는다. 확인하지 못하면 `Assumption`으로 남긴다.

1. IAP 터널에 `iap.googleapis.com`을 켜야 하는가. (Step 3)
2. `ConnectTimeout=10`이 IAP 터널을 여는 시간보다 길다. (Step 4, 6)
3. `tailscale status`가 로그인 상태에서 0, 로그아웃 상태에서 0이 아닌 값이다. (Step 4, 5)
4. Ubuntu 26.04 Minimal의 `sshd -T`가 `passwordauthentication no`, `kbdinteractiveauthentication no`를 출력한다. (Step 6)
5. `make backup`이 IAP 경로에서 걸리는 시간. (Step 6)
6. 사무실 네트워크에서 `make tunnel`과 도구 호출이 된다. (Step 8)
7. `ServerAliveInterval=30`이 IAP 한 시간 무활동 끊김을 막는다. (Step 9)

---

### 시작: 브랜치, worktree, 초안 PR (에이전트)

- [ ] `gh pr view <계획 12 PR 번호> --json state`가 `MERGED`다.
- [ ] `git fetch origin` 후 `origin/main`에서 worktree와 `plan/13-access-mode-migration` 브랜치를 만든다(git-workflow 스킬의 Start).
- [ ] 첫 커밋으로 이 계획 파일을 `active/`로 옮기고 push한 뒤 초안 PR을 연다.

```bash
git mv docs/plans/backlog/2026-10-15-13-access-mode-migration.md docs/plans/active/2026-10-15-13-access-mode-migration.md
git commit -m "docs: start plan 13 access mode migration" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: none"
git push -u origin plan/13-access-mode-migration
gh pr create --draft --base main --title "docs: record the move of the VM to the ssh access mode" --body-file "$TMPDIR/pr-13.md"
```

---

### Task 1: VM 이전 (사용자와 함께, 단계마다 OK)

**Files:**
- Modify: 이 계획 파일(Progress log), `docs/decisions/0006-access-modes.md`("이전 결과"), `docs/specs/2026-10-15-access-modes-design.md`(§3 Assumption, §14), `docs/runbooks/operations.md`(점검 기록 행, 확인된 사실로 고칠 문장), 필요하면 `docs/runbooks/gcp-vm.md`

**Interfaces:**
- Consumes: 계획 12의 `make access-check`·`make tunnel`·`ssh` 모드 `verify`·`status`, 런북의 "접속 방식 바꾸기 (Access mode change)"와 gcp-vm 8단계
- Produces: 스펙 §1 완료 조건 5의 증거, §3 Assumption의 판정

- [ ] **Step 1: 사전 점검과 롤백 지점 (OK 불필요)**

```bash
make status
grep 'image:' compose.yaml
time make backup
make access-check
```

Expected:
- `make status`의 이미지가 `compose.yaml`과 같다. 다르면 멈추고 사용자에게 묻는다.
- `make backup`이 `backup saved: <main>/backups/bm-<stamp>.tgz`로 끝난다. 경로와 걸린 시간(Tailscale 경로 기준값)을 Progress log에 적는다.
- `make access-check`가 이 네트워크의 두 경로를 보고한다(`BM_ACCESS`가 비어 있으면 0으로 끝난다).
- 사용자에게 Step 6까지 다른 에이전트 세션에서 노트를 쓰지 말라고 알린다(Review Focus 5).

- [ ] **Step 2: IAP 방화벽 규칙 (사용자 OK, 사용자가 실행)**

사용자가 [VM 런북](../../runbooks/gcp-vm.md) 8단계 1번 명령을 실행한다. 그다음 에이전트가 읽기 전용으로 확인한다.

```bash
gcloud compute firewall-rules list --configuration=bm-personal --format='table(name,direction,disabled,sourceRanges.list(),allowed[].map().firewall_rule().list())'
```

Expected: `default-allow-internal`(`10.128.0.0/9`)과 `allow-iap-ssh`(`35.235.240.0/20`, `tcp:22`) 두 행만 있다. 이 시점부터 Step 5까지 두 경로가 함께 열려 있다.

- [ ] **Step 3: SSH 별칭과 첫 접속 (사용자, 항목 1)**

에이전트가 gcp-vm 8단계 3번의 `Host agent-hub-iap` 블록을 보여 주고, 사용자가 `~/.ssh/config`에 넣는다. 사용자가 자기 터미널에서 실행한다.

```bash
ssh ubuntu@agent-hub-iap true
```

Expected: 호스트 키를 묻고, 수락하면 0으로 끝난다.
- API나 권한 오류로 실패하면 gcp-vm 8단계 5번(`gcloud services enable iap.googleapis.com --configuration=bm-personal`, 사용자 OK)을 실행하고 다시 시도한다. 켜야 했는지를 항목 1로 기록한다.
- 계속 실패하면 멈춘다. Step 2의 규칙을 지울지 사용자와 정한다(롤백). Tailscale 경로는 그대로다.

- [ ] **Step 4: `.env` 전환 (사용자, 항목 2·3)**

사용자가 main 체크아웃의 `.env`에서 `BM_ACCESS=ssh`, `BM_VM_HOST=agent-hub-iap`로 바꾸고 `BM_ACCESS_CHECK_URL`, `BM_TUNNEL_MCP_PORT`, `BM_TUNNEL_WEB_PORT`를 `.env.example`대로 넣는다. `BM_TAILNET_DOMAIN`은 남겨 둬도 된다(롤백용).

```bash
time make access-check
make status
```

Expected:
- `make access-check`가 `ssh ubuntu@agent-hub-iap: ok`를 출력하고 0으로 끝난다(Review Focus 2). 걸린 시간을 적는다(IAP 연결 시간이 `ConnectTimeout=10`보다 짧은지, 항목 2).
- `make status`가 `access: ssh`와 `WARNING: Tailscale is still logged in on the VM`을 출력한다. 로그인 상태에서 `tailscale status`가 0이라는 증거다(항목 3 앞부분).

- [ ] **Step 5: VM의 Tailscale 정리 (사용자 OK, 항목 3)**

Step 3과 Step 4가 모두 성공했을 때만 진행한다(Review Focus 1). 사용자가 자기 터미널에서 실행한다.

```bash
ssh ubuntu@agent-hub-iap 'sudo tailscale serve reset && sudo tailscale logout'
make status
```

Expected: `make status`가 `tailscale: not installed or logged out`을 출력한다(항목 3 뒷부분).

이어서 사용자가 Tailscale admin console에서 `agent-hub` 기기를 지운다. 정책의 `tag:agent-hub` 관련 항목은 남아도 해가 없다. 지울지는 사용자가 정한다.

패키지를 지울지 사용자에게 묻는다(스펙 §14의 3).
- A) 로그아웃만 한다(추천). 롤백할 때 새 인증 키로 `make vm-bootstrap`만 다시 하면 된다. `verify`는 로그아웃 상태를 통과로 본다.
- B) `sudo apt-get purge -y tailscale`로 지운다. 공격면이 조금 줄지만, 롤백하면 부트스트랩이 다시 설치한다.

결정을 Progress log에 적는다.

- [ ] **Step 6: 종단 검증과 백업 시간 (OK 불필요, 항목 2·4·5)**

```bash
make probe
make verify
make status
time make backup
```

Expected:
- `make verify`가 다음을 출력한다(공인 IP는 `<공인 IP>`로 가려 기록).
  - `verify tunnel is open`
  - `OK: MCP round trip passed`
  - `OK: SilverBullet checks passed for http://127.0.0.1:23000`
  - `OK: Tailscale does not expose the VM`
  - `OK: sshd accepts keys only`
  - `refuses ports 22 80 443 8443 8737 3000`
  - `OK: automated VM checks passed (access: ssh)`
- `OK: sshd accepts keys only`가 나오지 않으면 멈추고 gcp-vm 8단계 6번의 sshd 설정(사용자 OK)을 한 뒤 다시 실행한다. 실제 `sshd -T` 줄을 기록한다(항목 4).
- `make backup` 시간을 Step 1의 값과 비교해 적는다(항목 5). 두 배를 넘게 느리면 Follow-up으로 남긴다.

- [ ] **Step 7: 이 Mac의 클라이언트 전환 (사용자와 에이전트)**

사용자가 다른 터미널에서 `make tunnel`을 띄운다. 출력의 `MCP: http://127.0.0.1:18737/mcp  web UI: http://127.0.0.1:13000`을 확인한다.

```bash
claude mcp remove basic-memory -s user
claude mcp add --transport http -s user basic-memory http://127.0.0.1:18737/mcp
codex mcp remove basic-memory
codex mcp add basic-memory --url http://127.0.0.1:18737/mcp
claude mcp get basic-memory
```

Expected: `claude mcp get`이 `URL: http://127.0.0.1:18737/mcp`와 `Connected`를 보인다.

도구 호출로 확인한다(scratchpad 같은 빈 디렉터리에서 실행).

```bash
claude -p "Call the basic-memory MCP tool list_memory_projects once. Reply with only the project names it returns, comma-separated, or the exact error." --allowedTools "mcp__basic-memory__list_memory_projects" --model haiku
codex exec --skip-git-repo-check -s read-only "Call the basic-memory MCP tool list_memory_projects once. Reply with only the project names it returns, comma-separated, or the exact error."
```

Expected: 두 명령 모두 `main`을 출력한다. `codex exec`의 사용량을 기록한다.

사용자가 브라우저에서 `http://127.0.0.1:13000`을 열어 로그인하고 대시보드가 보이는지 확인한다.

- [ ] **Step 8: 사무실 네트워크와 다른 기기 (사용자와 에이전트, 항목 6)**

사용자가 이 Mac을 사무실 네트워크로 옮긴다. `make tunnel`이 끊겼으면 다시 띄운다.

```bash
make access-check
```

Expected:
- `tailscale control plane: blocked (...)`
- `tunnel endpoint https://tunnel.cloudproxy.app/: reachable (HTTP 404)`
- `ssh ubuntu@agent-hub-iap: ok`
- 0으로 끝난다.

Step 7의 두 도구 호출을 다시 하고 `main`을 확인한다. 웹 UI도 한 번 연다.

사용자가 쓰는 다른 기기가 있으면 그 기기에서 gcp-vm 8단계 3번(별칭)과 운영 런북 "에이전트 연결"을 따른다. 기기마다 `claude mcp get basic-memory`의 URL과 도구 호출 결과를 기록한다(Review Focus 3). 다른 기기가 없으면 "없음"이라고 적는다.

- [ ] **Step 9: 무활동 시험 (항목 7)**

`make tunnel`을 띄운 채 70분 동안 MCP를 쓰지 않는다. 그다음 Step 7의 `claude -p` 호출을 한 번 한다.

Expected: `main`이 나오고, `make tunnel` 터미널에 `tunnel closed`가 없다. 끊겼으면 시각과 메시지를 기록하고, Step 11에서 운영 런북 "에이전트 연결"에 "한 시간 넘게 쉬면 터널이 끊길 수 있으니 다시 실행"을 더한다.

- [ ] **Step 10: Exposure audit (사용자와 에이전트)**

```bash
gcloud compute firewall-rules list --configuration=bm-personal --format='table(name,direction,disabled,sourceRanges.list(),allowed[].map().firewall_rule().list())'
```

Expected: VPC 밖 소스는 `allow-iap-ssh`(`35.235.240.0/20`, `tcp:22`) 하나뿐이다. 사용자가 Tailscale admin console에서 `agent-hub` 기기가 없는지 확인한다.

운영 런북 "점검 기록" 표에 행을 더한다: 날짜, VPC 밖 규칙(`allow-iap-ssh` 하나), Funnel 항목은 "해당 없음(ssh 모드)", 자동 검사 결과(`make verify` 통과), 점검자.

- [ ] **Step 11: 기록**

- ADR 0006 "이전 결과"에 Step 1~9의 결과를 `Verified`(명령 포함)로 적는다: IAP API 필요 여부, 접속 시간, `tailscale status` 종료 코드, `sshd -T` 줄, 백업 시간 비교, 사무실 결과, 무활동 결과, 패키지 결정(A/B).
- 스펙 §3의 "Assumption (계획 13에서 확인)" 중 확인한 것을 `Verified (계획 13, <날짜>)`로 바꾸고, §14에서 풀린 질문을 표시한다.
- 확인된 사실이 런북 문장과 다르면 그 문장을 고친다(예: gcp-vm 8단계 5번의 IAP API 문장, Step 9의 끊김 안내).
- Progress log에 Step 1~10의 증거를 적는다.

- [ ] **Step 12: 커밋과 push**

```bash
make check
git add docs/plans/active/2026-10-15-13-access-mode-migration.md docs/decisions/0006-access-modes.md docs/specs/2026-10-15-access-modes-design.md docs/runbooks
git commit -m "docs: record the move of the VM to the ssh access mode" --trailer "Assisted-by: <tool> <model>" --trailer "Plan: 13" --trailer "Task: 1"
git push
```

**롤백 (사용자 OK 후):**
- **Step 5 전:**
  1. 사용자가 `.env`를 `BM_ACCESS=`(또는 `tailscale`), `BM_VM_HOST=agent-hub`로 되돌린다.
  2. 사용자가 `gcloud compute firewall-rules delete allow-iap-ssh --configuration=bm-personal`로 IAP 규칙을 지운다.
  3. `make probe`로 Tailscale 경로를 확인한다.
- **Step 5 뒤 IAP가 안 될 때:**
  1. bootstrap 런북 문제 해결의 "22번을 지운 뒤 접속 불가" 행대로 내 IP/32 규칙을 만든다.
  2. 사용자가 `.env`를 `BM_ACCESS=tailscale`, `BM_VM_HOST=agent-hub`로 되돌리고, 새 인증 키로 `make vm-bootstrap HOST=<공인 IP>`를 자기 터미널에서 실행한다.
  3. 임시 규칙을 지우고 `make verify`를 실행한다.
- **노트가 상했을 때:** Step 1의 백업으로 `make restore BACKUP=<그 파일>`을 실행한다. 사용자가 `yes`를 입력한다.

---

### 마무리: 리뷰, 넘기기 (git-workflow 스킬의 Review and merge)

- [ ] Progress log에 그날 `make check` 결과를 `Verified`로 적고, 계획 파일을 `docs/plans/completed/`로 옮겨 커밋·push한다(`Task: none`).
- [ ] 다른 벤더의 읽기 전용 리뷰는 사용자 승인 후 실행한다. 게시 전에 IP·tailnet 이름·프로젝트 id를 가린다.
- [ ] CI가 통과하고 열린 P0/P1이 없으면 `gh pr ready <PR>`을 실행하고 사용자에게 알린다. 승인과 squash 병합은 사람만 한다.
- [ ] 병합 뒤 worktree를 정리한다(`backups/`·`.env` 확인 먼저).

## Follow-ups (이 계획 밖)

- 이전한 다음 달 SKU별 청구에서 IAP 터널 트래픽과 송신량을 확인한다(운영 런북 "비용 점검", 스펙 §14의 2).
- Step 9에서 끊김이 잦으면 터널 자동 재연결(launchd 또는 autossh)을 새 작업으로 판단한다.
- 다른 사람에게 줄 최소 IAM 권한을 확인해 accounts 7단계에 적는다(스펙 §14의 4).
- Windows 확인(기기가 생기면).

## Progress log

| 날짜 | 표기 | 내용 |
|---|---|---|
