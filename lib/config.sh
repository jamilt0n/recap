#!/bin/bash
# Config loader for claude-recaps
# Sources config.yaml into bash variables with RECAP_ prefix
# Sourced by all other scripts in this package

# Resolve package root (handles symlinks from install)
_resolve_package_dir() {
    local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local dir
    dir="$(cd "$(dirname "$source")" && pwd)"
    # If we're in lib/ or hooks/, go up one level
    case "$dir" in
        */lib|*/hooks) dir="$(dirname "$dir")" ;;
    esac
    echo "$dir"
}

RECAP_PACKAGE_DIR="$(_resolve_package_dir)"
RECAP_CONFIG_FILE="${RECAP_CONFIG_FILE:-$RECAP_PACKAGE_DIR/config.yaml}"

# Defaults
RECAP_ENABLED=true
RECAP_MODEL=sonnet
RECAP_SKIP_MODELS=(haiku)
RECAP_MIN_MESSAGES=3
RECAP_MIN_NEW_LINES=5
RECAP_MAX_TRANSCRIPT_EXCHANGES=150
RECAP_EXTRACT_TRANSCRIPT=true
RECAP_SUMMARIZE=true
RECAP_EXTRACT_INDEXES=true
RECAP_NOTIFY=true
RECAP_DIR="$HOME/.recaps"

# Parse config.yaml (flat key: value only)
if [[ -f "$RECAP_CONFIG_FILE" ]]; then
    while IFS= read -r line; do
        # Strip comments and trim
        line="${line%%#*}"
        [[ -z "${line// /}" ]] && continue

        key="${line%%:*}"
        value="${line#*: }"
        key="${key// /}"
        value="${value## }"
        value="${value%% }"

        # Expand tilde
        value="${value/#\~/$HOME}"

        case "$key" in
            enabled)                  RECAP_ENABLED="$value" ;;
            model)                    RECAP_MODEL="$value" ;;
            skip_models)
                # Parse [val1, val2] into bash array
                value="${value#\[}"
                value="${value%\]}"
                IFS=', ' read -ra RECAP_SKIP_MODELS <<< "$value"
                ;;
            min_messages)             RECAP_MIN_MESSAGES="$value" ;;
            min_new_lines)            RECAP_MIN_NEW_LINES="$value" ;;
            max_transcript_exchanges) RECAP_MAX_TRANSCRIPT_EXCHANGES="$value" ;;
            extract_transcript)       RECAP_EXTRACT_TRANSCRIPT="$value" ;;
            summarize)                RECAP_SUMMARIZE="$value" ;;
            extract_indexes)          RECAP_EXTRACT_INDEXES="$value" ;;
            notify)                   RECAP_NOTIFY="$value" ;;
            recap_dir)                RECAP_DIR="$value" ;;
        esac
    done < "$RECAP_CONFIG_FILE"
fi

# Computed paths
RECAP_TRANSCRIPTS_DIR="$RECAP_DIR/transcripts"
RECAP_SUMMARIES_DIR="$RECAP_DIR/summaries"
RECAP_INDEXES_DIR="$RECAP_DIR/indexes"
RECAP_LOGS_DIR="$RECAP_DIR/logs"
RECAP_JOBS_DIR="/tmp/recap-jobs"
RECAP_SESSION_META_DIR="/tmp/claude-sessions"
RECAP_PROMPT_FILE="$RECAP_PACKAGE_DIR/prompts/recap.md"
RECAP_WORKER_SCRIPT="$RECAP_PACKAGE_DIR/lib/worker.sh"

# Utility: slugify a headline
recap_slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-50
}

# Utility: log with timestamp
recap_log() {
    echo "[$(date -Iseconds)] $*" >> "$RECAP_LOGS_DIR/worker.log"
}

recap_log_error() {
    echo "[$(date -Iseconds)] ERROR: $*" >> "$RECAP_LOGS_DIR/errors.log"
}
