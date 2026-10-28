# Roll back an upgrade

Roll back only after the user agrees, because notes written after the backup are replaced (they stay in `/srv/basic-memory.prev-*` on the VM).

1. Put the old `image:` line (step 2 of the skill) back in `compose.yaml`.
2. Ask the user to run `make restore BACKUP=<absolute archive path from step 7>` in their own terminal and type `yes` at the prompt. Never pipe `yes` into it.
3. Restore uploads this repo's `compose.yaml` together with the pre-upgrade data and then runs verify, so both the data and the image go back. Then run `make memory-sync FULL=1` once on each Mac that mirrors agent memory (the user runs it on the other Macs), because the mirror's local state does not see that the restore put older notes back.
4. Deleting `/srv/basic-memory.prev-*` is for the human only; never remove it.
5. Do not commit the new pin. Record the outcome and suggest an "Incident log" row (step 9 of the skill).
