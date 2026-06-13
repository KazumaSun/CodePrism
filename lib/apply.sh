#!/usr/bin/env bash
set -euo pipefail

apply_phase() {
  local repo="$1"
  local sid="$2"
  local strategy="${3:-cherry-pick}"
  local target_agent="${4:-melchior}"
  load_merged_config "$repo"
  local wt_json
  wt_json="$(session_load_worktrees "$repo" "$sid")"
  local wt_path
  wt_path="$(worktree_path_from_json "$wt_json" "$target_agent")"
  [[ -n "$wt_path" ]] || die "No worktree for agent $target_agent"
  local branch base_branch
  branch="$(agent_branch_name "$sid" "$target_agent")"
  base_branch="$(json_get "$(session_load_meta "$repo" "$sid")" base_branch 2>/dev/null || echo main)"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would apply $strategy from $branch into current branch in $repo"
    return 0
  fi
  worktree_commit_if_dirty "$wt_path" "codeprism: apply ${sid}/${target_agent}"
  local ahead
  ahead="$(worktree_commits_ahead_of_base "$wt_path" "$base_branch")"
  if [[ "$ahead" -eq 0 ]]; then
    die "No commits to apply from ${target_agent}. Implement may have failed or produced no file changes."
  fi
  (
    cd "$repo"
    local cur
    cur="$(git branch --show-current)"
    log_info "Applying from $branch (strategy=$strategy, commits=${ahead}) onto $cur"
    case "$strategy" in
      cherry-pick)
        local resolved sha
        resolved="$(git -C "$wt_path" rev-parse "$(worktree_resolve_base_ref "$wt_path" "$base_branch")")"
        while IFS= read -r sha; do
          [[ -n "$sha" ]] || continue
          git cherry-pick "$sha" || die "cherry-pick failed at $sha"
        done < <(git -C "$wt_path" rev-list --reverse "${resolved}..HEAD")
        ;;
      merge)
        git merge --no-ff "$branch" -m "codeprism: merge ${sid}/${target_agent}" || die "merge failed"
        ;;
      *)
        die "Unknown apply strategy: $strategy"
        ;;
    esac
  )
  session_update_meta "$repo" "$sid" "applied"
  log_info "Apply complete for session $sid"
}
