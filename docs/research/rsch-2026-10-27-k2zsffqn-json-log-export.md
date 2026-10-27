---
status: snapshot
id: k2zsffqn
---

# 모든 서비스의 로그를 공통 JSON Lines로 내려받을 수 있는가

- 기준: 2026-10-27 시점의 스냅샷이다. 이후 바뀐 사실은 반영하지 않는다. 저장소 안 사실은 `main` 01eb909 기준이다.
- 표기: 출처 링크가 붙은 문장은 `Verified`(그날 1차 출처에서 확인), 2차 보도는 `Reported`, 추론은 `Assumption`이다.
- 방법: 저장소 파일 읽기, 고정된 이미지 태그의 GitHub 소스, Docker·Cloudflare·Google Cloud 공식 문서, 로컬 `docker logs --help`·`docker compose logs --help`. VM 명령은 실행하지 않았다.
- 사용자 결정(2026-10-27): 목적은 "가능한 모든 애플리케이션에서 공통 JSON 포맷으로 디버깅"이고, 범위는 VM 컨테이너 로그를 Mac으로 내려받는 것이다. 외부 수집처와 스크립트 `log()`는 범위 밖이다.

서비스 설정을 바꾸지 않고도 공통 JSON Lines를 만들 수 있다. ssh로 컨테이너마다 `docker logs -t`를 받아 Mac에서 `{time, service, stream, msg, data}`로 감싸면 된다. 서비스가 직접 JSON을 내게 하는 방법은 basic-memory의 uvicorn 로그와 SilverBullet에는 없어서, 어느 쪽이든 Mac 쪽 정규화가 필요하다.

## 1. 지금은 gateway 감사 로그만 JSON이다

