---
name: bm-recover
description: Recovers the Basic Memory VM and its notes. Use when the VM is stopped and will not answer, was deleted, will not start, or its data is corrupted, or when notes must be restored from a backup onto a new VM. A stopped VM is started, never rebuilt. Not for a VM that runs but misbehaves (bm-diagnose) or for an image change (bm-upgrade).
---

# Recover the Basic Memory VM

## Rules

- Each of steps 3 to 6 changes cloud resources or data: ask the user and wait for an OK before every one of them, including the `make vm-bootstrap` in step 4.
- `.env` belongs to the user and lives in the main checkout: the user edits it, and you must not read it by any means (not with Read, `cat` or anything else).
- The user runs every command that needs a terminal prompt (the Tailscale auth key, the restore `yes`) in their own terminal. Never ask for the auth key in chat, never put `TS_AUTHKEY=...` on a command line and never pipe `yes`.
- The user runs every cloud command, exactly as the runbook section named in each step writes it.
- Never delete the old instance or its disk before the restore is verified.
- `agent-hub` and `ubuntu` below are the defaults of `BM_VM_HOST` and `BM_VM_USER` (`.env.example`).
- In ssh mode (`make status` printed `access: ssh` before, or the user says so) there is no Tailscale node, auth key or Serve: follow "ssh 모드 순서" in docs/runbooks/bootstrap.md for steps 3 to 5.

## Checklist

Copy this into your reply and tick each item:

