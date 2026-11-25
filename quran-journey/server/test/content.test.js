import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from './helpers.js';
import { seed } from '../src/seed-data.js';

const draft = (extra = {}) => ({
  type: 'tafsir', category: 'paraphrase', surah: 1, start_ayah: 1, end_ayah: 4,
  title: 'Test', body: 'Body text.', source_id: 'tafsir-ibn-kathir-ar', scholar_id: 'ibn-kathir',
  citation: { volume: '1', page: '20', edition: 'Test edition', url: 'https://example.org/x' }, ...extra,
});

async function setup() {
  const s = await startServer();
  seed(s.db);
  const editor = await s.userWithRole('editor@example.org', 'editor');
  const reviewer = await s.userWithRole('reviewer@example.org', 'reviewer');
  const reviewer2 = await s.userWithRole('reviewer2@example.org', 'reviewer');
  const admin = await s.userWithRole('admin@example.org', 'admin');
  const user = await s.userWithRole('user@example.org', 'user');
  return { s, editor, reviewer, reviewer2, admin, user };
}
const status = (s, token, id, to) => s.req('POST', `/api/admin/content/${id}/status`, { token, body: { status: to } });

test('full workflow: only published items reach the app; unpublish produces removed_ids', async () => {
  const { s, editor, reviewer, admin } = await setup();
  try {
    const c = await s.req('POST', '/api/admin/content', { token: editor, body: draft() });
    assert.equal(c.status, 201);
    const id = c.body.item.id;
    assert.equal(c.body.item.status, 'draft');
    const pub0 = await s.req('GET', '/api/content/published');
    assert.equal(pub0.status, 200);
    assert.equal(pub0.body.items.length, 0, 'drafts are never published (seed draft included)');
    assert.ok(pub0.body.sources.length >= 6);
    assert.ok(pub0.body.scholars.some((x) => x.name === 'Ibn Kathir' && x.death_year_ah === 774));

    assert.equal((await status(s, editor, id, 'source_verified')).status, 200);
    assert.equal((await status(s, reviewer, id, 'reviewed')).status, 200);
    const appr = await status(s, reviewer, id, 'approved');
    assert.equal(appr.status, 200);
    assert.equal(appr.body.item.reviewer, 'reviewer@example.org');
    assert.ok(appr.body.item.verified_at);
    assert.equal((await s.req('GET', '/api/content/published')).body.items.length, 0, 'approved is not yet published');
    assert.equal((await status(s, admin, id, 'published')).status, 200);
    const pub = await s.req('GET', '/api/content/published');
    assert.equal(pub.body.items.length, 1);
    assert.equal(pub.body.items[0].citation.volume, '1');
    assert.equal(pub.body.items[0].category, 'paraphrase');
    assert.equal(pub.body.items[0].created_by, undefined, 'internal fields not exposed publicly');
    const since = pub.body.server_time;

    s.clock.t += 1000;
    assert.equal((await status(s, admin, id, 'unpublished')).status, 200);
    const after = await s.req('GET', `/api/content/published?since=${encodeURIComponent(since)}`);
    assert.equal(after.body.items.length, 0);
    assert.deepEqual(after.body.removed_ids, [id]);
    // Re-publishing clears the removal.
    s.clock.t += 1000;
    assert.equal((await status(s, admin, id, 'published')).status, 200);
    const again = await s.req('GET', '/api/content/published');
    assert.equal(again.body.items.length, 1);
    assert.deepEqual(again.body.removed_ids, []);
  } finally { await s.close(); }
});

