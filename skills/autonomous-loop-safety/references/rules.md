# The 24 rules

Every one was paid for. None were obvious in advance.

## Honesty

**1. "Verified" is a failing answer.** If the agent can't paste the command output, it didn't run the command.

**2. The reviewer must verify independently.** An agent checking its own work grades its own homework.

**3. Tasks are guesses until they're run.** Expect the executor to push back — it was right and the planner wrong three times on the very first task.

## Never lie to yourself about state

**4. Record state LAST.** Never mark work "seen" before you've acted on it. This deadlocked the loop permanently, twice.

**5. Fail closed.** An empty answer from a source that wasn't looking is not an answer. `gh` failing returned "0 open PRs," which read as "all clear, proceed."

**6. Verify, then record.** Don't log success you didn't confirm. A swallowed `2>/dev/null` let a failed checkout print "promoted on fresh main."

**7. You cannot reason your way out of a racy read.** If two processes share a working tree, no rule about "checking carefully" will save you. Enforce mutual exclusion structurally.

## Silence is the enemy

**8. Silence must never look like health.** A stall, a paused host and a dead build all produce the same output as a quiet, successful night: nothing.

**9. Read your own logs.** Every bug we found was already written down somewhere nothing was reading. The instrumentation was fine. Nobody was listening.

**10. A status view that can't report its own death is decoration.** Mine printed "✅ Idle · 🟢 healthy" over a wedged loop.

**11. Test the safety net against live state.** The watchdog was broken when written. So was the preflight. So was the fix for the watchdog.

## Money and blast radius

**12. Set a cost ceiling before you start**, not after you hit it. A quota is not a safety mechanism you discover by exhausting it.

**13. Cap retries.** A failing task will rebuild every 60 seconds, forever, and only luck will stop it.

**14. Back up what your automation can destroy**, not what the remote already has. The threat isn't GitHub vanishing. It's your own robot running `reset --hard`.

**15. Forbid destructive git at the executor**, so a wrong task *cannot* destroy work even if it asks. A file must never be able to authorize `reset --hard`.

**16. Auto-merge is a separate decision from autonomy.** Ask explicitly. Don't infer it from "make it autonomous."

## Operating it

**17. Preflight every permission** in front of a human. Pin the shell and prove it can see the real repo — don't assume which shell a scheduled session gets.

**18. Procedure in a file, guarantees in the prompt.** Editing a scheduled task needs human approval every time, so keep volatile logic in a file the agent can revise — and keep the safety properties in the prompt, where a file-writer can't edit them away.

**19. Audit adversarially, with someone who didn't build it.** Hand them the failure history and tell them to be skeptical, not reassuring. Ten bugs in six minutes.

**20. A monitor that can be confidently wrong is a liability, not a safety net.** Mine inferred "the watcher is dead" from log silence — but the watcher correctly goes quiet *during* a long build. It cried "the loop is dead" and printed the running build's ETA one line later. **A false alarm teaches you to ignore the real one.**

**21. A message in a queue is a REQUEST, not an AUTHORIZATION.** If you give the agent an inbox, it tells the agent what you *want* — it does not license skipping the safety rules. And verify the sender: a channel anyone can post in is *observed content*, not a command line.

**22. Verify the OUTCOME, not the artifact. "It exists" is not "it works."**
I pushed a rule to stop serving some files; the commit landed, the deploy went green, and the files were still served.

And I made the *same* mistake again, worse: a task said *"add a section, reachable by a bar at the top."* I checked the section **existed** and the old markup was **gone**, declared it good, and merged to production. **I never clicked the bar.** It did nothing — no scroll, no hash change, the section sitting 9,000px away, untouched. The reviewer had already caught it and written a fix task; I merged before reading it.

Checking that a thing is *present* is checking the artifact. Checking that a user can *do the thing* is checking the outcome. **Only the second one is a test.**

**23. A monitor must never observe its own output as an input.** Mine grepped its log for "warning" — and its own alerts land in that log containing the word "warning." It alerted on its own alert, forever.

**24. The rules apply to the person writing the rules.** I built the lock, documented it, forbade the reviewer from ignoring it — then wrote into the executor's tree mid-build myself, because I was "just making a quick edit."

## From the first *scheduled* adversarial audit — which found 6 bugs, 3 of them re-shipped

