import crypto from 'node:crypto';

const SCRYPT = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };
const KEYLEN = 64;

export function hashPassword(password, salt = crypto.randomBytes(16).toString('base64')) {
  const hash = crypto.scryptSync(password, salt, KEYLEN, SCRYPT).toString('base64');
  return { hash, salt };
}

export function verifyPassword(password, salt, expectedHash) {
  const actual = crypto.scryptSync(password, salt, KEYLEN, SCRYPT);
  const expected = Buffer.from(expectedHash, 'base64');
  return expected.length === actual.length && crypto.timingSafeEqual(actual, expected);
}

export const newToken = () => crypto.randomBytes(32).toString('base64url');
export const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
export const uuid = () => crypto.randomUUID();

export const ROLE_RANK = { user: 0, editor: 1, reviewer: 2, admin: 3 };
export const hasRole = (user, role) => !!user && ROLE_RANK[user.role] >= ROLE_RANK[role];
