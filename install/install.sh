#!/bin/bash
# claude-tg interactive installer.
# - Collects Telegram bot token, chat id, Groq API key.
# - Wires up permissions + hooks in ~/.claude/settings.json.
# - Optionally installs a systemd unit or screen wrapper so Claude stays alive
#   when you log out.
# - Assumes the plugin itself is already loaded via /plugin (the script prints
#   the exact /plugin command if it isn't).
#
# Safe to re-run — merges rather than replaces.

set -euo pipefail

RED="\033[0;31m"; GRN="\033[0;32m"; YLW="\033[0;33m"; CLR="\033[0m"
say() { printf "%b\n" "$*"; }
ok()  { say "${GRN}✓${CLR} $*"; }
warn(){ say "${YLW}!${CLR} $*"; }
err() { say "${RED}✗${CLR} $*" >&2; }

# --- pre-flight ---------------------------------------------------------
command -v curl   >/dev/null || { err "curl is required"; exit 1; }
command -v python3 >/dev/null || { err "python3 is required"; exit 1; }
command -v jq     >/dev/null || warn "jq not found — will use python3 for JSON (works, just slower)"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/claude-tg"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-tg"
SETTINGS="$CLAUDE_HOME/settings.json"

mkdir -p "$CLAUDE_HOME" "$CFG_DIR"

say ""
say "═══════════════════════════════════════════════════════════════════"
say "                       claude-tg installer"
say "═══════════════════════════════════════════════════════════════════"
say ""

# --- collect config -----------------------------------------------------
read -rp "Telegram bot token (from @BotFather): " BOT_TOKEN
[ -n "$BOT_TOKEN" ] || { err "bot token is required"; exit 1; }

# Auto-discover the chat id: generate a random pairing code, ask the user to
# send it to their bot, then poll getUpdates until it shows up. Avoids the
# "find your chat_id" scavenger hunt and is safer than grabbing any random
# /start that arrives.
PAIRING_CODE="CLAUDE-TG-$(LC_ALL=C tr -dc 'A-Z0-9' </dev/urandom | head -c 8)"

say ""
say "Now pair this installer with your Telegram account."
say "  1. Open your bot in Telegram (the one the token above belongs to)"
say "  2. Send it exactly this message:"
say ""
say "       ${YLW}$PAIRING_CODE${CLR}"
say ""
say "Waiting up to 3 minutes for the pairing message..."

CHAT_ID=""
OFFSET=0
export PAIRING_CODE
for attempt in $(seq 1 90); do
  RESP="$(curl -sS --max-time 5 \
    "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=2&allowed_updates=%5B%22message%22%5D" \
    || true)"

  export RESP
  PARSED="$(python3 <<'PY' 2>/dev/null || true
import json, os
code = os.environ.get("PAIRING_CODE", "")
raw  = os.environ.get("RESP", "")
try:
    data = json.loads(raw or "{}")
except Exception:
    print(""); print(0); raise SystemExit
found_chat = ""
max_id = 0
for upd in data.get("result", []):
    max_id = max(max_id, upd.get("update_id", 0))
    msg = upd.get("message") or upd.get("edited_message") or {}
    if msg.get("text", "").strip() == code:
        frm = msg.get("from") or {}
        found_chat = str(frm.get("id", ""))
        break
print(found_chat)
print(max_id)
PY
)"
  CHAT_ID="$(printf '%s\n' "$PARSED" | sed -n '1p')"
  MAX_ID="$(printf '%s\n' "$PARSED" | sed -n '2p')"

  if [ -n "$CHAT_ID" ]; then
    ok "Paired with chat_id $CHAT_ID"
    break
  fi

  if [ "${MAX_ID:-0}" -gt 0 ]; then
    OFFSET=$((MAX_ID + 1))
  fi

  sleep 2
done

if [ -z "$CHAT_ID" ]; then
  warn "Pairing timed out — paste your chat_id manually."
  read -rp "chat_id: " CHAT_ID
  [ -n "$CHAT_ID" ] || { err "chat_id is required"; exit 1; }
fi

read -rp "Groq API key (get one at console.groq.com, leave empty to skip voice transcription): " GROQ_KEY || true

# --- write telegram plugin env ------------------------------------------
TG_ENV="$CLAUDE_HOME/channels/telegram/.env"
mkdir -p "$(dirname "$TG_ENV")"
printf 'TELEGRAM_BOT_TOKEN=%s\n' "$BOT_TOKEN" > "$TG_ENV"
chmod 600 "$TG_ENV"
ok "Wrote $TG_ENV"

