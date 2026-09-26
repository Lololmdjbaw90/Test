// Recommendations: the "For you" feed, suggested people, servers, trending
// tags and music picks.
// -----------------------------------------------------------------------------
// Everything runs on the client from data the app already loads, so it works
// the same with Firebase and the local demo backend. Scores combine a few
// explainable signals, and every recommendation carries a short `reason`
// ("Liked by Luna", "Follows you", "3 friends are here", ...):
//
//   affinity    how much you interact with the author (follows, friends,
//               likes and comments you've given them)
//   engagement  likes and comments, log-scaled so viral posts don't swamp
//               everything, with extra weight for recent activity
//   social      people you follow / are friends with who liked it
//   interest    overlap with your interests and the hashtags you engage with
//   freshness   smooth time decay (newer is better, but a great post from
//               yesterday still beats an empty one from a minute ago)
//   novelty     posts you've already scrolled past sink; brand-new creators
//               get a small boost so they're discovered
// A final diversity pass stops one person from filling the whole feed.
// -----------------------------------------------------------------------------

const HOUR = 3600000;
const SEEN_KEY = "mimilocks:__seen_posts";
const PLAYS_KEY = "mimilocks:__plays";
const HIDDEN_KEY = "mimilocks:__hidden_posts";

const hoursSince = (date, now = Date.now()) => Math.max(0, (now - new Date(date || now).getTime()) / HOUR);
const log1 = (n) => Math.log1p(Math.max(0, n || 0));
const cap = (n, max) => Math.min(max, n);
// Stored data isn't always the expected shape (older records, manual edits).
const arr = (v) => (Array.isArray(v) ? v : []);
const lower = (v) => String(v ?? "").toLowerCase();

