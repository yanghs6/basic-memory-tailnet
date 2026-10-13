# Failure messages

Find the first error you saw. "The user" runs or approves the step; you only propose it. Add a row when a new error turns up (the user approves the change).

## Tailnet and SSH

| Message or symptom | Meaning | Next step |
|---|---|---|
| `Host key verification failed` after a rebuilt VM | The VM has a new SSH host key. | The user runs `ssh-keygen -R agent-hub` and accepts the new key (see `bm-recover`). |
| SSH fails while `tailscale status` shows the VM | The Tailscale policy denies SSH. | Check the `ssh` rule for `tag:agent-hub` (docs/runbooks/accounts.md). |

## Memory and Serve (`make status`)

| Message or symptom | Meaning | Next step |
|---|---|---|
| A warning containing `no active swap` | The swap file is missing. | The user reruns `make vm-bootstrap` (docs/runbooks/bootstrap.md). After the deploy, port 22 is closed, so the rerun is `make vm-bootstrap HOST=agent-hub` over Tailscale SSH (Assumption, confirmed in plan 05 item 29). |
| Sustained swap use, or container restarts in `make logs` | Memory pressure on the 1 GB VM. | Report the numbers and point to docs/decisions/0002-vm-sizing.md. Do not change anything. |
| `tailscale serve is not configured` | Serve is missing. | The user reruns bootstrap (`bm-recover` explains the Serve reset). |

## MCP (`make probe`)

| Message or symptom | Meaning | Next step |
|---|---|---|
| `initialize: request to <url> failed` | DNS or HTTPS. | Check MagicDNS and HTTPS certificates in the Tailscale admin console. |
| `initialize: HTTP 4xx` | Host header or path. | Propose comparing against a local container: `make local-up local-verify` starts a container and writes a test note, so the user decides. |
| `tools/list: missing tool` | The image changed. | See `bm-upgrade`. |
| `Funnel is on for this node` or `accepts connections on port N` | Exposure problem. | Point the user to "Exposure audit" in docs/runbooks/operations.md. Do not try to fix it yourself. |
| `BM_VM_PUBLIC_IP must be ...` | `.env` holds a wrong or stale value; the IP changes after a stop and start. | The user corrects `.env`. |
| Probe passes but agents cannot write | Data permissions or disk space. | Check `ssh ubuntu@agent-hub ls -ln /srv/basic-memory` (owner must be 1000) and `ssh ubuntu@agent-hub df -h /srv`, then propose `make verify`, which writes and deletes a test note, for the user to approve. |
| Log line `initialized (no session id)` | The server sent no session header. | Report it as evidence. `initialized (session abcd****)` is a masked real id; never print a full one. |