# --- write claude-tg config ---------------------------------------------
CFG_ENV="$CFG_DIR/env"
cat > "$CFG_ENV" <<EOF
# claude-tg runtime config (sourced by the hook + transcribe scripts)
export CLAUDE_TG_CHAT_ID=$CHAT_ID
EOF
chmod 600 "$CFG_ENV"

if [ -n "${GROQ_KEY:-}" ]; then
  printf '%s\n' "$GROQ_KEY" > "$CFG_DIR/groq_key"
  chmod 600 "$CFG_DIR/groq_key"
  ok "Saved Groq key to $CFG_DIR/groq_key"
else
  warn "No Groq key — voice transcription disabled (you can add one later)"
fi

# --- merge settings.json ------------------------------------------------
# We merge, never replace. Existing allow rules and hooks stay put.
SETTINGS_PATH="$SETTINGS" PLUGIN_DIR="$PLUGIN_DIR" CHAT_ID="$CHAT_ID" python3 <<'PYEOF'
import json, os, pathlib

settings_path = pathlib.Path(os.environ["SETTINGS_PATH"])
plugin_dir    = os.environ["PLUGIN_DIR"]
chat_id       = os.environ["CHAT_ID"]

data = {}
if settings_path.exists():
    try:
        data = json.loads(settings_path.read_text())
    except json.JSONDecodeError:
        print(f"⚠  {settings_path} was not valid JSON — backing up and starting fresh")
        settings_path.rename(settings_path.with_suffix(".json.bak"))
        data = {}

perm = data.setdefault("permissions", {})
perm.setdefault("defaultMode", "dontAsk")
allow = perm.setdefault("allow", [])
for rule in [
    "Bash", "Write", "Edit", "Read", "Glob", "Grep",
    "mcp__plugin_telegram_telegram__reply",
    "mcp__plugin_telegram_telegram__react",
    "mcp__plugin_telegram_telegram__edit_message",
    "mcp__plugin_telegram_telegram__download_attachment",
]:
    if rule not in allow:
        allow.append(rule)

hooks = data.setdefault("hooks", {})
pretool = hooks.setdefault("PreToolUse", [])

notify_cmd = f"CLAUDE_TG_CHAT_ID='{chat_id}' {plugin_dir}/hooks/notify-bash.sh"

# Replace any existing bash notifier from a previous install
pretool[:] = [
    entry for entry in pretool
    if not any(
        isinstance(h, dict) and h.get("command", "").endswith("notify-bash.sh")
        for h in entry.get("hooks", [])
    )
]
pretool.append({
    "matcher": "Bash",
    "hooks": [{
        "type": "command",
        "command": notify_cmd,
        "async": True,
        "timeout": 5,
    }]
})

plugins = data.setdefault("enabledPlugins", {})
plugins.setdefault("telegram@claude-plugins-official", True)

settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"✓ Updated {settings_path}")
PYEOF

# --- make scripts executable --------------------------------------------
chmod +x "$PLUGIN_DIR/hooks/notify-bash.sh" "$PLUGIN_DIR/scripts/transcribe-voice.sh"

# --- optional: systemd service or screen wrapper ------------------------
say ""
read -rp "Set up claude-tg to run on startup? [s]ystemd / [c]reen / [n]one: " RUN_MODE
RUN_MODE="${RUN_MODE:-n}"

case "$RUN_MODE" in
  s|S)
    if ! command -v systemctl >/dev/null; then
      err "systemd not available on this host — try screen instead"
      exit 1
    fi
    UNIT="/etc/systemd/system/claude-tg.service"
    sed "s|@REPO_DIR@|$REPO_DIR|g; s|@HOME@|$HOME|g" \
      "$REPO_DIR/install/systemd/claude-tg.service" > "$UNIT"
    systemctl daemon-reload
    systemctl enable --now claude-tg.service
    ok "Installed and started systemd unit at $UNIT"
    say "  Logs:    journalctl -u claude-tg.service -f"
    say "  Attach:  sudo -u $USER screen -r claude-tg   (unit uses a named screen)"
    ;;
  c|C)
    bash "$REPO_DIR/install/run-in-screen.sh"
    ok "Started in a screen session named 'claude-tg'"
    say "  Attach:  screen -r claude-tg"
    ;;
  *)
    say "Skipping auto-start. Run Claude manually with:"
    say "  claude --channels plugin:telegram@claude-plugins-official"
    ;;
esac

say ""
ok "Done."
say ""
say "Next steps:"
say "  1. If the plugin isn't loaded yet, inside Claude run:"
say "     ${YLW}/plugin marketplace add file://$REPO_DIR${CLR}"
say "     ${YLW}/plugin install claude-tg@claude-tg${CLR}"
say "  2. Send /start to your bot in Telegram so it can reach you."
say "  3. Talk to the bot — voice or text — and Claude will reply."
say ""
