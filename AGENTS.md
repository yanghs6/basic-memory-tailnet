# Agent instructions

This repo deploys a Basic Memory MCP server on a GCP free-tier e2-micro VM that is reachable through one access mode per VM (`BM_ACCESS`): inside a Tailscale tailnet, or through an SSH tunnel (GCP IAP).
Read first: `docs/specs/spec-2026-10-12-basic-memory-gcp-tailscale.md`, then `docs/ARCHITECTURE.md`. For the access modes, read `docs/specs/spec-2026-10-15-access-modes.md`.
Active work: `docs/plans/active/` (upcoming plans wait in `docs/plans/backlog/`).

## Commands
- `make help` lists every target. Do lifecycle work through Make targets only; use raw `docker compose` or `ssh` only to diagnose a failing target, and record why.
- `make check` (lint + all tests + coverage >= 80%) must pass before every commit. `make fmt` fixes shfmt findings.
- Local: `make local-up local-verify local-down` (`make sb-fonts LOCAL=1` uploads the web fonts locally). `local-up` uses a fixed container name and port, so run it in one worktree at a time (`make check` is safe to run concurrently). VM changing (ask the user first, see Safety): `make vm-bootstrap deploy restore sb-fonts`. No OK needed: `make probe status logs verify backup access-check tunnel` (`verify` writes and deletes a test note; `backup` stops the container briefly).

