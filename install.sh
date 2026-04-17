#!/bin/bash
# Install claude-recaps hooks into Claude Code
#
# Global install (default):
#   ./install.sh
#   → Registers hooks in ~/.claude/settings.json, fires for ALL sessions
#
# Project install (scoped to a repo):
#   ./install.sh --project /path/to/repo
#   → Registers hooks in <repo>/.claude/settings.local.json, fires only
#     when sessions are launched from that repo. Data still lands in ~/.recaps/.
#
# Idempotent: safe to run multiple times.
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse args ---

SCOPE="global"
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            SCOPE="project"
            PROJECT_PATH="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# --- Determine target settings file ---

if [[ "$SCOPE" == "project" ]]; then
    if [[ -z "$PROJECT_PATH" ]] || [[ ! -d "$PROJECT_PATH" ]]; then
        echo "Error: --project requires a valid directory path" >&2
        exit 1
    fi
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
    SETTINGS_DIR="$PROJECT_PATH/.claude"
    SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"
    mkdir -p "$SETTINGS_DIR"
else
    SETTINGS_DIR="$HOME/.claude"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"
fi

START_HOOK="$PACKAGE_DIR/hooks/session-start.sh"
END_HOOK="$PACKAGE_DIR/hooks/session-end.sh"

# --- Preflight ---

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    exit 1
fi

if ! command -v claude &> /dev/null; then
    echo "Warning: claude CLI not found in PATH. Summarization requires it." >&2
    echo "Install will continue — the transcript extraction stage works without it." >&2
    echo ""
fi

if [[ "$SCOPE" == "global" ]] && [[ ! -d "$SETTINGS_DIR" ]]; then
    echo "Error: ~/.claude/ does not exist. Is Claude Code installed?" >&2
    exit 1
fi

# --- Read config for recap_dir ---
source "$PACKAGE_DIR/lib/config.sh"

# --- Create data directory structure ---

echo "Creating directories..."
mkdir -p "$RECAP_TRANSCRIPTS_DIR" "$RECAP_SUMMARIES_DIR" "$RECAP_INDEXES_DIR" "$RECAP_LOGS_DIR"
echo "  $RECAP_DIR/"
echo "  $RECAP_TRANSCRIPTS_DIR/"
echo "  $RECAP_SUMMARIES_DIR/"
echo "  $RECAP_INDEXES_DIR/"
echo "  $RECAP_LOGS_DIR/"

# --- Make scripts executable ---

chmod +x "$PACKAGE_DIR"/hooks/*.sh "$PACKAGE_DIR"/lib/*.sh
echo "Scripts marked executable."

# --- Merge hooks into settings.json ---

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
    echo "Created $SETTINGS_FILE"
fi

install_hook() {
    local event="$1"
    local cmd="$2"
    local label="$3"

    if jq -e ".hooks.${event}[]?.hooks[]? | select(.command == \"$cmd\")" "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo "$label hook already installed, skipping."
        return
    fi

    jq --arg event "$event" --arg cmd "$cmd" '
        .hooks[$event] = (.hooks[$event] // []) + [{"hooks": [{"type": "command", "command": $cmd}]}]
    ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

    echo "$label hook installed."
}

echo ""
echo "Configuring hooks ($SCOPE scope)..."
install_hook "SessionStart" "$START_HOOK" "SessionStart"
install_hook "SessionEnd" "$END_HOOK" "SessionEnd"

# --- Summary ---

echo ""
echo "================================================================"
echo "  claude-recaps installed ($SCOPE)"
echo "================================================================"
echo ""
echo "  Package:     $PACKAGE_DIR"
echo "  Settings:    $SETTINGS_FILE"
echo "  Data:        $RECAP_DIR"
echo "  Config:      $PACKAGE_DIR/config.yaml"
echo "  Logs:        $RECAP_LOGS_DIR"
echo ""

if [[ "$SCOPE" == "project" ]]; then
    echo "  Scope: hooks fire only for sessions launched from"
    echo "         $PROJECT_PATH"
    echo ""
    echo "  Note: settings.local.json is typically gitignored."
    echo "        To share the hook config with the repo, move entries to"
    echo "        .claude/settings.json and commit it."
    echo ""
fi

echo "  Edit config.yaml to adjust model, thresholds, or disable."
echo "  Run uninstall.sh [--project <path>] to remove hooks."
echo ""
