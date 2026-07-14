---
name: brand-logos-without-rehosting
description: Show real company logos next to brand names — airlines, hotels, banks, SaaS vendors, anything — without scraping or rehosting a single asset file. Resolves each mark at runtime from the brand's own published favicon, with a self-hosted override and a monogram fallback so a missing logo is never a broken image. Use when building a comparison table, directory, vendor dashboard, or any list where a logo makes a row scannable. Also use when logos look fuzzy, when a logo resolves to the wrong brand, or when someone asks whether displaying a brand's logo is allowed.
---

# Brand logos, without rehosting anything

A row labelled "United MileagePlus" reads faster with United's logo beside it. Most people solve this
badly: right-click a logo off a press kit, commit the PNG, watch it rot.

This is the pattern that works, and the traps that cost real deploys.

## The legal shape (know it before you refuse)

Using a company's logo **to identify that company** — not as decoration, not as your own branding,
not implying endorsement — is **nominative use**. Every comparison site, review site and directory on
the internet relies on it. A logo beside a row about that company's product is the textbook case: the
mark is doing *referential* work.

Two genuinely different acts, worth separating:

- **Displaying a mark to identify a brand.** Routine. This is what you're doing.
- **Downloading a brand's asset file and redistributing copies from your server.** Different — you're
  making and hosting copies of a file you don't hold rights to.

**This skill avoids the second entirely.** Nothing is scraped, nothing is committed. Each mark is
fetched **at runtime, by the visitor's browser, from the brand's own domain**. You are not in the
distribution path.

Don't lecture an owner who has already reasoned about this. Engage the actual distinction, or build.

## The chain — first hit wins

```
1. logos/<id>.svg        ← file the owner dropped in (self-hosted override)
2. logos/<id>.png        ← same, PNG
3. DIRECT[<id>]          ← the brand's OWN /favicon.ico, from the brand's domain
4. favicon proxy         ← https://www.google.com/s2/favicons?sz=64&domain=<domain>
5. brand-coloured monogram (UA, MB, DL…)
```

Steps 1–2 let any single logo be upgraded later **without touching code**. Step 4 renders for most
brands. Step 5 means a missing logo is never a broken image.

### ⚠️ Step 3 (DIRECT) usually FAILS. Read this before you use it — I shipped it and it broke.

The idea is sound: the proxy is a cache, and it is sometimes wrong or stale. In a real 39-brand run it
returned a **generic globe** for one airline, and a 16px mush for a retailer whose own domain served a
**scalable SVG**. So: go straight to `https://<brand>/favicon.ico`. Better quality, and the mark comes
from the company itself.

**It does not work, and the reason is invisible to your tests.**

```
curl  https://www.evaair.com/favicon.ico   → 200, valid icon    ✅
curl  https://www.costco.com/favicon.ico   → 200, valid SVG     ✅

<img src="https://www.evaair.com/favicon.ico">  from another origin  → FAILS TO PAINT ❌
<img src="https://www.costco.com/favicon.ico">  from another origin  → FAILS TO PAINT ❌
```

**Hotlink protection.** Those servers see a cross-origin `Referer` and refuse. **`curl` sends no
Referer, so it sails straight through.** Every check you'd naturally run says the URL is fine. The
browser says otherwise, silently, and your logo drops to a monogram.

I verified those URLs with `curl`, shipped them, and two brands fell back to monograms in production.
**A 200 is not a painted logo.**

**If you use a DIRECT entry, verify it with an actual image load, from a different origin:**

```js
const test = src => new Promise(res => {
  const i = new Image();
  i.onload  = () => res({ src, ok: true, w: i.naturalWidth });
  i.onerror = () => res({ src, ok: false });          // ← hotlink block lands here
  i.src = src;
  setTimeout(() => res({ src, ok: false, note: 'timeout' }), 8000);
});
```

Run it **from a page on your own domain**, not from a file:// page and not from curl. Most brands
will fail. Treat DIRECT as a rare exception you have *proven*, not a default.

```js
const LOGO_DOMAIN = { united: "united.com", marriott: "marriott.com", /* … */ };
// DIRECT: only for brands you have PROVEN paint via a real <img> load from your own origin.
// Most brands hotlink-block and will silently fail here (see the warning above).
// The two examples I originally shipped BOTH failed in production. Left empty on purpose.
const DIRECT = {};
const favicon = d => `https://www.google.com/s2/favicons?sz=64&domain=${d}`;

