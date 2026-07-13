---
name: mobile-verification
description: Test what a page actually DOES on a phone — real taps, real scrolling, real animations — using Playwright instead of a browser-automation tab that is structurally blind to motion. Use whenever verifying mobile behaviour, testing touch interactions, checking horizontal overflow or touch-target sizes, before merging any front-end change, or when a scroll/animation/click test reports "nothing happened" and you need to know whether the page is broken or your harness is.
---

# Mobile Verification

## The trap this exists to escape

Most browser-automation tools drive a tab that is **never visible and never focused**:

```
document.visibilityState  ->  "hidden"
document.hasFocus()       ->  false
```

**`requestAnimationFrame` is throttled to ZERO in a hidden tab.** Anything animated silently never moves. And `scroll-behavior: smooth` — which most modern sites set on `html` — animates via rAF.

So on a page that works perfectly for a human, that harness reports:

```
location.hash = '#target'              ->  no movement
element.scrollIntoView()               ->  no movement
window.scrollTo({behavior:'smooth'})   ->  no movement
a REAL TRUSTED MOUSE CLICK on an anchor ->  no movement
```

I concluded *"the whole site cannot be scrolled,"* closed a good PR, wrote an alarming brief, burned three builds, and told the owner production was broken. **A five-second check on his phone proved it worked fine.**

**Know what your harness is structurally blind to.** Mine could not observe motion — not because of a bug, but because of what it *was*.

## The one-line discriminator

Before you ever conclude "the page can't scroll":

```js
window.scrollTo({ top: 1000, behavior: 'instant' });   // bypasses rAF entirely
```

**If INSTANT works and SMOOTH doesn't, your tab is hidden and your test is invalid.** Not the page.

## The fix: Playwright

Playwright's pages are genuinely visible and focused. Verified:

```
visibilityState:  "visible"          hasFocus: true
rAF ticks/300ms:  21                 ← animations actually run
viewport: 393x659   touch: true   dpr: 3   ← real iPhone 15 Pro

REAL TAP → scrollY 0 → 2695, target section landed at top: 0    ✅
```

```sh
npm i playwright && npx playwright install chromium
node scripts/mobile-check.mjs "<url>" --tap ".cta-bar" --expect-visible "#target"
```

`scripts/mobile-check.mjs` checks in one pass:

- **Horizontal overflow** — names the offending elements (ignores intentional `overflow-x:auto` scrollers)
- **Touch targets under 44px** — Apple's floor; we shipped 40px more than once
- **The tap outcome** — did the page scroll, did the expected element land on screen
- **Console errors**
- **A screenshot**

And it **self-aborts** if its own tab isn't visible or rAF isn't ticking. **A harness that cannot see motion should say so, not report a false failure.**

## Prove your harness can FAIL

The most important step, and the one everybody skips:

```sh
# assert something you KNOW is false
node scripts/mobile-check.mjs "<url>" --tap ".cta-bar" --expect-visible "#something-far-away"
# must print 🔴 FAIL
```

**A harness that has never failed cannot be trusted.** If it can't fail on a false assertion, its passes mean nothing. (My first hook test "passed" because the command never ran at all.)

## When to use which tool

| Job | Tool |
|---|---|
| Read the DOM, grep the HTML, inspect computed styles | Any automation / extension. Fine. |
| **Anything a USER DOES** — tap, scroll, animate, transition | **Playwright.** |
| "Does this *feel* right" / "does this look cramped" | **Ask a human.** Five seconds. |

That last row is not a defeat. Some things a harness is *structurally* blind to — visual taste, feel, motion on a real device. **An hour of an agent chasing a ghost is worth strictly less than one five-second look at a phone.**

## Higher-fidelity options, if you need them

- **iOS Simulator** (free, ships with Xcode) — real WebKit/Safari, not Chromium. Use when the bug smells iOS-specific: `-webkit-` quirks, Safari's viewport units, momentum scrolling, input zoom.
- **BrowserStack / LambdaTest / Sauce Labs** (paid) — real physical devices. Use when a bug only reproduces on hardware.

Playwright's Chromium emulation covers the overwhelming majority of layout and interaction bugs, and it's the only one of the three that's free and fast enough to run on every single build.
