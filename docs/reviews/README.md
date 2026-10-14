# Review records

The files here are the review records of branches merged before plan 09; keep them as history and add no new ones. From plan 09 on, the record is the pull request's "Review record" comment. The author keeps the table in the main checkout's `.review-out/<branch-slug>-record.md` and publishes it with `make review-record PR=<number> FILE=<that file>`; `make review-post` posts the raw reports. Policy: `docs/specs/2026-10-13-github-pr-workflow-design.md`, section 8.

## Template

```markdown
| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex <model> | <base sha> | <head sha> | blocked (1 P1) |

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/example.sh:42 | <failure scenario> | fixed <sha> |
```

Status values: `open`, `fixed <sha>`, `rejected <evidence>`, `deferred <human's reason>`.
