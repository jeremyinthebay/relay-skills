---
name: agent-preflight
description: Force every permission dialog, auth prompt, and environment assumption to surface NOW, while a human is watching — instead of at 3am when the agent stalls silently and nobody can click Allow. Use this before letting any agent run unattended, scheduled, headless, or overnight. Also use when an agent mysteriously stops mid-run, when a scheduled task behaves differently from an interactive one, when someone is drowning in repeated permission prompts, or when a background job "just doesn't do anything."
---

# Agent Preflight

Permissions are **lazy**. A macOS TCC dialog or an agent tool-approval prompt fires the *first time a process actually does the thing*. In an interactive session that's invisible — you click Allow and move on.

In an autonomous loop, **"the first time" is 3am, with nobody there to click Allow.** The loop stops. Silently. It looks exactly like "no work to do."

**A preflight forces every one of those moments to happen now, in front of a human.**

## The front door (do this first — most people miss it)

Before clicking through dialogs one at a time, check whether your agent's settings let you grant a whole tool group at once:

> **Settings → Extensions → [your shell/filesystem MCP] → Tool permissions → "Always allow"** on each group (Interactive, Read-only, Write/delete).

This grants the entire set **up front** instead of waiting for each individual tool to prompt on first use. We found this embarrassingly late, after days of dialog-clicking.

**Be clear-eyed about what's in there:** Kill Process, Force Terminate, Write/Modify, Move/Rename. Real teeth. That is the genuine cost of an unattended loop — grant it deliberately, on a machine and a repo where you accept it.

## Every distinct TOOL prompts separately

Not every app — every **tool**. Granting a shell MCP's `start_process` does **not** grant its `read_file` or `write_file`. And a prompt only fires when a run actually *reaches* that step — so the notification tool's dialog won't appear until a run finally has something to report.

**Approvals therefore dribble out over days**, and you never know when you're done. A preflight collapses that into ninety seconds.

## Pick the broadest option offered

On approval dialogs, the options usually mean very different things:

- **"Allow once"** — persists nothing. Guarantees a 3am stall.
- **"Allow for all runs of this task"** — often the big default button. Only covers *that one task*. Every other task re-asks for the same tool.
- **"Allow for all tasks"** — usually hidden under a dropdown. **This is the one that ends it.**

## Some prompts have no "always allow" — and that is correct

Changing a scheduled task's own *configuration* asks a human every single time. **Don't try to defeat this.** Something that runs unattended should not be silently reprogrammable by another agent.

It also never stalls the loop — it only fires while you're sitting there. So **design around it**: make the scheduled task a thin permanent bootstrap (*"read `INSTRUCTIONS.md` and follow it"*) and keep all the volatile logic in a file the agent can revise freely. Keep the safety guarantees in the prompt, where a file-writer can't edit them away.

## What a preflight must actually check

Run `scripts/preflight.sh` (adapt it) and approve everything it surfaces.

**Binaries under the scheduler's PATH.** `launchd` and `cron` give you a minimal PATH — not your shell's. A binary that works in your terminal and is missing under the scheduler is a classic silent killer.

**Non-interactive auth.** `gh auth status`, `git ls-remote`. A credential prompt at 3am is a dead loop.

**The headless agent actually runs.** Not "the binary exists" — actually invoke `claude -p` and check it returns.

**The notification path.** This is the one that throws an OS Automation dialog. Send a real test message.

**The environment assumptions baked into your prompts.** See below — this is the one everyone forgets.

## The trap nobody warns you about: your agent's shell may not see your repo

A scheduled agent session may get a **sandboxed shell that only sees a mount, not the real filesystem — and has no `gh` on PATH.** Meanwhile a different tool (a desktop-control MCP) runs on the actual machine and has everything.

My instructions told the reviewer to *avoid* the desktop MCP and use the sandboxed shell. **Written after an early run where the opposite was true.** By the time permissions were granted, that guidance had become a lie — and an agent following it literally would have failed its state check and its merge step, **silently**.

The preflight caught it. Nothing else would have.

> **Verify your shell can see the real repo and has the binaries — don't assume which shell a scheduled session gets.**

And the general form, which is the real lesson:

> **Guidance written from one failed run becomes a lie the moment the environment changes.** A preflight should re-verify the *environment assumptions* in your prompts, not just the permissions.

## A preflight that has never failed has never been tested

Mine found **two bugs in itself** on its first run:

- `timeout` doesn't exist on stock macOS (that's GNU coreutils' `gtimeout`)
- it was invoking `claude -p` **inside the repo where the executor was mid-build** — two agents doing git operations in one working tree

Both would have produced confusing failures later. **Run it. Believe the output, not the intent.**

## Reference files

- `scripts/preflight.sh` — a working preflight; adapt the checks to your stack
- `references/checklist.md` — everything to verify before you walk away
