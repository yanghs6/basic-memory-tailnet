---
name: doc-authoring
description: Creates and updates this repo's documents (spec, plan, ADR, runbook, research note) from the type registry in docs/README.md and this skill's templates with make new-doc. Use when writing a new spec, plan, ADR, runbook or research note, changing a document's status (approved, active, completed, superseded), superseding or amending a document, deciding where labels and evidence go, or adding a document type. Not for skills (use skill-authoring) or review records, which are PR comments (use branch-review).
---

# Create and update repository documents

Every agent creates documents the same way from repo files alone. The type registry, the table under "문서 타입" in `docs/README.md`, holds each type's code, number, folder, status values, required front matter keys and template. Read it instead of guessing, and change it instead of working around it.

## Rules

- Create a new document only with `make new-doc TYPE=<type> SLUG=<slug>`. Never copy a neighboring document: older documents predate the templates and spread old formats.
- Write documents only in the folders the registry lists. Repo rules override tool and plugin default paths such as `docs/superpowers/`.
- Never rewrite evidence (commands, output, SHAs, dates, measurements), the decision sentences of an accepted ADR or the user decisions of a spec. Add new facts after them instead.
- Fill every `{{...}}` blank or delete its line before you commit.

## Create a document

1. Pick the type in `docs/README.md` ("타입 고르는 법").
2. Run `git fetch origin`, then `make new-doc TYPE=<type> SLUG=<slug>` in your worktree. Numbered types (plan, adr) take the number after the largest one on every local and remote-tracking branch, so fetch first. The slug is lowercase words joined by single hyphens. The command prints the new path.
3. Fill the template in Korean; plan headings stay English:
   - spec: [assets/spec.md](assets/spec.md)
   - plan: [assets/plan.md](assets/plan.md)
   - ADR: [assets/adr.md](assets/adr.md)
   - runbook: [assets/runbook.md](assets/runbook.md)
   - research note: [assets/research.md](assets/research.md)
4. Commit it through `git-workflow`.

## Front matter and status

- Front matter keys are lowercase English: `status`, `date`, `spec`, `reviewed`, `superseded-by`, `amended-by` (meanings in `docs/README.md`, "메타데이터"). Use no other keys.
- Change `status` in the commit that causes the change, and set `date` (spec, ADR) or `reviewed` (runbook) to that day:
  - spec: `draft`, then `approved` when the user approves it.
  - plan: `backlog` when written, `active` in the first commit of the plan branch, `completed` when every task is done and before the review, or `dropped` with a one-line reason under the title.
  - ADR: `proposed`, then `accepted`; later `superseded` or `deprecated`.
  - runbook: `reviewed` is the day you last followed the steps or checked them against the system.
- To replace a document, write the new one (its "대체 범위" line says what it replaces) and, in the same commit, give the old one `status: superseded` and `superseded-by: <path>`, or `amended-by: <path>` when only part changes.
- Until plan 14 merges, older documents keep their old names and have no front matter, and old-name plans still move between `docs/plans/backlog/`, `active/` and `completed/` as `git-workflow` says. Do not rename them by hand: plan 14 does.

## Labels and evidence

- In Korean documents, start a statement about outside systems, the environment or tool behavior with a label: `**Verified:**` (you checked it), `**Command:**` (what you ran), `**Assumption:**` (not checked), `**Open question:**` (for a human), `**Reported:**` (second-hand). In a table, put only the label in the 표기 column. Add a date when it matters: `**Verified (2026-10-16):**`.
- Record evidence (command and result) in the active plan's Progress log (`| 날짜 | 표기 | 내용 |`) or in an ADR.
- Name repo files by relative link or by repo path in backticks. Write example paths of files that do not exist only inside code blocks.

## Add a document type

1. First check whether an existing type fits. Add a type only for a new folder or a new lifecycle (status values).
2. In one pull request: a registry row with an unused 3-4 letter code, a template `assets/<type>.md` named in this SKILL.md, and a line in `AGENTS.md` if agents need it. `make new-doc` reads the registry, so no code changes.
3. Record the reason in an ADR when the status values are a lifecycle no other type has.
4. To retire a type, set its `새 문서` cell to `금지`: new files are refused and old ones stay.

## Gotchas

- `make new-doc` sees only the branches you have fetched; a number another agent pushed after your last fetch can collide. If your pull request shows a duplicate number, rename your file with `git mv` and update its references.
- `tests/repo.bats` checks the relative links of every tracked Markdown file and every docs Markdown path named in skills, even inside code blocks, so templates and this skill name only files that exist.
