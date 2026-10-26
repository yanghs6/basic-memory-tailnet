---
status: final
id: aqjax47t
---

# Review: work/workflow-alignment

Cross-vendor review per `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`, section 5. Author: claude-code (Claude Opus). Reviewer: codex, run with `make review BRANCH=work/workflow-alignment REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | c10fb5c (main) | bdf852b | plan review: mergeable; change review: 2 P2 |
| R2 | codex gpt-6.1-sol (sandbox read-only) | bdf852b (R1 head) | 32cc27f | plan review: mergeable; change review: no findings |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P2 | docs/plans/plan-2026-10-13-k93wjt1a-github-switch.md:860-861 | Says the check-run lookup must use the PR's merge SHA because `pull_request` check runs attach to it, not to the head SHA. | rejected: on the public `cli/cli` PR #14650 (2026-10-13) the head SHA 94c5a6f has 19 check runs, among them the `github-actions` app (id 15368), and the merge SHA cec90ef has 0; recorded in ca155f0 |
| R1-F2 | P2 | docs/plans/plan-2026-10-13-znbc3ase-review-posting.md:411-412 | On a public repo anyone can post a comment that starts with `<!-- review-record -->`; the planned search would pick it up, then PATCH someone else's comment or stop on a false duplicate. | fixed 5d05c76 |

## Notes

- Scope: documents only. The branch adds the research report (`docs/research/rsch-2026-10-13-djx2fzm5-agent-oss-git-strategies.md`), the GitHub pull-request workflow spec (`docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md`), the [github-switch](../plans/plan-2026-10-13-k93wjt1a-github-switch.md) and [review-posting](../plans/plan-2026-10-13-znbc3ase-review-posting.md) plans in `docs/plans/backlog/`, and one `AGENTS.md` Map line. No script, test or Make target changes; the code inside the plans runs only when the plans are executed (TDD).
- Verified: the raw reports are `.review-out/work-workflow-alignment-r1-codex-diff.md` and `.review-out/work-workflow-alignment-r1-codex-plan.md` ("Verdict: mergeable"). Codex said it ran the git policy check (passed) but neither `make check` nor anything on GitHub.
- The first `make review` attempt was cut off mid-run (no process left; an empty `-diff.md.partial` and the review worktree stayed behind). The human removed the stale worktree; the second run, started in the background, completed.
- Test evidence from the author: `make check` exit 0 after every commit on the branch, and `make check-git` "OK: git policy (7 commits since main)" at bdf852b.
- Verified: R2 ran with `make review BRANCH=work/workflow-alignment REVIEWER=codex ROUND=2 REVIEW_BASE=bdf852b` on the three commits after bdf852b. The raw reports are `.review-out/work-workflow-alignment-r2-codex-diff.md` (no new defects; the author filter and login check for R1-F2 are adequate) and `-r2-codex-plan.md` ("Verdict: mergeable"). Codex ran the git policy check ("OK: git policy (3 commits since review-base/work-workflow-alignment-r2)") and a diff whitespace check, not `make check`.
- R1-F2 changes the [review-posting plan](../plans/plan-2026-10-13-znbc3ase-review-posting.md) Task 2: `review-record.sh` reads the gh login (`gh api user`) and matches only that account's marker comments, stops when the login is empty, and the stub and tests cover both.
