---
name: skill-authoring
description: Conventions for the agent skills of this repo (.agents/skills folders, .claude/skills links, SKILL.md frontmatter, references and assets). Use when adding, renaming, splitting or editing a skill, when moving a procedure from AGENTS.md or a runbook into a skill, or when a skill does not load or trigger in Claude Code, Codex, Gemini CLI or Antigravity. Not for following an existing skill.
---

# Author a repository skill

Claude Code, Codex, Gemini CLI and Antigravity share these skills, so they follow the Agent Skills specification (https://agentskills.io/specification) and nothing tool-specific. `make check` runs `tests/skills.bats`, which enforces every rule marked (tested).

## Add a skill

1. Start a worktree and a `work/<slug>` branch through `git-workflow`.
2. Choose the name: lowercase words joined by single hyphens, at most 64 characters, equal to the folder name (tested). Prefix VM operations with `bm-`. Check `ls ~/.claude/skills ~/.agents/skills`: in Claude Code a personal skill with the same name hides the repo skill.
3. Copy [assets/skill-template.md](assets/skill-template.md) to `.agents/skills/<name>/SKILL.md` and fill it in (see Description and Body below).
4. Link it for Claude Code, which reads only `.claude/skills/` (tested): `ln -s ../../.agents/skills/<name> .claude/skills/<name>`.
5. Add the skill to both indexes (tested): a "situation: `<name>`" line under `## Skills` in AGENTS.md, which tells agents when to load it, and the name in the skill list of README.md.
6. Test it (below), run `make check`, and commit through `git-workflow`.

To rename or remove a skill, change the folder, the link, both indexes and every mention (`git grep -n <name>`); the tests fail on a stale link.

## Description

One plain YAML line, at most 1024 characters, without `: `, ` #` or angle brackets (tested). Use this order:

1. What the skill does, in one sentence and third person.
2. `Use when` plus the user's own words and the symptoms: error text, the failing make target (tested: contains `Use when`).
3. `Not for` the nearest miss, naming the sibling skill that handles it.

Put the key words first, because tool skill lists shorten long descriptions. Never summarize the steps: agents then follow the summary and skip the body.

## Body

- English, imperative, at most 500 lines (tested), ideally under 5,000 tokens.
- Rules that must never be broken go first: after a long session only the start of a skill may stay in context.
- Operational skills use the template's shape: Rules, a checklist to copy, numbered steps with exact commands, Gotchas. Mark each step that changes the VM, cloud resources or data with "Ask first".
- One default per step, not a menu. Exact commands where a mistake is costly; judgment only where situations differ.
- A step is a make target or a script call plus what to read in its output. When a step needs a check no target or script makes yet (a checksum, an archive listing, a count), add it to a script with a bats test and call that script; first look whether a script already checks it (for example `scripts/restore.sh` checks the archive checksum and manifest).
- Keep each value in one place. Name settings by their `.env.example` variable and default (`BM_VM_HOST`, default `agent-hub`).
- Cloud commands, regions and instance names live only in the runbooks (tested: skills name no cloud provider). When a step needs a cloud command, add it to the right runbook section (Korean, with the personal configuration flag) and point to that section by name from the skill.
- Refer to other skills by name (`use bm-diagnose`) and to repo files by path. Link a runbook section instead of copying it.

## Bundled files

- `references/<topic>.md`: detail that only some runs need, such as an error catalog or a rollback. Link it from SKILL.md with a Markdown link and say when to read it, for example: if verify fails, read references/rollback.md. Every bundled file is named in SKILL.md, and a reference file points to no other file of its skill (both tested).
- `assets/`: templates and other files used in the output.
- `scripts/`: logic used by this skill alone; prefer the repo's `scripts/` with tests. Call a bundled script as `bash scripts/<file>.sh` and keep it non-interactive.
- `agents/openai.yaml`: optional Codex display and invocation settings; other tools ignore it.
- Nothing else: no README and no nested SKILL.md (tested).

## Test the skill

1. Write two or three prompts in the user's words that should use the skill, and two near misses that belong to a sibling skill or to none.
2. Run each prompt in a fresh agent session: first in the main checkout (the old skill or none, the baseline), then in your worktree. Tell the agent to describe its plan without changing anything.
3. Compare: did it pick the skill, open the right reference, stop at every "Ask first", and use make targets instead of raw commands? Fix the description when it picks the wrong skill and the body when it acts wrongly, then run again.
4. Record the prompts and results in the commit body, the plan's Progress log, or on a work branch the PR body's Verification.

## Gotchas

- Another skill is not proof of a rule: older skills may predate these conventions, and copying them spreads a hardcoded value. Check new text against this skill.
- Tool-specific frontmatter keys (`disable-model-invocation`, `when_to_use`, `context`) break the specification validator and uploads (tested). Put tool-specific data in `metadata` (string values) or `agents/openai.yaml`.
- Gemini CLI finds skills only one folder deep: no category folders under `.agents/skills/`.
- Strict YAML parsers reject flow style (`{}`, `[]`) in frontmatter.
- A rule that must hold every time belongs in a test or a hook, not only in skill prose.
