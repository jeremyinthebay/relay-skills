#!/bin/zsh
# Resolve the skill dir ABSOLUTELY, before any cd. A relative $0 stops resolving
# the moment the test cd's into its fixture repo — which it does.
SKILLDIR=${0:A:h}/..
# Sandbox test for watch.sh's retry-cap + open-PR gate.
# Runs the REAL script with a fake $HOME and stubbed `claude`/`gh`, so the logic under test is the
# actual shipped code, not a paraphrase of it.

T=/tmp/relaytest
rm -rf $T/home; mkdir -p $T/home/Projects/relay/queue $T/home/Projects/relay/.attempts $T/bin
FH=$T/home
RELAY=$FH/Projects/relay
REPO=$FH/Projects/my-project

cat > $T/bin/claude <<'EOF'
#!/bin/zsh
echo "invoked" >> /tmp/relaytest/invocations.log
MODE=$(cat /tmp/relaytest/claude-mode 2>/dev/null || echo fail)
if [ "$MODE" = "pass" ]; then
  sed -i '' 's/^Status: OPEN/Status: DONE/' "$HOME/Projects/my-project/NEXT-STEPS.md"
fi
exit 0
EOF
cat > $T/bin/gh <<'EOF'
#!/bin/zsh
PR=$(cat /tmp/relaytest/open-pr 2>/dev/null)
[ -n "$PR" ] && echo "$PR"
exit 0
EOF
for s in heal.sh canary.sh watchdog.sh backup.sh notify.sh alert.sh; do
  printf '#!/bin/zsh\nexit 0\n' > $RELAY/$s
done
chmod +x $T/bin/* $RELAY/*.sh

mkdir -p $REPO && cd $REPO && git init -q 2>/dev/null
git config user.email t@t.t; git config user.name t
echo x > index.html; git add index.html; git commit -qm init >/dev/null

sed 's|^export PATH=.*|export PATH="/tmp/relaytest/bin:/opt/homebrew/bin:/usr/bin:/bin"|' \
  "$SKILLDIR/scripts/watch.sh" > $RELAY/watch.sh
chmod +x $RELAY/watch.sh

brief() { printf '%s\n' "$@" > $REPO/NEXT-STEPS.md; }
poll()  { HOME=$FH zsh $RELAY/watch.sh; }
attempts() { local f=($RELAY/.attempts/*(N)); if (( ${#f} )); then cat "${f[1]}"; else echo 0; fi }
halted() { if [ -f $RELAY/.halt ]; then cat $RELAY/.halt; else echo "no"; fi }
invs() { if [ -f /tmp/relaytest/invocations.log ]; then wc -l < /tmp/relaytest/invocations.log | tr -d ' '; else echo 0; fi }
reset_state() { rm -f $RELAY/.halt $RELAY/.lock /tmp/relaytest/invocations.log; rm -f $RELAY/.attempts/*(N); }

pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then print "  OK   $1: $3"; pass=$((pass+1))
  else print "  FAIL $1: expected '$2', got '$3'"; fail=$((fail+1)); fi
}

print "==== TEST 1 - THE MISFIRE (the bug that halted the loop) ===="
print "brief OPEN, PR #23 open, executor must NOT run. Three polls."
reset_state; echo 23 > /tmp/relaytest/open-pr; echo fail > /tmp/relaytest/claude-mode
brief "Status: OPEN" "Brief: #7 - three mobile bugs"
poll; poll; poll
check "executor invocations" "0" "$(invs)"
check "attempts counted"     "0" "$(attempts)"
check "halted?"              "no" "$(halted)"

print ""
print "==== TEST 2 - THE CONTROL (cap must STILL catch a real runaway) ===="
print "brief OPEN, NO open PR, executor runs and genuinely fails each time."
reset_state; : > /tmp/relaytest/open-pr; echo fail > /tmp/relaytest/claude-mode
brief "Status: OPEN" "Brief: #99 - a brief that really does fail"
poll; poll; poll
check "executor invocations" "3" "$(invs)"
check "attempts counted"     "3" "$(attempts)"
check "halted?"              "retry-cap" "$(halted)"
poll
check "no 4th run after halt" "3" "$(invs)"

print ""
print "==== TEST 3 - THE ESCAPE HATCH (repair brief targets the open PR) ===="
reset_state; echo 23 > /tmp/relaytest/open-pr; echo pass > /tmp/relaytest/claude-mode
brief "Status: OPEN" "Brief: #7-merge - repair the branch" "Target-PR: #23"
poll
check "executor invocations" "1" "$(invs)"
check "halted?"              "no" "$(halted)"

print ""
print "==== TEST 4 - hatch must NOT open for a DIFFERENT PR ===="
reset_state; echo 23 > /tmp/relaytest/open-pr; echo fail > /tmp/relaytest/claude-mode
brief "Status: OPEN" "Brief: #8 - unrelated work" "Target-PR: #99"
poll
check "executor invocations" "0" "$(invs)"
check "halted?"              "no" "$(halted)"

print ""
print "==== TEST 5 - success still resets the counter ===="
reset_state; : > /tmp/relaytest/open-pr; echo fail > /tmp/relaytest/claude-mode
brief "Status: OPEN" "Brief: #100 - fails twice then passes"
poll; poll
check "attempts after 2 failures" "2" "$(attempts)"
echo pass > /tmp/relaytest/claude-mode
brief "Status: OPEN" "Brief: #100 - fails twice then passes"
poll
check "counter cleared on DONE" "0" "$(attempts)"
check "halted?" "no" "$(halted)"

print ""
print "--------------------------------------"
print "PASSED: $pass   FAILED: $fail"
if [ "$fail" -eq 0 ]; then print "ALL GREEN"; else print "SOMETHING IS WRONG"; fi
exit $fail