---
name: parallel-build-serialized-merge
description: Decompose a large task into disjoint-ownership workstreams, build them in parallel with independent agents in separate worktrees, then serialize the merge one verdict at a time through a single review gate. Use when a review/merge gate trusts only one verdict at a time and that's forcing an otherwise-parallelizable build to run serially, when splitting work across multiple agents or branches that will all need review before merging, or when someone asks "can we build these at the same time" or "how do I speed up the pipeline without weakening review."
---

# Parallel Build, Serialized Merge

The speedup this buys you is not "more agents." It's noticing which part of your pipeline
actually has to be serial, and refusing to serialize anything else.

## The insight: find your single verdict slot

Most review/merge gates are built to protect **one merge at a time** — a status file that names
exactly one approved PR, a human who reviews one diff at a time, a CI slot that only one build can
occupy. That gate is real and should stay real. But it constrains the **merge**, not the **build**.

The build is usually the slow part (the actual coding, the self-verification) and the merge is
usually fast (write a verdict, run a gate script, fast-forward a branch). If your gate happens to
be structured so that two open, unreviewed changes can't both be "the approved one" at the same
time, that's a constraint on the verdict — not a law that says the work behind it must also happen
one at a time.

**Only the merge must serialize. The build can run in parallel.** That's the entire pattern.

## Step 1 — decompose into disjoint-ownership workstreams, up front

Before spawning anything, split the task into workstreams and have each one declare, in writing,
the exact files and functions/regions it will touch. Two workstreams are safe to run in parallel
only if their declared ownership doesn't overlap. Rules that keep the eventual merge clean:

- **Append-only shared files** (stylesheets, changelogs): each workstream appends inside its own
  delimited block — `/* === WS-A start === */ ... /* === WS-A end === */` — instead of editing
  existing rules. Two appends to the end of a file never conflict.
- **Shared code files, disjoint functions**: workstreams may edit the same file as long as they
  touch different functions/components and don't reflow shared regions (imports, formatting,
  shared helpers). Reformatting a whole file is not disjoint, even if the "real" change is small.
- **Shared markup, disjoint sections**: own different named sections/views; avoid two workstreams
  both touching global chrome (nav, header, layout shell).
- **If two workstreams must edit the same function or the same few lines, they are not
  independent.** Merge them into a single workstream rather than hoping the merge resolves cleanly.

This step is where most of the actual thinking happens. Get it wrong and step 3 is where you find out.

## Step 2 — spawn parallel BUILD agents, one per workstream

Launch one agent per workstream **in the same message/batch**, so they actually run concurrently.
Each build agent should:

1. Create its own isolated worktree on its own branch: `git worktree add -b <branch>
   <path>/<branch> origin/main`. Isolated worktrees, not a shared working tree — two agents sharing
   one checkout is a different (and worse) failure mode than anything this pattern is solving.
2. Build **only** the change described for its workstream — nothing from the review/safety layer,
   nothing in shared bookkeeping files.
3. Self-verify with a real harness before opening a PR — not "I read the code and it looks right."
   (See the `mobile-verification` / `signed-in-web-verification` skills for why a real browser,
   not a description, is the bar.)
4. Open a PR (or equivalent change request). **Do not merge. Do not touch the shared verdict
   file or any other bookkeeping the merge gate reads.**
5. Report back: what changed (files + functions), pasted verification evidence, and a
   **shared-file flag** — any file/region another workstream might also touch, so the human/
   orchestrating agent can watch for a real conflict at merge time.

## Step 3 — serialize the MERGE, one verdict at a time

Pick a merge order (most central / most depended-on first, or see the caveat below). Then, per change:

1. Confirm it's still cleanly mergeable against current `main` (no conflicts).
2. Produce **exactly one verdict** in whatever form your gate reads — a status file naming this
   PR with a pass header and pasted evidence, an approval, a green CI run. Commit/record that
   verdict on `main` or wherever the gate reads from — never on the feature branch, or the gate
   can't tell your verdict from the code it's supposed to be judging.
3. Let the gate do its normal job: it checks the verdict is present and matches, runs its own
   independent verification, and merges.
4. **Live-verify** the merged result if you can (open the real page/endpoint after deploy, not
   just "the merge succeeded").
5. Move to the next change: rebase its branch onto the new `main`, resolve any (should-be-rare,
   thanks to step 1) textual conflicts in the delimited/disjoint regions, push, and repeat from (1).

While a change's verdict is not yet in the slot, a correctly-built gate refuses it. That refusal
**is** the serialization working as designed — it is not a bug to route around.

## The caveat that will bite you: newest-first

If your gate only inspects **the single newest open item** each cycle (a common, sensible
optimization — e.g. `list --state open --limit 1`, newest-first) then writing a verdict for an
**older** open item while a **newer**, un-verdicted item is still open will stall you: the gate
keeps looking at the newer item, sees no verdict for it, refuses it, and never gets back around to
the one you actually verdicted.

**Serialize merges in descending age order: newest first.** Verdict the newest open item, let it
merge, then move to the next-newest. Don't verdict out of order because it "should" go first
logically — the gate doesn't know your logic, it knows item age. `scripts/merge-order.sh` prints
the correct verdict order for a `gh`-based repo; adapt the query for other review tools.

This was learned the hard way: one older, fully-passing PR sat mergeable while the gate looped
refusing a newer, unverdicted one — because the gate only ever looked at the newest.

## Safety is unchanged, not relaxed

This pattern is a scheduling trick for the build, not a loosening of review:

- Build agents still open changes only; they never merge and never touch the safety/bookkeeping
  layer directly.
- Every merge still goes through the same independent verification the gate always ran.
- Rollback stays cheap regardless of how many workstreams ran in parallel: revert the bad merge.

## When NOT to use it

- The work can't be split into genuinely disjoint ownership (heavy shared-function edits) — you'll
  spend the time you saved building resolving conflicts instead.
- It's one small change — orchestration overhead isn't worth it below a certain size.
- Anything touching the safety/review layer itself, or shared data/schema — keep those serial and
  human-reviewed regardless of how parallelizable the rest of the task is.

## Result

N workstreams building concurrently, still passing through exactly one merge at a time — the wall
clock for the build collapses toward the slowest single workstream instead of the sum of all of
them, with zero loss of verification rigor at the merge.
