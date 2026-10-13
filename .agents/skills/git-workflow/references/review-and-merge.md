# Review and merge

The phases after the last task commit, in order. Policy: docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md, sections 5 and 6.

## Hand off for review

1. Move a finished plan to `docs/plans/completed/` (commit with `Task: none`).
2. Ask the other vendor to review; never review your own branch:
   - you are Claude Code: `make review BRANCH=<branch> REVIEWER=codex` (runs `codex exec review` with `-c 'sandbox_mode="read-only"'`; never use a writable sandbox)
   - you are Codex, Antigravity or Gemini: `make review BRANCH=<branch> REVIEWER=claude`
3. `make review` starts `codex` or `claude`, which need network access: run it where they can reach the network, outside the sandbox of the agent that calls it. If your sandbox blocks the network, ask the human to run the command.
4. `make review` logs the exact report paths. The raw reviews are in the main checkout's `.review-out/` (`<main checkout>/.review-out/<branch-slug>-r<round>-<reviewer>-diff.md` and `-plan.md`), not in your worktree. Copy the findings into `docs/reviews/<branch-slug>.md` using `docs/reviews/README.md`, and commit with `Task: review`.

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
4. After the merge, the human cleans up. `git worktree remove` deletes ignored files such as `backups/` and `.env` without any warning, so first run `ls <your worktree>/backups <your worktree>/.env` and move any archive into the main checkout's `backups/` (never overwrite a file there), then run `git worktree remove <your worktree>` and `git branch -d <branch>`.
