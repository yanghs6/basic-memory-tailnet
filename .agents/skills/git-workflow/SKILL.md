---
name: git-workflow
description: Start, commit, hand off for review and prepare the merge of agent work in this repo (plan/NN-slug or work/slug branches in their own worktree, commit trailers, review fixes). Use whenever you are about to change files or commit here.
---

# Agent git workflow

Policy: docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md. Never commit to `main`, force-push, rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.

## Start

1. Set your identity once: `export AGENT_ID="<claude-code|codex|antigravity|gemini-cli> <model id>"`.
2. Work in your own worktree on your own branch: one agent per worktree, one worktree per branch, never the main checkout.
   - Claude Code: start with `claude --worktree <slug>` (or enter a worktree in the session), then `git branch -m plan/NN-slug` or `git branch -m work/slug`.
   - Other tools: `git worktree add ../027_agent_share_poc-wt/<slug> -b plan/NN-slug main`, then work in that directory.
3. For a plan, make the first commit move the plan file from `docs/plans/backlog/` to `docs/plans/active/`.

## Commit

1. Run `make check`.
2. `git commit -m "<type>: <description>" --trailer "Assisted-by: $AGENT_ID" --trailer "Plan: <NN|none>" --trailer "Task: <N|review|none>"`
3. Never add `Co-authored-by` or `Signed-off-by`.
4. Before asking for review, `make check-git` must pass.

## Hand off for review

1. Move a finished plan to `docs/plans/completed/` (commit with `Task: none`).
2. Ask the other vendor to review; never review your own branch:
   - you are Claude Code: `make review BRANCH=<branch> REVIEWER=codex` (runs `codex exec review` with `-c 'sandbox_mode="read-only"'`; never use a writable sandbox)
   - you are Codex, Antigravity or Gemini: `make review BRANCH=<branch> REVIEWER=claude`
3. Copy the findings from `.review-out/` into `docs/reviews/<branch-slug>.md` using `docs/reviews/README.md`, and commit with `Task: review`.

## Fix findings

1. Verify each finding before acting: reproduce it or cite the code. Mark unfounded ones `rejected <evidence>`.
2. Fix accepted findings one commit each, with `--trailer "Review-Finding: R<round>-F<n>"`, and set their status to `fixed <sha>`.
3. If anything changed, run round 2 on the new commits only: `make review BRANCH=<branch> REVIEWER=<same> ROUND=2 REVIEW_BASE=<reviewed head sha>`. After round 2, leave any remaining disagreement to the human.

## Prepare the merge (only the human merges)

1. Check: no open P0/P1, every deferred P2 carries the human's reason, `make check` and `make check-git` pass.
2. Write the merge message to `.review-out/merge-<branch-slug>.txt` in your worktree:

   ```
   Merge <branch>

   Reviewed-by: <human>
   Review-Agent: <reviewer tool> <model>
   Review-Record: docs/reviews/<branch-slug>.md
   Reviewed-Head: <reviewed head sha>
   ```

3. Ask the human to run, from the main checkout: `git merge --no-ff <branch> -F <absolute path of that file>`, then `git worktree remove <your worktree>` and `git branch -d <branch>`.
