#!/usr/bin/env bash
set -euo pipefail

review_label_for() {
  local reviewer="$1"
  local target="$2"
  local -a order=(melchior balthasar caspar)
  local -a labels=(alpha beta gamma)
  local i j
  for i in "${!order[@]}"; do
    if [[ "${order[$i]}" == "$target" ]]; then
      echo "${labels[$i]}"
      return 0
    fi
  done
  echo "unknown"
}

review_pairs() {
  # reviewer -> target (each reviews the other two)
  local reviewer="$1"
  local -a targets=()
  local a
  for a in "${AGENTS[@]}"; do
    [[ "$a" == "$reviewer" ]] && continue
    targets+=("$a")
  done
  printf '%s\n' "${targets[@]}"
}

review_phase() {
  local repo="$1"
  local sid="$2"
  load_merged_config "$repo"
  local anon="$CONFIG_REVIEW_ANON"
  local backend
  backend="$(detect_agent_backend "$CONFIG_AGENT_BACKEND")"
  local session_dir
  session_dir="$(session_dir_for "$repo" "$sid")"
  worktree_collect_all "$repo" "$sid"
  local diffs_dir="${session_dir}/diffs"
  session_update_meta "$repo" "$sid" "review"
  local reviewer target label diff_path prompt_file prompt
  for reviewer in "${AGENTS[@]}"; do
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      diff_path="${diffs_dir}/${target}.diff"
      [[ -f "$diff_path" ]] || diff_path="/dev/null"
      label="$(review_label_for "$reviewer" "$target")"
      if [[ "$anon" == "true" ]]; then
        label="implementation-${label}"
      else
        label="${target}"
      fi
      prompt_file="${session_dir}/review-${reviewer}-of-${target}.prompt.md"
      render_template "${CODEPRISM_ROOT}/templates/review.txt" "$prompt_file" \
        SESSION_ID "$sid" \
        REVIEWER_PERSONA "$(<"$(persona_path_for_agent "$reviewer" "$repo")")" \
        TARGET_LABEL "$label" \
        DIFF "$(<"$diff_path")"
      prompt="$(<"$prompt_file")"
      run_agent "$backend" "$prompt" "$repo" "$CONFIG_AGENT_MODEL" "$session_dir" "review-${reviewer}-of-${target}"
    done < <(review_pairs "$reviewer")
  done
  log_info "Review phase complete for session $sid"
}
