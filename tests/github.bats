#!/usr/bin/env bats
load helpers

setup() {
  WORKFLOWS="$REPO_DIR/.github/workflows"
  RULESET="$REPO_DIR/.github/rulesets/main.json"
}

@test "workflows run read-only on pull_request, pin actions by commit SHA and keep expressions out of run lines" {
  local file files bad=""
  files="$(find "$WORKFLOWS" -name '*.yml' 2>/dev/null | sort)"
  [[ -n "$files" ]] || fail "no workflows under .github/workflows"
  [[ -z "$(find "$WORKFLOWS" -name '*.yaml')" ]] || fail "use .yml for workflows: the tests read only *.yml"
  while IFS= read -r file; do
    ! grep -qE '^    name:' "$file" || bad="$bad $(basename "$file")(job name: it renames the check-run and breaks the required checks)"
    ! grep -qE '^ +[a-z-]+: write' "$file" || bad="$bad $(basename "$file")(write permission)"
    ! grep -qE '^    permissions:' "$file" || bad="$bad $(basename "$file")(job-level permissions)"
    grep -qx 'permissions:' "$file" && grep -qx '  contents: read' "$file" || bad="$bad $(basename "$file")(permissions)"
    ! grep -q 'pull_request_target' "$file" || bad="$bad $(basename "$file")(pull_request_target)"
    ! grep -E 'uses: ' "$file" | grep -vqE 'uses: [^@ ]+@[0-9a-f]{40}( |$)' || bad="$bad $(basename "$file")(action not pinned by SHA)"
    ! grep -qE '^ *(- )?run: *[|>]' "$file" || bad="$bad $(basename "$file")(multi-line run)"
    ! grep -qE '^ *(- )?run:.*\$\{\{' "$file" || bad="$bad $(basename "$file")(expression in run; pass it through env)"
  done <<<"$files"
  [[ -z "$bad" ]] || fail "fix these workflows:$bad"
}

@test "the main ruleset keeps one human approval, squash only and no bypass, and requires the jobs the workflows define" {
  run jq -e '
    .enforcement == "active" and .bypass_actors == []
    and .conditions.ref_name.include == ["~DEFAULT_BRANCH"]
    and ((["deletion", "non_fast_forward", "required_linear_history", "pull_request", "required_status_checks"] - [.rules[].type]) == [])
    and (.rules[] | select(.type == "pull_request") | .parameters
      | .required_approving_review_count >= 1 and .dismiss_stale_reviews_on_push and .require_last_push_approval
        and .required_review_thread_resolution and .allowed_merge_methods == ["squash"])
    and (.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy)
    and (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks | all(.integration_id == 15368))
  ' "$RULESET"
  assert_success
  local required jobs
  required="$(jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' "$RULESET" | sort)"
  jobs="$(awk '/^jobs:/ { inside = 1; next } /^[a-z]/ { inside = 0 } inside && /^  [a-z0-9-]+:$/ { sub(/^ +/, ""); sub(/:$/, ""); print }' "$WORKFLOWS"/*.yml | sort)"
  [[ -n "$required" ]] || fail "the ruleset requires no status checks"
  [[ "$required" == "$jobs" ]] || fail "required checks ($required) must equal the workflow job ids ($jobs)"
}
