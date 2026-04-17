#!/bin/bash
# Stage 2: Generate structured recap from clean transcript
#
# Calls claude -p to summarize. Supports full and incremental modes.
#
# Usage: summarize.sh <clean_transcript> <job_file>
# Prints the output file path on success.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

CLEAN_TRANSCRIPT="$1"
JOB_FILE="$2"

# Read job metadata
SESSION_ID=$(jq -r '.session_id' "$JOB_FILE")
SESSION_ID_SHORT=$(jq -r '.session_id_short' "$JOB_FILE")
WORKING_DIR=$(jq -r '.working_dir' "$JOB_FILE")
LINE_COUNT=$(jq -r '.line_count' "$JOB_FILE")
LAST_LINE_COUNT=$(jq -r '.last_line_count' "$JOB_FILE")
EXISTING_SUMMARY=$(jq -r '.existing_summary // ""' "$JOB_FILE")
CLAUDE_BIN=$(jq -r '.claude_bin // ""' "$JOB_FILE")
TIMESTAMP=$(jq -r '.timestamp' "$JOB_FILE")

# Resolve claude binary
if [[ -z "$CLAUDE_BIN" ]] || [[ ! -x "$CLAUDE_BIN" ]]; then
    CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
fi
if [[ -z "$CLAUDE_BIN" ]]; then
    recap_log_error "claude binary not found, cannot summarize"
    exit 1
fi

# Format transcript for the prompt (role: content, truncated per message)
format_transcript() {
    local file="$1"
    local max_lines="$2"
    jq -r '
      "\(.role | ascii_upcase): \(.content[0:1500])"
    ' "$file" 2>/dev/null | head -"$max_lines"
}

PROMPT_FILE=$(mktemp)
INCREMENTAL=false

if [[ -n "$EXISTING_SUMMARY" ]] && [[ "$EXISTING_SUMMARY" != "null" ]] && [[ -f "$EXISTING_SUMMARY" ]]; then
    INCREMENTAL=true
fi

