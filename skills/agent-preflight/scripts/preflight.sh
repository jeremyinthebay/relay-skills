#!/bin/zsh
# PREFLIGHT — exercise every LOCAL capability the autonomous loop needs, on purpose,
# while the owner is sitting at the machine to approve the prompts.
#
# WHY THIS EXISTS: permissions on macOS are lazy. A TCC prompt (Automation, Files &
# Folders, Full Disk Access) fires the FIRST time a process actually does the thing —
# which, in an autonomous loop, is at 3am when nobody is there to click Allow. The loop
# then blocks forever and looks like silence. This script forces every prompt to happen
# NOW, in front of a human.
#
# Run it, approve everything it asks for, and the loop will never stall on a dialog.
#
#   ~/Projects/relay/preflight.sh
#
# It is read-only / no-op wherever possible. It does not push, merge, or publish.

REPO="$HOME/Projects/my-project"
RELAY="$HOME/Projects/relay"
PASS=0; FAIL=0
ok(){ echo "  ✅ $*"; PASS=$((PASS+1)); }
no(){ echo "  ❌ $*"; FAIL=$((FAIL+1)); }

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "═══════════════════════════════════════════════════════════"
echo " RELAY PREFLIGHT — approve every prompt that appears"
echo "═══════════════════════════════════════════════════════════"
echo

echo "1. Binaries on PATH (launchd has a minimal PATH — this is a classic silent killer)"
for b in claude gh git node curl osascript shasum; do
  command -v $b >/dev/null 2>&1 && ok "$b -> $(command -v $b)" || no "$b NOT FOUND — loop will fail"
done
echo

echo "2. GitHub auth (must be non-interactive; a login prompt at 3am = dead loop)"
gh auth status >/dev/null 2>&1 && ok "gh authenticated" || no "gh NOT authenticated — run: gh auth login"
git -C "$REPO" ls-remote --exit-code origin >/dev/null 2>&1 && ok "git can reach origin without a prompt" || no "git remote unreachable / wants credentials"
echo

echo "3. Repo state"
[ -d "$REPO/.git" ] && ok "repo present at $REPO" || no "repo missing"
[ -f "$REPO/CLAUDE.md" ] && ok "CLAUDE.md present (project identity)" || no "CLAUDE.md missing"
[ -w "$REPO" ] && ok "repo writable" || no "repo not writable"
echo

echo "4. Claude Code headless — the real thing, one cheap call."
echo "   >>> If macOS prompts for anything, APPROVE IT. <<<"
# No `timeout` on stock macOS (that's GNU coreutils' gtimeout) — the preflight caught this
# about itself on first run. Use perl's alarm instead, which is always present.
# Run in a TEMP dir, not the repo: Code may be mid-build in there, and two claude processes
# doing git operations in one working tree is a real way to corrupt a run.
TMPD=$(mktemp -d)
OUT=$(cd "$TMPD" && perl -e 'alarm 120; exec @ARGV' claude -p "Reply with exactly: PREFLIGHT_OK. Do nothing else. Do not read files, do not run commands." --dangerously-skip-permissions 2>&1)
rm -rf "$TMPD"
if echo "$OUT" | grep -q "PREFLIGHT_OK"; then
  ok "claude -p runs headless and returns output"
else
  no "claude -p did not respond as expected. Got: $(echo "$OUT" | head -2)"
fi
echo

echo "5. iMessage via osascript — THIS is the one that throws an Automation prompt."
echo "   >>> Approve 'Terminal/Claude wants to control Messages'. <<<"
osascript <<'EOF' >/dev/null 2>&1
tell application "Messages"
  set targetService to 1st account whose service type = iMessage
  set targetBuddy to participant "+15550000000" of targetService
  send "Relay preflight: notification path confirmed. You can ignore this." to targetBuddy
end tell
EOF
[ $? -eq 0 ] && ok "iMessage sent — check your phone" || no "osascript blocked. Fix: System Settings > Privacy & Security > Automation > allow Messages"
echo

echo "6. Network reachability (no proxy prompts, no captive portal)"
curl -s -m 15 -o /dev/null -w "" https://example.com/ && ok "prod reachable" || no "cannot reach prod"
curl -s -m 15 -o /dev/null -w "" https://api.github.com/ && ok "github api reachable" || no "cannot reach github"
echo

echo "7. launchd agent"
launchctl list 2>/dev/null | grep -q pointsrelay && ok "watcher agent loaded" || no "watcher NOT loaded — run: launchctl load ~/Library/LaunchAgents/com.example.relay.plist"
for s in watch.sh notify.sh watchdog.sh; do
  [ -x "$RELAY/$s" ] && ok "$s executable" || no "$s missing or not +x"
done
echo

echo "8. Scripts parse"
for s in watch.sh notify.sh watchdog.sh; do
  zsh -n "$RELAY/$s" 2>/dev/null && ok "$s syntax OK" || no "$s SYNTAX ERROR"
done
echo

echo "═══════════════════════════════════════════════════════════"
echo " $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo " ✅ LOCAL side is clear. The loop will not stall on a local dialog."
  echo
  echo " STILL TO DO — the Claude-side approvals, which live per scheduled task:"
  echo "   Open the Scheduled sidebar, hit 'Run now' on relay-reviewer"
  echo "   with the .preflight flag set, and approve every tool it asks for."
  echo "   Those approvals are stored ON THE TASK and reused on every future run."
else
  echo " ❌ Fix the failures above before walking away. Each one is a 3am stall."
fi
echo "═══════════════════════════════════════════════════════════"
