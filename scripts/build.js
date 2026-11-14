import {existsSync, mkdirSync, cpSync, copyFileSync, rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
// Cloudflare Workers serves SPA routes via wrangler.jsonc; do not publish legacy _redirects fallback.
const files = ['index.html','_headers','robots.txt'];
const dirs = ['src','assets'];
for(const path of [...files,...dirs,'supabase/migrations/202611120001_initial.sql']) if(!existsSync(path))throw new Error(`Missing ${path}`);
for(const path of ['src/app.js','src/api.js','src/logic.js','src/config.js']) execFileSync(process.execPath,['--check',path],{stdio:'inherit'});

// Production-only safety gate: never publish a fake/demo/unconfigured app.
const config = await import('../src/config.js');
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(config.CONFIG.SUPABASE_URL || '') ||
    !/^sb_publishable_[A-Za-z0-9_-]{15,}$/.test(config.CONFIG.SUPABASE_PUBLISHABLE_KEY || '') ||
    /YOUR|PROJECT|DEMO|EXAMPLE|PLACEHOLDER/i.test(config.CONFIG.SUPABASE_URL + config.CONFIG.SUPABASE_PUBLISHABLE_KEY)) {
  throw new Error('PRODUCTION BUILD BLOCKED: set your real Supabase Project URL and publishable key in src/config.js, then run checks. No public demo deployment.');
}
rmSync('dist',{recursive:true,force:true});mkdirSync('dist',{recursive:true});
for(const file of files)copyFileSync(file,`dist/${file}`);
for(const dir of dirs)cpSync(dir,`dist/${dir}`,{recursive:true});
console.log('✅ Helpay static build is ready: dist/ (Cloudflare Pages output directory).');
