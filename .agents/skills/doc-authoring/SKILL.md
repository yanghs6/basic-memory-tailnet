---
name: doc-authoring
description: Creates and updates this repo's documents (spec, plan, ADR, runbook, research note) from the type registry in docs/README.md and this skill's templates with make new-doc. Use when writing a new spec, plan, ADR, runbook or research note, drafting a spec, plan or ADR on the Basic Memory draft board, changing a document's status (approved, active, completed, superseded), superseding or amending a document, deciding where labels and evidence go, or adding a document type. Not for skills (use skill-authoring) or review records, which are PR comments the author keeps (use git-workflow).
---

# Create and update repository documents

Every agent creates documents the same way from repo files alone. The type registry, the table under "문서 타입" in `docs/README.md`, holds each type's code, folder, status values, required front matter keys and template. Read it instead of guessing, and change it instead of working around it.

## Rules

- Create a new document only with `make new-doc TYPE=<type> SLUG=<slug> [ID=<id>]`. Every document has a random 8-character id (characters `0123456789abcdefghjkmnpqrstvwxyz`) in its file name (`<code>-<YYYY-MM-DD>-<id>-<slug>.md`) and in its front matter `id`. Never copy a neighboring document: older documents predate the templates and spread old formats.
- Write documents only in the folders the registry lists. Repo rules override tool and plugin default paths such as `docs/superpowers/`.
- Never rewrite evidence (commands, output, SHAs, dates, measurements), the decision sentences of an accepted ADR or the user decisions of a spec. Add new facts after them instead.
- Fill every `{{...}}` blank or delete its line before you commit.

## Create a document

1. Pick the type in `docs/README.md` ("타입 고르는 법").
2. Run `git fetch origin`, then `make new-doc TYPE=<type> SLUG=<slug>` in your worktree. The command picks an id that no local or remote-tracking branch and no document uses, so fetch first. Pass `ID=<id>` to reuse the id of an approved draft (see "Draft board"). The slug is lowercase words joined by single hyphens. The command prints the new path.
3. Fill the template in Korean; plan headings stay English:
   - spec: [assets/spec.md](assets/spec.md)
   - plan: [assets/plan.md](assets/plan.md)
   - ADR: [assets/adr.md](assets/adr.md)
   - runbook: [assets/runbook.md](assets/runbook.md)
   - research note: [assets/research.md](assets/research.md)
4. Commit it through `git-workflow`.

## Draft board

Before approval, a spec, plan or ADR is a draft note on the Basic Memory draft board, not a file in the repo. The repo document is created only after the user approves the draft. Use the `basic-memory` MCP tools (`search_notes`, `write_note`, `read_note`); the project is `main`.

- Path and title: `agent-drafts/<project key>/<code>-<id>-<slug>`.
  - Project key: `git remote get-url origin` normalized to `<owner>-<repo>` (lowercase, `.git` and host removed, other characters to `-`); this repo is `yanghs6-basic-memory-tailnet`.
  - Device name: `$BM_MEMORY_DEVICE` if set, else `hostname -s` in lowercase.
- Front matter (`metadata` of `write_note`):

  | key | value |
  |---|---|
  | `draft` | `true` |
  | `project` | the project key |
  | `id`, `type`, `slug` | what the repo document will get |
  | `status` | `drafting`, `review`, `approved` or `dropped` |
  | `owner` | `<device>/<agent>`, for example `mac-work/claude-code` |
  | `branch` | the linked branch, empty if none |
  | `areas` | the repo paths or directories the document touches |
  | `updated` | ISO date; change it on every edit |
  | `repo_path`, `pr` | set after approval |

Flow:

1. Before you write a spec, plan or ADR, or change an existing document substantially, list the board: `search_notes(metadata_filters={"project": "<key>", "draft": true})`. If a draft overlaps in `areas` or slug, tell the user.
2. `make new-id` prints the id. `write_note` creates the draft without `overwrite`; start the body from the type's template.
3. The user reads it in SilverBullet; approval is given in the conversation.
4. After approval run `make new-doc TYPE=<type> SLUG=<slug> ID=<same id>`, move the body in, run `make check`, commit, push and open the draft PR. Then set `status: approved`, `repo_path` and `pr` on the note. From then on the repo document is the source of truth.
5. A change to an existing document made outside a plan execution branch goes up as a note with `type: change`, `areas` and a summary of the change.

Write rules:

- Only the `owner` writes a draft. Other agents read it and tell the user about any overlap.
- The owner runs `read_note` before every edit, merges what the user changed in SilverBullet, then writes with `overwrite`.
- Drafts have no expiry (no `expires` key). Tell the user about a draft whose `updated` is old; delete a note only after the user approves.
- If the tunnel is down (`ECONNREFUSED`), ask the user to run `make tunnel` and wait. Do not write the draft to a local file: that would create two sources of truth. Id uniqueness does not depend on the board, so file names stay safe.

## Front matter and status

- Front matter keys are lowercase English: `id`, `status`, `date`, `spec`, `reviewed`, `superseded-by`, `amended-by` (meanings in `docs/README.md`, "메타데이터"). Use no other keys.
- Change `status` in the commit that causes the change, and set `date` (spec, ADR) to that day:
  - spec: `draft`, then `approved` when the user approves it.
  - plan: `backlog` when written, `active` in the first commit of the plan branch, `completed` when every task is done and before the review, or `dropped` with a one-line reason under the title.
  - ADR: `proposed`, then `accepted`; later `superseded` or `deprecated`.
  - runbook: `reviewed` is the day you last followed the steps or checked them against the system.
- To replace a document, write the new one (its "대체 범위" line says what it replaces) and, in the same commit, give the old one `status: superseded` and `superseded-by: <path>`, or `amended-by: <path>` when only part changes.

## Labels and evidence

- In Korean documents, start a statement about outside systems, the environment or tool behavior with a label: `**Verified:**` (you checked it), `**Command:**` (what you ran), `**Assumption:**` (not checked), `**Open question:**` (for a human), `**Reported:**` (second-hand). In a table, put only the label in the 표기 column. Add a date when it matters: `**Verified (2026-10-16):**`.
- Record evidence (command and result) in the active plan's Progress log (`| 날짜 | 표기 | 내용 |`), or on a work branch in the PR body's Verification; record decisions in an ADR. The PR's CI results go in the PR body's Verification.
- Name repo files by relative link or by repo path in backticks. Write example paths of files that do not exist only inside code blocks.

## Add a document type

1. First check whether an existing type fits. Add a type only for a new folder or a new lifecycle (status values).
2. In one pull request: a registry row with an unused 3-4 letter code, a template `assets/<type>.md` named in this SKILL.md, and a line in `AGENTS.md` if agents need it. `make new-doc` reads the registry, so no code changes. Copy an existing row and change every cell: a row has exactly ten cells and none is empty (write `없음` for no number or no template), for example:

   ```markdown
   | memo | memo | 없음 | `docs/memos/` | draft, final | status, date | 허용 | 기록 | 한국어 | `.agents/skills/doc-authoring/assets/memo.md` |
   ```
3. Record the reason in an ADR when the status values are a lifecycle no other type has.
4. To retire a type, set its `새 문서` cell to `금지`: new files are refused and old ones stay.

## Gotchas

- `make new-doc` and `make new-id` see only the branches you have fetched; an id is random, so a collision is unlikely, but `make check` fails if two documents share an id. Rename the newer one with `git mv`, change its `id` and update its references.
- `tests/repo-docs.bats` checks the relative links of every tracked Markdown file and every docs Markdown path named in skills (even inside code blocks) and in other Markdown outside code, so templates and this skill name only files that exist.
