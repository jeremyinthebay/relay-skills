---
name: adversarial-audit
description: Point a fresh, skeptical agent at a system you built and have it hunt for the ways it silently loses work, deadlocks, lies about its own state, or spends money — before your users find them for you. Use when a project keeps producing bugs found by humans, before trusting anything to run unattended, after an incident, when reviewing your own automation or infrastructure, or when someone says "we keep finding bugs one at a time" or "how do I know this is actually safe."
---

# Adversarial Audit

If a human keeps finding your bugs one at a time, **you don't have a system with checks and balances — you have a person doing QA for a robot.** That doesn't scale, and it burns their trust.

The fix is cheap: **point an agent that built none of it at the thing, hand it the failure history, and tell it to be skeptical rather than reassuring.**

Ours found **ten bugs, four critical, in about six minutes** — after days of the human finding them one at a time.

## Why a fresh agent beats the one that built it

An agent reviewing its own work grades its own homework. It knows what it *meant* to do, so it sees what it meant to do. It is also, subtly, invested in the work being good.

A separate agent — separate context, no memory of writing the code, no stake in it being correct — has none of that loyalty. **It is the only party in the system with no interest in the answer being "it's fine."**

## How to run one

### 1. Give it the failure history — this is the highest-leverage input

Don't just say "review this code." Say:

> *"This system has already exhausted a build quota and took production down for four hours. It deadlocked twice. It shipped a watchdog that was broken in exactly the way it was written to prevent. It came one click away from running `git reset --hard` on the only copy of a finished feature. Assume there are more bugs of this class. Find them."*

**The failure history is the best prior for where the next bug lives.** Systems fail in families.

### 2. Tell it explicitly not to be reassuring

Agents default to helpfulness, and helpfulness reads as "this looks solid overall, here are some minor nits." That is useless. Ask for the opposite:

> *"Be adversarial. I do not want reassurance. For each component, answer: how does this silently lose work? How does it deadlock? How does it lie about its own state? How does it spend money without telling me? What does it do when a dependency fails — does it fail open or closed?"*

### 3. Give it the artifacts, not a description

Every script, every prompt, every config, every log. **Especially the logs.** Which brings us to the finding that mattered most.

## The finding that mattered most

**Every single one of the ten bugs was already visible in a file on the machine.**

- `stderr` held **259 unread errors** — the watchdog throwing on *every poll*, meaning the safety detector it existed for may never have been able to fire.
- The main log held the executor plainly stating that its branch *"silently reverted to main partway through"* — the exact root cause of the near-disaster, written in plain English, hours before anyone noticed.

**The instrumentation was excellent. Nothing was reading it.**

> Before you add more logging, make something *read* the logging you already have. Then have the audit read it too — it's where the bugs are already written down.

## What to ask it to look for

These are the categories that actually bite, in rough order of how much they cost us:

**Shared mutable state between agents.** Two processes, one working tree, no mutual exclusion. *You cannot reason your way out of a racy read* — no amount of "check carefully first" fixes it. Look for structural exclusion, not rules.

**Fail-open safety gates.** When the check itself errors, what happens? Ours returned "0 open PRs" when `gh` failed — which read as "all clear, proceed."

**Record-before-verify.** Anything that marks work as "seen/done/handled" *before* it has actually acted on it. This deadlocks permanently and survives the original problem being fixed.

**Monitors that can't report their own death.** A status view that prints "✅ Idle · healthy" for the exact state of a wedged loop. A liveness check inferred from a signal that goes quiet when the system is busiest.

**Monitors that observe their own output.** Ours grepped its log for "warning" — and its own alerts land in that log containing the word "warning."

**Unbounded retries and unbounded spend.** A failing task that rebuilds every 60 seconds, forever, and only luck stops it.

**Kill switches that don't kill.** Ours was deleted by the watchdog within 60 seconds of being set.

**Bugs you already fixed, re-shipped.** Three of our ten were exactly this — the *same* bug, reintroduced inside the code written to fix it. **After fixing anything, grep every other file for the same pattern.**

## Do it on a schedule, not just after a disaster

The point isn't a one-off cleanup. It's that **the human should stop being the bug-finder.** Run it after any significant change to the automation, and always before extending trust — more autonomy, a bigger blast radius, a longer unattended window.

## The uncomfortable part, and why you want it

Three of the ten bugs were ones we had **already found and fixed** — reintroduced in the very code written to prevent them. The safety net had a hole in exactly the shape of the thing it was catching.

You will not enjoy reading that report. That is what makes it worth running.