if [[ "$INCREMENTAL" == "true" ]]; then
    recap_log "Summarize: incremental mode"

    EXISTING_RECAP=$(jq -r '.recaps[-1] |
      "Previous headline: \(.headline)\nPrevious summary: \(.summary)\nPrevious highlights: \(.highlights | join("; "))\nPrevious tags: \(.tags | join(", "))"
    ' "$EXISTING_SUMMARY" 2>/dev/null)

    # For incremental, compute how many new messages to include
    EXISTING_TRANSCRIPT_LINES=$(jq -r '.recaps[-1].line_count // 0' "$EXISTING_SUMMARY" 2>/dev/null)
    # Read only the newer portion of the clean transcript
    TOTAL_CLEAN_LINES=$(wc -l < "$CLEAN_TRANSCRIPT")
    # Rough proportional offset — use last_line_count ratio
    if [[ "$LAST_LINE_COUNT" -gt 0 ]] && [[ "$LINE_COUNT" -gt 0 ]]; then
        SKIP_RATIO=$(( (LAST_LINE_COUNT * TOTAL_CLEAN_LINES) / LINE_COUNT ))
    else
        SKIP_RATIO=0
    fi
    TRANSCRIPT_CONTENT=$(tail -n +"$((SKIP_RATIO + 1))" "$CLEAN_TRANSCRIPT" | jq -r '"\(.role | ascii_upcase): \(.content[0:1500])"' 2>/dev/null | head -"$RECAP_MAX_TRANSCRIPT_EXCHANGES")

    cat > "$PROMPT_FILE" << PROMPT_END
You are updating a Claude Code session recap with new activity. Return ONLY valid JSON, no markdown.

PREVIOUS RECAP:
$EXISTING_RECAP

NEW ACTIVITY (since last recap):
$TRANSCRIPT_CONTENT

Produce an UPDATED recap that incorporates the new activity. Keep existing insights if still relevant, add new ones.

{
  "headline": "5-10 word description - update if focus shifted",
  "summary": "2-3 sentence summary - incorporate new activity",
  "highlights": ["keep relevant old ones", "add new accomplishments", "3-7 total"],
  "decisions": [{"decision": "any new decisions", "rationale": "why", "alternatives_considered": []}],
  "artifacts": {"files_created": [], "files_modified": [], "files_deleted": [], "commands_run": []},
  "concepts": [{"term": "technical term", "context": "how it was used"}],
  "tags": ["merge old and new relevant tags"],
  "open_items": ["update: resolved items removed, new items added"],
  "learnings": ["any new insights"],
  "connections": [{"to": "related system/project", "relationship": "how it relates"}]
}
PROMPT_END

else
    recap_log "Summarize: full mode"

    TRANSCRIPT_CONTENT=$(format_transcript "$CLEAN_TRANSCRIPT" "$RECAP_MAX_TRANSCRIPT_EXCHANGES")

    # Build prompt from template
    if [[ -f "$RECAP_PROMPT_FILE" ]]; then
        PROMPT_TEMPLATE=$(cat "$RECAP_PROMPT_FILE")
    else
        recap_log_error "Prompt file not found: $RECAP_PROMPT_FILE"
        exit 1
    fi

    # Substitute placeholders
    PROMPT_TEMPLATE="${PROMPT_TEMPLATE//\{session_id\}/$SESSION_ID}"
    PROMPT_TEMPLATE="${PROMPT_TEMPLATE//\{working_dir\}/$WORKING_DIR}"
    PROMPT_TEMPLATE="${PROMPT_TEMPLATE//\{timestamp\}/$TIMESTAMP}"

    # Write prompt with transcript (can't use simple substitution for large text)
    echo "${PROMPT_TEMPLATE%%\{transcript\}*}" > "$PROMPT_FILE"
    echo "$TRANSCRIPT_CONTENT" >> "$PROMPT_FILE"
    echo "${PROMPT_TEMPLATE##*\{transcript\}}" >> "$PROMPT_FILE"
fi

# Call claude
recap_log "Calling $CLAUDE_BIN -p --model $RECAP_MODEL..."
SUMMARY=$("$CLAUDE_BIN" -p --model "$RECAP_MODEL" --no-session-persistence --dangerously-skip-permissions < "$PROMPT_FILE" 2>/dev/null | sed 's/^```json//; s/^```//; s/```$//')
rm -f "$PROMPT_FILE"

# Validate JSON
if ! echo "$SUMMARY" | jq . > /dev/null 2>&1; then
    recap_log_error "Invalid JSON from claude, raw output: $(echo "$SUMMARY" | head -5)"
    SUMMARY='{"headline":"Recap generation failed","summary":"Could not parse LLM output.","highlights":["Error during summarization"],"decisions":[],"artifacts":{"files_created":[],"files_modified":[],"files_deleted":[],"commands_run":[]},"concepts":[],"tags":["error"],"open_items":[],"learnings":[],"connections":[]}'
fi

# Generate slug from headline
HEADLINE=$(echo "$SUMMARY" | jq -r '.headline // "session-recap"')
SLUG=$(recap_slugify "$HEADLINE")

# Determine output path
YEAR=$(date +"%Y")
MONTH=$(date +"%m")
DAY=$(date +"%d")
OUT_DIR="$RECAP_SUMMARIES_DIR/$YEAR/$MONTH"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/${DAY}_${SESSION_ID_SHORT}_${SLUG}.json"

# Build final envelope
if [[ "$INCREMENTAL" == "true" ]] && [[ -f "$EXISTING_SUMMARY" ]]; then
    NEW_ENTRY=$(echo "$SUMMARY" | jq --arg ts "$TIMESTAMP" --argjson lc "$LINE_COUNT" '. + {timestamp: $ts, line_count: $lc}')
    FINAL=$(jq --argjson entry "$NEW_ENTRY" --argjson lc "$LINE_COUNT" \
        '.recaps += [$entry] | .last_line_count = $lc' "$EXISTING_SUMMARY")
    # Write to new path, remove old if different
    echo "$FINAL" | jq . > "$OUT_FILE" 2>/dev/null
    if [[ "$EXISTING_SUMMARY" != "$OUT_FILE" ]]; then
        rm -f "$EXISTING_SUMMARY"
        recap_log "Renamed summary: $(basename "$EXISTING_SUMMARY") -> $(basename "$OUT_FILE")"
    fi
else
    FINAL=$(echo "$SUMMARY" | jq --arg sid "$SESSION_ID" --arg wd "$WORKING_DIR" --arg ts "$TIMESTAMP" --argjson lc "$LINE_COUNT" '{
        session_id: $sid,
        working_dir: $wd,
        last_line_count: $lc,
        recaps: [. + {timestamp: $ts, line_count: $lc}]
    }')
    echo "$FINAL" | jq . > "$OUT_FILE" 2>/dev/null
fi

recap_log "Wrote summary: $OUT_FILE"
echo "$OUT_FILE"
