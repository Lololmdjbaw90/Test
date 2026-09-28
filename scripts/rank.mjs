// Server-side work the phones and the website shouldn't do, run by
// .github/workflows/rank.yml (no Cloud Functions, so the free Firebase plan
// is enough):
//
// 1. Moves old likes into the Like table, once: every artwork, post, reel
//    and track that has no like_count yet gets one Like record per liker and
//    like_count = how many likers. It stops at a read/write budget and
//    carries on from the same place next run.
// 2. Scores every reel and community post whose likes, views or comments
//    changed since the last run. rank_score is "how good" plus "how new"
//    (the hot formula), so older things sink on their own and only changed
//    ones ever need a new score. It also keeps comment_count.
//
// Locally: FIREBASE_SERVICE_ACCOUNT="$(cat key.json)" node scripts/rank.mjs
import { cert, initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore } from "firebase-admin/firestore";

let key;
try { key = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || ""); } catch {
  console.error("FIREBASE_SERVICE_ACCOUNT isn't valid JSON.");
  process.exit(1);
}
initializeApp({ credential: cert(key), projectId: key.project_id });
const db = getFirestore();

// Stay well inside the free plan's daily limits (50k reads, 20k writes).
const MAX_READS = Number(process.env.RANK_MAX_READS || 6000);
const MAX_WRITES = Number(process.env.RANK_MAX_WRITES || 2500);
let reads = 0;
let writes = 0;
const budgetLeft = () => reads < MAX_READS && writes < MAX_WRITES;

const stateRef = db.doc("System/rank");
const state = (await stateRef.get()).data() || {};
reads += 1;
const persist = () => stateRef.set({ ...state, last_run: new Date().toISOString() }).then(() => { writes += 1; });

// ---- 1. Old likes -> Like table ------------------------------------------

const LIKED = ["Artwork", "CommunityPost", "Reel", "MusicReview"];
const SAMPLE_KEEP = 200; // likers kept on the post itself (faces, "liked by")
const uids = new Map(); // email -> uid (null when there's no account)

async function lookUp(emails) {
  const missing = [...new Set(emails)].filter((e) => !uids.has(e));
  for (let i = 0; i < missing.length; i += 30) {
    const chunk = missing.slice(i, i + 30);
    const snap = await db.collection("User").where("email", "in", chunk).get();
    reads += Math.max(snap.size, 1);
    chunk.forEach((e) => uids.set(e, null));
    snap.forEach((d) => uids.set(String(d.get("email")), d.id));
  }
}

const likeRef = (coll, id, email) => {
  const uid = uids.get(email);
  return uid ? db.doc(`Like/${coll}_${id}_${uid}`) : null;
};
const likeData = (coll, id, email, owner) => ({
  target_id: id, target_type: coll, user_email: email, owner_email: owner, created_date: new Date().toISOString(), migrated: true,
});
const likersOf = (data) => [...new Set((Array.isArray(data.likes) ? data.likes : []).filter((e) => typeof e === "string" && e))];

async function moveDoc(coll, snap) {
  const data = snap.data();
  if (typeof data.like_count === "number") return;
  const owner = data.user_email || data.created_by || data.owner_email || data.artist_email || "";
  const likers = likersOf(data);
  await lookUp(likers);
  // Like records first, in chunks...
  for (let i = 0; i < likers.length; i += 400) {
    const batch = db.batch();
    let n = 0;
    for (const email of likers.slice(i, i + 400)) {
      const ref = likeRef(coll, snap.id, email);
      if (ref) { batch.set(ref, likeData(coll, snap.id, email, owner)); n += 1; }
    }
    if (n) { await batch.commit(); writes += n; }
  }
  // ...then the count, re-reading the post so a like or unlike that landed
  // meanwhile is counted right.
  const fresh = await snap.ref.get();
  reads += 1;
  if (!fresh.exists || typeof fresh.get("like_count") === "number") return;
  const now = likersOf(fresh.data());
  await lookUp(now);
  const batch = db.batch();
  for (const email of now.filter((e) => !likers.includes(e))) {
    const ref = likeRef(coll, snap.id, email);
    if (ref) batch.set(ref, likeData(coll, snap.id, email, owner));
  }
  for (const email of likers.filter((e) => !now.includes(e))) {
    const ref = likeRef(coll, snap.id, email);
    if (ref) batch.delete(ref);
  }
  const patch = { like_count: now.length };
  if (now.length > 500) patch.likes = now.slice(-SAMPLE_KEEP);
  batch.update(snap.ref, patch);
  await batch.commit();
  writes += 1 + Math.abs(now.length - likers.length);
}

