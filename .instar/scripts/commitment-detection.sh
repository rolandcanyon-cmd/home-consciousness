#!/bin/bash
set -e

# Job: commitment-detection
# Scans iMessage chats for commitments, promises, and action items
# Updates evolution/actions system with detected commitments

AUTH=$(python3 -c "import json; print(json.load(open('.instar/config.json')).get('authToken',''))" 2>/dev/null || echo "")
[ -z "$AUTH" ] && exit 1

PORT=4040
BOOKMARK_FILE=".instar/state/commitment-detection-bookmark.json"

python3 << 'PYTHON_END'
import json, sys, re, subprocess
from datetime import datetime

# Read bookmark
bookmark = {"lastCheck": datetime.utcnow().isoformat() + "Z", "processed": []}
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

# Fetch all iMessage chats
chats_resp = subprocess.run(
    ["curl", "-s", "-H", f"Authorization: Bearer {auth}",
     "http://localhost:4040/imessage/chats"],
    capture_output=True, text=True, timeout=5
)
try:
    chats = json.loads(chats_resp.stdout)
except:
    chats = []

commitments = []

# Scan each chat for commitments
for chat in chats:
    chat_id = chat.get("chatId")
    if not chat_id:
        continue

    # Fetch chat history (last 100 messages)
    hist_resp = subprocess.run(
        ["curl", "-s", "-H", f"Authorization: Bearer {auth}",
         f"http://localhost:4040/imessage/chats/{chat_id}/history?limit=100"],
        capture_output=True, text=True, timeout=5
    )
    try:
        messages = json.loads(hist_resp.stdout)
    except:
        messages = []

    for msg in messages:
        msg_id = msg.get("id", str(msg.get("timestamp", "")))
        if msg_id in bookmark["processed"]:
            continue

        text = msg.get("text", "").strip()
        timestamp = msg.get("timestamp", "")

        if not text or len(text) < 5:
            continue

        # Detect commitment keywords
        commitment_keywords = [
            'i will', "i'll", 'let me', "i've committed",
            'action item', 'todo', '@todo', 'deadline',
            'promised', 'commit to', 'will build', 'will implement',
            'will fix', 'need to', 'should', 'must'
        ]

        text_lower = text.lower()
        if any(kw in text_lower for kw in commitment_keywords):
            # Extract due date
            due_date = None
            date_match = re.search(r'\d{4}-\d{2}-\d{2}', text)
            if date_match:
                due_date = date_match.group(0)

            title = text[:180].replace('\n', ' ').strip()
            commitments.append({
                "msgId": msg_id,
                "title": title,
                "dueDate": due_date,
                "timestamp": timestamp,
                "chatId": chat_id
            })

            bookmark["processed"].add(msg_id)

# Register commitments
registered = 0
for comm in commitments:
    payload = {
        "title": comm["title"],
        "source": "commitment-detection",
        "description": f"From iMessage chat: {comm['chatId']}",
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

# Save bookmark
bookmark["processed"] = list(bookmark["processed"])
bookmark["lastCheck"] = datetime.utcnow().isoformat() + "Z"
bookmark["registered"] = registered

with open(".instar/state/commitment-detection-bookmark.json", "w") as f:
    json.dump(bookmark, f, indent=2)

if registered > 0:
    print(f"[ATTENTION] Detected and registered {registered} commitment(s)")

PYTHON_END

exit 0
