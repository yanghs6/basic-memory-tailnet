---
name: bm-recover
description: Rebuild the Basic Memory VM after OCI reclaims it or it becomes unusable, then restore the latest backup. Use when the VM is terminated, permanently unreachable, or its data is corrupted.
---

# Recover the Basic Memory VM

Each of steps 3 to 6 changes cloud resources or data: ask the user and wait for an OK before every one of them, including the `make vm-bootstrap` in step 4. You cannot read `.env` (it is denied for agents), so the user edits it. The user also runs every command that needs a terminal prompt (the Tailscale auth key, the restore `yes`) in their own terminal. Never ask for the auth key in chat, never put `TS_AUTHKEY=...` on a command line and never pipe `yes`.

1. Confirm the VM is really gone: `make status` fails and the user sees the instance stopped or terminated in the OCI console. For anything transient, use `bm-diagnose` instead.
2. Choose the newest backup: `ls -t backups/bm-*.tgz | head -n 1`. Check that both `<file>.sha256` and `<file>.manifest` exist; `make restore` refuses an archive without either ("checksum file missing", "manifest missing"). If no backup qualifies, tell the user the notes cannot be restored and continue with an empty VM only if they agree.
3. Ask first. The user creates a new VM following `docs/runbooks/oci-vm.md` (temporary port 22 rule) and removes the old `bm-node` machine in the Tailscale admin console so the new VM can take the name. The user then sets the new public IP as `BM_VM_PUBLIC_IP` in `.env` (you cannot edit or read it).
4. Ask first. The user creates a new one-off auth key (`docs/runbooks/accounts.md`). The user runs `make vm-bootstrap HOST=<new-public-ip>` in their own terminal and pastes the key at the hidden prompt, or runs `read -rs TS_AUTHKEY && export TS_AUTHKEY` first. It is safe to repeat if it fails.
5. Ask first. First Tailscale SSH to the new VM: run `ssh-keygen -R bm-node` to drop the old host key, then ask the user to run an interactive `ssh ubuntu@bm-node true` and accept the new key. Only when that succeeds, ask the user to delete the port 22 ingress rule in OCI.
6. Ask first. Run `make deploy`. Then the user runs `make restore BACKUP=<file from step 2>` in their own terminal and types `yes`; the target runs verify at the end.
7. Run `make status` and `make probe`. Add a row to "Incident log" in `docs/runbooks/operations.md` (date, cause, backup used, data loss window) and commit it through the `git-workflow` skill.

If the Serve configuration is wrong afterwards, do not edit it by hand. Assumption (confirm in plan 05): turn Funnel off first if "Funnel is on for this node" appears, then run `make vm-bootstrap HOST=bm-node` over Tailscale SSH (port 22 stays closed). Deleting `/srv/basic-memory.prev-*` is for the human only.
