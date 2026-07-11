// @ts-check
/**
 * Contract tests — verifies both APIs return identical response shapes.
 *
 * Covers ALL endpoints from api-contract.md. Run with both APIs live against
 * the same database.
 *
 * Usage:
 *   node scripts/contract-tests.js --old-api http://localhost:8000 --new-api http://localhost:5131
 *   node scripts/contract-tests.js --old-api https://my-purchases-api.onrender.com --new-api http://localhost:5131
 *
 * Requires: Node 18+
 */

const https = require('https');
const http = require('http');

const args = Object.fromEntries(
  process.argv.slice(2).map(a => a.startsWith('--') ? a.slice(2).split('=') : [])
);

const OLD_API = (args['old-api'] || 'https://my-purchases-api.onrender.com').replace(/\/+$/, '');
const NEW_API = (args['new-api'] || 'http://localhost:5131').replace(/\/+$/, '');

// =========================================================================
// Endpoint definitions — one entry per API contract row
// =========================================================================
// Each entry:
//   method, path, body?, expectStatus: [array of accepted status codes],
//   note?: string, skip?: true (known drift / stub), criticalDiff?: string

const ENDPOINTS = [
  // ── 1. Health ──────────────────────────────────────────────────────────
  { method: 'GET', path: '/health/live', expectStatus: [200], note: 'Instant liveness probe' },
  { method: 'GET', path: '/health/ready', expectStatus: [200, 503], note: 'DB + schema check' },
  { method: 'GET', path: '/health', expectStatus: [200], note: 'Config + AI probes' },
  { method: 'HEAD', path: '/health/live', expectStatus: [200], note: 'Uptime probe' },

  // ── 2. Auth ───────────────────────────────────────────────────────────
  // 401 tests (no credentials)
  { method: 'POST', path: '/v1/auth/login', body: { email: 'nonexistent@test.com', password: 'wrong' }, expectStatus: [401], note: 'Invalid credentials returns 401' },
  { method: 'POST', path: '/v1/auth/register', body: { email: 'test@test.com', username: 'test', password: 'test123456', name: 'Test' }, expectStatus: [201, 200], note: 'Register; 201 new, 200 if already exists' },
  { method: 'POST', path: '/v1/auth/refresh', body: { refresh_token: 'invalid' }, expectStatus: [401], note: 'Invalid refresh token returns 401' },
  { method: 'POST', path: '/v1/auth/forgot-password', body: { email: 'test@test.com' }, expectStatus: [200], note: 'Forgot password always returns 200' },
  { method: 'POST', path: '/v1/auth/reset-password', body: { token: 'invalid', new_password: 'newpass123' }, expectStatus: [200, 422], note: 'Invalid token; .NET may return 422' },

  // ── 3. Me (requires auth — test without) ──────────────────────────────
  { method: 'GET', path: '/v1/me/profile', expectStatus: [401], note: 'Unauthenticated returns 401' },
  { method: 'GET', path: '/v1/me/businesses', expectStatus: [401], note: 'Unauthenticated returns 401' },

  // ── 4. Catalog (stubs in .NET for some) ───────────────────────────────
  // Categories
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/item-categories', expectStatus: [401, 403, 404], note: 'No auth — 401. Bad biz ID — 404.' },
  { method: 'POST', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/item-categories', body: { name: 'Test Cat' }, expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/item-categories/00000000-0000-0000-0000-000000000000', expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/category-types-index', expectStatus: [401, 403, 404], note: 'No auth' },

  // Catalog items
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/catalog-items', expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/catalog-items/00000000-0000-0000-0000-000000000000', expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/catalog/fuzzy-check?name=rice', expectStatus: [401, 403, 404], note: 'No auth' },

  // Variants
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/catalog-items/00000000-0000-0000-0000-000000000000/variants', expectStatus: [401, 403, 404], note: 'No auth' },

  // ── 5. Contacts (stubs in .NET — skip until implemented) ──────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/suppliers', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/brokers', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 6. Trade Purchases (live in .NET) ─────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/trade-purchases/draft', expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/trade-purchases/next-human-id', expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/trade-purchases/delivery-pipeline', expectStatus: [401, 403, 404], note: 'No auth' },

  // ── 7. Stock (stubs in .NET) ──────────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/stock/list', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/stock/inventory-summary', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/stock/alerts/summary', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 8. Stock Audits (stubs in .NET) ───────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/stock-audits', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 9. Reports (stubs in .NET) ────────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/reports/trade', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/reports/trade/summary', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 10. Users (live in .NET) ───────────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/users', expectStatus: [401, 403, 404], note: 'No auth' },
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/users/active-sessions', expectStatus: [401, 403, 501], note: 'Returns 501 in FastAPI if auth' },

  // ── 11. Dashboard (stub in .NET) ──────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/dashboard?month=2026-01', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 12. Search (stub in .NET) ─────────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/search?q=rice', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 13. Notifications (stub in .NET) ──────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/notifications', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 14. Operations (stub in .NET) ─────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/operations/checklists', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 15. Exports (stub in .NET) ────────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/exports/stock-inventory.xlsx', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 16. Media / OCR (stub in .NET) ────────────────────────────────────
  { method: 'POST', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/media/ocr', body: { image_data: '' }, expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 17. Public Items (stub in .NET) ───────────────────────────────────
  { method: 'GET', path: '/v1/public/items/test-token', expectStatus: [200, 404, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 18. Real-time (stub in .NET) ──────────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/realtime/events', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },

  // ── 19. Damage Reports (stub in .NET) ─────────────────────────────────
  { method: 'GET', path: '/v1/businesses/00000000-0000-0000-0000-000000000000/damage-reports/pending-count', expectStatus: [401, 501], note: 'Stub in .NET returns 501', skip: true },
];

// =========================================================================
// Test runner
// =========================================================================

function request(apiBase, { method, path, body, expectStatus }) {
  return new Promise((resolve) => {
    const url = new URL(path, apiBase);
    const opts = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method,
      headers: { 'Content-Type': 'application/json' },
      rejectUnauthorized: false,
      timeout: 10000,
    };

    const proto = apiBase.startsWith('https') ? https : http;
    const req = proto.request(opts, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        let parsed;
        try { parsed = JSON.parse(data); } catch { parsed = data; }
        resolve({ status: res.statusCode, body: parsed, headers: res.headers });
      });
    });
    req.on('error', (e) => resolve({ status: 0, body: null, error: e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ status: 0, body: null, error: 'timeout' }); });
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function normalize(obj) {
  if (obj === null || obj === undefined) return null;
  if (typeof obj === 'object') {
    if (Array.isArray(obj)) return obj.map(normalize);
    return Object.fromEntries(
      Object.entries(obj)
        .filter(([k]) => !['$id', '$values'].includes(k))
        .map(([k, v]) => [k.replace(/([A-Z])/g, '_$1').toLowerCase(), normalize(v)])
    );
  }
  return obj;
}

function deepCompare(a, b, path = 'root') {
  const diffs = [];
  if (typeof a !== typeof b) {
    diffs.push(`${path}: type mismatch (${typeof a} vs ${typeof b})`);
    return diffs;
  }
  if (a === null && b === null) return diffs;
  if (a === null || b === null) {
    diffs.push(`${path}: null mismatch (${a} vs ${b})`);
    return diffs;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    const maxLen = Math.max(a.length, b.length);
    for (let i = 0; i < maxLen; i++) {
      if (i >= a.length) diffs.push(`${path}[${i}]: missing in old`);
      else if (i >= b.length) diffs.push(`${path}[${i}]: missing in new`);
      else diffs.push(...deepCompare(a[i], b[i], `${path}[${i}]`));
    }
    return diffs;
  }
  if (typeof a === 'object') {
    const allKeys = new Set([...Object.keys(a), ...Object.keys(b)]);
    for (const k of allKeys) {
      if (!(k in a)) diffs.push(`${path}.${k}: missing in old`);
      else if (!(k in b)) diffs.push(`${path}.${k}: missing in new`);
      else diffs.push(...deepCompare(a[k], b[k], `${path}.${k}`));
    }
    return diffs;
  }
  // primitive
  if (a !== b) diffs.push(`${path}: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`);
  return diffs;
}

async function main() {
  let passed = 0, failed = 0, skipped = 0;

  console.log(`OLD API: ${OLD_API}`);
  console.log(`NEW API: ${NEW_API}`);
  console.log('');

  for (const ep of ENDPOINTS) {
    if (ep.skip) {
      console.log(`  SKIP  ${ep.method} ${ep.path}  (${ep.note || 'skipped'})`);
      skipped++;
      continue;
    }

    const [oldRes, newRes] = await Promise.all([
      request(OLD_API, ep),
      request(NEW_API, ep),
    ]);

    const oldOk = ep.expectStatus.includes(oldRes.status);
    const newOk = ep.expectStatus.includes(newRes.status);

    const statusMatch = oldRes.status === newRes.status;
    let shapeDiffs = [];

    if (oldRes.body && newRes.body && typeof oldRes.body === 'object' && typeof newRes.body === 'object') {
      shapeDiffs = deepCompare(normalize(oldRes.body), normalize(newRes.body));
    }

    const name = `${ep.method} ${ep.path}`;
    if (oldOk && newOk && statusMatch && shapeDiffs.length === 0) {
      console.log(`  PASS  ${name}`);
      passed++;
    } else {
      console.log(`  FAIL  ${name}`);
      if (!oldOk) console.log(`        old status ${oldRes.status} (expected ${ep.expectStatus})`);
      if (!newOk) console.log(`        new status ${newRes.status} (expected ${ep.expectStatus})`);
      if (!statusMatch) console.log(`        status mismatch: old=${oldRes.status} new=${newRes.status}`);
      if (oldRes.error) console.log(`        old error: ${oldRes.error}`);
      if (newRes.error) console.log(`        new error: ${newRes.error}`);
      for (const d of shapeDiffs.slice(0, 10)) console.log(`        shape: ${d}`);
      if (ep.criticalDiff) console.log(`        ★ CRITICAL: ${ep.criticalDiff}`);
      failed++;
    }
  }

  console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped, ${passed + failed + skipped} total`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(console.error);
