// Reels "For you" algorithm.
// -----------------------------------------------------------------------------
// Learns from how you watch, like TikTok does, and keeps learning while you
// scroll (the queue below the current reel is re-ranked after every reel):
//
//  Signals kept on this device (per reel you've seen):
//   - watch time and how much of the reel you watched
//   - full watches and re-watches (strong positive)
//   - quick swipes away in under ~1.5 s (negative)
//   - likes, saves, comments, shares (strong positive)
//   - "Not interested" (strong negative for that creator and its hashtags)
//
//  Those turn into two taste profiles: creators and hashtags you enjoy. Each
//  candidate reel is then scored on:
//   - your affinity to its creator (+ follows / friends)
//   - your affinity to its hashtags (+ interests from your profile)
//   - how well it does with everyone: like rate, views, comments (smoothed so
//     a new reel with 2 likes out of 3 views doesn't beat a proven one)
//   - freshness (gentle decay over a few days)
//   - whether you've already seen it (seen / skipped reels sink)
//
//  Then a diversity pass stops the same creator or hashtag from repeating back
//  to back, and ~1 in 6 slots goes to "exploration": a reel from a creator you
//  haven't met yet, so the feed never gets stuck in a bubble.
// -----------------------------------------------------------------------------
const KEY = "mimilocks:__reel_signals";
const HOUR = 3600000;
const MAX_ITEMS = 600;

function load() {
  try { return JSON.parse(localStorage.getItem(KEY) || "{}"); } catch { return {}; }
}
function save(map) {
  const entries = Object.entries(map).sort((a, b) => (b[1].t || 0) - (a[1].t || 0)).slice(0, MAX_ITEMS);
  try { localStorage.setItem(KEY, JSON.stringify(Object.fromEntries(entries))); } catch { /* quota */ }
}

let memory = null;
const listeners = new Set();
export function reelSignals() {
  if (!memory) memory = load();
  return memory;
}
export function onReelSignals(fn) { listeners.add(fn); return () => listeners.delete(fn); }

// record(reel, { ms, completed, skipped, liked, saved, commented, shared, hidden })
export function recordReelSignal(reel, patch) {
  if (!reel?.id) return;
  const map = reelSignals();
  const prev = map[reel.id] || { a: reel.user_email, g: (reel.tags || []).slice(0, 6), ms: 0, n: 0, done: 0, skip: 0 };
  const next = { ...prev, t: Date.now() };
  if (patch.ms) { next.ms = (prev.ms || 0) + Math.round(patch.ms); next.n = (prev.n || 0) + 1; }
  if (patch.completed) next.done = (prev.done || 0) + 1;
  if (patch.skipped) next.skip = (prev.skip || 0) + 1;
  ["liked", "saved", "commented", "shared", "hidden"].forEach((k) => { if (k in patch) next[k] = patch[k]; });
  map[reel.id] = next;
  save(map);
  listeners.forEach((fn) => fn());
}

// Creator and hashtag taste, learned from the signals above.
export function buildReelTaste({ me, friends = [], signals = reelSignals() } = {}) {
  const creators = new Map();
  const tags = new Map();
  const add = (map, k, w) => { if (k) map.set(k, (map.get(k) || 0) + w); };
  Object.values(signals).forEach((s) => {
    const ageDays = (Date.now() - (s.t || 0)) / (24 * HOUR);
    const decay = 1 / (1 + ageDays / 10); // recent behaviour counts more
    let w = 0;
    w += Math.min(3, (s.ms || 0) / 8000) * 0.6;          // time spent
    w += (s.done || 0) * 1.2 + Math.max(0, (s.done || 0) - 1) * 0.8; // full + re-watches
    w -= (s.skip || 0) * 1.1;                             // swiped away fast
    if (s.liked) w += 2.5;
    if (s.saved) w += 2;
    if (s.commented) w += 2;
    if (s.shared) w += 2.5;
    if (s.hidden) w -= 6;
    w *= decay;
    add(creators, s.a, w);
    (s.g || []).forEach((g) => add(tags, g, w * 0.6));
  });
  (me?.following || []).forEach((e) => add(creators, e, 3));
  friends.forEach((e) => add(creators, e, 2.5));
  (me?.interests || []).forEach((i) => add(tags, String(i).toLowerCase().replace(/\s+/g, ""), 1.2));
  return { creators, tags, me: me?.email, follows: new Set(me?.following || []), friends: new Set(friends) };
}

const squash = (x) => x / (1 + Math.abs(x)); // keeps any single signal from dominating

