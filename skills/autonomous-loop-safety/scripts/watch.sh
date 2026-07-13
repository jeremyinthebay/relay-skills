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

# THE HEADER IS THE ONLY STATUS. Read the FIRST `Status:` line and nothing else.
#
# A brief once contained a Deliverables footer that began "Status: DONE. Do not merge." — 173
# lines below the real header. A plain `grep -q '^Status: *DONE'` matched it, which means the
# poller would have declared the brief COMPLETE the moment it ran, whatever the executor did:
# retry counter reset, failure hidden, next brief promoted over the top of a broken one.
#
# A brief must never be able to declare itself finished from its own body. Only the header,
# only the first occurrence, and only after the executor has written it.
brief_status() {
  grep -i -m1 '^Status:' "$1" 2>/dev/null | sed 's/^[Ss]tatus: *//' | tr '[:lower:]' '[:upper:]' | cut -d' ' -f1
}

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
# DEDUPED alert. The watchdog had throttling; watch.sh did NOT — and watch.sh is the one that
# alerts inside a 60-second poll loop. Any persistent condition (promotion blocked, budget hit,
# brief failing) would have sent ONE iMESSAGE PER MINUTE until noticed. Hit the daily build
# budget at 10am and that is ~1,400 identical texts before midnight.
#
# An alarm that fires 1,400 times is not an alarm, it's a reason to turn your phone off — and
# then you miss the real one. Same message = once per hour, max.
alert() {
  local msg="$*"
  local key=$(printf '%s' "$msg" | shasum | cut -c1-12)
  local stamp="$RELAY/.alerted/$key"
  mkdir -p "$RELAY/.alerted"
  if [ -f "$stamp" ] && [ $(( $(date +%s) - $(stat -f %m "$stamp") )) -lt 3600 ]; then
    return 0                      # already told them within the hour
  fi
  date +%s > "$stamp"
  printf '%s\n' "$msg" >> "$RELAY/outbox.txt"
  "$RELAY/notify.sh"
}

# ---- 0. MANUAL STOP. Permanent. Nothing auto-clears this. -------------------
# `touch ~/Projects/relay/.stop` halts the loop until a human removes it.
# This is separate from .halt (which the watchdog manages and auto-clears).
if [ -f "$RELAY/.stop" ]; then
  exit 0
fi

# Drain any pending alert.
[ -s "$REPO/.outbox.txt" ] || [ -s "$RELAY/outbox.txt" ] && "$RELAY/notify.sh"

"$RELAY/heal.sh"

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
      echo stuck-lock > "$RELAY/.halt"
    fi
    exit 0
  fi
  log "stale lock (pid $PID not a live shell), clearing"
  rm -f "$LOCK"
fi

cd "$REPO" || { log "ERROR: repo missing"; alert "🔴 Relay: repo missing at $REPO"; exit 1; }

# ---- 3. Queue promotion — VERIFY, THEN RECORD. -----------------------------
if [ ! -f NEXT-STEPS.md ] || [ "$(brief_status NEXT-STEPS.md)" = "DONE" ]; then
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
      # BOTH relay files are disposable — the executor rewrites them every run, and the
      # canonical copies arrive with the merge. Discard local edits so `pull --ff-only`
      # cannot abort.
      #
      # BUG (audit #2): this discarded only NEXT-STEPS.md. COWORK-STATUS.md was left dirty,
      # and every PR modifies it — so the moment a PR merged, `git pull --ff-only` refused
      # ("your local changes would be overwritten"), promotion aborted, and because alert()
      # had no dedup it sent ONE iMESSAGE PER MINUTE, forever, while the queue never moved.
      # The loop would have looked alive and done nothing.
      git checkout -- NEXT-STEPS.md COWORK-STATUS.md 2>/dev/null

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
[ "$(brief_status NEXT-STEPS.md)" = "OPEN" ] || exit 0

# ---- 4. RETRY CAP. A failing brief must not rebuild forever. ---------------
mkdir -p "$ATTEMPTS"
# Key on the BRIEF NUMBER, not the file's hash.
#
# BUG (audit #4): BKEY was `shasum NEXT-STEPS.md`. But the executor REWRITES NEXT-STEPS.md —
# CLAUDE.md explicitly tells it to write a report and leave the brief OPEN when it refuses a
# destructive instruction. Any such edit changes the hash → new key → attempts reset to 0 →
# "3 strikes" never lands. The retry cap FAILED OPEN: the exact "rebuilds forever" bug it was
# written to prevent, capped only by the daily budget.
#
# The brief's identity is its number, and the executor never changes that.
BKEY=$(grep -i -m1 '^Brief:' NEXT-STEPS.md | sed 's/[^0-9a-zA-Z]/_/g' | cut -c1-24)
[ -z "$BKEY" ] && BKEY="unnumbered"
N=$(cat "$ATTEMPTS/$BKEY" 2>/dev/null || echo 0)
if [ "$N" -ge 3 ]; then
  log "brief $BKEY has failed $N times — HALTING"
  alert "⛔ Relay HALTED: the current brief failed 3 times. Not retrying. Needs you."
  echo retry-cap > "$RELAY/.halt"
  exit 0
fi

