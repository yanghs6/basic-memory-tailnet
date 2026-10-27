#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats runs each @test in a subshell; exports there stay in that test
load helpers

setup() {
  setup_stubs ssh docker sudo
  use_vm_env
  export BACKUP_DIR="$BATS_TEST_TMPDIR/backups"
  echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  BACKUP="$REPO_DIR/scripts/backup-notes.sh"
  RESTORE="$REPO_DIR/scripts/restore-notes.sh"
}

# make_archive NOTE -> creates $ARCHIVE (+ .sha256, .manifest) holding basic-memory/knowledge/restored.md
make_archive() {
  SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$SRC/basic-memory/knowledge" "$SRC/basic-memory/config"
  echo "$1" >"$SRC/basic-memory/knowledge/restored.md"
  mkdir -p "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/bm-20261007T000000Z.tgz"
  pack_archive basic-memory
  local_manifest "$SRC/basic-memory" >"$ARCHIVE.manifest"
}

# pack_archive TAR_ARGS... -> rebuild $ARCHIVE from $SRC with a valid .sha256 (the manifest is left as is).
pack_archive() {
  tar -C "$SRC" -czf "$ARCHIVE" "$@"
  printf '%s  %s\n' "$(sha256sum "$ARCHIVE" | awk '{ print $1 }')" "$(basename "$ARCHIVE")" >"$ARCHIVE.sha256"
}

# local_manifest DIR -> the manifest of DIR, built by the same command backup-notes.sh and restore-notes.sh run on the VM.
local_manifest() {
  bash -c "$(. "$REPO_DIR/scripts/lib/vm.sh" && manifest_cmd "$1")"
}

restore_with_answer() {
  run bash -c 'printf "%s\n" "$1" | "$0" "$2"' "$RESTORE" "$1" "$ARCHIVE"
}

# add_model_cache -> a HuggingFace-style cache in the fake data root: a blob plus a relative symlink to it.
add_model_cache() {
  local cache="$BM_REMOTE_DATA_ROOT/config/fastembed_cache"
  mkdir -p "$cache/blobs" "$cache/snapshots/rev"
  echo "model" >"$cache/blobs/hash1"
  ln -s ../../blobs/hash1 "$cache/snapshots/rev/model.onnx"
}

@test "a backup made by backup-notes.sh skips the model cache and restores with restore-notes.sh to match its manifest" {
  # A deployed VM already holds the current space files, which the restore writes again unchanged.
  local notes="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory"
  mkdir -p "$notes/Library/agent-hub"
  cp "$REPO_DIR/silverbullet/notes.gitignore" "$notes/.gitignore"
  cp "$REPO_DIR/silverbullet/agent-hub.md" "$notes/Library/agent-hub/agent-hub.md"
  cp "$REPO_DIR/silverbullet/index.md" "$notes/index.md"
  add_model_cache
  echo "{}" >"$BM_REMOTE_DATA_ROOT/config/config.json"
  run "$BACKUP"
  assert_success
  ARCHIVE="$(ls "$BACKUP_DIR"/bm-*.tgz)"
  run tar -tzf "$ARCHIVE"
  assert_line "basic-memory/config/config.json"
  refute_output --partial "fastembed_cache"
  run cat "$ARCHIVE.manifest"
  refute_output --partial "fastembed_cache"
  echo "changed after the backup" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  echo "written after the backup" >"$BM_REMOTE_DATA_ROOT/knowledge/later.md"
  restore_with_answer yes
  assert_success
  assert_output --partial "restored $(basename "$ARCHIVE")"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
  [[ ! -e "$BM_REMOTE_DATA_ROOT/knowledge/later.md" && ! -e "$BM_REMOTE_DATA_ROOT/config/fastembed_cache" ]] \
    || fail "the restored data root must hold only what the backup saved"
  run local_manifest "$BM_REMOTE_DATA_ROOT"
  assert_output "$(cat "$ARCHIVE.manifest")"
}

