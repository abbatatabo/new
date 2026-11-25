import { tx } from './db.js';
import { uuid } from './security.js';
import * as v from './validate.js';
import { HttpError } from './validate.js';
import { serializeItemAdmin, serializeGrouping, serializeSource, serializeScholar } from './serialize.js';

// Canonical verse counts (Hafs), used to validate verse ranges when quran.db is absent.
export const AYAH_COUNTS = [
  7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135, 112, 78,
  118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38,
  29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20,
  56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
  11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
];

export const CONTENT_TYPES = ['context', 'tafsir', 'reflection', 'word_note', 'surah_intro'];
export const CATEGORIES = ['direct_quotation', 'paraphrase', 'editorial_summary', 'ai_assisted'];
export const STATUSES = ['draft', 'source_verified', 'reviewed', 'approved', 'published', 'unpublished'];

/** Allowed workflow transitions: target -> { from, role, notOwn }. */
export const TRANSITIONS = {
  source_verified: { from: ['draft'], role: 'editor' },
  reviewed: { from: ['source_verified'], role: 'reviewer' },
  approved: { from: ['reviewed'], role: 'reviewer', notOwn: true },
  published: { from: ['approved', 'unpublished'], role: 'admin' },
  unpublished: { from: ['published'], role: 'admin' },
  draft: { from: ['source_verified', 'reviewed', 'approved', 'unpublished'], role: 'editor' },
};

const ROLES = ['user', 'editor', 'reviewer', 'admin'];

