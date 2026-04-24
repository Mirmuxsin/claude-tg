#!/bin/bash
# Transcribe an audio file via Groq Whisper API.
# Usage: transcribe-voice.sh <audio-file-path> [language]
# Outputs the transcription text to stdout. Errors go to stderr; exit non-zero on failure.
#
# Config (env vars, any optional):
#   CLAUDE_TG_GROQ_KEY_FILE   path to a file containing the Groq API key
#                             (default: ~/.config/claude-tg/groq_key)
#   CLAUDE_TG_GROQ_KEY        raw API key as a string (overrides KEY_FILE)
#   CLAUDE_TG_WHISPER_MODEL   Whisper model name (default: whisper-large-v3-turbo)

set -euo pipefail

KEY_FILE="${CLAUDE_TG_GROQ_KEY_FILE:-$HOME/.config/claude-tg/groq_key}"
MODEL="${CLAUDE_TG_WHISPER_MODEL:-whisper-large-v3-turbo}"

if [ $# -lt 1 ]; then
  echo "usage: $0 <audio-file> [language-code]" >&2
  exit 2
fi

AUDIO="$1"
LANG="${2:-}"

if [ ! -f "$AUDIO" ]; then
  echo "file not found: $AUDIO" >&2
  exit 2
fi

if [ -n "${CLAUDE_TG_GROQ_KEY:-}" ]; then
  KEY="$CLAUDE_TG_GROQ_KEY"
elif [ -r "$KEY_FILE" ]; then
  KEY="$(cat "$KEY_FILE")"
else
  echo "no Groq key: set CLAUDE_TG_GROQ_KEY env var or create $KEY_FILE" >&2
  exit 2
fi

# Telegram voice notes arrive as .oga; Groq's endpoint only accepts .ogg (and
# a handful of other standard extensions). Map the uncommon ones to accepted
# names — the bytes are unchanged, only the filename label differs.
EXT="${AUDIO##*.}"
case "${EXT,,}" in
  oga) UPLOAD_NAME="audio.ogg" ;;
  *)   UPLOAD_NAME="audio.$EXT" ;;
esac

ARGS=(-sS -X POST "https://api.groq.com/openai/v1/audio/transcriptions"
      -H "Authorization: Bearer $KEY"
      -F "file=@$AUDIO;filename=$UPLOAD_NAME"
      -F "model=$MODEL"
      -F "response_format=text")

if [ -n "$LANG" ]; then
  ARGS+=(-F "language=$LANG")
fi

RESPONSE="$(curl "${ARGS[@]}")"

# Success responses are plain text; errors come back as a JSON envelope
if [[ "$RESPONSE" == \{* ]]; then
  echo "groq api error: $RESPONSE" >&2
  exit 1
fi

printf '%s\n' "$RESPONSE"