test('workflow permissions', async () => {
  const { s, editor, reviewer, reviewer2, admin, user } = await setup();
  try {
    const id = (await s.req('POST', '/api/admin/content', { token: editor, body: draft() })).body.item.id;
    assert.equal((await status(s, editor, id, 'published')).status, 403, 'editor cannot publish');
    assert.equal((await status(s, admin, id, 'published')).status, 409, 'cannot skip steps');
    await status(s, editor, id, 'source_verified');
    assert.equal((await status(s, editor, id, 'reviewed')).status, 403, 'editor cannot review');
    await status(s, reviewer, id, 'reviewed');

    // A reviewer cannot approve an item they created.
    const own = (await s.req('POST', '/api/admin/content', { token: reviewer, body: draft() })).body.item.id;
    await status(s, reviewer, own, 'source_verified');
    await status(s, reviewer, own, 'reviewed');
    const selfApprove = await status(s, reviewer, own, 'approved');
    assert.equal(selfApprove.status, 403);
    assert.equal((await status(s, reviewer2, own, 'approved')).status, 200);

    assert.equal((await s.req('POST', '/api/admin/content', { token: user, body: draft() })).status, 403, 'plain users have no admin access');
    assert.equal((await s.req('GET', '/api/admin/content')).status, 401);
  } finally { await s.close(); }
});

test('editing any item resets it to draft and bumps the version; editing a published item withdraws it', async () => {
  const { s, editor, reviewer, admin } = await setup();
  try {
    const id = (await s.req('POST', '/api/admin/content', { token: editor, body: draft() })).body.item.id;
    await status(s, editor, id, 'source_verified');
    await status(s, reviewer, id, 'reviewed');
    await status(s, reviewer, id, 'approved');
    await status(s, admin, id, 'published');
    const since = (await s.req('GET', '/api/content/published')).body.server_time;
    s.clock.t += 1000;
    const e = await s.req('PUT', `/api/admin/content/${id}`, { token: editor, body: draft({ body: 'Changed body.' }) });
    assert.equal(e.status, 200);
    assert.equal(e.body.item.status, 'draft');
    assert.equal(e.body.item.version, 2);
    assert.equal(e.body.item.reviewer, null);
    const pub = await s.req('GET', `/api/content/published?since=${encodeURIComponent(since)}`);
    assert.equal(pub.body.items.length, 0);
    assert.deepEqual(pub.body.removed_ids, [id]);
    const audit = await s.req('GET', '/api/admin/audit', { token: admin });
    assert.ok(audit.body.entries.some((x) => x.action === 'update' && x.entity_id === id));
    assert.ok(audit.body.entries.filter((x) => x.action === 'status' && x.entity_id === id).length >= 4);
  } finally { await s.close(); }
});

test('content validation', async () => {
  const { s, editor } = await setup();
  try {
    const cases = [
      draft({ surah: 115 }),
      draft({ start_ayah: 8, end_ayah: 8 }), // Al-Fatihah has 7 verses
      draft({ start_ayah: 4, end_ayah: 2 }),
      draft({ category: 'scholar_opinion' }),
      draft({ type: 'hadith' }),
      draft({ body: '' }),
      draft({ source_id: 'does-not-exist' }),
      draft({ category: 'direct_quotation', source_id: null }),
      draft({ citation: { url: 'javascript:alert(1)' } }),
    ];
    for (const c of cases) {
      const r = await s.req('POST', '/api/admin/content', { token: editor, body: c });
      assert.equal(r.status, 400, JSON.stringify(c) + ' -> ' + JSON.stringify(r.body));
    }
  } finally { await s.close(); }
});

