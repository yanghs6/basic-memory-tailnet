# agent-share-poc: Basic Memory on OCI + Tailscale

여러 기기의 코딩 에이전트(Codex, Claude Code, Antigravity)가 같은 기억을 쓰도록, Basic Memory MCP 서버를 OCI Always Free VM에 올리고 Tailscale tailnet 안에서만 접근하게 만드는 저장소입니다.

- 설계: [docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md](docs/specs/spec-2026-10-07-p7h3jvpf-basic-memory-oci-tailscale.md)
- 구조: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 결정 기록: [basic-memory-on-oci-tailscale ADR](docs/decisions/adr-2026-10-12-b229z2y6-basic-memory-on-oci-tailscale.md), [vm-sizing ADR](docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)
- 에이전트 지침: [AGENTS.md](AGENTS.md)

## 사전 요구사항 (Prerequisites)

- macOS + Docker Desktop (실행 중이어야 함), `make`
- `ssh`, `curl`, `nc`, `git` (macOS 기본 포함)와 `jq` (`brew install jq`)
- 교차 리뷰(`make review`)를 쓸 때만: 리뷰어 CLI인 `codex` 또는 `claude`
- VM 작업용: 이 Mac에 Tailscale 앱 설치·로그인 ([accounts 런북](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md))

## 빠르게 시작하기

```bash
make help                          # 전체 타깃
make check                         # lint + 테스트 + 커버리지
make local-up local-verify         # 로컬 컨테이너로 MCP 왕복 확인
make local-down
```

`local-up`은 고정된 컨테이너 이름과 포트를 쓰므로 한 번에 한 작업 트리에서만 실행합니다.

## VM 구축 순서

VM이나 클라우드 자원을 바꾸는 명령(`vm-bootstrap`, `deploy`, `restore`)은 사람이 승인한 뒤에만 실행합니다.

1. [계정 준비](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md): OCI, Tailscale, 정책, 인증 키
2. [VM 만들기](docs/runbooks/rbk-2026-10-12-vebvx40g-oci-vm.md): A1.Flex, Ubuntu 24.04, 임시 22번 규칙
3. [부트스트랩](docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md): `make vm-bootstrap` → `ssh ubuntu@bm-node true` 확인 → 22번 규칙 삭제 → `make deploy verify status`
4. [운영](docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md): 백업, 복원, 업그레이드, 유휴 회수 대응

## 에이전트용 스킬

`.agents/skills/`(Claude Code는 `.claude/skills/` 링크)에 운영 스킬이 있습니다: `bm-upgrade`(이미지 업그레이드), `bm-recover`(VM 회수 후 복구), `bm-diagnose`(읽기 전용 진단), `git-workflow`, `branch-review`.

## 범위 밖 (다음 목표)

에이전트별 MCP 연결 설정, 자동 백업, `personal-context` GitHub 정본 연동, 회사용 별도 인스턴스
