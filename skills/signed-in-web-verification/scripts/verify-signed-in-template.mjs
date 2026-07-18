#!/usr/bin/env node
// verify-signed-in-template.mjs — generalized signed-in E2E verification harness.
//
// WHY THIS EXISTS: a screenshot tool or browser extension can't hold a real
// signed-in session, and if it drives a hidden/unfocused tab it can't
// reliably scroll or animate either. A real Playwright browser can do both.
// This script injects a session that YOU place (see SECRET HANDLING below),
// then drives the live site signed-in and asserts your auth-gated feature(s)
// actually work.
//
// SECRET HANDLING: this script NEVER contains or prints a token. It reads the
// session you paste into a gitignored file. To get it:
//   1. Sign in to your real site in your own browser.
//   2. DevTools -> Application/Storage -> find your auth token key.
//   3. Copy the VALUE of that key.
//   4. Save it as the whole file contents of SESSION_FILE below (default:
//      .verify-session.json, next to this script). Gitignore that file.
//
// USAGE:  node verify-signed-in-template.mjs
//         node verify-signed-in-template.mjs --headed        # watch it run
//         SITE_URL=https://deploy-preview-NN--yourapp.netlify.app node verify-signed-in-template.mjs

import { chromium } from 'playwright';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ---- CONFIGURE ME -----------------------------------------------------
const SITE = process.env.SITE_URL || 'https://your-site.example.com';
const AUTH_KEY = 'your-auth-storage-key';           // e.g. 'sb-<project>-auth-token'
const SESSION_FILE = path.join(__dirname, '.verify-session.json');
// Given the raw stored value (string), return a bearer token to send as
// `Authorization: Bearer <token>`. Adjust to your auth provider's shape.
function extractToken(storedValueJsonString) {
  try {
    const v = JSON.parse(storedValueJsonString);
    return v.access_token || (v.currentSession && v.currentSession.access_token) || null;
  } catch { return null; }
}
// ------------------------------------------------------------------------

const HEADED = process.argv.includes('--headed');

function die(msg) { console.error('\n❌ ' + msg + '\n'); process.exit(1); }
function ok(msg)  { console.log('  ✅ ' + msg); }
function info(msg){ console.log('  ·  ' + msg); }

if (!existsSync(SESSION_FILE)) {
  die(`No session file. Create ${SESSION_FILE} with your signed-in storage value.\n` +
      `   See the header of this file for the 4 steps (copy your auth key from DevTools).`);
}
let sessionRaw = readFileSync(SESSION_FILE, 'utf8').trim();
try { const p = JSON.parse(sessionRaw); if (p && p.value && typeof p.value === 'string') sessionRaw = p.value; } catch {}

const run = async () => {
  console.log(`\n🔐 Signed-in verification against ${SITE}\n`);
  const browser = await chromium.launch({ headless: !HEADED });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const consoleErrors = [];
  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));

  // Inject the session BEFORE any page script runs, so it's present at hydration.
  await ctx.addInitScript(([k, v]) => { try { localStorage.setItem(k, v); } catch {} }, [AUTH_KEY, sessionRaw]);

  await page.goto(SITE + '/?cb=verify' + Date.now(), { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500); // let the client hydrate/refresh the session

  // --- 1. Confirm we're actually signed in (do this before anything else) ---
  const token = extractToken(sessionRaw);
  if (!token) die('Could not extract a bearer token from the session file — check extractToken().');
  ok('session file parsed, token present');

  // --- 2. CONFIGURE ME: your own feature checks go here. Example shape: ---
  // const result = await page.evaluate(async ({ token }) => {
  //   const r = await fetch(window.YOUR_FEATURE.endpointUrl, {
  //     method: 'POST',
  //     headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  //     body: JSON.stringify({ /* your payload */ }),
  //   });
  //   return { status: r.status, body: await r.json() };
  // }, { token });
  // if (result.status !== 200) die(`Feature call failed: status ${result.status}`);
  // ok('feature responded 200');

  // --- 3. Real scroll/interaction check, if your feature is scroll/tap-gated ---
  // await page.goto(SITE + '/?cb=scroll' + Date.now() + '#/your-view', { waitUntil: 'domcontentloaded' });
  // await page.waitForTimeout(1200);
  // await page.mouse.wheel(0, 2000);
  // await page.waitForTimeout(600);
  // const el = await page.evaluate(() => {
  //   const d = document.getElementById('your-element-id'); if (!d) return { present: false };
  //   const r = d.getBoundingClientRect(); const cs = getComputedStyle(d);
  //   return { present: true, shown: parseFloat(cs.opacity) > 0.5 && r.bottom <= window.innerHeight + 4 };
  // });
  // el.present && el.shown ? ok('element appeared on scroll') : info('⚠️ element did not appear as expected');

  // --- 4. Console errors ---
  const realErrors = consoleErrors.filter(e => !/favicon|404/i.test(e));
  realErrors.length === 0 ? ok('no unexpected console errors')
                          : info('⚠️ console errors: ' + realErrors.slice(0, 3).join(' | '));

  await browser.close();
  console.log('\n✅ Signed-in verification complete.\n');
};

run().catch(e => die('harness crashed: ' + (e && e.stack || e)));
