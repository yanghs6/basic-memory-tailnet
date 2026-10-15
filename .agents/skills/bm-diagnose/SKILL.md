---
name: bm-diagnose
description: Read-only troubleshooting for the Basic Memory MCP endpoint, Tailscale (tailnet, SSH, Serve) and the VM container. Use when an agent cannot reach or write to Basic Memory, make probe or make verify fails, the container is unhealthy or restarting, or the VM seems offline, slow or out of memory or disk. Not for rebuilding a deleted VM (bm-recover) or changing the image (bm-upgrade).
---

# Diagnose Basic Memory

Read-only: find the first failing layer and propose a fix. The user decides and acts.

## Rules

- Run only `make probe`, `make status`, `make logs` and `make access-check`, plus `tailscale status` (tailscale mode) and `ssh <user>@<host> true` on this machine.
- On the VM, read only with `ls`, `df` and this one named file: `/opt/basic-memory/compose.yaml` (the deployed compose file). Never read the VM's `/opt/basic-memory/.env` and never run an unrestricted `cat`.
- Anything that writes notes, starts or restarts something, or changes settings (`make verify`, `make local-up`, `make deploy`, `make restore`, `make backup`) is a proposal for the user, not a step you run.
- The local `.env` belongs to the user and lives in the main checkout: do not read it by any means; ask the user to check values in it. The make targets read it from there even when you run them in a worktree.
- `agent-hub` and `ubuntu` below are the defaults of `BM_VM_HOST` and `BM_VM_USER` (`.env.example`). If make output names another host or user, use that one.
- The access mode is `BM_ACCESS` in the user's `.env` (empty means tailscale). You cannot read `.env`: ask the user which mode the VM uses, or read it from `make status` (`access: ssh` or `tailscale serve`).

## Layers

Work top-down and stop at the first layer that fails. Look up every error message in [references/failure-messages.md](references/failure-messages.md) before you propose a fix.

1. Path to the VM.
   - tailscale mode: `tailscale status | grep agent-hub` on this machine. Missing or offline means the VM is stopped, deleted or logged out: ask the user to check the instance state with the command in "정지된 VM" in docs/runbooks/operations.md. When this machine itself shows `offline` with a coordination server warning, the network blocks Tailscale: run `make access-check` and report it.
   - ssh mode: `make access-check` and `ssh ubuntu@agent-hub-iap true` (the alias is `BM_VM_HOST`). A failure points to the alias, its login or the firewall rule for the tunnel range: docs/runbooks/gcp-vm.md, section 8.
   - `TERMINATED` (stopped): the user starts it and updates `BM_VM_PUBLIC_IP` (same section). Do not rebuild.
   - Deleted or unusable: use `bm-recover`.
2. SSH: `ssh ubuntu@agent-hub true`. Failing while the tailnet is fine: check the Tailscale policy `ssh` rule for `tag:agent-hub` (docs/runbooks/accounts.md).
3. Container: `make status`. Not `(healthy)`: run `make logs` and quote the first error.
4. Memory: `make status` prints the memory and swap use.
5. Serve: `make status` ends with `tailscale serve status`; it must show `proxy http://127.0.0.1:8737` (`BM_PORT`).
   In ssh mode there is no Serve: `make status` must show `tailscale: not installed or logged out`.
6. MCP: `make probe` (initialize and tools/list only; writes nothing). Read the failing step.
7. Report the failing layer, the evidence (command and output excerpt), the proposed fix and who runs it. If the incident was real, suggest a row in "Incident log" in docs/runbooks/operations.md.

## Gotchas

- After a stop and start the VM gets a new public IP, so a `BM_VM_PUBLIC_IP` error may only mean a stale value.
- `make local-up local-verify` starts a container and writes a test note: propose it, do not run it.
- Never print a full session id. The log line `initialized (session abcd****)` is already masked.
- When you meet an error the catalog lacks, suggest a new row for it to the user.