test('groupings: editor drafts, admin publishes, overlap rejected, unpublish removes', async () => {
  const { s, editor, admin } = await setup();
  try {
    const g = await s.req('POST', '/api/admin/groupings', { token: editor, body: { surah: 1, start_ayah: 1, end_ayah: 4, rationale: 'Praise (1-4) kept together' } });
    assert.equal(g.status, 201);
    assert.equal((await s.req('POST', `/api/admin/groupings/${g.body.grouping.id}/status`, { token: editor, body: { status: 'published' } })).status, 403);
    assert.equal((await s.req('POST', `/api/admin/groupings/${g.body.grouping.id}/status`, { token: admin, body: { status: 'published' } })).status, 200);
    const g2 = await s.req('POST', '/api/admin/groupings', { token: editor, body: { surah: 1, start_ayah: 3, end_ayah: 7, rationale: 'Overlapping' } });
    assert.equal((await s.req('POST', `/api/admin/groupings/${g2.body.grouping.id}/status`, { token: admin, body: { status: 'published' } })).status, 409);
    const pub = await s.req('GET', '/api/content/published');
    assert.equal(pub.body.groupings.length, 1);
    assert.equal(pub.body.groupings[0].end_ayah, 4);
    await s.req('POST', `/api/admin/groupings/${g.body.grouping.id}/status`, { token: admin, body: { status: 'unpublished' } });
    const after = await s.req('GET', '/api/content/published');
    assert.equal(after.body.groupings.length, 0);
    assert.ok(after.body.removed_ids.includes(g.body.grouping.id));
  } finally { await s.close(); }
});

test('admin-only endpoints reject non-admins; role changes', async () => {
  const { s, editor, reviewer, admin, user } = await setup();
  try {
    for (const t of [user, editor, reviewer]) {
      assert.equal((await s.req('GET', '/api/admin/users', { token: t })).status, 403);
      assert.equal((await s.req('GET', '/api/admin/audit', { token: t })).status, 403);
      assert.equal((await s.req('POST', '/api/admin/audio', { token: t, body: { name: 'x', base_url: 'https://a.example/', license: 'x' } })).status, 403);
    }
    assert.equal((await s.req('GET', '/api/admin/sources', { token: user })).status, 403);
    const users = (await s.req('GET', '/api/admin/users', { token: admin })).body.users;
    const u = users.find((x) => x.email === 'user@example.org');
    const me = users.find((x) => x.email === 'admin@example.org');
    assert.equal((await s.req('PUT', `/api/admin/users/${u.id}/role`, { token: admin, body: { role: 'editor' } })).status, 200);
    assert.equal((await s.req('GET', '/api/admin/sources', { token: user })).status, 200, 'promoted user now has editor access');
    assert.equal((await s.req('PUT', `/api/admin/users/${me.id}/role`, { token: admin, body: { role: 'user' } })).status, 409);
    assert.equal((await s.req('PUT', `/api/admin/users/${u.id}/role`, { token: admin, body: { role: 'superuser' } })).status, 400);
  } finally { await s.close(); }
});

test('metadata CRUD: sources, scholars, audio, translations', async () => {
  const { s, editor, admin } = await setup();
  try {
    const src = await s.req('POST', '/api/admin/sources', { token: editor, body: { title: 'A work', license: 'Public domain', url: 'https://example.org' } });
    assert.equal(src.status, 201);
    assert.equal((await s.req('PUT', `/api/admin/sources/${src.body.item.id}`, { token: editor, body: { title: 'A work (2nd ed.)', license: 'Public domain' } })).body.item.title, 'A work (2nd ed.)');
    assert.equal((await s.req('DELETE', `/api/admin/sources/${src.body.item.id}`, { token: editor })).status, 403);
    assert.equal((await s.req('DELETE', `/api/admin/sources/${src.body.item.id}`, { token: admin })).status, 204);
    assert.equal((await s.req('POST', '/api/admin/scholars', { token: editor, body: { name: 'X', death_year_ah: 99999 } })).status, 400);
    assert.equal((await s.req('POST', '/api/admin/audio', { token: admin, body: { name: 'R', base_url: 'http://insecure.example/', license: 'x' } })).status, 400);
    const a = await s.req('POST', '/api/admin/audio', { token: admin, body: { name: 'R', base_url: 'https://audio.example/r/', license: 'Permission letter on file' } });
    assert.equal(a.status, 201);
    const pubAudio = await s.req('GET', '/api/audio/reciters');
    assert.ok(pubAudio.body.reciters.some((r) => r.name === 'R'));
    assert.equal((await s.req('GET', '/api/admin/translations', { token: editor })).body.translations.length, 3);
  } finally { await s.close(); }
});
