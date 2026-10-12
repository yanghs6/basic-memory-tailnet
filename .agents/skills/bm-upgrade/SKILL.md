---
name: bm-upgrade
description: Upgrade the pinned Basic Memory container image (version and digest) and roll it out to the VM safely. Use when asked to update, bump or patch Basic Memory.
---

# Upgrade Basic Memory

This changes what runs against real notes. Follow the steps in order. Ask the user before step 6 (`make deploy`) and before any restore in step 7. `make backup` and `make verify` need no OK, but `make backup` stops the container briefly, so say so.

1. Current pin: `grep 'image:' compose.yaml`. Keep this line for rollback.
2. Pick the target release on https://github.com/basicmachines-co/basic-memory/releases. Read the notes between the current and target versions for changes to: the `mcp` CLI flags (`--transport streamable-http --path /mcp`), `BASIC_MEMORY_*` env vars, data paths (`/app/data`, `/home/appuser/.basic-memory`), and the tools `write_note`, `read_note`, `search_notes`, `delete_note`. Flag any database, index or config migration: once the new version touches the data, the old image must not run on it again. Summarize all of this for the user.
3. Resolve the multi-arch digest (image tags have no `v` prefix) and confirm arm64 is included:
   `docker buildx imagetools inspect ghcr.io/basicmachines-co/basic-memory:<version>`
   Use the `Digest:` line of the index and check the list contains `linux/arm64`.
4. Change only the `image:` line in `compose.yaml` to `ghcr.io/basicmachines-co/basic-memory:<version>@<digest>`.
5. Verify locally: `make check local-up local-verify`, then `make local-down`. If anything fails, stop and report; do not deploy.
6. Ask the user to approve the rollout, then run `make backup`. Record the archive name from "backup saved: backups/bm-<stamp>.tgz": it is the rollback point and it holds the data from before the upgrade. Then run `make deploy`, `make verify` and `make status`.
7. Roll back only after the user agrees, because notes written after step 6 are replaced (they stay in `/srv/basic-memory.prev-*` on the VM). Put the old `image:` line back in `compose.yaml`, then ask the user to run `make restore BACKUP=<archive from step 6>` in their own terminal and type `yes` at the prompt. Never pipe `yes` into it. Restore uploads this repo's `compose.yaml` together with the pre-upgrade data and then runs verify, so both the data and the image go back. Deleting `/srv/basic-memory.prev-*` is for the human only; never remove it.
8. Commit `compose.yaml` through the `git-workflow` skill: work on a `plan/<NN>-<slug>` or `work/<slug>` branch in your own worktree, run `make check`, and end the commit with the `Assisted-by`, `Plan` and `Task` trailers (`Plan: none` and `Task: none` when no plan applies). Use the message `chore: upgrade basic-memory to <version>`. Record the outcome (Verified/Command) in the active plan's Progress log or in a new ADR under `docs/decisions/`. If the rollout failed, suggest a row for "Incident log" in `docs/runbooks/operations.md`.
