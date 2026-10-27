---
status: accepted
id: fcvznmdc
date: 2026-10-27
---

# ADR fcvznmdc: claude.ai 웹 커넥터는 아웃바운드 터널 뒤의 OAuth 게이트웨이로만 연다

- 설계: [웹 커넥터 설계](../specs/spec-2026-10-22-tn23wwmd-web-connector.md)
- 대체 범위: [basic-memory-on-gcp-tailscale ADR](adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md)과 [access-modes ADR](adr-2026-10-15-cz8c26gp-access-modes.md)이 전제한 "VM에 공개 인그레스 0"을 결정 2의 규칙으로 바꾼다. 두 ADR의 다른 결정은 그대로다.

## 맥락과 문제

- claude.ai의 커스텀 커넥터는 사용자 기기가 아니라 Anthropic 클라우드에서 MCP 서버를 호출하고, tailnet(CGNAT)·사설·loopback 주소는 요청 전에 거절한다(설계 §2). 지금 두 접속 방식으로는 웹에서 Basic Memory를 쓸 수 없다.
- Basic Memory 0.23.2에는 인증이 없다. claude.ai가 개인 플랜에서 받는 인증은 사실상 OAuth뿐이다(고정 헤더는 일부 조직 한정 beta).
- 사용자는 2026-10-22에 불변식을 바꿔서라도 웹에서 쓰기로 했다. 로그인이 강제되면 노트 전체와 쓰기 도구를 열어도 된다고 정했다(설계 §1 사용자 결정).

## 검토한 대안

1. 불변식 유지 + Basic Memory Cloud(월 $15/seat): 운영 부담이 없다. 노트가 VM을 떠나고, 이 저장소의 자체 호스팅을 대체한다.
2. Tailscale Funnel + 게이트웨이: 추가 비용이 없다. ssh 모드 VM은 Tailscale이 꺼져 있고, 한 VM 두 모드 금지와 Funnel 금지를 함께 풀어야 한다.
3. VM 공인 IPv4 443 + Caddy + 게이트웨이: 구성이 단순하다. 방화벽을 열어 인터넷 스캔을 1GB VM이 직접 받는다. 벤더가 IPv4로만 호출해서 [ipv6-egress 계획](../plans/plan-2026-10-13-gaewewkf-ipv6-egress.md)(IPv6 전용)과 충돌한다.
4. Cloudflare named Tunnel + Cloudflare Access Managed OAuth: VM 메모리를 거의 쓰지 않는다. origin이 Access JWT를 검증해야 하는데 Basic Memory는 못 하고, 도구 필터가 없다.
5. Cloudflare named Tunnel + FastMCP 게이트웨이: CIMD·DCR·S256·RFC 9207을 광고하고(2026-10-22 시제품), 소유자 확인과 도구 허용 목록을 한 곳에서 강제한다. 대신 게이트웨이 코드, 비밀값 세 개, 약 105 MiB 메모리(arm64 측정)를 치른다.

## 결정

1. 웹 커넥터는 선택 기능 `BM_WEB`(기본 꺼짐)이고 `BM_ACCESS`와 독립이다. 켜면 compose 프로필 `web`의 `gateway`와 `tunnel`의 `cloudflared`가 뜬다(로컬에서는 `gateway`만).
2. VM 노출 규칙: 모든 컨테이너 포트는 `127.0.0.1`에만 게시하고, Tailscale Funnel은 쓰지 않으며, 접속 방식이 요구하는 것 밖의 인바운드 방화벽 규칙을 더하지 않는다. 공개 경로는 `BM_WEB=on`일 때의 Cloudflare 호스트명 하나이고, `cloudflared`가 나가는 연결을 통해 게이트웨이에만 닿는다.
3. `cloudflared`는 게이트웨이와만 네트워크를 공유한다. Basic Memory와 SilverBullet에는 직접 닿지 못한다.
4. 게이트웨이는 FastMCP로 만들고, GitHub OAuth로 로그인한 한 사람(바뀌지 않는 숫자 id)만 통과시킨다. 클라이언트의 `Authorization`을 Basic Memory로 넘기지 않는다. 도구는 허용 목록으로 열고 `delete_note`·`create_memory_project`·`delete_project`는 넣지 않는다. claude.ai Research 모드가 승인 없이 도구를 부르기 때문이다.
5. 게이트웨이는 digest로 고정한 공식 Python 이미지에서 해시 고정 의존성으로 돌린다. 직접 만든 이미지를 레지스트리에 올리지 않는다.
6. 이번 범위는 claude.ai다. ChatGPT는 플랜 조건(Plus는 문서에 없음)과 `offline_access` 요구 때문에 따로 정한다.

## 결과

- 웹(claude.ai, 같은 계정의 Desktop·모바일 커넥터)에서 노트를 읽고 쓰고 고칠 수 있다. 삭제와 프로젝트 관리는 기존 경로(Claude Code, SilverBullet)로 한다. VM 방화벽과 두 접속 방식은 그대로다.
- 보안 경계가 네트워크에서 신원(GitHub 한 명)과 도구 허용 목록으로 옮겨 가고, 그 둘을 게이트웨이 한 프로세스가 강제한다. 노트는 Cloudflare edge를 평문으로 지나간다.
- 인증 없는 OAuth 요청(등록, 인가 시작)도 게이트웨이 저장소에 파일을 남긴다. 게이트웨이의 주기적 정리(`cull()`), Cloudflare rate limit, `make status`의 저장소 크기, 런북의 비우기 절차로 다룬다(설계 §3.4).
- 비밀값이 다섯 개가 된다(GitHub client secret, 게이트웨이 키, 터널 토큰 추가). 도메인 비용(연 약 $10~11)과 Cloudflare·GitHub 계정 설정이 생긴다. Basic Memory를 올릴 때마다 허용 목록을 다시 본다.
- 1GB VM에 약 105 MiB가 더해진다. 24시간 관찰에서 OOM이나 스왑 포화가 오면 대안 4로 다시 정한다.
- 확인 방법:
  - `tests/repo-config.bats`의 웹 서비스 구조 테스트(`cloudflared` 포트 미게시, 네트워크 격리, 헤더 미전달, 허용 목록, 의존성 해시)
  - `BM_WEB=on`일 때 `make local-verify`의 게이트웨이 동작 테스트(다른 사용자 거절, 막은 도구, `Authorization` 미전달)
  - `BM_WEB=on`일 때 `make verify`의 공개 URL 검사(401과 `resource_metadata`, 메타데이터, 등록 거절)
  - 운영 런북의 Exposure audit
