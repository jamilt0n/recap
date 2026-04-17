# Session Recap

You are analyzing a Claude Code session transcript to extract structured insights.

## Output Format

Return ONLY valid JSON with this structure:

```json
{
  "headline": "<5-10 word description of primary session focus>",
  "summary": "<2-3 sentence executive summary of what was accomplished>",

  "highlights": [
    "<Key accomplishment or decision - be specific>",
    "<Another significant point>"
  ],

  "decisions": [
    {
      "decision": "<What was decided>",
      "rationale": "<Why, if discussed>",
      "alternatives_considered": ["<other options if mentioned>"]
    }
  ],

  "artifacts": {
    "files_created": ["<path>"],
    "files_modified": ["<path>"],
    "files_deleted": ["<path>"],
    "commands_run": ["<significant commands>"]
  },

  "concepts": [
    {
      "term": "<Technical term or concept discussed>",
      "context": "<How it was used/relevant>"
    }
  ],

  "tags": ["<keyword>", "<keyword>"],

  "open_items": [
    "<Unfinished task or question>",
    "<Something to follow up on>"
  ],

  "learnings": [
    "<Something discovered or figured out during session>",
    "<A pattern or insight that emerged>"
  ],

  "connections": [
    {
      "to": "<Related project, system, or concept>",
      "relationship": "<How this session relates to it>"
    }
  ]
}
```

## Guidelines

1. **Be specific** - "Implemented session recap hooks" not "Made progress on hooks"
2. **Extract decisions** - These are valuable for understanding project evolution
3. **Capture learnings** - Insights that could inform future work
4. **Note connections** - How this session relates to other systems/projects
5. **List actual file paths** - Not placeholders
6. **Keep tags searchable** - Use consistent terminology
7. **Highlights should be 3-7 items** - Most important points only
8. **Open items are actionable** - Things that need follow-up

## Session Context

Session ID: {session_id}
Working Directory: {working_dir}
Timestamp: {timestamp}

## Transcript

{transcript}