@test "restore replaces the data, writes the space files while stopped and the VM .env, on an existing and on a recreated VM" {
  local notes="$BM_REMOTE_DATA_ROOT/knowledge/basic-memory" expected_env="$BATS_TEST_TMPDIR/vm.env" case vm stop prev
  (
    # shellcheck source=../scripts/lib/vm.sh
    . "$REPO_DIR/scripts/lib/vm.sh"
    vm_env
  ) >"$expected_env"
  make_archive "from backup"
  # An archive from before the web UI: a notes folder with an index.md but no .gitignore and no library page.
  mkdir -p "$SRC/basic-memory/knowledge/basic-memory"
  echo "my dashboard" >"$SRC/basic-memory/knowledge/basic-memory/index.md"
  pack_archive basic-memory
  local_manifest "$SRC/basic-memory" >"$ARCHIVE.manifest"
  # Each case: the VM | stopped when its running stack must be stopped before the first space file write | kept when
  # the previous data must stay as .prev-* (a recreated VM has no data, compose.yaml or .env).
  for case in "existing|stopped|kept" "recreated||none"; do
    IFS='|' read -r vm stop prev <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      rm -rf "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_DATA_ROOT".* "$BM_REMOTE_APP_DIR" || exit 1
      mkdir -p "$BM_REMOTE_APP_DIR" || exit 1
      if [[ "$vm" == existing ]]; then
        mkdir -p "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config" || exit 1
        echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md" || exit 1
        echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml" || exit 1
        install -m 644 /dev/null "$BM_REMOTE_APP_DIR/.env" || exit 1
      fi
      restore_with_answer yes
      assert_success || exit 1
      run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
      assert_output "from backup" || exit 1
      run stat -c '%u' "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
      assert_output "1000" || exit 1
      assert_stub_called -F 'tar --no-same-owner --no-same-permissions -C' \
        && assert_stub_called -F 'compose up -d --wait --wait-timeout 360' || exit 1
      assert_same_file "$REPO_DIR/compose.yaml" "$BM_REMOTE_APP_DIR/compose.yaml" \
        && assert_same_file "$expected_env" "$BM_REMOTE_APP_DIR/.env" || exit 1
      run stat -c '%a' "$BM_REMOTE_APP_DIR/.env"
      assert_output "600" || exit 1
      # No .prev-* or .upload-* copy is left in the app dir once the restore succeeded.
      run ls -A "$BM_REMOTE_APP_DIR"
      assert_output "$(printf '%s\n' .env compose.yaml)" || exit 1
      assert_same_file "$REPO_DIR/silverbullet/notes.gitignore" "$notes/.gitignore" \
        && assert_same_file "$REPO_DIR/silverbullet/agent-hub.md" "$notes/Library/agent-hub/agent-hub.md" || exit 1
      run cat "$notes/index.md"
      assert_output "my dashboard" || exit 1
      # The marker must be gone: the stopped Basic Memory loads the new .gitignore when it starts.
      [[ ! -e "$notes/.gitignore.pending" ]] || exit 1
      # Every space file write (as the container user) comes before the first start, and after the stop when one is due.
      run awk -v stop="$stop" '/^docker compose stop$/ { s = NR } /^sudo -n -u #1000 / { if (!f) f = NR; w = NR } /^docker compose up/ && !u { u = NR } END { exit !(f && u && w < u && (stop == "" || (s && s < f))) }' "$STUB_LOG"
      assert_success || exit 1
      run ls -A "$(dirname "$BM_REMOTE_DATA_ROOT")"
      refute_line --regexp '^basic-memory\.restore-' || exit 1
      if [[ "$prev" == kept ]]; then
        assert_line --regexp '^basic-memory\.prev-' || exit 1
        run bash -c 'cat "$0".prev-*/knowledge/a.md' "$BM_REMOTE_DATA_ROOT"
        assert_output "original"
      else
        refute_line --regexp '^basic-memory\.prev-'
      fi
    ) || fail "restore on the $vm VM"
  done
}

