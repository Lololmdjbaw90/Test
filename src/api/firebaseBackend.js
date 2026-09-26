// Firebase backend for Mimi Locks.
// -----------------------------------------------------------------------------
// Same `base44` API shape as the local backend, backed by:
// - Firebase Authentication for real email/password accounts
// - Cloud Firestore for every entity (one collection per entity name)
// - Firebase Storage for uploaded images/audio when a bucket is configured
//
// Queries are written so they satisfy firestore.rules (e.g. private collections
// are always filtered by the signed-in user's email). Filtered + sorted queries
// use the composite indexes in firestore.indexes.json; if an index has not been
// deployed yet we fall back to an unsorted query and sort on the client, so the
// site keeps working either way.
//
// Required Vite env vars:
// VITE_FIREBASE_API_KEY, VITE_FIREBASE_AUTH_DOMAIN, VITE_FIREBASE_PROJECT_ID,
// VITE_FIREBASE_STORAGE_BUCKET, VITE_FIREBASE_MESSAGING_SENDER_ID, VITE_FIREBASE_APP_ID
// Optional: VITE_FIREBASE_EMULATOR_HOST=127.0.0.1 to use local emulators.
// -----------------------------------------------------------------------------

import { initializeApp } from "firebase/app";
import { Capacitor } from "@capacitor/core";
import {
  getAuth,
  initializeAuth,
  indexedDBLocalPersistence,
  EmailAuthProvider,
  reauthenticateWithCredential,
  deleteUser,
  onAuthStateChanged,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  signOut,
  updateProfile,
  connectAuthEmulator,
} from "firebase/auth";
import {
  getFirestore,
  collection,
  doc,
  documentId,
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
  connectFirestoreEmulator,
} from "firebase/firestore";
import { getStorage, ref, uploadBytes, getDownloadURL, connectStorageEmulator } from "firebase/storage";
import { moderate } from "../utils/profanity.js";
import { isOperator, sortAndLimit } from "./queryUtils.js";
import { ENTITY_NAMES } from "./localBackend.js";

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
  Object.entries(obj || {}).forEach(([k, v]) => { if (v !== undefined) out[k] = v; });
  return out;
}

const convertValue = (v) => (v && typeof v.toDate === "function" ? v.toDate().toISOString() : v);
function serializeDoc(snapshot) {
  if (!snapshot.exists()) return null;
  const data = snapshot.data() || {};
  return { id: snapshot.id, ...Object.fromEntries(Object.entries(data).map(([k, v]) => [k, convertValue(v)])) };
}
const serializeQuerySnapshot = (snapshot) => snapshot.docs.map(serializeDoc).filter(Boolean);
// Drop server-timestamp sentinels before handing a freshly written object to the UI.
const withoutSentinels = ({ created_at, updated_at, ...rest }) => rest;

function publicUserFromFirebaseUser(firebaseUser, profile = {}) {
  if (!firebaseUser) return null;
  const email = normalizeEmail(firebaseUser.email);
  const name = profile.display_name || firebaseUser.displayName || email.split("@")[0];
  return {
    id: firebaseUser.uid,
    email,
    full_name: profile.full_name || name,
    display_name: name,
    profile_picture: profile.profile_picture || firebaseUser.photoURL || "",
    role: "user",
    bio: "",
    following: [],
    xp: 0,
    coins: 0,
    nitro_until: null,
    nitro_active: false,
    onboarding_completed: false,
    theme: "light",
    accent: "rose",
    saved_artworks: [],
    last_seen: nowISO(),
    created_date: nowISO(),
    updated_date: nowISO(),
  };
}

const isIndexError = (e) => e?.code === "failed-precondition" || /requires an index/i.test(e?.message || "");
const warnedIndexes = new Set();
function warnMissingIndex(name, e) {
  const key = `${name}:${e?.message}`;
  if (warnedIndexes.has(key)) return;
  warnedIndexes.add(key);
  console.info(`[firebase] ${name}: composite index missing, sorting on the client instead. Deploy firestore.indexes.json to speed this up.`, e?.message);
}

