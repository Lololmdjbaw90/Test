// Sugerly's on-device moderation engine (no network). The iOS app runs the
// same steps (native/Sugerly/App/Moderation.swift) on the same word lists
// (moderationLexicon.json), so both judge text the same way.
//
//   analyze(text, kind) -> { blocked, score, category, reason, strike, support, needsAI, signals }
//
// Steps:
//  1. Normalise: lower case, accents off, invisible characters out, look-alike
//     letters (Cyrillic/Greek) and leetspeak (4ss, $h1t) mapped back, stretched
//     letters (fuuuck) squeezed, spaced-out letters (f u c k) joined.
//  2. Word lists by category (hate, sexual, insults, swearing), with simple
//     plural/-ing endings, plus squashed text for the worst slurs.
//  3. Phrases (bullying, grooming, hate, scams, spam, personal info) and
//     patterns (threats, self-harm).
//  4. Who it's aimed at: insults near "you" count far more than insults at a
//     thing ("this game is stupid").
//  5. Personal info (phone numbers, cards that pass the Luhn check, addresses,
//     emails), links (shorteners, invites, unknown sites), CAPS, floods,
//     mentions, gibberish and length.
//  6. A score per category; how strict depends on where the text goes.
//     Borderline results are sent on to AI when it's available.
import LEX from "./moderationLexicon.json";

export const KINDS = ["message", "comment", "post", "caption", "profile", "name"];
// Block at or above this score, by where the text goes.
const THRESHOLD = { message: 0.85, comment: 0.7, post: 0.7, caption: 0.7, profile: 0.6, name: 0.35 };
const MAX_LENGTH = { message: 4000, comment: 1000, post: 3000, caption: 600, profile: 300, name: 40 };
const PUBLIC = new Set(["comment", "post", "caption", "profile", "name"]);
// Strike points by category (feeds the cooldown ladder).
const STRIKE = { hate: 2, threat: 2, sexual: 2, harassment: 1, scam: 1 };

const HOMOGLYPHS = {
  "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s", "ԁ": "d", "ɡ": "g", "һ": "h",
  "к": "k", "м": "m", "н": "h", "т": "t", "в": "b", "ո": "n", "ս": "u", "α": "a", "β": "b", "ε": "e", "η": "n", "ι": "i", "κ": "k",
  "ν": "v", "ο": "o", "ρ": "p", "τ": "t", "υ": "u", "χ": "x", "ω": "w", "ł": "l", "ø": "o", "æ": "ae", "œ": "oe", "ß": "ss",
};
const LEET = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "!": "i", "|": "l", "+": "t", "€": "e" };
const SUFFIXES = ["ing", "ers", "er", "ed", "es", "s", "in", "y", "z"];

// ---- lexicon, prepared once ----------------------------------------------
const TERMS = new Map(); // word -> [{ cat, w }]
const SQUEEZED = new Map(); // squeezed word -> original (only for words of 4+ letters)
for (const [cat, words] of Object.entries(LEX.terms)) {
  for (const [word, w] of Object.entries(words)) {
    TERMS.set(word, [...(TERMS.get(word) || []), { cat, w }]);
    const sq = squeeze1(word);
    if (sq.length >= 4 && !SQUEEZED.has(sq)) SQUEEZED.set(sq, word);
  }
}
const ALLOW = new Set(LEX.allow);
const SECOND = new Set(LEX.secondPerson);
const PHRASES = Object.entries(LEX.phrases).flatMap(([cat, map]) =>
  Object.entries(map).map(([p, w]) => ({ cat, w, key: ` ${tokenize(p).join(" ")} ` })));
const PATTERNS = Object.fromEntries(Object.entries(LEX.patterns).map(([cat, list]) => [cat, list.map(([src, w]) => ({ re: new RegExp(src, "i"), w }))]));

function squeeze1(s) { return s.replace(/(.)\1+/g, "$1"); }
function squeeze2(s) { return s.replace(/(.)\1{2,}/g, "$1$1"); }

