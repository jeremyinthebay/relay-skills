#!/bin/zsh
# status.sh — one-shot project status for the Slack heartbeat.
# Prints a ready-to-post Slack message. All logic lives here (a file), not in the
# scheduled task's prompt, so it can be tuned without a human approving a task edit.
# See Rule 12 in the Notion page.

REPO="$HOME/Projects/my-project"
RELAY="$HOME/Projects/relay"
LOG="$RELAY/relay.log"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$REPO" 2>/dev/null || { echo "🔴 Relay: repo missing at $REPO"; exit 0; }

# zsh aborts the script on an unmatched glob. An empty queue is NORMAL, not an error —
# without this, status.sh dies on its own success case.
setopt local_options null_glob

# ---------- what is it doing right now? ----------
STATE="idle"; ELAPSED=""; PID=""
if [ -f "$RELAY/.lock" ]; then
  # The lock is now "PID TIMESTAMP claude-relay" — cat'ing the whole line and passing it to
  # kill -0 silently fails, so a live build read as idle and the status said WEDGED.
  # A status script that misreports the thing it exists to report is worse than none.
  PID=$(cut -d' ' -f1 "$RELAY/.lock" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    STATE="building"
    CPID=$(pgrep -f "claude -p check next" | head -1)
    [ -n "$CPID" ] && ELAPSED=$(ps -o etime= -p "$CPID" 2>/dev/null | tr -d ' ')
  fi
fi

BRIEF=$(grep -i '^Brief:' NEXT-STEPS.md 2>/dev/null | head -1 | sed 's/^Brief: *//')
BSTATUS=$(grep -i '^Status:' NEXT-STEPS.md 2>/dev/null | head -1 | sed 's/^Status: *//')
BRANCH=$(git branch --show-current 2>/dev/null)
# `.[0] | ...` on an empty array yields the literal string "#null null" — guard with select().
OPENPR=$(gh pr list --state open --limit 1 --json number,title -q '.[] | "#\(.number) \(.title)"' 2>/dev/null | head -1)

# If a PR is open and nothing is building, the reviewer owns it next.
if [ "$STATE" = "idle" ] && [ -n "$OPENPR" ]; then STATE="awaiting review"; fi

# ---------- ETA, from how long past briefs actually took ----------
# Pair each "OPEN brief detected" with the following "run complete" in the log.
AVG=$(awk '
  /OPEN brief detected/ { split($2,t,":"); start=t[1]*3600+t[2]*60+t[3]; open=1 }
  /run complete/ && open { split($2,t,":"); end=t[1]*3600+t[2]*60+t[3];
                           d=end-start; if(d<0) d+=86400;
                           if(d>60 && d<14400){ sum+=d; n++ } open=0 }
  END { if(n>0) printf "%d", sum/n/60 }' "$LOG" 2>/dev/null)
[ -z "$AVG" ] && AVG=25   # no history yet — brief #1 took ~23m

ETA=""
if [ "$STATE" = "building" ] && [ -n "$ELAPSED" ]; then
  MINS=$(echo "$ELAPSED" | awk -F: '{ if (NF==3) print $1*60+$2; else print $1 }')
  REM=$(( AVG - MINS ))
  if [ "$REM" -gt 0 ]; then ETA="~${REM}m left (avg brief: ${AVG}m)"
  else ETA="running long — ${MINS}m vs ${AVG}m avg"; fi
fi

# ---------- what's done, what's left ----------
MERGED=$(git log --oneline origin/main 2>/dev/null | grep -c "(#1[5-9]\|(#2[0-9]")

# Use an ARRAY, not `ls glob | wc -l`. With null_glob an empty pattern DISAPPEARS, so `ls`
# runs with no arguments and lists the current directory — reporting "8 briefs queued" when
# the queue is empty. Confidently wrong is the worst kind of status.
QFILES=("$RELAY"/queue/*.md)
QUEUE=${#QFILES[@]}
NEXTUP=""
[ "$QUEUE" -gt 0 ] && NEXTUP=$(grep -i '^Brief:' "${QFILES[1]}" 2>/dev/null | head -1 | sed 's/^Brief: *//')

# ---------- health ----------
CODE=$(curl -s -m 15 -o /dev/null -w "%{http_code}" https://example.com/ 2>/dev/null)
if [ "$CODE" = "200" ]; then HEALTH="🟢 prod 200"; else HEALTH="🔴 prod $CODE"; fi
[ -f "$RELAY/.halt" ] && HEALTH="$HEALTH · ⛔ HALTED"

# ---------- emit ----------
# WEDGED DETECTION — the audit's sharpest catch.
# The old version computed BSTATUS and never printed it, so "brief OPEN, watcher dead,
# nothing running" — the exact signature of a wedged loop — rendered as "✅ Idle. 🟢 healthy."
# A status script that cannot report its own death is decoration.
WEDGED=no
[ "$STATE" = "idle" ] && echo "$BSTATUS" | grep -qi OPEN && WEDGED=yes

# Is the watcher alive? Use the BEACON (.alive, touched every poll), not log activity.
#
# The old check asked "has relay.log changed in 5 minutes?" — but during a long build the
# watcher correctly exits early without logging, so a healthy 40-minute build looked exactly
# like a dead watcher. It shouted "WATCHER IS NOT RUNNING — the loop is dead" and then, one
# line later, printed the running build's ETA. A status view that contradicts itself in
# consecutive lines is worse than no status view.
#
# Rule: a liveness signal must be emitted by the liveness itself, never inferred from side
# effects that fall silent exactly when the system is busiest.
WATCHER_DEAD=no
if [ -f "$RELAY/.alive" ]; then
  BEAT=$(( ( $(date +%s) - $(stat -f %m "$RELAY/.alive") ) / 60 ))
  [ "$BEAT" -gt 3 ] && WATCHER_DEAD=yes      # polls every 60s; 3 min of silence is real
else
  WATCHER_DEAD=yes                            # never beat = never ran
fi
launchctl list 2>/dev/null | grep -q pointsrelay || WATCHER_DEAD=yes
[ -f "$RELAY/.stop" ] && WATCHER_DEAD=stopped

# A live build is proof of life. If the executor is running, the watcher started it —
# so it cannot be dead, whatever any other signal claims. Never contradict yourself.
[ "$STATE" = "building" ] && [ "$WATCHER_DEAD" = "yes" ] && WATCHER_DEAD=no

case "$STATE" in
  building)          ICON="🔨"; LINE="*Building* — $BRIEF" ;;
  "awaiting review") ICON="🔍"; LINE="*Awaiting review* — PR $OPENPR" ;;
  idle)              ICON="✅"; LINE="*Idle* — nothing in flight" ;;
esac

# These override everything. Bad news must never render as good news.
if [ "$WEDGED" = "yes" ]; then
  ICON="🔴"; LINE="*WEDGED* — a brief is OPEN but nothing is running: $BRIEF"
fi
if [ "$WATCHER_DEAD" = "stopped" ]; then
  ICON="⛔"; LINE="*STOPPED* — manual kill switch (.stop) is set. Nothing will run."
elif [ "$WATCHER_DEAD" = "yes" ]; then
  ICON="🔴"; LINE="*WATCHER IS NOT RUNNING* — the loop is dead, not idle."
fi
[ -f "$RELAY/.halt" ] && { ICON="⛔"; LINE="*HALTED* — watchdog stopped the loop. Check alerts."; }

echo "$ICON $LINE"
echo ""
[ "$STATE" = "building" ] && echo "• Running: ${ELAPSED:-?} on \`$BRANCH\`   ${ETA:+· $ETA}"
[ "$STATE" = "awaiting review" ] && echo "• Reviewer picks it up within 6 min, merges on pass"
[ -n "$OPENPR" ] && [ "$STATE" = "building" ] && echo "• Open PR: $OPENPR"
echo "• Merged so far: $MERGED PRs on main"
if [ "$QUEUE" -gt 0 ]; then
  echo "• Queue: $QUEUE waiting${NEXTUP:+ · next: $NEXTUP}"
else
  echo "• Queue: empty"
fi
if [ "$STATE" = "idle" ] && [ "$QUEUE" -eq 0 ] && [ -z "$OPENPR" ]; then
  echo "• *All briefs done — loop idle.*"
fi
echo "• $HEALTH"
