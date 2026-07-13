# Setting up the relay

## File layout

```
~/Projects/my-project/            the repo the executor works in
  NEXT-STEPS.md                   task    (planner -> executor)
  COWORK-STATUS.md                report  (executor -> planner)
  CLAUDE.md                       identity + destructive-git refusal   [git-excluded]
  REVIEWER.md                     the reviewer's brain                 [git-excluded]
  .relay-state                    hash of the last-reviewed report
  .outbox.txt                     pending alert
  .automerge                      "on" = authorized to merge
  .preflight                      present = next scheduled run is a permission drill

~/Projects/my-project-backups/    read-only. nothing in the loop can touch these.

~/Projects/relay/
  watch.sh        60s poller: health-check, promote queue, run the executor
  watchdog.sh     the thing that says "I'm stuck"
  notify.sh       drains the outbox
  preflight.sh    exercise every permission, in front of a human
  status.sh       the periodic status heartbeat
  queue/          tasks waiting their turn
  relay.log       ground truth
```

**If the repo root is also your web root** (common for static sites), `NEXT-STEPS.md` and `COWORK-STATUS.md` will be **served publicly**. Git-excluding them is not enough — they ship inside the deploy. Block them at the edge:

```
# _redirects — the trailing ! is load-bearing. A redirect is IGNORED when the path
# matches a real file, unless forced. Ours was silently served for hours.
/NEXT-STEPS.md      /404.html  404!
/COWORK-STATUS.md   /404.html  404!
/*.md               /404.html  404!
```

## 1. The executor's CLAUDE.md

Lead with what the project is **not** — ambient memory of other projects on the same machine is a real failure mode.

```markdown
# [Project]

**This project has NOTHING to do with [that other thing on this machine].**
Do not cd there, do not reference it, do not reuse anything from it.

## The relay
NEXT-STEPS.md is your inbox. When told "check next": read it, execute any `Status: OPEN`
task, overwrite COWORK-STATUS.md with REAL COMMAND OUTPUT (never the word "verified"),
flip the task to DONE, commit, push, open a PR with `gh`. **Do not merge.**

## Push back
If a task is wrong about the code, say so plainly and don't do it. You have been right and
the planner wrong more than once.
```

Then paste in the destructive-git refusal (see `autonomous-loop-safety/references/destructive-git.md`).

## 2. The poller

`scripts/watch.sh`, run every 60s by launchd or cron. It:

- touches a **liveness beacon** before any early exit (never infer liveness from log activity — the poller correctly goes quiet during a long build)
- honors a **permanent kill switch** (`.stop`) that no automation may delete
- runs the **watchdog**, and halts if it says to
- holds a **PID lockfile** so a long build can't stack
- **promotes the next queued task** only after *verifying* it reached a clean `main` — verify, then record
- **fails closed** if `gh` can't answer
- enforces a **retry cap** and a **daily build budget**
- **snapshots the repo** before invoking the executor

## 3. The reviewer

A scheduled task, every ~6 minutes. Make the task prompt a **thin permanent bootstrap**:

> *"Your operating instructions live in `~/Projects/my-project/REVIEWER.md`. Read it first and follow it exactly. If the file differs from what you remember, the file wins."*

Then keep the volatile logic in `REVIEWER.md`, which the agent can revise via shell without a human approving a task edit every time.

**Keep the safety properties in the prompt**, where a file-writer can't edit them away:

1. Never merge a PR that fails your own independent verification.
2. Never record state as "seen" before you've finished acting on it.
3. Never run a local git write command — you share a working tree with the executor. `gh pr merge` is server-side.
4. If the executor's lock is held, stop the run entirely.

## 4. The merge gate

`gh pr view --json mergeable` reports **git conflict state only**. It says nothing about whether the build passed.

And a deploy-preview URL serves the **last successful deploy** — so if the head commit's build failed, that URL still returns 200 **with the previous commit's content**. You would verify old code and merge a broken commit.

Prove the build is green **for the exact commit you're merging**:

```sh
gh pr checks <N>       # must show the deploy as passing for the head SHA
```

## 5. The queue

Drop task files in `queue/`. When a PR merges and no PR is open, the poller promotes the next one onto fresh `main` and the executor picks it up within 60 seconds.

**Watch for the half-done trap:** executors sometimes split a large task into two PRs. If the queue is empty and the merged PR was "part 1 of 2," **nothing will trigger part 2.** The reviewer must notice this and write the follow-up itself.