export function createFirebaseClient() {
  const app = initializeApp(firebaseConfigFromEnv());
  // Inside the iOS app, getAuth() can stall waiting for a browser popup helper
  // that WKWebView doesn't have; email/password sign-in only needs storage.
  const authSdk = Capacitor.isNativePlatform() ? initializeAuth(app, { persistence: indexedDBLocalPersistence }) : getAuth(app);
  const db = getFirestore(app);
  const storage = import.meta.env.VITE_FIREBASE_STORAGE_BUCKET ? getStorage(app) : null;

  const emulatorHost = import.meta.env.VITE_FIREBASE_EMULATOR_HOST;
  if (emulatorHost) {
    connectAuthEmulator(authSdk, `http://${emulatorHost}:9099`, { disableWarnings: true });
    connectFirestoreEmulator(db, emulatorHost, 8080);
    if (storage) connectStorageEmulator(storage, emulatorHost, 9199);
  }

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
    const profile = publicUserFromFirebaseUser(firebaseUser);
    await setDoc(refDoc, cleanObject(profile));
    return profile;
  }

  function buildConstraints(queryObject) {
    const constraints = [];
    Object.entries(queryObject || {}).forEach(([field, value]) => {
      const path = field === "id" ? documentId() : field;
      if (isOperator(value)) {
        if ("$contains" in value) constraints.push(where(path, "array-contains", value.$contains));
        if ("$in" in value) constraints.push(where(path, "in", value.$in.length ? value.$in : ["__none__"]));
      } else {
        constraints.push(where(path, "==", value));
      }
    });
    return constraints;
  }
  function buildQuery(name, queryObject, sort, limitAmount) {
    const constraints = buildConstraints(queryObject);
    if (sort) {
      const desc = sort.startsWith("-");
      constraints.push(orderBy(desc ? sort.slice(1) : sort, desc ? "desc" : "asc"));
    }
    if (limitAmount != null) constraints.push(qLimit(limitAmount));
    return query(collection(db, name), ...constraints);
  }
  const hasFilters = (queryObject) => Object.keys(queryObject || {}).length > 0;

  async function runQuery(name, queryObject, sort, limitAmount) {
    if (hasFilters(queryObject) && sort) {
      try {
        return serializeQuerySnapshot(await getDocs(buildQuery(name, queryObject, sort, limitAmount)));
      } catch (e) {
        if (!isIndexError(e)) throw e;
        warnMissingIndex(name, e);
      }
      const all = serializeQuerySnapshot(await getDocs(buildQuery(name, queryObject, null, null)));
      return sortAndLimit(all, sort, limitAmount);
    }
    return serializeQuerySnapshot(await getDocs(buildQuery(name, queryObject, sort, limitAmount)));
  }

  function makeEntity(name) {
    return {
      list(sort, limitAmount) { return runQuery(name, null, sort, limitAmount); },
      filter(queryObject, sort, limitAmount) { return runQuery(name, queryObject, sort, limitAmount); },
      async get(id) {
        if (!id) return null;
        return serializeDoc(await getDoc(doc(db, name, id)));
      },
      async create(data) {
        const me = await currentUser();
        const payload = cleanObject({
          created_date: nowISO(),
          updated_date: nowISO(),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
          created_by: me.email,
          ...data,
        });
        const refDoc = await addDoc(collection(db, name), payload);
        return { id: refDoc.id, ...withoutSentinels(payload) };
      },
      async update(id, data) {
        await currentUser();
        const refDoc = doc(db, name, id);
        const payload = cleanObject({ ...data, updated_date: nowISO(), updated_at: serverTimestamp() });
        await updateDoc(refDoc, payload);
        const snap = await getDoc(refDoc).catch(() => null);
        return (snap && serializeDoc(snap)) || { id, ...withoutSentinels(payload) };
      },
      async delete(id) {
        await currentUser();
        await deleteDoc(doc(db, name, id));
        return { id, success: true };
      },
      async bulkCreate(items) {
        const created = [];
        for (const item of items || []) created.push(await this.create(item));
        return created;
      },
      // callback({ type: "create" | "update" | "delete", id, data, initial })
      // Documents already present when the listener attaches arrive once as
      // `create` events flagged `initial: true`.
      subscribe(callback, queryObject = null, { sort = null, limit = null } = {}) {
        let unsub = () => {};
        let cancelled = false;
        const listen = (useSort) => {
          let first = true;
          const q = useSort ? buildQuery(name, queryObject, sort, limit) : buildQuery(name, queryObject, null, null);
          unsub = onSnapshot(q, (snap) => {
            const initial = first;
            first = false;
            snap.docChanges().forEach((change) => {
              const data = serializeDoc(change.doc);
              const type = change.type === "added" ? "create" : change.type === "modified" ? "update" : "delete";
              callback({ type, id: change.doc.id, data, initial });
            });
          }, (e) => {
            if (!cancelled && useSort && isIndexError(e)) { warnMissingIndex(name, e); listen(false); return; }
            console.warn(`[firebase] ${name} subscription error:`, e?.message || e);
          });
        };
        listen(!!(sort || limit));
        return () => { cancelled = true; unsub(); };
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
      const cred = await createUserWithEmailAndPassword(authSdk, email, password).catch((e) => { throw friendlyAuthError(e); });
      const name = (display_name || full_name || email.split("@")[0]).trim();
      await updateProfile(cred.user, { displayName: name });
      const profile = publicUserFromFirebaseUser(cred.user, { full_name: name, display_name: name });
      await setDoc(doc(db, "User", cred.user.uid), cleanObject(profile));
      return profile;
    },
    async login({ email, password } = {}) {
      const cred = await signInWithEmailAndPassword(authSdk, normalizeEmail(email), password || "").catch((e) => { throw friendlyAuthError(e); });
      const profile = await currentUser();
      await updateDoc(doc(db, "User", cred.user.uid), { last_seen: nowISO(), updated_date: nowISO() }).catch(() => {});
      return profile;
    },
    async updateMe(data) {
      const me = await currentUser();
      const safeData = cleanObject({ ...data });
      ["role", "email", "id"].forEach((k) => delete safeData[k]);
      const next = { ...safeData, updated_date: nowISO() };
      await updateDoc(doc(db, "User", me.id), next);
      return { ...me, ...next };
    },
    async resetPassword(email) {
      await sendPasswordResetEmail(authSdk, normalizeEmail(email)).catch((e) => { throw friendlyAuthError(e); });
    },
    // Confirms the password (Firebase needs a fresh sign-in before deleting).
    async verifyPassword(password) {
      const user = authSdk.currentUser;
      if (!user) throw new Error("You're not signed in.");
      await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email, password || "")).catch((e) => { throw friendlyAuthError(e); });
    },
    // Removes the profile and the sign-in account. Call verifyPassword first.
    async deleteAccount() {
      const user = authSdk.currentUser;
      if (!user) throw new Error("You're not signed in.");
      await deleteDoc(doc(db, "User", user.uid)).catch(() => {});
      await deleteUser(user).catch((e) => { throw friendlyAuthError(e); });
      window.location.href = "/Login";
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
          // No bucket configured: keep the app usable with an inline data URL.
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

  return { entities, auth, integrations, mode: "firebase", firebase: { app, auth: authSdk, db, storage } };
}

function friendlyAuthError(e) {
  const map = {
    "auth/invalid-credential": "Email or password is incorrect.",
    "auth/wrong-password": "Email or password is incorrect.",
    "auth/user-not-found": "No account found for that email.",
    "auth/email-already-in-use": "An account with this email already exists.",
    "auth/invalid-email": "That email address doesn't look right.",
    "auth/weak-password": "Password should be at least 6 characters.",
    "auth/too-many-requests": "Too many attempts. Please wait a minute and try again.",
    "auth/network-request-failed": "Network error. Check your connection and try again.",
    "auth/operation-not-allowed": "Email/password sign-in is not enabled in the Firebase console.",
    "auth/requires-recent-login": "Please enter your password again to continue.",
    "auth/missing-password": "Please enter your password.",
  };
  return new Error(map[e?.code] || e?.message || "Something went wrong.");
}
