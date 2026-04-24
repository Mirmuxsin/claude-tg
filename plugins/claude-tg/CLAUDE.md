# claude-tg — assistant guidance

This plugin lets the user drive Claude Code remotely via Telegram. When this
plugin is loaded, adjust your behavior as follows:

## Voice messages

When an inbound `<channel source="plugin:telegram:telegram" ...>` message has
`attachment_kind="voice"` (or any audio mime type) and an `attachment_file_id`:

1. Call `mcp__plugin_telegram_telegram__download_attachment` with the file_id.
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/transcribe-voice.sh <downloaded-path>` to
   transcribe via Groq Whisper.
3. Treat the transcription as the user's actual message content and respond
   accordingly via `mcp__plugin_telegram_telegram__reply`. If transcription
   fails (script exits non-zero), tell the user what failed rather than
   guessing at the content.

## Match the user's language

Reply in the language of the user's most recent message:
- Voice in Russian → reply in Russian
- Text in English → reply in English
- Text in Uzbek or another language → reply in the same language

Code blocks (commands, paths, scripts, prompts being edited) stay verbatim
regardless of reply language — only the surrounding prose switches.

## Bash command notifications

A `PreToolUse` hook on `Bash` pings the user's Telegram chat with each command
before it runs. This is intentional: the user interacts from their phone and
wants visibility into what's executing. Don't suppress or batch these.

## Permissions

The installer sets `defaultMode: dontAsk` plus an allowlist for common tools
(Bash, Write, Edit, Read, Glob, Grep, and the telegram plugin's tools). If
something new prompts repeatedly, suggest the user add it to the allow list
via `/permissions`.

## Scripts shipped by this plugin

- `scripts/transcribe-voice.sh <audio-file> [language]` — prints transcription
  to stdout. Reads Groq key from `$CLAUDE_TG_GROQ_KEY_FILE` (default
  `~/.config/claude-tg/groq_key`). Defaults to `whisper-large-v3-turbo`.

- `hooks/notify-bash.sh` — PreToolUse hook for Bash. Reads the Telegram chat
  id from `$CLAUDE_TG_CHAT_ID` and the bot token from the telegram plugin's
  installed env file.
