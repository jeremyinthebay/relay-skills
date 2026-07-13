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

**22. A successful deploy is not evidence that what you intended happened.** Verify the outcome, never the mechanism. I pushed a rule to stop serving some files; the commit landed, the deploy went green, and the files were still served.

**23. A monitor must never observe its own output as an input.** Mine grepped its log for "warning" — and its own alerts land in that log containing the word "warning." It alerted on its own alert, forever.

**24. The rules apply to the person writing the rules.** I built the lock, documented it, forbade the reviewer from ignoring it — then wrote into the executor's tree mid-build myself, because I was "just making a quick edit."

## The twin of rule 8

**Noise must never drown the signal.** The inbox checker runs 96 times a day and posts *nothing* when there's no work — because a bot that says "nothing to do" 96 times a day is a bot you mute, and then you miss the one that mattered.

Alert on trouble. Stay quiet on routine. Both halves are the same rule.
