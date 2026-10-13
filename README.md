# agent-share-poc: Basic Memory on GCP + Tailscale

여러 기기의 코딩 에이전트(Codex, Claude Code, Antigravity)가 같은 기억을 쓰도록, Basic Memory MCP 서버를 GCP 무료 등급 e2-micro VM에 올리고 Tailscale tailnet 안에서만 접근하게 만드는 저장소입니다.

- 설계: [docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md](docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md)
- 구조: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 결정 기록: [basic-memory-on-gcp-tailscale ADR](docs/decisions/adr-2026-10-12-m4yy1sb7-basic-memory-on-gcp-tailscale.md), [vm-sizing ADR](docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md)
- 에이전트 지침: [AGENTS.md](AGENTS.md)

## 사전 요구사항 (Prerequisites)

- macOS + Docker Desktop (실행 중이어야 함), `make`
- `ssh`, `curl`, `nc`, `git` (macOS 기본 포함)와 `jq` (`brew install jq`)
- 교차 리뷰(`make review`)를 쓸 때만: 리뷰어 CLI인 `codex` 또는 `claude`
- VM 작업용:
  - Tailscale 앱 설치·로그인과 `tailscale` 명령(`tailscale version`으로 확인, [accounts 런북](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md))
  - Google Cloud SDK(`gcloud`)와 개인 계정용 설정 `bm-personal` ([accounts 1단계](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md)). 스크립트는 gcloud를 쓰지 않고 런북의 사람 작업에만 씁니다.

## 빠르게 시작하기

```bash
make help                          # 전체 타깃
make check                         # lint + 테스트 + 커버리지
make local-up local-verify         # 로컬 컨테이너로 MCP 왕복 확인
make local-down
```

`local-up`은 고정된 컨테이너 이름과 포트를 쓰므로 한 번에 한 작업 트리에서만 실행합니다.

테스트는 불변식, 데이터 안전, 대표 성공 경로, 조용한 실패, Git 정책을 지키는 것만 둡니다. 기준은 [test-scope ADR](docs/decisions/adr-2026-10-13-a878ypj5-test-scope.md)에 있습니다.

## VM 구축 순서

VM이나 클라우드 자원을 바꾸는 명령(`vm-bootstrap`, `deploy`, `restore`, gcloud 명령)은 사람이 승인한 뒤에만 실행합니다. `.env`와 `backups/`는 main 체크아웃에만 둡니다(`git worktree remove`가 worktree 안의 git ignore 파일을 경고 없이 지우기 때문입니다).

1. [계정 준비](docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md): GCP 프로젝트·Budget 알림·gcloud `bm-personal`, Tailscale, 정책. Tailscale 인증 키는 부트스트랩 직전에 발급합니다(accounts 5단계, 만료 1일).
2. [VM 만들기](docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md): e2-micro, us-west1-b, Ubuntu 26.04 Minimal, pd-standard 30GB, 방화벽 정리, `default-allow-ssh`를 내 IP/32로 제한
3. [부트스트랩](docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md): `make vm-bootstrap` → `ssh ubuntu@agent-hub true` 확인 → `default-allow-ssh` 삭제 → `make deploy verify status`
4. [운영](docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md): 백업, 복원, 업그레이드, 정지된 VM 시작, 비용 점검

## 에이전트용 스킬

`.agents/skills/`(Claude Code는 `.claude/skills/` 링크)에 스킬이 있습니다: `bm-upgrade`(이미지 업그레이드), `bm-recover`(VM 정지·삭제·손상 후 복구), `bm-diagnose`(읽기 전용 진단), `git-workflow`, `branch-review`, `skill-authoring`(스킬 추가·수정 규칙). 어떤 상황에 어떤 스킬을 쓰는지는 `AGENTS.md`의 `## Skills`에 있고, 구조 규칙은 `tests/skills.bats`가 검사합니다([skill-structure ADR](docs/decisions/adr-2026-10-13-m0xvj6rr-skill-structure.md)).

## 범위 밖 (다음 목표)

에이전트별 MCP 연결 설정, 자동 백업, `personal-context` GitHub 정본 연동, 회사용 별도 인스턴스
