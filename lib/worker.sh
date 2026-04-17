#!/bin/bash
# Worker: orchestrates the three-stage recap pipeline
#
# Runs in background (spawned by session-end hook via nohup).
# Stages are independent — if stage 2 fails, stage 1 output is preserved.
#
# Usage: worker.sh <job_file> | worker.sh --process-all
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

process_job() {
    local JOB_FILE="$1"

    if [[ ! -f "$JOB_FILE" ]]; then
        recap_log "Job file not found: $JOB_FILE"
        return 1
    fi

    local SESSION_ID SESSION_ID_SHORT TRANSCRIPT_PATH LINE_COUNT LAST_LINE_COUNT TTY_PATH
    SESSION_ID=$(jq -r '.session_id' "$JOB_FILE")
    SESSION_ID_SHORT=$(jq -r '.session_id_short' "$JOB_FILE")
    TRANSCRIPT_PATH=$(jq -r '.transcript_path' "$JOB_FILE")
    LINE_COUNT=$(jq -r '.line_count' "$JOB_FILE")
    LAST_LINE_COUNT=$(jq -r '.last_line_count' "$JOB_FILE")
    TTY_PATH=$(jq -r '.tty_path // ""' "$JOB_FILE")

    recap_log "Processing: session=$SESSION_ID_SHORT, lines=$LINE_COUNT"

    if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
        recap_log_error "Transcript gone: $TRANSCRIPT_PATH"
        rm -f "$JOB_FILE"
        return 1
    fi

    local CLEAN_TRANSCRIPT=""
    local SUMMARY_FILE=""

    # --- Stage 1: Extract clean transcript ---
    if [[ "$RECAP_EXTRACT_TRANSCRIPT" == "true" ]]; then
        recap_log "Stage 1: extracting transcript"
        CLEAN_TRANSCRIPT=$("$SCRIPT_DIR/extract-transcript.sh" "$TRANSCRIPT_PATH" "$SESSION_ID_SHORT" "$LINE_COUNT" "$LAST_LINE_COUNT" 2>&1) || {
            recap_log_error "Stage 1 failed: $CLEAN_TRANSCRIPT"
            CLEAN_TRANSCRIPT=""
        }
        if [[ -n "$CLEAN_TRANSCRIPT" ]] && [[ -f "$CLEAN_TRANSCRIPT" ]]; then
            recap_log "Stage 1 complete: $CLEAN_TRANSCRIPT"
        fi
    fi

    # --- Stage 2: Summarize ---
    if [[ "$RECAP_SUMMARIZE" == "true" ]]; then
        recap_log "Stage 2: summarizing"

        # Use clean transcript if available, fall back to raw
        local SUMMARIZE_INPUT="${CLEAN_TRANSCRIPT:-$TRANSCRIPT_PATH}"

        SUMMARY_FILE=$("$SCRIPT_DIR/summarize.sh" "$SUMMARIZE_INPUT" "$JOB_FILE" 2>&1) || {
            recap_log_error "Stage 2 failed: $SUMMARY_FILE"
            SUMMARY_FILE=""
        }
        if [[ -n "$SUMMARY_FILE" ]] && [[ -f "$SUMMARY_FILE" ]]; then
            recap_log "Stage 2 complete: $SUMMARY_FILE"
        fi
    fi

    # --- Stage 3: Extract indexes ---
    if [[ "$RECAP_EXTRACT_INDEXES" == "true" ]] && [[ -n "$SUMMARY_FILE" ]] && [[ -f "$SUMMARY_FILE" ]]; then
        recap_log "Stage 3: extracting indexes"
        "$SCRIPT_DIR/extract-indexes.sh" "$SUMMARY_FILE" 2>&1 || {
            recap_log_error "Stage 3 failed"
        }
        recap_log "Stage 3 complete"
    fi

    # --- Notification ---
    if [[ "$RECAP_NOTIFY" == "true" ]] && [[ -n "$SUMMARY_FILE" ]] && [[ -f "$SUMMARY_FILE" ]]; then
        if [[ -n "$TTY_PATH" ]] && [[ -w "$TTY_PATH" ]]; then
            local HEADLINE SLUG TOKEN_EST
            HEADLINE=$(jq -r '.recaps[-1].headline // "recap complete"' "$SUMMARY_FILE" 2>/dev/null)
            SLUG=$(recap_slugify "$HEADLINE")
            TOKEN_EST=$(( $(wc -c < "$SUMMARY_FILE") / 4 ))
            echo "recap: $SLUG (~${TOKEN_EST} tok)" > "$TTY_PATH" 2>/dev/null || true
        fi
    fi

    rm -f "$JOB_FILE"
    recap_log "Job complete: $SESSION_ID_SHORT"
    return 0
}

# --- Main ---
if [[ "${1:-}" == "--process-all" ]]; then
    recap_log "Processing all pending jobs..."
    for job in "$RECAP_JOBS_DIR"/*.json; do
        [[ -f "$job" ]] || continue
        process_job "$job"
    done
    recap_log "All jobs processed"
elif [[ -n "${1:-}" ]]; then
    process_job "$1"
else
    echo "Usage: $0 <job-file.json> | --process-all" >&2
    exit 1
fi
