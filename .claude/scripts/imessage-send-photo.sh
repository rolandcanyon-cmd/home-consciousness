#!/bin/bash
# imessage-send-photo.sh — Send an image via iMessage using AppleScript.
#
# Usage:
#   ./imessage-send-photo.sh RECIPIENT /path/to/image.jpeg
#   ./imessage-send-photo.sh RECIPIENT /path/to/image.jpeg "Optional caption text"
#
# Compresses the image first (via image_compress.py), then sends via AppleScript.
# imsg --file fails due to Full Disk Access restrictions; AppleScript works fine.

RECIPIENT="$1"
IMAGE_PATH="$2"
CAPTION="$3"

if [ -z "$RECIPIENT" ] || [ -z "$IMAGE_PATH" ]; then
  echo "Usage: imessage-send-photo.sh RECIPIENT /path/to/image [caption]" >&2
  exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
  echo "Image not found: $IMAGE_PATH" >&2
  exit 1
fi

# Get script directory for finding image_compress.py
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Compress the image to ~/Pictures (Messages can read from here; /tmp is blocked by macOS privacy)
TMPFILE="$HOME/Pictures/imsg-photo-$(date +%s).jpeg"
if python3 "${SCRIPT_DIR}/image_compress.py" "$IMAGE_PATH" "$TMPFILE" 2>/dev/null; then
  SEND_PATH="$TMPFILE"
else
  echo "Compression failed, sending original" >&2
  cp "$IMAGE_PATH" "$TMPFILE"
  SEND_PATH="$TMPFILE"
fi

# Send via AppleScript targeting iMessage service specifically
# - Do NOT use /tmp or project dir — macOS blocks Messages from reading those
# - ~/Pictures works reliably
osascript << APPLESCRIPT 2>&1
tell application "Messages"
    set imService to first service whose service type is iMessage
    set theBuddy to buddy "$RECIPIENT" of imService
    send POSIX file "$SEND_PATH" to theBuddy
end tell
APPLESCRIPT
PHOTO_STATUS=$?

rm -f "$TMPFILE"

if [ $PHOTO_STATUS -ne 0 ]; then
  echo "Failed to send photo via AppleScript" >&2
  exit 1
fi

echo "Photo sent to $RECIPIENT"

# If there's a caption, send it as a text follow-up
if [ -n "$CAPTION" ]; then
  sleep 1
  "$SCRIPT_DIR/imessage-reply.sh" "$RECIPIENT" "$CAPTION"
fi
