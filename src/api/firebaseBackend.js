// Firebase backend for Mimi Locks.
// -----------------------------------------------------------------------------
// This keeps the same `base44` API shape used by the app, but stores data in:
// - Firebase Authentication for real email/password accounts
// - Cloud Firestore for users, artworks, posts, comments, follows, likes, servers,
//   channels, messages, settings and logs
// - Firebase Storage for uploaded images/audio when a storage bucket is configured
//
// Required Vite env vars:
// VITE_FIREBASE_API_KEY
// VITE_FIREBASE_AUTH_DOMAIN
// VITE_FIREBASE_PROJECT_ID
// VITE_FIREBASE_STORAGE_BUCKET
// VITE_FIREBASE_MESSAGING_SENDER_ID
// VITE_FIREBASE_APP_ID
// -----------------------------------------------------------------------------

import { initializeApp } from "firebase/app";
import {
  getAuth,
  onAuthStateChanged,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  updateProfile,
} from "firebase/auth";
import {
  getFirestore,
  collection,
  doc,
  addDoc,
  setDoc,
  getDoc,
  getDocs,
  updateDoc,
  deleteDoc,
  query,
  where,
  orderBy,
  limit as qLimit,
  onSnapshot,
  serverTimestamp,
} from "firebase/firestore";
import {
  getStorage,
  ref,
  uploadBytes,
  getDownloadURL,
} from "firebase/storage";
import { moderate } from "../utils/profanity.js";

const ENTITY_NAMES = [
  "Artwork", "ArtworkPing", "ChannelMessage", "Comment", "Commission", "Community",
  "CommunityComment", "CommunityPost", "DirectMessage", "Friendship", "GroupChat", "Log", "MusicReview",
  "Notification", "ServerChannel", "ServerMember", "ServerRole", "SiteConfig", "User",
];

const FIREBASE_COLLECTIONS = Object.fromEntries(ENTITY_NAMES.map((name) => [name, name]));
const normalizeEmail = (email) => String(email || "").trim().toLowerCase();
const nowISO = () => new Date().toISOString();
function firebaseConfigFromEnv() {
  return {
    apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
    authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
    projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
    storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
    messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
    appId: import.meta.env.VITE_FIREBASE_APP_ID,
  };
}

export function hasFirebaseConfig() {
  const cfg = firebaseConfigFromEnv();
  return !!(cfg.apiKey && cfg.authDomain && cfg.projectId && cfg.appId);
}

function cleanObject(obj) {
  const out = {};
  Object.entries(obj || {}).forEach(([k, v]) => {
    if (v !== undefined) out[k] = v;
  });
  return out;
}

function serializeDoc(snapshot) {
  if (!snapshot.exists()) return null;
  const data = snapshot.data() || {};
  const convert = (v) => v && typeof v.toDate === "function" ? v.toDate().toISOString() : v;
  const converted = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, convert(v)]));
  return { id: snapshot.id, ...converted };
}

function serializeQuerySnapshot(snapshot) {
  return snapshot.docs.map(serializeDoc).filter(Boolean);
}

