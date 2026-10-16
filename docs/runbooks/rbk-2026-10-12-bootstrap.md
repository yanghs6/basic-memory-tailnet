# 부트스트랩: VM을 tailnet에 올리고 배포하기

`make vm-bootstrap`, `make deploy`, `make restore`는 VM을 바꾸므로 에이전트는 사용자의 OK를 받은 뒤에만 실행합니다. 인증 키 프롬프트처럼 터미널 입력이 필요한 명령은 사용자가 자기 터미널에서 직접 실행합니다.

접속 방식(`.env`의 `BM_ACCESS`)을 먼저 정합니다. 클라이언트가 쓸 네트워크(사무실, 집 등)마다 `make access-check`를 실행하고, 어느 한 곳이라도 Tailscale이 막히고 터널 엔드포인트가 열리면 `ssh`, 모두 Tailscale이 되면 `tailscale`(비워 두어도 같음)을 고릅니다. 기존 설치의 `.env`에는 `.env.example`의 `BM_ACCESS_CHECK_URL`, `BM_TUNNEL_MCP_PORT`, `BM_TUNNEL_WEB_PORT`를 추가해야 합니다(없으면 `access-check`가 터널을 "미확인"으로 보고합니다). 아래 "순서"와 "완료 조건"은 `tailscale` 모드이고, `ssh` 모드는 "ssh 모드 순서"를 따릅니다.

## 준비

- `.env`는 main 체크아웃에 있습니다([accounts 3단계](rbk-2026-10-12-accounts.md)). `BM_TAILNET_DOMAIN`(`tailscale` 모드만)과 `BM_VM_PUBLIC_IP`가 채워져 있는지 사용자가 확인합니다(에이전트는 읽을 수 없음). 없으면 main 체크아웃에서 `cp .env.example .env` 후 채웁니다.
- 사람은 VM 대상 Make 타깃을 main 체크아웃에서 실행합니다. 에이전트는 자기 worktree에서 실행해도 되며, 그때도 `.env`와 `backups/`는 main 체크아웃의 것을 씁니다. 에이전트가 worktree에서 `deploy`·`restore`를 할 때는 먼저 `git diff main -- compose.yaml`이 아무것도 출력하지 않는지 확인합니다(bm-upgrade의 사용자 승인 배포는 예외).
- `tailscale` 모드만: [accounts 런북 5단계](rbk-2026-10-12-accounts.md)대로 1회용 인증 키를 **지금** 발급합니다(만료 1일).

## 순서

1. VM을 다시 만드는 경우(재구축)에만 먼저:
   - Tailscale admin console에서 옛 `agent-hub` 기기를 삭제합니다. 남아 있으면 새 노드가 `agent-hub-1` 같은 다른 이름으로 들어옵니다.
   - 옛 호스트 키를 지웁니다: `ssh-keygen -R agent-hub`
   - 새 VM의 공인 IP가 옛 IP와 같을 수 있으므로 `ssh-keygen -R <새 공인 IP>`도 실행합니다(항목이 없어도 무해합니다). 남아 있으면 `make vm-bootstrap`이 `upload failed`로 끝납니다.
2. `make vm-bootstrap HOST=<공인 IP>` → 숨김 프롬프트에 인증 키를 붙여 넣습니다(화면에 표시되지 않음).
   - 인증 키를 명령줄에 쓰지 마세요(`make vm-bootstrap TS_AUTHKEY=...` 금지: 셸 기록과 프로세스 목록에 남습니다). 프롬프트를 쓰거나, 먼저 `read -rs TS_AUTHKEY && export TS_AUTHKEY`를 실행합니다. 이 경우 끝나면 같은 셸에서 `unset TS_AUTHKEY`를 실행합니다(그 셸에서 나중에 띄운 도구가 키를 물려받지 않게).
   - 스왑 파일 1GB(`/swapfile`)를 **가장 먼저** 만들고(Docker 설치 전), Docker·Tailscale 설치, tailnet 참여(`agent-hub`, Tailscale SSH), 데이터 디렉터리 생성, Serve 설정까지 합니다.
   - 여러 번 실행해도 안전합니다. 이미 tailnet에 있으면 키 없이 빈 입력으로 다시 실행할 수 있고, 스왑이 이미 있으면 건너뜁니다.
3. `ssh ubuntu@agent-hub true` → **대화형으로 처음 한 번** 실행해 새 호스트 키를 수락하고, Tailscale SSH로 접속되는지 확인합니다.
4. **3단계가 성공한 뒤에만** 22번을 여는 방화벽 규칙을 지웁니다.

   ```bash
   gcloud compute firewall-rules delete default-allow-ssh --configuration=bm-personal
   ```

   이제 VPC 밖 소스를 허용하는 인바운드 규칙이 없습니다(`default-allow-internal`의 `10.128.0.0/9`만 남음).
5. `make deploy sb-fonts verify status`

## ssh 모드 순서

1. [VM 런북](rbk-2026-10-12-gcp-vm.md) 3단계와 8단계: `default-allow-ssh`를 지우고 `allow-iap-ssh`를 만들고, `~/.ssh/config`에 `agent-hub-iap`를 넣고(VM을 다시 만들어 인스턴스 이름이 바뀌었으면 별칭의 `HostName`도 새 이름으로 바꿉니다), 대화형 `ssh ubuntu@agent-hub-iap true`로 호스트 키를 수락합니다.
2. `.env`: `BM_ACCESS=ssh`, `BM_VM_HOST=agent-hub-iap`. `BM_TAILNET_DOMAIN`은 필요 없습니다. `make access-check`가 `ssh ubuntu@agent-hub-iap: ok`를 출력해야 합니다.
3. `make vm-bootstrap HOST=agent-hub-iap` → 인증 키를 묻지 않고 스왑·Docker·데이터 디렉터리만 준비합니다(`access mode ssh: skipping Tailscale`).
4. `make deploy sb-fonts verify status`
5. 다른 터미널에서 `make tunnel`을 띄우고 [운영 런북](rbk-2026-10-12-operations.md)의 "에이전트 연결"대로 클라이언트를 등록합니다.

