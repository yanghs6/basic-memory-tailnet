---
name: branch-review
description: Reviews another agent's plan/ or work/ branch in this repo as an independent, read-only reviewer (plan conformance, bugs, security, trailers) and reports P0-P3 findings. Use when asked to review a branch or check whether it is mergeable, or when make review runs you. Not for fixing findings or reviewing your own branch (the author does that through git-workflow).
---

# Review a branch (read-only)

You review; you never fix. Do not edit, create or delete files, commit, or switch branches. If your vendor also authored commits on the branch (see their `Assisted-by` trailers), stop and say so, unless your prompt says the human set `REVIEW_ALLOW_SAME_VENDOR=1`. Then review anyway and write `Same-vendor review allowed by the human` on the line after the verdict, so the review record notes it.

## Scope

- Changes: `git diff <base>...HEAD`; commits: `git log <base>..HEAD`.
- The plan: the file in `docs/plans/` named by the commits' `Plan` trailer.
- Round 2: only commits after the previously reviewed head. Confirm earlier findings are closed and report only new P0/P1.

## Checklist (AGENTS.md, Code Review Rules)

1. Every task of the plan is implemented and its verification passed with evidence (command and result).
2. No changes outside the plan's scope.
3. The plan's Progress log records a passing `make check`, the PR body's Verification records passing CI (`check`, `pr-rules`), and `scripts/check-git.sh origin/main <branch>` passes. If you cannot run scripts, read the trailers at the end of each message in `git log origin/main..<branch>`.
4. Security: secrets, `.env`, public exposure, unauthenticated endpoints.
5. Docs required by AGENTS.md are updated.
6. Every commit carries `Assisted-by`, `Plan` and `Task` trailers, and the pull request body ends with `Assisted-by` and `Plan` (the squash commit message).

## Severity

| Level | Meaning | Merge |
|---|---|---|
| P0 | data loss, security, outage | blocks |
| P1 | bug or unmet requirement | blocks |
| P2 | maintainability | fix or human-deferred |
| P3 | minor | optional |

## Output

First line: `Verdict: mergeable` or `Verdict: blocked (<n> P0/P1)`.
Then one finding per line: `[P1] scripts/restore.sh:42 - <failure scenario> - <suggested fix>`.
Report only problems these changes introduce. No style nits, no speculation without a concrete scenario, always cite path:line.