export function plain(text) {
  let s = String(text || "").toLowerCase();
  try { s = s.normalize("NFKD").replace(/[̀-ͯ]/g, ""); } catch { /* old engines */ }
  s = s.replace(/[​-‏⁠﻿­͏᠎]/g, "");
  s = s.replace(/[’‘`´]/g, "'").replace(/[“”]/g, '"');
  s = s.replace(/([a-z])'([a-z])/g, "$1$2"); // you're -> youre, i'll -> ill
  s = s.replace(/[^\x00-\x7f]/g, (c) => HOMOGLYPHS[c] ?? c);
  return s.replace(/\s+/g, " ").trim();
}

function leet(s) { return s.replace(/[01345789@$!|+€]/g, (c) => LEET[c] ?? c); }

export function tokenize(text) {
  return leet(plain(text)).split(/[^a-z0-9]+/).filter(Boolean);
}

// All the ways a token could be a listed word.
function lookup(token) {
  if (ALLOW.has(token)) return null;
  const candidates = [token, squeeze2(token)];
  if (/(.)\1/.test(token)) {
    const sq = squeeze1(token);
    if (SQUEEZED.has(sq)) candidates.push(SQUEEZED.get(sq));
  }
  for (const c of candidates) if (TERMS.has(c)) return { word: c, hits: TERMS.get(c) };
  for (const suffix of SUFFIXES) {
    if (token.length - suffix.length >= 3 && token.endsWith(suffix)) {
      const stem = token.slice(0, -suffix.length);
      if (TERMS.has(stem)) return { word: stem, hits: TERMS.get(stem), stem: true };
    }
  }
  return null;
}

// Tokens with spaced-out letters put back together ("f u c k you" -> "fuck you").
function mergeRuns(tokens) {
  const out = [];
  let run = [];
  const flush = () => { if (run.length >= 3) out.push(run.join("")); else out.push(...run); run = []; };
  for (const t of tokens) {
    if (t.length === 1) run.push(t);
    else { flush(); out.push(t); }
  }
  flush();
  return out;
}

function joinedRuns(tokens) {
  const out = [];
  let run = [];
  for (const t of tokens) {
    if (t.length === 1) run.push(t);
    else { if (run.length >= 3) out.push(run.join("")); run = []; }
  }
  if (run.length >= 3) out.push(run.join(""));
  return out;
}

function luhn(digits) {
  let sum = 0;
  let double = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48;
    if (double) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
    double = !double;
  }
  return sum % 10 === 0;
}

const URL_RE = /\b((?:https?:\/\/)?(?:[a-z0-9-]+\.)+(?:com|net|org|io|gg|co|me|ly|xyz|app|dev|tv|link|site|shop|info|biz|ru|to|cc|us|uk|it|de|fr|es|ai|be|live|online|club|top|click|gl|at|in|ws|su)(?::\d+)?(?:\/[^\s]*)?)/gi;
const IP_LINK = /\bhttps?:\/\/\d{1,3}(\.\d{1,3}){3}/i;
const EMAIL = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i;
const PHONE = /(?:\+|\b)\d[\d\s().-]{7,}\d\b/g;
const ADDRESS = /\b\d{1,5}\s+[a-z]+(\s+[a-z]+)?\s+(street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr|court|ct|way|place|pl)\b|\b(via|viale|piazza|corso|calle|avenida)\s+[a-z]+(\s+[a-z]+)?\s*,?\s*\d{1,4}\b/i;
const SSN = /\b\d{3}-\d{2}-\d{4}\b/;
const EMOJI = /\p{Extended_Pictographic}/gu;

function domainOf(url) {
  return url.replace(/^https?:\/\//i, "").split(/[/?#:]/)[0].toLowerCase().replace(/^www\./, "");
}
const matchesDomain = (domain, list) => list.some((d) => domain === d || domain.endsWith(`.${d}`));

export function analyze(text, kind = "message") {
  const k = KINDS.includes(kind) ? kind : "message";
  const raw = String(text || "");
  const scores = {};
  const signals = [];
  const add = (cat, value, why) => {
    if (value <= 0) return;
    scores[cat] = Math.min(1, Math.max(scores[cat] || 0, value));
    if (why) signals.push(`${cat}:${why}`);
  };
  const result = (extra = {}) => finish(k, scores, signals, extra);

  if (!raw.trim()) return result();
  if (raw.length > MAX_LENGTH[k]) {
    return { ...result(), blocked: true, score: 1, category: "length", reason: `${LEX.reasons.length} (max ${MAX_LENGTH[k]} characters)`, strike: 0, needsAI: false };
  }

  const p = plain(raw);
  const tokens = tokenize(raw);
  const words = [...tokens, ...joinedRuns(tokens)];

  // 2. word lists
  const insultAt = [];
  let swearing = 0;
  let sexual = 0;
  tokens.forEach((t, i) => {
    const hit = lookup(t);
    if (!hit) return;
    for (const { cat, w } of hit.hits) {
      if (cat === "insult") insultAt.push({ i, w, word: hit.word });
      else if (cat === "profanity") swearing += w;
      else if (cat === "sexual") sexual += w;
      else add(cat, w, hit.word);
    }
  });
  for (const joined of joinedRuns(tokens)) {
    const hit = lookup(joined);
    if (!hit) continue;
    for (const { cat, w } of hit.hits) {
      if (cat === "insult") insultAt.push({ i: -1, w, word: hit.word });
      else if (cat === "profanity") swearing += w;
      else if (cat === "sexual") sexual += w;
      else add(cat, w, `spaced ${hit.word}`);
    }
  }
  // Squashed text for the worst slurs ("n i g g e r", "n.1.g.g.e.r"), minus allowed words.
  const squashed = words.filter((t) => !ALLOW.has(t)).join("");
  const squashed1 = squeeze1(squashed);
  for (const word of LEX.compact) {
    if (squashed.includes(word) || squashed1.includes(squeeze1(word))) {
      for (const { cat, w } of TERMS.get(word) || []) add(cat, w, `hidden ${word}`);
    }
  }
  if (sexual) add("sexual", Math.min(1, sexual), "words");

  // 3. phrases and patterns
  const merged = mergeRuns(tokens);
  const texts = [` ${tokens.join(" ")} `, ` ${tokens.map(squeeze2).join(" ")} `, ` ${merged.join(" ")} `, ` ${merged.map(squeeze2).join(" ")} `];
  for (const { cat, w, key } of PHRASES) {
    if (texts.some((t) => t.includes(key))) add(cat, w, key.trim());
  }
  for (const { re, w } of PATTERNS.threat) if (re.test(p)) add("threat", w, "threat");
  const support = PATTERNS.selfHarm.some(({ re }) => re.test(p));

  // 4. aimed at someone?
  const secondAt = tokens.map((t, i) => (SECOND.has(t) ? i : -1)).filter((i) => i >= 0);
  const aimed = (i) => i < 0 ? secondAt.length > 0 : secondAt.some((j) => Math.abs(j - i) <= 4);
  if (insultAt.length) {
    let best = 0;
    let targeted = false;
    for (const { i, w } of insultAt) {
      const hitTarget = aimed(i);
      targeted ||= hitTarget;
      best = Math.max(best, hitTarget ? Math.min(1, 0.75 + w * 0.35) : w * 0.6);
    }
    // A lone insult as a whole reply ("idiot") is aimed at whoever it answers.
    if (!targeted && tokens.length <= 2) best = Math.max(best, 0.65);
    best += Math.min(0.2, (insultAt.length - 1) * 0.1);
    add("harassment", best, targeted ? "insult at you" : "insult");
  }
  if (swearing) {
    const aimedSwear = secondAt.length > 0 && swearing >= 0.3;
    add("profanity", Math.min(0.75, swearing + (aimedSwear ? 0.2 : 0)), "swearing");
  }

  // 5. personal info
  for (const m of raw.match(PHONE) || []) {
    const digits = m.replace(/\D/g, "");
    if (digits.length >= 13 && digits.length <= 19 && luhn(digits)) add("personal", 1, "card number");
    else if (digits.length >= 9 && digits.length <= 15 && !/^(19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}$/.test(m.trim())) add("personal", 1, "phone number");
  }
  if (SSN.test(raw)) add("personal", 1, "id number");
  if (ADDRESS.test(p)) add("personal", 1, "address");
  if (EMAIL.test(raw) && k !== "message") add("personal", 0.9, "email");

  // links
  const links = raw.match(URL_RE) || [];
  let unknownLinks = 0;
  for (const link of links) {
    const domain = domainOf(link);
    const lower = link.toLowerCase();
    if (matchesDomain(domain, LEX.shorteners)) add("scam", 0.9, `short link ${domain}`);
    else if (LEX.invites.some((inv) => lower.includes(inv))) { if (PUBLIC.has(k)) add("spam", 0.85, "invite link"); }
    else if (!matchesDomain(domain, LEX.safeDomains)) unknownLinks += 1;
  }
  if (IP_LINK.test(raw)) add("scam", 0.9, "ip link");
  if (unknownLinks) {
    const w = { name: 0.8, profile: 0.8, caption: 0.75, post: 0.45, comment: 0.45, message: 0 }[k];
    add("link", w, "link");
  }
  if (scores.scam && links.length) add("scam", Math.max(scores.scam, 0.95), "scam + link");

  // floods
  const letters = raw.replace(/[^A-Za-z]/g, "");
  if (letters.length >= 12 && letters.replace(/[^A-Z]/g, "").length / letters.length >= 0.75) add("caps", 0.75, "caps");
  if (/(.)\1{11,}/u.test(raw)) add("flood", 0.8, "repeated letters");
  if ((raw.match(EMOJI) || []).length > 40) add("flood", 0.8, "emoji");
  if ((raw.match(/@\w+/g) || []).length > 8) add("spam", 0.9, "mentions");
  if (tokens.length >= 8) {
    const counts = {};
    for (const t of tokens) counts[t] = (counts[t] || 0) + 1;
    if (Math.max(...Object.values(counts)) / tokens.length >= 0.7) add("flood", 0.8, "same word");
  }
  if (tokens.some((t) => t.length >= 30 && !/^https?/.test(t))) add("spam", 0.6, "gibberish");

  // Names: any swearing or sexual word is too much.
  if (k === "name") {
    if (scores.profanity) add("profanity", Math.min(1, scores.profanity * 3), null);
    if (scores.sexual) add("sexual", Math.min(1, scores.sexual * 2), null);
  }

  return result({ support });
}

function finish(kind, scores, signals, { support = false } = {}) {
  let category = null;
  let score = 0;
  for (const [cat, value] of Object.entries(scores)) if (value > score) { score = value; category = cat; }
  const always = (cat, min) => (scores[cat] || 0) >= min;
  const blocked = score >= THRESHOLD[kind]
    || always("hate", 0.8) || always("threat", 0.8) || always("sexual", 0.8)
    || (scores.personal || 0) >= 0.9 || (scores.scam || 0) >= 0.9;
  if (blocked && !(score >= THRESHOLD[kind])) {
    // Blocked by an always-on rule: report that category.
    for (const cat of ["hate", "threat", "sexual", "personal", "scam"]) if ((scores[cat] || 0) >= 0.8) { category = cat; score = Math.max(score, scores[cat]); break; }
  }
  const reasonKey = kind === "name" && ["profanity", "link", "sexual"].includes(category) ? "name" : category;
  return {
    blocked,
    score,
    category,
    reason: blocked ? (LEX.reasons[reasonKey] || LEX.reasons.spam) : "",
    strike: blocked ? (category === "sexual" && score < 0.8 ? 1 : STRIKE[category] || 0) : 0,
    support,
    needsAI: !blocked && (score >= 0.3 || (PUBLIC.has(kind) && kind !== "name" && signals.some((s) => s.startsWith("harassment")))),
    signals,
  };
}

export const moderationReasons = LEX.reasons;
