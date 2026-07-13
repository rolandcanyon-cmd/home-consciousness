#!/usr/bin/env python3
"""
Commitment detection job: scans recent messages for promises and action items,
registers them via the evolution/actions API, updates bookmark.

Runs silently unless something needs attention.
"""

import json
import sqlite3
import re
import os
import sys
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

# Config
CONFIG_PATH = Path.home() / '.instar/agents/Roland/.instar/config.json'
IMESSAGE_DB = Path.home() / '.instar/agents/Roland/.instar/imessage/chat.db'
BOOKMARK_PATH = Path.home() / '.instar/agents/Roland/state/commitment-detection-bookmark.json'
STATE_DIR = BOOKMARK_PATH.parent
API_BASE = 'http://localhost:4040'

# Commitment patterns (look for these phrases)
COMMITMENT_PATTERNS = [
    r"i\s+(?:will|\'ll|need\s+to)\s+([^.!?\n]+)",
    r"let\s+me\s+([^.!?\n]+)",
    r"i\s+(?:should|must|can)\s+([^.!?\n]+)",
    r"we\s+(?:should|need\s+to)\s+([^.!?\n]+)",
    r"i\s+(?:built|built|built|created|wrote|implemented)\s+([^.!?\n]+)",
    r"(?:TODO|FIXME|ACTION|todo|fixme)\s*:?\s*([^.!?\n]+)",
    r"(?:on\s+it|working\s+on|implementing|building|adding|fixing)\s+([^.!?\n]+)",
    r"(?:need\s+to|gotta|got\s+to)\s+([^.!?\n]+)",
]

def read_bookmark():
    """Read the last processed message ID."""
    if not BOOKMARK_PATH.exists():
        return 0
    try:
        with open(BOOKMARK_PATH) as f:
            return json.load(f).get('lastProcessedId', 0)
    except:
        return 0

def update_bookmark(msg_id):
    """Update the bookmark with the latest processed message ID."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(BOOKMARK_PATH, 'w') as f:
        json.dump({'lastProcessedId': msg_id, 'updatedAt': datetime.now().isoformat()}, f)

def get_auth_token():
    """Get the Instar auth token from config."""
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f).get('authToken', '')
    except:
        return ''

def query_imessage_messages(since_id: int, limit: int = 100):
    """Query recent messages from iMessage database since bookmark."""
    if not IMESSAGE_DB.exists():
        return []

    try:
        conn = sqlite3.connect(IMESSAGE_DB)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        # Query messages newer than bookmark, sorted by date
        # The imessage DB has messages table with ROWID and text/timestamp
        cursor.execute("""
            SELECT ROWID, text, datetime(date/1000000000 + 978307200, 'unixepoch') as msg_date
            FROM message
            WHERE ROWID > ? AND text IS NOT NULL AND text != ''
            ORDER BY ROWID DESC
            LIMIT ?
        """, (since_id, limit))

        messages = []
        for row in cursor.fetchall():
            messages.append({
                'id': row[0],
                'text': row[1],
                'date': row[2]
            })

        conn.close()
        # Reverse to process chronologically
        return list(reversed(messages))
    except Exception as e:
        print(f"[ATTENTION] Failed to query iMessage database: {e}", file=sys.stderr)
        return []

def detect_commitments(text: str) -> list:
    """Detect commitment patterns in text. Returns list of extracted commitments."""
    if not text or len(text) < 10:
        return []

    commitments = []
    text_lower = text.lower()

    for pattern in COMMITMENT_PATTERNS:
        matches = re.finditer(pattern, text_lower, re.IGNORECASE)
        for match in matches:
            # Extract the commitment part
            commitment = match.group(1).strip() if match.groups() else match.group(0).strip()
            if commitment and len(commitment) > 5:
                commitments.append(commitment)

    return commitments

def register_commitment(title: str, description: str, auth_token: str):
    """Register a commitment via the evolution/actions API."""
    if not auth_token:
        return None

    payload = {
        'title': title[:100],  # Truncate title
        'description': description[:500],
        'source': 'commitment-detection',
        'priority': 'medium',
        'status': 'pending'
    }

    try:
        result = subprocess.run([
            'curl', '-s', '-X', 'POST',
            f'{API_BASE}/evolution/actions',
            '-H', f'Authorization: Bearer {auth_token}',
            '-H', 'Content-Type: application/json',
            '-d', json.dumps(payload)
        ], capture_output=True, text=True, timeout=5)

        if result.returncode == 0:
            try:
                response = json.loads(result.stdout)
                return response.get('id')
            except:
                return None
        return None
    except Exception as e:
        print(f"[ATTENTION] Failed to register commitment: {e}", file=sys.stderr)
        return None

def main():
    """Main job function."""
    # Read bookmark
    last_id = read_bookmark()

    # Get auth token
    auth_token = get_auth_token()
    if not auth_token:
        print("[ATTENTION] No auth token found", file=sys.stderr)
        return 1

    # Query recent messages
    messages = query_imessage_messages(last_id)

    if not messages:
        # Silent exit if no new messages
        return 0

    # Scan for commitments
    registered_count = 0
    max_id = last_id

    for msg in messages:
        msg_id = msg['id']
        text = msg['text']
        max_id = max(max_id, msg_id)

        # Detect commitments in this message
        commitments = detect_commitments(text)

        for commitment in commitments:
            # Avoid duplicates: short heuristic check
            title = commitment[:80].strip() + ('...' if len(commitment) > 80 else '')

            # Register the commitment
            result = register_commitment(
                title=title,
                description=f"Detected from iMessage: {text[:200]}",
                auth_token=auth_token
            )

            if result:
                registered_count += 1

    # Update bookmark
    if max_id > last_id:
        update_bookmark(max_id)

    # Only signal if we found and registered new commitments
    if registered_count > 0:
        print(f"[ATTENTION] Detected and registered {registered_count} new commitment(s)")

    return 0

if __name__ == '__main__':
    sys.exit(main())
