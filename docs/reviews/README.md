# Review records

The files here are the review records of branches merged before the [review-posting plan](../plans/plan-2026-10-13-znbc3ase-review-posting.md); keep them as history and add no new ones. From the review-posting plan on, the record is the pull request's "Review record" comment. The author keeps the table in `.review-out/<branch-slug>-record.md` of their own worktree (`.review-out/` is git-ignored there) and publishes it with `make review-record PR=<number> FILE=<that file>`; `make review-post` posts the raw reports. In a worktree session, run `make review` and `make review-post` with `REVIEW_OUT_DIR=<your worktree>/.review-out` so the raw reports land there too (`.agents/skills/git-workflow/references/review-and-merge.md`, Review step 5). Policy: `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md`, section 8.

## Template

```markdown
## Review record

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex <model> | <base sha> | <head sha> | blocked (1 P1) |

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/example.sh:42 | <failure scenario> | fixed <sha> |
```

Status values: `open`, `fixed <sha>`, `rejected <evidence>`, `deferred <human's reason>`.
