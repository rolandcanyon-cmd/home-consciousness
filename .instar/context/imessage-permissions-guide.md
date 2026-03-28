# iMessage Permissions Setup Guide

**Date**: 2026-03-28
**macOS Version**: 14+ required

## Overview

The `imsg` tool needs two permissions to work:
1. **Full Disk Access** - to read the Messages database
2. **Automation** - to send messages via AppleScript

## Step 1: Grant Full Disk Access

This allows imsg to read `~/Library/Messages/chat.db`

### Option A: Terminal.app (if you use standard Terminal)

1. **Open System Settings**
   - Click Apple menu  > System Settings

2. **Navigate to Privacy & Security**
   - Scroll down in the left sidebar
   - Click "Privacy & Security"

3. **Open Full Disk Access**
   - Scroll down in the right pane
   - Click "Full Disk Access"

4. **Unlock to make changes**
   - Click the lock icon in the bottom left
   - Enter your password

5. **Add Terminal**
   - Click the "+" button
   - Navigate to `/Applications/Utilities/`
   - Select `Terminal.app`
   - Click "Open"

6. **Enable the toggle**
   - Make sure the switch next to Terminal is ON (blue)

7. **Restart Terminal**
   - Quit Terminal completely (Cmd+Q)
   - Reopen it
   - **Important**: You MUST restart for permissions to take effect

### Option B: iTerm2 (if you use iTerm)

Follow the same steps but add `/Applications/iTerm.app` instead

### Option C: Visual Studio Code Terminal

If running from VS Code's integrated terminal:

1. Follow the same steps
2. Add `/Applications/Visual Studio Code.app`
3. Restart VS Code

### Option D: Grant to the shell itself

More permissive but works from any terminal:

1. Follow the same steps
2. Navigate to `/bin/`
3. Add `bash` (or `zsh` depending on your shell)
4. Restart your terminal

## Step 2: Grant Automation Permission

This allows imsg to control Messages.app to send messages.

### Initial Setup

The first time you try to send a message, macOS will prompt you. But you can set it up manually:

1. **Open System Settings**
   - Click Apple menu  > System Settings

2. **Navigate to Privacy & Security**
   - Scroll down in the left sidebar
   - Click "Privacy & Security"

3. **Open Automation**
   - Scroll down in the right pane
   - Click "Automation"

4. **Find your terminal app**
   - Look for Terminal.app, iTerm.app, or whatever you're using
   - Expand it by clicking the disclosure triangle

5. **Enable Messages.app**
   - Check the box next to "Messages.app"

### Or trigger the prompt

Alternatively, just try to send a test message and approve when prompted:

```bash
# This will trigger the automation permission dialog
imsg send --to "+14081234567" --text "Test" --service imessage
```

When the dialog appears, click "OK" to allow.

## Verify Permissions

Run the test script to check everything is working:

```bash
chmod +x .claude/scripts/test-imessage-permissions.sh
./.claude/scripts/test-imessage-permissions.sh
```

You should see green checkmarks (✓) for:
- ✓ imsg is installed
- ✓ Messages database exists
- ✓ Full Disk Access granted
- ✓ Can read message history
- ✓ RPC mode working

## Troubleshooting

### "permission denied" error persists

**Problem**: Even after granting Full Disk Access, still getting permission errors

**Solution**:
1. Make sure you restarted your terminal COMPLETELY (Cmd+Q, not just close window)
2. Check that the toggle is actually ON in System Settings
3. Try logging out and back in to macOS
4. In rare cases, you may need to reboot

### "Messages.app is not running" error

**Problem**: Can't send messages

**Solution**:
1. Open Messages.app manually
2. Make sure you're signed in to iMessage
3. Messages.app must be running in the background for sending to work

### Can read but can't send

**Problem**: Read permissions work but sending fails

**Solution**:
1. Check Automation permissions (Step 2 above)
2. Make sure Messages.app is signed in to iMessage
3. Try sending a test message manually in Messages.app first

### "Database locked" error

**Problem**: Sometimes get database lock errors

**Solution**:
- This is usually temporary - Messages.app locks the DB while writing
- The imsg tool will retry automatically
- If it persists, try closing Messages.app temporarily

### Wrong terminal app showing in permissions

**Problem**: Granted permission to Terminal but running from iTerm

**Solution**:
- You need to grant permission to the ACTUAL app you're using
- Check which terminal is running: `ps -p $$ -o comm=`
- Grant permission to that specific app

## Quick Reference

### Check which shell/terminal you're using
```bash
echo "Shell: $SHELL"
echo "Terminal: $(ps -p $(ps -p $$ -o ppid=) -o comm=)"
```

### Check if Messages database is accessible
```bash
ls -la ~/Library/Messages/chat.db
```

### Test read permission
```bash
imsg chats --limit 1 --json
```

### Test send capability
```bash
# Send to yourself for testing
imsg send --to "your-phone-number-or-email" --text "Test from imsg"
```

## Security Notes

- Full Disk Access is powerful - it allows reading ANY file on your system
- Only grant to apps you trust
- Terminal/iTerm are generally safe choices
- You can revoke at any time in System Settings

## Next Steps

Once permissions are granted and verified:
1. ✅ Run the test script to confirm
2. ✅ Test sending a message to yourself
3. ✅ Test the RPC mode
4. → Build the iMessage adapter integration
