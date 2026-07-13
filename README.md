# Relay Skills — running an AI agent unattended, without losing your work

```sh
npx skills add jeremyinthebay/relay-skills
```

## There are already good skills for running an agent in a loop. This is not one of them.

If you want an autonomous loop, **install [`ralph-wiggum`](https://skills.sh/fstandhartinger/ralph-wiggum/ralph-wiggum) or [`ralph-tui`](https://skills.sh/subsy/ralph-tui/ralph-tui-prd)** — feed an agent a task list, let it work through the items, commit what passes, retry what fails. They're mature, they're simpler than this, and the loop itself was not invented here.

**This is what you install after that loop has hurt you.**

Two things here that the others don't have:

### 1. A second agent that can veto the first

The executor **commits but never merges.** The reviewer **merges but never commits.** Neither ships alone, and the reviewer verifies the result **independently, in a real browser** — it never takes the executor's word.

This matters because **an agent checking its own work grades its own homework.** On our first run the executor's test came back perfectly clean — while measuring elements inside a `display:none` container. A single-agent loop ships that false green and tells you it's done. Ralph is single-agent and self-verifying by design (*"you have full autonomy, don't wait for approval"*), which is exactly where this bites.

### 2. The part that keeps it from destroying things

Other loop skills **name** these failure modes. [`everything-claude-code`](https://skills.sh/affaan-m/everything-claude-code) even has a Failure Modes section that calls out *"cost drift from unbounded escalation."* **None of them ship the mechanism** — no watchdog, no backups, no kill switch, no reconciled budget.

Every row below exists because something actually broke:

| | |
|---|---|
| **A watchdog** | The loop went silent for four hours and looked exactly like a quiet successful night. A stall, a dead host and a finished run all produce the same output: nothing. |
| **A cost ceiling** | 49 pushes in one day, most of them the loop's own bookkeeping, each triggering a full deploy. The build quota ran out. **The host paused the site — production was down for four hours,** and the previews died with it, so the review loop deadlocked too. Ralph's error handling is *"retry with exponential backoff,"* which is precisely the behavior that did this. |
| **Backups against your own robot** | GitHub covers *pushed* commits. Not the 40 minutes of uncommitted work in the tree. Not a `reset --hard` before a push. **The threat model isn't "GitHub vanishes" — it's "my automation deletes my work."** |
| **A destructive-git refusal** | A task once instructed `git reset --hard` on the only copy of a finished feature, with a confident explanation attached. A human hit Deny. That was the entire safety system. Now the executor refuses, even when told. |
| **A kill switch that actually works** | Ours didn't. The watchdog deleted it within 60 seconds. |

**They're better at the loop. This is better at surviving it.**

---

## What it cost to learn this

The loop described here ran in production. It also:

- took the site down for **four hours** by exhausting a build quota nobody was watching
- **deadlocked twice**, permanently, in ways that survived the original problem being fixed
- shipped a watchdog broken *in exactly the way it was written to prevent* — 259 errors into a log nothing read
- came **one click away from `git reset --hard`** on the only copy of a finished feature

**Every rule here is scar tissue.** Copy the architecture; skip the tuition.

---

## The skills

| Skill | What it's for |
|---|---|
| **`two-claude-relay`** | The architecture. Two agents, two files in a git repo, a 60-second poller. The division of authority that makes it safe: *the executor can commit but never merge; the planner can merge but never commit.* |
| **`autonomous-loop-safety`** | The rules. Watchdogs, kill switches, cost ceilings, retry caps, backups, and the failure modes that silently destroy work or money. **Read this one even if you use none of the rest.** |
| **`agent-preflight`** | Forcing every permission dialog and environment assumption to surface *now*, in front of a human — instead of at 3am when the loop stalls silently. |
| **`adversarial-audit`** | Pointing a fresh, skeptical agent at your system to find the bugs before your users do. Ours found ten in six minutes, after days of a human finding them one at a time. |
| **`destructive-git-hook`** | A `PreToolUse` hook that **mechanically** blocks `reset --hard`, `push --force`, `branch -D`. A model can talk its way past a paragraph in `CLAUDE.md` — one did, on the only copy of a finished feature. It cannot talk its way past a hook. **Includes a tested answer to whether hooks actually block under `--dangerously-skip-permissions`: they do.** |
| **`production-canary`** | After every merge, prove production still works — and **`git revert` it automatically if it doesn't.** This is what makes auto-merge survivable: a loop that can undo itself in 60 seconds can afford to move fast. |
| **`autonomous-loop-safety`** (updated) | Now also ships the guardrails that **turn on you**: a retry cap that counted polls instead of attempts and halted a loop that had failed zero times; a gate whose only exit was the thing it blocked (a deadlock a human had to break); and `pr-gate.sh` — the merge preconditions as **code**, with a test suite whose control proves it still refuses a failing PR. |
| **`mobile-verification`** | Test what a page actually **does** on a phone — real taps, real scrolling, real animations. Most automation tabs are **hidden**, so `requestAnimationFrame` never ticks and *smooth scrolling silently never moves* — which made us report a production outage that did not exist. Playwright is not blind. |

Install all seven, or cherry-pick:

```sh
npx skills add jeremyinthebay/relay-skills
```

---

## The five ideas that matter most

**1. Two agents, because one grades its own homework.**
An agent verifying its own work knows what it *meant* to do, so it tends to see what it meant to do. On the first run, the executor's test came back perfectly clean — while measuring elements inside a `display:none` container. A separate reviewer, with no memory of writing the code, has no such loyalty.

**2. "Verified" is a failing answer.**
Every task carries a verification bar, and the report must contain **real pasted command output**. If the agent can't show you the output, it didn't run the command. This single rule catches more than any amount of prompting about being careful.

**3. Silence must never look like health.**
A stalled build, a paused host, and a dead watcher all produce output identical to a quiet successful night: nothing. Build a watchdog whose only job is to say *"I'm stuck."* Its twin: **noise must never drown the signal** — a bot that says "nothing to do" 96 times a day is a bot you mute, and then you miss the one that mattered.

**4. You cannot reason your way out of a racy read.**
Two agents sharing one git working tree corrupted a branch mid-build. The first fix was a *rule* telling the reviewer to check more carefully — aimed at the wrong layer entirely. It guards a bad **inference**; the cause was a corrupted **observation**. The real fix is structural: the reviewer may never run a local git write, and must stop dead if the executor's lock is held.

**5. Back up what your automation can destroy, not what the remote already has.**
GitHub covers *pushed* commits. It does not cover the 40 minutes of uncommitted work in the tree, or a `reset --hard` before a push, or `--delete-branch` eating an unpushed commit. **The threat model isn't "GitHub vanishes." It's "my own robot deletes my work."**

---

## The meta-finding

**Every single bug this system had was already visible in a file on the machine.**

`stderr` had 259 unread errors. The main log had the executor plainly announcing that its branch had reverted — the exact root cause of the near-disaster, in plain English, hours before anyone noticed.

The instrumentation was excellent. **Nothing was reading it.**

Before you add more logging, make something *read* the logging you already have.

---

## Honest warnings

**`--dangerously-skip-permissions` is load-bearing and it is dangerous.** A headless agent cannot answer a permission prompt, so without it the loop deadlocks on the first git command. With it, an unattended model runs shell commands with no approval step while holding push access to a live site. Scoped to a folder, **not sandboxed**.

That trade was taken deliberately, on a low-stakes repo with no secrets in it. **It is not a default.** Don't point this at anything you'd be upset to lose — and if you do, read the backup and destructive-git sections twice.

**Auto-merge is a separate decision from autonomy.** Ask for it explicitly. Don't infer it from "make it autonomous."

**The loop is excellent at "prove zero overflow at 390px." It cannot tell you whether one design feels better than another.** Keep a human gate for judgment calls, and be honest with yourself about which is which.

---

## Install these alongside it — they're better than what we built

Not politeness. Two of these solve problems we solved *worse*:

- **[`obra/superpowers`](https://skills.sh/obra/superpowers/using-git-worktrees) → `using-git-worktrees`.** Two agents sharing one git working tree is the bug that nearly destroyed a finished feature here. Worktrees are the clean, standard answer — **and we reinvented a worse one** (a lockfile plus a rule politely asking the reviewer to behave) because we never checked whether the problem was already solved.
- **`obra/superpowers` → `verification-before-completion`.** States our core rule better than we did: *"No completion claims without fresh verification evidence... claiming work is complete without verification is dishonesty, not efficiency."*
- **[`ralph-wiggum`](https://skills.sh/fstandhartinger/ralph-wiggum/ralph-wiggum)** — its specs carry a **Completion Signal**: an explicit checklist that makes "done" machine-checkable instead of a judgment call. Our early tasks said things like *"make it responsive,"* which is a vibe, not a finish line — and we got exactly what we asked for.
- **[`vercel-labs/skills`](https://skills.sh/vercel-labs/skills/find-skills) → `find-skills`.** Lets an agent discover skills mid-session. The meta-fix for *"I didn't know that existed"* — which is how we ended up rebuilding worktrees badly.

```sh
npx skills add obra/superpowers
npx skills add vercel-labs/skills
```

## Requirements

An agent CLI that runs headless (`claude -p` or equivalent) · a shell/filesystem MCP that can see your **real** repo and has `gh` on PATH (verify this — a sandboxed shell that only sees a mount will fail silently) · `gh` + git, authenticated non-interactively · a scheduler (launchd/cron) · a host with per-PR deploy previews, so the reviewer has something real to verify against · a notification channel you'll actually see.

## License

MIT. The scripts are the real ones, genericized. They have all failed at least once, which is why they look the way they do.
