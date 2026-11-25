import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from './helpers.js';

const T0 = '2026-11-25T12:00:00.000Z';
const note = (id, text, updated_at, extra = {}) => ({
  kind: 'note', id, updated_at, ...extra,
  data: { study_start: 1, study_end: 4, verse_id: 2, text, created_at: T0 },
});

test('sync round-trips records to a second device', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('a@example.org', 'user');
    const r1 = await s.req('POST', '/api/sync', { token: t, body: { since: null, changes: [
      note('n1', 'first', T0),
      { kind: 'progress', id: 'p1', updated_at: T0, data: { verse_start: 1, verse_end: 4, completed_at: T0 } },
    ] } });
    assert.equal(r1.status, 200);
    assert.equal(r1.body.changes.length, 0, 'own writes are not echoed back');
    const r2 = await s.req('POST', '/api/sync', { token: t, body: { since: null, changes: [] } });
    assert.equal(r2.body.changes.length, 2);
    // Incremental: nothing new since server_time.
    const r3 = await s.req('POST', '/api/sync', { token: t, body: { since: r2.body.server_time, changes: [] } });
    assert.equal(r3.body.changes.length, 0);
  } finally { await s.close(); }
});

test('last writer wins for bookmarks and progress', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('a@example.org', 'user');
    const bm = (label, at) => ({ kind: 'bookmark', id: 'b1', updated_at: at,
      data: { type: 'verse', verse_start: 5, verse_end: 5, ref_id: null, label, created_at: T0 } });
    await s.req('POST', '/api/sync', { token: t, body: { changes: [bm('newer', '2026-11-25T12:05:00.000Z')] } });
    s.clock.t += 1000;
    const stale = await s.req('POST', '/api/sync', { token: t, body: { since: null, changes: [bm('older', '2026-11-25T12:01:00.000Z')] } });
    assert.equal(stale.status, 200);
    const server = stale.body.changes.find((c) => c.id === 'b1');
    assert.equal(server.data.label, 'newer', 'stale write rejected; server copy returned');
    s.clock.t += 1000;
    await s.req('POST', '/api/sync', { token: t, body: { changes: [bm('newest', '2026-11-25T12:09:00.000Z')] } });
    const row = s.db.prepare("SELECT data FROM user_records WHERE id = 'b1'").get();
    assert.equal(JSON.parse(row.data).label, 'newest');
  } finally { await s.close(); }
});

test('concurrent note edits keep both copies (never discard user text)', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('a@example.org', 'user');
    await s.req('POST', '/api/sync', { token: t, body: { changes: [note('n1', 'original', T0)] } });
    // Device A edits (based on T0).
    s.clock.t += 1000;
    await s.req('POST', '/api/sync', { token: t, body: { changes: [note('n1', 'edit from A', '2026-11-25T12:10:00.000Z', { base_updated_at: T0 })] } });
    // Device B also edits from base T0, without having seen A's change.
    s.clock.t += 1000;
    const r = await s.req('POST', '/api/sync', { token: t, body: { since: null, changes: [note('n1', 'edit from B', '2026-11-25T12:11:00.000Z', { base_updated_at: T0 })] } });
    assert.equal(r.status, 200);
    assert.equal(r.body.conflicts.length, 1);
    assert.equal(r.body.conflicts[0].resolution, 'kept_both');
    assert.equal(r.body.conflicts[0].server.data.text, 'edit from A');
    const notes = s.db.prepare("SELECT id, data FROM user_records WHERE kind = 'note'").all().map((x) => ({ id: x.id, ...JSON.parse(x.data) }));
    assert.equal(notes.length, 2);
    assert.ok(notes.some((n) => n.id === 'n1' && n.text === 'edit from A'));
    const copy = notes.find((n) => n.id !== 'n1');
    assert.equal(copy.text, 'edit from B');
    assert.equal(copy.conflict_of, 'n1');
    // Both are returned to device B.
    assert.ok(r.body.changes.some((c) => c.id === 'n1' && c.data.text === 'edit from A'));
    assert.ok(r.body.changes.some((c) => c.id === copy.id));
    // A non-conflicting edit (based on the latest server version) is accepted normally.
    s.clock.t += 1000;
    const ok = await s.req('POST', '/api/sync', { token: t, body: { changes: [note('n1', 'merged', '2026-11-25T12:20:00.000Z', { base_updated_at: '2026-11-25T12:10:00.000Z' })] } });
    assert.equal(ok.body.conflicts.length, 0);
  } finally { await s.close(); }
});

