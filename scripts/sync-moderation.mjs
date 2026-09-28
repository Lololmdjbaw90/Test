import fs from 'node:fs';
const source = new URL('../src/lib/moderationLexicon.json', import.meta.url);
const target = new URL('../native/Sugerly/Firebase/moderationLexicon.json', import.meta.url);
if (process.argv.includes('--check')) {
  if (fs.readFileSync(source,'utf8') !== fs.readFileSync(target,'utf8')) throw new Error('Native moderation policy is out of sync. Run node scripts/sync-moderation.mjs');
} else fs.copyFileSync(source,target);
