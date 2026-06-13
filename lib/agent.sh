#!/usr/bin/env bash
set -euo pipefail

detect_agent_backend() {
  local requested="${1:-auto}"
  if [[ "$requested" != "auto" ]]; then
    echo "$requested"
    return 0
  fi
  if command -v cursor >/dev/null 2>&1 && cursor agent --help >/dev/null 2>&1; then
    echo "cursor-cli"
    return 0
  fi
  if [[ -n "${CURSOR_API_KEY:-}" ]] && [[ -f "${CODEPRISM_ROOT}/optional/sdk/run.mjs" ]]; then
    echo "cursor-sdk"
    return 0
  fi
  echo "manual"
}

run_agent() {
  local backend="$1"
  local prompt="$2"
  local workspace="$3"
  local model="${4:-composer-2.5}"
  local session_dir="${5:-}"
  local label="${6:-agent}"

  case "$backend" in
    cursor-cli)
      local -a cmd=(cursor agent -p "$prompt" --workspace "$workspace")
      if cursor agent --help 2>&1 | grep -q output-format; then
        cmd+=(--output-format json)
      fi
      if cursor agent --help 2>&1 | grep -q model; then
        cmd+=(--model "$model")
      fi
      if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry-run] ${cmd[*]}"
        return 0
      fi
      "${cmd[@]}"
      ;;
    cursor-sdk)
      if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry-run] node optional/sdk/run.mjs workspace=$workspace"
        return 0
      fi
      node "${CODEPRISM_ROOT}/optional/sdk/run.mjs" \
        --workspace "$workspace" \
        --model "$model" \
        --prompt "$prompt"
      ;;
    manual)
      local out="${session_dir}/manual-${label}-$(date +%Y%m%d-%H%M%S).md"
      if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry-run] would write manual prompt to $out"
        return 0
      fi
      mkdir -p "$session_dir"
      {
        echo "# Manual agent run: $label"
        echo ""
        echo "## Workspace"
        echo "$workspace"
        echo ""
        echo "## Prompt"
        echo "$prompt"
      } >"$out"
      log_info "Wrote manual prompt: $out"
      ;;
    *)
      die "Unknown agent backend: $backend"
      ;;
  esac
}
