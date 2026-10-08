---
name: git-workflow
description: Start, commit, hand off for review and prepare the merge of agent work in this repo (plan/NN-slug or work/slug branches in their own worktree, commit trailers, review fixes). Use whenever you are about to change files or commit here.
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

## Commit

1. Run `make check`.
2. `git commit -m "<type>: <description>" --trailer "Assisted-by: <tool> <model id>" --trailer "Plan: <NN|none>" --trailer "Task: <N|review|none>"`, with your identity written out. If you keep it in a variable, set it in the same command and write `${AGENT_ID:?set AGENT_ID}`, so an unset value stops the commit instead of writing an empty trailer.
3. Never add `Co-authored-by` or `Signed-off-by`.
4. Before asking for review, `make check-git` must pass.

## Hand off for review

1. Move a finished plan to `docs/plans/completed/` (commit with `Task: none`).
2. Ask the other vendor to review; never review your own branch:
   - you are Claude Code: `make review BRANCH=<branch> REVIEWER=codex` (runs `codex exec review` with `-c 'sandbox_mode="read-only"'`; never use a writable sandbox)
   - you are Codex, Antigravity or Gemini: `make review BRANCH=<branch> REVIEWER=claude`
3. `make review` logs the exact report paths. The raw reviews are in the main checkout's `.review-out/` (`<main checkout>/.review-out/<branch-slug>-r<round>-<reviewer>-diff.md` and `-plan.md`), not in your worktree. Copy the findings into `docs/reviews/<branch-slug>.md` using `docs/reviews/README.md`, and commit with `Task: review`.

## Fix findings

1. Verify each finding before acting: reproduce it or cite the code. Mark unfounded ones `rejected <evidence>`.
2. Fix accepted findings one commit each, with `--trailer "Review-Finding: R<round>-F<n>"`, and set their status to `fixed <sha>`.
3. If anything changed, run round 2 on the new commits only: `make review BRANCH=<branch> REVIEWER=<same> ROUND=2 REVIEW_BASE=<reviewed head sha>`. After round 2, leave any remaining disagreement to the human.

## Prepare the merge (only the human merges)

Follow the spec, section 6, in this order:

1. Check the record: no open P0/P1, and every deferred P2 carries the human's reason.
2. Check the head: `git log --oneline <reviewed head>..<branch>` lists only the recorded fix and review-record commits, where `<reviewed head>` is the head of the last review round. `make check` and `make check-git` pass.
3. Write the merge message to the main checkout's `.review-out/merge-<branch-slug>.txt`, next to the raw reviews (if your sandbox cannot write there, use another path and give it to the human):

   ```
   Merge <branch>

   Reviewed-by: <human>
   Review-Agent: <reviewer tool> <model>
   Review-Record: docs/reviews/<branch-slug>.md
   Reviewed-Head: <head of the last review round>
   ```

   Ask the human to run, from the main checkout: `git merge --no-ff <branch> -F .review-out/merge-<branch-slug>.txt` (or the path you gave).
4. After the merge, the human cleans up: `git worktree remove <your worktree>` and `git branch -d <branch>`.
