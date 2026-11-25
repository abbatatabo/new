import { tx } from './db.js';
import { hashPassword, verifyPassword, newToken, sha256, uuid } from './security.js';
import * as v from './validate.js';
import { HttpError } from './validate.js';
import { serializeItem, serializeGrouping, serializeSource, serializeScholar } from './serialize.js';

const MAX_CHANGES = 2000;

export function registerPublicRoutes(router, ctx) {
  const { db, config } = ctx;

  function issueToken(userId) {
    const token = newToken();
    const created = ctx.iso();
    const expires = new Date(ctx.now() + config.tokenTtlMs).toISOString();
    db.prepare('INSERT INTO tokens (token_hash, user_id, created_at, expires_at) VALUES (?,?,?,?)')
      .run(sha256(token), userId, created, expires);
    return token;
  }
  const publicUser = (u) => ({ id: u.id, email: u.email, role: u.role });

  // ---------------- Auth ----------------
  router.add('POST', '/api/auth/register', ({ body }) => {
    v.obj(body);
    const email = v.email(body.email);
    const password = v.password(body.password);
    const { hash, salt } = hashPassword(password);
    const id = uuid();
    try {
      db.prepare('INSERT INTO users (id, email, password_hash, salt, role, created_at) VALUES (?,?,?,?,?,?)')
        .run(id, email, hash, salt, 'user', ctx.iso());
    } catch (e) {
      if (/UNIQUE/.test(e.message)) throw new HttpError(409, 'An account with this email already exists');
      throw e;
    }
    const user = { id, email, role: 'user' };
    return { status: 201, body: { token: issueToken(id), user } };
  });

  router.add('POST', '/api/auth/login', ({ body, ip }) => {
    v.obj(body);
    const email = v.email(body.email);
    const password = v.str(body.password, 'password', { min: 1, max: 200 });
    const key = `${ip}|${email}`;
    const windowStart = ctx.now() - config.loginWindowMs;
    db.prepare('DELETE FROM login_failures WHERE at < ?').run(windowStart);
    const failures = db.prepare('SELECT COUNT(*) AS n FROM login_failures WHERE key = ? AND at >= ?')
      .get(key, windowStart).n;
    if (failures >= config.loginMaxFailures) {
      throw new HttpError(429, 'Too many failed sign-in attempts. Try again in 15 minutes.');
    }
    const u = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
    // Always run scrypt so timing does not reveal whether the account exists.
    const ok = u ? verifyPassword(password, u.salt, u.password_hash)
      : (verifyPassword(password, 'dummy-salt', 'A'.repeat(88)), false);
    if (!ok) {
      db.prepare('INSERT INTO login_failures (key, at) VALUES (?, ?)').run(key, ctx.now());
      throw new HttpError(401, 'Incorrect email or password');
    }
    db.prepare('DELETE FROM login_failures WHERE key = ?').run(key);
    return { body: { token: issueToken(u.id), user: publicUser(u) } };
  });

  router.add('GET', '/api/auth/me', ({ requireUser }) => {
    const u = requireUser();
    return { body: { user: publicUser(u) } };
  });

  router.add('POST', '/api/auth/logout', ({ requireUser }) => {
    const u = requireUser();
    db.prepare('DELETE FROM tokens WHERE token_hash = ?').run(u.tokenHash);
    return { status: 204 };
  });

  // ---------------- Account ----------------
  router.add('DELETE', '/api/account', ({ requireUser, body }) => {
    const u = requireUser();
    v.obj(body);
    const password = v.str(body.password, 'password', { min: 1, max: 200 });
    const row = db.prepare('SELECT * FROM users WHERE id = ?').get(u.id);
    if (!verifyPassword(password, row.salt, row.password_hash)) throw new HttpError(401, 'Incorrect password');
    tx(db, () => {
      db.prepare('DELETE FROM user_records WHERE user_id = ?').run(u.id);
      db.prepare('DELETE FROM tokens WHERE user_id = ?').run(u.id);
      db.prepare('DELETE FROM users WHERE id = ?').run(u.id);
    });
    return { status: 204 };
  });

  router.add('GET', '/api/account/export', ({ requireUser }) => {
    const u = requireUser();
    const row = db.prepare('SELECT id, email, role, created_at FROM users WHERE id = ?').get(u.id);
    const records = db.prepare(
      'SELECT kind, id, updated_at, deleted, data FROM user_records WHERE user_id = ? AND deleted = 0 ORDER BY kind, updated_at',
    ).all(u.id);
    const out = { exported_at: ctx.iso(), user: row, notes: [], bookmarks: [], progress: [] };
    for (const r of records) {
      const rec = { id: r.id, updated_at: r.updated_at, data: JSON.parse(r.data) };
      if (r.kind === 'note') out.notes.push(rec);
      else if (r.kind === 'bookmark') out.bookmarks.push(rec);
      else out.progress.push(rec);
    }
    return { body: out };
  });

  // ---------------- Sync ----------------
  function validateData(kind, data) {
    v.obj(data, 'data');
    const vid = (x, n, opt = false) => v.int(x, n, { min: 1, max: 6236, optional: opt });
    if (kind === 'note') {
      return {
        study_start: vid(data.study_start, 'data.study_start'),
        study_end: vid(data.study_end, 'data.study_end'),
        verse_id: vid(data.verse_id, 'data.verse_id', true),
        text: v.str(data.text, 'data.text', { max: 100000 }),
        created_at: v.iso(data.created_at, 'data.created_at'),
        ...(data.conflict_of ? { conflict_of: v.id(data.conflict_of, 'data.conflict_of') } : {}),
      };
    }
    if (kind === 'bookmark') {
      return {
        type: v.oneOf(data.type, 'data.type', ['verse', 'study', 'tafsir', 'reflection']),
        verse_start: vid(data.verse_start, 'data.verse_start'),
        verse_end: vid(data.verse_end, 'data.verse_end'),
        ref_id: v.str(data.ref_id, 'data.ref_id', { max: 200, optional: true }),
        label: v.str(data.label, 'data.label', { max: 500, optional: true }),
        created_at: v.iso(data.created_at, 'data.created_at'),
      };
    }
    return {
      verse_start: vid(data.verse_start, 'data.verse_start'),
      verse_end: vid(data.verse_end, 'data.verse_end'),
      completed_at: v.iso(data.completed_at, 'data.completed_at'),
    };
  }

  const toWire = (r) => ({
    kind: r.kind, id: r.id, updated_at: r.updated_at, deleted: !!r.deleted, data: JSON.parse(r.data),
  });

  router.add('POST', '/api/sync', ({ requireUser, body }) => {
    const u = requireUser();
    v.obj(body);
    const since = v.iso(body.since, 'since', { optional: true });
    const changes = body.changes ?? [];
    if (!Array.isArray(changes)) throw v.bad('changes must be an array');
    if (changes.length > MAX_CHANGES) throw v.bad(`at most ${MAX_CHANGES} changes per request`);

    const parsed = changes.map((c, i) => {
      v.obj(c, `changes[${i}]`);
      const kind = v.oneOf(c.kind, `changes[${i}].kind`, ['note', 'bookmark', 'progress']);
      const deleted = c.deleted === undefined ? false : v.bool(c.deleted, `changes[${i}].deleted`);
      return {
        kind,
        id: v.id(c.id, `changes[${i}].id`),
        updated_at: v.iso(c.updated_at, `changes[${i}].updated_at`),
        base_updated_at: v.iso(c.base_updated_at, `changes[${i}].base_updated_at`, { optional: true }),
        deleted,
        data: deleted && (c.data === undefined || c.data === null) ? {} : validateData(kind, c.data),
      };
    });

    const serverTime = ctx.stamp();
    const accepted = new Set();
    const conflicts = [];

    tx(db, () => {
      const get = db.prepare('SELECT * FROM user_records WHERE user_id = ? AND kind = ? AND id = ?');
      const upsert = db.prepare(
        `INSERT INTO user_records (user_id, kind, id, updated_at, deleted, data, server_updated_at)
         VALUES (?,?,?,?,?,?,?)
         ON CONFLICT(user_id, kind, id) DO UPDATE SET updated_at = excluded.updated_at,
           deleted = excluded.deleted, data = excluded.data, server_updated_at = excluded.server_updated_at`,
      );
      for (const c of parsed) {
        const existing = get.get(u.id, c.kind, c.id);
        if (c.kind === 'note' && existing && !existing.deleted && !c.deleted) {
          const serverChangedSinceBase = !c.base_updated_at || existing.updated_at > c.base_updated_at;
          const serverText = JSON.parse(existing.data).text;
          if (serverChangedSinceBase && serverText !== c.data.text && existing.updated_at !== c.updated_at) {
            // Keep both: server copy stays, client text becomes a new note.
            const copyId = uuid();
            const copy = { ...c.data, conflict_of: c.id };
            upsert.run(u.id, 'note', copyId, serverTime, 0, JSON.stringify(copy), serverTime);
            conflicts.push({
              kind: 'note', id: c.id, resolution: 'kept_both',
              server: toWire(existing), client_copy_id: copyId,
            });
            continue;
          }
        }
        if (!existing || c.updated_at >= existing.updated_at) {
          upsert.run(u.id, c.kind, c.id, c.updated_at, c.deleted ? 1 : 0, JSON.stringify(c.data), serverTime);
          accepted.add(`${c.kind}|${c.id}`);
        }
        // else: server copy is newer; it will be returned in `changes`.
      }
      // Purge old tombstones.
      const cutoff = new Date(ctx.now() - config.tombstoneTtlMs).toISOString();
      db.prepare('DELETE FROM user_records WHERE user_id = ? AND deleted = 1 AND server_updated_at < ?').run(u.id, cutoff);
    });

    const rows = since
      ? db.prepare('SELECT * FROM user_records WHERE user_id = ? AND server_updated_at > ? ORDER BY server_updated_at').all(u.id, since)
      : db.prepare('SELECT * FROM user_records WHERE user_id = ? ORDER BY server_updated_at').all(u.id);
    // Return everything changed since `since`, except records exactly as this request wrote them.
    const out = rows
      .filter((r) => !(accepted.has(`${r.kind}|${r.id}`) && r.server_updated_at === serverTime))
      .map(toWire);
    // Conflicted notes: make sure the server version is present.
    for (const c of conflicts) {
      if (!out.some((r) => r.kind === 'note' && r.id === c.id)) out.push(c.server);
    }
    return { body: { server_time: serverTime, changes: out, conflicts } };
  });

  // ---------------- Published content ----------------
  router.add('GET', '/api/content/published', ({ query }) => {
    const sinceRaw = query.get('since');
    const since = sinceRaw ? v.iso(sinceRaw, 'since') : null;
    const items = since
      ? db.prepare("SELECT * FROM content_items WHERE status = 'published' AND updated_at >= ? ORDER BY updated_at").all(since)
      : db.prepare("SELECT * FROM content_items WHERE status = 'published' ORDER BY updated_at").all();
    const groupings = since
      ? db.prepare("SELECT * FROM groupings WHERE status = 'published' AND updated_at >= ?").all(since)
      : db.prepare("SELECT * FROM groupings WHERE status = 'published'").all();
    const removed = since
      ? db.prepare('SELECT id FROM removals WHERE removed_at >= ?').all(since)
      : db.prepare('SELECT id FROM removals').all();
    const publishedIds = new Set([...items, ...groupings].map((x) => x.id));
    return {
      body: {
        server_time: ctx.iso(),
        items: items.map(serializeItem),
        groupings: groupings.map(serializeGrouping),
        sources: db.prepare('SELECT * FROM sources ORDER BY title').all().map(serializeSource),
        scholars: db.prepare('SELECT * FROM scholars ORDER BY name').all().map(serializeScholar),
        removed_ids: removed.map((r) => r.id).filter((x) => !publishedIds.has(x)),
      },
    };
  });

  router.add('GET', '/api/audio/reciters', () => ({
    body: {
      reciters: db.prepare('SELECT id, name, style, base_url, file_pattern, license, source_url FROM audio_reciters WHERE enabled = 1 ORDER BY name').all(),
    },
  }));
}
