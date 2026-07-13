#!/bin/zsh
# watch.sh — the executor's poller. Runs every 60s via launchd.
#
# REWRITTEN after an adversarial audit found four critical bugs in the original:
#   1. Promotion recorded success it never verified (git checkout failure was swallowed by
#      2>/dev/null, then it cp'd the brief onto the WRONG BRANCH and logged "on fresh main").
#      That is the same verify-before-record bug that already deadlocked this loop once.
#   2. `gh` failing (auth, network, PATH) returned 0 open PRs, which reads as "PR merged,
#      promote the next brief." The one-PR-in-flight gate FAILED OPEN.
#   3. No retry cap anywhere. A failing brief rebuilds every 60s forever, burning tokens
#      and Netlify builds. Only luck stopped it.
#   4. The kill switch (.halt) was deleted by the watchdog within 60s.
#
# Principles now: verify THEN record. Fail closed. Cap retries. A manual stop is permanent.

REPO="$HOME/Projects/my-project"
RELAY="$HOME/Projects/relay"
LOG="$RELAY/relay.log"
LOCK="$RELAY/.lock"
ATTEMPTS="$RELAY/.attempts"
BUDGET="$RELAY/.builds-today"

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# LIVENESS BEACON. Touched on EVERY poll, before any early exit.
#
# Why: I first used "has relay.log changed recently?" as the liveness signal. But during a
# long build this script holds the lock and exits early WITHOUT logging — which is correct —
# so a healthy 40-minute build looked identical to a dead watcher, and the heartbeat cried
# "WATCHER IS NOT RUNNING" while cheerfully printing the build's ETA on the next line.
#
# A liveness signal must be emitted by the liveness itself, not inferred from side effects
# that go quiet exactly when the system is busiest.
touch "$RELAY/.alive"
alert() { printf '%s\n' "$*" >> "$RELAY/outbox.txt"; "$RELAY/notify.sh"; }

# ---- 0. MANUAL STOP. Permanent. Nothing auto-clears this. -------------------
# `touch ~/Projects/relay/.stop` halts the loop until a human removes it.
# This is separate from .halt (which the watchdog manages and auto-clears).
if [ -f "$RELAY/.stop" ]; then
  exit 0
fi

# Drain any pending alert.
[ -s "$REPO/.outbox.txt" ] || [ -s "$RELAY/outbox.txt" ] && "$RELAY/notify.sh"

# ---- 1. Watchdog: notice trouble and SAY SO. Silence used to look like health.
"$RELAY/watchdog.sh"
[ -f "$RELAY/.halt" ] && exit 0

# ---- 2. Don't stack runs. Validate the lock properly. -----------------------
# PIDs get reused after a reboot. A recycled PID made the old code think a build was
# running forever — and it also made the watchdog think everything was fine.
if [ -e "$LOCK" ]; then
  PID=$(cut -d' ' -f1 "$LOCK" 2>/dev/null)
  LOCKAGE=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && ps -p "$PID" -o comm= 2>/dev/null | grep -q zsh; then
    if [ "$LOCKAGE" -gt 5400 ]; then      # 90 min — no brief should take this long
      log "lock held ${LOCKAGE}s by $PID — STUCK"
      alert "⚠️ Relay: a build has been running $((LOCKAGE/60))m. Probably stuck. Loop is blocked."
      touch "$RELAY/.halt"
    fi
    exit 0
  fi
  log "stale lock (pid $PID not a live shell), clearing"
  rm -f "$LOCK"
fi

cd "$REPO" || { log "ERROR: repo missing"; alert "🔴 Relay: repo missing at $REPO"; exit 1; }

