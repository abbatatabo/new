import { createApp } from '../src/app.js';
import { openDatabase } from '../src/db.js';
import { hashPassword, uuid } from '../src/security.js';

export async function startServer({ quranDb = null, config = {} } = {}) {
  const clock = { t: Date.parse('2026-11-25T12:00:00.000Z') };
  const db = openDatabase(':memory:');
  const { server, ctx } = createApp({ db, quranDb, now: () => clock.t, config, env: {} });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  async function req(method, path, { body, token, headers = {} } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: {
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = text; }
    return { status: res.status, body: json, headers: res.headers };
  }
  function makeUser(email, role, password = 'correct-horse-battery') {
    const { hash, salt } = hashPassword(password);
    db.prepare('INSERT INTO users (id, email, password_hash, salt, role, created_at) VALUES (?,?,?,?,?,?)')
      .run(uuid(), email, hash, salt, role, new Date(clock.t).toISOString());
  }
  async function login(email, password = 'correct-horse-battery') {
    const r = await req('POST', '/api/auth/login', { body: { email, password } });
    if (r.status !== 200) throw new Error(`login failed ${r.status} ${JSON.stringify(r.body)}`);
    return r.body.token;
  }
  async function userWithRole(email, role) {
    makeUser(email, role);
    return login(email);
  }
  const close = () => new Promise((r) => server.close(r));
  return { req, db, ctx, clock, makeUser, login, userWithRole, close, base };
}

export const iso = (ms) => new Date(ms).toISOString();
