# claude-recaps

Hook-driven session recap system for Claude Code. Captures every session as a clean transcript, a structured summary, and indexed decisions/learnings/open items.

## What it does

On `SessionEnd`, a background worker:

1. **Extracts** a clean JSONL transcript (user/assistant text only — no tool calls, no thinking blocks)
2. **Summarizes** via `claude -p` into structured JSON: headline, highlights, decisions, open items, learnings, tags
3. **Indexes** extracted items into append-only JSONL files for fast grep
4. **Notifies** your terminal with a one-line completion message

The three stages are independent. If summarization fails, the clean transcript still exists. Stages are re-runnable.

## Install

```bash
git clone https://github.com/jamilt0n/recap.git claude-recaps
cd claude-recaps

# Global: fires for every Claude Code session
./install.sh

# OR project-scoped: fires only for sessions launched from a specific repo
./install.sh --project ~/path/to/repo
```

Project installs write to `<repo>/.claude/settings.local.json` (typically gitignored). Data still lands in `~/.recaps/`.

## File layout

```
~/.recaps/
  transcripts/YYYY/MM/DD_<short_id>.jsonl
  summaries/YYYY/MM/DD_<short_id>_<headline-slug>.json
  indexes/
    decisions.jsonl
    learnings.jsonl
    open_items.jsonl
  logs/
    worker.log
    errors.log
```

Every index entry includes `date`, `session`, `project` (working dir), and `tags` — filter by any.

## Config

Edit `config.yaml`:

```yaml
enabled: true
model: sonnet                # summarizer model
skip_models: [haiku]         # skip these sessions entirely
min_messages: 3              # skip short sessions
min_new_lines: 5             # skip trivial increments on resumed sessions
max_transcript_exchanges: 150
extract_transcript: true     # stage 1
summarize: true              # stage 2
extract_indexes: true        # stage 3
notify: true                 # stderr notification on completion
recap_dir: ~/.recaps
```

## Uninstall

```bash
./uninstall.sh                           # global
./uninstall.sh --project ~/path/to/repo  # project
```

Data in `~/.recaps/` is preserved. Delete it manually if you want it gone.

## Requirements

- `jq`
- `claude` CLI (only needed for the summarization stage)
- bash 4+
