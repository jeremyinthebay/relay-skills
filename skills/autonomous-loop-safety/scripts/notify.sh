#!/bin/zsh
# Sends anything in the outbox to the owner via iMessage, then clears it.
# The outbox lives INSIDE the repo folder because scheduled Claude sessions can mount
# the repo but not ~/Projects/relay. osascript always works; the iMessage MCP doesn't.

REPO="$HOME/Projects/my-project"
RELAY="$HOME/Projects/relay"
LOG="$RELAY/relay.log"
TO="+15550000000"

for OUTBOX in "$REPO/.outbox.txt" "$RELAY/outbox.txt"; do
  [ -s "$OUTBOX" ] || continue

  BODY=$(cat "$OUTBOX")
  : > "$OUTBOX"   # clear first, so a send failure can't loop

  /usr/bin/osascript <<EOF
tell application "Messages"
  set targetService to 1st account whose service type = iMessage
  set targetBuddy to participant "$TO" of targetService
  send "$(echo "$BODY" | sed 's/\\/\\\\/g; s/"/\\"/g')" to targetBuddy
end tell
EOF

  if [ $? -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] iMessage sent (from $(basename $OUTBOX))" >> "$LOG"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] iMessage FAILED; body: $BODY" >> "$LOG"
  fi
done
