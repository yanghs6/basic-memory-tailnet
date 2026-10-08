# Review records

One file per reviewed branch: `docs/reviews/<branch-slug>.md`, for example `plan-02-git-review-tooling.md`. The author agent writes it from the raw reviewer output in the main checkout's `.review-out/` (`make review` logs the exact paths) and commits it with `Task: review`. Policy: `docs/specs/2026-10-07-git-review-policy-design.md`, section 5.

## Template

````markdown
# Review: plan/NN-slug

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex <model> | <base sha> | <head sha> | blocked (1 P1) |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/example.sh:42 | <failure scenario> | fixed <sha> |
````

Status values: `open`, `fixed <sha>`, `rejected <evidence>`, `deferred <human's reason>`.
