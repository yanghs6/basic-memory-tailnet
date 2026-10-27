# Agent instructions

This repo deploys a Basic Memory MCP server on a GCP free-tier e2-micro VM that is reachable through one access mode per VM (`BM_ACCESS`): inside a Tailscale tailnet, or through an SSH tunnel (GCP IAP).
Read first: `docs/specs/spec-2026-10-12-p5nmsc4m-basic-memory-gcp-tailscale.md`, then `docs/ARCHITECTURE.md`. For the access modes, read `docs/specs/spec-2026-10-15-jr59pvyf-access-modes.md`.
Plans: `docs/plans/`; each plan's front matter `status` says backlog, active, completed or dropped. `main` shows `active` only after a plan's pull request merges, so a pushed `origin/plan/<ID>-*` branch means that plan is already in progress (`git-workflow`, Start).

## Commands
- `make help` lists every target. Do lifecycle work through Make targets only; use raw `docker compose` or `ssh` only to diagnose a failing target, and record why.
- `make check` (lint + all tests + coverage >= 80%) must pass before every commit. `make fmt` fixes shfmt findings.
- Local: `make local-up local-verify local-down` (`make sb-fonts LOCAL=1` uploads the web fonts locally). `local-up` and `local-down` refuse a stack that another worktree started; run `make local-down` there first (`make check` is safe to run concurrently). VM changing (ask the user first, see Safety): `make vm-bootstrap deploy restore sb-fonts`. No OK needed: `make probe status logs verify backup access-check tunnel` (`verify` writes and deletes a test note; `backup` stops the container briefly).

## Invariants (never weaken a test to make it pass; a pull request that removes or skips tests carries `Tests-Removed: <reason>` in its trailer paragraph)
- Basic Memory has no auth: publish every port on `127.0.0.1` only, never enable Tailscale Funnel, and add no inbound firewall rule beyond the access mode's own (none for tailscale, the tunnel range to port 22 for ssh). The only public path is the optional web connector (`BM_WEB=on`): `cloudflared` dials out and reaches only the OAuth gateway, which admits one GitHub account (by numeric id) and lists only allowed tools. In ssh mode the only inbound rule from outside the VPC is the tunnel range to port 22, every `ssh -L` binds `127.0.0.1` (`forward_spec`), and a VM never runs both modes.
- Pin container images by digest; change the pin only after reading the release notes and passing `make check local-up local-verify`. Upgrade Basic Memory only through the `bm-upgrade` skill.
- Scripts: `#!/usr/bin/env bash` then `set -euo pipefail`; source `scripts/lib/common.sh` or a `scripts/lib/` library that sources it (scripts in `scripts/remote/` run alone on the VM and source none); fail with an actionable message via `die`.
- Scripts must run on macOS bash 3.2: no `mapfile`, associative arrays, `${x,,}`, `inherit_errexit`, or empty array expansion. After `x="$(fn)"` where `fn` can fail, add `|| exit 1`.
- Name constants instead of magic numbers. Never print secrets or session ids; use `mask`.
- Write the bats test first: `tests/<name>.bats` for `scripts/<name>.sh`, `tests/remote-<name>.bats` and `tests/lib-<name>.bats` for `scripts/remote/` and `scripts/lib/` (`make new-script` creates both); fake commands live in tests/stubs/, recorded responses in tests/fixtures/<test name>/.
- `make check` and CI `pr-rules` check these rules where a check can see them; the rules no check can see, and why, are listed in docs/decisions/adr-2026-10-27-0svs72hp-prose-only-invariants.md.

## Safety
- Never commit secrets, `.env`, Tailscale auth keys, `backups/`, `.local-data/`, or note content.
- Five secrets: the Tailscale auth key reaches the VM via `TS_AUTHKEY` or the hidden prompt; `SB_USER` (the SilverBullet login) and the web connector's `BM_WEB_GITHUB_CLIENT_SECRET`, `BM_WEB_JWT_KEY` and `BM_WEB_TUNNEL_TOKEN` live only in the main checkout `.env` and the VM `.env` (mode 600), and scripts pass them on over SSH or curl stdin. None ever goes in a repo file, output or command argument. The ssh mode adds no secret: access is the user's cloud identity plus their SSH key.
- Ask the user before anything that changes the VM or cloud resources: `vm-bootstrap`, `deploy`, `restore`, resizing, firewall rules, instance metadata, Tailscale policy.
- Never delete `backups/` or `/srv/basic-memory.prev-*` directories.
- `.env` and `backups/` live only in the main checkout: the Makefile and `make backup` use them from any worktree. Never create or copy them in a worktree, and check a worktree's `backups/` before `git worktree remove`.
- Run `gcloud` only with `--configuration=bm-personal` (except `gcloud config configurations list`, which shows the active configuration); never run `gcloud config configurations activate` or `gcloud auth application-default`. Read-only `describe`/`list` calls need no OK.
- The user types the Tailscale auth key and the restore `yes` in their own terminal, never in chat or through a pipe.
- Never write the VM's external or tailnet IP addresses in commits, PRs, PR comments or repo files; use `agent-hub` or a placeholder. `make check`, `check-git` and `pr-rules` enforce this with `scripts/check-public-text.sh`; only recorded evidence and must-fail fixtures go in `.public-text-exemptions` (path and kind, never the value).

