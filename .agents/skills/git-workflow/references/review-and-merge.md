# Review and merge

The phases after the last task commit, in order. Policy: docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md, sections 8 and 9.

## Review

1. Move a finished plan to `docs/plans/completed/` (commit with `Task: none`) and push.
2. Ask the other vendor to review; never review your own branch:
   - you are Claude Code: `make review BRANCH=<branch> REVIEWER=codex` (runs `codex exec review` with `-c 'sandbox_mode="read-only"'`; never use a writable sandbox)
   - you are Codex, Antigravity or Gemini: `make review BRANCH=<branch> REVIEWER=claude`
   The base is `origin/main`.
3. `make review` starts `codex` or `claude`, which need network access: run it where they can reach the network, outside the sandbox of the agent that calls it. If your sandbox blocks the network, ask the human to run the command.
4. Post both raw reports to the pull request: `make review-post PR=<PR> BRANCH=<branch> REVIEWER=<reviewer> REVIEW_MODEL=<reviewer model>` (add `ROUND=<n>` from round 2). It posts two comments headed by the round, the reviewer and model, and the base and reviewed head SHAs that `make review` recorded. Before posting, check both reports for the VM's IP addresses and session ids and mask them, because the pull request is public.
5. Keep the findings table in `.review-out/<branch-slug>-record.md` in the main checkout (or in your own worktree if your tool cannot write outside it; `.review-out/` is git-ignored there too) (format: docs/reviews/README.md) and publish it with `make review-record PR=<PR> FILE=<that file>`. Run it again after every status change: it updates the same "Review record" comment.

## Fix findings

1. Verify each finding before acting: reproduce it or cite the code. Mark unfounded ones `rejected <evidence>`.
2. Fix accepted findings one commit each, with `--trailer "Review-Finding: R<round>-F<n>"`, push, and set their status to `fixed <sha>`.
3. If anything changed, run round 2 on the new commits only: `make review BRANCH=<branch> REVIEWER=<same> ROUND=2 REVIEW_BASE=<reviewed head sha>`, and post it with `make review-post ... ROUND=2`. If you merged `origin/main` after the reviewed head, run `git fetch origin` and use `REVIEW_BASE=origin/main` instead, because a range across the merge pulls `main`'s commits into the review. After round 2, leave any remaining disagreement to the human.

## Keep the branch current

When GitHub says the branch is out of date with `main` (the required checks are strict):

1. `git fetch origin`, then `git merge origin/main` and resolve any conflicts. Never rebase or force-push.
2. `make check`, then push. The push dismisses the approval and re-runs CI.
3. If resolving conflicts changed code after the review, say what changed in a pull request comment and have the other vendor review the pull request again against the new `main`: `git fetch origin`, then `make review BRANCH=<branch> REVIEWER=<same> ROUND=<next> REVIEW_BASE=origin/main`. A `<previous head>..` range would include the commits that came in from `main`.
4. The human never presses Update branch: the last push must come from the machine account, or the human cannot approve it (last-push approval in the ruleset).

## Hand the pull request to the human

1. Check: CI passes; the Review record has no open P0/P1; every deferred P2 carries the human's reason.
2. Run `gh pr ready <PR>` and tell the human the pull request number. The human approves and squash-merges; never merge yourself.

## Clean up

After `gh pr view <PR> --json state` shows `MERGED`:

1. `git worktree remove` deletes ignored files such as `backups/` and `.env` without any warning, so first run `ls <your worktree>/backups <your worktree>/.env` and move any archive into the main checkout's `backups/` (never overwrite a file there), then run `git worktree remove <your worktree>` and `git branch -D <branch>` (`-d` refuses a squash-merged branch). GitHub deletes the remote branch.
2. The human updates the main checkout with `git pull --ff-only`.
