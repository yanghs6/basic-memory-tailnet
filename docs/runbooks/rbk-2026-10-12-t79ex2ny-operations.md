---
status: current
id: t79ex2ny
reviewed: 2026-10-27
---

# 운영

사람은 VM 대상 Make 타깃(`deploy`, `verify`, `backup`, `restore` 등)을 main 체크아웃에서 실행합니다. 에이전트는 자기 worktree에서 실행해도 되며, 그때도 `.env`와 `backups/`는 main 체크아웃의 것을 씁니다. 에이전트가 worktree에서 `deploy`·`restore`를 할 때는 먼저 `git diff main -- compose.yaml`이 아무것도 출력하지 않는지 확인합니다(bm-upgrade의 사용자 승인 배포는 예외. 아래 "배포·복원 전 이미지 점검"도 함께).

## 일상 명령

| 목적 | 명령 |
|---|---|
| 상태 점검 (주 1회) | `make status` |
| 지금 네트워크에서 되는 접속 경로 | `make access-check` |
| `ssh` 모드에서 MCP·웹 UI 터널 (작업하는 동안 띄워 둠) | `make tunnel` |
| 읽기 전용 검사 (노트를 쓰지 않음) | `make probe` |
| 종단 검증 (테스트 노트를 쓰고 지움) | `make verify` |
| 로그 | `make logs` |
| 로그를 JSON Lines로 내려받기 (장애 조사, 기본 최근 24시간) | `make export-logs [SINCE=6h]` → main 체크아웃의 `log-exports/`. 예: `jq -c 'select(.stream == "stderr")' log-exports/logs-*.jsonl` |
| 배포 (compose 변경 후) | `make deploy verify` |
| 웹 UI 글꼴 (새 VM이나 글꼴을 바꿀 때) | `make sb-fonts` |
| 백업 (주 1회 + 업그레이드 전) | `make backup` |
| 복원 | `make restore BACKUP=<백업 파일의 절대 경로>` (사용자가 자기 터미널에서 `yes` 입력. 저장소의 compose.yaml도 함께 적용하고, 실패하면 이전 상태로 자동 롤백, 끝나면 verify 실행. 끝난 뒤 각 Mac에서 `make memory-sync FULL=1`을 한 번 실행) |

에이전트는 `vm-bootstrap`, `deploy`, `restore`, `sb-fonts` 전에 사용자의 OK를 받습니다. `probe`, `status`, `logs`, `export-logs`, `verify`, `backup`, `access-check`, `tunnel`, `memory-sync`, `memory-index`는 OK 없이 실행할 수 있습니다(`verify`는 테스트 노트를 쓰고 지우며 SilverBullet에 로그인했다가 로그아웃하고, `backup`은 컨테이너를 잠깐 멈추고, `memory-sync`는 `agent-memory/` 노트만 쓰고 지웁니다). `export-logs`는 VM에서 읽기만 하지만, 내려받은 파일에 노트 식별자와 client 주소가 들어갈 수 있으므로 그 내용을 채팅·PR·저장소에 붙이지 않습니다. 개수와 형식 같은 요약만 남깁니다. `memory-hooks`는 사용자의 Claude Code·Codex hook 설정을 고치므로 OK를 받고 실행합니다.

**배포·복원 전 이미지 점검:** `make status`의 컨테이너 이미지와 `grep 'image:' compose.yaml`이 같은지 확인합니다. 다르면 멈추고 사용자에게 묻습니다. 업그레이드 리뷰 중에는 VM이 main이 고정하지 않은 이미지로 돌 수 있고, 이때 옛 이미지를 새 버전이 손댄 데이터 위에 배포하면 안 되기 때문입니다([bm-upgrade 스킬](../../.agents/skills/bm-upgrade/SKILL.md)). 새로 만든 VM처럼 아직 아무것도 배포하지 않았다면 `make status`가 `could not query containers`로 끝납니다. 정상이므로 이미지 비교는 건너뜁니다. 이때 에이전트는 `git diff main -- compose.yaml`이 아무것도 출력하지 않는지만 확인하고, 사람은 main 체크아웃에서 실행하는지 확인합니다.

## 백업