function publicUserFromFirebaseUser(firebaseUser, profile = {}) {
  if (!firebaseUser) return null;
  const email = normalizeEmail(firebaseUser.email);
  return {
    id: firebaseUser.uid,
    email,
    full_name: profile.full_name || firebaseUser.displayName || email.split("@")[0],
    display_name: profile.display_name || firebaseUser.displayName || email.split("@")[0],
    profile_picture: profile.profile_picture || firebaseUser.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(email.split("@")[0])}&background=d4708a&color=fff&bold=true`,
    role: profile.role || "user",
    bio: profile.bio || "",
    following: profile.following || [],
    followers: profile.followers || [],
    xp: profile.xp || 0,
    coins: profile.coins || 0,
    nitro_until: profile.nitro_until || null,
    onboarding_completed: profile.onboarding_completed ?? false,
    theme: profile.theme || "light",
    last_seen: profile.last_seen || nowISO(),
    created_date: profile.created_date || nowISO(),
    updated_date: profile.updated_date || nowISO(),
  };
}

export function createFirebaseClient() {
  const app = initializeApp(firebaseConfigFromEnv());
  const authSdk = getAuth(app);
  const db = getFirestore(app);
  const storage = import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ? getStorage(app) : null;

  let authReadyPromise = null;
  function waitForAuthReady() {
    if (!authReadyPromise) {
      authReadyPromise = new Promise((resolve) => {
        const unsub = onAuthStateChanged(authSdk, (user) => { unsub(); resolve(user); });
      });
    }
    return authReadyPromise;
  }

  async function currentFirebaseUser() {
    return authSdk.currentUser || await waitForAuthReady();
  }

  async function currentUser() {
    const firebaseUser = await currentFirebaseUser();
    if (!firebaseUser) throw new Error("auth_required");
    const refDoc = doc(db, "User", firebaseUser.uid);
    const snap = await getDoc(refDoc);
    if (snap.exists()) return serializeDoc(snap);

    const profile = publicUserFromFirebaseUser(firebaseUser, { role: "user" });
    await setDoc(refDoc, cleanObject({ ...profile, created_date: nowISO(), updated_date: nowISO() }));
    return profile;
  }

  function isAdminUser(user) { return user?.role === "admin"; }
  function isOwner(user, record) {
    const email = normalizeEmail(user?.email);
    return [record?.created_by, record?.user_email, record?.owner_email, record?.artist_email, record?.requester_email].some((v) => normalizeEmail(v) === email);
  }
  async function canManageCommunity(user, communityId) {
    if (!user || !communityId) return false;
    if (isAdminUser(user)) return true;
    const snap = await getDoc(doc(db, "Community", communityId));
    const comm = serializeDoc(snap);
    return normalizeEmail(comm?.owner_email) === normalizeEmail(user.email);
  }
  async function canUpdateEntity(user, name, current, data = {}) {
    if (!user) return false;
    if (isAdminUser(user)) return true;
    if (name === "SiteConfig" || name === "Log" || name === "User") return false;
    if (["ServerChannel", "ServerRole", "ServerMember"].includes(name)) return canManageCommunity(user, current?.community_id || data.community_id);
    if (name === "Community") {
      const keys = Object.keys(data || {});
      if (keys.length === 1 && keys[0] === "member_emails") return true;
      return normalizeEmail(current?.owner_email) === normalizeEmail(user.email);
    }
    if (name === "ChannelMessage") {
      const keys = Object.keys(data || {});
      if (keys.every((k) => ["reactions", "thread_count"].includes(k))) return true;
      if (data.is_pinned !== undefined && await canManageCommunity(user, current?.community_id)) return true;
      return normalizeEmail(current?.user_email) === normalizeEmail(user.email);
    }
    if (["Artwork", "CommunityPost", "MusicReview", "Comment", "CommunityComment", "Commission", "GroupChat", "DirectMessage", "ProfileMessage"].includes(name)) {
      const keys = Object.keys(data || {});
      if (keys.length === 1 && keys[0] === "likes") return true;
      return isOwner(user, current);
    }
    return true;
  }
  async function canDeleteEntity(user, name, current) {
    if (!user) return false;
    if (isAdminUser(user)) return true;
    if (name === "SiteConfig" || name === "Log" || name === "User") return false;
    if (["ServerChannel", "ServerRole", "ServerMember"].includes(name)) return canManageCommunity(user, current?.community_id);
    if (name === "Community") return normalizeEmail(current?.owner_email) === normalizeEmail(user.email);
    if (name === "ChannelMessage") return normalizeEmail(current?.user_email) === normalizeEmail(user.email) || await canManageCommunity(user, current?.community_id);
    return isOwner(user, current);
  }

  function buildQuery(name, queryObject, sort, limitAmount) {
    const constraints = [];
    Object.entries(queryObject || {}).forEach(([field, value]) => {
      constraints.push(where(field, "==", value));
    });
    if (sort) {
      const desc = sort.startsWith("-");
      constraints.push(orderBy(desc ? sort.slice(1) : sort, desc ? "desc" : "asc"));
    }
    if (limitAmount != null) constraints.push(qLimit(limitAmount));
    return query(collection(db, FIREBASE_COLLECTIONS[name]), ...constraints);
  }

  function makeEntity(name) {
    const colName = FIREBASE_COLLECTIONS[name];
    return {
      async list(sort, limitAmount) {
        const snap = await getDocs(buildQuery(name, null, sort, limitAmount));
        return serializeQuerySnapshot(snap);
      },
      async filter(queryObject, sort, limitAmount) {
        const snap = await getDocs(buildQuery(name, queryObject, sort, limitAmount));
        return serializeQuerySnapshot(snap);
      },
      async get(id) {
        const snap = await getDoc(doc(db, colName, id));
        return serializeDoc(snap);
      },
      async create(data) {
        const me = await currentUser();
        if (name === "SiteConfig" && !isAdminUser(me)) throw new Error("permission_denied");
        if (["ServerChannel", "ServerRole", "ServerMember"].includes(name) && !await canManageCommunity(me, data?.community_id)) throw new Error("permission_denied");
        const payload = cleanObject({
          created_date: nowISO(),
          updated_date: nowISO(),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
          created_by: me.email,
          ...data,
        });
        const refDoc = await addDoc(collection(db, colName), payload);
        return { id: refDoc.id, ...payload };
      },
      async update(id, data) {
        const me = await currentUser();
        const refDoc = doc(db, colName, id);
        const current = serializeDoc(await getDoc(refDoc));
        if (!current) return null;
        if (!await canUpdateEntity(me, name, current, data)) throw new Error("permission_denied");
        const payload = cleanObject({ ...data, updated_date: nowISO(), updated_at: serverTimestamp() });
        await updateDoc(refDoc, payload);
        return { ...current, ...data, updated_date: payload.updated_date };
      },
      async delete(id) {
        const me = await currentUser();
        const refDoc = doc(db, colName, id);
        const current = serializeDoc(await getDoc(refDoc));
        if (current && !await canDeleteEntity(me, name, current)) throw new Error("permission_denied");
        await deleteDoc(refDoc);
        return { id, success: true };
      },
      async bulkCreate(items) {
        const created = [];
        for (const item of items || []) created.push(await this.create(item));
        return created;
      },
      subscribe(callback, queryObject = null, sort = "-created_date", limitAmount = 200) {
        return onSnapshot(buildQuery(name, queryObject, sort, limitAmount), (snap) => {
          callback({ type: "snapshot", data: serializeQuerySnapshot(snap) });
        });
      },
    };
  }

  const entities = {};
  ENTITY_NAMES.forEach((name) => { entities[name] = makeEntity(name); });

  const auth = {
    async me() { return currentUser(); },
    async register({ email, password, display_name, full_name }) {
      email = normalizeEmail(email);
      if (!email || !password || password.length < 6) throw new Error("Email and a 6+ character password are required.");
      const cred = await createUserWithEmailAndPassword(authSdk, email, password);
      const name = (display_name || full_name || email.split("@")[0]).trim();
      await updateProfile(cred.user, { displayName: name });
      const profile = publicUserFromFirebaseUser(cred.user, {
        full_name: name,
        display_name: name,
        role: "user",
      });
      await setDoc(doc(db, "User", cred.user.uid), cleanObject(profile));
      return profile;
    },
    async login({ email, password } = {}) {
      const cred = await signInWithEmailAndPassword(authSdk, normalizeEmail(email), password || "");
      const profile = await currentUser();
      await updateDoc(doc(db, "User", cred.user.uid), { last_seen: nowISO(), updated_date: nowISO(), updated_at: serverTimestamp() }).catch(() => {});
      return profile;
    },
    async updateMe(data) {
      const me = await currentUser();
      const safeData = cleanObject({ ...data });
      delete safeData.role; delete safeData.email; delete safeData.id;
      const next = { ...safeData, updated_date: nowISO(), updated_at: serverTimestamp() };
      await updateDoc(doc(db, "User", me.id), next);
      return { ...me, ...safeData, updated_date: next.updated_date };
    },
    async logout() {
      await signOut(authSdk);
      window.location.href = "/Login";
    },
    redirectToLogin() { window.location.href = "/Login"; },
    async isAdmin() { const u = await currentUser(); return u.role === "admin"; },
  };

  const integrations = {
    Core: {
      async UploadFile(args) {
        const file = args?.file;
        if (!file) return { file_url: "" };
        const me = await currentUser();
        if (!storage) {
          // Storage bucket missing: keep the app usable while config is incomplete.
          return await new Promise((resolve, reject) => {
            const fr = new FileReader();
            fr.onload = () => resolve({ file_url: fr.result });
            fr.onerror = reject;
            fr.readAsDataURL(file);
          });
        }
        const safeName = String(file.name || "upload").replace(/[^a-zA-Z0-9._-]/g, "_");
        const fileRef = ref(storage, `uploads/${me.id}/${Date.now()}-${safeName}`);
        await uploadBytes(fileRef, file, { contentType: file.type || "application/octet-stream" });
        return { file_url: await getDownloadURL(fileRef) };
      },
      async InvokeLLM(args) {
        const schema = args?.response_json_schema;
        const prompt = args?.prompt || "";
        if (schema?.properties?.safe) return moderate(prompt);
        if (schema?.properties) {
          const out = {};
          Object.entries(schema.properties).forEach(([key, value]) => {
            const type = value?.type;
            out[key] = type === "array" ? [] : type === "object" ? {} : type === "boolean" ? true : type === "number" || type === "integer" ? 0 : "";
          });
          return out;
        }
        return "";
      },
    },
  };

  return { entities, auth, integrations, firebase: { app, auth: authSdk, db, storage } };
}
