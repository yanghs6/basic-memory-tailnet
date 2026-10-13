# Review: work/skill-best-practices

Cross-vendor review per `docs/specs/spec-2026-10-07-restd5vd-git-review-policy.md`, section 5. Author: claude-code (Claude Opus controller, Sonnet subagents for research and read-only scenarios). Reviewer: codex, run by the human with `make review BRANCH=work/skill-best-practices REVIEWER=codex`.

| Round | Reviewer | Base | Reviewed head | Verdict |
|---|---|---|---|---|
| R1 | codex gpt-6.1-sol (sandbox read-only) | 56d3ab4 (main) | 49afdf9 | mergeable; no findings in the change review or the plan review |

## Findings

| ID | Sev | Location | Summary | Status |
|---|---|---|---|---|
| — | — | — | No findings. | — |

## Notes

- Scope: the user asked to research skill best practices and apply them with a focus on flexibility and extensibility. 49afdf9 restructures the five skills (rules, checklist, steps, gotchas; `references/` for the error catalog, the rollback and the review/merge phases), moves cloud commands out of skills into the runbooks, rewrites the descriptions, turns `## Skills` in AGENTS.md into situation-to-skill routing, adds the `skill-authoring` skill with a template, and collects all skill checks in `tests/skills.bats`. Decision and sources: `docs/decisions/adr-2026-10-13-m0xvj6rr-skill-structure.md`.
- Verified: the raw reports are `.review-out/work-skill-best-practices-r1-codex-diff.md` ("수정이 필요한 동작 결함이나 요구사항 누락을 발견하지 못했습니다") and `.review-out/work-skill-best-practices-r1-codex-plan.md` ("Verdict: mergeable"). Codex did not run the tests, and its git policy check could not finish because the review checkout is a detached HEAD.
- Test evidence from the author: RED (the new skills cloud-neutral test and the template test failed), then `make check` passed with 234 tests and 97.97% line coverage, and `make check-git` reported "OK: git policy (1 commits since main)". A temporary skill with 13 violations failed all 13 checks after the frontmatter-key regex fix (the old check let `when_to_use` through since the [git-review-tooling plan](../plans/plan-2026-10-07-qq4h1djv-git-review-tooling.md)); it was removed. `git merge-tree` against `plan/qtvzskgx-vm-rollout` showed no conflict.
- AGENTS.md changed (`## Skills` routing, the `.agents/skills` map line); the human should read that diff before merging.
- Follow-ups after the [vm-rollout plan](../plans/plan-2026-10-07-qtvzskgx-vm-rollout.md) merges: split the last paragraph of `bm-recover` (kept byte-identical to avoid a conflict) into its Gotchas, and update "Assumption, confirmed in the vm-rollout plan item 29" in `bm-diagnose/references/failure-messages.md` once the vm-rollout plan records it.
