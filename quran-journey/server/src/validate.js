/** Small strict validators. Each throws HttpError(400) with a readable message. */
export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const bad = (msg) => new HttpError(400, msg);

const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/;
const ID_RE = /^[A-Za-z0-9._-]{1,100}$/;
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,63}$/;

export function obj(v, name = 'body') {
  if (v === null || typeof v !== 'object' || Array.isArray(v)) throw bad(`${name} must be an object`);
  return v;
}
export function str(v, name, { min = 0, max = 10000, optional = false } = {}) {
  if (v === undefined || v === null) {
    if (optional) return null;
    throw bad(`${name} is required`);
  }
  if (typeof v !== 'string') throw bad(`${name} must be a string`);
  if (v.length < min || v.length > max) throw bad(`${name} must be ${min}-${max} characters`);
  return v;
}
export function int(v, name, { min = -Infinity, max = Infinity, optional = false } = {}) {
  if (v === undefined || v === null || v === '') {
    if (optional) return null;
    throw bad(`${name} is required`);
  }
  if (typeof v === 'string' && /^-?\d+$/.test(v)) v = Number(v);
  if (!Number.isInteger(v) || v < min || v > max) throw bad(`${name} must be an integer ${min}..${max}`);
  return v;
}
export function bool(v, name, { optional = false } = {}) {
  if (v === undefined || v === null) {
    if (optional) return null;
    throw bad(`${name} is required`);
  }
  if (typeof v !== 'boolean') throw bad(`${name} must be a boolean`);
  return v;
}
export function oneOf(v, name, values, { optional = false } = {}) {
  if ((v === undefined || v === null) && optional) return null;
  if (!values.includes(v)) throw bad(`${name} must be one of: ${values.join(', ')}`);
  return v;
}
export function iso(v, name, { optional = false } = {}) {
  if ((v === undefined || v === null) && optional) return null;
  if (typeof v !== 'string' || !ISO_RE.test(v) || Number.isNaN(Date.parse(v))) {
    throw bad(`${name} must be an ISO-8601 UTC timestamp`);
  }
  return new Date(v).toISOString();
}
export function id(v, name) {
  if (typeof v !== 'string' || !ID_RE.test(v)) throw bad(`${name} must be an id of 1-100 [A-Za-z0-9._-] characters`);
  return v;
}
export function email(v) {
  const s = str(v, 'email', { min: 3, max: 254 }).trim().toLowerCase();
  if (!EMAIL_RE.test(s)) throw bad('email is invalid');
  return s;
}
export function password(v) {
  const s = str(v, 'password', { min: 10, max: 200 });
  return s;
}
export function url(v, name, { optional = true } = {}) {
  const s = str(v, name, { max: 2000, optional });
  if (s === null || s === '') return null;
  let u;
  try {
    u = new URL(s);
  } catch {
    throw bad(`${name} must be a valid URL`);
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') throw bad(`${name} must be http(s)`);
  return s;
}
