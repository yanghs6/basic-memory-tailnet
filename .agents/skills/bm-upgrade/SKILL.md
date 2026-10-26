---
name: bm-upgrade
description: Upgrades the pinned Basic Memory container image (version and digest) and rolls it out to the VM with a backup as the rollback point. Use when asked to update, bump, patch or roll back Basic Memory, or when a new Basic Memory release or security fix is out. Not for compose or VM settings unrelated to the image.
---

# Upgrade Basic Memory

This changes what runs against real notes. Follow the steps in order.

## Rules

- Ask the user before the `make deploy` in step 7 and before any restore in step 8. `make backup` and `make verify` need no OK, but `make backup` stops the container briefly, so say so.
- Never edit `compose.yaml` in the main checkout. `make deploy` uploads the working-tree `compose.yaml`, so the file in your worktree is the file that gets deployed.
- The make targets read `.env` from the main checkout and `make backup` saves into the main checkout's `backups/`, even when you run them in your worktree. Never copy or read `.env` yourself.
- Deleting `/srv/basic-memory.prev-*` is for the human only; never remove it.

## Checklist

Copy this into your reply and tick each item:

- [ ] 1. Own worktree and branch
- [ ] 2. Current pin recorded
- [ ] 3. Release notes summarized, migrations flagged
- [ ] 4. Digest resolved; `linux/amd64` and `linux/arm64` present
- [ ] 5. Only the `image:` line changed
- [ ] 6. `make check local-up local-verify` passed, `make local-down` done
- [ ] 7. Ask first: backup path recorded, deployed, verified
- [ ] 8. Only on failure, ask first: rolled back
- [ ] 9. Committed, outcome recorded, review requested

## Steps

1. Set up first, through the `git-workflow` skill: create your own worktree and a `work/<slug>` branch (or `plan/<ID>-<slug>` if a plan covers this) before touching any file.
2. Current pin: `grep 'image:' compose.yaml`. Keep this line for rollback.
3. Pick the target release on https://github.com/basicmachines-co/basic-memory/releases. Read the notes between the current and target versions for changes to: the `mcp` CLI flags (`--transport streamable-http --path /mcp`), `BASIC_MEMORY_*` env vars, data paths (`/app/data`, `/home/appuser/.basic-memory`), and the tools `write_note`, `read_note`, `search_notes`, `delete_note`. Flag any database, index or config migration: once the new version touches the data, the old image must not run on it again. Summarize all of this for the user.
4. Resolve the multi-arch digest (image tags have no `v` prefix) and confirm both architectures are included:
   `docker buildx imagetools inspect ghcr.io/basicmachines-co/basic-memory:<version>`
   Use the `Digest:` line of the index and check the list contains `linux/amd64` (the VM) and `linux/arm64` (Apple Silicon Macs running `make local-up`).
5. Change only the `image:` line in `compose.yaml` to `ghcr.io/basicmachines-co/basic-memory:<version>@<digest>`.
6. Verify locally: `make check local-up local-verify`, then `make local-down`. If anything fails, stop and report; do not deploy.
7. Ask the user to approve the rollout, and tell them: until this branch is reviewed and merged, the VM runs an image that main does not pin, so nobody may run `make deploy` or `make restore` from another checkout. Then run `make backup`. Record the absolute archive path from "backup saved: /…/backups/bm-<stamp>.tgz": it is the rollback point, it holds the data from before the upgrade, and it lives in the main checkout's `backups/`. Then run `make deploy`, `make verify` and `make status`.
8. If `make deploy`, `make verify` or `make status` fails, or the user asks to undo the upgrade, read [references/rollback.md](references/rollback.md) and follow it. Otherwise skip this step.
9. Commit `compose.yaml` on the branch from step 1 through the `git-workflow` skill: run `make check` and end the commit with the `Assisted-by`, `Plan` and `Task` trailers (`Plan: none` and `Task: none` when no plan applies). Use the message `chore: upgrade basic-memory to <version>`. If you rolled back in step 8, do not commit the new pin; record only the outcome. Record the outcome (Verified/Command) in the active plan's Progress log, or, without a plan, in the PR body's Verification; a decision goes in a new ADR (`make new-doc TYPE=adr`). If the rollout failed, suggest a row for "Incident log" in `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`. After committing, ask for the cross-vendor review and the merge right away: the VM keeps running the new image until main pins it.

## Gotchas

- Image tags have no `v` prefix: `basic-memory:0.23.2`, not `basic-memory:v0.23.2`.
- A migrated database cannot go back to the old image without the backup from step 7: never roll back by changing only the `image:` line.