test('deletes propagate as tombstones and are purged after 90 days', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('a@example.org', 'user');
    await s.req('POST', '/api/sync', { token: t, body: { changes: [note('n1', 'x', T0)] } });
    s.clock.t += 1000;
    const since = new Date(s.clock.t).toISOString();
    s.clock.t += 1000;
    await s.req('POST', '/api/sync', { token: t, body: { changes: [{ kind: 'note', id: 'n1', updated_at: '2026-11-25T12:30:00.000Z', deleted: true }] } });
    s.clock.t += 1000;
    const other = await s.req('POST', '/api/sync', { token: t, body: { since, changes: [] } });
    const tomb = other.body.changes.find((c) => c.id === 'n1');
    assert.equal(tomb.deleted, true);
    assert.equal((await s.req('GET', '/api/account/export', { token: t })).body.notes.length, 0);
    s.clock.t += 91 * 24 * 3600 * 1000;
    const t2 = await s.login('a@example.org'); // the 30-day token has expired meanwhile
    assert.equal((await s.req('POST', '/api/sync', { token: t2, body: { changes: [] } })).status, 200);
    assert.equal(s.db.prepare('SELECT COUNT(*) n FROM user_records').get().n, 0);
  } finally { await s.close(); }
});

test('sync validates input and isolates users', async () => {
  const s = await startServer();
  try {
    const a = await s.userWithRole('a@example.org', 'user');
    const b = await s.userWithRole('b@example.org', 'user');
    assert.equal((await s.req('POST', '/api/sync', { body: { changes: [] } })).status, 401);
    const bad = [
      [{ kind: 'secret', id: 'x', updated_at: T0, data: {} }],
      [{ kind: 'note', id: 'bad id!', updated_at: T0, data: {} }],
      [{ kind: 'note', id: 'x', updated_at: 'yesterday', data: {} }],
      [{ kind: 'progress', id: 'x', updated_at: T0, data: { verse_start: 0, verse_end: 7000, completed_at: T0 } }],
      [{ kind: 'note', id: 'x', updated_at: T0, data: { study_start: 1, study_end: 1, text: 5, created_at: T0 } }],
    ];
    for (const changes of bad) {
      const r = await s.req('POST', '/api/sync', { token: a, body: { changes } });
      assert.equal(r.status, 400, JSON.stringify(changes));
    }
    assert.equal((await s.req('POST', '/api/sync', { token: a, body: '{not json' })).status, 400);
    assert.equal((await s.req('POST', '/api/sync', { token: a, body: { changes: 'nope' } })).status, 400);
    await s.req('POST', '/api/sync', { token: a, body: { changes: [note('n1', 'private to A', T0)] } });
    const rb = await s.req('POST', '/api/sync', { token: b, body: { since: null, changes: [] } });
    assert.equal(rb.body.changes.length, 0);
  } finally { await s.close(); }
});

test('request bodies over 1 MB are rejected', async () => {
  const s = await startServer();
  try {
    const t = await s.userWithRole('a@example.org', 'user');
    const big = JSON.stringify({ changes: [], pad: 'x'.repeat(1100 * 1024) });
    const r = await s.req('POST', '/api/sync', { token: t, body: big });
    assert.equal(r.status, 413);
  } finally { await s.close(); }
});
