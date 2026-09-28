import policy from './moderationLexicon.json';
import {analyzeText} from './modEngine.js';
export {hasLink} from './modEngine.js';
// Submission preflight. The central write gate owns cooldowns and strikes.
// Content stays on-device; rejected private text is never sent to a webhook.
export async function checkText(text, {where} = {}) {
 const result=analyzeText(text,policy,where || '');
 return result.needsReview ? {...result,safe:false,reason:'This wording could target someone. Please rephrase it.'} : result;
}
