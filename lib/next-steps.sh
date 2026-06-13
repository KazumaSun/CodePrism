#!/usr/bin/env bash
set -euo pipefail

synthesis_is_ready() {
  local synthesis_file="$1"
  [[ -f "$synthesis_file" ]] || return 1
  if grep -q 'See synthesize prompt and agent output' "$synthesis_file" 2>/dev/null; then
    return 1
  fi
  if grep -q 'pending manual run' "$synthesis_file" 2>/dev/null; then
    return 1
  fi
  local lines
  lines=$(wc -l <"$synthesis_file" | tr -d ' ')
  [[ "$lines" -gt 3 ]]
}

session_has_manual_prompts() {
  local session_dir="$1"
  find "$session_dir" -maxdepth 1 -name 'manual-*.md' -print -quit 2>/dev/null | grep -q .
}

_print_repo_flag() {
  local repo="$1"
  printf -- '--repo %q' "$repo"
}

_print_worktree_paths() {
  local repo="$1"
  local sid="$2"
  local wt_json agent path
  wt_json="$(session_load_worktrees "$repo" "$sid")"
  for agent in "${AGENTS[@]}"; do
    path="$(worktree_path_from_json "$wt_json" "$agent")"
    [[ -n "$path" ]] || continue
    echo "   ${agent}: ${path}" >&2
  done
}

print_next_steps() {
  local repo="$1"
  local sid="$2"
  local command="${3:-run}"
  local session_dir repo_flag
  session_dir="$(session_dir_for "$repo" "$sid")"
  repo_flag="$(_print_repo_flag "$repo")"
  load_merged_config "$repo"
  local backend synthesis_file
  backend="$(detect_agent_backend "$CONFIG_AGENT_BACKEND")"
  synthesis_file="${session_dir}/SYNTHESIS.md"

  echo "" >&2
  echo "── Next steps ──────────────────────────────────────" >&2
  echo "Session: ${sid}" >&2
  echo "Repo:    ${repo}" >&2
  echo "" >&2

  case "$command" in
    run|synthesize)
      if synthesis_is_ready "$synthesis_file"; then
        echo "Plan: ready at ${synthesis_file}" >&2
        echo "" >&2
        echo "1) Read the synthesis plan:" >&2
        echo "   less ${synthesis_file}" >&2
      else
        echo "Plan: not ready (SYNTHESIS.md is still a placeholder)" >&2
        echo "" >&2
        if [[ "$backend" == "manual" ]] || session_has_manual_prompts "$session_dir"; then
          echo "1) Complete manual synthesis and write the plan:" >&2
          echo "   less ${session_dir}/synthesize.prompt.md" >&2
          echo "   # Save the agent result to ${synthesis_file}" >&2
        else
          echo "1) Inspect or re-run synthesis:" >&2
          echo "   less ${session_dir}/synthesize.prompt.md" >&2
          echo "   codeprism synthesize --session ${sid} ${repo_flag}" >&2
        fi
      fi

      echo "" >&2
      echo "2) Inspect collected diffs:" >&2
      local agent
      for agent in "${AGENTS[@]}"; do
        echo "   less ${session_dir}/diffs/${agent}.diff" >&2
      done

      echo "" >&2
      echo "3) Open agent worktrees:" >&2
      _print_worktree_paths "$repo" "$sid"

      echo "" >&2
      echo "4) Apply one agent branch with cherry-pick (default):" >&2
      echo "   # Worktree changes are auto-committed before apply" >&2
      for agent in "${AGENTS[@]}"; do
        echo "   codeprism apply --session ${sid} --agent ${agent} ${repo_flag}" >&2
      done

      echo "" >&2
      echo "5) Apply one agent branch with merge:" >&2
      for agent in "${AGENTS[@]}"; do
        echo "   codeprism apply --session ${sid} --agent ${agent} --strategy merge ${repo_flag}" >&2
      done

      echo "" >&2
      echo "6) Check session metadata:" >&2
      echo "   codeprism status --session ${sid} ${repo_flag}" >&2

      echo "" >&2
      echo "7) Open a 4-pane tmux layout:" >&2
      echo "   codeprism tmux ${repo_flag}" >&2

      echo "" >&2
      echo "8) Remove worktrees when finished:" >&2
      echo "   codeprism clean --session ${sid} ${repo_flag}" >&2
      ;;

    implement)
      local step=1
      if [[ "$backend" == "manual" ]] || session_has_manual_prompts "$session_dir"; then
        echo "Manual implement prompts were written under ${session_dir}" >&2
        echo "" >&2
        echo "${step}) Run each manual-implement-*.md prompt in its worktree:" >&2
        _print_worktree_paths "$repo" "$sid"
        echo "   less ${session_dir}/manual-implement-*.md" >&2
        step=$((step + 1))
        echo "" >&2
        echo "${step}) Snapshot worktree changes:" >&2
        echo "   codeprism collect --session ${sid} ${repo_flag}" >&2
        step=$((step + 1))
      else
        echo "Implement phase finished (agent changes auto-committed in worktrees)." >&2
        echo "" >&2
        echo "${step}) Inspect worktrees:" >&2
        _print_worktree_paths "$repo" "$sid"
        step=$((step + 1))
      fi

      echo "" >&2
      echo "${step}) Run cross reviews:" >&2
      echo "   codeprism review --session ${sid} ${repo_flag}" >&2
      step=$((step + 1))

      echo "" >&2
      echo "${step}) Continue with synthesis after review:" >&2
      echo "   codeprism synthesize --session ${sid} ${repo_flag}" >&2
      step=$((step + 1))

      echo "" >&2
      echo "${step}) Check session metadata:" >&2
      echo "   codeprism status --session ${sid} ${repo_flag}" >&2
      ;;

    review)
      local step=1
      if [[ "$backend" == "manual" ]] || session_has_manual_prompts "$session_dir"; then
        echo "Manual review prompts were written under ${session_dir}" >&2
        echo "" >&2
        echo "${step}) Run each manual-review-*.md prompt:" >&2
        echo "   less ${session_dir}/manual-review-*.md" >&2
        step=$((step + 1))
        echo "" >&2
      fi

      echo "${step}) Produce the synthesis plan:" >&2
      echo "   codeprism synthesize --session ${sid} ${repo_flag}" >&2
      step=$((step + 1))

      echo "" >&2
      echo "${step}) Inspect collected diffs:" >&2
      for agent in "${AGENTS[@]}"; do
        echo "   less ${session_dir}/diffs/${agent}.diff" >&2
      done
      step=$((step + 1))

      echo "" >&2
      echo "${step}) Check session metadata:" >&2
      echo "   codeprism status --session ${sid} ${repo_flag}" >&2
      ;;

    apply)
      echo "Apply phase finished." >&2
      echo "" >&2
      echo "1) Review changes in your repo:" >&2
      echo "   git -C ${repo} status" >&2
      echo "   git -C ${repo} diff" >&2

      echo "" >&2
      echo "2) Commit and push when satisfied:" >&2
      echo "   git -C ${repo} add -A" >&2
      echo "   git -C ${repo} commit -m \"your message\"" >&2
      echo "   git -C ${repo} push" >&2

      echo "" >&2
      echo "3) Remove worktrees when finished:" >&2
      echo "   codeprism clean --session ${sid} ${repo_flag}" >&2
      ;;
  esac

  echo "──────────────────────────────────────────────────" >&2
}
