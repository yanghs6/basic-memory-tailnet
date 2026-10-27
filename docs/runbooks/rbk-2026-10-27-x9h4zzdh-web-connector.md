---
status: current
id: x9h4zzdh
reviewed: 2026-10-27
---

# 웹 커넥터 (claude.ai) 켜기·운영·차단

claude.ai의 커스텀 커넥터로 Basic Memory를 쓰려고 선택 기능 `BM_WEB=on`을 켜거나, 켠 뒤 운영하고 끌 때 쓰는 런북입니다. 구조는 [웹 커넥터 설계](../specs/spec-2026-10-22-tn23wwmd-web-connector.md), 결정은 [web-connector ADR](../decisions/adr-2026-10-22-fcvznmdc-web-connector.md)에 있습니다. 공개되는 것은 Cloudflare 호스트명 하나이고, 그 뒤에서 `cloudflared`가 아웃바운드로만 연결해 OAuth 게이트웨이(`gateway`)에 닿습니다. 게이트웨이는 GitHub 계정 하나(숫자 id)와 허용한 도구 18개만 통과시킵니다.

이 문서는 호스트명과 IP를 적지 않습니다. `<BM_WEB_HOST>`(예: `mcp.<domain>`)는 `.env` 값으로 읽으세요. 출력을 PR이나 Progress log에 붙이기 전에 호스트명이 들어 있는지 확인합니다.

**Command:** 앞으로 쓰는 변수 이름은 `.env.example`에 있습니다.

| 변수 | 비밀값 | 내용 |
|---|---|---|
| `BM_WEB` | 아니오 | `on` / `off` (비어 있으면 꺼짐) |
| `BM_WEB_HOST` | 아니오 | 공개 호스트명. `https://`, 경로, 포트 없이 |
| `BM_WEB_PORT` | 아니오 | 게이트웨이의 `127.0.0.1` 게시 포트(기본 8738) |
| `BM_WEB_GITHUB_USER_ID` | 아니오 | 통과시킬 GitHub 사용자의 숫자 id |
| `BM_WEB_GITHUB_CLIENT_ID` | 아니오 | GitHub OAuth App의 client ID |
| `BM_WEB_GITHUB_CLIENT_SECRET` | 예 | GitHub OAuth App의 client secret |
| `BM_WEB_JWT_KEY` | 예 | 게이트웨이 토큰 서명과 저장소 암호화 키. 32자 이상 |
| `BM_WEB_TUNNEL_TOKEN` | 예 | Cloudflare tunnel 토큰 |

## 준비

### 언제 쓰나

처음 `BM_WEB=on`으로 배포하기 전에 한 번 합니다. 절차는 사람이 브라우저에서 하는 작업이라 에이전트가 대신하지 않습니다.

### 사전 조건

- Cloudflare 계정과, 그 DNS로 관리하는 도메인 하나.
- 노트가 Cloudflare(TLS 종료 지점)와 Anthropic 대화를 지나가는 것을 받아들인다는 결정([ADR](../decisions/adr-2026-10-22-fcvznmdc-web-connector.md)).
- VM이 `BM_ACCESS` 어느 모드로든 배포돼 있고 `make verify`가 통과합니다.

### 절차

**Assumption:** 아래 Cloudflare와 GitHub의 메뉴 이름과 경로는 이 저장소에서 따라 해 보지 않은 설명입니다. 화면이 다르면 같은 기능을 찾아 쓰고, 처음 켤 때(웹 커넥터 계획 Task 4) 확인해 고칩니다.

