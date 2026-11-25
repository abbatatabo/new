#!/usr/bin/env node
// Usage: node bin/create-admin.js <email>
// Password from QJ_ADMIN_PASSWORD, otherwise prompted on stdin (not echoed).
// Creates the user, or promotes an existing user to admin (and resets the password).
import readline from 'node:readline';
import { loadConfig } from '../src/config.js';
import { openDatabase } from '../src/db.js';
import { hashPassword, uuid } from '../src/security.js';
import * as v from '../src/validate.js';

async function promptHidden(question) {
  if (!process.stdin.isTTY) {
    const rl = readline.createInterface({ input: process.stdin });
    for await (const line of rl) { rl.close(); return line; }
    return '';
  }
  return new Promise((resolve) => {
    process.stdout.write(question);
    const stdin = process.stdin;
    stdin.setRawMode(true);
    stdin.resume();
    let buf = '';
    stdin.on('data', function onData(ch) {
      const c = ch.toString('utf8');
      if (c === '\r' || c === '\n') {
        stdin.setRawMode(false); stdin.pause(); stdin.off('data', onData);
        process.stdout.write('\n'); resolve(buf);
      } else if (c === '\u0003') process.exit(130);
      else if (c === '\u007f') buf = buf.slice(0, -1);
      else buf += c;
    });
  });
}

try {
  const email = v.email(process.argv[2]);
  const password = v.password(process.env.QJ_ADMIN_PASSWORD || (await promptHidden('Admin password (min 10 chars): ')));
  const db = openDatabase(loadConfig().dbPath);
  const { hash, salt } = hashPassword(password);
  const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (existing) {
    db.prepare("UPDATE users SET role='admin', password_hash=?, salt=? WHERE id=?").run(hash, salt, existing.id);
    console.log(`Promoted ${email} to admin.`);
  } else {
    db.prepare("INSERT INTO users (id, email, password_hash, salt, role, created_at) VALUES (?,?,?,?, 'admin', ?)")
      .run(uuid(), email, hash, salt, new Date().toISOString());
    console.log(`Created admin ${email}.`);
  }
} catch (e) {
  console.error('Error:', e.message);
  console.error('Usage: QJ_ADMIN_PASSWORD=... node bin/create-admin.js admin@example.org');
  process.exit(1);
}
