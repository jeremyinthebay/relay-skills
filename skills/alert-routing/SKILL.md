---
name: alert-routing
description: Stop your automation from paging a human for routine events. Route every alert through one front door so agents triage first and humans are only woken for real emergencies. Use when an autonomous system texts/emails/pages a person too often, when alerts get ignored because they're noisy, when a human is manually relaying alarms back to an agent, or when the same alert policy is duplicated across several scripts.
---

# Alert routing: the human is the last responder, not the first

## The problem this solves

Your automation detects a problem and texts a human. The human reads it, and then has to **tell an
agent to go look** — even though an agent runs every five minutes and could have seen it first.

**The human has become the message bus for a system built to avoid exactly that.**

Meanwhile, routine states ("a PR is open and waiting", "retrying a task") page them too — so the
alerts get muted, and then the one that mattered is missed.

## The rule

| Severity | Goes to | Wakes a human? |
|---|---|---|
| **urgent** | log + chat + agent queue + **page** | Yes — prod is down or money is burning |
| **normal** | log + chat + agent queue | **No** |

Default is `normal`. **Paging is opt-in**, and the bar is: *would they want to be woken for this?*

An agent triages the queue on its next cycle, fixes what's safe, and escalates with a **diagnosis**
rather than a raw alarm. A person is contacted only if the agent can't resolve it.

## The mistake almost everyone makes

**Do not add severity to each script's `alert()` function.** We did. We changed one of them, declared
the policy shipped, and the very next routine event paged the human anyway — because four *other*
scripts each had their own copy of `alert()` calling the pager directly.

**A policy implemented in five places is not a policy. It's a coincidence waiting to end.**

Collapse them into **one front door** every script must call, then prove no other path survives:

```sh
grep -rn "notify.sh" *.sh   # who can page a human? Must be exactly ONE file.
```

If that returns anything but your router, you have not shipped the policy. **Make the wrong thing
structurally impossible, not merely discouraged.**

## Reference implementation

`alert.sh` — the only script permitted to call the pager:

```sh
#!/bin/zsh
SEV="${1:-normal}"; shift
MSG="$*"; [ -n "$MSG" ] || exit 0

# Dedupe on the alert CLASS, not the exact bytes. "Fires every 60s = muted" is only true if the
# throttle actually catches it — and a live "12m" age or an HTTP code baked into the message changes
# the hash every tick and defeats the throttle entirely. We shipped exactly this: a watchdog put the
# minute-count in the text and fired 78 identical "stuck PR" alerts in one hour, evicting the one
# alert that mattered. Strip volatile digit runs BEFORE hashing so "open 12m" and "open 13m" collapse.
KEY=$(printf '%s' "$MSG" | sed -E 's/[0-9]+/N/g' | shasum | cut -c1-12)
STAMP="$STATE/$KEY"
if [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -f %m "$STAMP") )) -lt 3600 ]; then exit 0; fi
date +%s > "$STAMP"

printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$SEV" "$MSG" >> "$BASE/alerts.log"   # agents read this
printf '%s\t%s\n' "$SEV" "$MSG" >> "$BASE/.chat-queue"                           # agent posts it
printf '%s\n'     "$MSG"        >> "$BASE/.pending-alerts"                       # agent triages it

# A queue nothing drains is a silent leak. If an agent is not GUARANTEED to drain these every cycle,
# bound them (ring-buffer to the last N) and surface their depth where a human sees it. An undrained
# backlog must never be invisible — "silence must not look like health" applies to your own plumbing.
for f in "$BASE/.chat-queue" "$BASE/.pending-alerts"; do
  [ -f "$f" ] && [ "$(wc -l < "$f")" -gt 500 ] && { tail -n 500 "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
done

[ "$SEV" = "urgent" ] && { printf '%s\n' "$MSG" >> "$BASE/outbox.txt"; "$BASE/notify.sh"; }
exit 0
```

Every caller collapses to one line:

```sh
alert(){ local sev=normal; [ "$1" = urgent ] && { sev=urgent; shift; }; "$BASE/alert.sh" $sev "$*"; }
```

**Shell can't call your chat API? Don't try.** Queue to a file and let the agent — which *does* have
chat tools — drain it on its next run. Queue, don't block.

## Test it for real

Stub the pager so it records instead of sending, fire both severities, assert the count:

```sh
./alert.sh normal "a PR is open and waiting"     # expect: NO page
./alert.sh urgent "production is serving 500s"   # expect: page
```

**Exactly one page.** If the routine one paged too, a caller is still bypassing the front door.

Then fire the **same class twice with only a number changed** — assert it logs once:

```sh
./alert.sh normal "PR #7 open 12m, no build"     # logs
./alert.sh normal "PR #7 open 13m, no build"     # must NOT log again — same class
```

If the second one logs, your dedup key still carries a volatile substring and the throttle is a
no-op. A test that fires a class only *once* can never catch this — vary the number and watch. (This
is the bug that flooded us; the test that would have caught it didn't exist until after.)

## The last mile: don't chatter either

Once alerting is trustworthy, delete the periodic "everything's fine" heartbeat. Ours ran every 10
minutes until the owner killed it: *"I trust the process is working, we have a watcher, and you'll
alert me when I need to do work."*

**A status update nobody asked for is a tax on attention.** A watchdog is what makes silence
trustworthy. Chattering to prove you're alive is just noise with good intentions.
