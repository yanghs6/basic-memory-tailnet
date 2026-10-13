---
name: git-workflow
description: Git workflow for agent work in this repo, from the first file change to the merge (own worktree, plan/NN-slug or work/slug branch, commit trailers, cross-vendor review, review fixes, merge message). Use whenever you are about to change files or commit here, ask for a review, fix review findings or prepare a merge.
---

# Agent git workflow

Policy: docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md. Never commit to `main`, force-push, rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.

## Start

1. Your identity is the literal trailer value `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model id>`, for example `Assisted-by: codex gpt-6.1-sol`. Write it out in every commit command: your shell may not keep exported variables between commands, and an empty trailer can only be repaired by rewriting history.
2. Work in your own worktree on your own branch: one agent per worktree, one worktree per branch, never the main checkout.
   - Claude Code: start with `claude --worktree <slug>` (it creates `.claude/worktrees/<slug>`), then `git branch -m plan/NN-slug` or `git branch -m work/slug`.
   - Codex app: the app already runs you in a detached worktree under `$CODEX_HOME/worktrees`; run `git switch -c plan/NN-slug` (or `work/slug`) there.
   - Codex CLI, Gemini CLI, Antigravity: they can write only inside the directory they were started in. From any directory of this repo, create the worktree next to the main checkout:
     `git -C "$(git rev-parse --path-format=absolute --git-common-dir)/.." worktree add ../027_agent_share_poc-wt/<slug> -b plan/NN-slug main`
     Then end this session and start the tool again inside that directory (`codex -C <dir>`, `cd <dir> && gemini`, or open the folder in Antigravity); `git worktree list` shows its absolute path.
3. For a plan, make the first commit move the plan file from `docs/plans/backlog/` to `docs/plans/active/`.
4. For work that belongs to no plan (an upgrade, a fix, a doc change), use a `work/<slug>` branch and write `Plan: none` and `Task: none` in every commit.

## Commit

1. Run `make check`.
2. `git commit -m "<type>: <description>" --trailer "Assisted-by: <tool> <model id>" --trailer "Plan: <NN|none>" --trailer "Task: <N|review|none>"`, with your identity written out. If you keep it in a variable, set it in the same command and write `${AGENT_ID:?set AGENT_ID}`, so an unset value stops the commit instead of writing an empty trailer.
3. Never add `Co-authored-by` or `Signed-off-by`.
4. Before asking for review, `make check-git` must pass.

## Review and merge

When the branch is ready for review, read [references/review-and-merge.md](references/review-and-merge.md) and follow it in order: hand off for review, fix findings, prepare the merge (only the human merges) and clean up. Read it again before each of those phases; never review your own branch.