1. 도메인을 Cloudflare DNS에 올립니다(네임서버를 Cloudflare로 바꿈).
2. Cloudflare Zero Trust에서 remotely-managed tunnel을 만들고 토큰을 복사합니다. Public hostname 하나를 `<BM_WEB_HOST>`로 정하고 서비스는 `http://gateway:8080`으로 둡니다. 다른 호스트명이나 서비스를 더하지 않습니다. quick tunnel(`trycloudflare.com`)은 인증 없는 공개 URL이 되므로 쓰지 않습니다.
   - **Verified:** Docker 네트워크로는 `cloudflared`가 `web` 네트워크에만 있어서, 대시보드의 서비스를 잘못 적어도 Basic Memory와 SilverBullet 컨테이너에는 닿지 못합니다(`compose.yaml`의 `networks`).
   - **Assumption:** 이 격리는 Docker 네트워크 사이의 것뿐입니다. `web`은 바깥으로 나가는 일반 bridge 네트워크라서, `cloudflared`는 VM이 라우팅하는 곳(인터넷, `0.0.0.0`에 열린 호스트 포트, `169.254.169.254` 같은 link-local 주소)에는 닿을 수 있습니다. 그래서 대시보드의 서비스가 `http://gateway:8080` 하나인지는 그대로 통제 항목이고, [운영 런북](rbk-2026-10-12-t79ex2ny-operations.md)의 Exposure audit이 점검합니다.
3. GitHub → Settings → Developer settings → OAuth Apps에서 앱을 만듭니다. Authorization callback URL은 `https://<BM_WEB_HOST>/auth/callback` 하나입니다. client ID를 적고 client secret을 만듭니다.
4. 허용할 GitHub 계정의 숫자 id를 찾습니다. 로그인 이름은 바뀌어 남이 가져갈 수 있으므로 id를 씁니다.

   ```bash
   gh api users/<login> --jq .id
   ```

5. 키를 만듭니다. `make`가 `.env`를 글자 그대로 읽으므로 영숫자와 `._~+/=-`만 씁니다.

   ```bash
   openssl rand -hex 32
   ```

### 확인

- 위 값 여덟 개가 모두 준비됐고, 호스트명은 Cloudflare 대시보드의 Public hostname과 같습니다.

### 되돌리기

1. Cloudflare에서 tunnel과 Public hostname을 지우고, GitHub OAuth App을 지웁니다. VM은 아직 바뀌지 않았습니다.

## .env 값 쓰기

### 절차

1. 사용자가 main 체크아웃의 `.env`에 `.env.example`의 `BM_WEB*` 항목을 직접 씁니다. 비밀값 세 개(`BM_WEB_GITHUB_CLIENT_SECRET`, `BM_WEB_JWT_KEY`, `BM_WEB_TUNNEL_TOKEN`)는 채팅, 명령 인자, 저장소 파일에 쓰지 않습니다. 에이전트는 `.env`를 읽지도 복사하지도 않습니다.
2. 스크립트는 값을 검사해 틀리면 원격 접속 전에 실패합니다: `BM_WEB must be on or off`, `BM_WEB_HOST must be a host name like mcp.<domain>`, `BM_WEB_GITHUB_USER_ID must be the numeric GitHub user id`. 비밀값은 `vm_env`가 ssh 표준입력으로 VM `.env`(권한 600)에 씁니다.

## 켜기

### 사전 조건

- 위 두 절이 끝났습니다.
- `make deploy`는 VM을 바꾸므로 **사용자 OK를 받는다**. `make backup`은 컨테이너를 잠깐 멈춘다고 알립니다.
- 먼저 로컬에서 `BM_WEB=on make local-up local-verify`를 통과시킬 수 있습니다. 이 검사는 게이트웨이 단위 테스트도 uid 1000으로 돌립니다.
  - **Verified (2026-10-26, [web-connector 계획](../plans/plan-2026-10-22-d3dpb00s-web-connector.md)의 Progress log):** 로컬 검사에는 가짜 GitHub 값이면 됩니다. 가짜 사용자 id·client id·secret과 `openssl rand -hex 32` 키를 make 명령줄로 넘긴 `make local-up local-verify local-down`이 통과했습니다.

### 절차

1. 쓰기를 열기 전의 롤백 지점을 만듭니다.

   ```bash
   make backup
   ```

