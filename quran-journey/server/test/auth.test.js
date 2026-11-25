import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from './helpers.js';

test('register, login, me, logout', async () => {
  const s = await startServer();
  try {
    const r = await s.req('POST', '/api/auth/register', { body: { email: 'Amina@Example.org', password: 'long-enough-pass' } });
    assert.equal(r.status, 201);
    assert.equal(r.body.user.email, 'amina@example.org');
    assert.equal(r.body.user.role, 'user');
    assert.ok(r.body.token);
    const dup = await s.req('POST', '/api/auth/register', { body: { email: 'amina@example.org', password: 'long-enough-pass' } });
    assert.equal(dup.status, 409);
    const l = await s.req('POST', '/api/auth/login', { body: { email: 'amina@example.org', password: 'long-enough-pass' } });
    assert.equal(l.status, 200);
    const me = await s.req('GET', '/api/auth/me', { token: l.body.token });
    assert.equal(me.status, 200);
    assert.equal(me.body.user.email, 'amina@example.org');
    // Tokens are stored hashed, never in plain text.
    const stored = s.db.prepare('SELECT token_hash FROM tokens').all().map((x) => x.token_hash);
    assert.ok(!stored.includes(l.body.token));
    const out = await s.req('POST', '/api/auth/logout', { token: l.body.token });
    assert.equal(out.status, 204);
    assert.equal((await s.req('GET', '/api/auth/me', { token: l.body.token })).status, 401);
  } finally { await s.close(); }
});

test('registration cannot choose a role; weak passwords and bad emails rejected', async () => {
  const s = await startServer();
  try {
    const r = await s.req('POST', '/api/auth/register', { body: { email: 'x@example.org', password: 'long-enough-pass', role: 'admin' } });
    assert.equal(r.status, 201);
    assert.equal(r.body.user.role, 'user');
    assert.equal((await s.req('POST', '/api/auth/register', { body: { email: 'y@example.org', password: 'short' } })).status, 400);
    assert.equal((await s.req('POST', '/api/auth/register', { body: { email: 'not-an-email', password: 'long-enough-pass' } })).status, 400);
  } finally { await s.close(); }
});

test('bad password is rejected and login is rate limited per ip+email', async () => {
  const s = await startServer();
  try {
    s.makeUser('b@example.org', 'user');
    for (let i = 0; i < 5; i++) {
      const r = await s.req('POST', '/api/auth/login', { body: { email: 'b@example.org', password: 'wrong-password' } });
      assert.equal(r.status, 401);
    }
    const blocked = await s.req('POST', '/api/auth/login', { body: { email: 'b@example.org', password: 'correct-horse-battery' } });
    assert.equal(blocked.status, 429);
    // Window passes -> allowed again.
    s.clock.t += 16 * 60 * 1000;
    const ok = await s.req('POST', '/api/auth/login', { body: { email: 'b@example.org', password: 'correct-horse-battery' } });
    assert.equal(ok.status, 200);
    // Unknown account gives the same 401 as a wrong password.
    const unknown = await s.req('POST', '/api/auth/login', { body: { email: 'nobody@example.org', password: 'whatever-pass' } });
    assert.equal(unknown.status, 401);
    assert.equal(unknown.body.error, 'Incorrect email or password');
  } finally { await s.close(); }
});

test('tokens expire after 30 days', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('c@example.org', 'user');
    s.clock.t += 29 * 24 * 3600 * 1000;
    assert.equal((await s.req('GET', '/api/auth/me', { token: t })).status, 200);
    s.clock.t += 2 * 24 * 3600 * 1000;
    assert.equal((await s.req('GET', '/api/auth/me', { token: t })).status, 401);
  } finally { await s.close(); }
});

test('account export and deletion', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('d@example.org', 'user');
    const sync = await s.req('POST', '/api/sync', { token: t, body: { since: null, changes: [
      { kind: 'note', id: 'n1', updated_at: '2026-11-25T12:00:00.000Z', data: { study_start: 1, study_end: 4, verse_id: null, text: 'My note', created_at: '2026-11-25T12:00:00.000Z' } },
      { kind: 'bookmark', id: 'b1', updated_at: '2026-11-25T12:00:00.000Z', data: { type: 'verse', verse_start: 2, verse_end: 2, ref_id: null, label: null, created_at: '2026-11-25T12:00:00.000Z' } },
    ] } });
    assert.equal(sync.status, 200);
    const ex = await s.req('GET', '/api/account/export', { token: t });
    assert.equal(ex.status, 200);
    assert.equal(ex.body.notes.length, 1);
    assert.equal(ex.body.notes[0].data.text, 'My note');
    assert.equal(ex.body.bookmarks.length, 1);
    assert.equal(ex.body.user.email, 'd@example.org');
    assert.equal(ex.body.user.password_hash, undefined);
    assert.equal((await s.req('DELETE', '/api/account', { token: t, body: { password: 'wrong-password' } })).status, 401);
    assert.equal((await s.req('DELETE', '/api/account', { token: t, body: { password: 'correct-horse-battery' } })).status, 204);
    assert.equal(s.db.prepare('SELECT COUNT(*) n FROM users').get().n, 0);
    assert.equal(s.db.prepare('SELECT COUNT(*) n FROM user_records').get().n, 0);
    assert.equal(s.db.prepare('SELECT COUNT(*) n FROM tokens').get().n, 0);
    assert.equal((await s.req('GET', '/api/auth/me', { token: t })).status, 401);
  } finally { await s.close(); }
});
