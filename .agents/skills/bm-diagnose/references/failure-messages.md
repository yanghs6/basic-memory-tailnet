# Failure messages

Find the first error you saw. "The user" runs or approves the step; you only propose it. Add a row when a new error turns up (the user approves the change).

## Tailnet and SSH

| Message or symptom | Meaning | Next step |
|---|---|---|
| `Host key verification failed` after a rebuilt VM | The VM has a new SSH host key. | The user runs `ssh-keygen -R agent-hub` and accepts the new key (see `bm-recover`). |
| SSH fails while `tailscale status` shows the VM | The Tailscale policy denies SSH. | Check the `ssh` rule for `tag:agent-hub` (docs/runbooks/rbk-2026-10-12-hqxjjqy8-accounts.md). |

## Memory and Serve (`make status`)

| Message or symptom | Meaning | Next step |
|---|---|---|
| A warning containing `no active swap` | The swap file is missing. | The user reruns `make vm-bootstrap` (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md). tailscale mode: after the deploy, port 22 is closed, so the rerun is `make vm-bootstrap HOST=agent-hub` over Tailscale SSH (Assumption, confirmed in the vm-rollout plan item 29). ssh mode: the rerun is `make vm-bootstrap HOST=<the SSH alias in BM_VM_HOST>`, for example `agent-hub-iap`, without an auth key. |
| `WARNING: swap is N% used`, sustained swap use, or container restarts in `make logs` | Memory pressure on the 1 GB VM. | Report the numbers and point to docs/decisions/adr-2026-10-12-mdq5exsf-vm-sizing.md. Do not change anything. |
| `WARNING: <service> is not running` | The container of that note service exited or was removed. | Run `make logs` and quote the first error. A restart needs the user's OK (`make deploy`). |
| `WARNING: Basic Memory did not answer HTTP` | The server took the connection but gave no answer within 10 seconds; the healthcheck can still say `(healthy)`. | Same as the "server hangs" row under MCP: run `make probe`, report the memory and swap numbers, and suggest a restart for the user's OK. |
| `WARNING: the data root's filesystem is N% full` | The VM disk is filling up; note writes and backups fail when it is full. | Report the number. The user decides what to free; never delete `backups/` or `/srv/basic-memory.prev-*` yourself. |
| `tailscale serve is not configured` | Serve is missing. | The user reruns bootstrap (`bm-recover` explains the Serve reset). |

## MCP (`make probe`)

