# claude-tg

Drive **Claude Code** from Telegram. Host a persistent Claude session on a
Linux box, talk to it from your phone — text or voice — and watch commands
stream into your chat as they run.

Built for people who want a pocket-sized AI operator for their servers.

## Features

- 🎙 **Voice messages transcribed via Groq Whisper.** Send a voice note;
  Claude hears it, responds in the same language. Groq free tier is plenty
  for personal use.
- 🔧 **Live Bash command feed.** Every shell command Claude is about to run
  shows up in your chat before it executes. No surprises.
- 🔓 **Sensible auto-accept permissions.** No more tapping "allow" for
  every tool call — the installer sets a safe allowlist.
- 🏠 **Runs headless.** Systemd unit or screen wrapper keeps Claude alive
  when you log out.

The Telegram transport itself comes from the official
[`telegram` plugin](https://github.com/anthropics/claude-plugins) — this
repo layers the above on top of it.

## Requirements

- Linux host (any distro with systemd or screen) — macOS support is a
  [TODO](#todo).
- `claude` CLI installed and authenticated (`claude login`).
- A Telegram bot token from [@BotFather](https://t.me/BotFather).
- A Groq API key from [console.groq.com](https://console.groq.com) if you
  want voice messages transcribed (optional).
- `curl`, `python3`, `screen` (if using screen mode).

## Install

```sh
git clone https://github.com/Mirmuxsin/claude-tg.git
cd claude-tg
bash install/install.sh
```

The installer will:

1. Prompt for your Telegram bot token, chat id, and Groq key.
2. Write those to `~/.claude/channels/telegram/.env` and
   `~/.config/claude-tg/` respectively (chmod 600).
3. Merge safe defaults into `~/.claude/settings.json` — permission allowlist
   and the PreToolUse hook. Existing rules are preserved.
4. Optionally install a `systemd` unit or kick off a `screen` session so
   Claude stays alive after you log out.

After install, inside Claude Code add this repo as a plugin marketplace and
enable the plugin:

```
/plugin marketplace add file:///absolute/path/to/claude-tg
/plugin install claude-tg@claude-tg
```

(or push the repo to GitHub and `/plugin marketplace add github:yourname/claude-tg` — same effect.)

Then send any message to your bot from Telegram. Claude replies.

## How it works

```
┌──────────┐         ┌───────────────────────────────┐
│ Your     │ ←────→  │ Telegram Bot (@BotFather one) │
│ Phone    │         └─────────────┬─────────────────┘
└──────────┘                       │
                                   ▼
                     ┌───────────────────────────┐
                     │  telegram plugin (Bun srv)│
                     │  ←→ Claude Code           │
                     └────────────┬──────────────┘
                                  │
         ┌────────────────────────┼─────────────────────────┐
         │                        │                         │
         ▼                        ▼                         ▼
  Voice → Groq Whisper    Every Bash call         settings.json:
  (transcribe-voice.sh)   → notify-bash.sh        auto-accept permissions
                          → Telegram chat
```

- The **Telegram plugin** (`telegram@claude-plugins-official`) is the
  transport. It runs a Bun server and delivers inbound messages to Claude
  as `<channel>` tags.
- **`hooks/notify-bash.sh`** is wired as a `PreToolUse` hook on `Bash`. It
  receives the tool-use payload on stdin, picks out the command, and POSTs
  to Telegram's Bot API.
- **`scripts/transcribe-voice.sh`** is called by Claude (the plugin's
  `CLAUDE.md` tells it to) whenever an inbound voice attachment arrives. It
  uploads the clip to Groq's Whisper endpoint and prints the text.
- **`install/install.sh`** merges allow rules and the hook into your
  `settings.json`.
- **`install/systemd/claude-tg.service`** (or `run-in-screen.sh`) keeps
  Claude running across logouts.

## Configuration

All runtime config lives in env vars the scripts read:

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_TG_CHAT_ID` | — | Your Telegram chat id (required for notifications) |
| `CLAUDE_TG_BOT_TOKEN_FILE` | `~/.claude/channels/telegram/.env` | Where to read `TELEGRAM_BOT_TOKEN=` |
| `CLAUDE_TG_BOT_TOKEN` | — | Raw token (overrides the file) |
| `CLAUDE_TG_GROQ_KEY_FILE` | `~/.config/claude-tg/groq_key` | File containing the Groq API key |
| `CLAUDE_TG_GROQ_KEY` | — | Raw key (overrides the file) |
| `CLAUDE_TG_WHISPER_MODEL` | `whisper-large-v3-turbo` | Which Whisper variant to call |

Installer writes the first two for you. Edit `~/.config/claude-tg/env` to
change them later.

## Uninstall

```sh
# systemd
sudo systemctl disable --now claude-tg.service
sudo rm /etc/systemd/system/claude-tg.service

# secrets + config
rm -rf ~/.config/claude-tg ~/.claude/channels/telegram/.env

# remove hook from ~/.claude/settings.json by hand (search for notify-bash.sh)
```

The plugin itself can be removed via `/plugin uninstall claude-tg@claude-tg`.

## Security

- The bot token and Groq key are stored `chmod 600` in your home directory.
  Don't commit them.
- The Bash hook sends **every command Claude is about to run** to your
  chat. Treat that chat like a shell log — don't share it.
- `defaultMode: dontAsk` means Claude will run allowed tools without
  prompting. Review the allowlist in `~/.claude/settings.json` if you want
  tighter policy.
- Message attestation on the bot API is limited. Use the telegram plugin's
  `/telegram:access` skill to lock down who can pair with your bot.

## TODO

Contributions welcome on any of these:

- [ ] **macOS support.** Replace the systemd unit with a `launchd` plist
      and swap `apt`-specific checks.
- [ ] **Additional voice backends.** Right now Groq Whisper only —
      add optional adapters for OpenAI Whisper, local `whisper.cpp`,
      `faster-whisper`, or anything else that returns text from audio.
- [ ] **Hook for photos/documents** so Claude acknowledges them in
      real time the way it does Bash commands.
- [ ] **Pluggable notification channels.** Slack, Discord, Matrix — same
      idea as Telegram.
- [ ] **Persisted approval-queue** for projects that want durability
      across restarts (currently in-memory only if you wire that in).
- [ ] **Docker setup.** Dockerfile + compose that bundles `claude` + the
      plugin for VPS deploys.

## License

MIT. See [LICENSE](./LICENSE).
