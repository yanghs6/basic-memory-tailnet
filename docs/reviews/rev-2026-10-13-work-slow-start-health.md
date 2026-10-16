# Review: work/slow-start-health

Cross-vendor review per `docs/specs/spec-2026-10-07-git-review-policy.md`, section 5. Author: claude-code (Claude Opus). Reviewer: codex, run with `make review BRANCH=work/slow-start-health REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 43771b1 (main) | 65567da | mergeable; no findings in the change review or the plan review |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| — | — | — | No findings. | — |

## Notes

- Scope: plan 05 found on the e2-micro VM (Progress log, 2026-10-13) that the container took 161s after the first deploy and 192s after a reboot to start listening, turned `unhealthy` once after the reboot (`start_period: 60s`, `interval: 30s`, `retries: 3`), and that `docker compose up --wait` fails at once on an unhealthy container (reproduced locally with compose 5.0.2). So `make deploy` and `make restore` (and its rollback) could fail on a cold start. This branch raises the healthcheck `start_period` to 300s and `HEALTH_TIMEOUT_SECONDS` to 360s (65567da). Plan 05 itself stays on `plan/05-vm-rollout`; the fix is split out as the plan asks.
- Verified: the raw reports are `.review-out/work-slow-start-health-r1-codex-diff.md` ("이번 변경에서 새로 발생한 동작 결함은 발견하지 못했습니다") and `.review-out/work-slow-start-health-r1-codex-plan.md` ("Verdict: mergeable"). Codex could not run the tests (no Docker in its sandbox), and its git policy check failed only because the review checkout is a detached HEAD.
- Test evidence from the author: RED (the new start_period test failed with "start_period 60s is below 240s"), then `make check` passed with 222 tests and 97.97% line coverage, `make local-up local-verify local-down` passed (healthy at once locally, two MCP round trips OK), and `make check-git` reported "OK: git policy (1 commits since main)".
- Four existing assertions that pin the timeout value (`tests/vm_ops.bats`, `tests/backup_restore.bats`) moved from 180 to 360 with the constant; they check the same behavior.
- Still to verify on the VM after the merge: `make deploy` with the new compose and the time to healthy (plan 05).