export function registerAdminRoutes(router, ctx) {
  const { db } = ctx;

  function audit(user, action, entity, entityId, detail) {
    db.prepare('INSERT INTO audit_log (user_id, user_email, action, entity, entity_id, detail, at) VALUES (?,?,?,?,?,?,?)')
      .run(user.id, user.email, action, entity, entityId ?? null, detail ? JSON.stringify(detail) : null, ctx.iso());
  }
  function markRemoved(id, kind) {
    db.prepare('INSERT INTO removals (id, kind, removed_at) VALUES (?,?,?) ON CONFLICT(id, kind) DO UPDATE SET removed_at = excluded.removed_at')
      .run(id, kind, ctx.iso());
  }
  function clearRemoved(id, kind) {
    db.prepare('DELETE FROM removals WHERE id = ? AND kind = ?').run(id, kind);
  }

  function verseRange(body) {
    const surah = v.int(body.surah, 'surah', { min: 1, max: 114 });
    const max = AYAH_COUNTS[surah - 1];
    const start = v.int(body.start_ayah, 'start_ayah', { min: 1, max });
    const end = v.int(body.end_ayah, 'end_ayah', { min: start, max });
    return { surah, start, end };
  }
  const optRef = (table, value, name) => {
    if (value === undefined || value === null || value === '') return null;
    v.id(value, name);
    if (!db.prepare(`SELECT 1 FROM ${table} WHERE id = ?`).get(value)) throw v.bad(`${name} does not exist`);
    return value;
  };

  // ---------------- Content items ----------------
  function parseItem(body) {
    v.obj(body);
    const { surah, start, end } = verseRange(body);
    const citation = body.citation === undefined || body.citation === null ? {} : v.obj(body.citation, 'citation');
    const cit = {};
    for (const k of ['volume', 'page', 'edition']) {
      const s = v.str(citation[k], `citation.${k}`, { max: 200, optional: true });
      if (s) cit[k] = s;
    }
    const u = v.url(citation.url, 'citation.url');
    if (u) cit.url = u;
    const category = v.oneOf(body.category, 'category', CATEGORIES);
    const sourceId = optRef('sources', body.source_id, 'source_id');
    const scholarId = optRef('scholars', body.scholar_id, 'scholar_id');
    if (category === 'direct_quotation' && !sourceId) throw v.bad('A direct quotation must reference a source');
    return {
      type: v.oneOf(body.type, 'type', CONTENT_TYPES),
      category,
      surah, start, end,
      word_position: v.int(body.word_position, 'word_position', { min: 1, max: 200, optional: true }),
      title: v.str(body.title, 'title', { max: 300, optional: true }),
      body: v.str(body.body, 'body', { min: 1, max: 50000 }),
      language: v.str(body.language ?? 'en', 'language', { min: 2, max: 10 }),
      source_id: sourceId,
      scholar_id: scholarId,
      citation: JSON.stringify(cit),
    };
  }
  const getItem = (id) => {
    const r = db.prepare('SELECT * FROM content_items WHERE id = ?').get(id);
    if (!r) throw new HttpError(404, 'Content item not found');
    return r;
  };

  router.add('GET', '/api/admin/content', ({ requireRole, query }) => {
    requireRole('editor');
    const where = [];
    const args = [];
    const status = query.get('status');
    if (status) { where.push('status = ?'); args.push(v.oneOf(status, 'status', STATUSES)); }
    const type = query.get('type');
    if (type) { where.push('type = ?'); args.push(v.oneOf(type, 'type', CONTENT_TYPES)); }
    const surah = query.get('surah');
    if (surah) { where.push('surah = ?'); args.push(v.int(surah, 'surah', { min: 1, max: 114 })); }
    const q = query.get('q');
    if (q) { where.push('(title LIKE ? OR body LIKE ?)'); args.push(`%${q}%`, `%${q}%`); }
    const sql = `SELECT * FROM content_items ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
      ORDER BY surah, start_ayah, updated_at DESC LIMIT 500`;
    return { body: { items: db.prepare(sql).all(...args).map(serializeItemAdmin) } };
  });

  router.add('GET', '/api/admin/content/:id', ({ requireRole, params }) => {
    requireRole('editor');
    return { body: { item: serializeItemAdmin(getItem(params.id)) } };
  });

  router.add('POST', '/api/admin/content', ({ requireRole, body }) => {
    const user = requireRole('editor');
    const it = parseItem(body);
    const id = uuid();
    const now = ctx.iso();
    db.prepare(`INSERT INTO content_items (id, type, category, surah, start_ayah, end_ayah, word_position, title, body,
      language, source_id, scholar_id, citation, status, version, created_by, updated_by, created_at, updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?, 'draft', 1, ?, ?, ?, ?)`)
      .run(id, it.type, it.category, it.surah, it.start, it.end, it.word_position, it.title, it.body, it.language,
        it.source_id, it.scholar_id, it.citation, user.id, user.id, now, now);
    audit(user, 'create', 'content', id, { type: it.type, category: it.category });
    return { status: 201, body: { item: serializeItemAdmin(getItem(id)) } };
  });

  router.add('PUT', '/api/admin/content/:id', ({ requireRole, params, body }) => {
    const user = requireRole('editor');
    const existing = getItem(params.id);
    const it = parseItem(body);
    tx(db, () => {
      // Any edit resets the workflow: a changed text must be verified and reviewed again.
      db.prepare(`UPDATE content_items SET type=?, category=?, surah=?, start_ayah=?, end_ayah=?, word_position=?,
        title=?, body=?, language=?, source_id=?, scholar_id=?, citation=?, status='draft', reviewer=NULL,
        verified_at=NULL, version=version+1, updated_by=?, updated_at=? WHERE id=?`)
        .run(it.type, it.category, it.surah, it.start, it.end, it.word_position, it.title, it.body, it.language,
          it.source_id, it.scholar_id, it.citation, user.id, ctx.iso(), params.id);
      if (existing.status === 'published') markRemoved(params.id, 'content');
      audit(user, 'update', 'content', params.id, { previous_status: existing.status, previous_version: existing.version });
    });
    return { body: { item: serializeItemAdmin(getItem(params.id)) } };
  });

  router.add('POST', '/api/admin/content/:id/status', ({ requireRole, user, params, body }) => {
    requireRole('editor');
    v.obj(body);
    const target = v.oneOf(body.status, 'status', Object.keys(TRANSITIONS));
    const rule = TRANSITIONS[target];
    requireRole(rule.role);
    const item = getItem(params.id);
    if (!rule.from.includes(item.status)) {
      throw new HttpError(409, `Cannot move from ${item.status} to ${target}`);
    }
    if (rule.notOwn && (item.created_by === user.id || item.updated_by === user.id)) {
      throw new HttpError(403, 'You cannot approve content you created or last edited');
    }
    tx(db, () => {
      const now = ctx.iso();
      if (target === 'reviewed' || target === 'approved') {
        db.prepare('UPDATE content_items SET status=?, reviewer=?, verified_at=?, updated_at=? WHERE id=?')
          .run(target, user.email, now, now, item.id);
      } else {
        db.prepare('UPDATE content_items SET status=?, updated_at=? WHERE id=?').run(target, now, item.id);
      }
      if (target === 'published') clearRemoved(item.id, 'content');
      if (item.status === 'published') markRemoved(item.id, 'content');
      audit(user, 'status', 'content', item.id, { from: item.status, to: target, note: body.note ?? null });
    });
    return { body: { item: serializeItemAdmin(getItem(item.id)) } };
  });

  router.add('DELETE', '/api/admin/content/:id', ({ requireRole, params }) => {
    const user = requireRole('admin');
    const item = getItem(params.id);
    tx(db, () => {
      db.prepare('DELETE FROM content_items WHERE id = ?').run(item.id);
      markRemoved(item.id, 'content');
      audit(user, 'delete', 'content', item.id, { status: item.status });
    });
    return { status: 204 };
  });

  router.add('GET', '/api/admin/review-queue', ({ requireRole }) => {
    requireRole('editor');
    const q = (s) => db.prepare('SELECT * FROM content_items WHERE status = ? ORDER BY updated_at').all(s).map(serializeItemAdmin);
    return {
      body: {
        drafts: q('draft'),
        awaiting_review: q('source_verified'),
        awaiting_approval: q('reviewed'),
        awaiting_publication: q('approved'),
      },
    };
  });

  router.add('GET', '/api/admin/stats', ({ requireRole }) => {
    requireRole('editor');
    const byStatus = Object.fromEntries(STATUSES.map((s) => [s, 0]));
    for (const r of db.prepare('SELECT status, COUNT(*) n FROM content_items GROUP BY status').all()) byStatus[r.status] = r.n;
    return {
      body: {
        content_by_status: byStatus,
        sources: db.prepare('SELECT COUNT(*) n FROM sources').get().n,
        scholars: db.prepare('SELECT COUNT(*) n FROM scholars').get().n,
        groupings: db.prepare('SELECT COUNT(*) n FROM groupings').get().n,
        users: db.prepare('SELECT COUNT(*) n FROM users').get().n,
        quran_db_loaded: !!ctx.quranDb,
      },
    };
  });

  // ---------------- Generic metadata CRUD ----------------
  function crud(name, table, { role = 'editor', deleteRole = 'admin', parse, serialize }) {
    const get = (id) => {
      const r = db.prepare(`SELECT * FROM ${table} WHERE id = ?`).get(id);
      if (!r) throw new HttpError(404, `${name} not found`);
      return r;
    };
    router.add('GET', `/api/admin/${name}`, ({ requireRole }) => {
      requireRole('editor');
      return { body: { [name]: db.prepare(`SELECT * FROM ${table} ORDER BY created_at`).all().map(serialize) } };
    });
    router.add('POST', `/api/admin/${name}`, ({ requireRole, body }) => {
      const user = requireRole(role);
      const fields = parse(v.obj(body));
      const id = body.id ? v.id(body.id, 'id') : uuid();
      const now = ctx.iso();
      const cols = Object.keys(fields);
      db.prepare(`INSERT INTO ${table} (id, ${cols.join(', ')}, created_at, updated_at) VALUES (?, ${cols.map(() => '?').join(', ')}, ?, ?)`)
        .run(id, ...Object.values(fields), now, now);
      audit(user, 'create', name, id, fields);
      return { status: 201, body: { item: serialize(get(id)) } };
    });
    router.add('PUT', `/api/admin/${name}/:id`, ({ requireRole, params, body }) => {
      const user = requireRole(role);
      get(params.id);
      const fields = parse(v.obj(body));
      const cols = Object.keys(fields);
      db.prepare(`UPDATE ${table} SET ${cols.map((c) => `${c} = ?`).join(', ')}, updated_at = ? WHERE id = ?`)
        .run(...Object.values(fields), ctx.iso(), params.id);
      audit(user, 'update', name, params.id, fields);
      return { body: { item: serialize(get(params.id)) } };
    });
    router.add('DELETE', `/api/admin/${name}/:id`, ({ requireRole, params }) => {
      const user = requireRole(deleteRole);
      get(params.id);
      db.prepare(`DELETE FROM ${table} WHERE id = ?`).run(params.id);
      audit(user, 'delete', name, params.id);
      return { status: 204 };
    });
  }

  crud('sources', 'sources', {
    parse: (b) => ({
      title: v.str(b.title, 'title', { min: 1, max: 500 }),
      author: v.str(b.author, 'author', { max: 300, optional: true }),
      edition: v.str(b.edition, 'edition', { max: 300, optional: true }),
      publisher: v.str(b.publisher, 'publisher', { max: 300, optional: true }),
      year: v.str(b.year, 'year', { max: 50, optional: true }),
      url: v.url(b.url, 'url'),
      license: v.str(b.license, 'license', { min: 1, max: 2000 }),
      notes: v.str(b.notes, 'notes', { max: 5000, optional: true }),
    }),
    serialize: serializeSource,
  });

  crud('scholars', 'scholars', {
    parse: (b) => ({
      name: v.str(b.name, 'name', { min: 1, max: 300 }),
      death_year_ah: v.int(b.death_year_ah, 'death_year_ah', { min: 1, max: 1600, optional: true }),
      death_year_ce: v.int(b.death_year_ce, 'death_year_ce', { min: 600, max: 2200, optional: true }),
      bio_url: v.url(b.bio_url, 'bio_url'),
    }),
    serialize: serializeScholar,
  });

  crud('audio', 'audio_reciters', {
    role: 'admin',
    parse: (b) => {
      const pattern = v.str(b.file_pattern ?? '{surah3}{ayah3}.mp3', 'file_pattern', { min: 3, max: 200 });
      if (!/\{surah3\}|\{surah\}/.test(pattern) || !/\{ayah3\}|\{ayah\}/.test(pattern)) {
        throw v.bad('file_pattern must contain {surah3}/{surah} and {ayah3}/{ayah}');
      }
      const base = v.url(b.base_url, 'base_url', { optional: false });
      if (!base.startsWith('https://')) throw v.bad('base_url must use https');
      return {
        name: v.str(b.name, 'name', { min: 1, max: 200 }),
        style: v.str(b.style, 'style', { max: 100, optional: true }),
        base_url: base,
        file_pattern: pattern,
        license: v.str(b.license, 'license', { min: 1, max: 2000 }),
        source_url: v.url(b.source_url, 'source_url'),
        enabled: b.enabled === undefined ? 1 : (v.bool(b.enabled, 'enabled') ? 1 : 0),
        notes: v.str(b.notes, 'notes', { max: 5000, optional: true }),
      };
    },
    serialize: (r) => ({ ...r, enabled: !!r.enabled }),
  });

  crud('translations', 'translations_meta', {
    role: 'admin',
    parse: (b) => ({
      code: v.str(b.code, 'code', { min: 2, max: 50 }),
      name: v.str(b.name, 'name', { min: 1, max: 200 }),
      translator: v.str(b.translator, 'translator', { min: 1, max: 300 }),
      language: v.str(b.language, 'language', { min: 2, max: 20 }),
      license: v.str(b.license, 'license', { min: 1, max: 2000 }),
      source_url: v.url(b.source_url, 'source_url'),
      enabled: b.enabled === undefined ? 1 : (v.bool(b.enabled, 'enabled') ? 1 : 0),
    }),
    serialize: (r) => ({ ...r, enabled: !!r.enabled }),
  });

  // ---------------- Study grouping overrides ----------------
  const getGrouping = (id) => {
    const r = db.prepare('SELECT * FROM groupings WHERE id = ?').get(id);
    if (!r) throw new HttpError(404, 'Grouping not found');
    return r;
  };
  const parseGrouping = (b) => {
    v.obj(b);
    const { surah, start, end } = verseRange(b);
    return { surah, start, end, rationale: v.str(b.rationale, 'rationale', { min: 3, max: 2000 }) };
  };
  router.add('GET', '/api/admin/groupings', ({ requireRole }) => {
    requireRole('editor');
    return { body: { groupings: db.prepare('SELECT * FROM groupings ORDER BY surah, start_ayah').all().map(serializeGrouping) } };
  });
  router.add('POST', '/api/admin/groupings', ({ requireRole, body }) => {
    const user = requireRole('editor');
    const g = parseGrouping(body);
    const id = uuid();
    const now = ctx.iso();
    db.prepare("INSERT INTO groupings (id, surah, start_ayah, end_ayah, rationale, status, created_by, created_at, updated_at) VALUES (?,?,?,?,?,'draft',?,?,?)")
      .run(id, g.surah, g.start, g.end, g.rationale, user.id, now, now);
    audit(user, 'create', 'grouping', id, g);
    return { status: 201, body: { grouping: serializeGrouping(getGrouping(id)) } };
  });
  router.add('PUT', '/api/admin/groupings/:id', ({ requireRole, params, body }) => {
    const user = requireRole('editor');
    const existing = getGrouping(params.id);
    const g = parseGrouping(body);
    db.prepare("UPDATE groupings SET surah=?, start_ayah=?, end_ayah=?, rationale=?, status='draft', updated_at=? WHERE id=?")
      .run(g.surah, g.start, g.end, g.rationale, ctx.iso(), params.id);
    if (existing.status === 'published') markRemoved(params.id, 'grouping');
    audit(user, 'update', 'grouping', params.id, g);
    return { body: { grouping: serializeGrouping(getGrouping(params.id)) } };
  });
  router.add('POST', '/api/admin/groupings/:id/status', ({ requireRole, params, body }) => {
    const user = requireRole('admin');
    v.obj(body);
    const target = v.oneOf(body.status, 'status', ['draft', 'published', 'unpublished']);
    const g = getGrouping(params.id);
    if (target === 'published') {
      // Published overrides in the same surah must not overlap.
      const overlap = db.prepare(`SELECT id FROM groupings WHERE status='published' AND surah=? AND id<>?
        AND start_ayah <= ? AND end_ayah >= ?`).get(g.surah, g.id, g.end_ayah, g.start_ayah);
      if (overlap) throw new HttpError(409, 'Overlaps another published grouping in this surah');
    }
    db.prepare('UPDATE groupings SET status=?, updated_at=? WHERE id=?').run(target, ctx.iso(), g.id);
    if (target === 'published') clearRemoved(g.id, 'grouping');
    else if (g.status === 'published') markRemoved(g.id, 'grouping');
    audit(user, 'status', 'grouping', g.id, { from: g.status, to: target });
    return { body: { grouping: serializeGrouping(getGrouping(g.id)) } };
  });
  router.add('DELETE', '/api/admin/groupings/:id', ({ requireRole, params }) => {
    const user = requireRole('admin');
    const g = getGrouping(params.id);
    db.prepare('DELETE FROM groupings WHERE id = ?').run(g.id);
    markRemoved(g.id, 'grouping');
    audit(user, 'delete', 'grouping', g.id);
    return { status: 204 };
  });

  // ---------------- Surahs & verses (read-only) ----------------
  router.add('GET', '/api/admin/surahs', ({ requireRole }) => {
    requireRole('editor');
    if (!ctx.quranDb) {
      return { body: { surahs: AYAH_COUNTS.map((n, i) => ({ number: i + 1, ayah_count: n })), quran_db_loaded: false } };
    }
    return { body: { surahs: ctx.quranDb.prepare('SELECT * FROM surahs ORDER BY number').all(), quran_db_loaded: true } };
  });
  router.add('GET', '/api/admin/surahs/:n/verses', ({ requireRole, params }) => {
    requireRole('editor');
    const n = v.int(params.n, 'surah', { min: 1, max: 114 });
    if (!ctx.quranDb) throw new HttpError(503, 'Bundled Quran database not available on this server');
    const verses = ctx.quranDb.prepare(`SELECT v.id, v.surah, v.ayah, v.text_uthmani, v.juz, v.page,
        (SELECT text FROM translation_text t WHERE t.translation_id = 1 AND t.verse_id = v.id) AS translation
      FROM verses v WHERE v.surah = ? ORDER BY v.ayah`).all(n);
    return { body: { surah: n, verses, read_only: true, notice: 'Quran text is verbatim Tanzil text and cannot be edited (Tanzil licence: changing it is not allowed).' } };
  });
  const readOnly = () => {
    throw new HttpError(405, 'Quran verse text is read-only. It is verbatim Tanzil text; the licence forbids changes. Update the source file and rebuild with tools/build_content.py.');
  };
  for (const m of ['POST', 'PUT', 'DELETE']) {
    router.add(m, '/api/admin/verses', readOnly);
    router.add(m, '/api/admin/verses/:id', readOnly);
    router.add(m, '/api/admin/surahs/:n/verses', readOnly);
  }

  // ---------------- Users ----------------
  router.add('GET', '/api/admin/users', ({ requireRole }) => {
    requireRole('admin');
    return { body: { users: db.prepare('SELECT id, email, role, created_at FROM users ORDER BY created_at').all() } };
  });
  router.add('PUT', '/api/admin/users/:id/role', ({ requireRole, params, body }) => {
    const user = requireRole('admin');
    v.obj(body);
    const role = v.oneOf(body.role, 'role', ROLES);
    if (params.id === user.id && role !== 'admin') throw new HttpError(409, 'You cannot remove your own admin role');
    const target = db.prepare('SELECT id, email, role FROM users WHERE id = ?').get(params.id);
    if (!target) throw new HttpError(404, 'User not found');
    db.prepare('UPDATE users SET role = ? WHERE id = ?').run(role, params.id);
    audit(user, 'role', 'user', params.id, { from: target.role, to: role });
    return { body: { user: { ...target, role } } };
  });
  router.add('DELETE', '/api/admin/users/:id', ({ requireRole, params }) => {
    const user = requireRole('admin');
    if (params.id === user.id) throw new HttpError(409, 'Use account deletion to delete your own account');
    const target = db.prepare('SELECT id FROM users WHERE id = ?').get(params.id);
    if (!target) throw new HttpError(404, 'User not found');
    tx(db, () => {
      db.prepare('DELETE FROM user_records WHERE user_id = ?').run(params.id);
      db.prepare('DELETE FROM tokens WHERE user_id = ?').run(params.id);
      db.prepare('DELETE FROM users WHERE id = ?').run(params.id);
      audit(user, 'delete', 'user', params.id);
    });
    return { status: 204 };
  });

  router.add('GET', '/api/admin/audit', ({ requireRole, query }) => {
    requireRole('admin');
    const limit = v.int(query.get('limit') ?? 200, 'limit', { min: 1, max: 1000 });
    return { body: { entries: db.prepare('SELECT * FROM audit_log ORDER BY id DESC LIMIT ?').all(limit).map((r) => ({ ...r, detail: r.detail ? JSON.parse(r.detail) : null })) } };
  });
}
