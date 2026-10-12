---
name: bm-upgrade
description: Upgrade the pinned Basic Memory container image (version and digest) and roll it out to the VM safely. Use when asked to update, bump or patch Basic Memory.
---

# Upgrade Basic Memory

This changes what runs against real notes. Follow the steps in order. Ask the user before the `make deploy` in step 7 and before any restore in step 8. `make backup` and `make verify` need no OK, but `make backup` stops the container briefly, so say so.

1. Set up first, through the `git-workflow` skill: create your own worktree and a `work/<slug>` branch (or `plan/<NN>-<slug>` if a plan covers this) before touching any file. Never edit `compose.yaml` in the main checkout. `make deploy` uploads the working-tree `compose.yaml`, so this is also the file that gets deployed. The make targets read `.env` from the main checkout and `make backup` saves into the main checkout's `backups/`, even when you run them in your worktree. Never copy or read `.env` yourself.
2. Current pin: `grep 'image:' compose.yaml`. Keep this line for rollback.
3. Pick the target release on https://github.com/basicmachines-co/basic-memory/releases. Read the notes between the current and target versions for changes to: the `mcp` CLI flags (`--transport streamable-http --path /mcp`), `BASIC_MEMORY_*` env vars, data paths (`/app/data`, `/home/appuser/.basic-memory`), and the tools `write_note`, `read_note`, `search_notes`, `delete_note`. Flag any database, index or config migration: once the new version touches the data, the old image must not run on it again. Summarize all of this for the user.
4. Resolve the multi-arch digest (image tags have no `v` prefix) and confirm both architectures are included:
   `docker buildx imagetools inspect ghcr.io/basicmachines-co/basic-memory:<version>`
   Use the `Digest:` line of the index and check the list contains `linux/amd64` (the e2-micro VM) and `linux/arm64` (Apple Silicon Macs running `make local-up`).
5. Change only the `image:` line in `compose.yaml` to `ghcr.io/basicmachines-co/basic-memory:<version>@<digest>`.
6. Verify locally: `make check local-up local-verify`, then `make local-down`. If anything fails, stop and report; do not deploy.
7. Ask the user to approve the rollout, and tell them: until this branch is reviewed and merged, the VM runs an image that main does not pin, so nobody may run `make deploy` or `make restore` from another checkout. Then run `make backup`. Record the absolute archive path from "backup saved: /…/backups/bm-<stamp>.tgz": it is the rollback point, it holds the data from before the upgrade, and it lives in the main checkout's `backups/`. Then run `make deploy`, `make verify` and `make status`.
8. Roll back only after the user agrees, because notes written after step 7 are replaced (they stay in `/srv/basic-memory.prev-*` on the VM). Put the old `image:` line back in `compose.yaml`, then ask the user to run `make restore BACKUP=<absolute archive path from step 7>` in their own terminal and type `yes` at the prompt. Never pipe `yes` into it. Restore uploads this repo's `compose.yaml` together with the pre-upgrade data and then runs verify, so both the data and the image go back. Deleting `/srv/basic-memory.prev-*` is for the human only; never remove it.
9. Commit `compose.yaml` on the branch from step 1 through the `git-workflow` skill: run `make check` and end the commit with the `Assisted-by`, `Plan` and `Task` trailers (`Plan: none` and `Task: none` when no plan applies). Use the message `chore: upgrade basic-memory to <version>`. If you rolled back in step 8, do not commit the new pin; record only the outcome. Record the outcome (Verified/Command) in the active plan's Progress log or in a new ADR under `docs/decisions/`. If the rollout failed, suggest a row for "Incident log" in `docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md`. After committing, ask for the cross-vendor review and the merge right away: the VM keeps running the new image until main pins it.
