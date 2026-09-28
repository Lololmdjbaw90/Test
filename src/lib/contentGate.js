import policy from './moderationLexicon.json';
import {analyzeText,textEntries,cooldownKind,normalizeText,WriteLimiter} from './modEngine.js';
const limiter = new WriteLimiter();
export async function guardTextWrite(collection,data,{user='anonymous',create=false}={}) {
  const entries=textEntries(collection,data,policy); if(!entries.length) return;
  const bucket=cooldownKind(collection);
  limiter.begin(user,bucket);
  const fingerprint=normalizeText(entries.map(x=>x[1]).join('\n'));
  let accepted=false;
  try {
    if(create && bucket && limiter.duplicate(user,collection,fingerprint)) throw new Error('You just sent this. Please avoid duplicate posts.');
    for(const [field,text] of entries) {
      const verdict=analyzeText(text,policy,field);
      if(!verdict.safe) {if(['hate','threat','sexual','harassment','scam'].includes(verdict.category)) limiter.strike(user); throw new Error(verdict.reason);}
      if(verdict.needsReview) {
        throw new Error('This wording could target someone. Please rephrase it. No strike was added.');
      }
    }
    accepted=true;
  } finally {limiter.finish(user,collection,fingerprint,policy.cooldowns[bucket] || 0,accepted,bucket);}
}

export function recordPreflightViolation(user, verdict) {
 if (user?.id && !verdict.safe && ['hate','threat','sexual','harassment','scam'].includes(verdict.category)) limiter.strike(user.id);
}
