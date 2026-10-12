# 계정 준비: OCI와 Tailscale

## 1. OCI 가입

1. https://signup.cloud.oracle.com 에서 가입합니다. **Assumption:** 본인 확인용 카드 등록이 필요합니다(Always Free 자원만 쓰면 과금되지 않음).
2. **홈 리전은 나중에 바꿀 수 없습니다**(**Verified**). 한국 리전은 `ap-seoul-1`(서울)과 `ap-chuncheon-1`(춘천)이며, 둘 다 가용 도메인(AD)이 1개입니다. A1 용량이 부족하면 VM 생성이 실패할 수 있습니다.
3. Pay As You Go로 업그레이드하지 않습니다. 업그레이드 계정에 유휴 회수 정책이 적용되는지는 **Open question**입니다.

## 2. Tailscale 가입

1. https://login.tailscale.com/start 에서 **개인 계정**으로 가입합니다. 회사 도메인 이메일로 가입하면 tailnet이 회사 소유가 됩니다(**Verified**).
2. **Open question:** 회사 Mac을 개인 tailnet에 참여시키는 것이 회사 보안 정책과 Tailscale Personal 약관(비상업 용도)에 맞는지 직접 확인하세요.
3. 이 Mac에 Tailscale 앱을 설치하고 로그인합니다(`brew install --cask tailscale` 또는 App Store).

## 3. DNS와 HTTPS

Admin console → **DNS**에서 다음을 켭니다.
- **MagicDNS**
- **HTTPS Certificates**: 인증서가 발급된 기기 이름은 공개 Certificate Transparency 로그에 기록됩니다(**Verified**). 그래서 기기 이름을 일반적인 `bm-node`로 씁니다.

먼저 저장소 루트에서 설정 파일을 만듭니다(이미 있으면 건너뜁니다).

```bash
cp .env.example .env
```

`.env`는 git에 커밋하지 않습니다(`.gitignore`가 제외). tailnet DNS 이름(예: `tail1234.ts.net`)을 `.env`의 `BM_TAILNET_DOMAIN`에 적습니다. `.env`는 사용자가 직접 편집합니다(에이전트는 읽을 수 없음). `BM_VM_HOST`는 `bm-node` 그대로 둡니다. 부트스트랩이 기기 이름을 `bm-node`로 고정하므로 바꾸면 deploy와 verify가 VM을 찾지 못합니다.

## 4. 접근 정책 (Access controls)

Admin console → **Access controls**에서 정책 파일을 편집합니다.

1. `tagOwners`에 서버 태그를 추가합니다.
2. `ssh`에 태그 서버로의 접속 규칙을 추가합니다. 기본 규칙의 `autogroup:self`는 태그가 붙은 기기를 포함하지 않으므로 별도 규칙이 필요합니다.
3. **Funnel 사용 권한이 없는지 확인합니다**: Funnel은 기본 비활성입니다(**Verified**, tailscale.com/docs/features/tailscale-funnel). 누군가 `tailscale funnel`을 실행해 승인하면 정책 `nodeAttrs`에 `"funnel"` 속성이 추가됩니다. 이 속성이 있으면 지웁니다. 기기가 실제로 공개 중인지는 `make verify`/`make probe`가 `tailscale serve status`로 따로 확인합니다.

```json
{
  "tagOwners": {
    "tag:bm-server": ["autogroup:admin"]
  },
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:bm-server"],
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
- Tags: `tag:bm-server`
- Expiration: 1일

키는 어디에도 저장하지 말고, 사용자가 자기 터미널에서 `make vm-bootstrap`의 숨김 프롬프트에 붙여 넣습니다. 채팅에 붙여 넣거나 명령줄 인자로 넘기지 않습니다([부트스트랩 런북](bootstrap.md)).
