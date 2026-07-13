#!/bin/zsh
# canary.sh — after every merge, prove PRODUCTION still works. Revert it if not.
#
# WHY: with auto-merge ON we are optimising for speed, which means bad code reaches production
# faster. That trade is only acceptable if a bad merge is CHEAP TO UNDO. So: after each deploy,
# check that production still does the things a user needs. If it doesn't, revert immediately —
# don't wait for a human to notice.
#
# `git revert` is SAFE: it creates a NEW commit that undoes the change. It never rewrites history,
# never deletes a commit, never force-pushes. It is the one "undo" an autonomous system may run,
# and it is why the destructive-git hook doesn't block it.
#
# ROLLBACK IS A FEATURE, NOT A FAILURE. A loop that can undo itself in 60 seconds can afford to
# move fast. A loop that can't, can't.

RELAY="$HOME/Projects/relay"
REPO="$HOME/Projects/my-project"
LOG="$RELAY/relay.log"
SITE="https://example.com"

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
log(){ printf '[%s] CANARY: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
alert(){ printf '%s\n' "$*" >> "$RELAY/outbox.txt"; "$RELAY/notify.sh"; }

cd "$REPO" || exit 1

# Only run after a merge we haven't checked yet.
HEAD_SHA=$(git rev-parse --short origin/main 2>/dev/null)
LAST=$(cat "$RELAY/.canary-checked" 2>/dev/null)
[ "$HEAD_SHA" = "$LAST" ] && exit 0
[ -z "$HEAD_SHA" ] && exit 0

# Give Netlify time to actually deploy the merge.
sleep 45

BODY=$(curl -s -m 25 --compressed "$SITE/?cb=$RANDOM" 2>/dev/null)
CODE=$(curl -s -m 25 -o /dev/null -w "%{http_code}" "$SITE/?cb=$RANDOM" 2>/dev/null)

# ---- The canary checks. ASSERT SUCCESS — don't try to enumerate failure. ----
# Each is a thing a USER needs. If any is missing, the site is broken for someone.
FAILED=()
[ "$CODE" = "200" ] || FAILED+=("HTTP $CODE")
printf '%s' "$BODY" | grep -q "Points & Prompts\|Points &amp; Prompts" || FAILED+=("title missing — is this even our site?")
printf '%s' "$BODY" | grep -q 'id="progGrid"'                        || FAILED+=("program grid gone")
printf '%s' "$BODY" | grep -q 'id="explorer"'                        || FAILED+=("explorer section gone")
printf '%s' "$BODY" | grep -q 'id="sources"'                         || FAILED+=("sources section gone")
printf '%s' "$BODY" | grep -q 'CARDS\s*=\|CARDS='                    || FAILED+=("CARDS data missing")
printf '%s' "$BODY" | grep -q 'PROGRAMS\s*=\|PROGRAMS='              || FAILED+=("PROGRAMS data missing")
# The AwardWallet proxy is load-bearing — the whole "live values" promise depends on it.
AWCODE=$(curl -s -m 20 -o /dev/null -w "%{http_code}" "$SITE/api/values" 2>/dev/null)
[ "$AWCODE" = "200" ] || FAILED+=("AwardWallet proxy returns $AWCODE")
# Page must not be a stub.
BYTES=$(printf '%s' "$BODY" | wc -c | tr -d ' ')
[ "$BYTES" -gt 100000 ] || FAILED+=("page is only ${BYTES} bytes — truncated or empty")

if [ ${#FAILED[@]} -eq 0 ]; then
  echo "$HEAD_SHA" > "$RELAY/.canary-checked"
  log "production healthy after $HEAD_SHA (${BYTES} bytes)"
  exit 0
fi

# ---- PRODUCTION IS BROKEN. Revert the merge. --------------------------------
log "PRODUCTION BROKEN after $HEAD_SHA: ${FAILED[*]}"

git fetch origin -q
git checkout -q main 2>/dev/null
git reset -q --keep origin/main 2>/dev/null || git checkout -q -- .
# `revert` a merge commit needs -m 1; a squash merge is an ordinary commit and doesn't.
if git revert --no-edit "$HEAD_SHA" 2>>"$LOG" || git revert --no-edit -m 1 "$HEAD_SHA" 2>>"$LOG"; then
  if git push origin main 2>>"$LOG"; then
    echo "$HEAD_SHA" > "$RELAY/.canary-checked"
    log "REVERTED $HEAD_SHA and pushed"
    alert "🔴 PRODUCTION BROKE after merging $HEAD_SHA — I REVERTED IT.

What failed:
$(printf '  · %s\n' "${FAILED[@]}")

The revert is pushed; prod should recover in ~1 min. The bad commit is still on the branch history
for inspection — nothing was destroyed. The loop is halted pending your look."
    echo canary-revert > "$RELAY/.halt"
    exit 1
  fi
fi

# Couldn't revert — this needs a human NOW.
alert "🔴🔴 PRODUCTION IS BROKEN after $HEAD_SHA AND I COULD NOT REVERT IT.

What failed:
$(printf '  · %s\n' "${FAILED[@]}")

Manual rollback: cd ~/Projects/my-project && git revert $HEAD_SHA && git push"
echo canary-revert-failed > "$RELAY/.halt"
exit 1
