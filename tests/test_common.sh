#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CODEPRISM_ROOT="$ROOT"
# shellcheck source=../lib/common.sh
source "${ROOT}/lib/common.sh"

check_deps

DRY_RUN=1
export DRY_RUN

load_merged_config ""
[[ "$CONFIG_AGENT_BACKEND" == "auto" ]]

log_info "dry-run logging ok"

# Template render dry-run
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
render_template "${ROOT}/templates/implement.txt" "${tmpdir}/out.txt" \
  SESSION_ID test \
  AGENT_NAME melchior \
  PERSONA test \
  TASK task \
  REPO_PATH /tmp/repo \
  BASE_BRANCH main \
  WORKTREE_PATH /tmp/wt \
  BRANCH codeprism/test/melchior

[[ ! -f "${tmpdir}/out.txt" ]] && echo "PASS: dry-run skipped write"

echo "test_common.sh: PASS"