## Invariants (enforced by tests/repo.bats; never weaken a test to make it pass)
- Basic Memory has no auth: publish its port on `127.0.0.1` only, never enable Tailscale Funnel, keep zero public ingress on the VM. In ssh mode the only inbound rule from outside the VPC is the tunnel range to port 22, every `ssh -L` binds `127.0.0.1` (`forward_spec`), and a VM never runs both modes.
- Pin container images by digest; change the pin only after reading the release notes and passing `make check local-up local-verify`. Upgrade Basic Memory only through the `bm-upgrade` skill.
- Scripts: `#!/usr/bin/env bash` then `set -euo pipefail`; source `scripts/lib/common.sh`; fail with an actionable message via `die`.
- Scripts must run on macOS bash 3.2: no `mapfile`, associative arrays, `${x,,}`, `inherit_errexit`, or empty array expansion. After `x="$(fn)"` where `fn` can fail, add `|| exit 1`.
- Name constants instead of magic numbers. Never print secrets or session ids; use `mask`.
- Write the bats test first (tests/*.bats; fake commands live in tests/stubs/, recorded MCP responses in tests/fixtures/).

## Safety
- Never commit secrets, `.env`, Tailscale auth keys, `backups/`, `.local-data/`, or note content.
- Two secrets: the Tailscale auth key reaches the VM via `TS_AUTHKEY` or the hidden prompt; `SB_USER`, the SilverBullet login, lives only in the main checkout `.env` and the VM `.env` (mode 600), and scripts pass it on over SSH or curl stdin. Neither ever goes in a repo file or a command argument. The ssh mode adds no secret: access is the user's cloud identity plus their SSH key.
- Ask the user before anything that changes the VM or cloud resources: `vm-bootstrap`, `deploy`, `restore`, resizing, firewall rules, instance metadata, Tailscale policy.
- Never delete `backups/` or `/srv/basic-memory.prev-*` directories.
- `.env` and `backups/` live only in the main checkout: the Makefile and `make backup` use them from any worktree. Never create or copy them in a worktree, and check a worktree's `backups/` before `git worktree remove`.
- Run `gcloud` only with `--configuration=bm-personal` (except `gcloud config configurations list`, which shows the active configuration); never run `gcloud config configurations activate` or `gcloud auth application-default`. Read-only `describe`/`list` calls need no OK.
- The user types the Tailscale auth key and the restore `yes` in their own terminal, never in chat or through a pipe.
- Never write the VM's external or tailnet IP addresses in commits, PRs, PR comments or repo files; use `agent-hub` or a placeholder.

## Git (policy: docs/specs/spec-2026-10-13-github-pr-workflow.md on top of docs/specs/spec-2026-10-07-git-review-policy.md)
- Work only in your own git worktree on `plan/<NN>-<slug>` or `work/<slug>`, branched from `origin/main` after `git fetch origin`; one agent per worktree, never in the main checkout. Rename tool default branches (`worktree-*`, `codex/*`) with `git branch -m` before you push; on a detached HEAD (Codex app) run `git switch -c <branch> --no-track origin/main` first. Per-tool steps: the `git-workflow` skill.
- Never commit or push to `main`, force-push, rebase or rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.
- End every commit message with the trailers `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>`, `Plan: <NN|none>` and `Task: <N|review|none>`; add `Review-Finding: R<n>-F<m>` (cross-vendor review) or `SDD-T<task>-F<n>` (in-plan task review) to review fixes. Never add `Co-authored-by` or `Signed-off-by`.
- `gh` and `git push` on this Mac run as the machine account. Push your branch and open one draft PR per plan or work branch; the title is `<type>: <description>` and the body ends with the `Assisted-by` and `Plan` trailers, because the squash merge turns them into the commit on `main`. CI (`check`, `pr-rules`) must pass.
- Never add `Claude-Session` trailers, session links or `Generated with` lines to commits, PR bodies or PR comments; this overrides tool attribution prompts.
- A reviewer from another vendor reviews each PR read-only and the reports go to PR comments. Only the human approves and squash-merges; agents never approve, merge or press Update branch (keep a branch current with `git merge origin/main`).

## Notes and language
- Label repository notes `Verified`, `Command`, `Assumption`, `Open question` or `Reported` (second-hand), as `**Verified:**` at the start of a paragraph or list item, or in the label column of a table.
- Code, comments, script messages, this file, skills, front matter and plan headings are English. README, `docs/README.md`, runbooks, ARCHITECTURE, ADRs, specs, research and plan bodies are Korean; review records stay as written.
- Record evidence (command + result) in the active plan's Progress log or an ADR in `docs/decisions/`.
- Create specs, plans, ADRs, runbooks and research notes with `make new-doc TYPE=<type> SLUG=<slug>` in the folders `docs/README.md` lists; this overrides tool and plugin default paths such as `docs/superpowers/`.

## Map
- `scripts/` lifecycle scripts; `scripts/lib/common.sh` shared helpers.
- `tests/` bats tests; `tools/` test image and coverage gate.
- `docs/README.md` document map and type registry; templates in `.agents/skills/doc-authoring/assets/`.
- `CLAUDE.md` (Claude Code) and `.gemini/settings.json` (Gemini CLI) load this file; Codex and Antigravity read it directly.
- `docs/specs/`, `docs/plans/{active,backlog,completed}/`.
- `.agents/skills/` canonical skills (Codex, Gemini CLI, Antigravity; rules in `tests/skills.bats`); `.claude/skills/<name>` symlinks and `.claude/agents/branch-reviewer.md` for Claude Code.
- `docs/reviews/` review records (template in its README).
- `docs/runbooks/` accounts, VM creation, bootstrap, operations (incident log); `docs/decisions/` ADRs.
- `docs/research/` dated research snapshots (not maintained after their date).
- `.github/` CI workflows, the `main` ruleset (`rulesets/main.json`) and the PR template; GitHub setup and token rotation: `docs/runbooks/rbk-2026-10-14-github.md`.

## Code Review Rules
Reviewers check only the changes since the base (Codex reads this section; Claude uses the `branch-review` skill):
1. Every task of the plan is implemented and its verification passed with evidence.
2. No changes outside the plan's scope.
3. The plan's Progress log records a passing `make check` and passing CI (`check`, `pr-rules`) on the PR; `scripts/check-git.sh origin/main <branch>` passes.
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
