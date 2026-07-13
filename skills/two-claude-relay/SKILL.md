---
name: two-claude-relay
description: Set up a two-agent autonomous loop where a planning agent writes briefs, an executing agent builds and opens PRs, and the planner independently verifies and merges — running unattended for hours. Use this whenever the user wants an agent to work autonomously, run overnight, keep working while they're away, self-review its own code, build a multi-agent or planner/executor setup, or asks how to let Claude Code run without supervision. Also use when someone asks "can I have an agent just keep going on its own" or wants to automate a build/review/merge cycle.
---

# The Two-Claude Relay

A working pattern for an autonomous build loop: one agent executes, a *different* agent reviews, and neither can ship alone.

This was built and run in production. It also took a site down for four hours, deadlocked twice, and came one click away from `git reset --hard` on the only copy of a finished feature. **The safety rules in `autonomous-loop-safety` are not optional garnish — they are the difference between this working and this costing you a night.** Read that skill alongside this one.

## The core idea

**One agent does the work. A different agent checks it.** They communicate through two files in a git repo. A shell script keeps the loop turning.

The split matters more than it sounds. An agent verifying its own work grades its own homework — it knows what it *meant* to do, so it tends to see what it meant to do. A separate reviewer, with a separate context window and no memory of writing the code, has no such loyalty.

That isn't theoretical. On the first run, the executor's overflow test came back clean — but the entire UI it was testing lived inside a `display:none` section, so the probe was measuring hidden elements and reporting a beautiful green pass on exactly the components under test. **A single agent ships that false green.**

## The division of authority

This is the safety model, not ceremony:

- **The executor can COMMIT but never MERGE.**
- **The planner can MERGE but never COMMIT.**
- **Neither one ships alone.**

Preserve this even when it feels bureaucratic. It's the only structural thing standing between a confident model and a broken production deploy at 2am.

## The protocol: two files, not an API

| File | Direction | Contents |
|---|---|---|
| `NEXT-STEPS.md` | planner → executor | The brief. Header line: `Status: OPEN` or `Status: DONE`. That single line is the trigger for everything. |
| `COWORK-STATUS.md` | executor → planner | The report: real pasted command output, verbatim errors, and anything it did beyond the brief or disagreed with. |
| `CLAUDE.md` | standing context | Project identity + the protocol. Auto-loaded by the executor. Git-exclude it if the repo root is a web root. |

Files, not a message bus. The entire agent-to-agent conversation is versioned in git and readable by a human at any moment. When something goes wrong — and it will — you can read exactly what each side believed.

## The rule that makes it honest

**Every brief carries a verification bar, and the report must contain real pasted output. The word "verified" is a failing answer.**

If the executor can't show you the command output, it didn't run the command. This one line catches more than any amount of prompting about being careful.

Make the bar concrete and project-specific: a syntax check, a grep for the thing that shouldn't be there, screenshots at the sizes that matter, a probe that proves the actual behavior. Then demand the output, pasted.

## How the loop turns

1. **Planner writes `NEXT-STEPS.md`** with `Status: OPEN`. It lands uncommitted in the working tree — fine, the executor reads the tree, not the branch.
2. **A 60-second poller** (launchd/cron) greps for `Status: OPEN` and runs `claude -p "check next" --dangerously-skip-permissions`. A PID lockfile stops a long build from stacking runs.
3. **The executor** builds on a branch, opens a PR, writes its report, flips the brief to `DONE`, commits, pushes.
4. **A scheduled reviewer** wakes, sees a new report, and **independently verifies the deploy preview in a real browser** — not the executor's word for anything.
5. **Pass → merge** (`gh pr merge`, server-side). **Fail → write a fix brief**, which is just another `Status: OPEN` and gets picked up within 60 seconds.
6. **The merge promotes the next queued brief.** Back to step 2, with nobody in the room.

## Setting it up

Read `references/setup.md` for the full walkthrough: the poller, the reviewer prompt, the queue, and the file layout. Working scripts are in `scripts/`.

The short version:

