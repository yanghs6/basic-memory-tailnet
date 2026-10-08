# Review records

One file per reviewed branch: `docs/reviews/<branch-slug>.md`, for example `rev-2026-10-08-tscgvpsz-git-review-tooling.md`. The author agent writes it from the raw reviewer output in `.review-out/` and commits it with `Task: review`. Policy: `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`, section 5.

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
