#!/usr/bin/env node
/**
 * mobile-check.mjs — verify a page the way a THUMB does, not the way a hidden tab does.
 *
 * WHY THIS EXISTS:
 *
 * The Claude-in-Chrome extension drives a tab that is never visible or focused:
 *
 *     document.visibilityState  ->  "hidden"
 *     document.hasFocus()       ->  false
 *
 * requestAnimationFrame is throttled to ZERO in a hidden tab. `scroll-behavior: smooth`
 * animates via rAF. So location.hash, scrollIntoView, scrollTo({behavior:'smooth'}) — and even
 * a REAL TRUSTED CLICK on an anchor — all report NO MOVEMENT on a page that works perfectly.
 *
 * That harness reported "the whole site cannot be scrolled." It closed a good PR, produced an
 * alarming brief, burned three builds, and declared a production outage that did not exist.
 * A five-second check on a real phone disproved all of it.
 *
 * Playwright does not have this problem:
 *
 *     visibilityState: "visible"   hasFocus: true   rAF: 34 ticks / 500ms
 *
 * Use THIS for anything behavioural, animated, or mobile. Use the extension for reading a page.
 *
 * USAGE
 *   node mobile-check.mjs <url> [--device "iPhone 15 Pro"] [--shot out.png]
 *   node mobile-check.mjs <url> --tap ".changes-bar" --expect-scroll
 *   node mobile-check.mjs <url> --tap "#row-1"       --expect-visible "#detail-1"
 */

import { chromium, devices } from 'playwright';

const args = process.argv.slice(2);
const url = args[0];
if (!url) { console.error('usage: mobile-check.mjs <url> [--device D] [--tap SEL] [--expect-scroll|--expect-visible SEL] [--shot f.png]'); process.exit(2); }
const arg = (k, d) => { const i = args.indexOf(k); return i > -1 ? (args[i+1] ?? true) : d; };

const deviceName = arg('--device', 'iPhone 15 Pro');
const device = devices[deviceName];
if (!device) { console.error(`unknown device "${deviceName}". Try: iPhone 15 Pro, iPhone SE, Pixel 7, iPad Mini`); process.exit(2); }

const browser = await chromium.launch();
const ctx = await browser.newContext({ ...device });
const page = await ctx.newPage();

const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 160)); });
page.on('pageerror', e => consoleErrors.push('PAGEERROR: ' + String(e).slice(0, 160)));

await page.goto(url, { waitUntil: 'networkidle', timeout: 45000 });

const result = { url, device: deviceName, checks: {} };

// ── Sanity: prove the harness can actually SEE motion. If this fails, trust nothing below. ──
result.harness = await page.evaluate(() => ({
  visibilityState: document.visibilityState,
  hasFocus: document.hasFocus(),
  viewport: `${window.innerWidth}x${window.innerHeight}`,
  touch: 'ontouchstart' in window,
}));
result.harness.rafTicksIn300ms = await page.evaluate(() => new Promise(res => {
  let n = 0; const t0 = performance.now();
  const loop = () => { n++; if (performance.now() - t0 < 300) requestAnimationFrame(loop); else res(n); };
  requestAnimationFrame(loop);
}));
if (result.harness.visibilityState !== 'visible' || result.harness.rafTicksIn300ms < 5) {
  console.log(JSON.stringify({ ...result, FATAL: 'HARNESS IS BLIND — tab not visible or rAF not ticking. Do not trust any animation/scroll result.' }, null, 2));
  await browser.close(); process.exit(3);
}

// ── Horizontal overflow: the thing that started this whole project ──
result.checks.horizontalOverflow = await page.evaluate(() => {
  const de = document.documentElement;
  const bad = [];
  document.querySelectorAll('*').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.overflowX === 'auto' || cs.overflowX === 'scroll') return;   // intentional scroller
    if (el.getBoundingClientRect().right > de.clientWidth + 1) bad.push(el.tagName + '.' + String(el.className).slice(0, 24));
  });
  return { pageOverflows: de.scrollWidth > de.clientWidth, offenders: bad.slice(0, 5), count: bad.length };
});

// ── Touch targets: 44px is Apple's floor, and we shipped 40px more than once ──
result.checks.smallTouchTargets = await page.evaluate(() =>
  [...document.querySelectorAll('a,button,[role=button],input,select,summary')]
    .filter(el => el.offsetParent !== null)
    .map(el => ({ el: el.tagName + '.' + String(el.className).slice(0, 20), h: Math.round(el.getBoundingClientRect().height) }))
    .filter(x => x.h > 0 && x.h < 44).slice(0, 6));

// ── The behavioural test: TAP something and assert what a user would see ──
const tapSel = arg('--tap');
if (tapSel) {
  const before = await page.evaluate(() => window.scrollY);
  await page.locator(tapSel).first().tap();
  await page.waitForTimeout(2000);              // let the smooth-scroll animation FINISH
  const after = await page.evaluate(() => window.scrollY);
  result.checks.tap = { selector: tapSel, scrollBefore: Math.round(before), scrollAfter: Math.round(after), moved: after - before };

  if (arg('--expect-scroll')) {
    result.checks.tap.pass = (after - before) > 300;
    result.checks.tap.verdict = result.checks.tap.pass ? '✅ tapping scrolled the page' : '🔴 tap did NOT scroll';
  }
  const expectVisible = arg('--expect-visible');
  if (typeof expectVisible === 'string') {
    const vis = await page.evaluate(sel => {
      const e = document.querySelector(sel);
      if (!e) return { found: false };
      const r = e.getBoundingClientRect();
      return { found: true, onScreen: r.top > -50 && r.top < window.innerHeight, top: Math.round(r.top) };
    }, expectVisible);
    result.checks.tap.expectVisible = { selector: expectVisible, ...vis };
    result.checks.tap.pass = vis.found && vis.onScreen;
    result.checks.tap.verdict = result.checks.tap.pass ? `✅ ${expectVisible} is on screen after the tap` : `🔴 ${expectVisible} is NOT on screen`;
  }
}

result.checks.consoleErrors = consoleErrors.slice(0, 5);

const shot = arg('--shot');
if (typeof shot === 'string') { await page.screenshot({ path: shot, fullPage: false }); result.screenshot = shot; }

const failed =
  result.checks.horizontalOverflow.pageOverflows ||
  (result.checks.tap && result.checks.tap.pass === false) ||
  consoleErrors.length > 0;

result.VERDICT = failed ? '🔴 FAIL' : '✅ PASS';
console.log(JSON.stringify(result, null, 2));
await browser.close();
process.exit(failed ? 1 : 0);