2. 배포합니다. `BM_WEB=on`이면 `gateway/` 파일을 VM에 올리고 `COMPOSE_PROFILES=web,tunnel`로 `gateway`와 `cloudflared`를 함께 띄웁니다. 게이트웨이의 첫 시작은 의존성을 설치하느라 몇 분 걸립니다(헬스체크 `start_period` 300초). 나중에 `gateway/` 코드나 `requirements.txt`만 바뀐 배포도, VM `.env`의 `BM_WEB_CODE_SHA256`(런타임 파일 세 개의 sha256)이 바뀌어 `gateway` 컨테이너를 다시 만듭니다.
   - **Verified (2026-10-27, Docker Compose v5.0.2):** `docker compose -f compose.yaml config --hash gateway`가 `BM_WEB_CODE_SHA256` 값에 따라 달라지고 `basic-memory`의 값은 그대로입니다. compose는 이 값이 바뀐 서비스만 다시 만듭니다.

   ```bash
   make deploy
   ```

3. 검증합니다.

   ```bash
   make verify
   make status
   ```

### 확인

- **Command:** `make verify`가 `OK: POST /mcp without a token answers 401 with resource_metadata`, `OK: the protected resource metadata names BASE_URL/mcp`, `OK: the authorization server metadata offers S256, client ID metadata documents and the none token auth method`, `OK: /register refuses a foreign redirect URI`, `OK: the host resolves only to public IPv4 addresses`를 냅니다. 게이트웨이 포트가 VM의 `127.0.0.1`에만 열려 있고 공인 IP에서 닫혀 있는지도 봅니다. 호스트명과 IP는 출력되지 않습니다.
- `make status`가 두 웹 컨테이너(`gateway-server`, `cloudflared-tunnel`)와 `gateway store: <N> KiB, <M> client registrations`를 보입니다. `<M>`은 `oauth-proxy/` 아래 모든 키 지문 디렉터리의 등록 수라서, `BM_WEB_JWT_KEY`를 바꾸기 전 키로 만든(이제는 읽지 못하는) 등록도 셉니다.
- **Assumption:** 실제 GitHub 로그인과 claude.ai 연결은 자동화하지 않습니다. 아래 "커넥터 등록"에서 사람이 확인합니다.

### 되돌리기

1. "차단과 끄기"를 따릅니다. 데이터가 바뀐 흔적이 있으면 1단계의 백업으로 복원합니다(`make restore`, 사용자가 직접 `yes`).
   - `BM_WEB=on`인 `make restore`는 Basic Memory와 SilverBullet이 healthy해지면 성공합니다. 그 뒤에 띄우는 `gateway`·`cloudflared`가 healthy하지 않으면 실패나 롤백 없이 `WARNING: the web connector services are not healthy`만 내므로, 그때는 `make status`와 `make logs`로 봅니다.

## Cloudflare 보호 설정

게이트웨이의 OAuth 엔드포인트는 표준상 인증 없이 열려 있고, 인증 없는 요청도 저장소에 파일을 남깁니다([설계 3.4](../specs/spec-2026-10-22-tn23wwmd-web-connector.md)). 그래서 edge에서 속도를 묶습니다.

**Assumption:** 아래 Cloudflare 메뉴 경로(Security → WAF, Security → Bots)는 이 저장소에서 따라 해 보지 않은 설명입니다. 처음 켤 때 확인해 고칩니다.

1. Security → WAF → Rate limiting rules에 규칙 하나를 만듭니다. 경로가 `/register`, `/authorize`, `/consent` 중 하나일 때 한 IP당 분당 소수(예: 10회)를 넘으면 차단합니다. Claude는 연결할 때만 이 경로를 부르므로 정상 사용은 걸리지 않습니다.
   - **Assumption:** 무료 규칙 하나로 세 경로를 묶을 수 있습니다. 안 되면 `/register`에만 겁니다.
   - **Open question:** 무료 등급의 rate limit 규칙 수와 조건 길이는 대시보드에서 확인해야 합니다(바뀔 수 있음).
