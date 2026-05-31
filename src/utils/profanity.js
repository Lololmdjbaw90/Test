// Local bad-word flagger.
// -----------------------------------------------------------------------------
// A dependency-free profanity / hate-speech filter used for content moderation
// now that the app is offline (no AI). It is intentionally conservative about
// false positives: it matches WHOLE words (after normalising common evasions
// like leetspeak, elongation, accents, and letter-spacing) rather than raw
// substrings, so ordinary words such as "class", "assassin" or "Scunthorpe"
// are NOT flagged.
//
//   containsProfanity(text) -> boolean
//   findProfanity(text)     -> string[]   (the offending words found)
//   maskProfanity(text)     -> string     (offending words replaced with ****)
//   moderate(text)          -> { safe: boolean, reason: string }
//
// The word list is deliberately editable — add or remove terms to taste.
// -----------------------------------------------------------------------------

// Core list. Kept reasonably small and obvious; extend as needed.
const WORDS = [
  // profanity
  "fuck", "fucker", "fuckers", "fucking", "motherfucker", "shit", "shite", "bullshit",
  "bitch", "bitches", "bastard", "asshole", "asshat", "ass", "arse", "arsehole",
  "dick", "dickhead", "cock", "prick", "pussy", "cunt", "twat", "wanker", "wank",
  "bollocks", "piss", "pissed", "slut", "whore", "skank", "douche", "douchebag",
  "jackass", "dumbass", "dipshit", "crap", "goddamn", "bugger",
  // slurs / hate (so the filter also flags hate speech)
  "nigger", "nigga", "faggot", "fag", "retard", "retarded", "spic", "chink",
  "kike", "tranny", "dyke", "coon", "gook", "wetback",
];
const BAD = new Set(WORDS);

// leetspeak / symbol substitutions
const LEET = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s", "!": "i", "+": "t" };

function normalize(s) {
  let out = (s || "").toString().toLowerCase();
  try { out = out.normalize("NFKD").replace(/[\u0300-\u036f]/g, ""); } catch { /* older runtimes */ }
  out = out.replace(/[013457@$!+8]/g, (c) => LEET[c] || c);
  return out;
}

// "fuuuuck" -> "fuck"; leaves single/doubled letters of real words checked separately
function collapseRepeats(token) {
  return token.replace(/(.)\1+/g, "$1");
}

function isBadToken(token) {
  if (!token) return false;
  if (BAD.has(token)) return true;
  const squashed = collapseRepeats(token);
  return BAD.has(squashed);
}

// Catch letter-spaced evasions like "f u c k" or "f.u.c.k" (runs of single letters).
function joinedSingleLetters(tokens) {
  const joins = [];
  let run = [];
  for (const t of tokens) {
    if (t.length === 1) run.push(t);
    else { if (run.length >= 3) joins.push(run.join("")); run = []; }
  }
  if (run.length >= 3) joins.push(run.join(""));
  return joins;
}

function tokenize(text) {
  return normalize(text).split(/[^a-z0-9]+/).filter(Boolean);
}

export function findProfanity(text) {
  const tokens = tokenize(text);
  const hits = new Set();
  for (const t of tokens) if (isBadToken(t)) hits.add(collapseRepeats(t));
  for (const j of joinedSingleLetters(tokens)) if (isBadToken(j)) hits.add(collapseRepeats(j));
  return [...hits];
}

export function containsProfanity(text) {
  const tokens = tokenize(text);
  if (tokens.some(isBadToken)) return true;
  return joinedSingleLetters(tokens).some(isBadToken);
}

export function maskProfanity(text) {
  if (!text) return text;
  // Replace whole offending words in the original text, preserving everything else.
  return text.replace(/[A-Za-z0-9@$!+]+/g, (word) => {
    const norm = normalize(word);
    if (isBadToken(norm)) {
      // keep first character, mask the rest -> e.g. "f***"
      return word[0] + "*".repeat(Math.max(1, word.length - 1));
    }
    return word;
  });
}

export function moderate(text) {
  const hits = findProfanity(text);
  if (hits.length === 0) return { safe: true, reason: "" };
  return { safe: false, reason: "Message contains language that isn't allowed here." };
}

export default { containsProfanity, findProfanity, maskProfanity, moderate };
