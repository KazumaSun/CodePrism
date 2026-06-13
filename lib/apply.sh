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
  wt_path="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],""))' "$target_agent" <<<"$wt_json")"
  [[ -n "$wt_path" ]] || die "No worktree for agent $target_agent"
  local branch
  branch="$(agent_branch_name "$sid" "$target_agent")"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would apply $strategy from $branch into current branch in $repo"
    return 0
  fi
  (
    cd "$repo"
    local cur
    cur="$(git branch --show-current)"
    log_info "Applying from $branch (strategy=$strategy) onto $cur"
    case "$strategy" in
      cherry-pick)
        local sha
        sha="$(git -C "$wt_path" rev-parse HEAD)"
        git cherry-pick "$sha" || die "cherry-pick failed"
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
