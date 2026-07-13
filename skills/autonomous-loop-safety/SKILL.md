---
name: autonomous-loop-safety
description: The safety rules for any agent that runs unattended — watchdogs, kill switches, cost ceilings, retry caps, backups, and the failure modes that silently destroy work or money. Use this whenever an agent will run without a human watching: scheduled tasks, cron jobs, background loops, overnight builds, self-merging pipelines, or anything using --dangerously-skip-permissions. Also use when a loop has stalled, deadlocked, gone silent, burned through a quota, or when someone asks "how do I know it's still working" or "how do I stop it safely."
---

# Autonomous Loop Safety

Every rule here is scar tissue from a loop that ran unattended and broke something. None of them were obvious in advance.

The failure modes are not the ones you expect. The agent doesn't go rogue. **It quietly stops, or quietly lies, or quietly spends your money — and nothing tells you.**

## The four that actually cost us

### 1. Silence must never look like health

The loop could only report *verdicts*. So a stalled build, a paused host, and a dead watcher all produced output identical to a healthy quiet night: **nothing at all.** It sat dead for four hours and looked exactly like it was working.

**Build a watchdog whose only job is to notice trouble and say so.** Host down, quota exhausted, PR stuck past N minutes, work item that never started, *and its own stderr*. Dedupe alerts (once an hour per condition) so it warns without becoming noise.

**Its twin, equally important:** *noise must never drown the signal.* A checker that posts "nothing to do" every 15 minutes is a channel you mute — and then you miss the one that mattered. **Alert on trouble. Stay quiet on routine.**

### 2. A quota is not a safety mechanism you discover by hitting it

The loop pushed 49 commits in one day. Every push triggered a host build. But most of those commits were the loop's own bookkeeping — status files nobody serves — and each one spun a full deploy of a static site that hadn't changed.

The build quota ran out. The host paused the site. **Production went down for four hours, and because the deploy previews died with it, the review loop deadlocked too.** One failure took out both the product and the machinery watching the product.

**Set a budget before you start, not after you hit the ceiling.** A daily build cap and a per-task retry cap, both of which *halt the loop and alert you* rather than grinding. And skip builds when nothing that ships has changed:

```toml
# netlify.toml — `ignore` runs BEFORE the build. Exit 0 = skip entirely, consume nothing.
[build]
  ignore = "git diff --quiet $CACHED_COMMIT_REF $COMMIT_REF -- index.html"
```

### 3. Record state LAST, and fail closed

Two failures, same root:

**The reviewer hashed a report as "seen" *before* verifying it.** When the deploy preview 404'd, it correctly refused to merge something it couldn't check — but had already consumed the report, so it would never look again. Permanent deadlock, surviving even after the host came back.

**`gh` failing returned "0 open PRs"** — which the loop read as "the PR merged, start the next one." The safety gate **failed open**. An empty answer from a source that wasn't looking is not an answer.

```sh
# Fail closed: distinguish "no PRs" from "couldn't ask."
if ! PRJSON=$(gh pr list --state open --json number 2>&1); then
  alert "Can't reach GitHub — not promoting the next task."
  exit 1
fi
```

### 4. You cannot reason your way out of a racy read

Two agents shared one git working tree. The reviewer ran `git checkout main` on its 6-minute cycle while the executor was 39 minutes into a build. **HEAD moved under it.** The executor's commits landed on the wrong branch — and it *said so in its log*, which nothing was reading.

The reviewer then read that half-written tree, concluded the work was "stranded," and wrote a recovery brief:

```sh
git checkout feature-branch
git reset --hard main      # would have DELETED the only copy of the feature
```

A human hit Deny on an approval dialog. That was the entire safety system.

**The first fix was a rule** — *"check four things before writing a recovery brief."* **That was aimed at the wrong layer.** It guards against a bad *inference*; the cause was a corrupted *observation*.

**The real fix is structural:**
- The reviewer may **never** run a local git write command. It doesn't need one — `gh pr merge` is server-side.
- Any agent must **stop entirely** if the executor's lock is held.
- **The executor refuses destructive git even when a task tells it to.** A file must never be able to authorize `reset --hard`. See `references/destructive-git.md`.

## Backups: your remote does not have you covered

GitHub covers *pushed* commits. It does not cover:

- the 40 minutes an executor has uncommitted work in the tree
- a `reset --hard` that deletes local commits before they're pushed
- `gh pr merge --delete-branch` eating a branch that still holds an unpushed commit

**Those are the exact three things the automation nearly did.** The threat model isn't "the remote vanishes." It's **"my own robot deletes my work."**

Snapshot before every run: a `git bundle` (every ref, fully cloneable) *plus* a tarball of the working tree **including uncommitted changes**. Timestamped, read-only, pruned by age — never by count, so a burst of activity can't evict the snapshot you need. `scripts/backup.sh` does this.

**And verify it by restoring it, not by checking the file exists.** A backup you haven't restored is a rumour.

## The kill switch must be honored by everything

`touch .stop` should halt the loop until a human removes it. Mine didn't work — **the watchdog deleted it within 60 seconds.**

Keep two separate flags: one the *automation* manages (auto-clears when the condition resolves) and one only a *human* clears (permanent until removed). Never let code delete the human's flag.

## Monitors that lie are worse than no monitors

**A monitor must never observe its own output as an input.** Mine grepped its log for "warning" — and its own alerts land in that log and contain the word "warning." It alerted on its own alert, forever, texting me each time.

**A monitor must never contradict itself.** Mine inferred "the watcher is dead" from log silence — but the watcher correctly goes quiet *during* a long build. It texted "🔴 the loop is dead" and then printed the running build's ETA on the very next line.

Emit liveness **directly** — touch a beacon file every poll, before any early exit. Never infer it from side effects that fall silent exactly when the system is busiest. **A false alarm teaches you to ignore alerts, and then you ignore the real one.**

## The meta-rule

**Every bug in this system was already visible in a file on the machine.** `stderr` had 259 unread errors — the watchdog itself throwing on every single poll, meaning the paused-host detector it existed for may never have been able to fire. The executor's log plainly stated its branch had reverted, hours before anyone noticed.

**The system didn't need better instrumentation. It needed to be forced to read the instrumentation it already had.** Make the watchdog read its own stderr and the executor's warnings, and alert on both.

## And one for the human

**The rules apply to the person writing the rules.** I built the lock, documented it, forbade the reviewer from ignoring it — then wrote into the executor's tree mid-build myself, because I was "just making a quick edit." The lock caught me.

A guardrail only works if *everything* that touches the resource checks it. Including you.

## Reference files

- `references/destructive-git.md` — the executor-side refusal, ready to paste into `CLAUDE.md`
- `references/rules.md` — all 24 rules, grouped, with what each one cost
- `scripts/watchdog.sh` — alerts on stalls, host failure, its own stderr
- `scripts/backup.sh` — bundle + worktree snapshots, verified by restore