# ---- 5. DAILY BUILD BUDGET — MEASURED, not guessed. -----------------------
#
# BUG (audit #5): this counted `claude -p` INVOCATIONS. Netlify does not bill invocations —
# it bills BUILDS. One brief = several pushes to the PR branch (a preview build each) + a
# production build on merge. Measured against reality: the counter said 6 while git showed
# 14 actual builds. A ceiling of "20" was really ~46 builds.
#
# A proxy metric that has never been reconciled against the real thing is a guess with a
# number on it — and this particular guess was the only thing standing between us and the
# quota exhaustion that took production down for four hours.
#
# So: COUNT THE ACTUAL TRIGGER. A Netlify build fires on a pushed commit that touches a file
# in netlify.toml's `ignore` list. Everything else is skipped and costs nothing. Derive the
# number from git each poll — self-correcting, no drift, no counter to fall out of sync.
BUILDS_TODAY=0
for c in $(git log --all --since=midnight --format=%H 2>/dev/null); do
  if git show --stat --format="" "$c" 2>/dev/null | grep -qE 'index\.html|_redirects|netlify\.toml'; then
    BUILDS_TODAY=$((BUILDS_TODAY+1))
  fi
done
BUILD_CEILING=25
if [ "$BUILDS_TODAY" -ge "$BUILD_CEILING" ]; then
  log "daily build budget reached ($BUILDS_TODAY real builds) — HALTING"
  alert "⛔ Relay HALTED: $BUILDS_TODAY Netlify builds today (ceiling $BUILD_CEILING). Netlify paused us once already — not risking it again."
  echo build-budget > "$RELAY/.halt"
  exit 0
fi
echo "$(date '+%Y-%m-%d') $BUILDS_TODAY" > "$BUDGET"
echo $((N+1)) > "$ATTEMPTS/$BKEY"

# ---- 5b. Prune stale worktrees. -------------------------------------------
# The executor now works in an isolated worktree (via the using-git-worktrees skill), so
# nothing else on this machine can move HEAD under it mid-build. That race — a reviewer
# running `git checkout main` during a 39-minute build — corrupted a branch and nearly
# triggered a `git reset --hard` on the only copy of a finished feature.
#
# We reinvented a worse fix (a lockfile plus a rule telling the reviewer to behave) before
# discovering worktrees are the standard answer. Keep the lock too — belt and braces — but
# the isolation is now structural rather than a promise.
git worktree prune 2>/dev/null

# ---- 5c. ONE PR PER BRIEF. Do not re-run work that already produced a PR. --
#
# BUG: a retry does not mean "start over." If the executor already opened a PR for this
# brief and then died (or was killed by a torn-read while someone edited this script),
# re-running it opens a SECOND PR for the same brief. That happened: brief #6 produced
# PRs #20 AND #21 before the retry cap stopped it.
#
# Promotion already gates on "zero open PRs" — but the RETRY path never checked. If a PR
# is open and the brief is still OPEN, the work exists; it's the bookkeeping that failed.
# That needs a human, not another build.
if OPEN_PR=$(gh pr list --state open --limit 1 --json number -q '.[0].number' 2>/dev/null) && [ -n "$OPEN_PR" ]; then
  # WAIT — do not HALT. An open PR is not a failure; it is the system waiting for a merge.
  # Halting would require a human to clear a flag before the loop could ever move again,
  # which turns the normal resting state into an outage. Just exit quietly and re-check next
  # poll. When the PR merges, promotion runs and the loop continues on its own.
  #
  # The alert is deduped (once/hour) so a PR that genuinely sits for days doesn't go unnoticed,
  # without becoming the 1,400-texts-a-day problem.
  log "brief OPEN but PR #$OPEN_PR exists — waiting for it to merge, not re-running"
  alert "⏳ Relay: PR #$OPEN_PR is open and waiting on you. The loop is paused until it merges — not re-running the brief (that would open a duplicate)."
  exit 0
fi

# ---- 6. Run the executor. --------------------------------------------------
"$RELAY/backup.sh" >/dev/null 2>&1
BRIEF=$(grep -i '^Brief:' NEXT-STEPS.md | head -1)
echo "$$ $(date +%s) claude-relay" > "$LOCK"
log "OPEN brief (attempt $((N+1))/3) — $BRIEF — invoking Claude Code"

claude -p "check next" --dangerously-skip-permissions >> "$LOG" 2>&1
RC=$?
log "Claude Code exited rc=$RC"

if [ "$(brief_status NEXT-STEPS.md)" = "DONE" ]; then
  log "brief marked DONE"
  rm -f "$ATTEMPTS/$BKEY"          # success — reset the counter
else
  # This branch used to do NOTHING. The poller would relaunch the identical build 60s later.
  log "WARNING: brief still OPEN after run (attempt $((N+1))/3)"
  if [ $((N+1)) -ge 3 ]; then
    alert "⛔ Relay: brief failed 3 times, halting. Check COWORK-STATUS.md."
    echo retry-cap > "$RELAY/.halt"
  else
    alert "⚠️ Relay: brief didn't complete (attempt $((N+1))/3). Will retry."
  fi
fi

rm -f "$LOCK"
log "--- run complete ---"
# harmless trailing comment 1783960023