# ---- 3. Queue promotion — VERIFY, THEN RECORD. -----------------------------
if [ ! -f NEXT-STEPS.md ] || grep -qi '^Status: *DONE' NEXT-STEPS.md; then
  # zsh ERRORS on an unmatched glob before `ls` ever runs, and `2>/dev/null` doesn't
  # suppress it — it's a shell error, not a command error. An empty queue is the NORMAL
  # end state, so the poller was throwing an error every 60s on success.
  # Same bug I fixed in status.sh and failed to fix here. Use an array.
  setopt local_options null_glob
  QF=("$RELAY"/queue/*.md)
  NEXTQ="${QF[1]}"
  if [ -n "$NEXTQ" ]; then

    # FAIL CLOSED: distinguish "no open PRs" from "couldn't ask GitHub".
    # An empty answer from a source that wasn't looking is not an answer.
    if ! PRJSON=$(gh pr list --state open --limit 5 --json number 2>&1); then
      log "ERROR: gh failed — NOT promoting. ($PRJSON)"
      alert "⚠️ Relay: can't reach GitHub, so I can't tell if a PR is open. Not promoting the next brief."
      exit 1
    fi
    OPENPRS=$(echo "$PRJSON" | jq 'length' 2>/dev/null || echo "?")
    [ "$OPENPRS" = "?" ] && { log "ERROR: unparseable gh output — NOT promoting"; exit 1; }

    if [ "$OPENPRS" -eq 0 ]; then
      # The brief file is disposable — discard local edits so checkout can't fail on it.
      git checkout -- NEXT-STEPS.md 2>/dev/null

      if ! git checkout main 2>>"$LOG" || ! git pull --ff-only 2>>"$LOG"; then
        log "ERROR: cannot reach a clean main — promotion ABORTED, queue untouched"
        alert "⚠️ Relay: couldn't get to a clean main. Next brief NOT promoted. Tree may be dirty."
        exit 1
      fi
      # Prove it, don't assume it.
      if [ "$(git branch --show-current)" != "main" ]; then
        log "ERROR: not on main after checkout — ABORTED"
        exit 1
      fi

      cp "$NEXTQ" NEXT-STEPS.md && mv "$NEXTQ" "$NEXTQ.promoted"
      log "promoted $(basename "$NEXTQ") -> NEXT-STEPS.md (verified on main @ $(git rev-parse --short HEAD))"
    fi
  fi
fi

[ -f NEXT-STEPS.md ] || exit 0
grep -qi '^Status: *OPEN' NEXT-STEPS.md || exit 0

# ---- 4. RETRY CAP. A failing brief must not rebuild forever. ---------------
mkdir -p "$ATTEMPTS"
BKEY=$(shasum NEXT-STEPS.md | cut -c1-10)
N=$(cat "$ATTEMPTS/$BKEY" 2>/dev/null || echo 0)
if [ "$N" -ge 3 ]; then
  log "brief $BKEY has failed $N times — HALTING"
  alert "⛔ Relay HALTED: the current brief failed 3 times. Not retrying. Needs you."
  touch "$RELAY/.halt"
  exit 0
fi

# ---- 5. DAILY BUILD BUDGET. A quota is not a safety mechanism you discover by hitting it.
TODAY=$(date '+%Y-%m-%d')
read -r BDAY BCOUNT < "$BUDGET" 2>/dev/null || { BDAY=""; BCOUNT=0; }
[ "$BDAY" != "$TODAY" ] && { BDAY="$TODAY"; BCOUNT=0; }
if [ "$BCOUNT" -ge 20 ]; then
  log "daily build budget reached ($BCOUNT) — HALTING"
  alert "⛔ Relay HALTED: 20 builds today. That's the budget. (Netlify paused us once already.)"
  touch "$RELAY/.halt"
  exit 0
fi
echo "$BDAY $((BCOUNT+1))" > "$BUDGET"
echo $((N+1)) > "$ATTEMPTS/$BKEY"

# ---- 6. Run the executor. --------------------------------------------------
"$RELAY/backup.sh" >/dev/null 2>&1
BRIEF=$(grep -i '^Brief:' NEXT-STEPS.md | head -1)
echo "$$ $(date +%s) claude-relay" > "$LOCK"
log "OPEN brief (attempt $((N+1))/3) — $BRIEF — invoking Claude Code"

claude -p "check next" --dangerously-skip-permissions >> "$LOG" 2>&1
RC=$?
log "Claude Code exited rc=$RC"

if grep -qi '^Status: *DONE' NEXT-STEPS.md; then
  log "brief marked DONE"
  rm -f "$ATTEMPTS/$BKEY"          # success — reset the counter
else
  # This branch used to do NOTHING. The poller would relaunch the identical build 60s later.
  log "WARNING: brief still OPEN after run (attempt $((N+1))/3)"
  if [ $((N+1)) -ge 3 ]; then
    alert "⛔ Relay: brief failed 3 times, halting. Check COWORK-STATUS.md."
    touch "$RELAY/.halt"
  else
    alert "⚠️ Relay: brief didn't complete (attempt $((N+1))/3). Will retry."
  fi
fi

rm -f "$LOCK"
log "--- run complete ---"
