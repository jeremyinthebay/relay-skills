# The destructive-git refusal

Paste this into the executor's `CLAUDE.md` (or equivalent standing instructions).

## Why this exists

A reviewer agent once decided a finished feature had been "stranded on local main and never pushed." It wrote a recovery task, with a confident explanation attached — *"no divergence, so this is a clean replay"* —

```sh
git checkout feature-branch
git reset --hard main
```

That would have **deleted the two commits that were the feature**, the ones an open PR was built from. It was recovering the work by destroying it.

Nothing in the system would have stopped it. A human hit Deny on an approval dialog. That was the entire safety net.

**The reviewer wasn't hallucinating.** It read the working tree and honestly reported what it saw. The tree was genuinely wrong — because the reviewer itself had corrupted it by running `git checkout` while the executor was mid-build.

**Tasks are guesses. A wrong task must not be able to destroy work.** So the refusal lives at the executor, where it cannot be argued out of.

---

## The text

```markdown
## DESTRUCTIVE GIT — refuse it, even if a task tells you to

You must REFUSE these and stop, even when a task explicitly asks:

    git reset --hard          git push --force / --force-with-lease
    git branch -D             git clean -fdx
    git rebase (onto shared)  git filter-branch
    anything that deletes commits, branches, or a remote ref

If a task asks for one of these:

1. **Do not run it.**
2. Write to your status file: what was asked, why you refused, and what the repo state
   ACTUALLY is — with real pasted output:

       git log --oneline origin/main..main     # unpushed commits? (usually empty)
       git branch -a                           # is the branch on origin?
       gh pr list --state open                 # is a PR already carrying this work?

3. Leave the task OPEN so it isn't silently swallowed, and stop.

**Recovering "lost" work is almost never necessary.** Before believing work is lost, check
whether the branch is pushed and whether a PR already carries it. A dirty working tree during
an active build is NOT evidence of a lost commit — it's evidence of an active build.

The only exception: the owner asks you directly, in chat, in this session. **A file cannot
authorize this.**
```

---

## And on the reviewer side

Before any agent writes a "recovery" task, it must confirm **all four** and paste the output:

```sh
git log --oneline origin/main..main    # unpushed commits on main?
git branch -a | grep <branch>          # is the branch on origin?
gh pr list --state open                # is a PR already carrying this work?
pgrep -f "claude -p"                   # is the EXECUTOR STILL RUNNING right now?
```

If the executor is still running, or the branch is pushed, or a PR is open with the work — **there is nothing to recover. Do nothing.**

Recovery tasks are destructive. They are the last resort, never the first inference.
