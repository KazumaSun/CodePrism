#!/usr/bin/env bash
set -euo pipefail

# Resolved from task file (optional); consumed by bin/codeprism after load_task_from_args.
TASK_FILE_BASE=""
TASK_FILE_TITLE=""

_task_abs_path() {
  local path="$1"
  local repo="${2:-}"
  if [[ "$path" = /* ]]; then
    echo "$path"
  elif [[ -n "$repo" && -f "${repo}/${path}" ]]; then
    echo "$(cd "$repo" && pwd)/${path#./}"
  elif [[ -f "$path" ]]; then
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  else
    die "Task file not found: $path"
  fi
}

load_task_from_file() {
  local path="$1"
  local repo="${2:-}"
  local abs
  abs="$(_task_abs_path "$path" "$repo")"
  [[ -f "$abs" ]] || die "Task file not found: $abs"

  python3 - "$abs" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
suffix = path.suffix.lower()

def emit(title, base, task):
    import json
    task = task.strip()
    if not task:
        sys.stderr.write("Task file has no task content\n")
        sys.exit(1)
    print(json.dumps({"title": title or "", "base": base or "", "task": task}))

def parse_frontmatter(raw):
    if not raw.startswith("---"):
        return {}, raw
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n(.*)\Z", raw, re.DOTALL)
    if not m:
        return {}, raw
    fm_text, body = m.group(1), m.group(2)
    meta = {}
    current = None
    buf = []
    for line in fm_text.splitlines():
        if re.match(r"^[\w.-]+:\s*$", line):
            if current is not None:
                meta[current] = "\n".join(buf).strip()
            current = line.split(":", 1)[0].strip()
            buf = []
            continue
        if line.startswith("  ") and current is not None:
            buf.append(line[2:])
            continue
        m2 = re.match(r"^([\w.-]+):\s*(.*)$", line)
        if m2:
            if current is not None:
                meta[current] = "\n".join(buf).strip()
            current = m2.group(1)
            val = m2.group(2).strip()
            if val in ("|", ">"):
                buf = []
            else:
                meta[current] = val.strip('"').strip("'")
                current = None
                buf = []
    if current is not None:
        meta[current] = "\n".join(buf).strip()
    return meta, body

def yaml_simple_task(raw):
    meta = {}
    current = None
    buf = []
    for line in raw.splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        if re.match(r"^[\w.-]+:\s*$", line):
            if current is not None:
                meta[current] = "\n".join(buf).strip()
            current = line.split(":", 1)[0].strip()
            buf = []
            continue
        if line.startswith("  ") and current is not None:
            buf.append(line[2:])
            continue
        m2 = re.match(r"^([\w.-]+):\s*(.*)$", line)
        if m2:
            if current is not None:
                meta[current] = "\n".join(buf).strip()
            current = m2.group(1)
            val = m2.group(2).strip()
            if val in ("|", ">"):
                buf = []
            else:
                meta[current] = val.strip('"').strip("'")
                current = None
                buf = []
    if current is not None:
        meta[current] = "\n".join(buf).strip()
    return meta

if suffix in (".yaml", ".yml"):
    meta = yaml_simple_task(text)
    task = meta.get("task") or meta.get("prompt") or ""
    emit(meta.get("title", ""), meta.get("base", ""), task)
elif suffix == ".md":
    meta, body = parse_frontmatter(text)
    task = meta.get("task") or meta.get("prompt") or body
    emit(meta.get("title", ""), meta.get("base", ""), task)
else:
    emit("", "", text)
PY
}

resolve_task_inputs() {
  local repo="${1:-}"
  local task_inline="${2:-}"
  local task_file="${3:-}"
  local base_explicit="${4:-0}"

  TASK_FILE_BASE=""
  TASK_FILE_TITLE=""

  if [[ -n "$task_inline" && -n "$task_file" ]]; then
    die "Use only one of --task or --task-file"
  fi

  local resolved=""
  local source=""

  if [[ -n "$task_inline" ]]; then
    resolved="$task_inline"
    source="--task"
  elif [[ -n "$task_file" ]]; then
    source="--task-file"
  elif [[ -n "$repo" && -f "${repo}/.codeprism/task.md" ]]; then
    task_file="${repo}/.codeprism/task.md"
    source=".codeprism/task.md"
  elif [[ -n "$repo" && -f "${repo}/.codeprism/task.yaml" ]]; then
    task_file="${repo}/.codeprism/task.yaml"
    source=".codeprism/task.yaml"
  elif [[ -n "$repo" && -f "${repo}/.codeprism/task.yml" ]]; then
    task_file="${repo}/.codeprism/task.yml"
    source=".codeprism/task.yml"
  fi

  if [[ -n "$task_file" && -z "$resolved" ]]; then
    local parsed title base task_body
    parsed="$(load_task_from_file "$task_file" "$repo")"
    title="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("title",""))' <<<"$parsed")"
    base="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("base",""))' <<<"$parsed")"
    task_body="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("task",""))' <<<"$parsed")"
    # shellcheck disable=SC2034
    TASK_FILE_TITLE="$title"
    # shellcheck disable=SC2034
    TASK_FILE_BASE="$base"
    resolved="$task_body"
    log_info "Loaded task from ${source}: $(basename "$task_file")"
    [[ -n "$title" ]] && log_info "Task title: $title"
    if [[ -n "$base" && "$base_explicit" == "0" ]]; then
      BASE_BRANCH="$base"
      export BASE_BRANCH
      log_info "Base branch from task file: $base"
    fi
  fi

  if [[ -z "$resolved" ]]; then
    resolved="Implement the requested change"
    if [[ "$source" == "" ]]; then
      log_warn "No --task or --task-file; using default task text"
    fi
  fi

  echo "$resolved"
}
