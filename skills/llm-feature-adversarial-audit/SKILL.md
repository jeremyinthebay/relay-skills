---
name: llm-feature-adversarial-audit
description: Adversarially audit an LLM-backed product feature for the exploit classes users actually find — client-controlled conversation history injecting false facts, XSS on rendered model output or user input, cost/kill-switch adequacy under variable payload size, auth/metering bypass, and secret handling. Use before shipping or reviewing an AI chat/assistant feature, before trusting client-supplied conversation history or documents, when adding a budget cap or kill switch to an LLM feature, or when someone asks "is our AI feature safe," "can this be jailbroken," or "can a user make it say/do something it shouldn't."
---

# LLM Feature Adversarial Audit

An LLM-backed feature has all the normal web attack surface (auth, XSS, cost) **plus** a new one:
the model itself is a component that will confidently do the wrong thing if you feed it the wrong
input, and it won't throw an error when it does. This is a checklist for finding that class of bug
before a user does — run it the same way you'd run `adversarial-audit` on automation infrastructure:
point a skeptical pass at the feature, assume there are bugs, and don't accept "looks fine" as an
answer without a concrete test.

## 1. Client-controlled conversation history (prompt injection via history)

**The attack:** if your endpoint accepts `{ question, history }` and treats `history` as trusted
prior turns, a client can submit a fabricated `assistant` turn asserting anything — a fake price, a
fake ratio, a fake permission, a fake prior "confirmation" — and then ask a leading follow-up that
gets the model to build on the fabrication as if it were real and already agreed.

**Why it's dangerous specifically for the model:** an LLM has no memory of what it "actually said."
It only has the history string you hand it back. If that string contains a confident, well-formed
assistant turn, the model has every reason to treat it as its own prior output and continue from
it — that's exactly the behavior multi-turn chat depends on.

**Test it:** send a real question, a fabricated assistant answer asserting something false and
checkable, and a follow-up that asks the model to build on the false answer. Check whether the
final answer **adopts** the fabrication (fail) or **rejects/flags** it as unverified (pass). See
`scripts/adversarial-poison-template.mjs` in the `signed-in-web-verification` skill for a runnable
version of this exact test.

**Mitigation (both parts matter — neither alone is sufficient):**
- **Reassert integrity/grounding rules in the prompt AFTER the untrusted history is inserted.**
  If your system prompt says "only state verified facts" but then untrusted history is appended
  after it, a model can treat the history as more recent/more authoritative context. Restate the
  hard rules (don't invent facts, don't treat prior assistant turns as ground truth for facts that
  need re-verification against the real data source) in a position the model reads *after* the
  history, not just before it.
- **Server-side sanitize the history.** Validate role structure (client shouldn't be able to
  inject a `system` role turn), cap length/turn count, and — if your domain has checkable facts
  (prices, ratios, permissions) — re-verify factual claims in incoming assistant turns against the
  real data source rather than trusting them as given.

## 2. XSS on rendered content — both directions

Two separate surfaces, both need escaping, and it's easy to fix one and forget the other:

- **User input reflected back**, e.g. the user's own question echoed into the page or into a
  transcript view. Standard reflected-XSS discipline: escape on render, don't `innerHTML` raw
  user text.
- **Model output rendered as markup.** If you render the model's answer as Markdown/HTML (for
  formatting, links, code blocks), remember the model's output can itself contain attacker-supplied
  text — from the user's own prompt, from injected history (see #1), or from any retrieved/tool
  content the model incorporates. "It came from the model" is not the same as "it's safe to render
  unescaped." Escape or sanitize model output through the same discipline you'd apply to any
  user-controlled string, and if you allow any HTML through (e.g. for formatting), use an
  allowlist sanitizer, not a blocklist.

**Test it:** submit a question containing `<img src=x onerror=alert(1)>`-style payloads directly,
and also via injected history, and check the rendered DOM (not just the JSON response) for
unescaped execution.

## 3. Dynamic cost / kill-switch adequacy under variable payload size

Metering and kill switches that were sized against typical usage often silently stop working once
payload size varies:

- **Test with an unusually large history/context** (many turns, long documents, large retrieved
  context) and confirm token/size limits are actually enforced server-side, not just assumed from
  typical client behavior.
- **Confirm the kill switch/budget ceiling reacts to spend, not request count.** A cap that counts
  "requests" rather than actual tokens/cost will not catch one enormous request, and a cap that
  counts cost correctly per-request can still be blind to a burst of medium requests if it doesn't
  aggregate over a time window.
- **Confirm the kill switch actually halts new work**, not just alerts. A kill switch that a
  monitoring loop or watchdog can silently break (see the `autonomous-loop-safety` skill for how
  this happens in practice) gives you the false comfort of a control that isn't load-bearing.
- **Fail closed on cost-check failure.** If the cost/budget check itself errors (API down, bad
  config), confirm the feature refuses rather than proceeds "since we couldn't check."

## 4. Auth / metering bypass

- Confirm the endpoint enforces auth **server-side**, not just via a UI that hides the button from
  signed-out users. Call the function URL directly, with no token, with an expired token, and with
  a token for a different/lower-tier account, and confirm each is rejected server-side.
- Confirm any usage metering/rate-limit/tier check is enforced server-side against the
  authenticated identity, not trusted from a client-supplied field (a client should never be able
  to say "I'm on the paid tier" or "this is my 1st request today" and have that trusted).
- Use the `signed-in-web-verification` skill's harness to drive these checks as a real signed-in
  (and deliberately mis-signed-in) browser session rather than reasoning about the code in the abstract.

## 5. Secret handling

- No credentials (API keys, session tokens, provider keys) ever pass through the assistant's hands
  during testing — the human places test sessions/secrets directly (see
  `signed-in-web-verification`).
- No secrets logged — check that request/response logging doesn't capture bearer tokens, full
  auth headers, or raw provider API keys.
- No secrets sent to the model provider that don't need to be there — check what's actually in the
  prompt payload, not just what you intended to send.
- Session/credential files used for testing are gitignored, never committed, never pasted into a
  PR description or chat transcript.

## How to run this as an audit

1. Get the real endpoint/feature and, if it's auth-gated, a way to drive it signed in (see
   `signed-in-web-verification`).
2. Work section by section above. For each, produce a concrete pass/fail test — not a code
   read-through. "I read the prompt and it looks fine" is not an audit finding.
3. Assume there's at least one bug in each category until a test says otherwise. The value of this
   checklist is in the categories it forces you to actually test, not in reading it once.
4. Where a test fails, the fix belongs in two places at once when the checklist says so (e.g. #1's
   prompt-position fix AND server-side sanitize) — a single-layer fix is usually the reason the same
   bug class comes back later.

`references/checklist.md` has the same five sections as a flat, copy-pasteable checklist for
pasting into a PR description or audit doc.