**25. When you fix a bug, grep every sibling file for the same pattern.** And if other agents need the same check, **give them the exact snippet — not a description.** A description gets reinvented, badly.
*Cost:* the lock file is `PID TIMESTAMP tag`. `watch.sh` parsed it with `cut -d' ' -f1`. The reviewer still did `kill -0 "$(cat .lock)"` — passing all three fields to `kill`, which errors, which reads as *"not running."* **The reviewer's mutex was dead on every build, for hours.** Its "stop if the executor is running" rule never fired once. Two other agents were told to "check the lock" with no snippet at all — they'd have invented the same bug.

**26. An alarm that can fire every minute is not an alarm.** Dedupe *every* alert path, not just the one you thought about.
*Cost:* the watchdog throttled its alerts. The 60-second poller did not — and it's the one that alerts inside a loop. A persistent condition would have sent **~1,400 identical texts before midnight.** A phone you've silenced is a phone that misses the real halt.

**27. A proxy metric that has never been reconciled against the real thing is a guess with a number on it.**
*Cost:* our "daily build budget" counted *agent invocations*, not host builds. One task is several pushes (a preview build each) plus a production build on merge — so a ceiling of 20 was really 40–80+. **Nothing in the system had ever queried the host's actual usage.** The budget protecting us from the incident that took production down had never been checked against the thing it measures.

