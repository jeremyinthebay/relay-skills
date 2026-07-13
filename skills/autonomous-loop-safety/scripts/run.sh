#!/bin/zsh
# run.sh — the ONLY thing launchd executes. It never changes.
#
# WHY THIS EXISTS — a real incident:
#
# A running shell reads its script INCREMENTALLY, by byte offset. Edit that file mid-run and
# the shell resumes at a stale offset in the NEW bytes — landing mid-line, mid-comment,
# anywhere. It then tries to execute whatever garbage it finds.
#
# That happened: `watch.sh` was edited while launchd had it open, the shell resumed inside a
# comment, and tried to run the word `structural`. The poller died after invoking the executor,
# so the brief never got marked DONE, retried three times, and opened TWO DUPLICATE PRs before
# the retry cap stopped it.
#
# The fix is not "be careful." Be careful failed — twice today. The fix is structural:
#
#   * launchd runs THIS file, which is tiny and never edited.
#   * It copies the real poller to a private snapshot and runs the SNAPSHOT.
#   * Editing watch.sh mid-run is now harmless: the running copy is a different inode,
#     and the next poll picks up the new version cleanly.
#
# `cp` to a temp path + run the temp path is enough — the executing shell holds an inode that
# nothing else touches.

RELAY="$HOME/Projects/relay"
SNAP="$RELAY/.run"

mkdir -p "$SNAP"

# Refuse to run a script that doesn't parse. A syntax error in watch.sh would otherwise take
# the whole loop down silently — and a loop that is down but looks idle is the failure this
# system exists to prevent.
if ! zsh -n "$RELAY/watch.sh" 2>/dev/null; then
  ERR=$(zsh -n "$RELAY/watch.sh" 2>&1 | head -2)
  printf '[%s] RUNNER: watch.sh does not parse — refusing to run it.\n%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$ERR" >> "$RELAY/relay.log"
  printf '🔴 Relay: watch.sh has a SYNTAX ERROR and will not run.\n%s\n' "$ERR" >> "$RELAY/outbox.txt"
  "$RELAY/notify.sh" 2>/dev/null
  exit 1
fi

# Snapshot, then execute the snapshot. The running copy can never be edited underneath us.
cp "$RELAY/watch.sh" "$SNAP/watch.snapshot.sh"
chmod +x "$SNAP/watch.snapshot.sh"
exec zsh "$SNAP/watch.snapshot.sh"
