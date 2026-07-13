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

## The twin of rule 8

**Noise must never drown the signal.** The inbox checker runs 96 times a day and posts *nothing* when there's no work — because a bot that says "nothing to do" 96 times a day is a bot you mute, and then you miss the one that mattered.

Alert on trouble. Stay quiet on routine. Both halves are the same rule.