@test "restore refuses before any ssh when the answer is not yes, SB_USER is missing, a backup file is missing, the checksum is wrong or the archive holds a symlink, a ../ or an absolute path" {
  local case input message detail answer entry
  # Each case: the bad input | the message of the check that refuses | the part of that message naming the reason.
  for case in "answer no|aborted: you must type 'yes'|" \
    "no SB_USER|missing env SB_USER|" \
    "missing archive|backup not found|" \
    "missing checksum file|checksum file missing|" \
    "missing manifest|manifest missing|" \
    "wrong checksum|checksum mismatch|" \
    "symlink entry|unsafe archive|not a regular file or directory" \
    "entry ../outside.md|unsafe archive|'..' component" \
    "entry $BATS_TEST_TMPDIR/outside.md|unsafe archive|absolute path"; do
    IFS='|' read -r input message detail <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      rm -rf "$BATS_TEST_TMPDIR/src" "$BACKUP_DIR" "$BATS_TEST_TMPDIR/outside.md" || exit 1
      echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md" || exit 1
      make_archive "x" || exit 1
      answer=yes
      case "$input" in
        "answer no") answer=no ;;
        "no SB_USER") unset SB_USER ;;
        "missing archive") ARCHIVE="$BACKUP_DIR/missing.tgz" ;;
        "missing checksum file") rm "$ARCHIVE.sha256" ;;
        "missing manifest") rm "$ARCHIVE.manifest" ;;
        "wrong checksum") echo "0000  $(basename "$ARCHIVE")" >"$ARCHIVE.sha256" ;;
        "symlink entry")
          ln -s /etc "$SRC/basic-memory/knowledge/etc" || exit 1
          pack_archive basic-memory || exit 1
          ;;
        "entry "*)
          entry="${input#entry }"
          echo "outside" >"$BATS_TEST_TMPDIR/outside.md" || exit 1
          pack_archive -P basic-memory "$entry" || exit 1
          run tar -tzf "$ARCHIVE"
          assert_line "$entry" || exit 1
          ;;
      esac
      restore_with_answer "$answer"
      assert_failure && assert_output --partial "$message" && refute_stub_called -F 'ssh' || exit 1
      if [[ -n "$detail" ]]; then
        assert_output --partial "$detail" || exit 1
      fi
      run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
      assert_output "original"
    ) || fail "restore did not refuse before ssh with: $input"
  done
}

