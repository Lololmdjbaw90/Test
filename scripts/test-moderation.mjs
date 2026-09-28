import fs from 'node:fs';
import assert from 'node:assert/strict';
import {analyzeText,textEntries,WriteLimiter,cooldownKind} from '../src/lib/modEngine.js';
const policy=JSON.parse(fs.readFileSync(new URL('../src/lib/moderationLexicon.json',import.meta.url)));
const cases=JSON.parse(fs.readFileSync(new URL('./moderation-cases.json',import.meta.url)));
for(const item of cases) {
 const actual=analyzeText(item.text,policy,item.field||'');
 assert.equal(actual.safe,item.safe,item.text);
 assert.equal(actual.needsReview,!!item.review,item.text+' review');
}
assert.equal(textEntries('Reel',{likes:['someone'],views:3},policy).length,0);
assert.equal(textEntries('Reel',{edits:{text:[{text:'k y s'}]}},policy).length,1);
assert.equal(textEntries('Report',{target_preview:'k y s'},policy).length,0,'Reporting abuse must remain possible');
assert.equal(cooldownKind('ServerChannel'),null,'Provisioning channels must not consume a post cooldown');
let now=0;const limiter=new WriteLimiter(()=>now);
limiter.begin('a','message');assert.throws(()=>limiter.begin('a','message'),/checked/);
limiter.finish('a','DirectMessage','hello',1200,true,'message');assert.throws(()=>limiter.begin('a','message'),/wait/);
limiter.begin('b','message');limiter.finish('b','DirectMessage','hello',1200,true,'message');
now=1500;limiter.begin('a','message');assert.ok(limiter.duplicate('a','DirectMessage','hello'));limiter.finish('a','','',0,false);
for(let i=0;i<3;i++) limiter.strike('a');assert.throws(()=>limiter.begin('a','comment'),/wait/);
now=32000;limiter.begin('a','message');limiter.finish('a','','',0,false);
console.log(`PASS ${cases.length} moderation cases; cooldowns, account isolation, duplicate sends, and temporary mutes`);
