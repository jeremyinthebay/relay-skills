#!/bin/zsh
# pr-gate.sh <PR-NUMBER> — the merge preconditions, as code instead of prose.
#
# WHY THIS EXISTS
# The reviewer's merge bar lived in REVIEWER.md as English. English does not fail closed. This
# script is the cheap, mechanical part of the bar — the part that can be tested, and that cannot
# be talked out of a refusal at 3am.
#
# IT IS NECESSARY, NOT SUFFICIENT. Passing this gate does NOT mean "merge it." The reviewer must
# still independently verify the deploy preview with Playwright — clicking the thing, with a
# control. That adversarial second look is the whole point of the relay and no script replaces it.
# This gate only catches the mechanical failures that kept costing us nights.
#
# Exit codes:  0 = PASS      2 = LEGACY (pre-2026-07-13 protocol; allowed, warned)
#              1 = REFUSE — do not merge, whatever else you believe.

set -u
PR="${1:-}"
REPO="$HOME/Projects/my-project"
[ -n "$PR" ] || { print "usage: pr-gate.sh <pr-number>"; exit 1; }
cd "$REPO" || { print "REFUSE: repo missing"; exit 1; }

# Product files. A PR may contain ONLY these.
#
# The relay bookkeeping (NEXT-STEPS.md, COWORK-STATUS.md) is now committed straight to main in its
# own commit and NEVER rides a feature branch. Reason: main moves during every build, both sides
# rewrite those files, and git conflicts on them — which is what made PR #23 and PR #24 unmergeable
# and deadlocked the loop. Product code doesn't conflict; paperwork does. So the paperwork stops
# travelling with the product.
PRODUCT='^(index\.html|404\.html|_redirects|netlify\.toml|assets/.*)$'
BOOKKEEPING='^(NEXT-STEPS\.md|COWORK-STATUS\.md)$'

FILES=$(gh pr view "$PR" --json files -q '.files[].path' 2>/dev/null)
if [ -z "$FILES" ]; then
  print "REFUSE: cannot read PR #$PR file list (gh failed?). An empty answer from a source that"
  print "        wasn't looking is not an answer — failing closed."
  exit 1
fi

legacy=0; bad=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if   printf '%s' "$f" | grep -qE "$PRODUCT";     then :
  elif printf '%s' "$f" | grep -qE "$BOOKKEEPING"; then legacy=1
  else bad="$bad $f"
  fi
done <<< "$FILES"

if [ -n "$bad" ]; then
  print "REFUSE: PR #$PR carries files that are neither product nor bookkeeping:$bad"
  print "        A PR ships product code. If this is intentional, a human decides — not the loop."
  exit 1
fi

# ---- The verification verdict. Read it from MAIN, not from the branch. ------------------------
# Code commits COWORK-STATUS.md to main directly, so main is where the report lives.
#
# ONE HEADER LINE, FIRST OCCURRENCE ONLY. Do NOT grep the body for the word "FAIL" — a HEALTHY
# report says things like "the control run on production failed all 3 checks", which is exactly
# what a good report SHOULD say. A body-grep would refuse correct work for describing a control
# working correctly. That is the misfiring-guardrail class of bug, and we have paid for it twice.
git fetch -q origin 2>/dev/null
STATUS_BODY=$(git show origin/main:COWORK-STATUS.md 2>/dev/null)
if [ -z "$STATUS_BODY" ]; then
  print "REFUSE: COWORK-STATUS.md not found on origin/main. No report = no merge."
  exit 1
fi

VERDICT=$(printf '%s' "$STATUS_BODY" | grep -i -m1 '^Verification:' | sed 's/^[Vv]erification: *//' \
          | tr '[:lower:]' '[:upper:]' | tr -d ' \r' | cut -c1-4)

case "$VERDICT" in
  PASS) : ;;
  FAIL)
    print "REFUSE: COWORK-STATUS.md on main reports 'Verification: FAIL'. Never merge a failing PR."
    exit 1 ;;
  *)
    # No verdict line. Two very different situations — do not collapse them.
    #
    # A NEW-protocol PR (product-only) with no verdict is a report that never said it worked:
    # FAIL CLOSED, refuse.
    #
    # A LEGACY PR (still carrying bookkeeping on the branch) was BUILT BEFORE the header existed.
    # Refusing it would be a guardrail firing on work that predates the rule it enforces — punishing
    # Code for not following an instruction it was never given. That is the misfiring-guardrail bug,
    # and shipping it here would have blocked brief #9, which was already mid-build when the
    # protocol changed. Warn loudly, let the reviewer's own Playwright verification decide.
    if [ "$legacy" -eq 1 ]; then
      print "LEGACY: PR #$PR predates the 'Verification:' header (built under the old protocol) and"
      print "        carries bookkeeping on the branch. No machine-readable verdict to check."
      print "        THE GATE CANNOT VOUCH FOR THIS ONE — your own verification is the only bar."
      print "        Merge only if YOU verified the preview with a real tap and a control."
      exit 2
    fi
    print "REFUSE: COWORK-STATUS.md on main has no 'Verification: PASS|FAIL' header line."
    print "        A report that does not state its verdict has not verified anything."
    exit 1 ;;
esac

# "Verified" without pasted output is a FAIL — an old rule, now enforced instead of hoped for.
if ! printf '%s' "$STATUS_BODY" | grep -q '```'; then
  print "REFUSE: COWORK-STATUS.md contains no pasted output (no code fences). 'Verified' is a claim,"
  print "        not evidence."
  exit 1
fi

# ---- Git must actually be able to merge it. --------------------------------------------------
MERGEABLE=$(gh pr view "$PR" --json mergeable -q .mergeable 2>/dev/null)
if [ "$MERGEABLE" = "CONFLICTING" ]; then
  print "REFUSE: PR #$PR is CONFLICTING. Do not close it and do not redo the work — write a repair"
  print "        brief with 'Target-PR: #$PR' in the header and let Code fix the branch."
  exit 1
fi

if [ "$legacy" -eq 1 ]; then
  print "LEGACY: PR #$PR carries relay bookkeeping on the branch (pre-2026-07-13 protocol)."
  print "        Verdict is PASS and it merges cleanly, so it may be merged — but this is the shape"
  print "        that conflicts. New PRs must be product-only."
  exit 2
fi

print "PASS: PR #$PR is product-only, verdict on main is PASS, output is pasted, and git can merge."
print "      This gate is NECESSARY, NOT SUFFICIENT — go verify the preview with Playwright."
exit 0
