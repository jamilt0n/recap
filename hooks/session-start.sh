#!/bin/bash
# SessionStart hook: stash model and TTY for use by SessionEnd
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

[[ "$RECAP_ENABLED" != "true" ]] && exit 0

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
MODEL=$(echo "$INPUT" | jq -r '.model // ""')

if [[ -n "$SESSION_ID" ]]; then
    mkdir -p "$RECAP_SESSION_META_DIR"

    # Stash model for filtering at session end
    [[ -n "$MODEL" ]] && echo "$MODEL" > "$RECAP_SESSION_META_DIR/$SESSION_ID.model"

    # Stash TTY for notification from background worker
    TTY_PATH=$(tty 2>/dev/null || true)
    if [[ "$TTY_PATH" == /dev/* ]]; then
        echo "$TTY_PATH" > "$RECAP_SESSION_META_DIR/$SESSION_ID.tty"
    fi

    # Stash claude binary path while we know it's available
    CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
    if [[ -n "$CLAUDE_BIN" ]]; then
        echo "$CLAUDE_BIN" > "$RECAP_SESSION_META_DIR/$SESSION_ID.claude_bin"
    fi
fi

exit 0
