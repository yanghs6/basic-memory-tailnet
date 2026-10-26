---
name: git-workflow
description: Git workflow for agent work in this repo, from the first file change to the human's squash merge (own worktree from origin/main, plan/ID-slug or work/slug branch, commit trailers, draft pull request as the machine account, cross-vendor review, review fixes, hand-off). Use whenever you are about to change files, commit or push here, open a pull request, ask for a review, fix review findings or hand a pull request to the human.
---

# Agent git workflow

Policy: docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md (pull requests, review, merge) on top of docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md (branches, worktrees, trailers). Never commit or push to `main`, force-push, rebase or rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree. Never approve or merge a pull request.

## Start

1. Your identity is the literal trailer value `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model id>`, for example `Assisted-by: codex gpt-6.1-sol`. Write it out in every commit command: your shell may not keep exported variables between commands, and an empty trailer can only be repaired by rewriting history.
2. Run `git fetch origin` (it needs the network; if your sandbox blocks it, ask the human to run it), then work in your own worktree on your own branch from `origin/main`: one agent per worktree, one worktree per branch, never the main checkout. For a plan, <ID> and <slug> are the plan file's id and slug (`plan-<date>-<ID>-<slug>.md`).
   - Claude Code: start with `claude --worktree <slug>` (it creates `.claude/worktrees/<slug>` from `origin/main`), then `git branch -m plan/<ID>-<slug>` or `git branch -m work/slug`.
   - Codex app: the app already runs you in a detached worktree under `$CODEX_HOME/worktrees`; run `git switch -c plan/<ID>-<slug> --no-track origin/main` (or `work/slug`) there.
   - Codex CLI, Gemini CLI, Antigravity: they can write only inside the directory they were started in. From any directory of this repo, create the worktree next to the main checkout:
     `git -C "$(git rev-parse --path-format=absolute --git-common-dir)/.." worktree add --no-track -b plan/<ID>-<slug> ../027_agent_share_poc-wt/<slug> origin/main`
     Then end this session and start the tool again inside that directory (`codex -C <dir>`, `cd <dir> && gemini`, or open the folder in Antigravity); `git worktree list` shows its absolute path. If Gemini CLI asks whether to trust the folder, trust it: with folder trust on (off by default), an untrusted folder ignores `.gemini/settings.json`, so Gemini CLI would not read `AGENTS.md`.
3. For a plan, first check that nobody runs it already. `main` keeps a plan at `backlog` until its pull request merges, so the in-progress signal is the pushed branch: after `git fetch origin`, `git branch -r --list 'origin/plan/<ID>-*'` must print nothing. If it prints a branch, the plan is in progress on another machine or tool: stop and tell the human. Then make the first commit change the plan's front matter `status` from `backlog` to `active` (`doc-authoring`) and push it at once (Publish, step 1), so others see the branch.
4. For work that belongs to no plan (an upgrade, a fix, a doc change), use a `work/<slug>` branch and write `Plan: none` and `Task: none` in every commit.

## Commit

1. Run `make check`.
2. `git commit -m "<type>: <description>" --trailer "Assisted-by: <tool> <model id>" --trailer "Plan: <ID|none>" --trailer "Task: <N|review|none>"`, with your identity written out. If you keep it in a variable, set it in the same command and write `${AGENT_ID:?set AGENT_ID}`, so an unset value stops the commit instead of writing an empty trailer.
3. Never add `Co-authored-by` or `Signed-off-by`.
4. `make check-git` (it checks against `origin/main`) must pass before you push.

## Publish

1. After the first commit run `git push -u origin <branch>`, then open one draft pull request for the whole branch: `gh pr create --draft --base main --title "<type>: <description>" --body-file <file>`. The body follows `.github/pull_request_template.md`: summary, plan file, verification evidence, and as the last paragraph `Assisted-by: <tool> <model id>` (one line per tool that worked on the branch) and `Plan: <ID|none>`. Replace the template's example text; the squash merge turns the title and body into the commit on `main`. Write each paragraph and each list item on one line: GitHub shows every line break in a pull request body, so text wrapped at a fixed width reads as broken sentences.
2. Push after every commit. CI runs `check` (`make check`) and `pr-rules` (branch name, commit trailers, PR title and trailers). Fix every failure; editing the title or body re-runs `pr-rules`.
3. `gh` and `git push` run as the machine account. If your sandbox blocks the network, ask the human to run the push or `gh` command.
4. Never write the VM's external or tailnet IP addresses in commits, the pull request or comments.
5. Never add `Claude-Session` trailers, session links or `Generated with` lines to commits, PR bodies or PR comments; this overrides tool attribution prompts.

## Review and merge

When the plan's tasks are done, read [references/review-and-merge.md](references/review-and-merge.md) and follow it in order: review, fix findings, keep the branch current, hand the pull request to the human, clean up. Read it again before each of those phases; never review your own branch.
