#!/bin/zsh
# watchdog.sh — notice trouble and SAY SO.
#
# REWRITTEN after an audit found this file — the safety net itself — silently broken:
#   * Line 45 threw "character not in range" on EVERY poll. 259 errors, into launchd.err.log,
#     which nothing read. Cause: zsh's builtin `echo` interprets backslash escapes, and the
#     site's inline JS contains a sequence it chokes on. The body being grepped was mangled
#     and TRUNCATED — so the "site paused" banner it exists to detect might never have matched.
#     The watchdog written to fix "the watchdog was silently broken" was silently broken.
#   * It deleted .halt unconditionally, so a human kill switch was erased within 60 seconds.
#   * gh failing returned empty -> no stuck-PR alert. Fail-open safety net = no safety net.
#
# Rules now: never pipe untrusted bytes through echo. Fail closed. Read your own error log.

REPO="$HOME/Projects/my-project"
RELAY="$HOME/Projects/relay"
LOG="$RELAY/relay.log"
STATE="$RELAY/.watchdog"
ERRLOG="$RELAY/launchd.err.log"
mkdir -p "$STATE"

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
log(){ printf '[%s] WATCHDOG: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

alert() {
  local key="$1"; shift
  local stamp="$STATE/$key"
  if [ -f "$stamp" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$stamp") ))
    [ "$age" -lt 3600 ] && return 0
  fi
  date +%s > "$stamp"
  log "ALERT [$key] $*"
  printf '%s\n' "$*" >> "$RELAY/outbox.txt"
  "$RELAY/notify.sh"
}
clear_alert(){ rm -f "$STATE/$1"; }

cd "$REPO" 2>/dev/null || { log "repo missing"; exit 1; }

# ---- 1. Production health -------------------------------------------------
# NEVER `echo "$BODY" | grep`. zsh's echo mangles escape sequences in the page's inline JS,
# truncating the very body we're inspecting. Grep the stream directly.
CODE=$(curl -s -m 20 -o /dev/null -w "%{http_code}" https://example.com/ 2>/dev/null)
PAUSED=no
curl -s -m 20 https://example.com/ 2>/dev/null | grep -qi "usage limits\|site was paused\|Site not available" && PAUSED=yes

if [ "$PAUSED" = "yes" ]; then
  alert prod_paused "🔴 Netlify PAUSED the site (usage limits). Relay halted so it stops burning builds. Needs your account."
  touch "$RELAY/.halt"
elif [ "$CODE" != "200" ]; then
  alert prod_down "🔴 example.com is DOWN (HTTP $CODE). Relay halted."
  touch "$RELAY/.halt"
else
  clear_alert prod_down; clear_alert prod_paused
  # Clear the AUTO halt only. NEVER touch .stop — that is the human kill switch and it is
  # permanent until a human removes it. The old code deleted the kill switch within 60s.
  rm -f "$RELAY/.halt"
fi

# ---- 2. Is the executor running? Validate the lock, don't trust it. --------
BUILDING=no
if [ -f "$RELAY/.lock" ]; then
  LPID=$(cut -d' ' -f1 "$RELAY/.lock" 2>/dev/null)
  if [ -n "$LPID" ] && kill -0 "$LPID" 2>/dev/null && ps -p "$LPID" -o comm= 2>/dev/null | grep -q zsh; then
    BUILDING=yes
  fi
fi

# ---- 3. A PR sitting unmerged with nothing happening -----------------------
# FAIL CLOSED: if gh can't answer, say so. An empty answer from a source that wasn't
# looking is not an answer — that's how the old version went quietly blind.
if ! PRJSON=$(gh pr list --state open --limit 1 --json number,createdAt 2>&1); then
  alert gh_broken "⚠️ Watchdog can't reach GitHub — it is BLIND to stuck PRs. ($PRJSON)"
else
  clear_alert gh_broken
  OPENPR=$(printf '%s' "$PRJSON" | jq -r '.[0].number // empty' 2>/dev/null)
  OPENED=$(printf '%s' "$PRJSON" | jq -r '.[0].createdAt // empty' 2>/dev/null)

  if [ -n "$OPENPR" ] && [ "$BUILDING" = "no" ]; then
    # -u is load-bearing: GitHub returns UTC. Without it the PR reads as created in the
    # FUTURE, age goes negative, and this alert never fires. That bug shipped once.
    OPENED_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$OPENED" +%s 2>/dev/null || echo 0)
    if [ "$OPENED_TS" -eq 0 ]; then
      alert watchdog_blind "⚠️ Watchdog can't parse PR timestamps — it is BLIND. Fix before trusting the loop."
    else
      AGE_MIN=$(( ( $(date +%s) - OPENED_TS ) / 60 ))
      if [ "$AGE_MIN" -gt 30 ]; then
        PREV=$(curl -s -m 20 -o /dev/null -w "%{http_code}" "https://deploy-preview-$OPENPR--myproject.netlify.app/" 2>/dev/null)
        if [ "$PREV" != "200" ]; then
          alert stuck_nopreview "⚠️ PR #$OPENPR open ${AGE_MIN}m, preview returns $PREV — no build. Relay can't review it."
        else
          alert stuck_unmerged "⚠️ PR #$OPENPR open ${AGE_MIN}m, preview up, nothing building, not merged. Reviewer may be stalled."
        fi
      fi
    fi
  else
    clear_alert stuck_nopreview; clear_alert stuck_unmerged
  fi
fi

# ---- 4. An OPEN brief that nothing is executing ----------------------------
if [ -f NEXT-STEPS.md ] && grep -qi '^Status: *OPEN' NEXT-STEPS.md && [ "$BUILDING" = "no" ]; then
  MOD=$(( ( $(date +%s) - $(stat -f %m NEXT-STEPS.md) ) / 60 ))
  [ "$MOD" -gt 20 ] && alert brief_unstarted "⚠️ An OPEN brief has sat ${MOD}m with nothing building. Executor isn't picking it up."
else
  clear_alert brief_unstarted
fi

# ---- 5. READ YOUR OWN ERROR LOG. -----------------------------------------
# The audit's real finding: every bug was already visible in a file on this machine.
# launchd.err.log had 259 unread errors. relay.log had Code reporting that its branch
# "silently reverted to main." The logs were excellent. Nothing read them.
if [ -f "$ERRLOG" ]; then
  SEEN=$(cat "$STATE/errlines" 2>/dev/null || echo 0)
  NOW=$(wc -l < "$ERRLOG" | tr -d ' ')
  if [ "$NOW" -gt "$SEEN" ]; then
    NEW=$(tail -n $(( NOW - SEEN )) "$ERRLOG" | head -3)
    echo "$NOW" > "$STATE/errlines"
    alert stderr_new "⚠️ Relay scripts are erroring. New in launchd.err.log:
$NEW"
  fi
fi

# ---- 6. Code shouting into the void in relay.log --------------------------
# Code writes real warnings there. Nobody was reading them.
if [ -f "$LOG" ]; then
  # EXCLUDE MY OWN ALERTS. They land in relay.log and contain the word "warning", so the
  # next poll saw them as a NEW warning and alerted about its own alert — which logged
  # another warning, and so on. A self-amplifying feedback loop, texting the owner each time.
  #
  # A monitor must never observe its own output as an input. Filter WATCHDOG lines out.
  WSEEN=$(cat "$STATE/warnlines" 2>/dev/null || echo 0)
  WNOW=$(grep -vi "WATCHDOG" "$LOG" | grep -ci "WARNING\|ERROR\|silently reverted\|stranded" || echo 0)
  if [ "$WNOW" -gt "$WSEEN" ]; then
    echo "$WNOW" > "$STATE/warnlines"
    LAST=$(grep -vi "WATCHDOG" "$LOG" | grep -i "WARNING\|ERROR\|silently reverted\|stranded" | tail -1)
    alert log_warning "⚠️ Relay log warning: $LAST"
  fi
fi

exit 0
