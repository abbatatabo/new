import http from 'node:http';
import path from 'node:path';
import { loadConfig, SERVER_ROOT } from './config.js';
import { openDatabase, openQuranDatabase } from './db.js';
import { Router, SECURITY_HEADERS, send, readJson, serveStatic } from './http.js';
import { HttpError } from './validate.js';
import { registerPublicRoutes } from './routes-public.js';
import { registerAdminRoutes } from './routes-admin.js';
import { sha256, hasRole } from './security.js';

/**
 * Creates the application. `options.now` lets tests control the clock.
 * Returns { server, db, ctx }.
 */
export function createApp(options = {}) {
  const config = { ...loadConfig(options.env || process.env), ...(options.config || {}) };
  const db = options.db || openDatabase(config.dbPath);
  const quranDb = options.quranDb !== undefined ? options.quranDb : openQuranDatabase(config.quranDbPath);
  const now = options.now || (() => Date.now());
  let lastStamp = 0;
  const ctx = {
    config, db, quranDb, now,
    iso: () => new Date(now()).toISOString(),
    // Strictly increasing timestamps for sync bookkeeping, so `since` can be exclusive.
    stamp: () => {
      lastStamp = Math.max(now(), lastStamp + 1);
      return new Date(lastStamp).toISOString();
    },
  };

  const router = new Router();
  registerPublicRoutes(router, ctx);
  registerAdminRoutes(router, ctx);

  const adminDir = path.join(SERVER_ROOT, 'public', 'admin');

  function authenticate(req) {
    const h = req.headers.authorization || '';
    const m = /^Bearer ([A-Za-z0-9_-]{20,200})$/.exec(h);
    if (!m) return null;
    const row = db
      .prepare(
        `SELECT u.id, u.email, u.role, t.expires_at FROM tokens t JOIN users u ON u.id = t.user_id
         WHERE t.token_hash = ?`,
      )
      .get(sha256(m[1]));
    if (!row) return null;
    if (Date.parse(row.expires_at) <= now()) {
      db.prepare('DELETE FROM tokens WHERE token_hash = ?').run(sha256(m[1]));
      return null;
    }
    return { id: row.id, email: row.email, role: row.role, tokenHash: sha256(m[1]) };
  }

  function corsHeaders(req) {
    const origin = req.headers.origin;
    if (!origin) return { ok: true, headers: {} };
    if (config.corsOrigins.includes(origin)) {
      return {
        ok: true,
        headers: {
          'Access-Control-Allow-Origin': origin,
          Vary: 'Origin',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Max-Age': '600',
        },
      };
    }
    return { ok: false, headers: { Vary: 'Origin' } };
  }

  const server = http.createServer(async (req, res) => {
    for (const [k, v] of Object.entries(SECURITY_HEADERS)) res.setHeader(k, v);
    let url;
    try {
      url = new URL(req.url, 'http://localhost');
    } catch {
      return send(res, 400, { error: 'Bad URL' });
    }
    const pathname = url.pathname;
    const cors = corsHeaders(req);

    try {
      // Same-origin dashboard requests carry an Origin equal to our host; allow those.
      const sameOrigin = req.headers.origin && req.headers.host &&
        (req.headers.origin === `http://${req.headers.host}` || req.headers.origin === `https://${req.headers.host}`);

      if (req.method === 'OPTIONS') {
        if (!cors.ok && !sameOrigin) return send(res, 403, { error: 'Origin not allowed' }, cors.headers);
        res.writeHead(204, cors.headers);
        return res.end();
      }
      if (pathname.startsWith('/api/') && !cors.ok && !sameOrigin) {
        return send(res, 403, { error: 'Origin not allowed' }, cors.headers);
      }

      if (pathname === '/' || pathname === '/admin') {
        res.writeHead(302, { Location: '/admin/' });
        return res.end();
      }
      if (pathname.startsWith('/admin/') && req.method === 'GET') {
        const rel = pathname.slice('/admin/'.length) || 'index.html';
        if (serveStatic(res, adminDir, rel)) return;
        return send(res, 404, { error: 'Not found' });
      }
      if (pathname === '/healthz') return send(res, 200, { ok: true });

      const match = router.match(req.method, pathname);
      if (!match) return send(res, 404, { error: 'Not found' }, cors.headers);
      if (match.methodNotAllowed) return send(res, 405, { error: 'Method not allowed' }, cors.headers);

      const body = ['POST', 'PUT', 'DELETE'].includes(req.method) ? await readJson(req, config.bodyLimit) : {};
      const user = authenticate(req);
      const ip = (config.trustProxy && (req.headers['x-forwarded-for'] || '').split(',')[0].trim()) ||
        req.socket.remoteAddress || 'unknown';
      const result = await match.handler({
        req, params: match.params, query: url.searchParams, body, user, ip,
        requireUser() {
          if (!user) throw new HttpError(401, 'Authentication required');
          return user;
        },
        requireRole(role) {
          if (!user) throw new HttpError(401, 'Authentication required');
          if (!hasRole(user, role)) throw new HttpError(403, `Requires ${role} role`);
          return user;
        },
      });
      const status = result?.status || 200;
      return send(res, status, result?.body, cors.headers);
    } catch (e) {
      if (e instanceof HttpError) return send(res, e.status, { error: e.message }, cors.headers);
      if (/UNIQUE constraint failed/.test(e?.message)) return send(res, 409, { error: 'Already exists' }, cors.headers);
      if (/FOREIGN KEY constraint failed/.test(e?.message)) return send(res, 400, { error: 'Referenced record does not exist' }, cors.headers);
      if (/CHECK constraint failed/.test(e?.message)) return send(res, 400, { error: 'Invalid value' }, cors.headers);
      console.error(e);
      return send(res, 500, { error: 'Internal error' }, cors.headers);
    }
  });

  return { server, db, ctx };
}