| Message or symptom | Meaning | Next step |
|---|---|---|
| `initialize: request to <url> failed` | tailscale mode: DNS or HTTPS. ssh mode: the tunnel is not running. | tailscale mode: check MagicDNS and HTTPS certificates in the Tailscale admin console. ssh mode: is `make tunnel` running? Run `make access-check`. |
| `curl: (28) Operation timed out after N milliseconds` printed before `<step>: request to <url> failed` | The connection was accepted (tunnel or tailnet), but no answer came within `MCP_DEFAULT_TIMEOUT_SECONDS` (30 seconds, scripts/lib/mcp.sh). Seen right after a deploy on 2026-10-21. | Wait 1-2 minutes, run `make status` (both containers `(healthy)`, memory and swap use), then `make probe`. If the probe passes, propose `make verify` to the user. If it repeats, report the first error in `make logs` and the memory numbers (see the "Sustained swap use" row) and suggest an Incident log row. If it still fails after several minutes, see the next row. |
| `make status` shows the container `(healthy)`, but `make probe` or MCP calls keep failing for minutes | The server hangs. The healthcheck only opens a TCP connection, so a stuck server still looks healthy. Seen twice on 2026-10-28 after memory-sync writes ("Incident log" in docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md). | Report the `make status` memory and swap numbers and the first errors in `make logs`. Suggest restarting the container and wait for the user's OK; on 2026-10-28 `make backup` did the restart (it stops and starts the container and also writes a backup). Then run `make probe` and suggest an Incident log row. |
| `initialize: HTTP 4xx` | Host header or path. | Propose comparing against a local container: `make local-up local-verify` starts a container and writes a test note, so the user decides. |
| `tools/list: missing tool` | The image changed. | See `bm-upgrade`. |
| `Funnel is on for this node` or `accepts connections on port N` | Exposure problem. | Point the user to "Exposure audit" in docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md. Do not try to fix it yourself. |
| `BM_VM_PUBLIC_IP must be ...` | `.env` holds a wrong or stale value; the IP changes after a stop and start. | The user corrects `.env`. |
| `BM_VM_PUBLIC_IP in .env is not the VM's current external IP` | The VM was stopped and started and got a new external IP. | The user looks up the new IP (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md, section 5) and updates `.env`. |
| `could not read the VM's external IP from the metadata server` | The VM has no external IP, or curl or the metadata server failed on the VM. | Check SSH first (`make access-check`); the user checks the instance's external IP (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md, section 5). |
| `search_notes: a hybrid search did not answer that semantic search is disabled` | Semantic search is on: the compose line is missing, or the image ignores the switch. With it on, writes stall the 1 GB VM. | Compare the `BASIC_MEMORY_SEMANTIC_SEARCH_ENABLED` and `image:` lines of `compose.yaml` with main and report; do not deploy (docs/decisions/adr-2026-10-30-bts7gsex-semantic-search-off.md, `bm-upgrade`). |
| Probe passes but agents cannot write | Data permissions or disk space. | Check `ssh ubuntu@<BM_VM_HOST> ls -ln /srv/basic-memory` (owner must be 1000) and `ssh ubuntu@<BM_VM_HOST> df -h /srv` (`BM_VM_HOST` is `agent-hub` in tailscale mode and the SSH alias, for example `agent-hub-iap`, in ssh mode), then propose `make verify`, which writes and deletes a test note, for the user to approve. |
| Log line `initialized (no session id)` | The server sent no session header. | Report it as evidence. `initialized (session abcd****)` is a masked real id; never print a full one. |

## Access mode (ssh mode and `BM_ACCESS`)

| Message or symptom | Meaning | Next step |
|---|---|---|
| `BM_ACCESS must be tailscale or ssh` | `.env` holds another value (case matters). | The user fixes `BM_ACCESS` in the main checkout `.env` (docs/runbooks/rbk-2026-10-12-ha5w72pm-bootstrap.md). |
| `make tunnel is for BM_ACCESS=ssh` | `make tunnel` was run in tailscale mode. | Tailscale-mode clients use the tailnet URL; the user sets `BM_ACCESS=ssh` only after the mode change in docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md. |
| `port N is in use on 127.0.0.1` | Another `make tunnel` or program holds the port. | Stop the other tunnel, or the user sets `BM_TUNNEL_MCP_PORT` or `BM_TUNNEL_WEB_PORT` in `.env`. |
| `tunnel closed (exit N)` | The SSH tunnel ended: login expired, network change or idle timeout. | The user reruns `make tunnel`; if it repeats, check the alias's ProxyCommand and login (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md, section 8). |
| `verify tunnel exited before it opened` | The temporary tunnel of `make verify` failed to start, often because a verify port is in use. | Check the ports named in the message, then the alias and its login (`make access-check`). |
| `verify tunnel did not open within` | The alias answered too slowly or not at all. | Run `make access-check`; check the instance state ("정지된 VM" in docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md). |
| `Tailscale is logged in on the VM but BM_ACCESS=ssh` | The VM is still on the tailnet. | The user logs it out (docs/runbooks/rbk-2026-10-12-t79ex2ny-operations.md, Access mode change). |
| `sshd on the VM accepts passwords` | sshd allows password logins. | The user sets key-only logins (docs/runbooks/rbk-2026-10-12-tcjs7m6x-gcp-vm.md, section 8, step 6). |
| `could not read the Tailscale state` | `sudo -n tailscale status --json` fails on the VM, for example the daemon is stopped. | The user logs Tailscale out or removes the package; do not just stop the daemon. |
| `unexpected Tailscale state` | The VM reports a state `verify` does not know. | Report the state text as evidence; the user checks Tailscale on the VM. |
