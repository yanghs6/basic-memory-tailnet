# Review: plan/dry1xr43-vm-scripts

Cross-vendor review per `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`, section 5. Author: claude-code (Claude Opus controller, Sonnet/Opus implementers). Reviewer: codex, run with `make review BRANCH=plan/dry1xr43-vm-scripts REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | a349fb4 (main) | a15638d | blocked (2 P1) |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/verify-vm.sh:57-61 | The public-exposure probe fails open: `nc` stderr is discarded and any non-zero exit counts as "closed", so a malformed `BM_VM_PUBLIC_IP` or an `nc` that rejects the options makes `make verify`/`make probe` pass without probing anything. Verified by reading `probe_port` and `check_public_closed`. | fixed 9d1fe67 |
| R1-F2 | P1 | scripts/backup.sh:50-52 | Finalization renames the manifest and archive to their final names before writing `.sha256`; if that write fails (for example a full disk), an incomplete backup set stays published. Verified by reading the code. | fixed 2f97140 |

## Notes

- Verified: the codex change review ran with `sandbox: read-only`; both raw reports held real review content.
- Codex could not run `make check` (no Docker in its sandbox). Test evidence comes from the author: 172 bats tests passing, 97.92% line coverage (plan Progress log).
- All scripts are stub-tested only; 16 live-VM checks moved to the [vm-rollout plan](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)'s backlog file.
- In-plan SDD fixes on this branch use `Review-Finding: SDD-T<task>-F<n>`; they are unrelated to the `R1-F<n>` IDs above.