- [ ] 1. Stopped (start it and stop here) or gone
- [ ] 2. Newest backup in the main checkout, with `.sha256` and `.manifest`
- [ ] 3. Ask first: new VM created (tailscale mode: old Tailscale machine removed; ssh mode: the tunnel rule exists)
- [ ] 4. Ask first: host keys cleared, VM bootstrapped (ssh mode: the alias's `HostName` points at the new instance)
- [ ] 5. Ask first (tailscale mode): Tailscale SSH works, then port 22 rule deleted. In ssh mode skip it.
- [ ] 6. Ask first: image checked, deployed, restored
- [ ] 7. Status and probe pass, audit and incident log recorded
- [ ] 8. ssh mode: `make verify` prints `OK: Tailscale does not expose the VM` and `OK: sshd accepts keys only`, and the only rule from outside the VPC is the tunnel rule

## Steps

1. Find out whether the VM is really gone: `make status` fails. Ask the user to check the instance state with the command in "정지된 VM" in `docs/runbooks/operations.md`.
   - `TERMINATED` (stopped): do not rebuild; the data is on its disk. The user starts it (same section). The external IP changes after a stop and start, so the user reads the new IP (docs/runbooks/gcp-vm.md, section 5) and updates `BM_VM_PUBLIC_IP` in `.env`. Then run `make status` and `make probe`, add an "Incident log" row if it was a real incident, and stop here.
   - Deleted, will not start, or the data is corrupt: continue with step 2.
   - Anything transient: use `bm-diagnose` instead.
2. Choose the newest backup in the main checkout, not in your worktree: the main checkout is the parent directory of `git rev-parse --path-format=absolute --git-common-dir`. List `<main checkout>/backups/bm-*.tgz` with `ls -t` and take the first. Check that both `<file>.sha256` and `<file>.manifest` exist; `make restore` refuses an archive without either ("checksum file missing", "manifest missing"). If no backup qualifies in the main checkout, tell the user the notes cannot be restored and continue with an empty VM only if they agree. Never conclude "no backup" from inside a worktree.
3. Ask first. The user creates a new VM following `docs/runbooks/gcp-vm.md` (keeping `default-allow-ssh` open to their own IP/32 for now) and removes the old `agent-hub` machine in the Tailscale admin console so the new VM can take the name.
   - Instances cannot be renamed, so the user creates the new VM under a different `INSTANCE` name and stops the old one if it still exists.
   - While the old VM or its disk exists the free tier can be exceeded, so after the restore is verified the user removes them soon (docs/runbooks/gcp-vm.md, section 7) and checks billing (the "비용 점검" section of docs/runbooks/operations.md).
   - The user then sets the new public IP as `BM_VM_PUBLIC_IP` in `.env` (the user's file; you neither edit nor read it).
   In ssh mode the user deletes `default-allow-ssh` and creates the tunnel rule only if it is not already listed, because firewall rules are project-wide (docs/runbooks/gcp-vm.md, sections 3 and 8), and there is no Tailscale machine to remove.
4. Ask first. The user creates a new one-off auth key (`docs/runbooks/accounts.md`). Before bootstrapping, the user follows step 1 of `docs/runbooks/bootstrap.md` (old Tailscale node, `ssh-keygen -R agent-hub` and `ssh-keygen -R <new-public-ip>`; the latter is harmless when no entry exists, and a stale host key for a reused public IP makes the bootstrap fail with "upload failed"). The user runs `make vm-bootstrap HOST=<new-public-ip>` in their own terminal and pastes the key at the hidden prompt, or runs `read -rs TS_AUTHKEY && export TS_AUTHKEY` first and `unset TS_AUTHKEY` afterwards. It is safe to repeat if it fails.
   In ssh mode the user points the alias's `HostName` at the new instance name (docs/runbooks/gcp-vm.md, section 8), accepts the new key with an interactive `ssh ubuntu@agent-hub-iap true` (known_hosts keys on the `HostName`, not the alias, so only a reused instance name needs `ssh-keygen -R <instance name>`), and runs `make vm-bootstrap HOST=agent-hub-iap` without a key.
5. Ask first. First Tailscale SSH to the new VM: ask the user to run an interactive `ssh ubuntu@agent-hub true` and accept the new key. Only when that succeeds, ask the user to delete the firewall rule that opens port 22 (`default-allow-ssh`, with the command in docs/runbooks/bootstrap.md step 4).
   In ssh mode skip this step: there is no Tailscale SSH, and port 22 is open only to the tunnel range.
6. Ask first. Before deploying, run `make status`.
   - It shows a Basic Memory container: compare its image with `grep 'image:' compose.yaml`; when they differ, stop and ask the user (an unmerged upgrade may be live, see `bm-upgrade`).
   - Nothing is deployed yet: `make status` ends with `could not query containers`. That is expected, so skip the comparison.
   - Run `make deploy` from your worktree only after `git diff main -- compose.yaml` prints nothing (your pin equals main's); if it prints anything, stop and ask the user.
   - Then the user runs `make restore BACKUP=<absolute path of the file from step 2>` in their own terminal and types `yes`; the target runs verify at the end.
   - Backups skip the model cache (`config/fastembed_cache/`); Basic Memory downloads it again on first use after the restore, so the first search can be slow.
7. Run `make status` and `make probe`. The firewall was created again, so ask the user to redo the "Exposure audit" in `docs/runbooks/operations.md` and add a row to its "점검 기록" table. Add a row to "Incident log" in the same file (date, cause, backup used, data loss window) and commit it through the `git-workflow` skill.

In tailscale mode, if the Serve configuration is wrong afterwards, do not edit it by hand; ask the user first. When "Funnel is on for this node" appears, the user turns Funnel off (removes the `funnel` attribute in the Tailscale policy, see "Exposure audit" in `docs/runbooks/operations.md`) before anything else. Then the user runs `make vm-bootstrap HOST=agent-hub` in their own terminal, because it prompts for the auth key. Verified in plan 05 (2026-10-13): once the public port 22 is closed, `HOST=agent-hub` works over Tailscale SSH; while the VM is still on the tailnet, leave the key prompt empty. `make status` prints a different hint, `make vm-bootstrap HOST=<public-ip>` (scripts/status.sh), which needs the port 22 rule again; prefer `HOST=agent-hub` and say why. Deleting `/srv/basic-memory.prev-*` is for the human only.
