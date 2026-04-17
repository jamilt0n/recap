#!/bin/bash
# SessionEnd hook: validate session and queue recap job
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

[[ "$RECAP_ENABLED" != "true" ]] && exit 0

mkdir -p "$RECAP_SUMMARIES_DIR" "$RECAP_JOBS_DIR" "$RECAP_LOGS_DIR"

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
SESSION_ID_SHORT="${SESSION_ID:0:8}"

recap_log "SessionEnd: session=$SESSION_ID, transcript=$TRANSCRIPT_PATH"

# --- Validation gates ---

# Check model against skip list
MODEL_FILE="$RECAP_SESSION_META_DIR/$SESSION_ID.model"
if [[ -f "$MODEL_FILE" ]]; then
    MODEL=$(cat "$MODEL_FILE")
    rm -f "$MODEL_FILE"
    for skip in "${RECAP_SKIP_MODELS[@]}"; do
        if [[ "$MODEL" == *"$skip"* ]]; then
            recap_log "Skipping model: $MODEL (matches $skip)"
            exit 0
        fi
    done
    recap_log "Model: $MODEL"
fi

# Transcript must exist
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    recap_log "No transcript found, skipping"
    exit 0
fi

# Minimum message count
USER_MSG_COUNT=$(jq -r 'select(.type == "user") | .type' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l)
if [[ "$USER_MSG_COUNT" -lt "$RECAP_MIN_MESSAGES" ]]; then
    recap_log "Too few user messages ($USER_MSG_COUNT < $RECAP_MIN_MESSAGES), skipping"
    exit 0
fi

LINE_COUNT=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

# Idempotency: check for existing summary
EXISTING_SUMMARY=""
LAST_LINE_COUNT=0
if [[ -d "$RECAP_SUMMARIES_DIR" ]]; then
    EXISTING_SUMMARY=$(find "$RECAP_SUMMARIES_DIR" -name "*_${SESSION_ID_SHORT}_*" -name "*.json" 2>/dev/null | head -1)
fi

if [[ -n "$EXISTING_SUMMARY" ]] && [[ -f "$EXISTING_SUMMARY" ]]; then
    LAST_LINE_COUNT=$(jq -r '.last_line_count // 0' "$EXISTING_SUMMARY" 2>/dev/null)
    NEW_LINES=$((LINE_COUNT - LAST_LINE_COUNT))

    if [[ "$NEW_LINES" -le 0 ]]; then
        recap_log "Transcript unchanged ($LINE_COUNT <= $LAST_LINE_COUNT), skipping"
        exit 0
    fi
    if [[ "$NEW_LINES" -lt "$RECAP_MIN_NEW_LINES" ]]; then
        recap_log "Too few new lines ($NEW_LINES < $RECAP_MIN_NEW_LINES), skipping"
        exit 0
    fi
    recap_log "Incremental: $LAST_LINE_COUNT -> $LINE_COUNT (+$NEW_LINES lines)"
fi

# --- Build job ---

# Recover TTY and claude binary paths
TTY_PATH=""
TTY_FILE="$RECAP_SESSION_META_DIR/$SESSION_ID.tty"
[[ -f "$TTY_FILE" ]] && TTY_PATH=$(cat "$TTY_FILE") && rm -f "$TTY_FILE"

CLAUDE_BIN=""
CLAUDE_BIN_FILE="$RECAP_SESSION_META_DIR/$SESSION_ID.claude_bin"
[[ -f "$CLAUDE_BIN_FILE" ]] && CLAUDE_BIN=$(cat "$CLAUDE_BIN_FILE") && rm -f "$CLAUDE_BIN_FILE"

# Fallback: try to find claude now
if [[ -z "$CLAUDE_BIN" ]]; then
    CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
JOB_FILE="$RECAP_JOBS_DIR/${SESSION_ID}.json"

cat > "$JOB_FILE" << EOF
{
  "session_id": "$SESSION_ID",
  "session_id_short": "$SESSION_ID_SHORT",
  "transcript_path": "$TRANSCRIPT_PATH",
  "working_dir": "$WORKING_DIR",
  "line_count": $LINE_COUNT,
  "last_line_count": $LAST_LINE_COUNT,
  "existing_summary": "$(echo "$EXISTING_SUMMARY" | sed 's/"/\\"/g')",
  "tty_path": "$TTY_PATH",
  "claude_bin": "$CLAUDE_BIN",
  "timestamp": "$TIMESTAMP"
}
EOF

recap_log "Queued job: $JOB_FILE"

nohup "$RECAP_WORKER_SCRIPT" "$JOB_FILE" >> "$RECAP_LOGS_DIR/worker.log" 2>&1 &

recap_log "Spawned worker (pid $!)"
exit 0
