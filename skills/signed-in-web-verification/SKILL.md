---
name: signed-in-web-verification
description: Verify auth-gated web flows — signed-in sessions, multi-turn/AI features, scroll-triggered UI — with a real Playwright browser that holds a session YOU place, never the assistant. Use when a screenshot tool or browser extension can't hold a signed-in session or can't drive real scroll/interaction, when verifying a login-gated feature or an AI/chat feature that depends on conversation history, or when someone asks "can you check the AI feature works while signed in" or wants to adversarially test whether a feature accepts poisoned client-supplied input.
---

# Signed-In Web Verification

## The gap this closes

A screenshot tool or browser extension typically can't do two things that auth-gated features
need: it can't **hold a real signed-in session** across a page load, and — if it drives a
never-focused, invisible tab — it can't reliably **scroll or animate** either (see the
`mobile-verification` skill for why: `requestAnimationFrame` ticks to zero in a hidden tab, so
smooth-scroll-triggered UI silently never fires and looks broken when it isn't).

A real Playwright browser, driven by a script instead of a chat tool, does both: it's a visible,
focused page that can hold an injected session and run real scroll/click/wheel events. That's the
only way to verify things like "does the grounded-answer feature actually answer once signed in,"
"does multi-turn history actually get used," or "does the scroll-triggered dock actually appear."

## The one rule that matters more than the code: you place the session, not the assistant

**The script must never contain, generate, print, or receive a real session token.** It only reads
one from a file **you** create by hand, outside the assistant's view:

1. Sign in to the real site yourself, in your own browser.
2. Open DevTools → Application/Storage → find the auth token key (e.g. a Supabase
   `sb-<project>-auth-token`, a JWT cookie, a bearer token in `localStorage`).
3. Copy the **value**, and save it as the entire contents of a local file — e.g.
   `.verify-session.json` — that lives next to the script.
4. **Gitignore that file.** It is a live credential. Never paste its contents into chat, a commit,
   a PR description, or anywhere the assistant echoes text back.

The assistant's job is to write and run the harness. The human's job is the one step that touches
a real secret. Don't let those swap.

## Generalized template

`scripts/verify-signed-in-template.mjs` is a genericized version of a working harness. To adapt it
to a new project, fill in the four `CONFIGURE ME` constants at the top (site URL, the storage key
your auth system uses, and how to pull a bearer token out of the stored value) and replace the
numbered check blocks with assertions for your own feature. The shape to keep:

- Inject the session via `context.addInitScript` **before** navigation, so it's present when the
  app's own auth client hydrates.
- Confirm you're actually signed in (decode the token / read a `/me` endpoint) before asserting
  anything else — if that check fails, every later failure is noise.
- Drive real interaction (`page.mouse.wheel`, real clicks) for anything scroll- or
  animation-gated, not `scrollIntoView` from a hidden context.
- Collect console/page errors throughout and report them at the end.
- Exit non-zero on failure so it's usable as a gate, not just a manual check.

```sh
npm i playwright && npx playwright install chromium
node verify-signed-in-template.mjs                 # headless
node verify-signed-in-template.mjs --headed        # watch it run
SITE_URL=https://deploy-preview-123--myapp.netlify.app node verify-signed-in-template.mjs
```

## The adversarial variant: poisoned-input testing

The same signed-in harness is also the right tool for **adversarially** testing an LLM-backed
feature: instead of asserting the feature works, you assert it correctly **refuses** hostile
input. `scripts/adversarial-poison-template.mjs` generalizes that pattern — sign in the same way,
then POST a client-supplied conversation history where a fabricated earlier turn asserts something
false, and check whether the feature adopts or rejects the fabrication in its next answer.

This is the same trust boundary as prompt injection: anything the client can supply (history,
uploaded documents, tool results) is untrusted input, and "the feature answered confidently" is not
the same as "the feature answered correctly." See the `llm-feature-adversarial-audit` skill for the
full checklist this one test belongs to — client-controlled history is one entry on it, not the
whole list.

## When to reach for this vs. other tools

| Job | Tool |
|---|---|
| Read markup, grep static HTML, check computed styles | Any automation/extension. Fine. |
| Anything that needs a **signed-in session** | This skill. |
| Anything that needs **real scroll/tap/animation** | This skill, or `mobile-verification`. |
| Testing whether a feature **rejects hostile client input** | The adversarial variant here, feeding into `llm-feature-adversarial-audit`. |
| "Does this feel right" | Ask a human. |

## Common failure modes to check for

- **"Session did not hydrate"** almost always means the token expired — re-copy it from DevTools
  rather than debugging the harness.
- A signed-in check that only looks at `localStorage` presence, not token validity, will report
  false positives once the token expires but hasn't been cleared.
- Forgetting the cache-buster (`?cb=<random>`) when checking a CDN-fronted site means you may be
  verifying a stale cached page, not the deploy you think you're testing.
