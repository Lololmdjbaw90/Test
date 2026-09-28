import { useEffect, useSyncExternalStore } from "react";
import { arrayRemove, arrayUnion, doc, getDoc, increment, serverTimestamp, updateDoc, writeBatch } from "firebase/firestore";
import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { notify } from "@/utils/notifications";

// Likes that scale to any number of people: one Like record per person per
// post/artwork/reel/track ("<Collection>_<id>_<uid>") plus a like_count on the
// thing, written together (the database rules check they match). The thing's
// `likes` list is only a small sample of likers, for faces and "liked by".
// Older things without a like_count still use the plain list until
// scripts/rank.mjs moves them over. The iOS app does the same (App/Likes.swift).
export const SAMPLE_SIZE = 200;
const LIKE_TABLE = new Set(["Artwork", "CommunityPost", "Reel", "MusicReview"]);

// What the Like table said about things whose sample doesn't show me.
const known = new Map(); // "<Collection>_<id>" -> liked by me
const asked = new Set();
const listeners = new Set();
let version = 0;
const emit = () => { version += 1; listeners.forEach((l) => l()); };
const subscribe = (l) => { listeners.add(l); return () => listeners.delete(l); };
const getVersion = () => version;

const db = () => base44.firebase?.db || null;
const myUid = () => base44.firebase?.auth?.currentUser?.uid || null;
const counted = (entity, record) => LIKE_TABLE.has(entity) && typeof record?.like_count === "number" && !!db() && !!myUid();

export { likeCount } from "@/lib/likeCount";

export function isLiked(record, user, entity) {
  if (!record || !user?.email) return false;
  if ((record.likes || []).includes(user.email)) return true;
  return known.get(`${entity}_${record.id}`) === true;
}

// Re-renders when the Like table answers, and asks it about the given things
// liked by more people than their sample holds (only popular ones).
export function useLikes(entity, records, user) {
  useSyncExternalStore(subscribe, getVersion, getVersion);
  useEffect(() => { prime(entity, records, user); }, [entity, records, user?.email]);
}

async function prime(entity, records, user) {
  const uid = myUid();
  if (!db() || !uid || !user?.email || !LIKE_TABLE.has(entity)) return;
  const todo = (records || []).filter((r) => {
    const key = `${entity}_${r?.id}`;
    return r && typeof r.like_count === "number" && r.like_count > (r.likes || []).length
      && !(r.likes || []).includes(user.email) && !known.has(key) && !asked.has(key);
  }).slice(0, 60);
  if (!todo.length) return;
  todo.forEach((r) => asked.add(`${entity}_${r.id}`));
  const found = await Promise.all(todo.map((r) => getDoc(doc(db(), "Like", `${entity}_${r.id}_${uid}`)).then((s) => s.exists()).catch(() => null)));
  todo.forEach((r, i) => { if (found[i] !== null) known.set(`${entity}_${r.id}`, found[i]); });
  emit();
}

// Adds one to a counter without overwriting anyone else's (views, plays).
export async function addOne(entity, record, field) {
  if (!db()) return base44.entities[entity].update(record.id, { [field]: (record[field] || 0) + 1 });
  return updateDoc(doc(db(), entity, record.id), { [field]: increment(1), updated_date: new Date().toISOString(), updated_at: serverTimestamp() });
}

// Adds or takes out one person in a list field without overwriting anyone
// else's change (comment likes and older things).
export async function likeInList(entity, record, email, on) {
  if (!db()) {
    const cur = record.likes || [];
    await base44.entities[entity].update(record.id, { likes: on ? [...cur.filter((e) => e !== email), email] : cur.filter((e) => e !== email) });
    return;
  }
  await updateDoc(doc(db(), entity, record.id), {
    likes: on ? arrayUnion(email) : arrayRemove(email), updated_date: new Date().toISOString(), updated_at: serverTimestamp(),
  });
}

async function writeLike(entity, record, user, liking) {
  if (!counted(entity, record)) {
    try {
      await likeInList(entity, record, user.email, liking);
    } catch (e) {
      // Moved to the Like table since this page loaded: do it that way.
      const fresh = db() && LIKE_TABLE.has(entity) ? await getDoc(doc(db(), entity, record.id)).catch(() => null) : null;
      if (fresh?.exists() && typeof fresh.data().like_count === "number") return writeLike(entity, { ...fresh.data(), id: record.id }, user, liking);
      throw e;
    }
    return;
  }
  const now = new Date().toISOString();
  const stamp = { updated_date: now, updated_at: serverTimestamp() };
  const batch = writeBatch(db());
  const likeRef = doc(db(), "Like", `${entity}_${record.id}_${myUid()}`);
  const target = doc(db(), entity, record.id);
  if (liking) {
    batch.set(likeRef, { target_id: record.id, target_type: entity, user_email: user.email, owner_email: record.user_email || record.created_by || "", created_date: now });
    batch.update(target, { like_count: increment(1), ...((record.likes || []).length < SAMPLE_SIZE ? { likes: arrayUnion(user.email) } : {}), ...stamp });
  } else {
    batch.delete(likeRef);
    batch.update(target, { like_count: increment(-1), likes: arrayRemove(user.email), ...stamp });
  }
  await batch.commit();
}

// Optimistically flips my like on `record` and notifies the owner on a new like.
export async function toggleLike({ entity, record, user, setData, message, link }) {
  if (!user || !record) return;
  const key = `${entity}_${record.id}`;
  const liking = !isLiked(record, user, entity);
  const sample = record.likes || [];
  const isCounted = counted(entity, record);
  const nextLikes = liking
    ? (sample.includes(user.email) || (isCounted && sample.length >= SAMPLE_SIZE) ? sample : [...sample, user.email])
    : sample.filter((e) => e !== user.email);
  const patch = (likes, count) => setData?.((list) => list.map((r) => (r.id === record.id ? { ...r, likes, ...(count !== undefined ? { like_count: count } : {}) } : r)));
  patch(nextLikes, isCounted ? Math.max(0, record.like_count + (liking ? 1 : -1)) : undefined);
  const had = known.get(key);
  known.set(key, liking);
  emit();
  try {
    await writeLike(entity, record, user, liking);
    const owner = record.user_email || record.created_by;
    if (liking && owner && owner !== user.email) {
      await notify({ to_email: owner, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture, type: "like", message: `${displayName(user)} ${message}`, link, entity_id: record.id });
    }
  } catch (e) {
    patch(sample, isCounted ? record.like_count : undefined);
    if (had === undefined) known.delete(key); else known.set(key, had);
    emit();
    toast.error(e?.message || "Could not update like.");
  }
}