- 결과물은 main 체크아웃의 `backups/`에 저장됩니다(git ignore, worktree에서 실행해도 같음). Time Machine 등으로 Mac 밖에도 사본을 두세요.
- worktree를 지우기 전에 그 안에 `backups/`가 없는지 확인합니다. `git worktree remove`는 git ignore 파일을 경고 없이 지웁니다.
- 백업 중에는 컨테이너가 몇 초 멈춥니다. SQLite 파일이 쓰는 도중에 복사되지 않게 하기 위해서입니다.
- 백업마다 `.sha256`(아카이브 무결성)과 `.manifest`(데이터 파일별 체크섬)가 함께 저장됩니다. 둘 중 하나라도 없으면 `make restore`가 거부합니다.
- 임베딩 모델 캐시(`config/fastembed_cache/`)는 백업에 포함하지 않습니다. 다시 내려받을 수 있고 심볼릭 링크를 담고 있어 복원 검사가 거부하기 때문입니다. 복원 뒤 Basic Memory가 처음 쓸 때 모델을 다시 내려받으므로 첫 검색·인덱싱은 평소보다 오래 걸릴 수 있습니다.
- 복원은 임시 경로에 먼저 풀고 manifest와 대조한 뒤에만 교체합니다. 기존 데이터는 `/srv/basic-memory.prev-<시각>`으로 옮겨지고, 실패하면 자동으로 되돌아갑니다(실패한 복원본은 `.failed-<시각>`에 남음).
- `.prev-*`와 `.failed-*` 삭제는 **사람만** 합니다. 에이전트는 지우지 않습니다. 결과를 확인한 뒤 직접: `ssh ubuntu@agent-hub sudo rm -r /srv/basic-memory.prev-<시각>`

## 업그레이드·복구·진단

에이전트에게 스킬을 쓰라고 요청합니다.
- 업그레이드: `bm-upgrade`
- VM이 삭제됐거나 쓸 수 없을 때(정지만 된 VM은 아래 "정지된 VM"): `bm-recover`
- 연결·MCP 문제: `bm-diagnose` (읽기 전용)

## 웹 UI (SilverBullet)

- 주소는 `https://agent-hub.<tailnet>.ts.net:8443`이고 tailnet 안에서만 열립니다. main 체크아웃 `.env`의 `SB_USER`로 로그인합니다. 트리는 `Cmd-O`, 페이지 검색은 `Cmd-K`, 노트 본문 검색은 `Cmd-Shift-F`, 그래프는 명령 팔레트의 `Graph: Explore`입니다. 에이전트에게 노트를 알려 줄 때는 `Basic Memory: Copy memory:// Link`로 주소를 복사합니다.
- 노트 검색에 본문 문단이 안 나오면 그 브라우저에서 `Space: Reindex`를 한 번 실행합니다. 왼쪽에 트리가 안 보이면 `Cmd-O`를 누릅니다.
- 새 기기에서 처음 열 때 상단 막대가 빨갛거나(동기화 오류) 글꼴이 기본 글꼴로 보이면 몇 초 뒤 새로고침합니다. 첫 연결이 느려 클라이언트가 서버를 잠깐 오프라인으로 본 것입니다.
- **관찰 카테고리 경고:** `[fact]`·`[decision]` 같은 카테고리 글자를 누르면 SilverBullet이 카테고리를 지웁니다(`[]`가 되고 Basic Memory는 그 관찰을 `note`로 다시 색인). 실수했으면 바로 `Cmd+Z`로 되돌립니다.
- **비밀번호 교체:** main 체크아웃 `.env`의 `SB_USER`를 바꾸고 `make deploy`(사용자 OK)를 실행합니다. VM `.env`가 바뀌면 compose가 SilverBullet을 다시 만들고, 열린 브라우저는 다시 로그인해야 합니다.
- **글꼴:** 새 VM이거나 글꼴을 바꿀 때 `make sb-fonts`(사용자 OK). 복원하면 백업에 든 글꼴이 돌아오므로 다시 올릴 필요가 없습니다.
- **무시 목록:** 저장소의 `silverbullet/notes.gitignore`를 고치고 `make deploy`를 실행합니다. 배포가 Basic Memory를 다시 만들어 새 목록을 읽게 합니다(VM 콜드 스타트 161~192초). 이미 색인된 항목은 남습니다.
- **관리 페이지:** `Library/agent-hub/agent-hub.md`는 배포마다 덮어씁니다. 개인 설정은 `CONFIG` 페이지에 둡니다. 대시보드 `index`는 처음 한 번만 만들고 이후에는 건드리지 않습니다.

## 에이전트 연결

Claude Code와 Codex는 각 기기에서 `basic-memory`라는 이름으로 한 번 등록합니다. URL은 접속 방식에 따라 다릅니다.

