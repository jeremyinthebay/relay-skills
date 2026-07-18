# LLM Feature Adversarial Audit — flat checklist

Copy into a PR description or audit doc. Check each box with a concrete test result, not "looks fine."

## 1. Client-controlled conversation history
- [ ] Sent a fabricated assistant turn asserting a false, checkable fact + a leading follow-up
- [ ] Confirmed the model REJECTS/flags the fabrication rather than adopting it
- [ ] System/instruction prompt reasserts integrity/grounding rules AFTER untrusted history is inserted
- [ ] Server sanitizes incoming history: role structure validated, length/turn-count capped
- [ ] Checkable factual claims in incoming history are re-verified against the real data source, not trusted

## 2. XSS on rendered content
- [ ] User input reflected into the page is escaped (tested with `<img src=x onerror=...>` style payload)
- [ ] Model output rendered as Markdown/HTML is escaped/sanitized (tested with a payload delivered via history/tool output, not just direct prompt)
- [ ] Any allowed HTML uses an allowlist sanitizer, not a blocklist

## 3. Dynamic cost / kill-switch adequacy
- [ ] Tested with an unusually large history/context/document and confirmed server-side size limits actually trigger
- [ ] Kill switch/budget ceiling keys on spend (tokens/cost), not naive request count
- [ ] Kill switch verified to actually halt new work, not just alert
- [ ] Cost-check failure (e.g. billing API down) fails CLOSED, not open

## 4. Auth / metering bypass
- [ ] Called the endpoint directly with no token — rejected server-side
- [ ] Called with an expired token — rejected server-side
- [ ] Called with a token for a different/lower-tier account — correct tier enforced server-side
- [ ] Confirmed no client-supplied field (tier, request count, plan) is trusted for metering decisions

## 5. Secret handling
- [ ] No credentials passed through the assistant's hands during testing (human placed test session/secret directly)
- [ ] Logging does not capture bearer tokens / auth headers / provider API keys
- [ ] Prompt payload inspected for secrets that don't need to be there
- [ ] Test session/credential files gitignored, never committed or pasted into chat/PR text