@test "restore rolls the previous data, compose.yaml and .env back when the extract, the manifest, the upload, the swap, the pages or the start fails" {
  local case step message started back
  # Each case, in pipeline order: the step that fails | its message | started when the restored data was already started |
  # live when the rollback's own start succeeds, down when it fails too.
  for case in "extract|extract failed; current data was not touched||live" \
    "manifest|extracted files do not match the backup manifest||live" \
    "upload|could not upload compose.yaml||live" \
    "swap|could not swap the restored data into place||live" \
    "pages|could not write the SilverBullet pages||live" \
    "start|container did not become healthy with the restored data|started|live" \
    "start and rollback start|container did not become healthy with the restored data|started|down"; do
    IFS='|' read -r step message started back <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      rm -rf "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_DATA_ROOT".* "$BM_REMOTE_APP_DIR" "$BATS_TEST_TMPDIR/src" "$BACKUP_DIR" \
        "$STUB_BIN/cp" || exit 1
      mkdir -p "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config" "$BM_REMOTE_APP_DIR" || exit 1
      echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md" || exit 1
      echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml" || exit 1
      echo "PREVIOUS=env" >"$BM_REMOTE_APP_DIR/.env" || exit 1
      make_archive "bad" || exit 1
      case "$step" in
        extract) export SSH_STUB_FAIL_MATCH="-xzf" ;;
        manifest) echo "0000  ./knowledge/missing.md" >>"$ARCHIVE.manifest" ;;
        upload)
          # A cp that dies midway (disk full): it leaves a partial destination file and fails.
          # shellcheck disable=SC2016 # the fake cp body must keep ${@: -1} literal
          fake_cmd cp 'printf partial >"${@: -1}"; exit 1' || exit 1
          ;;
        swap) export SSH_STUB_FAIL_MATCH="rmdir" ;;
        pages) export SSH_STUB_FAIL_MATCH="Library/agent-hub" ;;
        # Only the restore's own start fails; the rollback start succeeds.
        start) export DOCKER_STUB_FAIL_MATCH="up -d --wait" ;;
        # Every start fails, the rollback's too.
        "start and rollback start") export DOCKER_STUB_FAIL_MATCH="up -d" ;;
      esac
      restore_with_answer yes
      assert_failure && assert_output --partial "$message" && assert_output --partial "restore failed; rolling back" || exit 1
      if [[ "$back" == live ]]; then
        assert_output --partial "rolled back: the previous data is live again" || exit 1
      else
        refute_output --partial "the previous data is live again" || exit 1
      fi
      run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
      assert_output "original" || exit 1
      run cat "$BM_REMOTE_APP_DIR/compose.yaml"
      assert_output "previous compose" || exit 1
      run cat "$BM_REMOTE_APP_DIR/.env"
      assert_output "PREVIOUS=env" || exit 1
      # No temporary copy is left: no .prev-* or .restore-* next to the data root, only the two files in the app dir.
      run ls -A "$(dirname "$BM_REMOTE_DATA_ROOT")"
      refute_line --regexp '^basic-memory\.(prev|restore)-' || exit 1
      run ls -A "$BM_REMOTE_APP_DIR"
      assert_output "$(printf '%s\n' .env compose.yaml)" || exit 1
      if [[ "$started" == started ]]; then
        # The restored data is kept aside, and the rollback recreates the container so it mounts the previous data.
        run bash -c 'cat "$0".failed-*/knowledge/restored.md' "$BM_REMOTE_DATA_ROOT"
        assert_output "bad" && assert_stub_called -F 'docker compose up -d --force-recreate --wait --wait-timeout 360'
      else
        # Only the rollback starts the containers (on the previous data); the restored data never runs.
        refute_stub_called -E '^docker compose up -d --wait'
      fi
    ) || fail "restore after a failed $step"
  done
}

@test "restore on a VM without previous data says the restored data stays when the start fails" {
  make_archive "restored"
  rm -r "$BM_REMOTE_DATA_ROOT"
  export DOCKER_STUB_FAIL_MATCH="up -d"
  restore_with_answer yes
  assert_failure
  refute_output --partial "the previous data is live again"
  assert_output --partial "had no data before this restore"
  assert_output --partial "the restored data is now at $BM_REMOTE_DATA_ROOT"
  assert_output --partial "rerun 'make restore BACKUP=<archive>'"
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
  assert_output "restored"
}

@test "restore with BM_WEB=on and a missing or malformed setting stops before ssh and names only the variable" {
  local case name value
  make_archive "from backup"
  use_web_env
  for case in "BM_WEB_JWT_KEY|key with space" "BM_WEB_GITHUB_CLIENT_SECRET|" "BM_WEB_TUNNEL_TOKEN|tok\$en" "BM_WEB_HOST|https://mcp.example.com"; do
    IFS='|' read -r name value <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      export "$name=$value"
      restore_with_answer yes
      assert_failure && assert_output --partial "$name" && refute_stub_called -E '^(ssh|docker|sudo) ' || exit 1
      if [[ -n "$value" ]]; then
        refute_output --partial "$value"
      fi
    ) || fail "restore went on with $name='$value'"
  done
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}

