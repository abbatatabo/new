import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { startServer } from './helpers.js';

const QURAN_DB = new URL('../../app/assets/db/quran.db', import.meta.url).pathname;

test('security headers on API and dashboard', async () => {
  const s = await startServer();
  try {
    for (const path of ['/api/content/published', '/admin/', '/admin/app.js']) {
      const r = await s.req('GET', path);
      assert.equal(r.status, 200, path);
      assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
      assert.equal(r.headers.get('x-frame-options'), 'DENY');
      const csp = r.headers.get('content-security-policy');
      assert.match(csp, /frame-ancestors 'none'/);
      assert.match(csp, /script-src 'self'/);
      assert.doesNotMatch(csp, /unsafe-inline/);
    }
    assert.equal((await s.req('GET', '/admin/../src/app.js')).status, 404, 'no path traversal');
  } finally { await s.close(); }
});

test('dashboard html has no inline scripts or styles (CSP compatible)', () => {
  const html = fs.readFileSync(new URL('../public/admin/index.html', import.meta.url), 'utf8');
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)[^>]*>/);
  assert.doesNotMatch(html, /\sstyle=|\son[a-z]+=/i);
  const js = fs.readFileSync(new URL('../public/admin/app.js', import.meta.url), 'utf8');
  assert.doesNotMatch(js, /innerHTML|eval\(|new Function/);
});

test('CORS allow-list', async () => {
  const s = await startServer({ config: { corsOrigins: ['https://admin.example.org'] } });
  try {
    const ok = await s.req('GET', '/api/content/published', { headers: { Origin: 'https://admin.example.org' } });
    assert.equal(ok.status, 200);
    assert.equal(ok.headers.get('access-control-allow-origin'), 'https://admin.example.org');
    const evil = await s.req('GET', '/api/content/published', { headers: { Origin: 'https://evil.example' } });
    assert.equal(evil.status, 403);
    assert.equal(evil.headers.get('access-control-allow-origin'), null);
    const pre = await s.req('OPTIONS', '/api/sync', { headers: { Origin: 'https://evil.example' } });
    assert.equal(pre.status, 403);
    const noOrigin = await s.req('GET', '/api/content/published');
    assert.equal(noOrigin.status, 200, 'mobile apps send no Origin');
  } finally { await s.close(); }
});

test('unknown routes 404, wrong methods 405, JSON content type enforced', async () => {
  const s = await startServer();
  try {
    assert.equal((await s.req('GET', '/api/nope')).status, 404);
    assert.equal((await s.req('GET', '/api/auth/login')).status, 405);
    const r = await fetch(`${s.base}/api/auth/register`, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: 'email=a' });
    assert.equal(r.status, 415);
  } finally { await s.close(); }
});

test('Quran verse text is immutable: no endpoint modifies it and the DB is opened read-only', async (t) => {
  if (!fs.existsSync(QURAN_DB)) return t.skip('quran.db not built');
  const quranDb = new DatabaseSync(QURAN_DB, { readOnly: true });
  const before = quranDb.prepare("SELECT value FROM meta WHERE key = 'arabic_text_sha256'").get().value;
  const s = await startServer({ quranDb });
  try {
    const admin = await s.userWithRole('admin@example.org', 'admin');
    const verses = await s.req('GET', '/api/admin/surahs/1/verses', { token: admin });
    assert.equal(verses.status, 200);
    assert.equal(verses.body.verses.length, 7);
    assert.equal(verses.body.read_only, true);
    for (const [m, p] of [['PUT', '/api/admin/verses/1'], ['POST', '/api/admin/verses'], ['DELETE', '/api/admin/verses/1'], ['PUT', '/api/admin/surahs/1/verses'], ['POST', '/api/admin/surahs/1/verses']]) {
      const r = await s.req(m, p, { token: admin, body: { text_uthmani: 'tampered' } });
      assert.equal(r.status, 405, `${m} ${p}`);
      assert.match(r.body.error, /read-only/);
    }
    assert.throws(() => quranDb.exec("UPDATE verses SET text_uthmani = 'x' WHERE id = 1"), /readonly/);
    const after = quranDb.prepare("SELECT value FROM meta WHERE key = 'arabic_text_sha256'").get().value;
    assert.equal(after, before);
    const surahs = await s.req('GET', '/api/admin/surahs', { token: admin });
    assert.equal(surahs.body.surahs.length, 114);
  } finally { await s.close(); quranDb.close(); }
});
