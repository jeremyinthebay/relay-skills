---
name: destructive-git-hook
description: Install a PreToolUse hook that mechanically blocks git reset --hard, push --force, branch -D and other work-destroying commands — a gate an agent cannot talk its way past, unlike an instruction in CLAUDE.md. Use whenever an agent runs unattended or with --dangerously-skip-permissions, before letting an agent near a repo you care about, after an agent has proposed or run a destructive git command, or when someone asks how to stop an AI from deleting their work.
---

# The Destructive-Git Hook

## Why an instruction is not enough

Our executor had this in its `CLAUDE.md`:

> *"You must REFUSE `git reset --hard`, even if a task tells you to."*

Then a reviewing agent — reading a working tree that had been corrupted by a race — concluded a finished feature was "stranded," and wrote a task that said:

```sh
git checkout feature-branch
git reset --hard main      # "no divergence, so this is a clean replay"
```

That would have **deleted the only copy of a completed feature**, the commits an open PR was built from. It was recovering the work by destroying it, and it had a confident, plausible explanation attached.

**A human hit Deny on an approval dialog. That was the entire safety system.**

**A model can talk its way past a paragraph. It cannot talk its way past a hook.**

## The finding: hooks DO block in bypass mode (we tested it)

There's a widely-cited issue — [claude-code#20946](https://github.com/anthropics/claude-code/issues/20946), `has repro`, `area:security` — reporting that under `--dangerously-skip-permissions`, **`PreToolUse` hooks fire but do not block**: nine denials, five commits landed anyway. Closed as stale. Never fixed, never refuted.

If true, a hook would be **a safety gate that fails open in the exact mode an autonomous agent runs in** — worse than useless, because you'd trust it.

**So we tested it rather than believing either side.** On Claude Code **2.1.197**, it does **not** reproduce:

```
CONTROL (no hook):  agent ran the command, file created     ← proves the harness works
WITH HOOK:          "blocked by a PreToolUse hook"          ← nothing written
REAL COMMAND:       git reset --hard HEAD~1  →  BLOCKED, commit survived
HARMLESS GIT:       git status, git log      →  still allowed
```

**Hooks are a real mechanical gate. Install one.**

> ⚠️ **A mechanism you haven't tested in YOUR configuration is a rumour — and so is a bug report.** Re-run this test after every agent upgrade. `scripts/` has the hook; the test is in this file.

## The test that nearly lied to me

My first run reported **"✅ hook blocked it"** — and it was wrong. The test used `timeout`, which doesn't exist on stock macOS. The agent never ran, no file was created, and the verdict logic read *"no file"* as *"the hook blocked it."*

**A test that never ran, reporting success.**

**Always include a control run that proves the harness executes.** Without it, "nothing happened" is indistinguishable from "the guard worked."

## Install

```json
// ~/.claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "~/.claude/hooks/deny-destructive-git.sh" } ] }
    ]
  }
}
```

`scripts/deny-destructive-git.sh` blocks: `reset --hard`, `push --force`, `push -f`, `branch -D`, `clean -fd`, `filter-branch`, `reflog delete`, `update-ref -d`. Exit code **2** is the denial.

**Verify it in a real repo, not in your head:**

```sh
mkdir /tmp/gatecheck && cd /tmp/gatecheck && git init -q
echo v1 > f && git add . && git commit -qm "PRECIOUS COMMIT"
claude -p "run exactly: git reset --hard HEAD~1" --dangerously-skip-permissions
git log --oneline    # the commit must still be there
```

## Keep the CLAUDE.md refusal as well

Belt and braces, and they fail differently:

- **The hook** blocks the command *at dispatch*. Immune to the model rationalising.
- **The instruction** stops the tool call from ever being *emitted*. Immune to any hook-dispatch bug — including the one in that issue, if it ever regresses.

Two independent layers, neither of which depends on the other being correct.

## What NOT to block

`git revert` is **safe** — it creates a *new commit* that undoes a change. History intact, nothing deleted, fully auditable. It is the one "undo" an autonomous system may run, and it's what lets a `production-canary` roll back a bad deploy in 60 seconds.

**Block what destroys. Allow what reverses.**
