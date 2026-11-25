import fs from 'node:fs';
import path from 'node:path';
import { HttpError } from './validate.js';

/** Minimal router: add(method, '/api/x/:id', handler). */
export class Router {
  constructor() {
    this.routes = [];
  }
  add(method, pattern, handler) {
    const keys = [];
    const re = new RegExp(
      '^' + pattern.replace(/:([a-zA-Z]+)/g, (_, k) => (keys.push(k), '([^/]+)')) + '/?$',
    );
    this.routes.push({ method, re, keys, handler, pattern });
  }
  match(method, pathname) {
    let pathMatched = false;
    for (const r of this.routes) {
      const m = r.re.exec(pathname);
      if (!m) continue;
      pathMatched = true;
      if (r.method !== method) continue;
      const params = {};
      r.keys.forEach((k, i) => (params[k] = decodeURIComponent(m[i + 1])));
      return { handler: r.handler, params };
    }
    return pathMatched ? { methodNotAllowed: true } : null;
  }
}

export const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  'Content-Security-Policy':
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " +
    "connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'none'; " +
    "form-action 'self'; frame-ancestors 'none'",
};

export function send(res, status, body, extraHeaders = {}) {
  const headers = { ...extraHeaders };
  let payload = '';
  if (status !== 204 && body !== undefined) {
    payload = JSON.stringify(body);
    headers['Content-Type'] = 'application/json; charset=utf-8';
    headers['Cache-Control'] = headers['Cache-Control'] || 'no-store';
  }
  res.writeHead(status, headers);
  res.end(payload);
}

export function readJson(req, limit) {
  return new Promise((resolve, reject) => {
    const ct = req.headers['content-type'] || '';
    const len = Number(req.headers['content-length'] || 0);
    if (len > limit) {
      req.resume();
      return reject(new HttpError(413, 'Request body too large'));
    }
    let size = 0;
    const chunks = [];
    let aborted = false;
    req.on('data', (c) => {
      if (aborted) return;
      size += c.length;
      if (size > limit) {
        aborted = true;
        reject(new HttpError(413, 'Request body too large'));
        req.resume();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (aborted) return;
      if (size === 0) return resolve({});
      if (!ct.toLowerCase().startsWith('application/json')) {
        return reject(new HttpError(415, 'Content-Type must be application/json'));
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new HttpError(400, 'Malformed JSON'));
      }
    });
    req.on('error', reject);
  });
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

export function serveStatic(res, rootDir, relPath) {
  const safe = path.normalize(relPath).replace(/^(\.\.(\/|\\|$))+/, '');
  const file = path.join(rootDir, safe);
  if (!file.startsWith(rootDir)) return false;
  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    return false;
  }
  if (!stat.isFile()) return false;
  res.writeHead(200, {
    'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
    'Cache-Control': 'no-cache',
  });
  res.end(fs.readFileSync(file));
  return true;
}
