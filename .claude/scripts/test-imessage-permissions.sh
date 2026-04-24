#!/bin/bash
# Test iMessage Permissions
# This script helps verify that imsg has the necessary permissions to work

set -e

echo "🔍 Testing iMessage Integration Permissions"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if imsg is installed
echo "1. Checking if imsg is installed..."
if ! command -v imsg &> /dev/null; then
    echo -e "${RED}✗ imsg not found${NC}"
    echo "  Install with: brew install steipete/tap/imsg"
    exit 1
else
    IMSG_VERSION=$(imsg --version 2>&1 | head -1 || echo "unknown")
    echo -e "${GREEN}✓ imsg is installed${NC} ($IMSG_VERSION)"
fi
echo ""

# Check database path
echo "2. Checking Messages database..."
DB_PATH="$HOME/Library/Messages/chat.db"
if [ -f "$DB_PATH" ]; then
    echo -e "${GREEN}✓ Messages database exists${NC}"
    echo "  Location: $DB_PATH"
else
    echo -e "${RED}✗ Messages database not found${NC}"
    echo "  Expected: $DB_PATH"
    echo "  Make sure Messages.app has been opened and iMessage is signed in"
    exit 1
fi
echo ""

# Test database read permission
echo "3. Testing Full Disk Access permission..."
if imsg chats --limit 1 --json &> /dev/null; then
    echo -e "${GREEN}✓ Full Disk Access granted${NC}"
    CHAT_COUNT=$(imsg chats --json 2>/dev/null | jq 'length' || echo "?")
    echo "  Found $CHAT_COUNT conversation(s)"
else
    echo -e "${RED}✗ Full Disk Access NOT granted${NC}"
    echo ""
    echo "  To fix:"
    echo "  1. Open System Settings"
    echo "  2. Go to Privacy & Security > Full Disk Access"
    echo "  3. Click the '+' button"
    echo "  4. Add: $(which bash | sed 's|/bash||') (your terminal)"
    echo "  5. OR add the specific app you're running this from"
    echo ""
    echo "  You may need to restart your terminal after granting permission"
    exit 1
fi
echo ""

# Test sending (requires Automation permission)
echo "4. Testing Automation permission..."
echo "  (This tests if we can send messages via AppleScript)"
echo ""

# Try to get help for send command (this won't actually send, just checks if the command works)
if imsg send --help &> /dev/null; then
    echo -e "${GREEN}✓ Send command available${NC}"
else
    echo -e "${YELLOW}⚠ Send command may require Automation permission${NC}"
fi

# Test if we can check recent messages
echo ""
echo "5. Testing message history retrieval..."
# Get first chat ID
FIRST_CHAT=$(imsg chats --limit 1 --json 2>/dev/null | jq -r '.[0].chatId // empty' || echo "")

if [ -n "$FIRST_CHAT" ]; then
    echo "  Testing with chat: $FIRST_CHAT"
    if imsg history --chat-id "$FIRST_CHAT" --limit 1 --json &> /dev/null; then
        echo -e "${GREEN}✓ Can read message history${NC}"
        MSG_COUNT=$(imsg history --chat-id "$FIRST_CHAT" --json 2>/dev/null | jq 'length' || echo "?")
        echo "  Found $MSG_COUNT message(s) in most recent chat"
    else
        echo -e "${RED}✗ Cannot read message history${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No chats found to test history${NC}"
fi
echo ""

# Test RPC mode
echo "6. Testing RPC mode..."
echo "  (This is what the agent will use)"
echo ""

# Start RPC in background and send a test request
echo '{"jsonrpc":"2.0","id":1,"method":"chats.list","params":{"limit":1}}' | timeout 5 imsg rpc --json 2>&1 | head -20 | while IFS= read -r line; do
    if echo "$line" | jq . &> /dev/null; then
        # It's valid JSON
        if echo "$line" | jq -e '.result' &> /dev/null; then
            echo -e "${GREEN}✓ RPC mode working${NC}"
            echo "  Response: $(echo "$line" | jq -c '.')"
        elif echo "$line" | jq -e '.error' &> /dev/null; then
            echo -e "${RED}✗ RPC returned error${NC}"
            echo "  Error: $(echo "$line" | jq -c '.error')"
        fi
    fi
done || {
    echo -e "${YELLOW}⚠ RPC test timed out or failed${NC}"
    echo "  This might be okay - RPC mode may need different testing"
}
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary:"
echo ""
echo "If all checks passed (green ✓), imsg is ready to use!"
echo ""
echo "To grant Automation permission for sending:"
echo "  1. Try sending a test message (you'll be prompted)"
echo "  2. Or go to: System Settings > Privacy & Security > Automation"
echo "  3. Allow your terminal to control Messages.app"
echo ""
echo "Next step: Build the iMessage adapter integration"
