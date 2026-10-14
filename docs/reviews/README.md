# Review records

The files here are the review records of branches merged before the [review-posting plan](../plans/plan-2026-10-13-znbc3ase-review-posting.md); keep them as history and add no new ones. From the review-posting plan on, the record is the pull request's "Review record" comment. The author keeps the table in `.review-out/<branch-slug>-record.md` in the main checkout (or in your own worktree if your tool cannot write outside it; `.review-out/` is git-ignored there too) and publishes it with `make review-record PR=<number> FILE=<that file>`; `make review-post` posts the raw reports. Policy: `docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md`, section 8.

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