// Score one reel (and say why it's here).
export function scoreReel(reel, taste, { signals = reelSignals(), commentCount = 0, now = Date.now() } = {}) {
  const s = signals[reel.id];
  const creator = taste.creators.get(reel.user_email) || 0;
  const tagScore = (reel.tags || []).reduce((sum, g) => sum + (taste.tags.get(g) || 0), 0);
  const likes = (reel.likes || []).length;
  const views = Math.max(reel.views || 0, likes);
  const likeRate = (likes + 1) / (views + 8);               // Bayesian-smoothed
  const popularity = Math.log1p(likes * 2 + views * 0.05 + commentCount * 3);
  const ageH = Math.max(0, (now - new Date(reel.created_date).getTime()) / HOUR);
  const fresh = 1 / (1 + ageH / 60);

  let score = 1.6 * squash(creator / 3) + 1.2 * squash(tagScore / 3) + 2.2 * likeRate + 0.35 * popularity + 0.9 * fresh;
  if (s) {
    if (s.hidden) score -= 10;
    else if (s.skip && !s.done) score -= 2.5;
    else if (s.done) score -= 1.6 - (s.liked ? 0.6 : 0); // seen: sink, but loved ones can come back
    else score -= 0.9;
  }
  if (reel.user_email === taste.me) score -= 0.8;

  let reason = "Popular right now";
  if (taste.follows?.has(reel.user_email)) reason = "From someone you follow";
  else if (taste.friends?.has(reel.user_email)) reason = "From your friend";
  else if (creator >= 2) reason = "Because you watch this creator";
  else if (tagScore > 1.2) { const top = (reel.tags || []).slice().sort((a, b) => (taste.tags.get(b) || 0) - (taste.tags.get(a) || 0))[0]; reason = top ? `Because you like #${top}` : reason; }
  else if (ageH < 24) reason = "New today";
  else if (popularity > 3) reason = "Trending";
  return { score, reason, seen: !!s };
}

// Seeded random, so a session's exploration picks stay stable while you scroll.
function rng(seed) {
  let x = seed || 1;
  return () => { x = (Math.imul(x, 1664525) + 1013904223) >>> 0; return x / 4294967296; };
}

// Rank a list of reels into a feed order (array of { reel, reason }).
export function rankReels(reels, { me, friends = [], blocked = new Set(), commentCounts = {}, seed = 1, fixed = [] } = {}) {
  const signals = reelSignals();
  const taste = buildReelTaste({ me, friends, signals });
  const fixedSet = new Set(fixed);
  const pool = reels
    .filter((r) => !blocked.has(r.user_email) && !fixedSet.has(r.id) && !signals[r.id]?.hidden)
    .map((reel) => ({ reel, ...scoreReel(reel, taste, { signals, commentCount: commentCounts[reel.id] || 0 }) }));

  // Exploration candidates: creators you have no history with.
  const random = rng(seed);
  const unknown = pool.filter((x) => !taste.creators.has(x.reel.user_email) && !x.seen);

  // Greedy pick with a diversity penalty for the next 60 slots (what anyone
  // realistically scrolls to before the queue is re-ranked again); the rest
  // simply follow by score.
  const GREEDY = 60;
  pool.sort((a, b) => b.score - a.score);
  const out = [];
  const recent = [];
  while (pool.length && out.length < GREEDY) {
    const explore = unknown.length && out.length % 6 === 4 && random() < 0.85;
    const last = recent[recent.length - 1]?.user_email;
    const lastAuthors = new Set(recent.slice(-3).map((r) => r.user_email));
    const lastTags = new Set(recent.slice(-2).flatMap((r) => r.tags || []));
    let bestI = -1, best = -Infinity;
    for (let i = 0; i < pool.length; i++) {
      const x = pool[i];
      if (explore && !unknown.includes(x)) continue;
      if (!explore && x.score < best) break; // sorted, and penalties only lower a score
      let v = x.score;
      if (x.reel.user_email === last) v -= 2.2;                  // never back to back
      else if (lastAuthors.has(x.reel.user_email)) v -= 0.9;
      if ((x.reel.tags || []).some((g) => lastTags.has(g))) v -= 0.35;
      if (explore) v += random() * 0.5;
      if (v > best) { best = v; bestI = i; }
    }
    if (bestI < 0) bestI = 0;
    const [pick] = pool.splice(bestI, 1);
    const u = unknown.indexOf(pick);
    if (u >= 0) unknown.splice(u, 1);
    out.push({ reel: pick.reel, reason: explore && u >= 0 ? "New creator for you" : pick.reason });
    recent.push(pick.reel);
  }
  pool.forEach((x) => out.push({ reel: x.reel, reason: x.reason }));
  return out;
}
