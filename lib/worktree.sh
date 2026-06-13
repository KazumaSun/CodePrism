#!/usr/bin/env bash
set -euo pipefail

worktree_parent() {
  local repo="$1"
  local sid="$2"
  local repo_abs
  repo_abs="$(cd "$repo" && pwd)"
  echo "${repo_abs}/.codeprism-worktrees/${sid}"
}

agent_branch_name() {
  local sid="$1"
  local agent="$2"
  local prefix="${CONFIG_WT_PREFIX:-codeprism}"
  echo "${prefix}/${sid}/${agent}"
}

worktree_path_from_json() {
  local wt_json="$1"
  local agent="$2"
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],"").strip())' "$agent" <<<"$wt_json"
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
      git worktree add "$wt_path" "$branch" >&2
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

worktree_commit_if_dirty() {
  local wt_path="$1"
  local message="${2:-codeprism: agent changes}"
  if [[ ! -d "$wt_path" ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would commit changes in $wt_path"
    return 0
  fi
  (
    cd "$wt_path"
    if [[ -n "$(git status --porcelain)" ]]; then
      git add -A
      git commit -m "$message"
      log_info "Committed changes in $wt_path"
    fi
  )
}

worktree_commit_all() {
  local repo="$1"
  local sid="$2"
  local phase="${3:-implement}"
  local wt_json
  wt_json="$(session_load_worktrees "$repo" "$sid")"
  local agent wt_path
  for agent in "${AGENTS[@]}"; do
    wt_path="$(worktree_path_from_json "$wt_json" "$agent")"
    [[ -n "$wt_path" ]] || continue
    worktree_commit_if_dirty "$wt_path" "codeprism: ${phase} ${agent}"
  done
}

worktree_resolve_base_ref() {
  local wt_path="$1"
  local base_branch="${2:-main}"
  local ref=""
  (
    cd "$wt_path"
    if git show-ref --verify --quiet "refs/heads/${base_branch}"; then
      ref="$base_branch"
    elif git show-ref --verify --quiet "refs/remotes/origin/${base_branch}"; then
      ref="origin/${base_branch}"
    else
      ref="HEAD~1"
    fi
    echo "$ref"
  )
}

worktree_collect_diff() {
  local wt_path="$1"
  local base_ref="${2:-main}"
  if [[ ! -d "$wt_path" ]]; then
    echo ""
    return 0
  fi
  (
    cd "$wt_path"
    local resolved
    resolved="$(worktree_resolve_base_ref "$wt_path" "$base_ref")"
    if git rev-parse --verify "${resolved}^{commit}" >/dev/null 2>&1; then
      git diff "${resolved}...HEAD" 2>/dev/null \
        || git diff "${resolved}" HEAD 2>/dev/null \
        || true
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
      git diff HEAD 2>/dev/null || true
      git diff --cached HEAD 2>/dev/null || true
      git ls-files --others --exclude-standard -z | xargs -0 -I{} git diff --no-index /dev/null "{}" 2>/dev/null || true
    fi
  )
}

worktree_collect_all() {
  local repo="$1"
  local sid="$2"
  local base_branch="${3:-}"
  local out_dir
  out_dir="$(session_dir_for "$repo" "$sid")/diffs"
  local wt_json
  wt_json="$(session_load_worktrees "$repo" "$sid")"
  if [[ -z "$base_branch" ]]; then
    base_branch="$(json_get "$(session_load_meta "$repo" "$sid")" base_branch 2>/dev/null || echo main)"
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would collect diffs to $out_dir (base=$base_branch)"
    return 0
  fi
  mkdir -p "$out_dir"
  local agent path
  for agent in "${AGENTS[@]}"; do
    path="$(worktree_path_from_json "$wt_json" "$agent")"
    if [[ -n "$path" && -d "$path" ]]; then
      worktree_commit_if_dirty "$path" "codeprism: collect ${agent}"
      worktree_collect_diff "$path" "$base_branch" >"${out_dir}/${agent}.diff"
      log_info "Collected diff for $agent"
    fi
  done
}

worktree_commits_ahead_of_base() {
  local wt_path="$1"
  local base_branch="${2:-main}"
  if [[ ! -d "$wt_path" ]]; then
    echo "0"
    return 0
  fi
  (
    cd "$wt_path"
    local resolved count
    resolved="$(worktree_resolve_base_ref "$wt_path" "$base_branch")"
    count="$(git rev-list --count "${resolved}..HEAD" 2>/dev/null || echo 0)"
    echo "$count"
  )
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
    path="${path//$'\n'/}"
    if [[ $first -eq 0 ]]; then json+=','; fi
    first=0
    json+="\"${agent}\":$(json_escape "$path")"
  done
  json+='}'
  session_save_worktrees "$repo" "$sid" "$json"
}