// ---------- text helpers ----------
export function hashtags(text) {
  return [...String(text || "").matchAll(/#([\p{L}\p{N}_]{2,30})/gu)].map((m) => m[1].toLowerCase());
}
const STOP = new Set("the a an and or for with this that from have just some into your you are was were but not new get got its it's so very really my our me i to of in on at is be".split(" "));
function terms(text) {
  return String(text || "").toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2 && !STOP.has(w));
}
const postText = (p) => `${p.title || ""} ${p.description || ""}`;

// ---------- seen / play history (per device) ----------
function readMap(key) { try { return JSON.parse(localStorage.getItem(key) || "{}"); } catch { return {}; } }
function writeMap(key, map, max = 600) {
  const entries = Object.entries(map).sort((a, b) => (b[1]?.t || b[1]) - (a[1]?.t || a[1])).slice(0, max);
  try { localStorage.setItem(key, JSON.stringify(Object.fromEntries(entries))); } catch { /* ignore */ }
}
export function markSeen(id) {
  if (!id) return;
  const seen = readMap(SEEN_KEY);
  if (seen[id]) return;
  seen[id] = Date.now();
  writeMap(SEEN_KEY, seen);
}
export const seenPosts = () => readMap(SEEN_KEY);
// "Not interested": hides the post and makes its author rank lower for you.
export function hidePost(post) {
  const hidden = readMap(HIDDEN_KEY);
  hidden[post.id] = { t: Date.now(), author: post.user_email };
  writeMap(HIDDEN_KEY, hidden, 300);
}
export const hiddenPosts = () => readMap(HIDDEN_KEY);
export function recordPlay(track) {
  if (!track?.id) return;
  const plays = readMap(PLAYS_KEY);
  const prev = plays[track.id] || { n: 0 };
  plays[track.id] = { n: prev.n + 1, t: Date.now(), genre: track.genre || prev.genre || "", mood: track.mood || prev.mood || "", author: track.user_email || prev.author || "" };
  writeMap(PLAYS_KEY, plays, 300);
}
export const playHistory = () => readMap(PLAYS_KEY);

// ---------- your taste profile ----------
// Built from what you follow, like, comment on and listen to.
export function buildTaste({ me, friends = [], posts = [], comments = [], tracks = [], artworks = [] }) {
  const email = me?.email;
  const following = new Set(arr(me?.following));
  const friendSet = new Set(friends);
  const affinity = new Map(); // author email -> weight
  const bump = (who, w) => { if (who && who !== email) affinity.set(who, (affinity.get(who) || 0) + w); };
  const interest = new Map(); // term / hashtag -> weight
  const addInterest = (t, w) => interest.set(t, (interest.get(t) || 0) + w);
  arr(me?.interests).forEach((i) => terms(i).forEach((t) => addInterest(t, 2)));

  following.forEach((e) => bump(e, 3));
  friendSet.forEach((e) => bump(e, 2.5));
  const liked = (list) => list.filter((x) => arr(x.likes).includes(email));
  liked(posts).forEach((p) => { bump(p.user_email, 0.6); hashtags(postText(p)).forEach((h) => addInterest(h, 1.2)); terms(postText(p)).forEach((t) => addInterest(t, 0.25)); });
  liked(artworks).forEach((a) => { bump(a.user_email || a.created_by, 0.5); if (a.medium) addInterest(String(a.medium).toLowerCase(), 0.6); });
  liked(tracks).forEach((t) => bump(t.user_email, 0.5));
  const postAuthor = Object.fromEntries(posts.map((p) => [p.id, p.user_email]));
  comments.filter((c) => c.user_email === email).forEach((c) => bump(postAuthor[c.post_id], 0.9));
  posts.filter((p) => p.user_email === email).forEach((p) => hashtags(postText(p)).forEach((h) => addInterest(h, 1.5)));
  Object.values(hiddenPosts()).forEach((h) => bump(h.author, -1.2));

  // Music taste: liked tracks count double, plays add up.
  const genres = new Map();
  const moods = new Map();
  const addTaste = (map, k, w) => { if (k) map.set(k, (map.get(k) || 0) + w); };
  liked(tracks).forEach((t) => { addTaste(genres, t.genre, 2); addTaste(moods, t.mood, 1.5); });
  Object.values(playHistory()).forEach((p) => { addTaste(genres, p.genre, cap(p.n, 5) * 0.5); addTaste(moods, p.mood, cap(p.n, 5) * 0.3); bump(p.author, cap(p.n, 5) * 0.2); });
  arr(me?.interests).forEach((i) => { addTaste(genres, i, 1); });

  return { email, following, friends: friendSet, affinity, interest, genres, moods };
}

function affinityOf(taste, who) {
  const a = taste.affinity.get(who) || 0;
  return a >= 0 ? cap(log1(a) * 1.4, 4) : Math.max(-2, a); // negative after "Not interested"
}
const nameOf = (users, email) => users?.[email]?.display_name || email?.split("@")[0] || "someone";

// ---------- feed ----------
// Returns [{ post, score, reason }] best-first.
export function rankFeed(posts, { taste, comments = [], users = {}, now = Date.now(), seen = seenPosts(), hidden = hiddenPosts() } = {}) {
  const email = taste?.email;
  posts = posts.filter((p) => !hidden[p.id]);
  const commentsByPost = new Map();
  comments.forEach((c) => { const l = commentsByPost.get(c.post_id) || []; l.push(c); commentsByPost.set(c.post_id, l); });
  const circle = new Set([...(taste?.following || []), ...(taste?.friends || [])]);

  const scored = posts.map((post) => {
    const age = hoursSince(post.created_date, now);
    const likes = post.likes || [];
    const cs = commentsByPost.get(post.id) || [];
    const recent = cs.filter((c) => hoursSince(c.created_date, now) < 24).length;
    const engagement = log1(likes.length + 2 * cs.length + 3 * recent);
    const affinity = taste ? affinityOf(taste, post.user_email) : 0;
    const friendLikes = likes.filter((e) => circle.has(e) && e !== post.user_email);
    const social = cap(friendLikes.length * 0.6, 2.4);
    const tags = hashtags(postText(post));
    let interest = 0;
    let matched = null;
    if (taste) {
      for (const t of [...tags, ...terms(postText(post))]) {
        const w = taste.interest.get(t);
        if (w) { interest += w; if (!matched || tags.includes(t)) matched = t; }
      }
      interest = cap(log1(interest), 2);
    }
    const quality = (post.image_url ? 0.35 : 0) + (String(post.description || "").length > 60 ? 0.1 : 0);
    const newCreator = age < 6 && likes.length === 0 && !circle.has(post.user_email) ? 0.5 : 0;
    const base = Math.max(0.1, 1 + engagement * 1.15 + affinity + social + interest + quality + newCreator);
    const decay = 1 / Math.pow(1 + age / 20, 1.35);
    let score = base * decay;
    if (seen[post.id]) score *= 0.55;
    const mine = post.user_email === email;
    if (mine) score = age < 0.25 ? score + 100 : score * 0.6; // your fresh post shows first, then steps back

    let reason = null;
    if (mine) reason = null;
    else if (friendLikes.length) reason = { icon: "heart", text: `Liked by ${nameOf(users, friendLikes[0])}${friendLikes.length > 1 ? ` and ${friendLikes.length - 1} more` : ""}` };
    else if (taste?.following.has(post.user_email)) reason = null; // obvious: you follow them
    else if (taste?.friends.has(post.user_email)) reason = { icon: "friend", text: "From your friend" };
    else if (matched && interest > 0.5) reason = { icon: "sparkles", text: tags.includes(matched) ? `Because you like #${matched}` : `Matches your interest in ${matched}` };
    else if (engagement > 2.2 && age < 72) reason = { icon: "flame", text: "Trending in the community" };
    else if (newCreator) reason = { icon: "sprout", text: "New post — be the first to react" };
    return { post, score, reason, author: post.user_email };
  });

  return diversify(scored);
}

// Greedy re-rank: each extra post by an author you've just seen is damped.
function diversify(items, { window = 4, damp = 0.55 } = {}) {
  const pool = [...items].sort((a, b) => b.score - a.score);
  const out = [];
  while (pool.length) {
    const recent = out.slice(-window).map((x) => x.author);
    let best = 0;
    let bestScore = -Infinity;
    for (let i = 0; i < Math.min(pool.length, 12); i++) {
      const repeats = recent.filter((a) => a === pool[i].author).length;
      const s = pool[i].score * Math.pow(damp, repeats);
      if (s > bestScore) { bestScore = s; best = i; }
    }
    out.push(pool.splice(best, 1)[0]);
  }
  return out;
}

// ---------- trending hashtags ----------
export function trendingTags(posts, { now = Date.now(), limit = 8, days = 14 } = {}) {
  const tags = new Map();
  posts.forEach((p) => {
    const age = hoursSince(p.created_date, now);
    if (age > days * 24) return;
    const w = (1 + log1(arr(p.likes).length)) / (1 + age / 36);
    new Set(hashtags(postText(p))).forEach((t) => {
      const cur = tags.get(t) || { tag: t, score: 0, posts: 0 };
      cur.score += w;
      cur.posts += 1;
      tags.set(t, cur);
    });
  });
  return [...tags.values()].sort((a, b) => b.score - a.score).slice(0, limit);
}

// ---------- people ----------
// users: all User docs. Returns [{ user, score, reason }].
// `exclude` defaults to people you already follow.
export function suggestPeople(users, { me, taste, posts = [], limit = 6, now = Date.now(), exclude } = {}) {
  if (!me) return [];
  const following = new Set(arr(me.following));
  const skip = exclude || following;
  const myInterests = new Set(arr(me.interests).map(lower));
  const likesReceived = new Map();
  const lastPost = new Map();
  posts.forEach((p) => {
    likesReceived.set(p.user_email, (likesReceived.get(p.user_email) || 0) + arr(p.likes).length);
    const t = new Date(p.created_date).getTime();
    if (t > (lastPost.get(p.user_email) || 0)) lastPost.set(p.user_email, t);
  });
  // People I follow, grouped by who they follow (for "Followed by …").
  const followers = new Map();
  users.forEach((x) => { if (following.has(x.email)) arr(x.following).forEach((e) => followers.set(e, [...(followers.get(e) || []), x])); });
  const followedBy = (u) => followers.get(u.email) || [];

  return users
    .filter((u) => u.email && u.email !== me.email && !skip.has(u.email))
    .map((u) => {
      const followsMe = arr(u.following).includes(me.email);
      const mutual = followedBy(u);
      const shared = arr(u.interests).filter((i) => myInterests.has(lower(i)));
      const popularity = log1(likesReceived.get(u.email) || 0);
      const active = lastPost.has(u.email) && now - lastPost.get(u.email) < 7 * 24 * HOUR;
      const online = u.last_seen && now - new Date(u.last_seen).getTime() < 5 * 60000;
      const isNew = u.created_date && now - new Date(u.created_date).getTime() < 7 * 24 * HOUR;
      const friend = taste?.friends?.has(u.email);
      const score = (followsMe ? 3 : 0) + (friend ? 2.5 : 0) + mutual.length * 1.4 + shared.length * 0.9 + popularity * 0.6 + (active ? 0.8 : 0) + (online ? 0.3 : 0) + (isNew ? 0.4 : 0) + (u.profile_picture ? 0.2 : 0);
      let reason;
      if (followsMe) reason = "Follows you";
      else if (friend) reason = "Your friend";
      else if (mutual.length) reason = `Followed by ${mutual[0].display_name || mutual[0].email.split("@")[0]}${mutual.length > 1 ? ` +${mutual.length - 1}` : ""}`;
      else if (shared.length) reason = `Also into ${shared.slice(0, 2).join(", ")}`;
      else if (popularity > 1.5) reason = "Popular creator";
      else if (isNew) reason = "New to Sugerly";
      else reason = active ? "Recently active" : "Suggested for you";
      return { user: u, score, reason };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}

// ---------- servers ----------
export function suggestServers(communities, { me, taste, limit = 4, now = Date.now(), includeJoined = false } = {}) {
  if (!me) return [];
  const circle = new Set([...(taste?.following || []), ...(taste?.friends || [])]);
  return communities
    .filter((c) => includeJoined || !arr(c.member_emails).includes(me.email))
    .map((c) => {
      const members = c.member_emails || [];
      const friendsIn = members.filter((e) => circle.has(e));
      let interest = 0;
      if (taste) terms(`${c.name} ${c.description}`).forEach((t) => { interest += taste.interest.get(t) || 0; });
      const fresh = now - new Date(c.created_date || 0).getTime() < 14 * 24 * HOUR;
      const score = friendsIn.length * 2.5 + log1(members.length) * 0.9 + cap(log1(interest), 2) * 1.2 + (fresh ? 0.4 : 0);
      const reason = friendsIn.length ? `${friendsIn.length} ${friendsIn.length === 1 ? "person you know is" : "people you know are"} here` : interest > 0.5 ? "Matches your interests" : members.length > 5 ? `Popular · ${members.length} members` : fresh ? "New server" : `${members.length} member${members.length === 1 ? "" : "s"}`;
      return { community: c, score, reason, friendsIn };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}

// ---------- music ----------
// Returns [{ track, score, reason }] for the "Made for you" shelf.
export function rankTracks(tracks, { taste, users = {}, now = Date.now() } = {}) {
  const email = taste?.email;
  const plays = playHistory();
  const circle = new Set([...(taste?.following || []), ...(taste?.friends || [])]);
  const topGenre = taste ? [...taste.genres.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] : null;
  return tracks
    .filter((t) => t.music_url)
    .map((t) => {
      const age = hoursSince(t.created_date, now);
      const likes = t.likes || [];
      const popularity = log1(likes.length * 2 + (t.plays || 0));
      const genre = taste ? cap(log1(taste.genres.get(t.genre) || 0), 2.5) : 0;
      const mood = taste ? cap(log1(taste.moods.get(t.mood) || 0), 1.5) : 0;
      const affinity = taste ? affinityOf(taste, t.user_email) : 0;
      const friendLikes = likes.filter((e) => circle.has(e));
      const listened = plays[t.id]?.n || 0;
      const decay = 1 / Math.pow(1 + age / 96, 0.8);
      let score = (1 + popularity + genre * 1.3 + mood * 0.7 + affinity * 0.8 + cap(friendLikes.length * 0.6, 2)) * decay;
      if (listened > 3) score *= 0.75; // you know this one already; make room for discoveries
      if (t.user_email === email) score *= 0.5;
      let reason;
      if (friendLikes.length) reason = `Liked by ${nameOf(users, friendLikes[0])}`;
      else if (genre > 0.8 && t.genre) reason = t.genre === topGenre ? `Your top genre · ${t.genre}` : `Because you like ${t.genre}`;
      else if (affinity > 1) reason = `More from ${t.user_display_name || "an artist you like"}`;
      else if (popularity > 2) reason = "Popular right now";
      else if (age < 48) reason = "Fresh upload";
      else reason = t.mood ? `${t.mood} vibes` : "Discover";
      return { track: t, score, reason };
    })
    .sort((a, b) => b.score - a.score);
}

// Tracks sorted by recent momentum (likes + plays, decayed over ~3 days).
export function trendingTracks(tracks, { now = Date.now() } = {}) {
  return tracks
    .filter((t) => t.music_url)
    .map((t) => ({ track: t, score: (log1(arr(t.likes).length * 2 + (t.plays || 0)) + 0.2) / (1 + hoursSince(t.created_date, now) / 72) }))
    .sort((a, b) => b.score - a.score)
    .map((x) => x.track);
}

// "More like this" for an open post: shared hashtags count most, then the
// same artist, people who liked both, similar words and freshness.
export function relatedPosts(post, posts, { limit = 6, exclude = new Set() } = {}) {
  if (!post) return [];
  const myTags = new Set(hashtags(postText(post)));
  const myTerms = new Set(terms(postText(post)));
  const myLikers = new Set(arr(post.likes));
  const hidden = hiddenPosts();
  return posts
    .filter((p) => p.id !== post.id && !exclude.has(p.user_email) && !hidden[p.id])
    .map((p) => {
      const tags = hashtags(postText(p));
      const shared = tags.filter((t) => myTags.has(t)).length;
      const words = terms(postText(p)).filter((t) => myTerms.has(t)).length;
      const likers = arr(p.likes).filter((e) => myLikers.has(e)).length;
      const score = shared * 3 + (p.user_email === post.user_email ? 1.5 : 0) + Math.min(3, likers) * 0.5 + Math.min(4, words) * 0.4 + (p.image_url ? 0.3 : 0) + 1 / (1 + hoursSince(p.created_date) / 72);
      return { p, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map((x) => x.p);
}