async function moveLikes(coll) {
  const key = `likes_moved_${coll}`;
  if (state[key] === "done") return;
  while (budgetLeft()) {
    let q = db.collection(coll).orderBy(FieldPath.documentId()).limit(200);
    if (state[key]) q = q.startAfter(state[key]);
    const page = await q.get();
    reads += Math.max(page.size, 1);
    if (page.empty) { state[key] = "done"; break; }
    for (const snap of page.docs) {
      if (!budgetLeft()) break;
      await moveDoc(coll, snap);
      state[key] = snap.id;
    }
    await persist();
  }
  await persist();
  console.log(`${coll}: likes ${state[key] === "done" ? "all in the Like table" : `moved up to ${state[key]}`}`);
}

// ---- 2. Scores -------------------------------------------------------------

const EPOCH = 1.7e9; // seconds; only shifts every score by the same amount
const HALF_LIFE = 45000; // ~12.5 hours of newness is worth 10x the engagement

function rankScore(data, comments) {
  const likes = typeof data.like_count === "number" ? data.like_count : likersOf(data).length;
  const views = Math.max(Number(data.views) || 0, likes);
  const shares = Number(data.shares) || 0;
  const engagement = 1 + likes * 2 + comments * 3 + shares * 4 + views * 0.05;
  // Likes and comments per view (smoothed so 2 of 3 views doesn't beat a proven one).
  const rate = Math.min((likes + comments * 2 + 1) / (views + 10), 1);
  const created = (Date.parse(data.created_date) || Date.now()) / 1000;
  const score = Math.log10(engagement) + Math.log10(1 + 20 * rate) + (created - EPOCH) / HALF_LIFE;
  return Math.round(score * 1e6) / 1e6;
}

// Comments on reels have post_id "reel_<id>"; on posts just "<id>".
const RANKED = { Reel: "reel_", CommunityPost: "" };

async function commentCount(coll, id) {
  const agg = await db.collection("CommunityComment").where("post_id", "==", RANKED[coll] + id).count().get();
  reads += 1;
  return agg.data().count;
}

async function newlyCommented() {
  const out = { Reel: new Set(), CommunityPost: new Set(), until: state.comments_since };
  const since = state.comments_since || new Date(Date.now() - 86_400_000).toISOString();
  const snap = await db.collection("CommunityComment").where("created_date", ">", since).orderBy("created_date").limit(2000).get();
  reads += Math.max(snap.size, 1);
  snap.forEach((d) => {
    const post = String(d.get("post_id") || "");
    if (post.startsWith("reel_")) out.Reel.add(post.slice(5));
    else if (post && !post.startsWith("profile_")) out.CommunityPost.add(post);
    out.until = String(d.get("created_date"));
  });
  return out;
}

async function rescore(coll, extra) {
  const key = `ranked_since_${coll}`;
  const seen = new Set();
  const score = async (snap) => {
    if (seen.has(snap.id) || !snap.exists) return;
    seen.add(snap.id);
    const data = snap.data();
    const comments = await commentCount(coll, snap.id);
    const rank = rankScore(data, comments);
    if (data.rank_score === rank && data.comment_count === comments) return;
    // Not touching updated_date, so the next run doesn't see it as changed.
    await snap.ref.update({ rank_score: rank, comment_count: comments, rank_updated: new Date().toISOString() });
    writes += 1;
  };
  // Everything liked, viewed or edited since last time (oldest first).
  while (budgetLeft()) {
    let q = db.collection(coll).orderBy("updated_date").limit(300);
    if (state[key]) q = q.where("updated_date", ">", state[key]);
    const page = await q.get();
    reads += Math.max(page.size, 1);
    for (const snap of page.docs) {
      if (!budgetLeft()) break;
      await score(snap);
      state[key] = String(snap.get("updated_date") || state[key] || "");
    }
    if (page.size < 300) break;
  }
  // And anything with new comments.
  for (const id of extra) {
    if (!budgetLeft()) break;
    const snap = await db.doc(`${coll}/${id}`).get();
    reads += 1;
    await score(snap);
  }
  await persist();
  console.log(`${coll}: scored ${seen.size} (${reads} reads, ${writes} writes so far)`);
}

for (const coll of LIKED) await moveLikes(coll);
const commented = await newlyCommented();
for (const coll of Object.keys(RANKED)) await rescore(coll, commented[coll]);
// Only move past these comments once every post they touched is scored.
if (budgetLeft() && commented.until) state.comments_since = commented.until;
await persist();
console.log(`Done: ${reads} reads, ${writes} writes.`);
