#!/usr/bin/env node
// Deferral detector — catches agents deferring work they could do themselves.
// PreToolUse hook for Bash commands. Scans outgoing messages for deferral patterns.
// When detected, injects a due diligence checklist (does NOT block).
//
// Born from an agent saying "This is credential input I cannot do myself"
// when it already had the token available via CLI tools.

let data = '';
process.stdin.on('data', chunk => data += chunk);
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(data);
    if (input.tool_name !== 'Bash') process.exit(0);

    const command = (input.tool_input || {}).command || '';
    if (!command) process.exit(0);

    // Only check communication commands (messages to humans)
    const commPatterns = [
      /telegram-reply/i, /send-email/i, /send-message/i,
      /POST.*\/telegram\/reply/i, /slack.*send/i
    ];
    if (!commPatterns.some(p => p.test(command))) process.exit(0);

    // Exempt: genuinely human-only actions
    if (/password|captcha|legal|billing|payment credential/i.test(command)) process.exit(0);

    // Deferral patterns
    const patterns = [
      { re: /(?:I |i )(?:can'?t|cannot|am (?:not |un)able to)/i, type: 'inability_claim' },
      { re: /(?:this |it )(?:requires|needs) (?:your|human|manual) (?:input|intervention|action)/i, type: 'human_required' },
      { re: /you(?:'ll| will)? need to (?:do|handle|complete|input|enter|run|execute|click)/i, type: 'directing_human' },
      { re: /(?:you (?:can|could|should|might want to) )(?:run|execute|navigate|open|click)/i, type: 'suggesting_human_action' },
      { re: /(?:want me to|should I|shall I|would you like me to) (?:proceed|continue|go ahead)/i, type: 'permission_seeking' },
      { re: /(?:blocker|blocking issue|can'?t proceed (?:without|until))/i, type: 'claimed_blocker' },
    ];

    const matches = patterns.filter(p => p.re.test(command));
    if (matches.length === 0) process.exit(0);

    const checklist = [
      'DEFERRAL DETECTED — Before claiming you cannot do something, verify:',
      '',
      '1. Did you check --help or docs for the tool you are using?',
      '2. Did you search for a token/API-based alternative to interactive auth?',
      '3. Do you already have credentials/tokens that might work? (env vars, CLI auth, saved configs)',
      '4. Can you use browser automation to complete interactive flows?',
      '5. Is this GENUINELY beyond your access? (e.g., typing a password, solving a CAPTCHA)',
      '',
      'If ANY check might work — try it first.',
      'The pattern: You are DESCRIBING work instead of DOING work.',
      '',
      'Detected: ' + matches.map(m => m.type).join(', '),
    ].join('\n');

    process.stdout.write(JSON.stringify({ decision: 'approve', additionalContext: checklist }));
  } catch { /* don't break on errors */ }
  process.exit(0);
});
