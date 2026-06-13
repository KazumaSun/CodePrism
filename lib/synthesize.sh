#!/usr/bin/env bash
set -euo pipefail

synthesize_phase() {
  local repo="$1"
  local sid="$2"
  local task="$3"
  load_merged_config "$repo"
  local rapporteur="$CONFIG_RAPPORTEUR"
  local backend
  backend="$(detect_agent_backend "$CONFIG_AGENT_BACKEND")"
  local session_dir
  session_dir="$(session_dir_for "$repo" "$sid")"
  session_update_meta "$repo" "$sid" "synthesize"
  local summaries=""
  local agent
  for agent in "${AGENTS[@]}"; do
    local d="${session_dir}/diffs/${agent}.diff"
    local lines=0
    if [[ -f "$d" ]]; then
      lines=$(wc -l <"$d" | tr -d ' ')
    fi
    summaries+="- ${agent}: diff lines=${lines}"$'\n'
  done
  local reviews=""
  local f
  for f in "${session_dir}"/review-*.prompt.md; do
    [[ -e "$f" ]] || continue
    reviews+="### $(basename "$f")"$'\n'
    reviews+="$(<"$f")"$'\n\n'
  done
  local prompt_file="${session_dir}/synthesize.prompt.md"
  render_template "${CODEPRISM_ROOT}/templates/synthesize.txt" "$prompt_file" \
    SESSION_ID "$sid" \
    RAPPORTEUR "$rapporteur" \
    TASK "$task" \
    IMPLEMENTATION_SUMMARIES "$summaries" \
    REVIEWS "$reviews"
  local prompt
  prompt="$(<"$prompt_file")"
  local out="${session_dir}/SYNTHESIS.md"
  local raw_out="${session_dir}/synthesize-agent-raw.txt"
  if [[ "$DRY_RUN" == "1" ]]; then
    run_agent "$backend" "$prompt" "$repo" "$CONFIG_AGENT_MODEL" "$session_dir" "synthesize" "$raw_out"
    return 0
  fi
  if [[ "$backend" == "manual" ]]; then
    run_agent "$backend" "$prompt" "$repo" "$CONFIG_AGENT_MODEL" "$session_dir" "synthesize"
    log_info "Manual synthesis: edit $out after running prompt"
    [[ -f "$out" ]] || echo "# SYNTHESIS (pending manual run)" >"$out"
  else
    run_agent "$backend" "$prompt" "$repo" "$CONFIG_AGENT_MODEL" "$session_dir" "synthesize" "$raw_out"
    if [[ -f "$raw_out" ]] && agent_format_output "$raw_out" "$out"; then
      log_info "Wrote synthesis to $out"
    else
      echo "# SYNTHESIS" >"$out"
      echo "" >>"$out"
      echo "Agent output could not be parsed. See ${raw_out} and synthesize.prompt.md." >>"$out"
      log_warn "Synthesis output missing or empty; placeholder written to $out"
    fi
  fi
  log_info "Synthesize phase complete for session $sid (rapporteur=$rapporteur)"
}
