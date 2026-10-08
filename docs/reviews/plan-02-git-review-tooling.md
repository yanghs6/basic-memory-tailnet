# Review: plan/02-git-review-tooling

Cross-vendor review per `docs/specs/2026-10-07-git-review-policy-design.md`, section 5. Author: claude-code (Claude Opus controller, Sonnet/Opus implementers). Reviewer: codex, run with `make review BRANCH=plan/02-git-review-tooling REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 6417f00 (main) | 37e9956 | blocked (2 P1, 1 P2) |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P1 | scripts/review.sh:115 | With `REVIEWER=claude`, the change review runs `claude -p --permission-mode plan "/code-review …"` without `--agent branch-reviewer`, so the Bash guard hook and `disallowedTools` do not apply; plan mode alone does not restrict Bash. Verified by reading the code. | fixed 8184243 |
| R1-F2 | P1 | scripts/review-bash-guard.sh:26 | The guard allows `--ext-diff` and `--textconv`, which run external helpers configured in git config. `git diff` also uses `diff.external` and textconv drivers by default, so blocking the options alone is not enough. Verified: Codex showed both commands match the guard patterns. | fixed 144a9f8 |
| R1-F3 | P2 | scripts/check-git.sh:32 | Only the literal value `true` is flagged; `1`, `yes`, `on` enable `extensions.worktreeConfig` and pass. Spec section 2 says Antigravity breaks when the key is present, so any value should be flagged (stricter than the suggested `--bool`). | fixed e2acbb5 |

## Notes

- Verified (plan 02 Assumptions): the codex change review ran with `sandbox: read-only`; both raw reports held real review content; afterwards `git status` was clean and neither the review worktree nor a `review-base/*` branch remained.
- Codex could not run `make check` (no Docker in its sandbox). Test evidence comes from the plan's Progress log: 92 bats tests passing, 96.88% line coverage.
- Assumption (R1-F2 residual risk): the Claude reviewer's git ignores user and system config (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`), but a `diff.external` or textconv helper defined in the repository's own `.git/config` would still run; that config belongs to the human.
- In-plan SDD fixes on this branch use `Review-Finding: SDD-T<task>-F<n>`; they are unrelated to the `R1-F<n>` IDs above.
