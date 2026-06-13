#!/usr/bin/env bash
set -euo pipefail

worktree_parent() {
  local repo="$1"
  local sid="$2"
  local repo_abs
  repo_abs="$(cd "$repo" && pwd)"
  local parent
  parent="$(dirname "$repo_abs")/.codeprism-worktrees/${sid}"
  echo "$parent"
}

agent_branch_name() {
  local sid="$1"
  local agent="$2"
  local prefix="${CONFIG_WT_PREFIX:-codeprism}"
  echo "${prefix}/${sid}/${agent}"
}

worktree_create_for_agent() {
  local repo="$1"
  local sid="$2"
  local agent="$3"
  local base="${4:-main}"
  load_merged_config "$repo"
  local branch
  branch="$(agent_branch_name "$sid" "$agent")"
  local wt_base
  wt_base="$(worktree_parent "$repo" "$sid")"
  local wt_path="${wt_base}/${agent}"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would create worktree $wt_path branch $branch"
    echo "$wt_path"
    return 0
  fi
  mkdir -p "$wt_base"
  (
    cd "$repo"
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
      :
    else
      git branch "$branch" "$base" 2>/dev/null || git branch "$branch" "origin/${base}" 2>/dev/null || git branch "$branch"
    fi
    if [[ -d "$wt_path" ]]; then
      log_warn "Worktree already exists: $wt_path"
    else
      git worktree add "$wt_path" "$branch"
    fi
  )
  echo "$wt_path"
}

worktree_remove_for_agent() {
  local repo="$1"
  local wt_path="$2"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would remove worktree $wt_path"
    return 0
  fi
  if [[ -d "$wt_path" ]]; then
    (cd "$repo" && git worktree remove --force "$wt_path" 2>/dev/null) || rm -rf "$wt_path"
  fi
}

worktree_collect_diff() {
  local wt_path="$1"
  local base_ref="${2:-HEAD}"
  if [[ ! -d "$wt_path" ]]; then
    echo ""
    return 0
  fi
  (
    cd "$wt_path"
    git diff "$base_ref" 2>/dev/null || true
    git diff --cached "$base_ref" 2>/dev/null || true
  )
}

worktree_collect_all() {
  local repo="$1"
  local sid="$2"
  local out_dir
  out_dir="$(session_dir_for "$repo" "$sid")/diffs"
  local wt_json
  wt_json="$(session_load_worktrees "$repo" "$sid")"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would collect diffs to $out_dir"
    return 0
  fi
  mkdir -p "$out_dir"
  local agent path
  for agent in "${AGENTS[@]}"; do
    path="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],""))' "$agent" <<<"$wt_json")"
    if [[ -n "$path" && -d "$path" ]]; then
      worktree_collect_diff "$path" >"${out_dir}/${agent}.diff"
      log_info "Collected diff for $agent"
    fi
  done
}

worktree_register_all() {
  local repo="$1"
  local sid="$2"
  local base="$3"
  local json='{'
  local first=1
  local agent path
  for agent in "${AGENTS[@]}"; do
    path="$(worktree_create_for_agent "$repo" "$sid" "$agent" "$base")"
    if [[ $first -eq 0 ]]; then json+=','; fi
    first=0
    json+="\"${agent}\":$(json_escape "$path")"
  done
  json+='}'
  session_save_worktrees "$repo" "$sid" "$json"
}
