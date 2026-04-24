#!/bin/bash
# Start Claude Code in a detached screen session named "claude-tg".
# Attach later with: screen -r claude-tg
# Detach without killing: Ctrl-A then D

set -euo pipefail

SESSION="claude-tg"

if ! command -v screen >/dev/null; then
  echo "screen is not installed — apt install screen (or tmux and adapt this script)" >&2
  exit 1
fi

if screen -ls 2>/dev/null | grep -q "\\.${SESSION}[[:space:]]"; then
  echo "Session '$SESSION' already running. Attach with:  screen -r $SESSION"
  exit 0
fi

screen -dmS "$SESSION" bash -lc 'claude --channels plugin:telegram@claude-plugins-official'
echo "Started screen session '$SESSION'."
echo "Attach:    screen -r $SESSION"
echo "Detach:    Ctrl-A then D"
echo "Stop:      screen -S $SESSION -X quit"
