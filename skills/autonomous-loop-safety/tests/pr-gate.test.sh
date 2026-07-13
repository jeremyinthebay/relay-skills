#!/bin/zsh
# Resolve the skill dir ABSOLUTELY, before any cd. A relative $0 stops resolving
# the moment the test cd's into its fixture repo — which it does.
SKILLDIR=${0:A:h}/..
# Tests for pr-gate.sh — the merge gate.
# Runs the REAL script against a fake $HOME repo and a stubbed `gh`.

T=/tmp/prgatetest
rm -rf $T; mkdir -p $T/bin $T/home/Projects/my-project
FH=$T/home
REPO=$FH/Projects/my-project

cat > $T/bin/gh <<'EOF'
#!/bin/zsh
# stub: PR file list from /tmp/prgatetest/files, mergeable from /tmp/prgatetest/mergeable
for a in "$@"; do
  if [ "$a" = "files" ] || [ "$a" = ".files[].path" ]; then :; fi
done
if printf '%s' "$*" | grep -q "files"; then
  cat /tmp/prgatetest/files 2>/dev/null
elif printf '%s' "$*" | grep -q "mergeable"; then
  cat /tmp/prgatetest/mergeable 2>/dev/null || echo MERGEABLE
fi
exit 0
EOF
chmod +x $T/bin/gh

# a REAL origin, because the gate reads COWORK-STATUS.md from origin/main — without this the
# gate refuses for the wrong reason and the control passes by accident (it did, first run).
git init -q --bare $T/origin.git
cd $REPO && git init -q && git config user.email t@t.t && git config user.name t
git remote add origin $T/origin.git
git commit -q --allow-empty -m init && git branch -M main && git push -q origin main

# the gate under test, with the stub ahead of it on PATH
cp "$SKILLDIR/scripts/pr-gate.sh" $T/pr-gate.sh
chmod +x $T/pr-gate.sh

set_status() { printf '%s\n' "$@" > $REPO/COWORK-STATUS.md
  cd $REPO && git add -A && git commit -qm s --allow-empty >/dev/null && git push -q origin main
}
set_files()  { printf '%s\n' "$@" > $T/files; }
set_merge()  { echo "$1" > $T/mergeable; }
run_gate()   { PATH="$T/bin:$PATH" HOME=$FH zsh $T/pr-gate.sh 24 2>&1; }
code()       { PATH="$T/bin:$PATH" HOME=$FH zsh $T/pr-gate.sh 24 >/dev/null 2>&1; echo $?; }

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then print "  OK   $1 -> $3"; pass=$((pass+1))
          else print "  FAIL $1 -> expected $2, got $3"; fail=$((fail+1)); fi }

# a healthy report — note it MENTIONS a control that failed, which is CORRECT reporting
HEALTHY=(
 "# COWORK-STATUS.md"
 "Verification: PASS"
 ""
 "The control run against production failed all 3 checks, so the test can fail. Good."
 '```'
 "scroll 0 -> 2695, #changes at top 0"
 '```'
)
FAILED=(
 "# COWORK-STATUS.md"
 "Verification: FAIL"
 ""
 "The overflow probe found 3 offenders at 393px. Not fixed."
 '```'
 "docScrollWidth 431 > clientWidth 393"
 '```'
)
NOOUTPUT=( "# COWORK-STATUS.md" "Verification: PASS" "" "I verified everything. Trust me." )
NOVERDICT=( "# COWORK-STATUS.md" "" "Looks good to me." '```' "some output" '```' )

set_merge MERGEABLE

print "==== 1. Product-only PR, verdict PASS -> gate PASSES ===="
set_status "${HEALTHY[@]}"; set_files "index.html"
check "exit code" "0" "$(code)"

print ""
print "==== 2. CONTROL — COWORK-STATUS on main says FAIL -> gate REFUSES ===="
print "     (this is the one that must never soften: a failing PR is not mergeable)"
set_status "${FAILED[@]}"; set_files "index.html"
check "exit code" "1" "$(code)"
run_gate | head -1 | sed 's/^/     /'

print ""
print "==== 3. FALSE-REFUSE TRAP — healthy report that SAYS the word 'failed' ===="
print "     A naive body-grep for FAIL would refuse this. It is a correct report of a"
print "     control working. The gate must PASS it."
set_status "${HEALTHY[@]}"; set_files "index.html"
check "exit code" "0" "$(code)"

print ""
print "==== 4. No pasted output ('verified' as a bare claim) -> REFUSE ===="
set_status "${NOOUTPUT[@]}"; set_files "index.html"
check "exit code" "1" "$(code)"

print ""
print "==== 5. No verdict line at all -> REFUSE (fail closed) ===="
set_status "${NOVERDICT[@]}"; set_files "index.html"
check "exit code" "1" "$(code)"

print ""
print "==== 6. PR carrying relay bookkeeping -> LEGACY (allowed, warned) ===="
set_status "${HEALTHY[@]}"; set_files "index.html" "NEXT-STEPS.md" "COWORK-STATUS.md"
check "exit code" "2" "$(code)"

print ""
print "==== 7. PR carrying something that is neither -> REFUSE ===="
set_status "${HEALTHY[@]}"; set_files "index.html" ".github/workflows/deploy.yml"
check "exit code" "1" "$(code)"

print ""
print "==== 8. CONFLICTING -> REFUSE, and points at the Target-PR hatch ===="
set_status "${HEALTHY[@]}"; set_files "index.html"; set_merge CONFLICTING
check "exit code" "1" "$(code)"
print "     mentions the Target-PR hatch: $(run_gate | grep -c 'Target-PR')"
set_merge MERGEABLE

print ""
print "==== 9. gh returns nothing (blind) -> REFUSE, never fail open ===="
set_status "${HEALTHY[@]}"; : > $T/files
check "exit code" "1" "$(code)"

print ""
print "==== 10. TRANSITION — LEGACY PR with no verdict header -> LEGACY, not REFUSE ===="
print "     Brief #9 was already mid-build when the protocol changed. Refusing it would be a"
print "     guardrail punishing Code for not following a rule it was never given."
set_status "${NOVERDICT[@]}"; set_files "index.html" "NEXT-STEPS.md" "COWORK-STATUS.md"
check "exit code" "2" "$(code)"
run_gate | head -1 | sed 's/^/     /'

print ""
print "==== 11. …but a NEW-protocol PR with no verdict still REFUSES (fail closed) ===="
print "     The escape hatch must not become a hole: product-only means the header is required."
set_status "${NOVERDICT[@]}"; set_files "index.html"
check "exit code" "1" "$(code)"

print ""
print "==== 12. …and a LEGACY PR whose verdict says FAIL is still REFUSED ===="
print "     Legacy tolerance never extends to merging failed work."
set_status "${FAILED[@]}"; set_files "index.html" "NEXT-STEPS.md" "COWORK-STATUS.md"
check "exit code" "1" "$(code)"

print ""
print "--------------------------------------"
print "PASSED: $pass   FAILED: $fail"
if [ "$fail" -eq 0 ]; then print "ALL GREEN"; else print "SOMETHING IS WRONG"; fi
exit $fail