## Git (policy: docs/specs/spec-2026-10-13-pr762r68-github-pr-workflow.md on top of docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md)
- Work only in your own git worktree on `plan/<ID>-<slug>` (`<ID>` is the plan document's id, the 8 characters in its file name) or `work/<slug>`, branched from `origin/main` after `git fetch origin`; one agent per worktree, never in the main checkout. Rename tool default branches (`worktree-*`, `codex/*`) with `git branch -m` before you push; on a detached HEAD (Codex app) run `git switch -c <branch> --no-track origin/main` first. Per-tool steps: the `git-workflow` skill.
- Never commit or push to `main`, force-push, rebase or rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.
- End every commit message with the trailers `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>`, `Plan: <ID|none>` and `Task: <N|review|none>`; add `Review-Finding: R<n>-F<m>` (cross-vendor review) or `SDD-T<task>-F<n>` (in-plan task review) to review fixes. Never add `Co-authored-by` or `Signed-off-by`.
- `gh` and `git push` on this Mac run as the machine account. Push your branch and open one draft PR per plan or work branch; the title is `<type>: <description>` and the body ends with the `Assisted-by` and `Plan` trailers, because the squash merge turns them into the commit on `main`. CI (`check`, `pr-rules`) must pass.
- Never add `Claude-Session` trailers, session links or `Generated with` lines to commits, PR bodies or PR comments; this overrides tool attribution prompts. `scripts/check-public-text.sh` checks commit messages, PR text and review posts for them.
- A reviewer from another vendor reviews each PR read-only and the reports go to PR comments. Only the human approves and squash-merges; agents never approve, merge or press Update branch (keep a branch current with `git merge origin/main`).

## Notes and language
- Label repository notes `Verified`, `Command`, `Assumption`, `Open question` or `Reported` (second-hand), as `**Verified:**` at the start of a paragraph or list item, or in the label column of a table.
- Code, comments, script messages, this file, skills, front matter and plan headings are English. README, `docs/README.md`, runbooks, ARCHITECTURE, ADRs, specs, research and plan bodies are Korean; review records stay as written.
- Record evidence (command + result) in the active plan's Progress log, or on a work branch in the PR body's Verification; record decisions in an ADR in `docs/decisions/`. The pull request's CI results go in its body (Verification), which needs no commit.
- Create specs, plans, ADRs, runbooks and research notes with `make new-doc TYPE=<type> SLUG=<slug> [ID=<id>]` in the folders `docs/README.md` lists; every document gets a random 8-character id (`make new-id` prints one); this overrides tool and plugin default paths such as `docs/superpowers/`.
- Pre-approval drafts of specs, plans and ADRs live on the Basic Memory draft board (`doc-authoring`), not in the repo.

## Map
- `scripts/` lifecycle scripts named `<verb>-<object>.sh`; `scripts/lib/` shared helpers by topic, each with a function index at the top; `scripts/remote/` runs on the VM.
- `tests/` one bats file per script plus `repo-*.bats` for repo-wide rules; `tools/` test image and coverage gate.
- `docs/README.md` document map and type registry; templates in `.agents/skills/doc-authoring/assets/`.
- `CLAUDE.md` (Claude Code) and `.gemini/settings.json` (Gemini CLI) load this file; Codex and Antigravity read it directly.
- `docs/specs/`, `docs/plans/` (state in front matter).
- `.agents/skills/` canonical skills (Codex, Gemini CLI, Antigravity; rules in `tests/repo-skills.bats`); `.claude/skills/<name>` symlinks and `.claude/agents/branch-reviewer.md` for Claude Code.
- `docs/reviews/` review records (template in its README).
- `docs/runbooks/` accounts, VM creation, bootstrap, operations (incident log); `docs/decisions/` ADRs.
- `docs/research/` dated research snapshots (not maintained after their date).
- `.github/` CI workflows, the `main` ruleset (`rulesets/main.json`) and the PR template; GitHub setup and token rotation: `docs/runbooks/rbk-2026-10-14-ppmby9v6-github.md`.

## Code Review Rules
Reviewers check only the changes since the base (Codex reads this section; Claude uses the `branch-review` skill):
1. Every task of the plan is implemented and its verification passed with evidence.
2. No changes outside the plan's scope.
3. The plan's Progress log records a passing `make check`, the PR body's Verification records passing CI (`check`, `pr-rules`), and `scripts/check-git.sh origin/main <branch>` passes.
4. Security: secrets, `.env`, public exposure, unauthenticated endpoints.
5. Docs required by this file are updated.
6. Every commit carries the Git trailers, and the PR body ends with the `Assisted-by` and `Plan` trailers.
Severity: P0 data loss, security or outage and P1 bug or unmet requirement block the merge; P2 maintainability is fixed or deferred by the human with a reason; P3 is optional.
Each finding: `[Pn] path:line - failure scenario - suggested fix`. Report only problems these changes introduce; no style nits.

## Skills
Load the matching skill before you act; when two match, use both.
- Changing files, committing, asking for review, fixing findings or preparing a merge: `git-workflow`.
- Reviewing another agent's branch (read-only): `branch-review`.
- Updating, bumping, patching or rolling back the Basic Memory image: `bm-upgrade`.
- VM stopped, deleted or unusable, or notes to restore onto a new VM (a stopped VM is only started): `bm-recover`.
- Basic Memory unreachable, `make probe` or `make verify` failing, container or VM unhealthy (read-only): `bm-diagnose`.
- Writing a spec, plan, ADR, runbook or research note, changing a document's status, or adding a document type: `doc-authoring`.
- Adding, renaming or editing a skill: `skill-authoring`.
- Adding or changing a script, a library, a Make target, a bats test, a stub or a fixture: `script-authoring`.
