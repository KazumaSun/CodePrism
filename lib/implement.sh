#!/usr/bin/env bash
set -euo pipefail

implement_phase() {
  local repo="$1"
  local sid="$2"
  local task="$3"
  local base="$4"
  load_merged_config "$repo"
  local backend
  backend="$(detect_agent_backend "$CONFIG_AGENT_BACKEND")"
  local session_dir
  session_dir="$(session_dir_for "$repo" "$sid")"
  local wt_json
  wt_json="$(session_load_worktrees "$repo" "$sid")"
  if [[ "$wt_json" == "{}" || -z "$wt_json" ]]; then
    worktree_register_all "$repo" "$sid" "$base"
    wt_json="$(session_load_worktrees "$repo" "$sid")"
  fi
  session_update_meta "$repo" "$sid" "implement"
  local pids=()
  local agent persona_path wt_path branch prompt_file prompt
  for agent in "${AGENTS[@]}"; do
    wt_path="$(worktree_path_from_json "$wt_json" "$agent")"
    persona_path="$(persona_path_for_agent "$agent" "$repo")"
    branch="$(agent_branch_name "$sid" "$agent")"
    prompt_file="${session_dir}/implement-${agent}.prompt.md"
    render_template "${CODEPRISM_ROOT}/templates/implement.txt" "$prompt_file" \
      SESSION_ID "$sid" \
      AGENT_NAME "$agent" \
      PERSONA "$(<"$persona_path")" \
      TASK "$task" \
      REPO_PATH "$repo" \
      BASE_BRANCH "$base" \
      WORKTREE_PATH "$wt_path" \
      BRANCH "$branch"
    prompt="$(<"$prompt_file")"
    if [[ "$DRY_RUN" == "1" ]]; then
      run_agent "$backend" "$prompt" "$wt_path" "$CONFIG_AGENT_MODEL" "$session_dir" "implement-${agent}"
    else
      (
        run_agent "$backend" "$prompt" "$wt_path" "$CONFIG_AGENT_MODEL" "$session_dir" "implement-${agent}"
      ) &
      pids+=($!)
    fi
  done
  if [[ "$DRY_RUN" != "1" ]]; then
    for pid in "${pids[@]}"; do
      wait "$pid" || log_warn "Agent process $pid exited non-zero"
    done
    if [[ "$backend" != "manual" ]]; then
      worktree_commit_all "$repo" "$sid" "implement"
    fi
  fi
  log_info "Implement phase complete for session $sid (backend=$backend)"
}
