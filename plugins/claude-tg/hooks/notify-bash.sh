#!/bin/bash
# PreToolUse hook for Bash: sends a brief Telegram message describing the
# command about to run so the user can follow along from their phone.
# Stdin: {"tool_input": {"command": "...", "description": "..."}}
# Designed to fail silently — a notification hiccup should NEVER block a tool.
#
# Config (env vars):
#   CLAUDE_TG_CHAT_ID           Telegram chat id to notify (required)
#   CLAUDE_TG_BOT_TOKEN_FILE    path to the telegram plugin's env file holding
#                               TELEGRAM_BOT_TOKEN=<token>
#                               (default: ~/.claude/channels/telegram/.env)
#   CLAUDE_TG_BOT_TOKEN         raw bot token (overrides the file)

set -u

CHAT_ID="${CLAUDE_TG_CHAT_ID:-}"
TOKEN_FILE="${CLAUDE_TG_BOT_TOKEN_FILE:-$HOME/.claude/channels/telegram/.env}"

# Missing config → silently no-op (we must not crash on tool invocation)
[ -n "$CHAT_ID" ] || exit 0

if [ -n "${CLAUDE_TG_BOT_TOKEN:-}" ]; then
  TOKEN="$CLAUDE_TG_BOT_TOKEN"
elif [ -r "$TOKEN_FILE" ]; then
  TOKEN="$(grep -E '^TELEGRAM_BOT_TOKEN=' "$TOKEN_FILE" | cut -d= -f2-)"
else
  exit 0
fi
[ -n "$TOKEN" ] || exit 0

PAYLOAD="$(cat)"
CMD="$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)"
DESC="$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('description',''))" 2>/dev/null)"

[ -n "$CMD" ] || exit 0

# Truncate very long commands so we don't blast the chat
if [ ${#CMD} -gt 800 ]; then
  CMD="${CMD:0:800}…"
fi

if [ -n "$DESC" ]; then
  TEXT="🔧 $DESC"$'\n''```'$'\n'"$CMD"$'\n''```'
else
  TEXT="🔧"$'\n''```'$'\n'"$CMD"$'\n''```'
fi

curl -sS -m 5 -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${TEXT}" \
  -d "parse_mode=Markdown" \
  >/dev/null 2>&1 || true

exit 0