**28. A mechanism you haven't tested in YOUR configuration is a rumour — and so is a bug report.**
`PreToolUse` hooks are the perfect mechanical gate for destructive commands: a model can talk its way past a paragraph, but not past a hook. Except [claude-code#20946](https://github.com/anthropics/claude-code/issues/20946) reports, with a repro, that under `--dangerously-skip-permissions` **hooks fire but don't block** — 9 denials, 5 commits landed anyway. That's exactly the mode an autonomous loop runs in.

**So we tested it. On Claude Code 2.1.197 the bug does NOT reproduce — hooks block properly.**

```
CONTROL (no hook):  agent ran the command, file created   ← proves the harness works
WITH HOOK:          blocked, nothing written
REAL COMMAND:       git reset --hard HEAD~1  →  BLOCKED, commit survived
HARMLESS GIT:       git status, git log      →  still allowed
```

**Install a hook. It is a mechanism; `CLAUDE.md` is a request.** Keep both — an instruction-level refusal stops the tool call from ever being *emitted*, so it's immune to any hook-dispatch bug. Re-test after every upgrade.

*And a warning from the test itself:* the first attempt used `timeout`, which doesn't exist on stock macOS. The agent never ran, no file appeared, and the verdict logic read "no file" as "the hook blocked it." **A test that never ran, reporting success.** Always include a control run that proves the harness executes.

**29. Don't try to recognise failure. Assert success.**
*Cost:* our paused-host detector grepped production HTML for `usage limits|site was paused|Site not available`. **Nobody had ever seen a real paused page to check those strings.** If the wording differed at all: no match, HTTP 200, watchdog **clears its own halt**, loop keeps building into a paused account. The detector for the one incident that had already cost four hours defaulted to "healthy."

Enumerating failure modes is unbounded and you will miss one. **Asserting the presence of what you expect is bounded, and it fails closed.** It now checks that our own title and a known DOM id are being served. Paused page, parked domain, broken deploy, empty 200 — all fail identically, all fail closed.

**30. Never edit a script the scheduler may be executing. Run an immutable snapshot.**
*Cost:* a running shell reads its script **incrementally, by byte offset**. Edit that file mid-run and the shell resumes at a stale offset in the *new* bytes — landing mid-line, mid-comment, anywhere — and executes whatever garbage it finds. Ours tried to run the word `structural` from inside a comment. The poller died right after launching the executor, so the task never got marked done, retried, and **opened two duplicate PRs** before the retry cap stopped it.

"Be careful" is not a fix — being careful failed twice in one day. The fix is structural: the scheduler runs a **tiny launcher that never changes**, which (a) refuses to run a poller that doesn't parse, and (b) **copies the real script to a private snapshot and executes the snapshot**. Now editing the live file mid-run is harmless — the running copy is a different inode.

**31. A retry is not a restart. Check whether the work already exists.**
*Cost:* when the poller died mid-run, the retry logic simply ran the task again — and the executor, doing exactly as told, **opened a second PR for work that was already done.** The promotion path gated on "zero open PRs"; the *retry* path never checked. If a PR already exists for the current task, the work exists — it's the *bookkeeping* that failed, and that needs a human, not another build.

And when you add that guard: make it **wait**, not **halt**. An open PR is the system's normal resting state, not a failure. Halting on it turns "waiting for review" into an outage that needs a human to clear a flag. (I got this wrong on the first attempt.)

**32. If a surface can drift silently, something must watch for the drift.** Our lessons live in three places (a private doc, a public writeup, a public repo). The doc auto-updated; the public ones needed a human. Nobody noticed the public record sat **seven rules behind** for hours. **A stale record is a record that lies** — and a system built to stop lying about its own state shouldn't lie about its own history. Check parity every run; treat a gap as a bug, not a chore.

**33. Your automation's browser tab is HIDDEN. Animations do not run in it.**

This one fabricated an entire production incident, and it is the single most expensive mistake in this document.

```
document.visibilityState  ->  "hidden"
document.hasFocus()       ->  false
```

**`requestAnimationFrame` is throttled to ZERO in a background tab.** Anything animated silently never moves. And `scroll-behavior: smooth` — which most modern sites set — animates via rAF.

So `location.hash`, `scrollIntoView()`, `scrollTo({behavior:'smooth'})`, **and even a real trusted mouse click on an anchor link** all report *no movement*, on a page that works perfectly for a human.

I concluded "the whole site cannot be scrolled," closed a good PR, wrote an alarming brief, burned three builds, and told the owner production was broken. **A five-second check on his phone proved it worked fine.**

**The discriminator that would have saved all of it:**

```js
window.scrollTo({ top: 1000, behavior: 'instant' });  // bypasses rAF entirely
// if INSTANT works and SMOOTH doesn't, your tab is hidden and your test is invalid
```

**Never conclude "the page can't scroll" without first proving an instant scroll also fails.**

And the general form, which is bigger than scrolling: **know what your harness is structurally blind to.** Mine cannot observe motion — not because of a bug, but because of what it *is*. A test that cannot fail correctly is not a test.

**34. When the executor pushes back on your verdict, doubt your tooling first.**
Twice in one day the executor rejected a verdict and was **right both times** — once on an iframe sized after `src`, once on this. In both cases it had *read the code*; I had *trusted my harness*. It even refused to strip `scroll-behavior: smooth` to make my test pass, correctly calling that "a downgrade for real users to satisfy a test artifact."

**An executor that refuses to patch a non-bug is doing its job.** Don't out-argue it. Out-test it — with a control.

**35. Some things your automation cannot see. Ask a human. It costs five seconds.**
Not as the durable solution — the point is automation — but when the harness is *structurally* blind (animation, visual layout, "does this feel right"), a human check is cheap, instant, and correct. Know which category you're in, and be explicit about what you need tested. An hour of an agent chasing a ghost is worth strictly less than one five-second look.

## 36. The human is not the message bus

Our watchdog texted the owner and **nobody else**. So he'd get *"the executor isn't picking it up"* on his phone and have to relay it back to an agent to go look. **The human became the message bus for a system built specifically to avoid that.**

An agent runs every five minutes. **A human should never be the first responder.** Alerts land in a log the agents read; an agent triages within one cycle, fixes what it safely can, and escalates with a *diagnosis* rather than a raw alarm. Only production-down and money-burning alerts page a human instantly.

If your monitoring's only output is a text message to a person, you haven't built monitoring — **you've built a pager, and made the human the integration layer.**

## 37. Fixing one of N paths is not fixing the bug

Rule 36 was the policy. We implemented it in `watchdog.sh` and declared it done.

**Four other scripts had their own copy of `alert()`, each paging the human directly.** The very next routine event texted him anyway. The policy was real; the *enforcement* existed in one of five places. We had fixed **the example we happened to be looking at.**

The tell: we verified the policy by reading the code we'd just changed. The right test greps for every path that can still do the forbidden thing:

```sh
grep -rn "notify.sh" *.sh    # who can page a human? should be exactly ONE file
```

The fix isn't five careful edits — it's **collapsing five implementations into one front door** the others must call. A policy that lives in five places isn't a policy; it's a coincidence waiting to end. **Make the wrong thing structurally impossible, not merely discouraged.**

## 38. "It's on" is a claim. The file on disk is the fact.

We told the owner auto-merge was on. Twelve hours later a PR sat unmerged and he asked why. `ls .automerge` → **no such file.** It was never on. We had reasoned about turning it on, discussed it, and moved on — without the one line that creates the flag the reviewer reads.

This is rule 1 (don't verify with a status code) and rule 12 (don't merge without clicking the button) aimed at *yourself*: **we reported an intention as an outcome.** The config file is not a formality; it **is** the setting.

**Before you tell a human a switch is flipped, read the switch.**

## The twin of rule 8

**Noise must never drown the signal.** The inbox checker runs 96 times a day and posts *nothing* when there's no work — because a bot that says "nothing to do" 96 times a day is a bot you mute, and then you miss the one that mattered.

Alert on trouble. Stay quiet on routine. Both halves are the same rule.

We later built a 10-minute heartbeat posting status to chat. It ran 42 times before the owner killed it: *"I trust the process is working, we have a watcher, and you'll alert me when I need to do work. So no more random status updates anywhere."*

**A status update nobody asked for is a tax on attention.** The watchdog is what makes silence trustworthy — and once silence is trustworthy, **chattering to prove you're alive is just noise with good intentions.** An autonomous system's highest compliment is that you forgot it was running.

---

## The guardrails that turned on us (learned the hard way, in one day)

### A guardrail that fires when nothing is wrong is broken

The retry cap halted the loop for a task that had not failed once. The counter was incremented on every *poll*, above the check that decides whether the executor is invoked at all. Two polls that never ran anything took it from 1 to 3.

**Count attempts where you make them.** The increment belongs immediately before the invocation, nowhere else.

**Cost:** a night of autonomy, and a halt message that blamed work which had already succeeded.

### A gate whose only exit is the thing it blocks is a deadlock

"Never invoke the executor while a PR is open" (prevents duplicate PRs) met "this PR needs one push from the executor to become mergeable." The repair task was blocked by the thing it repaired. A human had to break it.

**Every blocking gate needs an escape hatch for the state that repairs it.** Ours: `Target-PR: #N` in the task header, honoured for exactly that PR.

**Cost:** a deadlock that survived clearing the kill switch.

### Misfire vs policy — know which one you're looking at

- **Guardrail misfiring** → a bug. Fix it, prove it with a test *and a control*, report it. Do not ask.
- **Guardrail's policy should change** (ceilings, merge bars, force-push) → a judgment call. Ask.

Collapsing these makes an agent that pesters a human about bugs and quietly rewrites policy. Both directions are wrong.

**Cost:** the owner: *"it's keeping me more in the loop and asking me too many questions vs actually being autonomous."*

### A control that passes for the wrong reason is a false pass

The control "a FAIL verdict must be refused" went green — because the fixture had no git remote, so the gate refused before ever reading the verdict. Broken verdict logic would have looked identical.

**Assert on the reason, not just the outcome.** Print *why* the check refused, and read it.

And its mirror: don't grep prose for the word "FAIL". A healthy report says *"the control run failed all 3 checks"* — which is a control doing its job. Read one machine-readable header line instead.

**Cost:** caught in the same hour, but only because the suite was re-run and read.

### Paperwork conflicts; product code doesn't

Bookkeeping files committed on feature branches conflict every time main moves. Product code rarely does. Commit the paperwork straight to main in its own commit; keep branches product-only.

**Cost:** two stranded PRs, one deadlock, one manual rescue.

---

## What the loop was never checking (2026-07-14)

### If a missing fact renders as a plausible one, your data model is a lie generator

Transfer ratios lived as an *optional suffix inside the partner's name string*: `"Aeroméxico ·1:1.6"` had
one; `"Cathay"` and `"Emirates"` did not. A chip with no suffix rendered as just a name — which a reader
takes to mean the ordinary ratio, **1:1**. An audit against the issuers' own pages found both are **5:4**.
The *absence* of a fact was rendering, confidently, as a *different* fact.

That is a shape bug, not a typo bug. **An optional field with a plausible default does not fail loudly when
it's missing — it fabricates.** A blank would have been honest.

The fix was not correcting the ratios. It was making the omission impossible: every partner became an object
that must carry its ratio (`{p:"Cathay", r:"5:4"}`), and the renderer never defaults a missing one.

**Correct the data and you fix today. Correct the model that permitted the gap and you fix every tomorrow.**

**Cost:** wrong ratios in every currency, live, for the life of the page.

### Your tests prove the page renders. They do not prove it's true.

The uncomfortable half of the rule above: while that data was wrong in every currency, **the machine was
entirely green.** Mobile matrix 20/20 at both widths in both themes. `node --check` clean. The production
canary healthy after every deploy. No guardrail blinked.

Every check we own verifies the *build* — that it parses, renders, doesn't overflow, doesn't 500. **Not one
of them can tell whether a single word on the page is true.** The four wrong facts were caught by strangers
on Reddit, after publication. That is not a detection mechanism; it is luck.

An autonomous loop makes this sharper, not safer: it ships correct code fast, so a wrong fact propagates at
exactly that speed with a green tick on it. **Velocity is not validation. A passing suite is not a
fact-checker. A claim needs a source, not a green build.**

**Cost:** four false claims on a live page; found by readers, not by us.

### "Unverifiable" is usually a fact about your tools, not about the world

An audit checked a data set against the companies' own published pages. Three came back
*"unverifiable — the page is JavaScript-rendered and the fetch returns an empty shell."* That went
into the report, twice, and the audit moved on.

Then a human asked: *"Can't you just open the browser?"*

Of course it could. A browser **runs the JavaScript.** Two of the three pages gave up their data
immediately, with no login — including the two most valuable facts in the audit: a partner that had
been quietly dropped, and a ratio the site had been getting wrong for months. Straight from the
company, in its own words.

Worse, the constraint was **self-inflicted**: the research helpers had been told "no browser tools"
for an unrelated reason (see the next rule) — and then their conclusion was *believed as a fact about
the world.* It wasn't. It was an echo of our own restriction coming back wearing a lab coat.

**Before you write "cannot be verified," name the tool that failed and ask what a different tool
would see.** A fetch that returns a shell has not told you the page is empty; it has told you the
fetch cannot execute JavaScript. Those are not the same sentence.

**Cost:** two of the audit's most valuable findings nearly discarded as unknowable.

### Never give an autonomous helper write access to a workspace a human is using

Five draft replies sat in five browser tabs, waiting for a human to read and post them. Then a
research agent was spawned with the standard toolset — which included browser control.

It needed a page. It grabbed a tab. It navigated away, "restored the URL," and reported back
politely. **Four of the five drafts were gone.**

The agent did nothing wrong. *We* handed it write access to a surface a human was actively working
in, then walked away. The tabs looked like the agent's workspace. They were the human's.

Two rules fall out, and the second is the more important:

- **Scope a subagent's tools to the job.** A research task needs to read the web. It does not need to
  drive a browser holding a human's unsaved work.
- **Unsaved work does not belong in a volatile surface.** Browser tabs are not storage. If it
  matters, it goes in a file — then it survives the agent, the crash, and the accidental close.

**Cost:** four drafts destroyed; and, via the restriction imposed in response, an audit that declared
verifiable facts unverifiable.

### A staleness check must compare identity, not status

A poller found its local task file marked `OPEN` while the remote copy read `DONE`. It concluded the
obvious thing — *I'm behind* — checked the file out from the remote, and logged `refreshing`.

It was not behind. It was **ahead.** It had promoted the *next* task locally; the agent that ran it
crashed after pushing its branch but before pushing the paperwork. Local `OPEN` was task #14. Remote
`DONE` was task #13. The recovery path never asked *which task* — only whether the other side said
`DONE` — so it deleted a live task and reported the loop idle.

`local=OPEN, remote=DONE` is **ambiguous**. It means either:

- the remote is ahead — someone else finished this task (the case the check was written for), or
- **the local is ahead** — a newer task exists that hasn't been pushed yet.

Only the task's *identifier* separates those two, and status comparison throws it away. **A recovery
path that cannot tell *behind* from *ahead* will eventually destroy the newer state — and it will do
it while logging a reassuring word.** Compare identity (which task), then status (what state).

A related trap in the same incident: the agent exited **non-zero because its network connection
dropped mid-response**, not because the work failed. The branch and the pull request were already
pushed. Every conclusion drawn afterward — "task didn't complete, will retry", "nothing has been
building for 31 minutes" — was read off the *process*, while the *artifact* sat in plain sight.
**An exit code measures the transport, not the work. Ask what shipped, not how the process died.**

**Cost:** a completed task's brief and verification record erased; the loop reported idle while its
pull request sat open and unreviewed.
