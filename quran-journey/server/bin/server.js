#!/usr/bin/env node
import { createApp } from '../src/app.js';

const { server, ctx } = createApp();
server.listen(ctx.config.port, ctx.config.host, () => {
  console.log(`The Quran Journey server listening on http://${ctx.config.host}:${ctx.config.port}`);
  console.log(`Database: ${ctx.config.dbPath}`);
  console.log(`Quran DB: ${ctx.quranDb ? ctx.config.quranDbPath + ' (read-only)' : 'not found - surah/verse browsing disabled'}`);
  if (!ctx.config.corsOrigins.length) console.log('CORS: no browser origins allowed (mobile apps unaffected)');
});
const stop = () => server.close(() => process.exit(0));
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
