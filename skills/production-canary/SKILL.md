---
name: production-canary
description: Prove production still works after every deploy, and automatically revert the merge if it doesn't. Use whenever an agent can merge or deploy without a human watching, when turning on auto-merge, when you want to ship faster without accepting more risk, after a bad deploy reached users, or when someone asks "how do I know the deploy didn't break anything" or "how do I roll back automatically."
---

# Production Canary

**A loop that can undo itself in 60 seconds can afford to move fast. A loop that can't, can't.**

If you let an agent merge to production without a human, the question is not *"will it ever ship something broken?"* — it will. The question is **how long broken code stays live, and who finds it.** Right now the answer is usually "hours" and "your users."

A canary makes it **60 seconds** and **the machine**.

## What it does

After every merge, once the deploy lands:

1. Fetch production.
2. **Assert the things a user actually needs are there** — not that it returned 200.
3. If any assertion fails: **`git revert` the merge, push, alert, halt.**

That's it. `scripts/canary.sh` is the working version; adapt the assertions.

## Assert success — do not try to recognise failure

The instinct is to detect the *bad* state: grep for "500", for an error page, for the host's "site paused" wording.

**That fails open, and it will fail open on exactly the day it matters.** We shipped a paused-host detector that grepped for three guessed strings — **nobody had ever seen the real paused page.** Wrong wording meant no match, HTTP 200, and the loop happily kept building into a dead account.

**You cannot enumerate every way a page can be wrong. You can state what right looks like.**

```sh
FAILED=()
[ "$CODE" = "200" ]                                   || FAILED+=("HTTP $CODE")
printf '%s' "$BODY" | grep -q "<title>My Product"     || FAILED+=("title missing — is this even our site?")
printf '%s' "$BODY" | grep -q 'id="main-app"'         || FAILED+=("app root gone")
printf '%s' "$BODY" | grep -q 'window.DATA ='         || FAILED+=("bootstrap data missing")
[ "$(curl -so/dev/null -w%{http_code} $SITE/api/health)" = "200" ] || FAILED+=("API down")
[ "${#BODY}" -gt 100000 ]                             || FAILED+=("page truncated")
```

A paused page, a parked domain, a broken build, a half-deployed bundle, an empty 200, a DNS hijack — **all fail identically, and all fail closed.**

**Pick assertions that break when a user is hurt.** Not "the CSS file exists" — "the thing the product does is present."

## `git revert` is the one undo an autonomous system may run

This matters, and it's why the canary doesn't conflict with a destructive-git ban:

- **`git revert`** creates a **new commit** that undoes the change. History is intact. The bad commit is still there to inspect. **Nothing is destroyed.**
- **`git reset --hard` / `push --force`** *delete* work. An agent must never run these. (See the `destructive-git-hook` skill.)

Revert is safe, auditable, and reversible in turn. **Rollback is a feature, not a failure** — and treating it as routine is what buys you the speed.

## Wire it in

Run it from the same poller that runs your loop — it's cheap, and it should fire after any merge:

```sh
# in the 60-second poller, before doing anything else
"$RELAY/canary.sh"
```

It keys on the production SHA (`.canary-checked`), so it only runs once per deploy and exits instantly otherwise.

## Test it BOTH ways before you trust it

A canary you haven't seen fail is a canary that might not be able to.

```
TEST 1 — healthy prod:    passes, does not revert   ✅
TEST 2 — simulated break: catches it, would revert  ✅
```

Ours found "title missing, app root gone, page only 37 bytes" against a fake paused page. **If your canary can't catch a page you deliberately broke, it will not catch the real one.**

## The honest caveat

**A canary tests what you told it to test.** It will catch a blank page, a missing app, a dead API — the catastrophic stuff. It will **not** catch "the button is there but doesn't do anything," which is a behavioural bug and needs a real click. (We shipped exactly that, and the canary would have passed it.)

So: canary for *catastrophe*, behavioural tests for *correctness*. They're different jobs. Don't let a green canary convince you the feature works.
