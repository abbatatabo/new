import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const SERVER_ROOT = path.resolve(here, '..');

/** Reads configuration from the environment. No secrets live in code. */
export function loadConfig(env = process.env) {
  return {
    port: Number(env.QJ_PORT || 8787),
    host: env.QJ_HOST || '0.0.0.0',
    dbPath: env.QJ_DB_PATH || path.join(SERVER_ROOT, 'data', 'quran-journey.sqlite'),
    quranDbPath: env.QJ_QURAN_DB_PATH || path.resolve(SERVER_ROOT, '..', 'app', 'assets', 'db', 'quran.db'),
    corsOrigins: (env.QJ_CORS_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean),
    trustProxy: env.QJ_TRUST_PROXY === '1',
    tokenTtlMs: 30 * 24 * 60 * 60 * 1000,
    tombstoneTtlMs: 90 * 24 * 60 * 60 * 1000,
    bodyLimit: 1024 * 1024,
    loginMaxFailures: 5,
    loginWindowMs: 15 * 60 * 1000,
  };
}
