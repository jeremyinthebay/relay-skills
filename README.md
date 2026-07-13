# Relay Skills — running an AI agent unattended, without losing your work

[![skills.sh](https://skills.sh/b/jeremyinthebay/relay-skills)](https://skills.sh/jeremyinthebay/relay-skills)

```sh
npx skills add jeremyinthebay/relay-skills
```

Four skills for building an **autonomous agent loop**: one agent plans and reviews, another executes, and neither can ship alone.

This isn't a "best practices" collection. **It's a list of the twenty-four ways an unattended agent loop actually broke, and the code that stops each one.**

The loop described here ran in production. It also:

- took the site down for **four hours** by exhausting a build quota nobody was watching
- **deadlocked twice**, permanently, in ways that survived the original problem being fixed
- shipped a watchdog that was broken *in exactly the way it was written to prevent* — 259 errors into a log nothing read
- came **one click away from `git reset --hard`** on the only copy of a finished feature, with a confident explanation attached

Every rule in here cost something. Copy the architecture; skip the tuition.

---

## The skills

| Skill | What it's for |
|---|---|
| **`two-claude-relay`** | The architecture. Two agents, two files in a git repo, a 60-second poller. The division of authority that makes it safe: *the executor can commit but never merge; the planner can merge but never commit.* |
| **`autonomous-loop-safety`** | The rules. Watchdogs, kill switches, cost ceilings, retry caps, backups, and the failure modes that silently destroy work or money. **Read this one even if you use none of the rest.** |
| **`agent-preflight`** | Forcing every permission dialog and environment assumption to surface *now*, in front of a human — instead of at 3am when the loop stalls silently. |
| **`adversarial-audit`** | Pointing a fresh, skeptical agent at your system to find the bugs before your users do. Ours found ten in six minutes, after days of a human finding them one at a time. |

Install all four, or cherry-pick:

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

## Prior art, and what's actually new here

**The autonomous loop itself is not a new idea.** There's an established family of these — the *"ralph loop"* ([`fstandhartinger/ralph-wiggum`](https://skills.sh/fstandhartinger/ralph-wiggum/ralph-wiggum), [`subsy/ralph-tui`](https://skills.sh/subsy/ralph-tui/ralph-tui-prd), [`andrelandgraf/fullstackrecipes`](https://skills.sh/andrelandgraf/fullstackrecipes/ralph-loop)) — feed an agent a task list, let it work through the items, commit what passes, retry what fails. If you just want a loop, start there; they're simpler than this.

**Two things here are different, and they're the only reasons to prefer this:**

1. **The two-agent review split.** The executor commits but never merges; the reviewer merges but never commits; and the reviewer **independently verifies in a real browser** rather than trusting the executor's report. An agent checking its own work grades its own homework — this is the structural fix for that.

2. **The safety layer**, which is most of what's here. The watchdog, the cost ceiling, the retry cap, the kill switch, the backups, the destructive-git refusal, and the 24 failure modes that produced them. **This is the part that was expensive to learn.**

## Skills you should install alongside this

Genuinely — some of these would have saved us:

- **[`obra/superpowers`](https://skills.sh/obra/superpowers/using-git-worktrees)** → `using-git-worktrees`. **Install this.** Two agents sharing one git working tree is the bug that nearly destroyed a finished feature here. Worktrees are the clean, off-the-shelf answer, and we reinvented a worse one (a lockfile and a rule) because we didn't look first.
- `obra/superpowers` → `verification-before-completion`, `systematic-debugging`, `requesting-code-review`
- **[`vercel-labs/skills`](https://skills.sh/vercel-labs/skills/find-skills)** → `find-skills`. Lets an agent discover skills mid-session — the meta-fix for *"I didn't know that existed."*

```sh
npx skills add obra/superpowers
npx skills add vercel-labs/skills
```

## Requirements

An agent CLI that runs headless (`claude -p` or equivalent) · a shell/filesystem MCP that can see your **real** repo and has `gh` on PATH (verify this — a sandboxed shell that only sees a mount will fail silently) · `gh` + git, authenticated non-interactively · a scheduler (launchd/cron) · a host with per-PR deploy previews, so the reviewer has something real to verify against · a notification channel you'll actually see.

## License

MIT. The scripts are the real ones, genericized. They have all failed at least once, which is why they look the way they do.
