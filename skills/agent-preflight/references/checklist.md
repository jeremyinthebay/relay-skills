# Preflight checklist

Run every item **in front of a human**, before the loop is ever trusted alone. Approve every dialog that appears, choosing the broadest option offered.

## Environment

- [ ] **Every binary resolves under the SCHEDULER's PATH**, not your shell's. `launchd` and `cron` give you a minimal PATH. A binary that works in Terminal and is missing under the scheduler is the classic silent killer. Check: `claude`, `gh`, `git`, `node`, `curl`, `osascript`, `shasum`, `jq`.
- [ ] **The agent CLI actually runs headless.** Not "the binary exists" — invoke `claude -p "reply OK"` and check it returns. Run it in a **temp dir**, not the repo: two agents doing git operations in one working tree is a real way to corrupt a run.
- [ ] **`timeout` exists?** It doesn't, on stock macOS — that's GNU coreutils' `gtimeout`. Use `perl -e 'alarm N; exec @ARGV'` instead. (Our preflight caught this about itself.)

## Auth — a credential prompt at 3am is a dead loop

- [ ] `gh auth status` succeeds non-interactively
- [ ] `git ls-remote origin` succeeds without prompting
- [ ] The repo is writable, and the branch you'll push to isn't protected in a way that blocks the agent

## The shell your scheduled agent actually gets

**This is the one everyone misses.**

- [ ] **Can it see the REAL repo** — or only a sandboxed mount?
- [ ] **Does it have `gh` on PATH?**

A scheduled session may get a sandboxed shell with neither. Meanwhile a desktop-control MCP runs on the actual machine and has both. Our instructions told the reviewer to *avoid* the desktop MCP and use the sandboxed shell — guidance written from an early run where that was true. By the time permissions were granted, it had become a lie, and an agent following it literally would have failed its state check and its merge, **silently**.

> **Re-verify the environment assumptions baked into your prompts — not just the permissions.** Guidance written from one failed run becomes a lie the moment the environment changes.

## Permissions

- [ ] **The front door:** Settings → Extensions → [shell MCP] → Tool permissions → **"Always allow"** on each group. This grants the whole set up front instead of one dialog at a time.
- [ ] **Every distinct TOOL exercised by name.** `start_process` does not grant `read_file` or `write_file`. Touch each one.
- [ ] **Browser tools** — navigate, execute-JS, screenshot are all separate.
- [ ] **Notification tools** — this is the one that throws an OS Automation dialog. **Send a real test message.**
- [ ] **Every tool the agent will only reach on a rare path** — e.g. the Slack tool that only fires on a run where something merged. Those are the ones that ambush you three days later.
- [ ] On each dialog, choose **"Allow for all tasks"** (usually under a dropdown), not the narrower default button.

## Network

- [ ] Production URL reachable
- [ ] Your git host's API reachable
- [ ] No captive portal / proxy prompt waiting to ambush a 3am run

## The loop's own machinery

- [ ] Scheduler agent is loaded (`launchctl list | grep <label>`)
- [ ] Every script is executable (`+x`) and **parses** (`zsh -n script.sh`)
- [ ] The **kill switch** works — and **the watchdog does not delete it.** (Ours did, within 60 seconds.)
- [ ] `stderr` is **empty**. If your scripts are erroring on every poll, you want to know now, not in 259 unread lines.

## Finally

- [ ] **Run the preflight and read the output.** A preflight that has never failed has never been tested. Ours found two bugs in itself on the first run.
