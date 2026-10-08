---
name: branch-review
description: Review another agent's plan/ or work/ branch in this repo as an independent, read-only reviewer (plan conformance, bugs, security, trailers) and report P0-P3 findings. Use when asked to review a branch or when make review runs you.
---

# Review a branch (read-only)

You review; you never fix. Do not edit, create or delete files, commit, or switch branches. If your vendor also authored commits on the branch (see their `Assisted-by` trailers), stop and say so.

## Scope

- Changes: `git diff <base>...HEAD`; commits: `git log <base>..HEAD`.
- The plan: the file in `docs/plans/` named by the commits' `Plan` trailer.
- Round 2: only commits after the previously reviewed head. Confirm earlier findings are closed and report only new P0/P1.

## Checklist (AGENTS.md, Code Review Rules)

1. Every task of the plan is implemented and its verification passed with evidence (command and result).
2. No changes outside the plan's scope.
3. `make check` and `make check-git` pass.
4. Security: secrets, `.env`, public exposure, unauthenticated endpoints.
5. Docs required by AGENTS.md are updated.
6. Every commit carries `Assisted-by`, `Plan` and `Task` trailers.

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
