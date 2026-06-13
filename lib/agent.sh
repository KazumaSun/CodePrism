#!/usr/bin/env bash
set -euo pipefail

detect_agent_backend() {
  local requested="${1:-auto}"
  requested="${requested%%#*}"
  requested="$(echo "$requested" | xargs)"
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

agent_format_output() {
  local raw_file="$1"
  local out_file="${2:-}"
  [[ -f "$raw_file" ]] || return 1
  python3 - "$raw_file" "$out_file" <<'PY'
import json, sys

raw_path, out_path = sys.argv[1], sys.argv[2]
with open(raw_path, encoding="utf-8", errors="replace") as f:
    raw = f.read().strip()

text = ""

def pick_string(obj):
    if isinstance(obj, str) and obj.strip():
        return obj.strip()
    if isinstance(obj, dict):
        for key in ("result", "message", "content", "text", "response", "output"):
            val = obj.get(key)
            if isinstance(val, str) and val.strip():
                return val.strip()
        for key in ("message", "content", "text"):
            val = obj.get(key)
            if isinstance(val, dict):
                nested = pick_string(val)
                if nested:
                    return nested
    if isinstance(obj, list):
        parts = []
        for item in obj:
            part = pick_string(item)
            if part:
                parts.append(part)
        if parts:
            return "\n\n".join(parts)
    return ""

try:
    data = json.loads(raw)
    text = pick_string(data) or ""
except json.JSONDecodeError:
    text = raw

if not text:
    text = raw

if not text.startswith("#"):
    text = "# SYNTHESIS\n\n" + text

if out_path:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
        if not text.endswith("\n"):
            f.write("\n")
else:
    print(text)
PY
}

run_agent() {
  local backend="$1"
  local prompt="$2"
  local workspace="$3"
  local model="${4:-composer-2.5}"
  local session_dir="${5:-}"
  local label="${6:-agent}"
  local output_file="${7:-}"

  case "$backend" in
    cursor-cli)
      local -a cmd=(cursor agent -p "$prompt" --workspace "$workspace")
      if cursor agent --help 2>&1 | grep -q -- '--trust'; then
        cmd+=(--trust)
      fi
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
      if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        if ! "${cmd[@]}" >"$output_file" 2>&1; then
          log_warn "Agent process exited non-zero for $label (output saved to $output_file)"
        fi
      else
        "${cmd[@]}"
      fi
      ;;
    cursor-sdk)
      if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry-run] node optional/sdk/run.mjs workspace=$workspace"
        return 0
      fi
      if [[ -n "$output_file" ]]; then
        mkdir -p "$(dirname "$output_file")"
        if ! node "${CODEPRISM_ROOT}/optional/sdk/run.mjs" \
          --workspace "$workspace" \
          --model "$model" \
          --prompt "$prompt" >"$output_file" 2>&1; then
          log_warn "SDK agent exited non-zero for $label (output saved to $output_file)"
        fi
      else
        node "${CODEPRISM_ROOT}/optional/sdk/run.mjs" \
          --workspace "$workspace" \
          --model "$model" \
          --prompt "$prompt"
      fi
      ;;
    manual)
      local out
      out="${session_dir}/manual-${label}-$(date +%Y%m%d-%H%M%S).md"
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
