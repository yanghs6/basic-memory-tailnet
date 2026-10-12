# 부트스트랩: VM을 tailnet에 올리고 배포하기

`make vm-bootstrap`, `make deploy`, `make restore`는 VM을 바꾸므로 에이전트는 사용자의 OK를 받은 뒤에만 실행합니다. 인증 키 프롬프트처럼 터미널 입력이 필요한 명령은 사용자가 자기 터미널에서 직접 실행합니다.

## 준비

`.env`는 [accounts 3단계](accounts.md)에서 만들었습니다. `BM_TAILNET_DOMAIN`과 `BM_VM_PUBLIC_IP`가 채워져 있는지 사용자가 확인합니다(에이전트는 읽을 수 없음). 없으면 `cp .env.example .env` 후 채웁니다.

[accounts 런북 5단계](accounts.md)대로 1회용 인증 키를 발급해 둡니다.

## 순서

1. VM을 다시 만드는 경우(재구축)에만:
   - Tailscale admin console에서 옛 `bm-node` 기기를 먼저 삭제합니다. 남아 있으면 새 노드가 `bm-node-1` 같은 다른 이름으로 들어옵니다.
   - 옛 호스트 키를 지웁니다: `ssh-keygen -R bm-node`. 새 VM이 옛 공인 IP를 그대로 받았다면 `ssh-keygen -R <공인 IP>`도 실행합니다.
2. `make vm-bootstrap HOST=<공인 IP>` → 숨김 프롬프트에 인증 키를 붙여 넣습니다(화면에 표시되지 않음).
   - 인증 키를 명령줄에 쓰지 마세요(`make vm-bootstrap TS_AUTHKEY=...` 금지: 셸 기록과 프로세스 목록에 남습니다). 프롬프트를 쓰거나, 먼저 `read -rs TS_AUTHKEY && export TS_AUTHKEY`를 실행합니다.
   - Docker·Tailscale 설치, tailnet 참여(`bm-node`, Tailscale SSH), 데이터 디렉터리 생성, Serve 설정까지 합니다.
   - 여러 번 실행해도 안전합니다. 이미 tailnet에 있으면 키 없이 빈 입력으로 다시 실행할 수 있습니다.
3. `ssh ubuntu@bm-node true` → **대화형으로 처음 한 번** 실행해 새 호스트 키를 수락하고, Tailscale SSH로 접속되는지 확인합니다.
4. **3단계가 성공한 뒤에만** OCI 콘솔에서 22번 인바운드 규칙을 삭제합니다. 이제 TCP/UDP 인바운드가 없습니다.
5. `make deploy verify status`

## 완료 조건

- [ ] `make verify`가 `OK: MCP round trip passed`, `listens on 127.0.0.1 only`, `tailscale serve is tailnet only`, `refuses ports 22 80 443 8737`을 모두 출력한다.
- [ ] [운영 런북](operations.md)의 Exposure audit(수동 점검)을 마치고 결과를 기록했다.
- [ ] `make status`에 `(healthy)`, `proxy http://127.0.0.1:8737`이 보인다.
- [ ] `make backup`이 `backups/bm-*.tgz`와 `.sha256`, `.manifest`를 만든다.

## 문제 해결

| 증상 | 확인 |
|---|---|
| `upload failed` | 공인 IP, SSH 키, 22번 규칙의 Source IP |
| `not on the tailnet and no auth key given` | VM이 아직 tailnet에 없습니다. 인증 키를 붙여 넣어 다시 실행 |
| `tailscale up failed` | 키 만료·재사용 여부, Pre-approved, `tag:bm-server`의 `tagOwners` |
| `Serve is not active` | [accounts 3단계](accounts.md)의 MagicDNS와 HTTPS Certificates를 켠 뒤 `make vm-bootstrap`을 다시 실행 |
| `Funnel is on for this node` | Funnel을 끄고([운영 런북](operations.md)의 Exposure audit) 다시 실행 |
| `Host key verification failed` / `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM을 다시 만들면 호스트 키가 바뀝니다. `ssh-keygen -R bm-node` 후 대화형 `ssh ubuntu@bm-node true`로 새 키를 수락 |
| `make vm-bootstrap` 중 `REMOTE HOST IDENTIFICATION HAS CHANGED` (공인 IP) | 재구축한 VM이 같은 공인 IP를 쓰면 옛 키와 충돌합니다. `ssh-keygen -R <공인 IP>` 후 다시 실행 |
| 새 노드 이름이 `bm-node-1` | 옛 `bm-node` 기기가 admin console에 남아 있습니다. 옛 기기를 삭제한 뒤 `make vm-bootstrap`을 다시 실행해 이름을 확인(`tailscale status`) |
| `ssh ubuntu@bm-node` 실패 | 정책의 `ssh` 규칙([accounts 4단계](accounts.md)) |
| 22번을 지운 뒤 접속 불가 | OCI 콘솔 → 인스턴스 → **Console connection**(시리얼 콘솔)으로 들어가 `sudo tailscale status` 확인 |
