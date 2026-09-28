// Pure policy: shared with the native engine through moderationLexicon.json.
export function normalizeText(text) {
  const lookalikes = {а:'a',е:'e',і:'i',о:'o',р:'p',с:'c',х:'x',у:'y',ј:'j'};
  return String(text || '').normalize('NFKC').toLowerCase()
    .replace(/[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]/g, '')
    .replace(/[аеіорсхуј]/g, c => lookalikes[c]).replace(/[’']/g, ' ')
    .replace(/\b(?:[a-z]\s+){2,}[a-z]\b/g, s => s.replace(/\s/g,''))
    .replace(/([a-z])\1{2,}/g,'$1$1').replace(/\s+/g,' ').trim();
}
export const hasLink = text => /(?:[a-z][a-z0-9+.-]*:\/\/|mailto:|www\.|\b[a-z0-9][a-z0-9.-]*\.[a-z]{2,63}\b|\b(?:\d{1,3}\.){3}\d{1,3}\b)/i.test(normalizeText(text));
export function analyzeText(text, policy, context = '') {
  const original = String(text || '');
  const normalized = normalizeText(original);
  const leet = normalized.replace(/[013457@$!]/g, c => ({0:'o',1:'i',3:'e',4:'a',5:'s',7:'t','@':'a','$':'s','!':'i'}[c]));
  const result = {safe:true, reason:'', category:'', needsReview:false, support:new RegExp(policy.supportPattern,'i').test(normalized)};
  const block = (category, reason) => ({...result,safe:false,category,reason});
  if (original.length > policy.maxLength) return block('length','This text is too long. Please shorten it.');
  if ((context === 'bio' || context === 'caption') && hasLink(original)) return block('links',"Links aren't allowed in bios or captions.");
  for (const rule of policy.rules) if (new RegExp(rule.pattern,'i').test(normalized) || new RegExp(rule.pattern,'i').test(leet)) return block(rule.category,rule.reason);
  const numbers = original.match(/\+?\d[\d ().-]{7,}\d/g) || [];
  if (numbers.some(n => { const digits=n.replace(/\D/g,''); return digits.length >= 9 && digits.length <= 19; })) return block('personal','Remove phone numbers or payment details before sharing.');
  if (/\b(?:i live at|my address is|abito in)\s+\d+/i.test(normalized)) return block('personal','Please keep home addresses private.');
  if (/(.)\1{15,}/u.test(original) || /(?:https?:\/\/|www\.)/gi.test(original) && (original.match(/https?:\/\//gi)||[]).length > 4) return block('spam','Please remove repeated text or excessive links.');
  result.needsReview = !result.support && new RegExp(policy.reviewPattern,'i').test(leet.replace(new RegExp(policy.benignPattern,'gi'),''));
  return result;
}
export function textEntries(collection, data, policy) {
  const entries = (policy.fields[collection] || []).filter(k => typeof data[k] === 'string' && data[k].trim()).map(k => [k,data[k]]);
  if (collection === 'Reel' && Array.isArray(data.edits?.text)) for (const sticker of data.edits.text) if (typeof sticker.text === 'string') entries.push(['sticker',sticker.text]);
  return entries;
}
export function cooldownKind(collection) {
  return /Message$/.test(collection) ? 'message' : /Comment$/.test(collection) ? 'comment' : collection === 'User' ? 'profile' : ['CommunityPost','Artwork','Reel','MusicReview','Commission'].includes(collection) ? 'post' : null;
}

// Short-lived local protection, not a substitute for server abuse controls.
export class WriteLimiter {
  constructor(now = () => Date.now()) { this.now=now; this.accounts=new Map(); }
  state(user) {
    if (!this.accounts.has(user)) this.accounts.set(user,{next:{},muted:0,strikes:[],recent:new Map(),pending:false});
    return this.accounts.get(user);
  }
  begin(user,bucket = 'post') {
    const s=this.state(user), wait=Math.max(bucket ? s.next[bucket] || 0 : 0,s.muted)-this.now();
    if(s.pending) throw new Error('A message is still being checked. Please wait.');
    if(wait>0) throw new Error(`Please wait ${Math.ceil(wait/1000)} seconds before writing again.`);
    s.pending=true;
  }
  strike(user) {
    const s=this.state(user), now=this.now(); s.strikes=s.strikes.filter(t=>now-t<600000);s.strikes.push(now);
    if(s.strikes.length>=3) s.muted=now+Math.min(300000,30000*(s.strikes.length-2));
  }
  finish(user, collection, fingerprint, interval, accepted, bucket = 'post') {
    const s=this.state(user);s.pending=false;
    if(accepted) {if(bucket) s.next[bucket]=this.now()+interval; s.recent.set(collection,{fingerprint,time:this.now()});}
  }
  duplicate(user,collection,fingerprint) {const old=this.state(user).recent.get(collection);return old?.fingerprint===fingerprint && this.now()-old.time<30000;}
}
