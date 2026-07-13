#!/bin/zsh
# Does the commit split actually kill the conflict class? Prove it, both ways.
#
# The scenario that stranded PR #23 and PR #24, reproduced exactly:
#   1. Code branches off main and starts building.
#   2. While it builds, main MOVES (someone commits — a boot-file edit, an alert fix, anything).
#   3. Code finishes and pushes its work.
#   4. Can the PR merge?
#
# OLD protocol (bookkeeping rides the branch) -> both sides rewrote NEXT-STEPS.md -> CONFLICT.
# NEW protocol (branch is product-only)       -> nothing to collide with -> clean merge.

T=/tmp/splittest; rm -rf $T; mkdir -p $T; cd $T
git init -q repo && cd repo && git config user.email t@t.t && git config user.name t

cat > index.html <<'EOF'
<html><body><h1>the product</h1></body></html>
EOF
printf 'Status: DONE\nBrief: #6 — previous brief\n' > NEXT-STEPS.md
printf '# COWORK-STATUS.md\nBrief #6 report\n' > COWORK-STATUS.md
git add -A && git commit -qm "base"
BASE=$(git rev-parse HEAD)

pass=0; fail=0
check() { if [ "$2" = "$3" ]; then print "  OK   $1 -> $3"; pass=$((pass+1))
          else print "  FAIL $1 -> expected $2, got $3"; fail=$((fail+1)); fi }

conflicts() { # conflicts <branch> -> "CONFLICT" or "clean"
  local out=$(git merge-tree --write-tree main "$1" 2>&1)
  if printf '%s' "$out" | grep -qi conflict; then echo "CONFLICT"; else echo "clean"; fi
}

git branch -M main

print "==== OLD PROTOCOL — bookkeeping rides the feature branch ===="
git checkout -q -b old-brief7 $BASE
# Code does the work AND the paperwork on its branch:
sed -i '' 's/the product/the product, improved/' index.html
printf 'Status: DONE\nBrief: #7 — three mobile bugs\n' > NEXT-STEPS.md
printf '# COWORK-STATUS.md\nBrief #7 report\nVerification: PASS\n' > COWORK-STATUS.md
git add -A && git commit -qm "Brief #7 + paperwork"
# meanwhile, main moves (a boot-file edit + the next brief promoted):
git checkout -q main
printf 'Status: OPEN\nBrief: #8 — bank pills\n' > NEXT-STEPS.md
echo "escalation bar" > COWORK-BOOT.md
git add -A && git commit -qm "boot + promote brief 8"
check "PR mergeable?" "CONFLICT" "$(conflicts old-brief7)"
print "     (this is PR #23 and PR #24, exactly)"

print ""
print "==== NEW PROTOCOL — branch carries product code ONLY ===="
git checkout -q -b new-brief9 $BASE
# Code does ONLY the work on its branch:
sed -i '' 's/the product/the product, improved again/' index.html
git add index.html && git commit -qm "Brief #9: product only"
# meanwhile main moves the SAME way — and Code's paperwork ALSO lands on main:
git checkout -q main
printf 'Status: DONE\nBrief: #9 — shortcut buttons\n' > NEXT-STEPS.md
printf '# COWORK-STATUS.md\nBrief #9 report\nVerification: PASS\n' > COWORK-STATUS.md
echo "more boot edits" >> COWORK-BOOT.md
git add -A && git commit -qm "Brief #9: status — Verification: PASS"
check "PR mergeable?" "clean" "$(conflicts new-brief9)"

print ""
print "==== CONTROL — the split must not hide a REAL code conflict ===="
print "     If two branches genuinely touch the same product line, it MUST still conflict."
git checkout -q -b rival $BASE
sed -i '' 's/the product/RIVAL EDIT/' index.html
git add index.html && git commit -qm "rival product change"
git checkout -q main && git merge -q --no-edit new-brief9 2>/dev/null
check "genuine code clash still conflicts?" "CONFLICT" "$(conflicts rival)"
print "     (the split removes PAPERWORK conflicts, not real ones — a merge gate that can no"
print "      longer detect a real collision would be worse than the bug it replaced)"

print ""
print "--------------------------------------"
print "PASSED: $pass   FAILED: $fail"
if [ "$fail" -eq 0 ]; then print "ALL GREEN"; else print "SOMETHING IS WRONG"; fi
exit $fail
