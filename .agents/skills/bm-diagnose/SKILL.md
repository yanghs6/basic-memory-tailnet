---
name: bm-diagnose
description: Read-only troubleshooting for the Basic Memory MCP endpoint, Tailscale Serve, Tailscale SSH and the VM container. Use when an agent cannot reach Basic Memory, make verify or make probe fails, or the VM seems unhealthy.
---

# Diagnose Basic Memory

Read-only. Run only `make probe`, `make status` and `make logs` (plus `tailscale status` and `ssh ubuntu@bm-node true` on this machine). On the VM read only with `ls`, `df` and this one named file: `/opt/basic-memory/compose.yaml` (the deployed compose file). Never read the VM's `/opt/basic-memory/.env` and never run an unrestricted `cat`. Anything that writes notes, starts or restarts something, or changes settings (`make verify`, `make local-up`, `make deploy`, `make restore`, `make backup`) is a proposal for the user, not a step you run. The local `.env` belongs to the user: do not read it by any means; ask the user to check values in it.

Work top-down and stop at the first layer that fails:

1. Tailnet: `tailscale status | grep bm-node` on this machine. Missing or offline: the VM is down or logged out; ask the user to check the OCI console (terminated means `bm-recover`).
2. SSH: `ssh ubuntu@bm-node true`. Failing while the tailnet is fine: check the Tailscale policy `ssh` rule for `tag:bm-server` (docs/runbooks/accounts.md). After a rebuilt VM, "Host key verification failed" means the user must run `ssh-keygen -R bm-node` and accept the new key (see `bm-recover`).
3. Container: `make status`. Not `(healthy)`: run `make logs` and quote the first error.
4. Memory: `make status` prints `WARNING: memory below ...%; with idle CPU and network OCI may reclaim this VM`. That is idle-reclaim risk; see "Idle reclamation" in docs/runbooks/operations.md.
5. Serve: `make status` ends with `tailscale serve status`; it must show `proxy http://127.0.0.1:8737`. If it dies with "tailscale serve is not configured", Serve is missing: the user reruns bootstrap (`bm-recover` explains the Serve reset).
6. MCP: `make probe` (initialize and tools/list only; writes nothing) and read the failing step:
   - `initialize: request to <url> failed`: DNS or HTTPS; check MagicDNS and HTTPS certificates in the Tailscale admin console.
   - `initialize: HTTP 4xx`: Host header or path; propose comparing against a local container (`make local-up local-verify` starts a container and writes a test note, so the user decides).
   - `tools/list: missing tool`: the image changed; see `bm-upgrade`.
   - `Funnel is on for this node` or `accepts connections on port N`: exposure problem; point the user to "Exposure audit" in docs/runbooks/operations.md. Do not try to fix it yourself.
   - `BM_VM_PUBLIC_IP must be ...`: the user must correct `.env`.
   - Probe passes but agents cannot write: check data permissions (`ssh ubuntu@bm-node ls -ln /srv/basic-memory`, owner must be 1000) and disk space (`ssh ubuntu@bm-node df -h /srv`), then propose `make verify`, which writes and deletes a test note, for the user to approve.
   - The log line `initialized (no session id)` means the server sent no session header; `initialized (session abcd****)` is a masked real id. Never print a full session id.
7. Report the failing layer, the evidence (command and output excerpt) and the proposed fix. If the incident was real, suggest a row in "Incident log" in docs/runbooks/operations.md.