| 출처 | 형식 | 표기 | 근거 |
|---|---|---|---|
| gateway `gateway.audit` | 접두어 없는 JSON 한 줄(stdout), 키 `time`, `user`, `tool`, `note`, `ms` | Verified | `gateway/gateway.py`(01eb909) 210-217행, 264-268행 |
| gateway uvicorn 접근 로그 | 꺼져 있다. `/auth/callback` 쿼리에 GitHub 인가 코드가 실리기 때문이다 | Verified | `gateway/gateway.py`(01eb909) 253-256행 |
| gateway의 나머지 | `boot:` print, pip 출력, fastmcp Rich 텍스트(stderr) | Verified | `gateway/boot.py`(01eb909) 33-34행, [fastmcp logging.py](https://github.com/PrefectHQ/fastmcp/blob/v4.1.3/fastmcp_slim/fastmcp/utilities/logging.py#L42-L90) |
| basic-memory stdout | uvicorn 기본 텍스트. 접근 로그에 client ip:port와 요청줄이 남는다 | Verified | [uvicorn 0.51.0 config.py](https://github.com/encode/uvicorn/blob/0.51.0/uvicorn/config.py#L81-L104) |
| basic-memory 앱 로그 | loguru가 파일에만 쓴다(10 MB 회전, 5개 보관). VM에서는 config 폴더의 `basic-memory.log`이고, 어떤 Make 타깃도 읽지 않는다 | Verified | `docs/ARCHITECTURE.md`(01eb909) 80행, [utils.py](https://github.com/basicmachines-co/basic-memory/blob/v0.23.2/src/basic_memory/utils.py#L411-L463) |
| silverbullet | Rust `tracing_subscriber` 텍스트(stdout) | Verified | [main.rs](https://github.com/silverbulletmd/silverbullet/blob/2.12.1/bin/silverbullet/src/main.rs#L64-L71) |
| cloudflared | zerolog 텍스트(stderr) | Verified | [create.go](https://github.com/cloudflare/cloudflared/blob/2026.10.3/logger/create.go#L187-L188) |

## 2. 서비스가 직접 JSON을 내게 할 수 있는 곳은 일부뿐이다

- basic-memory 0.23.2
  - uvicorn은 `mcp_server.run(..., log_level="INFO")`로 뜨고 `uvicorn_config`를 받지 않는다. 그래서 접근 로그 형식을 바깥에서 바꿀 수 없다(Verified, [mcp.py](https://github.com/basicmachines-co/basic-memory/blob/v0.23.2/src/basic_memory/cli/commands/mcp.py#L121-L128)).
  - 앱 로그 파일은 `LOGURU_SERIALIZE=true`를 주면 loguru 고유 스키마의 JSON이 된다(Verified, [loguru _defaults.py](https://github.com/Delgan/loguru/blob/0.7.3/loguru/_defaults.py#L42)).
  - 파일 sink가 `diagnose=True`라서 예외가 나면 변수 값이 기록된다. 그 안에 노트 내용이 섞일 수 있다(Verified 설정값, Assumption 내용).
- SilverBullet 2.12.1: `tracing-subscriber`의 `json` feature가 빠져 있어 JSON을 낼 수 없다(Verified, [Cargo.toml](https://github.com/silverbulletmd/silverbullet/blob/2.12.1/Cargo.toml#L51)).
- cloudflared 2026.10.3
  - `--logformat`이라는 플래그는 없다. 플래그는 `tunnel --output json`, 환경변수는 `TUNNEL_LOG_OUTPUT=json`이다(Verified, [cliutil/logger.go](https://github.com/cloudflare/cloudflared/blob/2026.10.3/cmd/cloudflared/cliutil/logger.go#L17-L22), [run parameters](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/cloudflared-parameters/run-parameters/)).
  - debug 수준에서는 요청 헤더 전체가 남는다(Verified, 같은 저장소 `proxy/logger.go`).
- gateway(fastmcp 4.1.3, uvicorn 0.54.0): `FASTMCP_LOG_ENABLED=false`와 `uvicorn_config={"log_config": ...}`를 쓰면 stdlib만으로 JSON을 낼 수 있다. 다만 코드를 고쳐야 한다(Verified, [fastmcp settings.py](https://github.com/PrefectHQ/fastmcp/blob/v4.1.3/fastmcp_slim/fastmcp/settings.py#L78-L110), [uvicorn 0.54.0 config.py](https://github.com/encode/uvicorn/blob/0.54.0/uvicorn/config.py#L387-L428)).

## 3. Docker 로그는 JSON으로 출력되지 않지만 stdout과 stderr, 시간을 얻을 수 있다

- json-file 레코드는 `log`, `stream`, `time`(RFC3339Nano)과 선택적인 `attrs`로 이루어진다(Verified, [jsonlog.go](https://raw.githubusercontent.com/moby/moby/master/daemon/logger/jsonfilelog/jsonlog/jsonlog.go), [json-file 문서](https://docs.docker.com/engine/logging/drivers/json-file/)).
- 로그 파일은 root 소유로 보인다(Assumption). Docker 문서는 이 파일을 Docker 데몬만 읽도록 설계했다고 경고한다(Verified, 같은 json-file 문서).
- `docker logs`와 `docker compose logs`에는 `--format`이나 JSON 출력이 없다(Verified, [docker logs 참조](https://docs.docker.com/reference/cli/docker/container/logs/), 로컬 Docker 29.2.1과 Compose v5.0.2의 `--help`).
- `docker compose logs`는 stdout과 stderr를 하나로 합친다. `docker logs`는 둘을 나누어 내고, 회전된 파일까지 읽는다(Verified, docker/compose `pkg/compose/logs.go`, docker/cli `container/logs.go`, moby `loggerutils/logfile.go`).
- VM의 관리 사용자는 docker 그룹에 들어가므로 sudo 없이 `docker logs`를 쓸 수 있다(Verified, `scripts/remote/provision-vm.sh` 104-110행).

## 4. 외부 수집처는 이 VM에 맞지 않는다

- Cloud Logging은 프로젝트당 월 50 GiB까지 무료이고, 그 뒤로는 $0.50/GiB이며, 30일 보관한다(Verified, [가격](https://cloud.google.com/products/observability/pricing)).
- Ops Agent의 Linux 메모리 사용량은 공식 문서에서 찾지 못했다(Verified, [ops-agent](https://docs.cloud.google.com/logging/docs/agent/ops-agent)).
  - 2026-10-27 시험 배포 뒤 e2-micro는 mem 64%, swap 487/1023 MB였다(Reported, 감독 세션).
  - 이런 VM에 상주 에이전트를 더하는 것은 위험하다(Assumption).
- 에이전트 없이 쓰는 `gcplogs` 드라이버도 있다(Verified, [gcplogs](https://docs.docker.com/engine/logging/drivers/gcplogs/)). 다만 노트 메타데이터가 외부로 나가는 경로가 하나 늘어난다.

## 시사점

1. 추천은 A안이다. 새 Make 타깃과 `scripts/export-logs.sh`가 컨테이너마다 `docker logs -t`를 받아 Mac에서 공통 JSONL로 바꾼다. JSON인 줄은 그 내용을 `data`에 그대로 넣는다. VM 배포가 필요 없고 상주 부하도 없다.
2. 사용자 결정(2026-10-27)은 다음과 같다.
   - 출력은 main checkout 안의 gitignore 폴더에 둔다.
   - 기본 범위는 최근 24시간과 실행 중인 서비스 전부다.
   - 서비스가 직접 JSON을 내게 하는 일은 범위에서 빼고 후속 작업으로 둔다.
3. `.gitignore`에 `*.log`나 `logs/` 항목이 없다(Verified, `.gitignore`). 출력 폴더를 무시 목록에 새로 넣어야 한다.
4. 내보낸 파일에 민감할 수 있는 값이 들어갈 수 있다(Assumption, 근거는 위 표와 `docs/specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md` 133-136행).
   - 해당 값: 노트 식별자, GitHub `sub`, client ip:port, Cloudflare edge IP, 검색이 실패했을 때 ERROR 줄에 남는 검색어.
   - 저장소나 PR에 붙이기 전에 `scripts/check-public-text.sh`를 돌려야 한다. 다만 이 스크립트는 노트 제목을 잡지 못한다.
   - basic-memory 앱 로그 파일(`diagnose=True`)은 기본 내보내기 대상에서 뺀다.
5. 기존 `logs`와 `local-logs`는 바꾸지 않는다. 계획 m97w7hqe가 `local-logs` 명령 문자열을 테스트로 고정한다(Verified, `docs/plans/plan-2026-10-22-m97w7hqe-invariant-enforcement.md` 95행).