function logoFallback(img, id, mono) {
  const step = img.dataset.tried || "svg";
  if (step === "svg") { img.dataset.tried = "png"; img.src = `logos/${id}.png`; return; }
  if (step === "png" && DIRECT[id]) { img.dataset.tried = "direct"; img.src = DIRECT[id]; return; }
  if ((step === "png" || step === "direct") && LOGO_DOMAIN[id]) {
    img.dataset.tried = "favicon"; img.src = favicon(LOGO_DOMAIN[id]); return;
  }
  img.remove();                       // nothing resolved → monogram
  const m = document.getElementById(mono);
  if (m) m.hidden = false;
}
```

## THE TRAP: `loading="lazy"` silently kills the whole chain

**Never put `loading="lazy"` on these images.**

An offscreen lazy image **never attempts to load**. No load attempt → **`onerror` never fires** → the
entire fallback chain does nothing → you ship a grid of invisible empty tiles that look fine in code
review and broken to a user.

Someone will add it later while "optimising images." Leave a comment saying why it must not be there.

## The second trap: verifying with a status code

1. **`curl` without `-L`.** The favicon endpoint **301s**. Without `-L` you'll conclude every domain
   failed and start fixing things that work.
2. **Checking for HTTP 200.** A 200 says the server answered. It doesn't say a logo was *painted*,
   and it doesn't say it's the **right brand**.

Verify by counting what rendered, in a real browser:

```js
[...document.querySelectorAll('.plogo')].map(m => {
  const img = m.querySelector('img'), mono = m.querySelector('span[id^=mono]');
  if (img && img.complete && img.naturalWidth > 0) return "LOGO " + img.naturalWidth + "px";
  if (mono && !mono.hidden) return "monogram";
  return "PENDING/BROKEN";     // ← any of these = broken chain (usually lazy-loading)
});
```

**Then look at them.** Build a contact sheet — every mark at real display size — screenshot it, and
actually look. That is the only way to catch a logo that resolved to something that isn't the brand.

## Monograms must be unique — check for collisions

The fallback monogram is usually an airline/loyalty code. **Two brands can legitimately share one.**
We shipped `BR` for both **EVA Air** (its IATA code) and **Bilt Rewards** — two unrelated brands
rendering the same two letters, which is worse than no logo at all.

Assert uniqueness across the whole map before you ship. It is three lines and it catches a real bug.

## Detect the generic globe — the silent wrong answer

When a favicon service can't resolve a domain it returns a **default globe**, with HTTP 200. It looks
like a logo. It isn't. Fingerprint it and compare — `scripts/check-favicons.sh` does this.

## Styling that matters

- **White tile behind the mark**: `background:#fff; padding:2px; border-radius:5px`. Most brand marks
  are drawn for light backgrounds; on a dark UI they vanish or look filthy.
- **22px inline, ~34px header-sized.** `object-fit:contain`.
- Restructure the row/pill/table if it fights the logo. Don't wedge.

## Sourcing domains: the part that needs care

A wrong domain gives a globe, or **someone else's logo**. Watch for:

- **Programs whose domain differs from the parent brand.** Flying Blue is `flyingblue.com`, not
  `airfrance.com`. Lufthansa's program is `miles-and-more.com`.
- **Subdomains that serve worse icons than the parent.** `all.accor.com` → 16px; `accor.com` → 64px.
- **Issuers vs. products.** Use the company's domain, not a product marketing page.

## Report quality honestly

Some brands publish bad favicons. The owner needs to know which to replace. From the real run:

| What you'll find | What to say |
|---|---|
| Only a **16×16** favicon exists (two major airlines, one retailer) | Soft at 22px. **Not fixable by you.** Needs a hand-sourced SVG. |
| The favicon is a **wordmark**, not a symbol (a hotel chain's "FOR THE STAY") | Fine at 34px, mush at 22px. |
| Resolves to something **ambiguous** (an orange ring that doesn't read as the brand) | Flag it. Don't ship it silently. |
| Proxy returns a **globe** | Use DIRECT, or accept the monogram. |

**Do not quietly ship something fuzzy and call it done.** The pattern's virtue is that it degrades
honestly, and any single logo can be fixed by dropping a file in `logos/` — no code change.

## Reference

- `scripts/check-favicons.sh` — fetches every domain (**with `-L`**), reports real format and pixel
  size, and flags any that came back as the generic globe.
- `scripts/logo-contact-sheet.html` — throwaway page rendering every mark at 22px and 44px on a dark
  background. Serve it, screenshot it, look at it.