**Give the executor a `CLAUDE.md` that opens by saying what the project is NOT.** Ambient memory of other projects on the same machine is a real failure mode — the executor went looking in an unrelated repo on day one. Negative space matters as much as instruction.

**Give the reviewer its instructions in a FILE**, not in the scheduled task's prompt. Editing a scheduled task needs human approval every time, and early on you'll revise constantly. Make the task a thin permanent bootstrap — *"read `REVIEWER.md` and follow it"* — and keep the volatile logic in the file. **Keep the safety guarantees in the prompt**, where a file-writer can't edit them away. Procedure in the file, guarantees in the prompt.

## Writing a brief that works

- **Say what "done" looks like, in checkable terms.** Not "make it responsive" but "zero horizontal overflow at 390px, in every view, both themes."
- **Include the verification bar.** Every time.
- **Expect to be wrong.** Briefs are guesses until they run. On the very first brief, the executor pushed back on three points and was right on all three — it had read the code and I hadn't. Tell it explicitly: *push back when the brief is wrong; your status file is ground truth over my assumptions.*
- **Don't put two decisions in one brief.** I once said "add click-to-expand" and "keep the three view modes" in the same brief, without asking whether three view modes earned their space on a phone. They didn't. The executor built exactly what I asked for, and the result was bad. That was a planning failure, not an execution one.

## Keep the paperwork off the feature branch

This one cost us two stranded PRs and a night of downtime, and it is the least obvious rule here.

The two protocol files (`NEXT-STEPS.md`, `COWORK-STATUS.md`) are **bookkeeping**. If the executor commits them to its feature branch, you get this:

1. Executor branches off main and starts a 30-minute build.
2. Main moves while it works — a doc edit, the next task getting promoted, anything.
3. Executor finishes, commits its work **and the paperwork**, opens a PR.
4. **The PR won't merge.** Both sides rewrote the same status file. Git says `CONFLICTING` — while the actual product code conflicts with *nothing*.

Two PRs in a row died this way. And it deadlocks: the fix is a push to the branch, only the executor can push, and the "one PR in flight" gate refuses to invoke the executor while a PR is open.

**So: feature branches carry product code ONLY. The protocol files are committed straight to main, in their own commit.**

```
# the work — on the branch, product only
git add index.html && git commit -m "Task #N: what shipped"
git push -u origin task-N && gh pr create ...

# the paperwork — on main, separately, never on the branch
cd <primary tree>        # NOT the worktree: git refuses to check out main twice
git pull --ff-only
git add NEXT-STEPS.md COWORK-STATUS.md
git commit -m "Task #N: status — Verification: PASS (PR #n)"
git push origin main
```

**The executor still never merges.** It commits paperwork to main; it never pushes product code there, and never runs `gh pr merge`. The division of authority is untouched — that is the whole safety model and this doesn't dent it.

The reviewer then reads the report from `git show origin/main:COWORK-STATUS.md` — **not** from the PR diff, where it is now correctly absent.

If your host rebuilds on every push, exclude markdown from the build trigger or this gets expensive. Ours (Netlify) skips the build unless a *served* file changed, so paperwork commits cost nothing — verify that before adopting this.

`tests/commit-split.test.sh` replays the exact scenario under both protocols and proves the conflict class is gone. Its third case is the one that matters: **two branches genuinely editing the same product line must STILL conflict.** Removing a class of false conflicts must never remove your ability to see a real one.

## What this is not good for

- **Anything you'd be upset to lose.** The executor runs with `--dangerously-skip-permissions`, because a headless agent can't answer a permission prompt. That means unattended shell with push access, scoped to a folder but *not sandboxed*.
- **Work that needs taste more than correctness.** The loop is excellent at "prove zero overflow at 390px." It cannot tell you whether one view *feels* better than three. Keep a human gate for judgment calls, and be honest about which is which.
- **Anything without a verifiable output.** If the reviewer can't independently check the result — a deploy preview, a test suite, a rendered artifact — the second agent adds nothing but cost.

## The one thing to take away

**Every bug this system had was already visible in a file on the machine.** The logs were excellent. Nothing read them. Before you add more instrumentation, make something read what you already have.