2. Security → Bots의 Bot Fight Mode가 켜져 있으면 claude.ai 백엔드를 막을 수 있습니다. 커넥터 연결이 막히면 Anthropic 아웃바운드 대역 `160.79.104.0/21`을 예외(Skip)로 둡니다.
   - **Reported:** Claude 커넥터 문제 해결 문서는 WAF가 Anthropic 대역에 403/429를 내는 것을 대표 실패 원인으로 듭니다([설계 §2](../specs/spec-2026-10-22-tn23wwmd-web-connector.md)). **Assumption:** Bot Fight Mode도 그렇게 막을 수 있습니다.
   - **Reported:** 이 대역은 Anthropic 문서의 값입니다. 연결이 안 될 때 문서에서 다시 확인합니다.

### 확인

- 규칙의 Action과 경로가 위와 같고, 커넥터 등록(다음 절)이 막히지 않습니다.

## 커넥터 등록

### 절차

1. claude.ai → Settings → Connectors → Add custom connector에서 URL `https://<BM_WEB_HOST>/mcp`를 입력합니다.
   - **Assumption:** 이 claude.ai 설정 경로는 이 저장소에서 따라 해 보지 않았습니다. 처음 연결할 때 확인해 고칩니다.
2. GitHub 로그인과 동의 화면이 뜨면, 허용한 계정으로 로그인하고 동의합니다. Claude 콜백은 `https://claude.ai/api/mcp/auth_callback` 하나만 허용됩니다.
3. 도구 목록에 허용한 18개만 보이는지 확인합니다(`delete_note`, `create_memory_project`, `delete_project`는 없습니다).
4. 도구별 권한을 정합니다. 읽기 도구도 승인 방식으로 시작하세요. 쓰기 도구(`write_note`, `edit_note`, `move_note`)에는 **"Always allow"를 쓰지 않는다**. 웹 페이지나 다른 커넥터 내용이 모델에게 쓰기를 시킬 수 있습니다.
   - **Verified (2026-10-16, [설계 §2](../specs/spec-2026-10-22-tn23wwmd-web-connector.md)의 Claude Help 문서):** Research 모드는 추가 승인 없이 도구를 부릅니다. 그래서 도구별 승인 설정만으로는 쓰기를 막지 못합니다.
5. 선택: 다른 GitHub 계정으로 로그인해 보면 도구가 0개이고 호출이 거절되어야 합니다.

### 확인

- 새 대화에서 읽기 도구(`search_notes`)를 불러 결과가 옵니다. `make logs`에서 `gateway-server`의 감사 줄(JSON, `time`·`user`·`tool`·`note`·`ms`, 노트 본문 없음)을 확인합니다. 거절된 호출도 줄이 남습니다.

### 되돌리기

1. claude.ai에서 커넥터를 지웁니다(차단 3).

## 비밀값 교체

노출이 의심될 때 하나씩 바꿉니다. 새 값은 사용자가 main 체크아웃 `.env`에 직접 쓰고 `make deploy`로 올립니다(**사용자 OK를 받는다**).

- **GitHub client secret:** GitHub OAuth App에서 새 secret을 만들고 이전 것을 지운 뒤 `.env`를 바꾸고 배포합니다.
- **터널 토큰:** Cloudflare에서 tunnel 토큰을 새로 발급받고 `.env`를 바꾸고 배포합니다.
- **`BM_WEB_JWT_KEY`:** 바꾸면 모든 클라이언트 등록과 토큰이 무효가 됩니다. 저장소 경로가 키 지문별이라 이전 지문 디렉터리는 디스크에 남으므로, `.env`를 바꾸고 배포한 뒤 아래 "게이트웨이 저장소 비우기"를 같이 합니다. 그다음 claude.ai에서 커넥터를 다시 연결합니다.

## 게이트웨이 저장소 비우기

### 언제 쓰나

`make status`의 `gateway store` 크기나 등록 수가 이상하게 늘었을 때(인증 없는 요청이 남긴 파일), 또는 `BM_WEB_JWT_KEY`를 바꾼 뒤.

