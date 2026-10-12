# 계정 준비: GCP와 Tailscale

## 1. GCP 가입과 gcloud 설정

1. **개인** Google 계정으로 https://console.cloud.google.com 에 가입하고 결제 계정을 만듭니다. 무료 등급(e2-micro 1대 등)도 결제 계정이 필요합니다(**Verified**, docs.cloud.google.com/free/docs/free-cloud-features). 회사 Google 계정과 회사 프로젝트는 쓰지 않습니다.
2. 이 저장소 전용 프로젝트를 만들고 프로젝트 ID를 적어 둡니다.
3. **VM을 만들기 전에** Budget 알림을 만듭니다: 월 예산 $1, 알림 임계값(예: 50%, 100%). **Assumption:** 콘솔 메뉴 이름(Billing → Budgets & alerts)은 바뀔 수 있습니다.
4. Mac에 Google Cloud SDK를 설치합니다(공식 설치 안내: cloud.google.com/sdk/docs/install).
5. 이 Mac의 활성 gcloud 설정은 회사 계정일 수 있습니다. 먼저 현재 상태를 확인하고, 활성이 아닌 설정 `bm-personal`을 따로 만들어 씁니다.

```bash
gcloud config configurations list
gcloud config configurations create bm-personal --no-activate
gcloud auth login --configuration=bm-personal
gcloud config set project <프로젝트 ID> --configuration=bm-personal
gcloud config list --configuration=bm-personal
```

Expected: 첫 명령에서 회사 설정이 계속 `IS_ACTIVE=True`입니다. 마지막 명령에서 `account`가 개인 계정이고 `project`가 전용 프로젝트입니다.

- 이후 **모든 gcloud 명령에 `--configuration=bm-personal`을 붙입니다.** 회사 설정은 활성 상태로 둡니다.
- 설정 활성화(`configurations activate`)와 `auth application-default …`는 실행하지 않습니다. 회사 설정과 인증 정보를 건드리지 않기 위해서입니다.
- **Open question:** 외부 IPv4 요금($0.005/h, 2024-02-01부터)이 무료 등급에 포함되는지는 공식 문서에 없습니다. 배포 다음 날 [운영 런북](rbk-2026-10-12-t79ex2ny-operations.md)의 비용 점검으로 확인합니다.

## 2. Tailscale 가입

1. https://login.tailscale.com/start 에서 **개인 계정**으로 가입합니다. 회사 도메인 이메일로 가입하면 tailnet이 회사 소유가 됩니다(**Verified**).
2. **Open question:** 회사 Mac을 개인 tailnet에 참여시키는 것이 회사 보안 정책과 Tailscale Personal 약관(비상업 용도)에 맞는지 직접 확인하세요.
3. 이 Mac에 Tailscale 앱을 설치하고 로그인합니다(`brew install --cask tailscale` 또는 App Store).
4. 터미널에서 `tailscale version`이 동작하는지 확인합니다. 스킬 `bm-diagnose`가 `tailscale status`를 씁니다. **Assumption:** 앱만 설치하면 `tailscale` 명령이 PATH에 없을 수 있습니다. 없으면 Tailscale 문서의 CLI 설치 안내를 따라 명령을 쓸 수 있게 합니다.

## 3. DNS와 HTTPS

Admin console → **DNS**에서 다음을 켭니다.
- **MagicDNS**
- **HTTPS Certificates**: 인증서가 발급된 기기 이름은 공개 Certificate Transparency 로그에 기록됩니다(**Verified**). 그래서 기기 이름을 일반적인 `agent-hub`로 씁니다.

먼저 **main 체크아웃**의 루트에서 설정 파일을 만듭니다(이미 있으면 건너뜁니다).

```bash
cp .env.example .env
```

`.env`는 git에 커밋하지 않습니다(`.gitignore`가 제외). tailnet DNS 이름(예: `tail1234.ts.net`)을 `.env`의 `BM_TAILNET_DOMAIN`에 적습니다. `.env`는 사용자가 직접 편집합니다(에이전트는 읽을 수 없음). `BM_VM_HOST`는 `agent-hub` 그대로 둡니다. 부트스트랩이 기기 이름을 `agent-hub`로 고정하므로 바꾸면 deploy와 verify가 VM을 찾지 못합니다. GCP 인스턴스 이름(예: `agent-hub-01`)은 `agent-hub`와 달라도 되며, 스크립트는 `agent-hub`만 씁니다.

`.env`와 `backups/`는 **main 체크아웃에만** 둡니다(`.local-data/`는 `make local-up`을 실행한 체크아웃마다 따로 생기는 로컬 테스트 데이터입니다). Makefile은 어느 체크아웃에서 실행하든 main 체크아웃의 `.env`를 읽고, `make backup`은 main 체크아웃의 `backups/`에 저장합니다. worktree 안에 `.env`나 백업을 따로 만들지 마세요. `git worktree remove`는 worktree 안의 git ignore 파일을 경고 없이 지웁니다.

## 4. 접근 정책 (Access controls)

Admin console → **Access controls**에서 정책 파일을 편집합니다.

1. `tagOwners`에 서버 태그를 추가합니다.
2. `ssh`에 태그 서버로의 접속 규칙을 추가합니다. 기본 규칙의 `autogroup:self`는 태그가 붙은 기기를 포함하지 않으므로 별도 규칙이 필요합니다.
3. **Funnel 사용 권한이 없는지 확인합니다**: Funnel은 기본 비활성입니다(**Verified**, tailscale.com/docs/features/tailscale-funnel). 누군가 `tailscale funnel`을 실행해 승인하면 정책 `nodeAttrs`에 `"funnel"` 속성이 추가됩니다. 이 속성이 있으면 지웁니다. 기기가 실제로 공개 중인지는 `make verify`/`make probe`가 `tailscale serve status`로 따로 확인합니다.

```json
{
  "tagOwners": {
    "tag:agent-hub": ["autogroup:admin"]
  },
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:agent-hub"],
      "users": ["ubuntu"]
    }
  ]
}
```

**Assumption:** 이 조각은 기존 정책 파일의 해당 섹션에 합쳐 넣는 것입니다. 저장할 때 편집기가 문법을 검증하니, 오류가 나면 메시지대로 고치세요.

## 5. 인증 키 (부트스트랩 직전에 발급)

Settings → **Keys** → **Generate auth key**:
- Reusable: **끔** (1회용)
- Ephemeral: **끔** (서버는 계속 유지)
- Pre-approved: **켬**
- Tags: `tag:agent-hub`
- Expiration: 1일

키는 어디에도 저장하지 말고, 사용자가 자기 터미널에서 `make vm-bootstrap`의 숨김 프롬프트에 붙여 넣습니다. 채팅에 붙여 넣거나 명령줄 인자로 넘기지 않습니다([부트스트랩 런북](rbk-2026-10-12-ha5w72pm-bootstrap.md)).
