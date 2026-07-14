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

**A throttle keyed on a volatile string is not a throttle.** Mine deduped alerts by hashing the whole message — but the message carried the PR's live age (`"open 78m"`), so every minute produced a new hash and the once-an-hour throttle never fired. One stuck PR sent 78 identical alerts in an hour and evicted the one that mattered from the heartbeat's last-three panel. Dedup on the alert *class*: strip the volatile parts (ages, counts, HTTP codes) before hashing.

**A queue nothing drains is a silent leak.** Two alert sinks were appended every tick and drained by an agent that had been replaced months earlier. They grew unbounded and unread — and nothing errored, which is exactly why no one noticed. Bound them (ring-buffer to a last-N) and surface their depth where a human already looks. "Silence must never look like health" applies to your own plumbing, not just the product.

**Retire a request only after the work is verified, never before.** The inbound handler filed each request as "handled" the instant it started, then only *logged* the exit code — so a failed run dropped the user's message silently. This is rule 3 (record state LAST) one directory over: archive on success, retain-and-retry on failure, dead-letter after N tries so a poison message can neither spin forever nor vanish.

**The meta — a fix isn't a lesson until it's a tested invariant.** An adversarial audit found all three of the above in the alert layer, and every one was a lesson the core loop had *already* learned and written down. They regressed because the original fixes were point-patches with no test to catch a recurrence elsewhere. A lesson that lives only as a corrected line in one script is a coincidence in one location. Each of these now ships with a test that goes **red** against the old logic — that, not more care, is what makes a fix stick.

## The meta-rule

**Every bug in this system was already visible in a file on the machine.** `stderr` had 259 unread errors — the watchdog itself throwing on every single poll, meaning the paused-host detector it existed for may never have been able to fire. The executor's log plainly stated its branch had reverted, hours before anyone noticed.

**The system didn't need better instrumentation. It needed to be forced to read the instrumentation it already had.** Make the watchdog read its own stderr and the executor's warnings, and alert on both.

## When the guardrail itself is the bug

Everything above is about building guardrails. This section is about the day they turn on you — which they will, and which nobody warns you about.

### A guardrail that fires when nothing is wrong is not "safe". It is broken.

Our retry cap halted the loop for a task that **had not failed even once.**

The executor ran, succeeded, opened a PR, and correctly left the task OPEN — the reviewer decides when work is done, not the executor. The next two polls never invoked the executor at all: they saw the open PR, logged *"waiting for it to merge"*, and exited. But the counter was incremented **above** that check, on the way past.

```
poll 1  executor runs, opens PR      attempts = 1
poll 2  never runs it (PR is open)   attempts = 2   <-- counted anyway
poll 3  never runs it (PR is open)   attempts = 3   <-- counted anyway
poll 4  "task failed 3 times" -> HALT
```

**An attempt that never invoked the executor is not an attempt.** Count the thing you are capping, at the moment you actually do it — in `scripts/watch.sh`, the increment sits immediately above the `claude -p` call and nowhere else.

Leaving a misfiring guardrail alone *feels* cautious. It isn't. It converts a healthy system into a halted one **and then blames the work.**

### A gate whose only exit is the thing it's blocking is a deadlock

One rule said *never invoke the executor while a PR is open* — otherwise a retry opens a duplicate PR. Sound.

Then a PR passed review but couldn't merge (stale branch, `CONFLICTING`). The fix was one push to that branch, and **only the executor can push.** So the reviewer wrote a task telling the executor to fix it — which the gate refused to run, because a PR was open. **The task that existed to repair the PR was blocked by the PR.** A human had to reach in.

**Every blocking gate needs an escape hatch for the case that repairs the blocked state.** Ours: a task may declare `Target-PR: #24` in its header and the gate lets exactly that one through. Ordinary tasks stay blocked, so the duplicate-PR guarantee survives. It's ~6 lines in `scripts/watch.sh`, and `tests/watch-retry-cap.test.sh` proves both halves — the hatch opens for the named PR, and does **not** open for a different one.

**When you write a gate, ask: what fixes the state this blocks, and can that thing still run?**

### Which failures are yours to fix, and which are the human's to decide

The owner, halfway through a long session: *"I feel like it's keeping me more in the loop and asking me too many questions vs actually being autonomous as possible."*

The bug was a collapsed distinction:

```
guardrail is MISFIRING      -> a BUG.      Fix it. Prove it. Report it. Don't ask.
guardrail's POLICY changes  -> a JUDGMENT. Raise the ceiling? Relax the merge bar?
                                           Allow force-push? That is the human's call.
```

**Asking about a bug is not caution, it's abdication** — it hands a human a decision with only one correct answer, usually at 3am. Quietly changing a *policy* because it seemed sensible is the opposite failure. Autonomy is not "acts without asking"; it's **knowing which things it doesn't need to ask about.**

The price of fixing your own guardrails is a high proof bar, and it is *yours* to meet: a test **and a control**, a backup first, the diff shown afterward.

### A control that passes for the wrong reason is a false pass

A test that has never failed cannot be trusted — but here's the sharper version.

Writing the merge gate, I added the control: *"a report that says FAIL must be refused."* It refused. Green tick. **But it refused because the test fixture had no git remote** — the gate never read the verdict at all. Had the verdict logic been broken, that control would still have been green.

**A control must fail for the reason you named, and pass for the reason you named.** Make it print *why* it refused, and read that — don't assert on the exit code alone.

Its mirror image, same hour: my first instinct was to grep the status file for the word `FAIL`. That would have refused a **healthy** report — a good report says things like *"the control run against production failed all 3 checks, so we know the test can fail."* **Describing a control working correctly is not a failure.** `scripts/pr-gate.sh` reads exactly one machine-readable header line (`Verification: PASS|FAIL`) and never the prose.

## And one for the human

**The rules apply to the person writing the rules.** I built the lock, documented it, forbade the reviewer from ignoring it — then wrote into the executor's tree mid-build myself, because I was "just making a quick edit." The lock caught me.

A guardrail only works if *everything* that touches the resource checks it. Including you.

## Reference files

- `references/destructive-git.md` — the executor-side refusal, ready to paste into `CLAUDE.md`
- `references/rules.md` — every rule, grouped, with what each one cost
- `scripts/watch.sh` — the poller: retry cap that counts **invocations, not polls**, plus the `Target-PR` escape hatch
- `scripts/pr-gate.sh` — the merge preconditions as **code**, not prose. Exit 0 pass / 2 legacy / 1 REFUSE. It is **necessary, not sufficient** — it never replaces the reviewer actually clicking the thing
- `tests/watch-retry-cap.test.sh` — runs the real poller against a fake `$HOME` with stubbed `claude`/`gh`. 5 cases **and a control**: a task that genuinely fails 3 times must still halt. *A cap that can't stop a runaway is worse than no cap.*
- `tests/pr-gate.test.sh` — 12 cases, including the control (a `FAIL` verdict is refused) and the false-refuse trap (a healthy report that says "the control run failed" must still pass)
- `scripts/watchdog.sh` — alerts on stalls, host failure, its own stderr
- `scripts/backup.sh` — bundle + worktree snapshots, verified by restore
