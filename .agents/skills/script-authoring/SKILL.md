---
name: script-authoring
description: Creates and changes this repo's bash scripts, libraries, Make targets and bats tests with make new-script and the templates in assets. Use when adding, renaming or editing a script under scripts/, a Make target, a bats test, a stub or a fixture, or when make check reports a missing pair test or an unknown verb. Not for documents (use doc-authoring) or skills (use skill-authoring).
---

# Write scripts, libraries, Make targets and tests

Every agent adds shell code the same way: `make new-script` writes a script and its pair test from the templates in `assets/`, and `make check` (lint, all tests, coverage) stops what breaks the rules below. Use this skill together with `git-workflow`, which covers the worktree, the branch and the commit.

## Rules

- Write the bats test first and watch it fail with `make test` before you write the code. Every script, remote script and library has exactly one pair test (Tests).
- Create a new script or library only with `make new-script`; never copy a neighboring file, which may predate these rules.
- Scripts in `scripts/remote/` run alone on the VM: they source nothing from `scripts/lib/` and keep their own `log`, `die` and constants.
- Before you write a helper, read the function index at the top of each `scripts/lib/` library (Libraries) and call the helper that already exists.
- The script rules in `AGENTS.md` Invariants hold for every file: the strict mode header, `die` with an actionable message, named constants, `mask` for secrets, and the macOS bash 3.2 limits. Read them there; they are not repeated here.
- Run tests only with `make test` or `make check`, never `bats` or `docker run` yourself.

## Name and place

| What | File | Pair test | Name |
|---|---|---|---|
| script | `scripts/<verb>-<object>.sh`, executable | `tests/<verb>-<object>.bats` | a verb from the Verbs table, then the object |
| remote script | `scripts/remote/<verb>-<object>.sh`, executable | `tests/remote-<verb>-<object>.bats` | the same |
| library | `scripts/lib/<topic>.sh`, not executable | `tests/lib-<topic>.bats` | the topic it holds, not an action (`vm`, `sb`) |
| repo-wide rule | none | `tests/repo-<topic>.bats` | the topic of the rule |

- Names are lowercase letters and digits joined by single hyphens. The test name copies the script name with its hyphens; `pair_test` in `scripts/lib/layout.sh` is the rule.
- Keep `scripts/` and `tests/` flat: the only folders are `scripts/remote/`, `scripts/lib/`, `tests/stubs/` and `tests/fixtures/`. bats runs no subfolder without `-r`, and the libraries find the repo root by their depth.
- A script sources only the libraries it needs. A topic library starts with a source guard (`[ -n "${_BM_LIB_<TOPIC>:-}" ] && return 0`) and sources `common.sh`.
- The header comment says what the script does and its usage line: the command people run, `# Usage: make <target> ...` when a Make target runs it.
- Make target names are what people type and do not change, so a target and its script may differ (`make logs` runs `scripts/show-logs.sh`). The Makefile is the map between them.

Background: `docs/specs/spec-2026-10-15-d8q0b7bt-script-test-layout.md`, sections 3, 4 and 6.

## Verbs

This table is the canonical verb list: `make new-script` and the repo checks read its first column. When no verb fits, add a row (verb, meaning, example) in the same change as the script that needs it.

| Verb | Meaning | Example |
|---|---|---|
| bootstrap | Prepares a new VM for first use (runs locally) | `bootstrap-vm` |
| provision | Installs packages and services inside the VM | `remote/provision-vm` |
| deploy | Deploys or restarts the services | `deploy-stack` |
| backup | Downloads data and keeps it | `backup-notes` |
| restore | Puts a kept copy back | `restore-notes` |
| export | Downloads records such as logs into local files in a format for other tools | `export-logs` |
| show | Prints state or logs and changes nothing | `show-status`, `show-logs` |
| verify | Checks a running service end to end | `verify-mcp`, `verify-sb`, `verify-vm` |
| check | Checks rules or the environment and only reports; changes nothing | `check-git`, `check-pr`, `check-access` |
| open | Holds a connection open in the foreground and exits with its exit code | `open-tunnel` |
| sync | Brings files to the wanted state; running it again gives the same result | `sync-sb-space` |
| upload | Uploads built files to the VM | `upload-sb-fonts` |
| review | Runs a review | `review-branch` |
| post | Posts to a pull request | `post-review`, `post-review-record` |
| guard | Filters commands in a hook | `guard-reviewer-bash` |
| create | Creates files from a template | `create-doc`, `create-script` |

## Libraries

Each library starts with a function index, one line per function. Read it before you add a helper, and add your function to it.

- `scripts/lib/common.sh`: core helpers every script needs (logging, `die`, required commands and settings, `mask`), the repo root and shared constants.
- `scripts/lib/vm.sh`: the VM layout, the access mode, SSH and compose on the VM, the data manifest.
- `scripts/lib/sb.sh`: the SilverBullet space in the notes folder and the SilverBullet login.
- `scripts/lib/git.sh`: commit trailer rules, problem lists, review report paths.
- `scripts/lib/docs.sh`: the document type registry and document ids.
- `scripts/lib/layout.sh`: the verbs of this skill's table, the folder of each kind of script (`script_dir`) and the pair test of a script.

## Tests