@test "restore with BM_WEB=on uploads the gateway runtime files before starting the stack on a VM that never ran the gateway" {
  local file secret
  make_archive "from backup"
  use_web_env
  [[ ! -e "$BM_REMOTE_APP_DIR/gateway" ]] || fail "the fake VM must start without gateway files"
  restore_with_answer yes
  assert_success
  for secret in test-client-secret fake-jwt-key-fake-jwt-key-fake-jwt-key test-tunnel-token; do
    refute_output --partial "$secret"
  done
  for file in boot.py gateway.py requirements.txt; do
    assert_same_file "$REPO_DIR/gateway/$file" "$BM_REMOTE_APP_DIR/gateway/$file"
  done
  assert_log_order "gateway/boot.py" "docker compose up -d --wait --wait-timeout 360"
  assert_log_order "gateway/gateway.py" "docker compose up -d --wait --wait-timeout 360"
  assert_log_order "gateway/requirements.txt" "docker compose up -d --wait --wait-timeout 360"
  run grep -x 'COMPOSE_PROFILES=web,tunnel' "$BM_REMOTE_APP_DIR/.env"
  assert_success
}

@test "restore with BM_WEB=off uploads no gateway files" {
  make_archive "from backup"
  restore_with_answer yes
  assert_success
  [[ ! -e "$BM_REMOTE_APP_DIR/gateway" ]] || fail "a BM_WEB=off restore uploaded the gateway files"
}

@test "restore with BM_WEB=on succeeds once the note services are healthy, and only warns without a rollback when the web services are not" {
  local case failing warned
  make_archive "from backup"
  use_web_env
  # Each case: the compose call that fails (none: every service healthy) | warned when the restore must warn about the
  # web services. The restore waits for the note services, starts the rest with a plain up -d, then waits once for all.
  for case in "|" "compose up -d|warned" "compose up -d --wait --wait-timeout 360|warned"; do
    IFS='|' read -r failing warned <<<"$case"
    (
      : >"$STUB_LOG" || exit 1
      rm -rf "$BM_REMOTE_DATA_ROOT" "$BM_REMOTE_DATA_ROOT".* || exit 1
      mkdir -p "$BM_REMOTE_DATA_ROOT/knowledge" "$BM_REMOTE_DATA_ROOT/config" || exit 1
      echo "original" >"$BM_REMOTE_DATA_ROOT/knowledge/a.md" || exit 1
      export DOCKER_STUB_FAIL_EXACT="$failing"
      restore_with_answer yes
      assert_success && assert_output --partial "restored $(basename "$ARCHIVE")" && refute_output --partial "rolling back" || exit 1
      if [[ "$warned" == warned ]]; then
        assert_output --partial "WARNING: the web connector services" || exit 1
      else
        refute_output --partial "WARNING" || exit 1
      fi
      refute_stub_called -F -- '--force-recreate' || exit 1
      run awk '$0 == "docker compose up -d --wait --wait-timeout 360 basic-memory silverbullet" && !n { n = NR } $0 == "docker compose up -d" && !p { p = NR } END { exit !(n && p && n < p) }' "$STUB_LOG"
      assert_success || exit 1
      run cat "$BM_REMOTE_DATA_ROOT/knowledge/restored.md"
      assert_output "from backup"
    ) || fail "restore with BM_WEB=on and a failing '$failing'"
  done
}

@test "restore with BM_WEB=on rolls back by the same rule: it waits only for the note services and only warns about the web services" {
  make_archive "bad"
  use_web_env
  echo "previous compose" >"$BM_REMOTE_APP_DIR/compose.yaml"
  echo "PREVIOUS=env" >"$BM_REMOTE_APP_DIR/.env"
  # The restore's start of the note services fails, the rollback's succeeds; the web services stay unhealthy.
  export DOCKER_STUB_FAIL_EXACT=$'compose up -d --wait --wait-timeout 360 basic-memory silverbullet\ncompose up -d --wait --wait-timeout 360'
  restore_with_answer yes
  assert_failure
  assert_output --partial "container did not become healthy with the restored data"
  assert_output --partial "rolled back: the previous data is live again"
  assert_output --partial "WARNING: the web connector services"
  assert_stub_called -Fx 'docker compose up -d --force-recreate --wait --wait-timeout 360 basic-memory silverbullet'
  refute_stub_called -Fx 'docker compose up -d --force-recreate --wait --wait-timeout 360'
  run cat "$BM_REMOTE_DATA_ROOT/knowledge/a.md"
  assert_output "original"
}
