# Review: work/backup-skip-model-cache

Cross-vendor review per `docs/specs/2026-10-07-git-review-policy-design.md`, section 5. Author: claude-code (Claude Sonnet implementer in an isolated worktree, Claude Opus controller reviewed the diff and re-ran `make check`). Reviewer: codex, run with `make review BRANCH=work/backup-skip-model-cache REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 71ad51b (main) | 3d60453 | mergeable; no defects in the change review; one P2 in the plan review |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| R1-F1 | P2 | docs/runbooks/operations.md:27 | The branch has `Plan: none`, so no plan Progress log or ADR records the passing `make check` that review rule 3 asks for. | fixed in this record: the author's test evidence is under Notes (same practice as `docs/reviews/work-slow-start-health.md`); plan 05's Progress log also records the finding that led to this branch |

## Notes

- Scope: plan 05 Step 12 (2026-10-13) found that `make restore` refused the first real backup: `ERROR: unsafe archive ...: it holds an entry that is not a regular file or directory`. Basic Memory's FastEmbed/HuggingFace model cache under `config/fastembed_cache/` stores `snapshots/<rev>/*` as relative symlinks to `../../blobs/*`; `scripts/backup.sh` archived them and the restore safety check (`scripts/restore.sh`, `check_archive_entries`) rightly rejects symlinks. So every backup made after the model downloaded was unrestorable. This branch keeps the re-downloadable cache out of both the tar stream and the manifest through one constant (`BM_MODEL_CACHE_REL_PATH` in `scripts/lib/common.sh`, `manifest_cmd` prunes it, `backup.sh` passes `--exclude`), and documents that Basic Memory downloads the model again on first use after a restore. The restore safety check is unchanged.
- Verified: the raw reports are `.review-out/work-backup-skip-model-cache-r1-codex-diff.md` ("이번 변경에서 확실한 신규 결함은 발견하지 못했습니다") and `.review-out/work-backup-skip-model-cache-r1-codex-plan.md` ("Verdict: mergeable" plus R1-F1). Codex could not run `make check` (no Docker socket in its sandbox).
- Test evidence from the author: RED before the fix, via `make test` in the test image (GNU tar): `not ok 2 backup excludes the model cache from the tar command`, `not ok 3 backup archive and manifest skip the model cache and restore accepts that archive`, `not ok 88 manifest_cmd skips the model cache but lists the other files`. After the fix the controller re-ran `make check` in the branch worktree: `1..225`, no `not ok`, total line coverage 97.97%; `make check-git`: OK. The existing test that refuses symlink archives passes unchanged.
- Still to verify on the VM after the merge (plan 05 Step 12): a new `make backup` from the main checkout, then `make restore` with the user's `yes`, and that the model downloads again on the first search.
- The backup made before this fix (`backups/bm-20261013T050026Z.tgz`) still holds the symlinks and stays unrestorable; it is kept, as backups are never deleted by agents.