완료 조건(ssh 모드):

- [ ] `make verify`가 `OK: MCP round trip passed`, `OK: SilverBullet checks passed`, `OK: Tailscale does not expose the VM`, `OK: sshd accepts keys only`, `refuses ports 22 80 443 8443 8737 3000`, `(access: ssh)`를 출력한다.
- [ ] Exposure audit(수동)에서 VPC 밖 소스를 허용하는 규칙이 `allow-iap-ssh` 하나뿐이다.
- [ ] `make status`에 두 컨테이너의 `(healthy)`와 `access: ssh`, `tailscale: not installed or logged out`이 보인다.
- [ ] `make backup`이 성공한다.

## 완료 조건

- [ ] `make verify`가 `OK: MCP round trip passed`, `OK: SilverBullet checks passed`, `listens on 127.0.0.1 only`(8737과 3000), `tailscale serve is tailnet only`, `refuses ports 22 80 443 8443 8737 3000`을 모두 출력한다.
- [ ] [운영 런북](rbk-2026-10-12-operations.md)의 Exposure audit(수동 점검)을 마치고 결과를 기록했다.
- [ ] `make status`에 두 컨테이너의 `(healthy)`, `proxy http://127.0.0.1:8737`, `proxy http://127.0.0.1:3000`이 보이고, 스왑이 활성이다(`no active swap` 경고가 없음).
- [ ] `make backup`이 main 체크아웃의 `backups/`에 `bm-*.tgz`와 `.sha256`, `.manifest`를 만든다.

## 문제 해결

| 증상 | 확인 |
|---|---|
| `upload failed` | 공인 IP(정지 후 시작하면 바뀜, [rbk-2026-10-12-gcp-vm.md](rbk-2026-10-12-gcp-vm.md) 5단계), SSH 키, `default-allow-ssh`의 소스 IP/32(다른 네트워크면 다시 `update`), 재구축이면 `ssh-keygen -R <공인 IP>` |
| `not on the tailnet and no auth key given` | VM이 아직 tailnet에 없습니다. 인증 키를 붙여 넣어 다시 실행 |
| `tailscale up failed` | 키 만료·재사용 여부, Pre-approved, `tag:agent-hub`의 `tagOwners` |
| 배포 뒤(22번 삭제 뒤) 부트스트랩을 다시 실행해야 함 | `make vm-bootstrap HOST=agent-hub` (Tailscale SSH 사용. **Assumption**, 계획 05 항목 29에서 확인) |
| `Serve is not active` | [accounts 3단계](rbk-2026-10-12-accounts.md)의 MagicDNS와 HTTPS Certificates를 켠 뒤 `make vm-bootstrap`을 다시 실행 |
| `Funnel is on for this node` | Funnel을 끄고([운영 런북](rbk-2026-10-12-operations.md)의 Exposure audit) 다시 실행 |
| `Host key verification failed` / `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM을 다시 만들면 호스트 키가 바뀝니다. `ssh-keygen -R agent-hub` 후 대화형 `ssh ubuntu@agent-hub true`로 새 키를 수락 |
| `make vm-bootstrap` 중 `REMOTE HOST IDENTIFICATION HAS CHANGED` (공인 IP) | 재구축한 VM이 같은 공인 IP를 쓰면 옛 키와 충돌합니다. `ssh-keygen -R <공인 IP>` 후 다시 실행 |
| 새 노드 이름이 `agent-hub-1` | 옛 `agent-hub` 기기가 admin console에 남아 있습니다. 옛 기기를 삭제한 뒤 `make vm-bootstrap`을 다시 실행해 이름을 확인(`tailscale status`) |
| `ssh ubuntu@agent-hub` 실패 | 정책의 `ssh` 규칙([accounts 4단계](rbk-2026-10-12-accounts.md)) |
| 22번을 지운 뒤 접속 불가 | 22번 규칙을 gcloud로 다시 추가합니다. 최후 수단은 GCP 시리얼 콘솔입니다(**Assumption:** 시리얼 포트 활성화와 로컬 비밀번호가 필요해 바로 쓸 수 없을 수 있음, 계획 05에서 확인). 규칙 추가: `gcloud compute firewall-rules create temp-ssh --configuration=bm-personal --network=default --allow=tcp:22 --source-ranges="<내 IP>/32"` (**Assumption:** 새 규칙 이름은 자유). 접속 후 `sudo tailscale status`를 확인하고, 해결되면 이 규칙을 다시 지웁니다 |
| `BM_ACCESS must be tailscale or ssh` | `.env`의 `BM_ACCESS`를 소문자 `tailscale`이나 `ssh`로 고치거나 비웁니다 |
| `ssh` 모드에서 `upload failed: check the ProxyCommand ...` | [VM 런북](rbk-2026-10-12-gcp-vm.md) 8단계: `allow-iap-ssh` 규칙, `~/.ssh/config`의 별칭, `gcloud` 로그인 |
| `Tailscale is logged in on the VM but BM_ACCESS=ssh` | 모드를 바꾸는 중이면 [운영 런북](rbk-2026-10-12-operations.md)의 "접속 방식 바꾸기" 5단계를 마칩니다 |
