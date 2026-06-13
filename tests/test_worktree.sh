#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CODEPRISM_ROOT="$ROOT"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"
# shellcheck source=lib/session.sh
source "${ROOT}/lib/session.sh"
# shellcheck source=lib/worktree.sh
source "${ROOT}/lib/worktree.sh"
# shellcheck source=lib/agent.sh
source "${ROOT}/lib/agent.sh"

check_deps

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# yaml inline comment stripping
cat >"${tmpdir}/cfg.yaml" <<'YAML'
agent:
  backend: auto   # cursor-cli | manual
YAML
val="$(yaml_get_simple "${tmpdir}/cfg.yaml" agent.backend)"
[[ "$val" == "auto" ]] || { echo "FAIL: expected auto, got: $val"; exit 1; }

# worktree path json helper
wt_json='{"melchior":"/tmp/wt/melchior\n","balthasar":"/tmp/wt/balthasar"}'
path="$(worktree_path_from_json "$wt_json" melchior)"
[[ "$path" == "/tmp/wt/melchior" ]] || { echo "FAIL: path strip, got: $path"; exit 1; }

# worktree parent under repo root
wt_parent="$(worktree_parent "${tmpdir}" test-session)"
[[ "$wt_parent" == "${tmpdir}/.codeprism-worktrees/test-session" ]] || {
  echo "FAIL: worktree_parent, got: $wt_parent"
  exit 1
}

# agent_format_output
cat >"${tmpdir}/agent.json" <<'JSON'
{"result":"## Recommendation\n\nUse melchior."}
JSON
agent_format_output "${tmpdir}/agent.json" "${tmpdir}/synthesis.md"
grep -q "Use melchior" "${tmpdir}/synthesis.md" || { echo "FAIL: synthesis parse"; exit 1; }

echo "test_worktree.sh: PASS"
