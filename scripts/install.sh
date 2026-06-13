#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "CodePrism install"
echo "Root: $ROOT"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }
}

require git
require python3
require bash

BIN_DIR="${ROOT}/bin"
LINE="export PATH=\"${BIN_DIR}:\$PATH\""

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
  echo ""
  echo "Add CodePrism to your PATH:"
  echo "  $LINE"
  echo ""
  echo "Or symlink:"
  echo "  ln -sf ${BIN_DIR}/codeprism /usr/local/bin/codeprism"
else
  echo "bin/ already on PATH"
fi

echo "Done. Try: codeprism --help"
