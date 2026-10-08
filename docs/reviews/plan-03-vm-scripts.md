# Review: plan/03-vm-scripts

Cross-vendor review per `docs/specs/2026-10-07-git-review-policy-design.md`, section 5. Author: claude-code (Claude Opus controller, Sonnet/Opus implementers). Reviewer: codex, run with `make review BRANCH=plan/03-vm-scripts REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 058ca9c (main) | 34a02a0 | blocked (2 P1) |
| R2 | codex gpt-6.1-sol (sandbox read-only) | 34a02a0 (R1 head) | e73be4b | blocked (1 P1, a regression from the R1-F2 fix); R1-F1 not re-raised |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/verify-vm.sh:57-61 | The public-exposure probe fails open: `nc` stderr is discarded and any non-zero exit counts as "closed", so a malformed `BM_VM_PUBLIC_IP` or an `nc` that rejects the options makes `make verify`/`make probe` pass without probing anything. Verified by reading `probe_port` and `check_public_closed`. | fixed 8fd3926, 6368680 |
| R1-F2 | P1 | scripts/backup.sh:50-52 | Finalization renames the manifest and archive to their final names before writing `.sha256`; if that write fails (for example a full disk), an incomplete backup set stays published. Verified by reading the code. | fixed 7471276 |
| R2-F1 | P1 | scripts/backup.sh:20-21 | The R1-F2 cleanup deleted this run's final file names even when they belonged to another run: two backups started in the same second (or after a clock rollback) share a name, and a failed run, even one that failed at the container stop, removed the other run's complete archive, manifest and checksum. Verified by reading the code and by two tests that fail on 7471276. | fixed d5e64e6 |

## Notes

- Verified: the codex change review ran with `sandbox: read-only`; both raw reports held real review content.
- Codex could not run `make check` (no Docker in its sandbox). Test evidence comes from the author: 172 bats tests passing, 97.92% line coverage (plan Progress log).
- All scripts are stub-tested only; 16 live-VM checks moved to plan 05's backlog file.
- R1-F1 now treats only an empty error, "refused", "timed out", "no route to host", "unreachable" or "prohibited" as a closed port; any other `nc` error stops verify. Assumption: the OCI Ubuntu image rejects with `icmp-host-prohibited`, which `nc` reports as "No route to host" (6368680). Confirm the real `nc` wording on macOS during plan 05; a wording not on the list fails loudly, never silently.
- After the R1 fixes `make check` passed with 181 tests and 97.99% line coverage.
- R2-F1 fix: backup.sh reserves `bm-<stamp>.tgz.partial` with an exclusive create (noclobber) and refuses a name whose final files already exist, both before the restart trap and the container stop; cleanup removes only this run's `.partial` files and the final files this run renamed. After the fix `make check` passed with 183 tests and 97.87% line coverage.
- Policy section 5 allows two rounds. R2-F1 was fixed after round 2 and has had no cross-vendor round of its own; the human decides at merge whether a third round is wanted.
- In-plan SDD fixes on this branch use `Review-Finding: SDD-T<task>-F<n>`; they are unrelated to the `R1-F<n>` IDs above.
