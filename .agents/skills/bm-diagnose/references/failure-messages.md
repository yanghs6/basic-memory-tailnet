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
| `initialize: request to <url> failed` | tailscale mode: DNS or HTTPS. ssh mode: the tunnel is not running. | tailscale mode: check MagicDNS and HTTPS certificates in the Tailscale admin console. ssh mode: is `make tunnel` running? Run `make access-check`. |
| `initialize: HTTP 4xx` | Host header or path. | Propose comparing against a local container: `make local-up local-verify` starts a container and writes a test note, so the user decides. |
| `tools/list: missing tool` | The image changed. | See `bm-upgrade`. |
| `Funnel is on for this node` or `accepts connections on port N` | Exposure problem. | Point the user to "Exposure audit" in docs/runbooks/operations.md. Do not try to fix it yourself. |
| `BM_VM_PUBLIC_IP must be ...` | `.env` holds a wrong or stale value; the IP changes after a stop and start. | The user corrects `.env`. |
| Probe passes but agents cannot write | Data permissions or disk space. | Check `ssh ubuntu@agent-hub ls -ln /srv/basic-memory` (owner must be 1000) and `ssh ubuntu@agent-hub df -h /srv`, then propose `make verify`, which writes and deletes a test note, for the user to approve. |
| Log line `initialized (no session id)` | The server sent no session header. | Report it as evidence. `initialized (session abcd****)` is a masked real id; never print a full one. |

## Access mode (ssh mode and `BM_ACCESS`)

| Message or symptom | Meaning | Next step |
|---|---|---|
| `BM_ACCESS must be tailscale or ssh` | `.env` holds another value (case matters). | The user fixes `BM_ACCESS` in the main checkout `.env` (docs/runbooks/bootstrap.md). |
| `make tunnel is for BM_ACCESS=ssh` | `make tunnel` was run in tailscale mode. | Tailscale-mode clients use the tailnet URL; the user sets `BM_ACCESS=ssh` only after the mode change in docs/runbooks/operations.md. |
| `port N is in use on 127.0.0.1` | Another `make tunnel` or program holds the port. | Stop the other tunnel, or the user sets `BM_TUNNEL_MCP_PORT` or `BM_TUNNEL_WEB_PORT` in `.env`. |
| `tunnel closed (exit N)` | The SSH tunnel ended: login expired, network change or idle timeout. | The user reruns `make tunnel`; if it repeats, check the alias's ProxyCommand and login (docs/runbooks/gcp-vm.md, section 8). |
| `verify tunnel exited before it opened` | The temporary tunnel of `make verify` failed to start, often because a verify port is in use. | Check the ports named in the message, then the alias and its login (`make access-check`). |
| `verify tunnel did not open within` | The alias answered too slowly or not at all. | Run `make access-check`; check the instance state ("정지된 VM" in docs/runbooks/operations.md). |
| `Tailscale is logged in on the VM but BM_ACCESS=ssh` | The VM is still on the tailnet. | The user logs it out (docs/runbooks/operations.md, Access mode change). |
| `sshd on the VM accepts passwords` | sshd allows password logins. | The user sets key-only logins (docs/runbooks/gcp-vm.md, section 8, step 6). |
| `could not read the Tailscale state` | `sudo -n tailscale status --json` fails on the VM, for example the daemon is stopped. | The user logs Tailscale out or removes the package; do not just stop the daemon. |
| `unexpected Tailscale state` | The VM reports a state `verify` does not know. | Report the state text as evidence; the user checks Tailscale on the VM. |