| `BM_ACCESS` | URL | 미리 할 일 |
|---|---|---|
| `tailscale` | `https://agent-hub.<tailnet>.ts.net/mcp` | 이 기기가 tailnet에 연결돼 있어야 함 |
| `ssh` | `http://127.0.0.1:18737/mcp` | `make tunnel`을 띄워 둠 |

```bash
claude mcp add --transport http -s user basic-memory <URL>
codex mcp add basic-memory --url <URL>
```

- `ssh` 모드에서는 `localhost`가 아니라 `127.0.0.1`을 씁니다. 터널은 IPv4 `127.0.0.1`에만 열리는데, `localhost`가 IPv6 `::1`로 풀리면 연결이 거부됩니다.
- 웹 UI는 `tailscale` 모드에서 `https://agent-hub.<tailnet>.ts.net:8443`, `ssh` 모드에서 `http://127.0.0.1:13000`입니다.
- 확인: `claude mcp get basic-memory`가 `Connected`, Codex 세션의 `/mcp`에 `basic-memory`가 보입니다. VM에 닿지 않을 때 시작한 세션에는 도구가 없으므로 `/mcp`로 다시 연결하거나 새로 시작합니다.
- **Assumption ([VM 런북](rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 8단계의 Windows 설정):** Windows: PowerShell에서 `make tunnel`이 출력하는 `ssh -N ...` 명령을 그대로 실행하고 같은 URL을 등록합니다.

### 기억 미러 (memory mirror)

Claude Code·Codex의 기억 파일을 Basic Memory의 `agent-memory/`로 미러하고, 새 세션에 다른 Mac·에이전트의 기억 색인을 넣습니다([스펙](../specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md)). 각 Mac에서 한 번 설정합니다.

1. 메인 체크아웃 `.env`에 `BM_MEMORY_DEVICE`(`^[a-z0-9-]+$`, 예: `mac-work`)를 넣습니다(사용자). Mac마다 다른 값을 씁니다. 다른 Mac의 `.env`를 복사했다면 이 값을 바꿉니다. 같은 값이면 두 Mac이 서로의 노트를 덮어쓰고, `FULL=1`은 상대 Mac의 노트를 지웁니다. 노트로 보내지 않을 프로젝트가 있으면 `BM_MEMORY_EXCLUDE`(쉼표로 구분한 프로젝트 키)도 넣습니다.
2. `make tunnel`을 띄웁니다(`ssh` 모드).
3. `make memory-sync`로 처음 올립니다. 한 번에 5개까지만 보내므로 `wait for the next memory-sync` 줄이 더 나오지 않을 때까지 다시 실행합니다(1 GB VM이므로 실행 사이에 `make status`로 상태를 봅니다). 그 실행들의 `wrote` 합이 원본 파일 수와 같아야 하고, 한 번 더 실행하면 아무것도 보내지 않습니다.
4. 사용자 OK를 받고 `make memory-hooks`를 실행합니다. SessionStart·Stop에 동기화를, SessionStart에 색인을 더합니다.
5. Codex에서 `/hooks`로 새 hook을 신뢰합니다.

- 첫 동기화 속도: 한 번에 노트 5개까지만 보내므로(쓰기 사이 3초 대기, 쓰기 하나는 90초까지 기다림), Mac에서 처음 올릴 때와 `FULL=1` 뒤에는 여러 번 실행해야 끝납니다. `... wait for the next memory-sync` 줄이 더 나오지 않을 때까지 `make memory-sync`를 다시 실행하거나 hook이 마저 올리게 둡니다. 1 GB VM이므로 실행 사이에 `make status`로 VM 상태를 봅니다. 응답 없이 연속 2번 실패하면 그 실행은 멈추고 1로 끝납니다(스펙 §3.3).
- 확인: 새 세션을 열면 컨텍스트에 `Basic Memory index:`가 들어옵니다. 다른 Mac이나 다른 에이전트의 기억이 아직 없으면 아무것도 들어오지 않습니다. 지난 결정을 물으면 에이전트가 `read_note`나 `search_notes`를 부릅니다.
- 에이전트 조회 규칙과 "새 기억은 영어로"는 사용자 전역 지침(`~/.agents/AGENTS.md`)에 있습니다(스펙 §3.8).
- 로그: `~/.local/state/bm-agent-memory/sync.log`
- 해제: `make memory-hooks REMOVE=1`
- Codex는 hook을 파일 안의 위치와 명령으로 신뢰합니다. 설치나 해제 뒤에는 Codex `/hooks`를 다시 열어, 위치가 바뀐 다른 hook이 신뢰를 잃지 않았는지 봅니다.
- 제외: `BM_MEMORY_EXCLUDE`에 키를 적으면 다음 동기화가 그 노트를 지웁니다. Codex 기억은 모두 `_global`이라 프로젝트 키로는 빠지지 않습니다. Codex 기억까지 빼려면 `_global`을 적어야 하고, 그러면 모든 Codex 기억과 홈 폴더 Claude 기억이 빠집니다(스펙 §4.2).
- 복원과 재구축 뒤: `make restore`나 VM 재구축 뒤에는 각 Mac에서 `make memory-sync FULL=1`을 한 번 실행합니다. 로컬 상태 파일이 VM의 옛 노트를 알아채지 못하기 때문입니다(스펙 §3.3).
- `CLAUDE_CONFIG_DIR`나 `CODEX_HOME`을 쓴다면 두 에이전트에 같은 값을 주거나, 둘 다 두지 않습니다. 한 에이전트에만 있으면 두 에이전트의 hook이 서로 다른 원본 폴더를 보고, 턴마다 서로의 노트를 지우고 다시 씁니다.
- **Verified (2026-10-26):** 시험 노트를 쓰고 검색한 뒤 `make logs | grep -c 'plan24 marker'`가 0이어서, 컨테이너 로그에 시험 노트 본문은 없었습니다. 이때 검색어(`경로`, `경로 <시각>`)는 grep하지 않았습니다. VM의 Basic Memory 앱 로그 파일은 읽는 Make 타깃이 없어 읽지 않았습니다.
- **Reported (Basic Memory 0.23.2 소스):** 검색어는 DEBUG 수준에서만 기록되고 VM은 INFO로 돕니다. [agent-memory-mirror 계획](../plans/plan-2026-10-22-mk823xbp-agent-memory-mirror.md) Task 6 Step 7에서 고유한 검색어로 `search_notes`를 한 번 부른 뒤 `make logs`에서 그 검색어를 grep해 다시 확인합니다.

## 접속 방식 바꾸기 (Access mode change)

`tailscale` → `ssh` 순서입니다. 2·5단계는 VM·클라우드를 바꾸므로 사용자 OK 후 진행합니다.

1. `make backup` (롤백 지점)
2. [VM 런북](rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 8단계 1번의 `allow-iap-ssh` 규칙
3. `~/.ssh/config`에 별칭을 넣고 대화형 `ssh ubuntu@agent-hub-iap true`. 실패하면 멈추고 2단계 규칙을 지웁니다(Tailscale 경로는 그대로).
4. `.env`: `BM_ACCESS=ssh`, `BM_VM_HOST=agent-hub-iap`. [access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md) 이전의 `.env`면 `.env.example`의 `BM_ACCESS_CHECK_URL`, `BM_TUNNEL_MCP_PORT`, `BM_TUNNEL_WEB_PORT`도 추가합니다. `make access-check`는 `ok`, `make status`는 Tailscale 로그인 경고(예상)를 냅니다.
5. `ssh ubuntu@agent-hub-iap 'sudo tailscale serve reset && sudo tailscale logout'`, Tailscale admin console에서 VM 기기 삭제
   - 로그아웃(또는 패키지 제거)까지 합니다. tailscaled 데몬만 멈추면 `verify`가 상태를 읽지 못해 실패합니다.
6. `make probe verify status`
7. 기기마다 `claude mcp remove basic-memory -s user`, `codex mcp remove basic-memory` 후 "에이전트 연결"대로 터널 URL로 다시 등록
8. Exposure audit을 하고 점검 기록과 Incident log에 남깁니다.

롤백: 5단계 전이면 `.env`를 되돌리고 `allow-iap-ssh`를 지웁니다. 5단계 뒤 IAP가 안 되면 [부트스트랩 런북](rbk-2026-10-12-ha5w72pm-bootstrap.md) 문제 해결의 "22번을 지운 뒤 접속 불가" 행대로 내 IP/32 규칙을 만들고, `BM_ACCESS=tailscale`과 새 인증 키로 `make vm-bootstrap HOST=<공인 IP>`를 실행합니다.

## 정지된 VM

VM이 정지돼 있으면(`TERMINATED`) 다시 만들지 않고 시작합니다. 디스크의 데이터가 그대로 있어서, 재구축하면 마지막 백업 이후의 노트를 잃습니다.

1. 사용자가 상태를 확인하고 시작합니다. 새 셸이면 먼저 [rbk-2026-10-12-tcjs7m6x-gcp-vm.md](rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 0단계의 `INSTANCE`, `ZONE`을 설정합니다.

   ```bash
   gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --configuration=bm-personal --format='value(status)'
   gcloud compute instances start "$INSTANCE" --zone="$ZONE" --configuration=bm-personal
   ```

2. 정지 후 시작하면 외부 IP가 바뀝니다([rbk-2026-10-12-tcjs7m6x-gcp-vm.md](rbk-2026-10-12-tcjs7m6x-gcp-vm.md) 5단계의 조회 명령). 새 IP를 `.env`의 `BM_VM_PUBLIC_IP`에 적습니다.
3. `make status`와 `make probe`로 확인합니다. 실제 장애였다면 Incident log에 행을 추가합니다.

## VM 재구축 순서

VM이 삭제됐거나 시작되지 않거나 데이터가 손상됐을 때만 합니다(에이전트의 `bm-recover` 스킬이 같은 순서를 따릅니다).

1. 최신 백업(`.sha256`과 `.manifest` 포함)이 main 체크아웃의 `backups/`에 있는지 확인합니다.
2. [rbk-2026-10-12-tcjs7m6x-gcp-vm.md](rbk-2026-10-12-tcjs7m6x-gcp-vm.md)대로 VM을 다시 만들고 방화벽을 정리합니다. 옛 인스턴스와 디스크는 복원이 검증되기 전에는 지우지 않습니다. `ssh` 모드면 `~/.ssh/config` 별칭의 `HostName`을 새 인스턴스 이름으로 바꾼 뒤, 3단계 대신 [rbk-2026-10-12-ha5w72pm-bootstrap.md](rbk-2026-10-12-ha5w72pm-bootstrap.md)의 "ssh 모드 순서"를 따릅니다.
3. [rbk-2026-10-12-ha5w72pm-bootstrap.md](rbk-2026-10-12-ha5w72pm-bootstrap.md) 1단계(옛 `agent-hub` 기기 삭제, 호스트 키 정리)와 2~4단계(부트스트랩, Tailscale SSH 확인, `default-allow-ssh` 삭제)를 합니다.
4. 배포 전에 `make status`의 이미지와 `compose.yaml`의 `image:`를 비교합니다(위의 이미지 점검). 아직 아무것도 배포하지 않은 VM에서는 `make status`가 `could not query containers`로 끝나는 것이 정상이며 비교는 건너뜁니다(에이전트는 `git diff main -- compose.yaml`이 비어 있는지만 확인). 그다음 `make deploy`, `make restore BACKUP=<절대 경로>`를 합니다.
5. Exposure audit을 다시 합니다(방화벽을 새로 만들었으므로).
6. 각 Mac에서 `make memory-sync FULL=1`을 한 번 실행합니다(위의 "기억 미러").
7. Incident log와 점검 기록에 행을 추가합니다.

## Exposure audit

`make verify`/`make probe`는 VM 쪽에서 확인할 수 있는 것만 자동으로 검사합니다: 8737·3000의 `127.0.0.1` 바인딩, Serve가 tailnet 전용이고 443→Basic Memory·8443→SilverBullet인지(두 포트 모두 Funnel off), 공인 IP의 22·80·443·8443·8737·3000 차단. 나머지 두 가지는 VM에서 읽을 수 없으므로, 배포 직후와 방화벽·정책을 바꾼 뒤(VM 재구축 포함)에 손으로 점검하고 결과를 Incident log 아래 "점검 기록"에 남깁니다. `ssh` 모드에서는 Serve 검사 대신 VM의 Tailscale이 로그인 상태가 아닌지와 sshd가 키 전용인지 검사합니다.

1. 방화벽 규칙 중 **VPC 밖의 소스를 허용하는 인바운드 규칙**을 확인합니다. `tailscale` 모드는 0개(`default-allow-internal`의 `10.128.0.0/9`만), `ssh` 모드는 `allow-iap-ssh`(`35.235.240.0/20`, `tcp:22`) 하나만 있어야 합니다.

   ```bash
   gcloud compute firewall-rules list --configuration=bm-personal --format='table(name,direction,disabled,sourceRanges.list(),allowed[].map().firewall_rule().list())'
   ```

   `direction`이 `INGRESS`, `disabled`가 `False`이면서 소스가 `10.128.0.0/9`가 아닌 행이 없어야 합니다(`ssh` 모드는 예외로 `allow-iap-ssh` 행(`35.235.240.0/20`, `tcp:22`) 하나가 있습니다. `default-allow-ssh`는 부트스트랩이 끝나면 지워져 있어야 함).
   - **Assumption:** 기본 `default` 네트워크 하나만 쓰는 프로젝트입니다.
2. Tailscale admin console → Access controls의 정책 `nodeAttrs`에 **`"funnel"`이 없는지** 확인합니다(`tailscale` 모드만).
3. `BM_WEB=on`이면 웹 커넥터 쪽도 점검합니다([web-connector 런북](rbk-2026-10-27-x9h4zzdh-web-connector.md)):
   - Cloudflare Zero Trust의 tunnel에 **공개 호스트명이 하나뿐**이고 서비스가 `http://gateway:8080`인지.
   - GitHub OAuth App이 하나이고 콜백이 `https://<BM_WEB_HOST>/auth/callback` 하나인지.
   - claude.ai의 커넥터 목록에 이 커넥터만 있고 쓰기 도구에 "Always allow"가 없는지.
   - `make status`의 `gateway store: <N> KiB, <M> client registrations`를 점검 기록에 남기고, 지난번보다 이상하게 늘었으면 런북의 "게이트웨이 저장소 비우기"를 검토합니다.

스크립트가 `Funnel is on for this node`라고 하면 먼저 정책의 `funnel` 속성을 지워 Funnel을 끄고, VM의 Serve 상태를 확인합니다(`ssh ubuntu@agent-hub sudo tailscale serve status`). 그다음 Serve를 다시 설정합니다.

**Verified (2026-10-13, [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Step 14):** 부트스트랩 뒤에는 22번이 닫혀 있으므로 `make vm-bootstrap HOST=agent-hub`를 Tailscale SSH로 실행해 Serve를 다시 설정합니다. 노드가 이미 tailnet에 있으면 키 프롬프트에 아무것도 넣지 않고 Enter만 누릅니다. 이 명령은 VM을 바꾸므로 사용자의 OK가 필요합니다.

**Verified (2026-10-13, Tailscale v1.104.1 소스 `cmd/tailscale/cli/serve_v2.go`의 `applyFunnel`):** 또한 `serve --bg`는 자기가 설정하는 포트(443)의 Funnel만 끄고(`Removing Funnel for ...` 출력) 다른 포트의 Funnel은 그대로 둡니다. 그래서 `tailscale funnel status`에 443 말고 다른 포트의 Funnel이 남아 있으면 `ssh ubuntu@agent-hub sudo tailscale serve reset`을 사용자 OK 후에 실행하고, Serve를 다시 설정합니다. `serve reset`은 443과 8443 설정을 모두 지우므로, 그 뒤 `make vm-bootstrap HOST=agent-hub`로 두 포트를 다시 설정합니다.

## 비용 점검

GCP 무료 등급에서 과금이 생기지 않는지 확인합니다.

**Open question:** 외부 IPv4 요금($0.005/h, 약 $3.65/월)이 무료 등급에 포함되는지는 아직 확인하지 못했습니다.

- 배포 **다음 날**과 **매월 초**에 청구 보고서를 SKU별로 봅니다: Cloud Console → Billing → Reports에서 프로젝트로 필터링하고 Group by를 SKU로 둡니다.
  - **Assumption:** 메뉴 이름은 바뀔 수 있고, 보고서에는 하루쯤 지연이 있음.
- e2-micro 인스턴스, standard persistent disk, 외부 IP, 네트워크(아웃바운드) SKU의 금액이 모두 0이어야 합니다. Budget 알림(월 $1)이 오면 같은 보고서를 확인합니다.
- 0이 아니면 사용자가 "그 금액을 감수"와 "다른 호스트" 중에서 결정합니다. 결과는 [basic-memory-on-gcp-tailscale ADR](../decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md)에 Verified로 남깁니다.
- 무료 아웃바운드는 월 1GB(북미 → 전 세계, 중국·호주 제외)입니다. Tailscale DERP 중계 트래픽도 포함되므로 같은 보고서로 확인합니다.

**Open question:** `ssh` 모드에서는 IAP 터널 트래픽이 무료 송신 한도(월 1GB)에 들어가는지 아직 확인하지 못했습니다. 이전한 다음 달 SKU별 청구에서 확인합니다.

## Incident log

장애는 실제 VM에서 서비스, 접속 경로, 복구 경로를 해친 계획에 없던 사건이며, 실패한 검증·시험도 포함합니다. 원인을 확인하지 못했으면 원인 칸을 `Assumption:`으로 시작합니다. 후속 조치 칸에는 커밋·PR·계획을 적고, 없으면 `없음`과 이유를 적습니다.

| 날짜 | 원인 | 사용한 백업 | 데이터 손실 구간 | 비고 | 후속 조치 |
|---|---|---|---|---|---|
| 2026-10-13 | 콜드 스타트가 약 192초 걸려 healthcheck(`start_period: 60s`)가 `unhealthy`가 됨. `docker compose up --wait`가 즉시 실패하므로 그때의 `make deploy`·`make restore`가 실패할 수 있었음 | 사용 안 함 | 없음 | 재부팅 자체는 `restart: unless-stopped`로 결국 healthy. 출처: [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Progress log `:289`, `:291-292` | `56d3ab4`(`start_period: 300s`, `HEALTH_TIMEOUT_SECONDS` 360초), `tests/repo-config.bats:63`. 늘어나는 콜드 스타트(161 → 192 → 248초)는 [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Follow-ups `:259`에 남아 있다 |
| 2026-10-13 | 모델 캐시가 생긴 뒤 만든 백업이 모두 복원 거부됨: 모델 캐시(`config/fastembed_cache`)의 상대 심볼릭 링크가 백업 tar에 들어가 restore 안전 검사가 아카이브를 거부함 | `bm-20261013T050026Z.tgz`(거부됨) | 없음(VM에 손대기 전에 거부) | 같은 날 2회차 복원(`bm-20261013T054955Z.tgz`)이 통과. 출처: [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Progress log `:309-311` | `a5781a4`(모델 캐시를 백업과 manifest에서 제외), `tests/restore-notes.bats:48` |
| 2026-10-13 | 접속 경로: 사무실 네트워크가 HTTPS `controlplane.tailscale.com`만 막아 이 Mac이 tailnet에 들어가지 못함 | 사용 안 함 | 없음 | 다른 네트워크에서는 접속됨. 출처: [vm-rollout 계획](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) Progress log `:285-287` | 사용자가 IT에 허용을 요청했고, [access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md)에서 VM을 `ssh` 모드로 옮겼다(코드 PR #8, 결과 기록 `ef67732` PR #12) |
| 2026-10-15 | 장애 아님: 접속 방식을 `tailscale`에서 `ssh`로 바꿈([access-modes 계획](../plans/plan-2026-10-15-ctv444ep-access-modes.md) Task 8) | 사용 안 함(롤백 지점 `bm-20261015T090644Z.tgz`) | 없음 | VM의 Tailscale은 로그아웃만 함(패키지 유지), admin console의 `agent-hub` 기기 삭제. 2026-10-16 `make verify` 통과 | 해당 없음(장애 아님) |
| 2026-10-21 | Assumption: 배포 직후 Basic Memory의 재색인으로 1GB VM의 응답이 30초를 넘김. 배포 직후 첫 `make verify`가 `tools/list`에서 `curl: (28)`로 끝남 | 사용 안 함 | 없음 | 2분 뒤 `make probe`·`make verify` 통과. 출처: [script-cleanup 계획](../plans/plan-2026-10-20-c2vxa7kp-script-cleanup.md) Progress log `:498-500` | [recovery-drill 계획](../plans/plan-2026-10-22-zw0shxee-recovery-drill.md) Task 2(`bm-diagnose` 실패 메시지 목록의 `curl: (28)` 행). 원인 확인은 그 계획의 Follow-ups에 남긴다 |
| 2026-10-26 | 장애 아님: 사용자가 Ruleset `main`의 Enforcement를 껐다가 다시 켬. [doc-ids 계획](../plans/plan-2026-10-26-e3svnr3h-doc-ids.md) Task 4의 일회성 이력 재작성 | 사용 안 함(재작성 전 `main` a1d77be의 mirror 백업 사본을 저장소 밖에 둠) | 없음 | `git push --force-with-lease`로 `main`을 829e77a로 바꾼 뒤 Enforcement를 다시 켰다. 공개 규칙 API에 규칙 5개(deletion, non_fast_forward, required_linear_history, pull_request, required_status_checks)가 보인다. [GitHub 런북](rbk-2026-10-14-ppmby9v6-github.md) 6절 4단계의 기록이다 | 해당 없음(장애 아님) |
| 2026-10-27 | Assumption: 0.24.1 첫 기동의 DB 마이그레이션과 재색인으로 1GB VM이 느려짐. 시험 배포 직후 `make verify`가 세 번 실패함(05:16Z ssh banner 시간 초과, 05:18Z 검증 터널 열리지 않음, 05:19Z `write_note`의 `curl: (28)`) | 사용 안 함 | 없음 | 컨테이너는 내내 healthy였고 메모리 64%, 스왑 487/1023MB. `make probe` 통과 뒤 05:22Z `make verify` 통과. 출처: [recovery-drill 계획](../plans/plan-2026-10-22-zw0shxee-recovery-drill.md) Progress log | 원인 확인과, 업그레이드 직후 verify를 몇 분 미룰지는 [recovery-drill 계획](../plans/plan-2026-10-22-zw0shxee-recovery-drill.md) Follow-ups에 남김 |
| 2026-10-27 | 장애 아님: 롤백 시험([recovery-drill 계획](../plans/plan-2026-10-22-zw0shxee-recovery-drill.md) Task 4). 0.24.1로 배포한 뒤 옛 `image:` 줄과 `make restore`로 0.23.2와 백업 시점 데이터로 되돌림 | `bm-20261027T050239Z.tgz` | 05:02:39Z(백업)부터 약 05:27Z(복원)까지. 그 사이 쓴 노트는 VM의 `/srv/basic-memory.prev-*`(이번 복원분)에만 남음 | 사용자가 시험 창 동안 노트 쓰기를 멈춤. 표시 노트 `verify/rollback-drill`이 복원 뒤 사라진 것을 확인 | `/srv/basic-memory.prev-*` 삭제는 사람이 정함 |
| 2026-10-28 | Assumption: 첫 기억 미러 동기화(`make memory-sync`, Claude 기억 62개, 컨테이너 재시작 직후 01:27Z)가 `write_note`를 쉬지 않고 연달아 보내, 1GB VM에서 색인·임베딩이 밀리고 swap thrashing이 일어남. `write_note`가 30초 시간 초과로 19번 넘게 실패했고, 01:39Z에 동기화를 멈춘 뒤에도 MCP initialize가 30분 넘게 응답하지 않음(`make probe` 2회 연속 실패) | 사용 안 함. 재시작에 `make backup`을 씀(`bm-20261028T022222Z.tgz`가 함께 생김) | 없음. 응답을 못 받은 쓰기 가운데 23개는 서버에 쓰였고, 다음 동기화가 덮어씀 | 컨테이너는 내내 healthy였음(healthcheck는 TCP 연결만 봄). 01:55Z vmstat에서 si 약 1MB/s, wa 45~52%, Basic Memory RSS 59MiB. 02:14Z에는 swap 입출력이 멈추고 CPU가 한가했지만 여전히 응답 없음. 02:24Z 재시작 뒤 swap 89MB, 02:28Z `make probe` 통과. serial port 출력에 OOM 없음 | PR #33(쓰기 속도 조절: 실행마다 10개, 쓰기 사이 3초, 응답 없는 요청이 2번 연속이면 멈춤). 그때까지 [agent-memory-mirror 계획](../plans/plan-2026-10-22-mk823xbp-agent-memory-mirror.md) Task 6의 동기화와 hook 설치를 보류 |

### 점검 기록 (Exposure audit)

| 날짜 | VPC 밖 소스를 허용하는 인바운드 규칙 수 | 정책 funnel 속성 | `make verify` | 점검자 |
|---|---|---|---|---|
| 2026-10-13 | 0 (`default-allow-ssh` 삭제 후 `default-allow-internal` `10.128.0.0/9`만 남음) | 없음: 2026-10-12에 사용자가 붙여 준 정책 JSON의 `nodeAttrs`에 없음, 2026-10-13 VM 노드 `CapMap`에 funnel 권한 없음 | 통과 (MCP 왕복, 127.0.0.1 바인딩, Serve tailnet only, 22·80·443·8737 차단) | claude-code, 사용자 |
| 2026-10-16 | 1 (`allow-iap-ssh` `35.235.240.0/20` `tcp:22`, 그 밖에는 `default-allow-internal` `10.128.0.0/9`만) | 해당 없음(`ssh` 모드). Tailscale admin console에 `agent-hub` 기기 없음(사용자 확인) | 통과 (`access: ssh`: MCP 왕복, SilverBullet, 8737·3000 loopback, Tailscale 노출 없음, sshd 키 전용, 공인 IP 22·80·443·8443·8737·3000 차단) | claude-code, 사용자 |
