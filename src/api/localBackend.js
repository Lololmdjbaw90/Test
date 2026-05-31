// Local, in-browser replacement for the Base44 SDK.
// -----------------------------------------------------------------------------
// This makes the app completely independent of Base44: there is no SDK, no app
// id, and no remote backend. Everything the app used to call on `base44` is
// reimplemented here against the browser's localStorage:
//
//   base44.entities.<Name>.{ list, filter, get, create, update, delete, subscribe, bulkCreate }
//   base44.auth.{ me, updateMe, login, logout, redirectToLogin }
//   base44.integrations.Core.{ UploadFile, InvokeLLM }
//
// Data persists in localStorage under the "mimilocks:" prefix and survives
// reloads. To wipe everything, clear site data for this origin (or run
// `localStorage.clear()` in the console).
//
// Notes / limitations of running fully local:
//  - Auth now supports real local accounts with email/password stored in this
//    browser. For true cross-device production auth, connect the same app shape
//    to Supabase/Firebase or your own API.
//  - File "uploads" are stored as data URLs inside the records (fine for small
//    images; very large files can exceed the localStorage quota).
//  - There is no AI offline, so `InvokeLLM` returns a safe, schema-shaped
//    placeholder (content-moderation calls therefore always pass).
// -----------------------------------------------------------------------------

import { moderate } from "../utils/profanity.js";

const PREFIX = "mimilocks";
const isBrowser = typeof window !== "undefined" && !!window.localStorage;
const memFallback = new Map(); // used only when there is no window (e.g. build)

// ---------- low-level storage ----------
function readRaw(key) {
  if (isBrowser) return window.localStorage.getItem(key);
  return memFallback.has(key) ? memFallback.get(key) : null;
}
function writeRaw(key, val) {
  if (isBrowser) {
    try { window.localStorage.setItem(key, val); }
    catch (e) { console.warn("[localBackend] localStorage write failed (quota?):", e); }
  } else {
    memFallback.set(key, val);
  }
}
function loadCollection(name) {
  const raw = readRaw(`${PREFIX}:${name}`);
  if (!raw) return [];
  try { const arr = JSON.parse(raw); return Array.isArray(arr) ? arr : []; }
  catch { return []; }
}
function saveCollection(name, arr) {
  writeRaw(`${PREFIX}:${name}`, JSON.stringify(arr));
}

