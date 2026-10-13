# Review: plan/06-test-pruning

Cross-vendor review per `docs/specs/2026-10-07-git-review-policy-design.md`, section 5. Author: claude-code (Claude Opus as controller, Claude Sonnet as task implementers). Reviewer: codex, run by the human with `make review BRANCH=plan/06-test-pruning REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 5561329 (main) | 3ecc423 (now fb54cdb, same tree) | mergeable; change review found no behavior defects, plan review 1 P2 |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P2 | docs/plans/completed/2026-10-13-06-test-pruning.md:369 | Commit 747d2c7 fixes the in-plan task finding SDD-T2-F1 (a merged test had dropped the "BM_VM_PUBLIC_IP must be the VM's public IPv4" assertion) but lacks the required `Review-Finding: SDD-T2-F1` trailer, so `git log` cannot link the finding to its fix. | fixed ac9429c (the human approved a one-time history rewrite on 2026-10-13 as an exception to the AGENTS.md rule; 747d2c7 became ac9429c with the trailer, trees unchanged) |

## Notes

- Scope: the bats suite went from 237 to 148 tests (63 deleted, 26 merged into representative tests). Criteria and the lost coverage lines are in `docs/decisions/0004-test-scope.md`. No file under `scripts/`, the Makefile, `compose.yaml`, the skills or AGENTS.md changed.
- Verified: the raw reports are `.review-out/plan-06-test-pruning-r1-codex-diff.md` ("계획에 따른 테스트 삭제·병합과 문서 변경에서 새 동작 결함을 발견하지 못했습니다", git policy check passed for all 9 commits) and `.review-out/plan-06-test-pruning-r1-codex-plan.md` ("Verdict: mergeable" with R1-F1). Codex could not rerun `make check` (no Docker in its sandbox).
- Test evidence from the author: `make check` 148 ok, 0 not ok, line coverage 96.96% (baseline 237 ok, 97.97%); `make check-git` "OK: git policy (9 commits since main)".
- In-plan reviews before this one (subagent-driven development): each of Tasks 1-4 had a separate verification agent that reran `make check`; the Task 2 verification found SDD-T2-F1 (fixed in ac9429c). The final whole-branch review (Claude Opus) found one Important (SDD-final-I1: the deleted "rejects an unknown reviewer" test was the only guard on the reviewer allowlist at `scripts/review.sh:49`) and Minors M1-M6; 686ea6a fixed I1, M1-M4 and M6, and a scoped re-review passed. M5 is R1-F1 above.
- History rewrite (Verified, 2026-10-13): to fix R1-F1 the human approved rewriting this branch once. Only messages and parents changed: 747d2c7→ac9429c, 400196e→8a472a1, c02cc62→686ea6a, 3ecc423→fb54cdb, 75f2f57→8871863. The human ran the rewrite script, which checked `git diff --quiet` for every pair before moving the branch; afterwards `git diff --stat 75f2f57 HEAD` was empty and `make check-git` passed. So the reviewed head 3ecc423 and fb54cdb hold the same tree, and the merge message names fb54cdb. The branch was never pushed (no remote).
