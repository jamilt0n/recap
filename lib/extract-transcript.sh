#!/bin/bash
# Stage 1: Extract clean transcript from raw CC session JSONL
#
# Produces a compact JSONL with just user/assistant text messages.
# No tool calls, no thinking blocks, no metadata.
#
# Usage: extract-transcript.sh <raw_transcript> <session_id_short> [line_count] [last_line_count]
# Prints the output file path on success.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

RAW_TRANSCRIPT="$1"
SESSION_ID_SHORT="$2"
LINE_COUNT="${3:-0}"
LAST_LINE_COUNT="${4:-0}"

YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")
OUT_DIR="$RECAP_TRANSCRIPTS_DIR/$YEAR/$MONTH"
OUT_FILE="$OUT_DIR/${DAY}_${SESSION_ID_SHORT}.jsonl"

mkdir -p "$OUT_DIR"

# jq filter: extract only text content from user and assistant messages
JQ_FILTER='
select(.type == "user" or .type == "assistant") |
{
  role: .type,
  content: (
    .message.content //
    (if .type == "user" then
      (.content // "")
    else "" end) |
    if type == "string" then .
    elif type == "array" then
      [.[] | select(.type == "text") | .text] | join("\n")
    else ""
    end
  ),
  ts: (.timestamp // .ts // null)
} |
select(.content != "" and .content != null)
'

if [[ "$LAST_LINE_COUNT" -gt 0 ]]; then
    # Incremental: only process new lines, append to existing file
    tail -n +"$((LAST_LINE_COUNT + 1))" "$RAW_TRANSCRIPT" | jq -c "$JQ_FILTER" >> "$OUT_FILE" 2>/dev/null
else
    # Full extraction
    jq -c "$JQ_FILTER" "$RAW_TRANSCRIPT" > "$OUT_FILE" 2>/dev/null
fi

echo "$OUT_FILE"
