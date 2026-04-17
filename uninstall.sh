#!/bin/bash
# Uninstall claude-recaps hooks from Claude Code
#
# Global:  ./uninstall.sh
# Project: ./uninstall.sh --project /path/to/repo
#
# Removes hook entries. Does NOT delete ~/.recaps/ (your data is preserved).
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCOPE="global"
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            SCOPE="project"
            PROJECT_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ "$SCOPE" == "project" ]]; then
    if [[ -z "$PROJECT_PATH" ]] || [[ ! -d "$PROJECT_PATH" ]]; then
        echo "Error: --project requires a valid directory path" >&2
        exit 1
    fi
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
    SETTINGS_FILE="$PROJECT_PATH/.claude/settings.local.json"
else
    SETTINGS_FILE="$HOME/.claude/settings.json"
fi

START_HOOK="$PACKAGE_DIR/hooks/session-start.sh"
END_HOOK="$PACKAGE_DIR/hooks/session-end.sh"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "No settings file found at $SETTINGS_FILE, nothing to uninstall."
    exit 0
fi

remove_hook() {
    local event="$1"
    local cmd="$2"
    local label="$3"

    if ! jq -e ".hooks.${event}[]?.hooks[]? | select(.command == \"$cmd\")" "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo "$label hook not found, skipping."
        return
    fi

    jq --arg event "$event" --arg cmd "$cmd" '
        .hooks[$event] = [.hooks[$event][]? | select(.hooks | all(.command != $cmd))] |
        if .hooks[$event] == [] then del(.hooks[$event]) else . end |
        if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

    echo "$label hook removed."
}

echo "Removing hooks ($SCOPE) from $SETTINGS_FILE..."
remove_hook "SessionStart" "$START_HOOK" "SessionStart"
remove_hook "SessionEnd" "$END_HOOK" "SessionEnd"

# Clean up temp files (only relevant for global uninstall)
if [[ "$SCOPE" == "global" ]]; then
    rm -rf /tmp/claude-sessions/ /tmp/recap-jobs/
    echo "Cleaned up temp files."
fi

echo ""
echo "Uninstalled. Your data in ~/.recaps/ is preserved."
