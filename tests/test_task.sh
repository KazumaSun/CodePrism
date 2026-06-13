#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CODEPRISM_ROOT="$ROOT"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
# shellcheck source=lib/task.sh
source "${ROOT}/lib/task.sh"

check_deps

md_task="$(resolve_task_inputs "" "" "${ROOT}/examples/tasks/github-profile.md" 0)"
[[ "$md_task" == *"GitHub プロフィール"* ]] || { echo "FAIL: md task load"; exit 1; }

yaml_task="$(resolve_task_inputs "" "" "${ROOT}/examples/tasks/github-profile.yaml" 0)"
[[ "$yaml_task" == *"GitHub プロフィール"* ]] || { echo "FAIL: yaml task load"; exit 1; }

[[ -n "$TASK_FILE_BASE" ]] || true

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "${tmpdir}/.codeprism"
cp "${ROOT}/examples/tasks/github-profile.yaml" "${tmpdir}/.codeprism/task.yaml"

default_task="$(resolve_task_inputs "$tmpdir" "" "" 0)"
[[ "$default_task" == *"GitHub プロフィール"* ]] || { echo "FAIL: default .codeprism/task.yaml"; exit 1; }

if ( resolve_task_inputs "" "inline" "${ROOT}/examples/tasks/github-profile.yaml" 0 ) 2>/dev/null; then
  echo "FAIL: should reject both --task and --task-file"
  exit 1
fi

echo "test_task.sh: PASS"
