#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

if [[ -z "${CODEPRISM_ROOT:-}" ]]; then
  CODEPRISM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export CODEPRISM_ROOT

DRY_RUN="${DRY_RUN:-0}"
AGENTS=(melchior balthasar caspar)

log() {
  local level="$1"
  shift
  printf '[codeprism][%s] %s\n' "$level" "$*" >&2
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }

die() {
  log_error "$@"
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

check_deps() {
  require_cmd git
  require_cmd python3
}

json_get() {
  local json="$1"
  local key="$2"
  python3 -c 'import json,sys; d=json.load(sys.stdin); k=sys.argv[1]; v=d
for part in k.split("."):
  if isinstance(v, dict): v=v.get(part)
  else: v=None; break
if v is None: sys.exit(1)
if isinstance(v,(dict,list)): print(json.dumps(v))
else: print(v)' "$key" <<<"$json"
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<<"$1"
}

yaml_get_simple() {
  # Minimal YAML reader for flat key: value and nested two-level keys (section.key)
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import sys, re
path, key = sys.argv[1], sys.argv[2]
parts = key.split(".")
with open(path) as f:
    lines = f.readlines()
cur_section = None
data = {}
for line in lines:
    line = line.rstrip("\n")
    if not line.strip() or line.strip().startswith("#"):
        continue
    m = re.match(r"^(\w+):\s*$", line)
    if m:
        cur_section = m.group(1)
        data[cur_section] = {}
        continue
    m = re.match(r"^  (\w+):\s*(.+)$", line)
    if m and cur_section:
        val = m.group(2).strip().strip('"').strip("'")
        val = re.split(r"\s+#", val, maxsplit=1)[0].strip()
        data[cur_section][m.group(1)] = val
        continue
    m = re.match(r"^(\w+):\s*(.+)$", line)
    if m:
        val = m.group(2).strip().strip('"').strip("'")
        val = re.split(r"\s+#", val, maxsplit=1)[0].strip()
        data[m.group(1)] = val
if len(parts) == 1:
    v = data.get(parts[0])
    if isinstance(v, dict):
        import json
        print(json.dumps(v))
    elif v is not None:
        print(v)
    else:
        sys.exit(1)
else:
    sec = data.get(parts[0], {})
    if isinstance(sec, dict) and parts[1] in sec:
        print(sec[parts[1]])
    else:
        sys.exit(1)
PY
}

load_merged_config() {
  local repo="${1:-}"
  local default="${CODEPRISM_ROOT}/config/default.yaml"
  local override=""
  if [[ -n "$repo" && -f "${repo}/.codeprism.yaml" ]]; then
    override="${repo}/.codeprism.yaml"
  fi
  CONFIG_DEFAULT="$default"
  CONFIG_OVERRIDE="$override"
  CONFIG_AGENT_BACKEND="$(yaml_get_simple "$default" agent.backend 2>/dev/null || echo auto)"
  CONFIG_AGENT_MODEL="$(yaml_get_simple "$default" agent.model 2>/dev/null || echo composer-2.5)"
  CONFIG_REVIEW_ANON="$(yaml_get_simple "$default" review.anonymize 2>/dev/null || echo true)"
  CONFIG_RAPPORTEUR="$(yaml_get_simple "$default" synthesis.rapporteur 2>/dev/null || echo melchior)"
  CONFIG_WT_PREFIX="$(yaml_get_simple "$default" worktree.prefix 2>/dev/null || echo codeprism)"
  if [[ -n "$override" ]]; then
    CONFIG_AGENT_BACKEND="$(yaml_get_simple "$override" agent.backend 2>/dev/null || echo "$CONFIG_AGENT_BACKEND")"
    CONFIG_AGENT_MODEL="$(yaml_get_simple "$override" agent.model 2>/dev/null || echo "$CONFIG_AGENT_MODEL")"
    CONFIG_REVIEW_ANON="$(yaml_get_simple "$override" review.anonymize 2>/dev/null || echo "$CONFIG_REVIEW_ANON")"
    CONFIG_RAPPORTEUR="$(yaml_get_simple "$override" synthesis.rapporteur 2>/dev/null || echo "$CONFIG_RAPPORTEUR")"
    CONFIG_WT_PREFIX="$(yaml_get_simple "$override" worktree.prefix 2>/dev/null || echo "$CONFIG_WT_PREFIX")"
  fi
}

persona_path_for_agent() {
  local agent="$1"
  local repo="${2:-}"
  load_merged_config "$repo"
  local rel
  rel="$(yaml_get_simple "${CODEPRISM_ROOT}/config/default.yaml" "personas.${agent}" 2>/dev/null || true)"
  if [[ -n "$repo" && -f "${repo}/.codeprism.yaml" ]]; then
    rel="$(yaml_get_simple "${repo}/.codeprism.yaml" "personas.${agent}" 2>/dev/null || echo "$rel")"
  fi
  if [[ -z "$rel" ]]; then
    rel="config/personas/${agent}.md"
  fi
  if [[ "$rel" = /* ]]; then
    echo "$rel"
  elif [[ -f "${repo}/${rel}" ]]; then
    echo "${repo}/${rel}"
  else
    echo "${CODEPRISM_ROOT}/${rel}"
  fi
}

render_template() {
  local template="$1"
  local out="$2"
  shift 2
  local content
  content="$(<"$template")"
  while [[ $# -gt 0 ]]; do
    local key="$1"
    local val="$2"
    content="${content//\{\{${key}\}\}/${val}}"
    shift 2
  done
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] would write template to $out"
  else
    printf '%s' "$content" >"$out"
  fi
}

run_or_echo() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[dry-run] $*"
  else
    "$@"
  fi
}
