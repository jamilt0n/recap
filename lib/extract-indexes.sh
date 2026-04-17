#!/bin/bash
# Stage 3: Extract decisions, learnings, open_items from recap into JSONL indexes
#
# Deduplicates by session ID: removes previous entries for the same session
# before appending updated ones (handles incremental recaps cleanly).
#
# Usage: extract-indexes.sh <summary_file>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

SUMMARY_FILE="$1"

if [[ ! -f "$SUMMARY_FILE" ]]; then
    recap_log_error "Summary file not found: $SUMMARY_FILE"
    exit 1
fi

mkdir -p "$RECAP_INDEXES_DIR"

SESSION_ID=$(jq -r '.session_id' "$SUMMARY_FILE")
WORKING_DIR=$(jq -r '.working_dir // ""' "$SUMMARY_FILE")
LATEST=$(jq '.recaps[-1]' "$SUMMARY_FILE")
DATE=$(echo "$LATEST" | jq -r '.timestamp // empty' | cut -dT -f1)
TAGS=$(echo "$LATEST" | jq -c '.tags // []')

# Deduplication helper: remove existing entries for this session, then append new ones
dedup_and_append() {
    local index_file="$1"
    local new_entries="$2"

    if [[ -f "$index_file" ]]; then
        # Remove previous entries for this session
        grep -v "\"session\":\"$SESSION_ID\"" "$index_file" > "${index_file}.tmp" 2>/dev/null || true
        mv "${index_file}.tmp" "$index_file"
    fi

    # Append new entries (skip if empty)
    if [[ -n "$new_entries" ]]; then
        echo "$new_entries" >> "$index_file"
    fi
}

# Decisions
DECISIONS=$(echo "$LATEST" | jq -c --arg date "$DATE" --arg sid "$SESSION_ID" --arg wd "$WORKING_DIR" --argjson tags "$TAGS" '
  .decisions // [] | .[] |
  {date: $date, session: $sid, project: $wd, decision: .decision, rationale: (.rationale // null), tags: $tags}
' 2>/dev/null)
dedup_and_append "$RECAP_INDEXES_DIR/decisions.jsonl" "$DECISIONS"

# Open items
OPEN_ITEMS=$(echo "$LATEST" | jq -c --arg date "$DATE" --arg sid "$SESSION_ID" --arg wd "$WORKING_DIR" --argjson tags "$TAGS" '
  .open_items // [] | .[] |
  {date: $date, session: $sid, project: $wd, item: ., tags: $tags}
' 2>/dev/null)
dedup_and_append "$RECAP_INDEXES_DIR/open_items.jsonl" "$OPEN_ITEMS"

# Learnings
LEARNINGS=$(echo "$LATEST" | jq -c --arg date "$DATE" --arg sid "$SESSION_ID" --arg wd "$WORKING_DIR" --argjson tags "$TAGS" '
  .learnings // [] | .[] |
  {date: $date, session: $sid, project: $wd, learning: ., tags: $tags}
' 2>/dev/null)
dedup_and_append "$RECAP_INDEXES_DIR/learnings.jsonl" "$LEARNINGS"

recap_log "Extracted indexes for session $SESSION_ID"