// ---------- ids + timestamps ----------
function uid() {
  if (isBrowser && window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
  return "id_" + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
}
const nowISO = () => new Date().toISOString();
const normalizeEmail = (email) => String(email || "").trim().toLowerCase();
async function hashPassword(password, salt) {
  const input = `${salt}:${password}`;
  if (isBrowser && window.crypto?.subtle) {
    const data = new TextEncoder().encode(input);
    const hash = await window.crypto.subtle.digest("SHA-256", data);
    return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  // Build-time fallback only, not used in the browser.
  let h = 0;
  for (let i = 0; i < input.length; i++) h = Math.imul(31, h) + input.charCodeAt(i) | 0;
  return String(h);
}
function publicUser(user) {
  if (!user) return null;
  const { password_hash, password_salt, ...safe } = user;
  return safe;
}
function requireAuthSync() {
  const u = currentUserSync();
  if (!u) throw new Error("auth_required");
  return u;
}
function isAdminUser(user) { return user?.role === "admin"; }
function isOwner(user, record) {
  if (!user || !record) return false;
  const email = normalizeEmail(user.email);
  return [record.created_by, record.user_email, record.owner_email, record.artist_email, record.requester_email].some((v) => normalizeEmail(v) === email);
}
function canManageCommunity(user, communityId) {
  if (!user || !communityId) return false;
  if (isAdminUser(user)) return true;
  const comm = loadCollection("Community").find((c) => c.id === communityId);
  return normalizeEmail(comm?.owner_email) === normalizeEmail(user.email);
}
function canUpdateEntity(user, name, current, data = {}) {
  if (!user) return false;
  if (isAdminUser(user)) return true;
  if (name === "SiteConfig" || name === "Log" || name === "User") return false;
  if (["ServerChannel", "ServerRole", "ServerMember"].includes(name)) return canManageCommunity(user, current?.community_id || data.community_id);
  if (name === "Community") {
    const keys = Object.keys(data || {});
    if (keys.length === 1 && keys[0] === "member_emails") return true; // join/leave only
    return normalizeEmail(current?.owner_email) === normalizeEmail(user.email);
  }
  if (name === "ChannelMessage") {
    const keys = Object.keys(data || {});
    const publicActions = keys.every((k) => ["reactions", "thread_count"].includes(k));
    if (publicActions) return true;
    if (data.is_pinned !== undefined && canManageCommunity(user, current?.community_id)) return true;
    return normalizeEmail(current?.user_email) === normalizeEmail(user.email);
  }
  if (["Artwork", "CommunityPost", "MusicReview", "Comment", "CommunityComment", "Commission", "GroupChat", "DirectMessage", "ProfileMessage"].includes(name)) {
    const keys = Object.keys(data || {});
    if (keys.length === 1 && keys[0] === "likes") return true;
    return isOwner(user, current);
  }
  return true;
}
function canDeleteEntity(user, name, current) {
  if (!user) return false;
  if (isAdminUser(user)) return true;
  if (name === "SiteConfig" || name === "Log" || name === "User") return false;
  if (["ServerChannel", "ServerRole", "ServerMember"].includes(name)) return canManageCommunity(user, current?.community_id);
  if (name === "Community") return normalizeEmail(current?.owner_email) === normalizeEmail(user.email);
  if (name === "ChannelMessage") return normalizeEmail(current?.user_email) === normalizeEmail(user.email) || canManageCommunity(user, current?.community_id);
  return isOwner(user, current);
}

// ---------- pub/sub (per entity) + cross-tab bus ----------
const listeners = {}; // name -> Set<callback>
function emit(name, event) {
  const set = listeners[name];
  if (!set) return;
  set.forEach((cb) => { try { cb(event); } catch (e) { console.error("[localBackend] subscriber error:", e); } });
}
function subscribe(name, cb) {
  if (!listeners[name]) listeners[name] = new Set();
  listeners[name].add(cb);
  return () => { if (listeners[name]) listeners[name].delete(cb); };
}
const BUS_KEY = `${PREFIX}:__bus`;
function broadcast(name, event) {
  if (!isBrowser) return;
  // Writing a changing value triggers a `storage` event in OTHER tabs, which
  // lets multiple open tabs stay in sync (handy for testing the chat).
  try { writeRaw(BUS_KEY, JSON.stringify({ name, event, t: Date.now() + Math.random() })); } catch { /* ignore */ }
}
if (isBrowser) {
  window.addEventListener("storage", (e) => {
    if (e.key !== BUS_KEY || !e.newValue) return;
    try { const { name, event } = JSON.parse(e.newValue); emit(name, event); } catch { /* ignore */ }
  });
}

// ---------- query + sort helpers (mirrors Base44 filter/list semantics) ----------
function matches(record, query) {
  if (!query) return true;
  return Object.keys(query).every((k) => {
    const qv = query[k];
    const rv = record[k];
    if (Array.isArray(qv)) return JSON.stringify(qv) === JSON.stringify(rv);
    return rv === qv;
  });
}
function sortRecords(arr, sort) {
  if (!sort) return arr;
  const desc = sort.charAt(0) === "-";
  const field = desc ? sort.slice(1) : sort;
  const sorted = [...arr].sort((a, b) => {
    const av = a[field], bv = b[field];
    if (av == null && bv == null) return 0;
    if (av == null) return -1;
    if (bv == null) return 1;
    if (typeof av === "number" && typeof bv === "number") return av - bv;
    const as = String(av), bs = String(bv);
    return as < bs ? -1 : as > bs ? 1 : 0;
  });
  return desc ? sorted.reverse() : sorted;
}

// ---------- entity factory ----------
function makeEntity(name) {
  return {
    async list(sort, limit) {
      let arr = sortRecords(loadCollection(name), sort);
      if (limit != null) arr = arr.slice(0, limit);
      return arr;
    },
    async filter(query, sort, limit) {
      let arr = loadCollection(name).filter((r) => matches(r, query));
      arr = sortRecords(arr, sort);
      if (limit != null) arr = arr.slice(0, limit);
      return arr;
    },
    async get(id) {
      return loadCollection(name).find((r) => r.id === id) || null;
    },
    async create(data) {
      const arr = loadCollection(name);
      const me = requireAuthSync();
      if (name === "SiteConfig" && !isAdminUser(me)) throw new Error("permission_denied");
      if (["ServerChannel", "ServerRole", "ServerMember"].includes(name) && !canManageCommunity(me, data?.community_id)) throw new Error("permission_denied");
      const record = {
        id: uid(),
        created_date: nowISO(),
        updated_date: nowISO(),
        created_by: me ? me.email : null,
        ...data,
      };
      arr.push(record);
      saveCollection(name, arr);
      const ev = { type: "create", data: record };
      emit(name, ev); broadcast(name, ev);
      return record;
    },
    async update(id, data) {
      const arr = loadCollection(name);
      const i = arr.findIndex((r) => r.id === id);
      if (i === -1) return null;
      const me = requireAuthSync();
      if (!canUpdateEntity(me, name, arr[i], data)) throw new Error("permission_denied");
      arr[i] = { ...arr[i], ...data, updated_date: nowISO() };
      saveCollection(name, arr);
      const ev = { type: "update", data: arr[i] };
      emit(name, ev); broadcast(name, ev);
      return arr[i];
    },
    async delete(id) {
      const arr = loadCollection(name);
      const i = arr.findIndex((r) => r.id === id);
      let removed = null;
      const me = requireAuthSync();
      if (i !== -1 && !canDeleteEntity(me, name, arr[i])) throw new Error("permission_denied");
      if (i !== -1) { removed = arr[i]; arr.splice(i, 1); saveCollection(name, arr); }
      const ev = { type: "delete", id, data: removed };
      emit(name, ev); broadcast(name, ev);
      return { id, success: true };
    },
    async bulkCreate(items) {
      const arr = loadCollection(name);
      const me = requireAuthSync();
      const created = (items || []).map((data) => ({
        id: uid(), created_date: nowISO(), updated_date: nowISO(),
        created_by: me ? me.email : null, ...data,
      }));
      created.forEach((r) => arr.push(r));
      saveCollection(name, arr);
      created.forEach((record) => { const ev = { type: "create", data: record }; emit(name, ev); broadcast(name, ev); });
      return created;
    },
    subscribe(cb) { return subscribe(name, cb); },
  };
}

// The full set of entities the app uses.
const ENTITY_NAMES = [
  "Artwork", "ArtworkPing", "ChannelMessage", "Comment", "Commission", "Community",
  "CommunityComment", "CommunityPost", "DirectMessage", "Friendship", "GroupChat", "Log", "MusicReview",
  "Notification", "ServerChannel", "ServerMember", "ServerRole", "SiteConfig", "User",
];
const entities = {};
ENTITY_NAMES.forEach((n) => { entities[n] = makeEntity(n); });

// ---------- auth (real local accounts) ----------
const AUTH_KEY = `${PREFIX}:__auth_user`;
const ACCOUNTS_KEY = `${PREFIX}:__accounts`;
function currentUserSync() {
  const raw = readRaw(AUTH_KEY);
  if (raw) { try { return JSON.parse(raw); } catch { /* ignore */ } }
  return null;
}
function loadAccounts() {
  const raw = readRaw(ACCOUNTS_KEY);
  if (!raw) return [];
  try { const arr = JSON.parse(raw); return Array.isArray(arr) ? arr : []; }
  catch { return []; }
}
function saveAccounts(arr) { writeRaw(ACCOUNTS_KEY, JSON.stringify(arr)); }
function avatarFor(name) {
  return `https://ui-avatars.com/api/?name=${encodeURIComponent(name || "User")}&background=d4708a&color=fff&bold=true`;
}
async function ensureDefaultAdminAccount() {
  let accounts = loadAccounts();
  if (accounts.length > 0) return;
  const salt = uid();
  const admin = {
    id: uid(),
    email: "admin@mimilocks.local",
    full_name: "Mimi Admin",
    display_name: "Mimi Admin",
    role: "admin",
    password_salt: salt,
    password_hash: await hashPassword("admin123", salt),
    profile_picture: avatarFor("Mimi Admin"),
    bio: "Site owner account.",
    following: [],
    followers: [],
    xp: 0,
    coins: 0,
    nitro_until: null,
    onboarding_completed: true,
    theme: "light",
    last_seen: nowISO(),
    created_date: nowISO(),
    updated_date: nowISO(),
  };
  accounts = [admin];
  saveAccounts(accounts);
  const users = loadCollection("User");
  if (!users.find((x) => normalizeEmail(x.email) === normalizeEmail(admin.email))) users.push(publicUser(admin));
  saveCollection("User", users);
}
function syncUserRecord(account) {
  const safe = publicUser(account);
  const users = loadCollection("User");
  const i = users.findIndex((x) => normalizeEmail(x.email) === normalizeEmail(safe.email) || x.id === safe.id);
  if (i === -1) users.push(safe); else users[i] = { ...users[i], ...safe };
  saveCollection("User", users);
  return safe;
}
const auth = {
  async me() {
    await ensureDefaultAdminAccount();
    const u = currentUserSync();
    if (!u) throw new Error("auth_required");
    return publicUser(u);
  },
  async register({ email, password, display_name, full_name }) {
    await ensureDefaultAdminAccount();
    email = normalizeEmail(email);
    if (!email || !password || password.length < 6) throw new Error("Email and a 6+ character password are required.");
    const accounts = loadAccounts();
    if (accounts.find((x) => normalizeEmail(x.email) === email)) throw new Error("An account with this email already exists.");
    const name = (display_name || full_name || email.split("@")[0]).trim();
    const salt = uid();
    const account = {
      id: uid(), email, full_name: name, display_name: name, role: "user",
      password_salt: salt, password_hash: await hashPassword(password, salt),
      profile_picture: avatarFor(name), bio: "", following: [], followers: [], xp: 0, coins: 0,
      nitro_until: null, onboarding_completed: false, theme: "light", last_seen: nowISO(),
      created_date: nowISO(), updated_date: nowISO(),
    };
    accounts.push(account); saveAccounts(accounts); syncUserRecord(account);
    writeRaw(AUTH_KEY, JSON.stringify(account));
    return publicUser(account);
  },
  async login({ email, password } = {}) {
    await ensureDefaultAdminAccount();
    email = normalizeEmail(email);
    const account = loadAccounts().find((x) => normalizeEmail(x.email) === email);
    if (!account) throw new Error("No account found for that email.");
    const expected = await hashPassword(password || "", account.password_salt);
    if (expected !== account.password_hash) throw new Error("Wrong password.");
    const next = { ...account, last_seen: nowISO() };
    const accounts = loadAccounts().map((x) => normalizeEmail(x.email) === email ? next : x);
    saveAccounts(accounts); syncUserRecord(next); writeRaw(AUTH_KEY, JSON.stringify(next));
    return publicUser(next);
  },
  async updateMe(data) {
    const current = requireAuthSync();
    const safeData = { ...data };
    delete safeData.role; delete safeData.email; delete safeData.password_hash; delete safeData.password_salt;
    const updated = { ...current, ...safeData, updated_date: nowISO() };
    writeRaw(AUTH_KEY, JSON.stringify(updated));
    saveAccounts(loadAccounts().map((x) => x.id === updated.id ? { ...x, ...updated } : x));
    return syncUserRecord(updated);
  },
  logout() {
    if (isBrowser) { window.localStorage.removeItem(AUTH_KEY); window.location.href = "/Login"; }
  },
  redirectToLogin() { if (isBrowser) window.location.href = "/Login"; },
  async isAdmin() { const u = await this.me(); return u.role === "admin"; },
};

// ---------- integrations.Core ----------
function fileToDataUrl(file) {
  return new Promise((resolve, reject) => {
    try {
      const fr = new FileReader();
      fr.onload = () => resolve(fr.result);
      fr.onerror = reject;
      fr.readAsDataURL(file);
    } catch (e) { reject(e); }
  });
}
function schemaDefaults(schema) {
  const out = {};
  const props = (schema && schema.properties) || {};
  Object.keys(props).forEach((key) => {
    const t = props[key] && props[key].type;
    if (t === "boolean") out[key] = true;            // e.g. moderation "safe" -> allow
    else if (t === "number" || t === "integer") out[key] = 0;
    else if (t === "array") out[key] = [];
    else if (t === "object") out[key] = {};
    else out[key] = "";
  });
  return out;
}
const integrations = {
  Core: {
    async UploadFile(args) {
      const file = args && args.file;
      if (!file) return { file_url: "" };
      const dataUrl = await fileToDataUrl(file);
      return { file_url: dataUrl };
    },
    async InvokeLLM(args) {
      const schema = args && args.response_json_schema;
      const prompt = (args && args.prompt) || "";
      // The app uses InvokeLLM only for content moderation (schema with a
      // boolean "safe"). Run the local bad-word flagger over the prompt (which
      // embeds the user's text) and return a real verdict.
      if (schema && schema.properties && schema.properties.safe) {
        return moderate(prompt);
      }
      if (schema) return schemaDefaults(schema);
      return ""; // offline: no text generation
    },
  },
};

// ---------- one-time demo seed ----------
function seedIfEmpty() {
  if (!isBrowser) return;
  if (readRaw(`${PREFIX}:__seeded`)) return;
  try {
    const accounts = loadAccounts();
    const me = publicUser(accounts.find(a => a.role === "admin") || accounts[0]);
    const ago = (m) => new Date(Date.now() - m * 60000).toISOString();
    const av = (name, bg) => `https://ui-avatars.com/api/?name=${encodeURIComponent(name)}&background=${bg}&color=fff&bold=true`;
    const pic = (seed, w, h) => `https://picsum.photos/seed/${seed}/${w || 640}/${h || 480}`;

    // --- demo users ---
    const demo = [
      { email: "aria@mimilocks.local", display_name: "Aria", full_name: "Aria Ven", role: "user", profile_picture: av("Aria", "e8a0b4"), bio: "Watercolor & ink.", xp: 1240, coins: 320 },
      { email: "kai@mimilocks.local", display_name: "Kai", full_name: "Kai Mori", role: "user", profile_picture: av("Kai", "7aa2f7"), bio: "3D + neon.", xp: 860, coins: 140 },
      { email: "luna@mimilocks.local", display_name: "Luna", full_name: "Luna Sol", role: "user", profile_picture: av("Luna", "b794f6"), bio: "Dreamy landscapes.", xp: 2010, coins: 540 },
      { email: "max@mimilocks.local", display_name: "Max", full_name: "Max Lo", role: "user", profile_picture: av("Max", "68d391"), bio: "Lo-fi beats.", xp: 430, coins: 60 },
    ].map((u) => ({ id: uid(), created_date: ago(60 * 24 * 14), updated_date: nowISO(), created_by: u.email, following: [], followers: [], nitro_until: null, onboarding_completed: true, theme: "light", ...u }));
    const users = loadCollection("User");
    demo.forEach((u) => { if (!users.find((x) => x.email === u.email)) users.push(u); });
    saveCollection("User", users);

    const E = { you: me.email, aria: "aria@mimilocks.local", kai: "kai@mimilocks.local", luna: "luna@mimilocks.local", max: "max@mimilocks.local" };
    const N = { [E.you]: me.display_name || "You", [E.aria]: "Aria", [E.kai]: "Kai", [E.luna]: "Luna", [E.max]: "Max" };
    const P = {}; demo.forEach((u) => { P[u.email] = u.profile_picture; }); P[E.you] = me.profile_picture || "";

    // --- communities ---
    const c1 = uid(), c2 = uid();
    saveCollection("Community", [
      { id: c1, created_date: ago(60 * 24 * 10), updated_date: nowISO(), created_by: E.you, name: "Mimi Locks", description: "The main hangout \u2014 art, music & good vibes.", icon_emoji: "\u{1F338}", icon_url: "", banner_url: pic("mimibanner", 1200, 300), owner_email: E.you, owner_display_name: N[E.you], member_emails: [E.you, E.aria, E.kai, E.luna, E.max], welcome_message: "Welcome to Mimi Locks \u{1F338} introduce yourself in #general!" },
      { id: c2, created_date: ago(60 * 24 * 6), updated_date: nowISO(), created_by: E.aria, name: "Pixel Pals", description: "Pixel art & game-dev corner.", icon_emoji: "\u{1F3AE}", icon_url: "", banner_url: pic("pixelbanner", 1200, 300), owner_email: E.aria, owner_display_name: "Aria", member_emails: [E.aria, E.you, E.kai], welcome_message: "gm pixel pals \u{1F3AE}" },
    ]);

    // --- roles ---
    const rOwner = uid(), rArtist = uid(), rMember = uid(), r2Member = uid();
    saveCollection("ServerRole", [
      { id: rOwner, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "Owner", color: "#d4708a", permissions: ["manage"], position: 0 },
      { id: rArtist, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "Artist", color: "#e8a0b4", permissions: [], position: 1 },
      { id: rMember, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "Member", color: "#9ca3af", permissions: [], position: 2 },
      { id: r2Member, created_date: ago(1000), updated_date: nowISO(), created_by: E.aria, community_id: c2, name: "Member", color: "#a78bfa", permissions: [], position: 0 },
    ]);

    // --- channels (text + voice) ---
    const gen = uid(), show = uid(), off = uid(), v1 = uid(), v2 = uid(), c2gen = uid(), c2v = uid();
    saveCollection("ServerChannel", [
      { id: gen, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "general", type: "text", description: "Main chat", position: 0, allowed_roles: [] },
      { id: show, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "showcase", type: "text", description: "Share your work", position: 1, allowed_roles: [] },
      { id: off, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "off-topic", type: "text", description: "Anything goes", position: 2, allowed_roles: [] },
      { id: v1, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "General Voice", type: "voice", description: "Hop in and chat", position: 3, allowed_roles: [] },
      { id: v2, created_date: ago(1000), updated_date: nowISO(), created_by: E.you, community_id: c1, name: "Music Lounge", type: "voice", description: "Listen together", position: 4, allowed_roles: [] },
      { id: c2gen, created_date: ago(1000), updated_date: nowISO(), created_by: E.aria, community_id: c2, name: "general", type: "text", description: "", position: 0, allowed_roles: [] },
      { id: c2v, created_date: ago(1000), updated_date: nowISO(), created_by: E.aria, community_id: c2, name: "Hangout", type: "voice", description: "", position: 1, allowed_roles: [] },
    ]);

    // --- members ---
    const member = (cid, email, roles) => ({ id: uid(), created_date: ago(1000), updated_date: nowISO(), created_by: email, community_id: cid, user_email: email, user_display_name: N[email], user_profile_picture: P[email] || "", roles, nickname: "" });
    saveCollection("ServerMember", [
      member(c1, E.you, [rOwner]), member(c1, E.aria, [rArtist]), member(c1, E.kai, [rArtist]), member(c1, E.luna, [rMember]), member(c1, E.max, [rMember]),
      member(c2, E.aria, [r2Member]), member(c2, E.you, [r2Member]), member(c2, E.kai, [r2Member]),
    ]);

    // --- channel messages ---
    const msg = (cid, chid, email, content, mins, extra) => Object.assign({ id: uid(), created_date: ago(mins), updated_date: ago(mins), created_by: email, channel_id: chid, community_id: cid, content, image_url: "", user_email: email, user_display_name: N[email], user_profile_picture: P[email] || "", reply_to_id: "", reply_to_preview: "", reactions: {}, is_pinned: false, is_edited: false }, extra || {});
    saveCollection("ChannelMessage", [
      msg(c1, gen, E.aria, "hey everyone! welcome to Mimi Locks \u{1F338}", 240, { is_pinned: true }),
      msg(c1, gen, E.kai, "this place looks so clean \u2728", 180),
      msg(c1, gen, E.luna, "just posted a new piece in #showcase \u{1F440}", 90, { reactions: { "\u2764\uFE0F": [E.aria, E.kai] } }),
      msg(c1, gen, E.max, "lofi set later in Music Lounge?", 35),
      msg(c1, gen, E.you, "let's goooo \u{1F525}", 6),
      msg(c1, show, E.luna, "Wildflower \u2014 watercolor, finished today", 88, { image_url: pic("art-luna", 800, 600) }),
    ]);

    // --- artworks ---
    const art = (title, desc, medium, email, seed, likes, featured) => ({ id: uid(), created_date: ago(Math.floor(Math.random() * 6000) + 60), updated_date: nowISO(), created_by: email, title, description: desc, medium, year: "2024", featured: !!featured, image_url: pic(seed, 640, 480), music_url: "", likes: likes || [], user_email: email, user_display_name: N[email], user_profile_picture: P[email] || "" });
    saveCollection("Artwork", [
      art("Sunset Koi", "Koi under a warm sky.", "watercolor", E.aria, "koi", [E.you, E.kai, E.luna], true),
      art("Neon Alley", "Late-night rain in the city.", "digital", E.kai, "neon", [E.aria, E.you]),
      art("Quiet Morning", "Coffee and soft light.", "oil", E.luna, "morning", [E.max]),
      art("Wildflower", "Field study.", "watercolor", E.luna, "flower", [E.you, E.aria]),
      art("City Rain", "Umbrellas and reflections.", "ink", E.kai, "rain", []),
      art("Dreamscape", "Between sleep and waking.", "digital", E.aria, "dream", [E.you]),
    ]);

    // --- community posts ---
    const post = (email, title, desc, seed, likes, mins) => ({ id: uid(), created_date: ago(mins), updated_date: nowISO(), created_by: email, title, description: desc, image_url: seed ? pic(seed, 720, 480) : "", user_email: email, user_display_name: N[email], user_profile_picture: P[email] || "", likes: likes || [] });
    saveCollection("CommunityPost", [
      post(E.max, "New mix dropping", "Working on a chill lo-fi set for the Music Lounge tonight \u{1F3A7}", "post-mix", [E.you, E.luna], 120),
      post(E.aria, "WIP", "Sketching some koi studies, thoughts?", "post-koi", [E.kai], 300),
      post(E.luna, "Finished!", "So happy with how Wildflower turned out \u{1F33C}", "post-flower", [E.you, E.aria, E.kai], 600),
      post(E.you, "Hello Mimi Locks", "Excited to be here \u2014 let's make cool stuff \u2728", "", [E.aria, E.luna], 30),
    ]);

    // --- music reviews ---
    const review = (email, title, genre, mood, text, likes, mins) => ({ id: uid(), created_date: ago(mins), updated_date: nowISO(), created_by: email, title, music_url: "", genre, mood, ai_review: text, identified_song: "", user_email: email, user_display_name: N[email], likes: likes || [] });
    saveCollection("MusicReview", [
      review(E.max, "Midnight Tape", "Lo-fi", "Chill", "Warm, dusty keys over a lazy beat \u2014 perfect background music.", [E.you, E.aria], 200),
      review(E.kai, "Neon Drive", "Synthwave", "Energetic", "Pulsing arps and big drums; very 80s in the best way.", [E.luna], 800),
      review(E.aria, "Rainy Window", "Ambient", "Calm", "Soft pads and field recordings; great for focus.", [], 1500),
    ]);

    // --- commissions ---
    const comm = (email, title, desc, tiers, mins) => ({ id: uid(), created_date: ago(mins), updated_date: nowISO(), created_by: email, title, description: desc, artist_email: email, artist_display_name: N[email], artist_profile_picture: P[email] || "", tiers, samples: [pic("samp-" + email.split("@")[0], 400, 400)], tags: [], status: "open" });
    saveCollection("Commission", [
      comm(E.aria, "Watercolor Portraits", "Soft, hand-painted portraits from your photo.", [{ name: "Bust", price: 25, description: "Head & shoulders" }, { name: "Half Body", price: 45, description: "Waist up" }], 400),
      comm(E.kai, "Neon Character Art", "Stylised digital character with neon lighting.", [{ name: "Sketch", price: 20, description: "Lineart" }, { name: "Full Color", price: 60, description: "Rendered + background" }], 900),
    ]);

    // --- friendships ---
    const fr = (reqEmail, recEmail, status, mins) => ({ id: uid(), created_date: ago(mins), updated_date: nowISO(), created_by: reqEmail, requester_email: reqEmail, requester_display_name: N[reqEmail], requester_profile_picture: P[reqEmail] || "", requester_profile_emoji: "", receiver_email: recEmail, receiver_display_name: N[recEmail], receiver_profile_picture: P[recEmail] || "", receiver_profile_emoji: "", status });
    saveCollection("Friendship", [
      fr(E.aria, E.you, "accepted", 5000),
      fr(E.kai, E.you, "pending", 40),
      fr(E.you, E.luna, "pending", 100),
    ]);

    // --- notifications (for you) ---
    const notif = (fromEmail, type, message, read, mins) => ({ id: uid(), created_date: ago(mins), updated_date: nowISO(), created_by: fromEmail, to_email: E.you, from_email: fromEmail, from_display_name: N[fromEmail], from_profile_picture: P[fromEmail] || "", type, message, link: "", entity_id: "", is_read: !!read });
    saveCollection("Notification", [
      notif(E.aria, "like", "liked your artwork", false, 20),
      notif(E.kai, "friend_request", "sent you a friend request", false, 40),
      notif(E.luna, "comment", "commented on your post", true, 200),
    ]);

    writeRaw(`${PREFIX}:__seeded`, "1");
  } catch (e) {
    console.warn("[localBackend] seed skipped:", e);
  }
}

export function createLocalClient() {
  if (isBrowser) { ensureDefaultAdminAccount().then(seedIfEmpty).catch((e) => console.warn("[localBackend] init skipped:", e)); }
  return { entities, auth, integrations };
}
