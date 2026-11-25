#!/usr/bin/env node
// Seeds factual reference data. Idempotent. Never publishes anything.
import { loadConfig } from '../src/config.js';
import { openDatabase } from '../src/db.js';
import { seed } from '../src/seed-data.js';

const db = openDatabase(loadConfig().dbPath);
const r = seed(db);
console.log(`Seeded: ${r.sources} sources, ${r.scholars} scholars, ${r.reciters} reciters, ${r.translations} translations, ${r.items} example draft item(s).`);
