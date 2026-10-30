---
status: accepted
id: bts7gsex
date: 2026-10-30
---

# ADR bts7gsex: Basic Memory의 의미 검색을 끄고 0.23.2에 고정한다

- 설계: [agent-memory-mirror 스펙](../specs/spec-2026-10-22-at2p2mw9-agent-memory-mirror.md) §3.3
- 관련: [VM 크기 ADR](adr-2026-10-12-mdq5exsf-vm-sizing.md)

## 맥락과 문제

- 서버는 1 GB e2-micro VM(공유 코어, 부트 디스크 pd-standard 30 GB)에서 Basic Memory 0.23.2를 기본 설정(의미 검색 켜짐)으로 돌린다.
- 기억 미러의 첫 동기화(2026-10-28)가 서버를 세 번 멈췄고, 두 번은 재시작해야 했다. 쓰기 속도 조절(PR #33: 실행마다 10개, 쓰기 사이 3초. PR #34: 5개, 쓰기 요청 90초)로는 풀리지 않았다.
- **Verified (2026-10-29, 진단):** 쉬는 동안 Basic Memory의 상주 메모리는 약 45 MiB이고 스왑은 약 629 MB였다. 노트 5개짜리 실행을 한 번 보내자 첫 2분은 스왑에서 메모리를 다시 읽었다(초당 0.6~2 MB, IO 대기 약 49%). 그다음 약 3.5분은 CPU가 바빴고 쓰기 두 개가 각각 90초 동안 응답하지 않았다.
- **Verified (Google 문서):** pd-standard는 읽기 0.75 IOPS/GiB, 0.12 MiB/s/GiB다. 30 GB면 읽기 약 22 IOPS, 3.6 MiB/s다.
- **Verified (Basic Memory 0.23.2 소스):** `BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED=false`이면 쓰기 뒤 vector sync를 예약하지 않는다(`knowledge_router.py:148`). 임베딩 모델도 올리지 않는다. `search_notes`의 기본 `search_type`은 `text`가 되고, `hybrid`·`vector`를 지정하면 결과 대신 꺼져 있다는 안내가 돌아온다(`mcp/tools/search.py:46-58`).
- **Reported:** 0.24.0(PR #1696)은 이 스위치를 없애 의미 검색이 항상 켜진다. 새 노트를 만들 때 비슷한 노트를 vector로 찾는 단계도 더한다(#1259).
- 1 GB VM에 맞는 다국어 임베딩 모델은 없어서(스펙 §2), 한국어 기억을 의미 검색으로 찾는 품질도 원래 기대하기 어려웠다.

## 검토한 대안

1. 서버의 의미 검색을 끄고 text 검색을 쓴다: 비용이 없고, 쓰기마다 하는 vector 작업과 모델 메모리가 없어진다. 동의어나 다른 언어로 묻는 검색을 잃고, 스위치가 있는 0.23.2에 묶인다.
2. 미러 노트에만 `embed: false`를 넣는다: 다른 노트의 의미 검색은 남는다. 모델은 다른 노트와 검색어 임베딩에 여전히 올라오고, 이 키의 동작은 확인하지 못했다(Reported).
3. VM을 키운다(e2-small 약 $12/월, e2-medium 약 $24/월, Reported): 의미 검색이 남는다. 무료 등급을 벗어나고 클라우드 변경이 필요하다.
4. 디스크를 pd-balanced로 바꾼다(30 GB 약 $3/월, Reported): 스왑 읽기만 빨라지고 쓰기마다 드는 CPU는 그대로다. 디스크를 다시 만들어야 한다.

## 결정

1. Basic Memory 서버의 의미 검색을 끈다. `compose.yaml`의 basic-memory 서비스에 `BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED: "false"`를 둔다.
2. 이 저장소의 `search_notes` 호출과 에이전트 안내는 `search_type: "text"`를 명시하고, 필요하면 `title`·`permalink` 조회와 `metadata_filters`를 쓴다. `hybrid`·`vector`는 안내하지 않는다.
3. Basic Memory는 이 스위치가 있는 0.23.2에 고정한다. 새 버전으로 올리기 전에 `bm-upgrade` 스킬에서 그 버전이 의미 검색 끄기를 지원하는지 확인하고, 지원하지 않으면 올리지 않고 이 결정을 다시 연다.
4. 의미 검색은 VM 메모리를 늘리거나 text 검색으로 찾지 못하는 일이 쌓일 때, 이 ADR을 대체하는 새 ADR로 다시 켠다.

## 결과

- 좋아지는 것: 쓰기 뒤의 vector sync와 임베딩 모델 메모리가 없어진다. 서버가 멈추는 일이 줄 것으로 본다(Assumption: 배포 뒤 재측정으로 확인한다).
- 치르는 것: 낱말이 다른 질문(동의어, 한국어 질문으로 영어 노트 찾기)은 찾지 못한다. 에이전트는 검색어를 노트의 언어와 낱말로 골라야 한다. 0.24.0 이후의 수정(보안 수정 포함)을 받으려면 이 결정을 다시 봐야 한다.
- 확인 방법: `compose.yaml`의 그 값과 bats의 `search_type: "text"` 검사. 배포 뒤 `search_notes(search_type="hybrid")`가 꺼져 있다는 안내를 돌려주는지 본다. `make memory-sync` 한 번 동안 `docker stats`·`vmstat`를 진단 때 값과 비교한다.
