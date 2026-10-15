# 부트스트랩: VM을 tailnet에 올리고 배포하기

`make vm-bootstrap`, `make deploy`, `make restore`는 VM을 바꾸므로 에이전트는 사용자의 OK를 받은 뒤에만 실행합니다. 인증 키 프롬프트처럼 터미널 입력이 필요한 명령은 사용자가 자기 터미널에서 직접 실행합니다.

## 준비

- `.env`는 main 체크아웃에 있습니다([accounts 3단계](accounts.md)). `BM_TAILNET_DOMAIN`과 `BM_VM_PUBLIC_IP`가 채워져 있는지 사용자가 확인합니다(에이전트는 읽을 수 없음). 없으면 main 체크아웃에서 `cp .env.example .env` 후 채웁니다.
- 사람은 VM 대상 Make 타깃을 main 체크아웃에서 실행합니다. 에이전트는 자기 worktree에서 실행해도 되며, 그때도 `.env`와 `backups/`는 main 체크아웃의 것을 씁니다. 에이전트가 worktree에서 `deploy`·`restore`를 할 때는 먼저 `git diff main -- compose.yaml`이 아무것도 출력하지 않는지 확인합니다(bm-upgrade의 사용자 승인 배포는 예외).
- [accounts 런북 5단계](accounts.md)대로 1회용 인증 키를 **지금** 발급합니다(만료 1일).

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

## 완료 조건

- [ ] `make verify`가 `OK: MCP round trip passed`, `OK: SilverBullet checks passed`, `listens on 127.0.0.1 only`(8737과 3000), `tailscale serve is tailnet only`, `refuses ports 22 80 443 8443 8737 3000`을 모두 출력한다.
- [ ] [운영 런북](operations.md)의 Exposure audit(수동 점검)을 마치고 결과를 기록했다.
- [ ] `make status`에 두 컨테이너의 `(healthy)`, `proxy http://127.0.0.1:8737`, `proxy http://127.0.0.1:3000`이 보이고, 스왑이 활성이다(`no active swap` 경고가 없음).
- [ ] `make backup`이 main 체크아웃의 `backups/`에 `bm-*.tgz`와 `.sha256`, `.manifest`를 만든다.

## 문제 해결

| 증상 | 확인 |
|---|---|
| `upload failed` | 공인 IP(정지 후 시작하면 바뀜, [gcp-vm.md](gcp-vm.md) 5단계), SSH 키, `default-allow-ssh`의 소스 IP/32(다른 네트워크면 다시 `update`), 재구축이면 `ssh-keygen -R <공인 IP>` |
| `not on the tailnet and no auth key given` | VM이 아직 tailnet에 없습니다. 인증 키를 붙여 넣어 다시 실행 |
| `tailscale up failed` | 키 만료·재사용 여부, Pre-approved, `tag:agent-hub`의 `tagOwners` |
| 배포 뒤(22번 삭제 뒤) 부트스트랩을 다시 실행해야 함 | `make vm-bootstrap HOST=agent-hub` (Tailscale SSH 사용. **Assumption**, 계획 05 항목 29에서 확인) |
| `Serve is not active` | [accounts 3단계](accounts.md)의 MagicDNS와 HTTPS Certificates를 켠 뒤 `make vm-bootstrap`을 다시 실행 |
| `Funnel is on for this node` | Funnel을 끄고([운영 런북](operations.md)의 Exposure audit) 다시 실행 |
| `Host key verification failed` / `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM을 다시 만들면 호스트 키가 바뀝니다. `ssh-keygen -R agent-hub` 후 대화형 `ssh ubuntu@agent-hub true`로 새 키를 수락 |
| `make vm-bootstrap` 중 `REMOTE HOST IDENTIFICATION HAS CHANGED` (공인 IP) | 재구축한 VM이 같은 공인 IP를 쓰면 옛 키와 충돌합니다. `ssh-keygen -R <공인 IP>` 후 다시 실행 |
| 새 노드 이름이 `agent-hub-1` | 옛 `agent-hub` 기기가 admin console에 남아 있습니다. 옛 기기를 삭제한 뒤 `make vm-bootstrap`을 다시 실행해 이름을 확인(`tailscale status`) |
| `ssh ubuntu@agent-hub` 실패 | 정책의 `ssh` 규칙([accounts 4단계](accounts.md)) |
| 22번을 지운 뒤 접속 불가 | 22번 규칙을 gcloud로 다시 추가합니다. 최후 수단은 GCP 시리얼 콘솔입니다(**Assumption:** 시리얼 포트 활성화와 로컬 비밀번호가 필요해 바로 쓸 수 없을 수 있음, 계획 05에서 확인). 규칙 추가: `gcloud compute firewall-rules create temp-ssh --configuration=bm-personal --network=default --allow=tcp:22 --source-ranges="<내 IP>/32"` (**Assumption:** 새 규칙 이름은 자유). 접속 후 `sudo tailscale status`를 확인하고, 해결되면 이 규칙을 다시 지웁니다 |
