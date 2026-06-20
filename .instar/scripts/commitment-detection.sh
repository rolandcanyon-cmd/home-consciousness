#!/bin/bash
set -e

# Job: commitment-detection
# Scans iMessage chats for commitments, promises, and action items
# Reads from local iMessage database (~/.instar/imessage/chat.db)

AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null || echo "")
[ -z "$AUTH" ] && exit 1

PORT=4040
BOOKMARK_FILE=".instar/state/commitment-detection-bookmark.json"
IMESSAGE_DB=".instar/imessage/chat.db"

[ ! -f "$IMESSAGE_DB" ] && exit 0

python3 << 'PYTHON_END'
import json, sys, re, subprocess, sqlite3
from datetime import datetime, timedelta
import os

# Read bookmark
bookmark = {
    "lastProcessedDate": 0,
    "processed": [],
    "lastCheck": datetime.utcnow().isoformat() + "Z"
}
try:
    with open(".instar/state/commitment-detection-bookmark.json") as f:
        data = json.load(f)
        bookmark = data
        bookmark["processed"] = set(bookmark.get("processed", []))
except:
    bookmark["processed"] = set()

# Get auth token
try:
    with open(".instar/config.json") as f:
        auth = json.load(f).get("authToken", "")
except:
    auth = ""

if not auth:
    sys.exit(1)

# Get last processed date (as Unix timestamp in seconds)
last_processed_sec = bookmark.get("lastProcessedDate", 0)

# iMessage uses timestamps in nanoseconds since 2001-01-01
# Convert to nanoseconds (where 2001-01-01 00:00:00 UTC = 978307200 seconds after Unix epoch)
last_processed_nano = int((last_processed_sec - 978307200) * 1_000_000_000) if last_processed_sec else 0

def extract_text_from_attributed_body(blob):
    """Extract readable text from NSAttributedString BLOB"""
    if not blob:
        return None

    # The attributedBody is an NSAttributedString binary format
    # We can extract ASCII/UTF-8 strings from it by looking for printable text
    try:
        # Try UTF-8 decode first
        text = blob.decode('utf-8', errors='ignore')
        # Remove the NSAttributedString formatting markers
        # Look for the actual string content
        # Apple's format often has "NSString" followed by the actual text
        match = re.search(r'NSString[^\x00]*?(\x00)(.{0,500}?)(?:\x00|$)', text, re.DOTALL)
        if match:
            extracted = match.group(2).strip()
            if extracted:
                return extracted

        # If no structured match, just take printable characters
        clean = ''.join(c for c in text if c.isprintable() or c in '\n\t ')
        clean = re.sub(r'NS[A-Z]\w+', '', clean)  # Remove class names
        clean = re.sub(r'\x00+', '', clean)  # Remove null bytes
        clean = clean.strip()

        if clean and len(clean) > 5:
            return clean
    except:
        pass

    return None

commitments = []

try:
    # Open iMessage database in read-only mode
    conn = sqlite3.connect("file:.instar/imessage/chat.db?mode=ro", uri=True, timeout=2)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Find the most active chat (the one with most messages from me = likely Adrian)
    cursor.execute("""
        SELECT c.ROWID, c.chat_identifier
        FROM chat c
        JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
        JOIN message m ON cmj.message_id = m.ROWID
        WHERE m.is_from_me = 1
        GROUP BY c.ROWID
        ORDER BY MAX(m.date) DESC
        LIMIT 1
    """)

    chat_row = cursor.fetchone()

    if not chat_row:
        conn.close()
        sys.exit(0)

    chat_id = chat_row[0]

    # Get messages from this chat that I sent, newer than bookmark
    cursor.execute("""
        SELECT message.ROWID, message.date, message.text, message.attributedBody
        FROM message
        JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
        WHERE chat_message_join.chat_id = ?
          AND message.is_from_me = 1
          AND message.date > ?
        ORDER BY message.date DESC
        LIMIT 200
    """, (chat_id, last_processed_nano))

    messages = cursor.fetchall()

    # Commitment keyword patterns
    commitment_patterns = [
        (r"i['ll|'ve|will|am].*(?:build|implement|fix|set up|install|configured|done|create|write|wrote|wrote)", re.IGNORECASE),
        (r"(?:todo|action item|note to self|need to|should).*(?:build|implement|fix|set up|install|create|write)", re.IGNORECASE),
        (r"(?:will|gonna|going to).*(?:push|merge|ship|deploy|release)", re.IGNORECASE),
        (r"let me (?:build|implement|fix|create|write|test|check)", re.IGNORECASE),
        (r"(?:committed|promise|pledge).*(?:to|that)", re.IGNORECASE),
        (r"(?:built|installed|configured|finished|completed).*(?:today|now|already)", re.IGNORECASE),
    ]

    for msg_row in messages:
        msg_id = str(msg_row[0])
        timestamp_nano = msg_row[1]
        text_field = msg_row[2]
        attributed_body = msg_row[3]

        if msg_id in bookmark["processed"]:
            continue

        # Extract text from either field
        text = text_field or extract_text_from_attributed_body(attributed_body)

        if not text or len(text.strip()) < 10:
            continue

        # Convert timestamp from nanoseconds to Unix timestamp
        timestamp_sec = (timestamp_nano / 1_000_000_000) + 978307200

        # Check for commitment patterns
        found_commitment = False
        for pattern, flags in commitment_patterns:
            if re.search(pattern, text):
                found_commitment = True
                break

        if found_commitment:
            # Extract due date if present
            due_date = None
            date_match = re.search(r'(\d{4}-\d{2}-\d{2})', text)
            if date_match:
                due_date = date_match.group(1)

            title = text[:200].replace('\n', ' ').strip()
            commitments.append({
                "msgId": msg_id,
                "title": title,
                "dueDate": due_date,
                "timestamp": datetime.utcfromtimestamp(timestamp_sec).isoformat() + "Z",
                "timestamp_sec": timestamp_sec,
                "chatId": chat_id
            })

            bookmark["processed"].add(msg_id)

    conn.close()

except sqlite3.DatabaseError as e:
    # Database locked or other error
    sys.exit(0)
except Exception as e:
    # Other errors
    sys.exit(0)

# Register commitments via evolution/actions API
registered = 0
for comm in commitments:
    payload = {
        "title": comm["title"],
        "source": "commitment-detection",
        "description": f"From iMessage ({comm['timestamp']})",
        "dueDate": comm["dueDate"]
    }

    try:
        reg_resp = subprocess.run(
            ["curl", "-s", "-X", "POST", f"http://localhost:4040/evolution/actions",
             "-H", f"Authorization: Bearer {auth}",
             "-H", "Content-Type: application/json",
             "-d", json.dumps(payload)],
            capture_output=True, text=True, timeout=5
        )

        if reg_resp.returncode == 0:
            try:
                result = json.loads(reg_resp.stdout)
                if "id" in result:
                    registered += 1
            except:
                pass
    except:
        pass

# Update bookmark
if commitments:
    latest = max(c["timestamp_sec"] for c in commitments)
    bookmark["lastProcessedDate"] = int(latest)

bookmark["processed"] = list(bookmark["processed"])
bookmark["lastCheck"] = datetime.utcnow().isoformat() + "Z"
bookmark["registered"] = registered
bookmark["status"] = "complete"
bookmark["messageSourcesScanned"] = ["iMessage"]

with open(".instar/state/commitment-detection-bookmark.json", "w") as f:
    json.dump(bookmark, f, indent=2)

if registered > 0:
    print(f"[ATTENTION] Detected and registered {registered} commitment(s)")

PYTHON_END

exit 0
