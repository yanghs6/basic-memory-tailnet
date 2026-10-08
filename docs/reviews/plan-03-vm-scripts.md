# Review: plan/03-vm-scripts

Cross-vendor review per `docs/specs/2026-10-07-git-review-policy-design.md`, section 5. Author: claude-code (Claude Opus controller, Sonnet/Opus implementers). Reviewer: codex, run with `make review BRANCH=plan/03-vm-scripts REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 058ca9c (main) | 34a02a0 | blocked (2 P1) |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/verify-vm.sh:57-61 | The public-exposure probe fails open: `nc` stderr is discarded and any non-zero exit counts as "closed", so a malformed `BM_VM_PUBLIC_IP` or an `nc` that rejects the options makes `make verify`/`make probe` pass without probing anything. Verified by reading `probe_port` and `check_public_closed`. | fixed 8fd3926 |
| R1-F2 | P1 | scripts/backup.sh:50-52 | Finalization renames the manifest and archive to their final names before writing `.sha256`; if that write fails (for example a full disk), an incomplete backup set stays published. Verified by reading the code. | fixed 7471276 |

## Notes

- Verified: the codex change review ran with `sandbox: read-only`; both raw reports held real review content.
- Codex could not run `make check` (no Docker in its sandbox). Test evidence comes from the author: 172 bats tests passing, 97.92% line coverage (plan Progress log).
- All scripts are stub-tested only; 16 live-VM checks moved to plan 05's backlog file.
- In-plan SDD fixes on this branch use `Review-Finding: SDD-T<task>-F<n>`; they are unrelated to the `R1-F<n>` IDs above.
