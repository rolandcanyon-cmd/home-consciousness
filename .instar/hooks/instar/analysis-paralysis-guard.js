#!/usr/bin/env node
// Analysis-Paralysis Guard — catches agents stuck in a read-loop without acting.
// PostToolUse hook. Tracks a sliding window of recent tool calls in a small
// state file. If READ_ONLY tools (Read/Grep/Glob/WebFetch) fire 5+ times
// in a row without an ACTION tool (Edit/Write/Bash/NotebookEdit) in between,
// injects a "act or report blocked" checklist.
//
// Borrowed from gsd-executor's prompt — proven to kill a known failure mode
// where agents spend the whole session researching and never commit.
//
// Cherry-picked into Instar's hook layer 2026-05-23 from the GSD-Instar
// integration spike (docs/specs/topic-intent-layer.md + the spike report).
// Signal-only — never blocks. Decision: approve + additionalContext.

// NOTE: uses `await import('node:fs')` inside the handler rather than a
// top-level `require` — a bare require crashes outright in ESM-mode agents
// (the hook-event-reporter lesson: an install-if-missing CJS hook left ESM
// hosts permanently broken). Dynamic import works in both module systems.

const READ_ONLY_TOOLS = new Set(['Read', 'Grep', 'Glob', 'WebFetch', 'WebSearch']);
const ACTION_TOOLS = new Set(['Edit', 'Write', 'Bash', 'NotebookEdit']);
const PARALYSIS_THRESHOLD = 5;
const STATE_FILE_REL = '.instar/state/analysis-paralysis-state.json';

let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', async () => {
  try {
    const fs = await import('node:fs');
    const path = await import('node:path');
    const input = JSON.parse(data);
    const toolName = input.tool_name || '';
    if (!toolName) process.exit(0);

    // Locate state file. CLAUDE_PROJECT_DIR is set by Claude Code on every hook.
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const stateFile = path.join(projectDir, STATE_FILE_REL);
    let state = { recent: [] };
    try {
      if (fs.existsSync(stateFile)) {
        state = JSON.parse(fs.readFileSync(stateFile, 'utf-8'));
        if (!Array.isArray(state.recent)) state.recent = [];
      }
    } catch { state = { recent: [] }; }

    const sessionId = input.session_id || 'default';
    const now = new Date().toISOString();

    // Action tool → reset the per-session window
    if (ACTION_TOOLS.has(toolName)) {
      state.recent = state.recent.filter(e => e.sessionId !== sessionId);
      try {
        fs.mkdirSync(path.dirname(stateFile), { recursive: true });
        fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
      } catch { /* best effort */ }
      process.exit(0);
    }

    // Read-only tool → append to the window
    if (READ_ONLY_TOOLS.has(toolName)) {
      state.recent.push({ sessionId, tool: toolName, at: now });
      // Cap total entries across sessions to bound state file size
      if (state.recent.length > 200) state.recent = state.recent.slice(-200);
      try {
        fs.mkdirSync(path.dirname(stateFile), { recursive: true });
        fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
      } catch { /* best effort */ }

      // Count contiguous read-only entries for THIS session
      const sessionEntries = state.recent.filter(e => e.sessionId === sessionId);
      const consecutiveRO = sessionEntries.length;

      if (consecutiveRO >= PARALYSIS_THRESHOLD) {
        const checklist = [
          'ANALYSIS-PARALYSIS DETECTED — ' + consecutiveRO + ' consecutive read-only tool calls (' +
            sessionEntries.slice(-5).map(e => e.tool).join(' → ') + ') without an Edit / Write / Bash.',
          '',
          'You have been researching without acting. Two paths from here:',
          '',
          '1. ACT — pick the smallest concrete action you can take with what you already know and DO it.',
          '   The next Edit / Write / Bash resets this counter.',
          '',
          '2. REPORT BLOCKED — if you genuinely cannot proceed, state precisely what is missing:',
          '   - a specific file or value you need access to',
          '   - a decision only the user can make',
          '   - an external dependency that has not been provisioned',
          '',
          'If neither path is true, you are avoiding the hard part. Pick option 1.',
        ];
        process.stdout.write(JSON.stringify({ decision: 'approve', additionalContext: checklist.join('\n') }));
        process.exit(0);
      }
    }
    // Other tools (TaskCreate, etc.) — pass through unchanged
  } catch { /* never block on errors */ }
  process.exit(0);
});
