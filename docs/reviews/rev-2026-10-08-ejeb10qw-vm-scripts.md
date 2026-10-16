---
status: final
---

# Review: plan/dry1xr43-vm-scripts

Cross-vendor review per `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`, section 5. Author: claude-code (Claude Opus controller, Sonnet/Opus implementers). Reviewer: codex, run with `make review BRANCH=plan/dry1xr43-vm-scripts REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | a349fb4 (main) | a15638d | blocked (2 P1) |
| R2 | codex gpt-6.1-sol (sandbox read-only) | a15638d (R1 head) | d15d641 | blocked (1 P1, a regression from the R1-F2 fix); R1-F1 not re-raised |
| R3 | codex gpt-6.1-sol (sandbox read-only) | d15d641 (R2 head) | bcc66c5 | plan review: mergeable; change review: 1 P1 (race in the R2-F1 reservation) |
| R4 | codex gpt-6.1-sol (sandbox read-only) | bcc66c5 (R3 head) | 9c8b9e0 | mergeable; R3-F1 race closed, no regression found (Codex ran shell syntax and diff whitespace checks, not the test suite) |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/verify-vm.sh:57-61 | The public-exposure probe fails open: `nc` stderr is discarded and any non-zero exit counts as "closed", so a malformed `BM_VM_PUBLIC_IP` or an `nc` that rejects the options makes `make verify`/`make probe` pass without probing anything. Verified by reading `probe_port` and `check_public_closed`. | fixed 9d1fe67, f47b3cf |
| R1-F2 | P1 | scripts/backup.sh:50-52 | Finalization renames the manifest and archive to their final names before writing `.sha256`; if that write fails (for example a full disk), an incomplete backup set stays published. Verified by reading the code. | fixed 2f97140 |
| R2-F1 | P1 | scripts/backup.sh:20-21 | The R1-F2 cleanup deleted this run's final file names even when they belonged to another run: two backups started in the same second (or after a clock rollback) share a name, and a failed run, even one that failed at the container stop, removed the other run's complete archive, manifest and checksum. Verified by reading the code and by two tests that fail on 2f97140. | fixed c2d505e |
| R3-F1 | P1 | scripts/backup.sh:23-29 | The R2-F1 reservation checked the final names before the exclusive create: run B could pass the check, pause, let run A finalize (A's `mv` removes A's `.partial`), then reserve the same name and overwrite or delete A's finished backup. Verified by reading the code. | fixed 2e09e2e |

## Notes

- Verified: the codex change review ran with `sandbox: read-only`; both raw reports held real review content.
- Codex could not run `make check` (no Docker in its sandbox). Test evidence comes from the author: 172 bats tests passing, 97.92% line coverage (plan Progress log).
- All scripts are stub-tested only; 16 live-VM checks moved to the [vm-rollout plan](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md)'s backlog file.
- R1-F1 now treats only an empty error, "refused", "timed out", "no route to host", "unreachable" or "prohibited" as a closed port; any other `nc` error stops verify. Assumption: the OCI Ubuntu image rejects with `icmp-host-prohibited`, which `nc` reports as "No route to host" (f47b3cf). Confirm the real `nc` wording on macOS during the [vm-rollout plan](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md); a wording not on the list fails loudly, never silently.
- After the R1 fixes `make check` passed with 181 tests and 97.99% line coverage.
- R2-F1 fix: backup.sh reserves `bm-<stamp>.tgz.partial` with an exclusive create (noclobber) and refuses a name whose final files already exist, both before the restart trap and the container stop; cleanup removes only this run's `.partial` files and the final files this run renamed. After the fix `make check` passed with 183 tests and 97.87% line coverage.
- Policy section 5 allows two rounds. The user asked to continue after R2-F1 was fixed, so a third round was run on the R2-F1 fix alone (d15d641..bcc66c5).
- R3-F1 fix: the exclusive create now comes first and the final names are checked after it. Another run's finalize turns its `.partial` into the final name with an atomic `rename`, so once this run holds the reservation, any name finished by another run is visible; on a taken name the run removes only its own reservation. The interleaving itself cannot be reproduced deterministically in bats, so there is no failing-first test for it. The existing "already exists" test now runs through the post-reservation check and asserts the reservation is released; removing the release line makes that test fail (mutation check). After the fix `make check` passed with 183 tests and 97.88% line coverage.
- The user chose a fourth round on the R3-F1 fix alone (bcc66c5..9c8b9e0); it found nothing further.
- In-plan SDD fixes on this branch use `Review-Finding: SDD-T<task>-F<n>`; they are unrelated to the `R1-F<n>` IDs above.
