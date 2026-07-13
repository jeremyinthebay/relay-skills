#!/bin/zsh
# MECHANICAL GATE for destructive git. A model can talk its way past a paragraph in CLAUDE.md
# — one did, this morning, and authored `git reset --hard` on the only copy of a finished
# feature with a confident explanation attached. It cannot talk its way past this.
#
# TESTED, not assumed: claude-code#20946 claims PreToolUse hooks do not block under
# --dangerously-skip-permissions. On 2.1.197 that does NOT reproduce — verified with a control
# run (agent DID execute without the hook) and then the real command (blocked, commit survived).
# Re-test after any Claude Code upgrade. A mechanism you haven't tested in YOUR config is a rumour.
CMD=$(cat | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)

case "$CMD" in
  *"reset --hard"*|*"push --force"*|*"push -f "*|*"branch -D"*|*"clean -fd"*|*"clean -xdf"*|*"filter-branch"*|*"reflog delete"*|*"update-ref -d"*)
    echo "BLOCKED by hook: destructive git is not permitted for autonomous runs." >&2
    echo "Command was: $CMD" >&2
    echo "If work looks lost, it almost certainly isn't. Check: git log origin/main..main, git branch -a, gh pr list." >&2
    echo "Only a human, in an interactive session, may run this — after editing ~/.claude/settings.json." >&2
    exit 2 ;;
esac
exit 0
