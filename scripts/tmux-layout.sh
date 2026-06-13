#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-$(pwd)}"
SESSION_NAME="codeprism"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not found" >&2
  exit 1
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  exec tmux attach -t "$SESSION_NAME"
fi

tmux new-session -d -s "$SESSION_NAME" -c "$REPO" \
  "echo 'CodePrism — rapporteur / main'; bash"
tmux split-window -h -t "$SESSION_NAME:0" -c "$REPO" \
  "echo 'melchior worktree'; bash"
tmux split-window -v -t "$SESSION_NAME:0.0" -c "$REPO" \
  "echo 'balthasar worktree'; bash"
tmux split-window -v -t "$SESSION_NAME:0.1" -c "$REPO" \
  "echo 'caspar worktree'; bash"
tmux select-layout -t "$SESSION_NAME:0" tiled
tmux attach -t "$SESSION_NAME"