### 사전 조건

- VM 파일을 지우므로 **사용자 OK를 받는다**. 지우는 것은 게이트웨이 저장소(`/srv/basic-memory/gateway/oauth-proxy/` 아래의 키 지문 디렉터리)뿐입니다. `knowledge/`, `config/`, `backups/`, `/srv/basic-memory.prev-*`는 건드리지 않습니다.
- 지운 뒤에는 claude.ai에서 커넥터를 다시 연결해야 합니다.

### 절차

2·3단계의 `ssh … docker compose stop`과 `rm -rf`는 Make 타깃이 아닌 원시 명령입니다. `AGENTS.md`의 "Make targets only" 규칙의 예외로, [설계 §3.4](../specs/spec-2026-10-22-tn23wwmd-web-connector.md)의 저장소 누적 결정 4가 정한 비우기 절차이며, **사용자 OK를 받은 뒤에만** 실행합니다.

1. 현재 크기를 기록합니다(`make status`의 `gateway store` 줄).
2. 게이트웨이를 멈춥니다. 앱 디렉터리는 `/opt/basic-memory`입니다.

   ```bash
   ssh <BM_VM_USER>@<BM_VM_HOST> 'cd /opt/basic-memory && docker compose stop gateway'
   ```

3. 지울 디렉터리를 먼저 눈으로 확인한 뒤 지웁니다.

   ```bash
   ssh <BM_VM_USER>@<BM_VM_HOST> 'sudo -n ls -la /srv/basic-memory/gateway/oauth-proxy'
   ssh <BM_VM_USER>@<BM_VM_HOST> 'sudo -n find /srv/basic-memory/gateway/oauth-proxy -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +'
   ```

4. 다시 켭니다.

   ```bash
   make deploy
   ```

5. claude.ai에서 커넥터를 지우고 다시 추가합니다.

### 확인

- `make status`의 `gateway store`가 작아지고 등록 수가 0에서 시작합니다. `make verify`가 통과합니다.

### 되돌리기

- 지운 저장소는 되살릴 필요가 없습니다(다시 연결하면 새로 만들어집니다).

## 차단과 끄기

급한 순서입니다. 앞 단계로 충분하면 멈춥니다.

1. **네트워크(가장 빠름):** 터널만 멈추면 공개 경로가 바로 닫힙니다. 아래 `ssh … docker compose stop`은 Make 타깃이 아닌 원시 명령입니다. `AGENTS.md`의 "Make targets only" 규칙의 예외로 [설계 §4](../specs/spec-2026-10-22-tn23wwmd-web-connector.md)의 차단 1이 정한 한 줄 명령이며, VM을 바꾸므로 **사용자 OK를 받은 뒤에만** 실행합니다.
   - **Command:**

     ```bash
     ssh <BM_VM_USER>@<BM_VM_HOST> 'cd /opt/basic-memory && docker compose stop cloudflared'
     ```

   - 영구히 끄려면 `.env`에서 `BM_WEB=off`(또는 비움)로 바꾸고 `make deploy`를 합니다(**사용자 OK를 받는다**). `BM_WEB=off`로 배포하면 남은 `gateway`·`cloudflared` 컨테이너를 `rm --stop --force`로 지웁니다. `gateway/` 파일과 저장소는 VM에 남습니다.
2. **토큰:** `BM_WEB_JWT_KEY`를 바꾸고 배포합니다(위 "비밀값 교체"). 이미 발급된 토큰과 등록이 모두 무효가 됩니다.
3. **클라이언트:** claude.ai에서 커넥터를 지우고, GitHub OAuth App을 지우고, Cloudflare의 tunnel과 Public hostname을 지웁니다.

### 확인

- `make status`가 웹 컨테이너를 보이지 않고, `make verify`에 웹 검사가 없습니다. 밖에서 `https://<BM_WEB_HOST>/mcp`가 응답하지 않습니다.
