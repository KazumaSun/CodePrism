#!/usr/bin/env bash
set -euo pipefail

session_dir_for() {
  local repo="$1"
  local sid="$2"
  echo "${repo}/.codeprism/sessions/${sid}"
}

session_meta_path() {
  echo "$(session_dir_for "$1" "$2")/meta.json"
}

session_worktrees_path() {
  echo "$(session_dir_for "$1" "$2")/worktrees.json"
}

session_create() {
  local repo="$1"
  local task="$2"
  local base="${3:-main}"
  local sid
  sid="$(date +%Y%m%d-%H%M%S)-$$"
  local dir
  dir="$(session_dir_for "$repo" "$sid")"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would create session $sid at $dir"
    echo "$sid"
    return 0
  fi
  mkdir -p "$dir"
  python3 - "$sid" "$task" "$base" "$dir/meta.json" <<'PY'
import json, sys, datetime
sid, task, base, path = sys.argv[1:5]
meta = {
  "id": sid,
  "task": task,
  "base_branch": base,
  "created_at": datetime.datetime.utcnow().isoformat() + "Z",
  "phase": "created",
  "agents": ["melchior", "balthasar", "caspar"],
}
with open(path, "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PY
  echo '{}' >"${dir}/worktrees.json"
  log_info "Created session $sid"
  echo "$sid"
}

session_load_meta() {
  local repo="$1"
  local sid="$2"
  local path
  path="$(session_meta_path "$repo" "$sid")"
  [[ -f "$path" ]] || die "Session not found: $sid ($path)"
  cat "$path"
}

session_update_meta() {
  local repo="$1"
  local sid="$2"
  local phase="${3:-}"
  local path
  path="$(session_meta_path "$repo" "$sid")"
  [[ -f "$path" ]] || die "Session not found: $sid"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would update session $sid phase=$phase"
    return 0
  fi
  python3 - "$path" "$phase" <<'PY'
import json, sys
path, phase = sys.argv[1], sys.argv[2]
with open(path) as f:
    meta = json.load(f)
if phase:
    meta["phase"] = phase
with open(path, "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PY
}

session_save_worktrees() {
  local repo="$1"
  local sid="$2"
  local json_blob="$3"
  local path
  path="$(session_worktrees_path "$repo" "$sid")"
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would save worktrees.json for $sid"
    return 0
  fi
  printf '%s\n' "$json_blob" >"$path"
}

session_load_worktrees() {
  local repo="$1"
  local sid="$2"
  local path
  path="$(session_worktrees_path "$repo" "$sid")"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo '{}'
  fi
}

session_latest() {
  local repo="$1"
  local base="${repo}/.codeprism/sessions"
  [[ -d "$base" ]] || return 1
  ls -1t "$base" 2>/dev/null | head -1
}
