#!/usr/bin/env node
// Hook Event Reporter — command hook replacement for HTTP hooks.
//
// Claude Code HTTP hooks (type: "http") silently fail to fire as of v2.1.78.
// This command hook achieves the same result: POST hook event data to the
// Instar server, which populates claudeSessionId for session resumption.
//
// Runs async (fire-and-forget) to avoid slowing down tool execution.

const http = require('http');

const serverUrl = process.env.INSTAR_SERVER_URL || 'http://localhost:4042';
const authToken = process.env.INSTAR_AUTH_TOKEN || '';
const instarSid = process.env.INSTAR_SESSION_ID || '';

if (!authToken || !instarSid) {
  // Missing env vars — skip silently
  process.exit(0);
}

let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(data);
    const payload = JSON.stringify({
      event: input.hook_event || (input.tool_name ? 'PostToolUse' : 'Unknown'),
      session_id: input.session_id || '',
      tool_name: input.tool_name || '',
    });

    const url = new URL(serverUrl + '/hooks/events?instar_sid=' + instarSid);
    const req = http.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + authToken,
      },
      timeout: 3000,
    }, (res) => {
      res.resume(); // drain response
    });

    req.on('error', () => {}); // silent failure
    req.write(payload);
    req.end();

    // Don't wait for response — exit immediately
    setTimeout(() => process.exit(0), 50);
  } catch (e) {
    process.exit(0);
  }
});

// Timeout safety — don't hang if stdin never closes
setTimeout(() => process.exit(0), 2000);