- One pair test per script (Name and place). Start the file with `load helpers`; outside functions put only `load helpers` and constants.
- Fake external commands live in `tests/stubs/<command>`, one executable per command. `setup_stubs <command>...` puts them first on PATH, and each logs its arguments to `$STUB_LOG`.
- Recorded responses live in `tests/fixtures/<test name>/`, named after the pair test without `.bats` (for example `tests/fixtures/verify-mcp/`).
- Use the helpers in `tests/helpers.bash` before you write your own, for example `setup_stubs`, `fake_cmd`, `use_vm_env`, `init_git_repo`, `assert_stub_called`, `refute_stub_called`, `assert_log_order`, `assert_same_file` and `refute_matches`. Each has a usage comment there.
- Keep only tests that `docs/decisions/adr-2026-10-13-a878ypj5-test-scope.md` allows. Its decision 2 rules out a test that repeats another test, checks only wording or format, tests a stub or helper itself, repeats a constant or document text, or checks a usage message.
- Cases that differ only in their input go in one test with a loop, named for everything the loop checks. Run each case in a subshell, `( ... ) || fail "<the case>"`, so no variable, PATH entry or file leaks into the next case; inside it chain the commands with `&&` and end with `|| exit 1`, because errexit is off there.
- Test a library function's behavior once, in the library's `tests/lib-<topic>.bats`. A script test only shows that the script calls it; to show that several scripts call the same check, loop over the scripts in that lib test.
- Assert a message only to tell which check stopped the script; never assert the wording of a hint.

## Make targets

- Add a target only when people run the script; a script that other scripts or CI call needs none.
- Write `<target>: ## <description>` (`make help` prints it) and add the target to `.PHONY`. `tests/repo-make.bats` checks both and that no target is defined twice.
- Pass arguments as make variables, quoted in the recipe, as the `new-doc` target does: `scripts/create-doc.sh "$(TYPE)" "$(SLUG)"`.
- Ask the user before you run a target that changes the VM or cloud resources (`AGENTS.md`, Safety).

## Templates

`make new-script` copies these and replaces `{{name}}` (and, in a library, the guard name `_BM_LIB_NAME`). Fill every other `{{...}}` blank or delete its line.

- script: [assets/script.sh](assets/script.sh) and [assets/script.bats](assets/script.bats)
- remote script: [assets/remote.sh](assets/remote.sh) and [assets/remote.bats](assets/remote.bats)
- library: [assets/lib.sh](assets/lib.sh) and [assets/lib.bats](assets/lib.bats)
- [assets/.shellcheckrc](assets/.shellcheckrc): `make lint` checks the templates where they are, and this file turns off only SC1091 for them, because the files they source exist only where `make new-script` writes them.

## Steps

Copy this checklist into your reply and tick each item:

- [ ] 1. `make new-script NAME=<name> [KIND=script|remote|lib]`
- [ ] 2. Pair test written, `make test` fails only on the new tests
- [ ] 3. Code written, `make test` passes
- [ ] 4. Make target and the files that name scripts updated
- [ ] 5. `make check` passes, committed through `git-workflow`

1. Pick the kind and the name (Name and place, Verbs), then run `make new-script NAME=<name> [KIND=script|remote|lib]` in your worktree. It prints the script and the test path. It refuses a script name that does not start with a verb from the table or has no object, and it writes nothing when the script or its test already exists.
2. Write the test: replace the two `{{...}}` test blocks with a real success path and a real failure path (Tests). Run `make test`. Only the new tests fail: a script template dies with "not implemented", and a new library has no function yet.
3. Write the code: fill the header blanks (what it does, usage), replace the `die "not implemented ..."` line, source the library you need and name every constant. Run `make test` until it passes.
4. If people run it, add the Make target (Make targets). Update the files that name scripts or libraries: the component table and the library list in `docs/ARCHITECTURE.md`, and the runbook or skill that tells people to run it.
5. Run `make check`, then commit through `git-workflow`.

To rename a script, `git mv` it with its pair test and its fixtures folder, then fix every mention (`git grep -n <old name>`). Records (completed plans, specs, ADRs, review records) keep the old name.

## Gotchas

- `make check` runs the tests under kcov, whose exported `PS4` reads `BASH_SOURCE`. At the top level of a `bash -c` string `BASH_SOURCE` is unset, so `set -u` stops that child shell ("BASH_SOURCE: unbound variable") although `make test` passes. Run a child shell from a temporary script file instead, as `tests/lib-sb.bats` does.
- A bare `return` inside a trap handler, or in a function a trap calls, returns the status from before the trap (`die`'s 1), not the last command's. End such a function with if/else, as `remote_compose` in `scripts/lib/vm.sh` does.
- `die` inside `$(...)` ends only that subshell. The caller sees a failed assignment, which errexit ignores while the function runs under `if`, `&&`, `||` or `!`, and which `local x="$(fn)"` hides. Write `x="$(fn)" || exit 1`, with `local x` on a line of its own.
- kcov counts only what runs from `scripts/` in the repo, and `make check` fails when an executable script is never run by a test ("never executed by any test"). Run the script from `$REPO_DIR/scripts`, not from a copy.
- bats runs each `@test` in a subshell, so an export stays in its test; shellcheck still reports SC2030 and SC2031 for it. A test file that exports in its tests turns both off on the line after the shebang, never in the repo `.shellcheckrc`, where they are real warnings for scripts.
