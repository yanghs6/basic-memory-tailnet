# Agent instructions

This repo deploys a Basic Memory MCP server on an OCI Always Free VM that is reachable only inside a Tailscale tailnet.
Read first: `docs/specs/2026-10-07-basic-memory-oci-tailscale-design.md`.
Active work: `docs/plans/active/` (upcoming plans wait in `docs/plans/backlog/`).

## Commands
- `make help` lists every target. Do lifecycle work through Make targets only; use raw `docker compose` or `ssh` only to diagnose a failing target, and record why.
- `make check` (lint + all tests + coverage >= 80%) must pass before every commit. `make fmt` fixes shfmt findings.
- Local: `make local-up local-verify local-down`. `local-up` uses a fixed container name and port, so run it in one worktree at a time (`make check` is safe to run concurrently). VM read-only: `make probe status logs`. VM changing (ask the user first): `make vm-bootstrap deploy verify backup restore` (`verify` writes and deletes a test note; `backup` stops the container briefly).

## Invariants (enforced by tests/repo.bats; never weaken a test to make it pass)
- Basic Memory has no auth: publish its port on `127.0.0.1` only, never enable Tailscale Funnel, keep zero public ingress on the VM.
- Pin container images by digest; change the pin only after reading the release notes and passing `make check local-up local-verify`.
- Scripts: `#!/usr/bin/env bash` then `set -euo pipefail`; source `scripts/lib/common.sh`; fail with an actionable message via `die`.
- Scripts must run on macOS bash 3.2: no `mapfile`, associative arrays, `${x,,}`, `inherit_errexit`, or empty array expansion. After `x="$(fn)"` where `fn` can fail, add `|| exit 1`.
- Name constants instead of magic numbers. Never print secrets or session ids; use `mask`.
- Write the bats test first (tests/*.bats; fake commands live in tests/stubs/, recorded MCP responses in tests/fixtures/).

## Safety
- Never commit secrets, `.env`, Tailscale auth keys, `backups/`, `.local-data/`, or note content.
- The only secret is the Tailscale auth key. It reaches the VM via `TS_AUTHKEY` or the hidden prompt, never via a file in the repo or a command argument.
- Ask the user before anything that changes the VM or cloud resources: `vm-bootstrap`, `deploy`, `restore`, resizing, OCI security rules, Tailscale policy.
- Never delete `backups/` or `/srv/basic-memory.prev-*` directories.

## Git (policy: docs/specs/2026-10-07-git-review-policy-design.md)
- Work only in your own git worktree on `plan/<NN>-<slug>` or `work/<slug>`; one agent per worktree, never in the main checkout. Rename tool default branches (`worktree-*`, `codex/*`) with `git branch -m` before review; on a detached HEAD (Codex app) run `git switch -c <branch>` first. Per-tool start steps: the `git-workflow` skill.
- Never commit to `main`, force-push, rewrite history, run `git gc`, enable `extensions.worktreeConfig`, or delete another agent's branch or worktree.
- End every commit message with the trailers `Assisted-by: <claude-code|codex|antigravity|gemini-cli> <model>`, `Plan: <NN|none>` and `Task: <N|review|none>`; add `Review-Finding: R<n>-F<m>` (cross-vendor review) or `SDD-T<task>-F<n>` (in-plan task review) to review fixes. Never add `Co-authored-by` or `Signed-off-by`.
- A reviewer from another vendor reviews each branch read-only; findings go to `docs/reviews/`; only the human merges, with `git merge --no-ff`.

## Notes and language
- Label repository notes `Verified`, `Command`, `Assumption`, or `Open question`.
- Code, comments, script messages, this file and skills are English. README, runbooks, ARCHITECTURE and ADRs are Korean.
- Record evidence (command + result) in the active plan's Progress log or an ADR in `docs/decisions/`.

## Map
- `scripts/` lifecycle scripts; `scripts/lib/common.sh` shared helpers.
- `tests/` bats tests; `tools/` test image and coverage gate.
- `docs/specs/`, `docs/plans/{active,backlog,completed}/`.
- `.agents/skills/` skills for Codex and Antigravity; `.claude/skills/<name>` symlinks and `.claude/agents/branch-reviewer.md` for Claude Code.
- `docs/reviews/` review records (template in its README).

## Code Review Rules
Reviewers check only the changes since the base (Codex reads this section; Claude uses the `branch-review` skill):
1. Every task of the plan is implemented and its verification passed with evidence.
2. No changes outside the plan's scope.
3. The plan's Progress log records a passing `make check`; `scripts/check-git.sh <base> <branch>` passes.
4. Security: secrets, `.env`, public exposure, unauthenticated endpoints.
5. Docs required by this file are updated.
6. Every commit carries the Git trailers.
Severity: P0 data loss, security or outage and P1 bug or unmet requirement block the merge; P2 maintainability is fixed or deferred by the human with a reason; P3 is optional.
Each finding: `[Pn] path:line - failure scenario - suggested fix`. Report only problems these changes introduce; no style nits.

## Skills
- `git-workflow`: start, commit, request review and prepare the merge of agent work.
- `branch-review`: review another agent's branch read-only.
