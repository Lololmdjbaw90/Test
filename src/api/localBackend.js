// Local, in-browser backend.
// -----------------------------------------------------------------------------
// Implements the same `base44` API as the Firebase backend against the
// browser's localStorage, so the whole site runs with zero setup:
//
//   base44.entities.<Name>.{ list, filter, get, create, update, delete, subscribe, bulkCreate }
//   base44.auth.{ me, register, login, logout, updateMe, resetPassword, redirectToLogin }
//   base44.integrations.Core.{ UploadFile, InvokeLLM }
//
// Permission checks mirror firestore.rules so behaviour is the same in both
// modes. Data persists under the "mimilocks:" prefix; realtime events are
// shared between open tabs through the `storage` event.
//
// Limitations of running fully local:
//  - accounts only exist in this browser (use Firebase for real multi-user)
//  - uploads are stored as data URLs (very large files can hit the quota)
//  - InvokeLLM only supports moderation, answered by the local word filter
// -----------------------------------------------------------------------------

import { moderate } from "../utils/profanity.js";
import { isSiteOwner } from "../lib/admin.js";
import { matchesQuery, sortAndLimit } from "./queryUtils.js";

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
    catch (e) {
      console.warn("[localBackend] localStorage write failed (quota?):", e);
      throw new Error("Browser storage is full. Try a smaller image or clear old data in Settings.");
    }
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

// ---------- permissions (mirror firestore.rules) ----------
const same = (a, b) => normalizeEmail(a) === normalizeEmail(b) && !!normalizeEmail(a);
const isAdminUser = (user) => user?.role === "admin" || isSiteOwner(user?.email);
const withOwnerRole = (user) => (user && isSiteOwner(user.email) ? { ...user, role: "admin" } : user);
function isOwner(user, record) {
  if (!user || !record) return false;
  return [record.created_by, record.user_email, record.owner_email, record.artist_email, record.requester_email].some((v) => same(v, user.email));
}
function onlyChanged(data, allowed) {
  return Object.keys(data || {}).every((k) => allowed.includes(k) || k === "updated_date");
}
// Server role permissions, computed straight from the roles (see src/lib/permissions.js).
const LEGACY_PERMS = { can_pin_messages: "pin_messages", can_manage_messages: "manage_messages" };
function hasServerPerm(user, communityId, perm) {
  if (!user || !communityId) return false;
  if (isAdminUser(user)) return true;
  const comm = loadCollection("Community").find((c) => c.id === communityId);
  if (!comm) return false;
  if (same(comm.owner_email, user.email)) return true;
  if (!(comm.member_emails || []).some((e) => same(e, user.email))) return false;
  const member = loadCollection("ServerMember").find((m) => m.community_id === communityId && same(m.user_email, user.email));
  const roles = loadCollection("ServerRole").filter((r) => r.community_id === communityId && (member?.roles || []).includes(r.id));
  return roles.some((r) => Object.entries(r.permissions || {}).some(([k, v]) => v && [perm, "administrator"].includes(LEGACY_PERMS[k] || k)));
}
function isServerMember(user, communityId) {
  if (isAdminUser(user)) return true;
  const comm = loadCollection("Community").find((c) => c.id === communityId);
  return !!comm && (comm.member_emails || []).some((e) => same(e, user.email));
}
function communityUpdateAllowed(user, current, data) {
  const email = user.email;
  if (same(current?.owner_email, email)) return true;
  const fields = (list) => onlyChanged(data, list);
  if (fields(["member_emails"]) && Array.isArray(data.member_emails)) {
    const before = new Set(current.member_emails || []);
    const after = new Set(data.member_emails);
    const added = [...after].filter((e) => !before.has(e));
    const removed = [...before].filter((e) => !after.has(e));
    if ([...added, ...removed].every((e) => same(e, email))) return true; // join / leave yourself
    if (added.length === 0 && !removed.some((e) => same(e, current.owner_email)) && hasServerPerm(user, current.id, "kick_members")) return true;
  }
  if (fields(["name", "description", "icon_emoji", "icon_url", "banner_url", "welcome_message"]) && hasServerPerm(user, current.id, "manage_server")) return true;
  if (fields(["perm_index", "everyone_permissions"]) && hasServerPerm(user, current.id, "manage_roles")) return true;
  return false;
}
const LIKEABLE = ["Artwork", "CommunityPost", "MusicReview", "Reel", "Comment", "CommunityComment"];

// Comments on reels have post_id "reel_<id>".
function reelOfComment(c) {
  const id = String(c?.post_id || "");
  return id.startsWith("reel_") ? loadCollection("Reel").find((r) => r.id === id.slice(5)) : null;
}
function canCreate(user, name, data) {
  if (!user) return false;
  if (isAdminUser(user)) return true;
  if (name === "SiteConfig" || name === "Log" || name === "User" || name === "AppUpdate") return false;
  if (name === "Reel") return same(data?.user_email, user.email);
  if (name === "CommunityComment" && reelOfComment(data)?.comments_off) return false;
  if (name === "ServerChannel") return hasServerPerm(user, data?.community_id, "manage_channels");
  if (name === "ServerRole") return hasServerPerm(user, data?.community_id, "manage_roles");
  if (name === "ServerMember") return hasServerPerm(user, data?.community_id, "manage_roles") || (same(data?.user_email, user.email) && !(data?.roles || []).length);
  if (name === "ChannelMessage") return same(data?.user_email, user.email) && isServerMember(user, data?.community_id);
  if (name === "DirectMessage") return (data?.member_emails || []).includes(user.email) && same(data?.user_email, user.email);
  if (name === "GroupChat") return (data?.member_emails || []).includes(user.email);
  if (name === "VoicePresence" || name === "VoiceSignal") return same(data?.user_email, user.email);
  if (name === "Call") return same(data?.caller_email, user.email) && (data?.member_emails || []).includes(user.email);
  if (name === "Report") return same(data?.reporter_email, user.email);
  return true;
}
function canUpdate(user, name, current, data = {}) {
  if (!user) return false;
  // Only site owners change who is an admin, or edit an owner's profile.
  if (name === "User" && !isSiteOwner(user.email) && (isSiteOwner(current?.email) || ("role" in data && (data.role || "user") !== (current?.role || "user")))) return false;
  if (isAdminUser(user)) return true;
  const email = user.email;
  switch (name) {
    case "SiteConfig": case "Log": case "User": case "AppUpdate": return false;
    case "ServerChannel": return hasServerPerm(user, current?.community_id, "manage_channels");
    case "ServerRole": return hasServerPerm(user, current?.community_id, "manage_roles");
    case "ServerMember":
      return hasServerPerm(user, current?.community_id, "manage_roles") ||
        (same(current?.user_email, email) && onlyChanged(data, ["nickname", "user_display_name", "user_profile_picture"]));
    case "Community": return communityUpdateAllowed(user, current, data);
    case "ChannelMessage":
      return (same(current?.user_email, email) && !("is_pinned" in (data || {})))
        || hasServerPerm(user, current?.community_id, "manage_messages")
        || (onlyChanged(data, ["is_pinned"]) && hasServerPerm(user, current?.community_id, "pin_messages"))
        || onlyChanged(data, ["reactions", "thread_count"]);
    case "DirectMessage":
      return (same(current?.user_email, email) && onlyChanged(data, ["content", "is_edited", "read_by", "reactions"])) ||
        ((current?.member_emails || []).includes(email) && onlyChanged(data, ["read_by", "reactions"]));
    case "Friendship": return same(current?.requester_email, email) || same(current?.receiver_email, email);
    case "GroupChat":
      return same(current?.owner_email, email) ||
        ((current?.member_emails || []).includes(email) && onlyChanged(data, ["member_emails", "member_display_names"]) && !(data.member_emails || []).includes(email));
    case "Notification": return same(current?.to_email, email);
    case "ArtworkPing": return same(current?.from_email, email) || same(current?.to_email, email);
    case "Call":
      return same(current?.caller_email, email) ||
        ((current?.member_emails || []).includes(email) && onlyChanged(data, ["status", "declined_by", "joined_emails", "answered_at", "ended_at"]));
    default:
      if (LIKEABLE.includes(name) && onlyChanged(data, ["likes"])) return true;
      if (name === "MusicReview" && onlyChanged(data, ["plays"]) && data.plays === (current?.plays || 0) + 1) return true;
      if (name === "Reel" && onlyChanged(data, ["views"]) && data.views === (current?.views || 0) + 1) return true;
      return isOwner(user, current);
  }
}
function canDelete(user, name, current) {
  if (!user) return false;
  if (name === "User" && isSiteOwner(current?.email) && !same(current?.email, user.email)) return false;
  if (isAdminUser(user)) return true;
  const email = user.email;
  switch (name) {
    case "SiteConfig": case "Log": case "User": case "AppUpdate": return false;
    case "ServerChannel": return hasServerPerm(user, current?.community_id, "manage_channels");
    case "ServerRole": return hasServerPerm(user, current?.community_id, "manage_roles");
    case "ServerMember": return same(current?.user_email, email) || hasServerPerm(user, current?.community_id, "kick_members") || hasServerPerm(user, current?.community_id, "manage_roles");
    case "Community": return same(current?.owner_email, email);
    case "ChannelMessage": return same(current?.user_email, email) || hasServerPerm(user, current?.community_id, "manage_messages");
    case "DirectMessage": return same(current?.user_email, email);
    case "Friendship": return same(current?.requester_email, email) || same(current?.receiver_email, email);
    case "GroupChat": return same(current?.owner_email, email);
    case "Notification": return same(current?.to_email, email);
    case "ArtworkPing": return same(current?.from_email, email) || same(current?.to_email, email);
    case "CommunityComment": return isOwner(user, current) || current?.post_id === `profile_${email}` || same(reelOfComment(current)?.user_email, email);
    case "VoicePresence": return isOwner(user, current) || (current?.last_active || 0) < Date.now() - 60000;
    case "VoiceSignal": return isOwner(user, current) || same(current?.to_email, email);
    case "Call": return same(current?.caller_email, email);
    default: return isOwner(user, current);
  }
}

// ---------- pub/sub (per entity) + cross-tab bus ----------
const listeners = {}; // name -> Set<callback>
function emit(name, event) {
  const set = listeners[name];
  if (!set) return;
  set.forEach((cb) => { try { cb(event); } catch (e) { console.error("[localBackend] subscriber error:", e); } });
}
const BUS_KEY = `${PREFIX}:__bus`;
function broadcast(name, event) {
  if (!isBrowser) return;
  // Writing a changing value fires a `storage` event in OTHER tabs.
  try { window.localStorage.setItem(BUS_KEY, JSON.stringify({ name, event, t: Date.now() + Math.random() })); } catch { /* ignore */ }
}
if (isBrowser) {
  window.addEventListener("storage", (e) => {
    if (e.key !== BUS_KEY || !e.newValue) return;
    try { const { name, event } = JSON.parse(e.newValue); emit(name, event); } catch { /* ignore */ }
  });
}
function publish(name, event) { emit(name, event); broadcast(name, event); }

// ---------- entity factory ----------
function makeEntity(name) {
  return {
    async list(sort, limit) {
      return sortAndLimit(loadCollection(name), sort, limit);
    },
    async filter(query, sort, limit) {
      return sortAndLimit(loadCollection(name).filter((r) => matchesQuery(r, query)), sort, limit);
    },
    async get(id) {
      return loadCollection(name).find((r) => r.id === id) || null;
    },
    async create(data) {
      const me = requireAuthSync();
      if (!canCreate(me, name, data)) throw new Error("permission_denied");
      const arr = loadCollection(name);
      const record = { id: uid(), created_date: nowISO(), updated_date: nowISO(), created_by: me.email, ...data };
      arr.push(record);
      saveCollection(name, arr);
      publish(name, { type: "create", id: record.id, data: record });
      return record;
    },
    async update(id, data) {
      const arr = loadCollection(name);
      const i = arr.findIndex((r) => r.id === id);
      if (i === -1) return null;
      const me = requireAuthSync();
      if (!canUpdate(me, name, arr[i], data)) throw new Error("permission_denied");
      arr[i] = { ...arr[i], ...data, updated_date: nowISO() };
      saveCollection(name, arr);
      publish(name, { type: "update", id, data: arr[i] });
      return arr[i];
    },
    async delete(id) {
      const arr = loadCollection(name);
      const i = arr.findIndex((r) => r.id === id);
      const me = requireAuthSync();
      if (i === -1) return { id, success: true };
      if (!canDelete(me, name, arr[i])) throw new Error("permission_denied");
      const [removed] = arr.splice(i, 1);
      saveCollection(name, arr);
      publish(name, { type: "delete", id, data: removed });
      return { id, success: true };
    },
    async bulkCreate(items) {
      const created = [];
      for (const item of items || []) created.push(await this.create(item));
      return created;
    },
    // callback({ type: "create" | "update" | "delete", id, data })
    subscribe(callback, query = null) {
      if (!listeners[name]) listeners[name] = new Set();
      const handler = (event) => { if (!query || matchesQuery(event.data, query)) callback(event); };
      listeners[name].add(handler);
      return () => listeners[name]?.delete(handler);
    },
  };
}

export const ENTITY_NAMES = [
  "Artwork", "ArtworkPing", "ChannelMessage", "Comment", "Commission", "Community",
  "CommunityComment", "CommunityPost", "DirectMessage", "Friendship", "GroupChat", "Log", "MusicReview",
  "Notification", "ServerChannel", "ServerMember", "ServerRole", "SiteConfig", "User",
  "VoicePresence", "VoiceSignal", "Call", "Report", "Reel", "AppUpdate",
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
function newProfile(fields) {
  return {
    bio: "", following: [], xp: 0, coins: 0, nitro_until: null, nitro_active: false,
    onboarding_completed: false, theme: "light", accent: "rose", saved_artworks: [],
    last_seen: nowISO(), created_date: nowISO(), updated_date: nowISO(),
    ...fields,
  };
}
let adminReady = null;
function ensureDefaultAdminAccount() {
  if (!adminReady) {
    adminReady = (async () => {
      if (loadAccounts().length > 0) return;
      const salt = uid();
      const admin = newProfile({
        id: uid(), email: "admin@mimilocks.local", full_name: "Mimi Admin", display_name: "Mimi Admin", role: "admin",
        password_salt: salt, password_hash: await hashPassword("admin123", salt),
        profile_picture: "", bio: "Site owner account.", onboarding_completed: true,
        xp: 1800, coins: 250,
      });
      saveAccounts([admin]);
      syncUserRecord(admin);
    })();
  }
  return adminReady;
}
function syncUserRecord(account) {
  const safe = publicUser(account);
  const users = loadCollection("User");
  const i = users.findIndex((x) => same(x.email, safe.email) || x.id === safe.id);
  // Keep the shared record's role: admins change it there (Admin panel).
  if (i === -1) users.push(safe); else { const { role, ...rest } = safe; users[i] = { ...users[i], ...rest }; }
  saveCollection("User", users);
  const record = i === -1 ? safe : users[i];
  publish("User", { type: i === -1 ? "create" : "update", id: record.id, data: record });
  return withOwnerRole(record);
}
const auth = {
  async me() {
    await ensureDefaultAdminAccount();
    const u = currentUserSync();
    if (!u) throw new Error("auth_required");
    // Prefer the shared User record so admin edits (e.g. role changes) apply.
    const record = loadCollection("User").find((x) => x.id === u.id);
    return withOwnerRole(publicUser({ ...u, ...(record || {}) }));
  },
  async register({ email, password, display_name, full_name }) {
    await ensureDefaultAdminAccount();
    email = normalizeEmail(email);
    if (!email || !password || password.length < 6) throw new Error("Email and a 6+ character password are required.");
    const accounts = loadAccounts();
    if (accounts.find((x) => same(x.email, email))) throw new Error("An account with this email already exists.");
    const name = (display_name || full_name || email.split("@")[0]).trim();
    const salt = uid();
    const account = newProfile({
      id: uid(), email, full_name: name, display_name: name, role: isSiteOwner(email) ? "admin" : "user",
      password_salt: salt, password_hash: await hashPassword(password, salt), profile_picture: "",
    });
    accounts.push(account); saveAccounts(accounts); syncUserRecord(account);
    writeRaw(AUTH_KEY, JSON.stringify(publicUser(account)));
    return withOwnerRole(publicUser(account));
  },
  async login({ email, password } = {}) {
    await ensureDefaultAdminAccount();
    email = normalizeEmail(email);
    const account = loadAccounts().find((x) => same(x.email, email));
    if (!account) throw new Error("No account found for that email.");
    const expected = await hashPassword(password || "", account.password_salt);
    if (expected !== account.password_hash) throw new Error("Wrong password.");
    const next = { ...account, last_seen: nowISO() };
    saveAccounts(loadAccounts().map((x) => same(x.email, email) ? next : x));
    syncUserRecord(next);
    writeRaw(AUTH_KEY, JSON.stringify(publicUser(next)));
    return withOwnerRole(publicUser(next));
  },
  async updateMe(data) {
    const current = requireAuthSync();
    const safeData = { ...data };
    ["role", "email", "id", "password_hash", "password_salt"].forEach((k) => delete safeData[k]);
    const updated = { ...current, ...safeData, updated_date: nowISO() };
    writeRaw(AUTH_KEY, JSON.stringify(publicUser(updated)));
    saveAccounts(loadAccounts().map((x) => x.id === updated.id ? { ...x, ...safeData, updated_date: updated.updated_date } : x));
    return syncUserRecord(updated);
  },
  async resetPassword() {
    throw new Error("Password reset emails need Firebase. In local demo mode, create a new account instead.");
  },
  async verifyPassword(password) {
    const current = requireAuthSync();
    const account = loadAccounts().find((x) => same(x.email, current.email));
    if (!account) throw new Error("Account not found.");
    const expected = await hashPassword(password || "", account.password_salt);
    if (expected !== account.password_hash) throw new Error("Wrong password.");
  },
  async deleteAccount() {
    const current = requireAuthSync();
    saveAccounts(loadAccounts().filter((x) => !same(x.email, current.email)));
    saveCollection("User", loadCollection("User").filter((u) => !same(u.email, current.email)));
    if (isBrowser) { window.localStorage.removeItem(AUTH_KEY); window.location.href = "/Login"; }
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
    if (t === "boolean") out[key] = true;
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
      // Videos and big files go to IndexedDB (localStorage only holds a few MB).
      if (typeof indexedDB !== "undefined" && (String(file.type || "").startsWith("video/") || file.size > 1.5 * 1024 * 1024)) {
        const { putLocalMedia } = await import("../lib/media.js");
        return { file_url: await putLocalMedia(file) };
      }
      return { file_url: await fileToDataUrl(file) };
    },
    async InvokeLLM(args) {
      const schema = args && args.response_json_schema;
      const prompt = (args && args.prompt) || "";
      if (schema && schema.properties && schema.properties.safe) return moderate(prompt);
      if (schema) return schemaDefaults(schema);
      return "";
    },
  },
};

// ---------- one-time demo seed ----------
function seedIfEmpty() {
  if (!isBrowser) return;
  if (readRaw(`${PREFIX}:__seeded`)) return;
  try {
    const accounts = loadAccounts();
    const me = publicUser(accounts.find((a) => a.role === "admin") || accounts[0]);
    const ago = (m) => new Date(Date.now() - m * 60000).toISOString();
    const pic = (seed, w, h) => `https://picsum.photos/seed/${seed}/${w || 640}/${h || 480}`;
    const base = (email, mins) => ({ id: uid(), created_date: ago(mins), updated_date: ago(mins), created_by: email });

    // --- demo users ---
    const demo = [
      { email: "aria@mimilocks.local", display_name: "Aria", full_name: "Aria Ven", bio: "Watercolor & ink. Koi enthusiast.", xp: 1240, coins: 320, profile_picture: "", name_style: "glow-pink" },
      { email: "kai@mimilocks.local", display_name: "Kai", full_name: "Kai Mori", bio: "3D + neon. Night owl.", xp: 860, coins: 140, profile_picture: "" },
      { email: "luna@mimilocks.local", display_name: "Luna", full_name: "Luna Sol", bio: "Dreamy landscapes and soft light.", xp: 3120, coins: 540, profile_picture: "", nitro_active: true, nitro_until: ago(-60 * 24 * 20), name_style: "aurora" },
      { email: "max@mimilocks.local", display_name: "Max", full_name: "Max Lo", bio: "Lo-fi beats for drawing sessions.", xp: 430, coins: 60, profile_picture: "" },
    ].map((u, i) => newProfile({ ...base(u.email, 60 * 24 * (14 - i)), role: "user", onboarding_completed: true, last_seen: ago(i * 3), ...u }));
    const users = loadCollection("User");
    demo.forEach((u) => { if (!users.find((x) => x.email === u.email)) users.push(u); });
    saveCollection("User", users);

    const E = { you: me.email, aria: demo[0].email, kai: demo[1].email, luna: demo[2].email, max: demo[3].email };
    const N = { [E.you]: me.display_name || "You" }; demo.forEach((u) => { N[u.email] = u.display_name; });
    const P = { [E.you]: me.profile_picture || "" }; demo.forEach((u) => { P[u.email] = u.profile_picture; });
    const author = (email) => ({ user_email: email, user_display_name: N[email], user_profile_picture: P[email] || "" });

    // --- communities ---
    const c1 = uid(), c2 = uid();
    saveCollection("Community", [
      { ...base(E.you, 60 * 24 * 10), id: c1, name: "Sugerly", description: "The main hangout — art, music & good vibes.", icon_emoji: "\u{1F338}", icon_url: "", banner_url: pic("mimibanner", 1200, 300), owner_email: E.you, owner_display_name: N[E.you], member_emails: [E.you, E.aria, E.kai, E.luna, E.max], welcome_message: "Welcome to Sugerly \u{1F338} introduce yourself in #general!" },
      { ...base(E.aria, 60 * 24 * 6), id: c2, name: "Pixel Pals", description: "Pixel art & game-dev corner.", icon_emoji: "\u{1F3AE}", icon_url: "", banner_url: pic("pixelbanner", 1200, 300), owner_email: E.aria, owner_display_name: N[E.aria], member_emails: [E.aria, E.you, E.kai], welcome_message: "gm pixel pals \u{1F3AE}" },
    ]);

    // --- roles ---
    const rMod = uid(), rArtist = uid(), rMember = uid(), r2Member = uid();
    saveCollection("ServerRole", [
      { ...base(E.you, 1000), id: rMod, community_id: c1, name: "Moderator", color: "#d4708a", permissions: { pin_messages: true, manage_messages: true, kick_members: true, mention_roles: true }, position: 0 },
      { ...base(E.you, 1000), id: rArtist, community_id: c1, name: "Artist", color: "#a78bfa", permissions: {}, position: 1 },
      { ...base(E.you, 1000), id: rMember, community_id: c1, name: "Member", color: "#64748b", permissions: {}, position: 2 },
      { ...base(E.aria, 1000), id: r2Member, community_id: c2, name: "Member", color: "#38bdf8", permissions: {}, position: 0 },
    ]);

    // --- channels ---
    const gen = uid(), show = uid(), off = uid(), v1 = uid(), v2 = uid(), c2gen = uid(), c2v = uid();
    const channel = (cid, owner, id, name, type, description, position, extra) => ({ ...base(owner, 1000), id, community_id: cid, name, type, description, position, allowed_roles: [], ...extra });
    saveCollection("ServerChannel", [
      channel(c1, E.you, gen, "general", "text", "Main chat", 0),
      channel(c1, E.you, show, "showcase", "text", "Share your work", 1, { allowed_roles: ["Artist", "Moderator"] }),
      channel(c1, E.you, off, "off-topic", "text", "Anything goes", 2),
      channel(c1, E.you, v1, "General Voice", "voice", "Hop in and chat", 3),
      channel(c1, E.you, v2, "Music Lounge", "voice", "Listen together", 4),
      channel(c2, E.aria, c2gen, "general", "text", "", 0),
      channel(c2, E.aria, c2v, "Hangout", "voice", "", 1),
    ]);

    // --- members ---
    const member = (cid, email, roles) => ({ ...base(email, 1000), community_id: cid, ...author(email), roles, nickname: "" });
    saveCollection("ServerMember", [
      member(c1, E.you, [rMod]), member(c1, E.aria, [rArtist, rMod]), member(c1, E.kai, [rArtist]), member(c1, E.luna, [rArtist]), member(c1, E.max, [rMember]),
      member(c2, E.aria, [r2Member]), member(c2, E.you, [r2Member]), member(c2, E.kai, [r2Member]),
    ]);

    // --- channel messages ---
    const msg = (cid, chid, email, content, mins, extra) => ({ ...base(email, mins), channel_id: chid, community_id: cid, content, image_url: "", ...author(email), reply_to_id: "", reply_to_preview: "", reactions: {}, is_pinned: false, is_edited: false, ...extra });
    saveCollection("ChannelMessage", [
      msg(c1, gen, E.aria, "hey everyone! welcome to Sugerly \u{1F338}", 240, { is_pinned: true }),
      msg(c1, gen, E.kai, "this place looks so clean ✨", 180),
      msg(c1, gen, E.luna, "just posted a new piece in #showcase \u{1F440}", 90, { reactions: { "❤️": [E.aria, E.kai], "\u{1F525}": [E.max] } }),
      msg(c1, gen, E.max, "lofi set later in Music Lounge?", 35),
      msg(c1, gen, E.you, "let's goooo \u{1F525}", 6),
      msg(c1, show, E.luna, "Wildflower — watercolor, finished today", 88, { image_url: pic("art-luna", 800, 600), reactions: { "✨": [E.aria, E.you] } }),
      msg(c2, c2gen, E.aria, "gm pixel pals \u{1F3AE}", 400),
      msg(c2, c2gen, E.kai, "anyone doing the 16x16 challenge this week?", 300),
    ]);

    // --- artworks (curated gallery) ---
    const art = (title, description, medium, email, seed, likes, mins, extra) => ({ ...base(email, mins), title, description, medium, year: "2025", featured: false, image_url: pic(seed, 640, [480, 800, 640, 560][title.length % 4]), music_url: "", likes: likes || [], ...author(email), ...extra });
    saveCollection("Artwork", [
      art("Sunset Koi", "Koi circling under a warm evening sky.", "painting", E.aria, "koi", [E.you, E.kai, E.luna], 300, { featured: true, music_url: "demo:sunset-koi" }),
      art("Neon Alley", "Late-night rain in the city, reflections everywhere.", "digital", E.kai, "neon", [E.aria, E.you], 900, { featured: true }),
      art("Quiet Morning", "Coffee and soft light.", "painting", E.luna, "morning", [E.max], 1400),
      art("Wildflower", "Field study in watercolor.", "painting", E.luna, "flower", [E.you, E.aria], 2200, { featured: true }),
      art("City Rain", "Umbrellas and reflections.", "drawing", E.kai, "rain", [], 3000),
      art("Dreamscape", "Between sleep and waking.", "digital", E.aria, "dream", [E.you], 3600),
      art("Harbor Light", "Golden hour at the old harbor.", "photography", E.max, "harbor", [E.luna, E.aria], 4200),
      art("Paper Moons", "Collage of cut paper and ink.", "mixed_media", E.luna, "moons", [E.kai], 5000),
    ]);

    // --- community posts ---
    const post = (email, title, description, seed, likes, mins) => ({ ...base(email, mins), title, description, image_url: seed ? pic(seed, 720, 520) : "", ...author(email), likes: likes || [] });
    const p1 = post(E.max, "New mix dropping", "Working on a chill lo-fi set for the Music Lounge tonight \u{1F3A7} #lofi #music", "post-mix", [E.you, E.luna], 120);
    const p2 = post(E.aria, "WIP koi studies", "Sketching some koi studies, thoughts? #wip #koi", "post-koi", [E.kai, E.luna, E.you], 300);
    const p3 = post(E.luna, "Finished!", "So happy with how Wildflower turned out \u{1F33C} #watercolor #finished", "post-flower", [E.you, E.aria, E.kai, E.max], 600);
    const p4 = post(E.kai, "Neon study #4", "Trying a new glow brush, feedback welcome. #digitalart #neon #wip", "post-neon", [E.aria], 900);
    const p5 = post(E.you, "Hello Sugerly", "Excited to be here — let's make cool stuff ✨ #hello", "post-hello", [E.aria, E.luna], 30);
    const p6 = post(E.aria, "", "Art challenge this week: draw your favourite snack as a character \u{1F369} Tag it #snackchallenge!", null, [E.luna, E.kai, E.max], 180);
    const p7 = post(E.luna, "", "What's everyone listening to while drawing today? Paper Lanterns has been on repeat \u{1F3B6} #music", null, [E.aria], 1400);
    saveCollection("CommunityPost", [p1, p2, p3, p4, p5, p6, p7]);
    const comment = (postId, email, content, mins) => ({ ...base(email, mins), post_id: postId, content, gif_url: "", ...author(email), likes: [] });
    saveCollection("CommunityComment", [
      comment(p2.id, E.luna, "the scales are gorgeous \u{1F60D}", 280),
      comment(p2.id, E.kai, "love the palette", 250),
      comment(p3.id, E.aria, "this is so dreamy", 580),
      comment(p6.id, E.kai, "a sentient boba tea incoming", 160),
      comment(p6.id, E.max, "count me in \u{1F369}", 140),
      comment(`profile_${E.you}`, E.aria, "welcome to the site! \u{1F338}", 2000),
    ]);

    // --- music ---
    const review = (email, title, genre, mood, text, likes, mins, plays = 0) => ({ ...base(email, mins), plays, title, music_url: `demo:${title.toLowerCase().replace(/\s+/g, "-")}`, cover_url: pic("cover-" + title.length, 400, 400), genre, mood, ai_review: text, identified_song: "", ...author(email), likes: likes || [] });
    saveCollection("MusicReview", [
      review(E.max, "Midnight Tape", "Lo-fi", "Chill", "Warm, dusty keys over a lazy beat — perfect background music.", [E.you, E.aria], 200, 42),
      review(E.kai, "Neon Drive", "Synthwave", "Energetic", "Pulsing arps and big drums; very 80s in the best way.", [E.luna], 800, 17),
      review(E.aria, "Rainy Window", "Ambient", "Calm", "Soft pads and field recordings; great for focus.", [], 1500),
      review(E.luna, "Paper Lanterns", "Dream pop", "Dreamy", "Floaty melody that sounds like a summer evening.", [E.aria, E.kai, E.you], 2600, 64),
    ]);

    // --- commissions ---
    const comm = (email, title, description, tiers, mins, isOpen) => ({ ...base(email, mins), title, description, artist_email: email, artist_display_name: N[email], artist_profile_picture: P[email] || "", tiers, samples: [pic("samp-" + email.split("@")[0], 600, 600)], tags: [], is_open: isOpen, paypal_link: "" });
    saveCollection("Commission", [
      comm(E.aria, "Watercolor Portraits", "Soft, hand-painted portraits from your photo.", [{ name: "Bust", price: 25, description: "Head & shoulders" }, { name: "Half Body", price: 45, description: "Waist up" }], 400, true),
      comm(E.kai, "Neon Character Art", "Stylised digital character with neon lighting.", [{ name: "Sketch", price: 20, description: "Lineart" }, { name: "Full Color", price: 60, description: "Rendered + background" }], 900, true),
      comm(E.luna, "Dreamy Landscapes", "Custom landscape of a place you love.", [{ name: "Small", price: 40, description: "A5 digital" }, { name: "Large", price: 90, description: "A3 print-ready" }], 1300, false),
    ]);

    // --- friendships ---
    const fr = (req, rec, status, mins) => ({ ...base(req, mins), requester_email: req, requester_display_name: N[req], requester_profile_picture: P[req] || "", receiver_email: rec, receiver_display_name: N[rec], receiver_profile_picture: P[rec] || "", status });
    saveCollection("Friendship", [fr(E.aria, E.you, "accepted", 5000), fr(E.luna, E.you, "accepted", 4000), fr(E.kai, E.you, "pending", 40)]);

    // --- direct messages + a group ---
    const dmId = [E.you, E.aria].sort().join("__dm__");
    const dm = (convo, members, email, content, mins, type = "dm", group_name = "") => ({ ...base(email, mins), conversation_id: convo, conversation_type: type, group_name, content, image_url: "", ...author(email), member_emails: members, read_by: [email], reactions: {}, is_edited: false });
    const g1 = uid();
    const groupMembers = [E.you, E.aria, E.luna].sort();
    saveCollection("GroupChat", [{ ...base(E.aria, 3000), id: g1, name: "Art Squad", owner_email: E.aria, member_emails: groupMembers, member_display_names: { [E.you]: N[E.you], [E.aria]: N[E.aria], [E.luna]: N[E.luna] } }]);
    saveCollection("DirectMessage", [
      dm(dmId, [E.you, E.aria].sort(), E.aria, "hey! loved your latest post \u{1F338}", 50),
      dm(dmId, [E.you, E.aria].sort(), E.you, "thank you!! your koi piece is amazing", 45),
      dm(dmId, [E.you, E.aria].sort(), E.aria, "we should collab sometime ✨", 12),
      dm(g1, groupMembers, E.luna, "art jam this weekend?", 100, "group", "Art Squad"),
      dm(g1, groupMembers, E.aria, "yes!! I'll bring snacks", 95, "group", "Art Squad"),
    ]);

    // --- notifications ---
    const notif = (from, type, message, read, mins, link = "") => ({ ...base(from, mins), to_email: E.you, from_email: from, from_display_name: N[from], from_profile_picture: P[from] || "", type, message, link, entity_id: "", is_read: !!read });
    saveCollection("Notification", [
      notif(E.aria, "like", "Aria liked your post \"Hello Sugerly\"", false, 20, "/Community"),
      notif(E.kai, "friend_request", "Kai sent you a friend request", false, 40, "/Friends"),
      notif(E.luna, "comment", "Luna commented on your post", true, 200, "/Community"),
    ]);

    saveCollection("SiteConfig", [{ ...base(E.you, 100), key: "global", announcement: "Welcome to the new Sugerly ✨ Reels, video cuts and AI captions are here.", announcement_active: true, announcement_color: "#d4708a", primary_color: "" }]);

    writeRaw(`${PREFIX}:__seeded`, "2");
  } catch (e) {
    console.warn("[localBackend] seed skipped:", e);
  }
}

// Reels arrived after the first demo seed, so they have their own one-time
// seed that also runs for demo data created by older versions.
const DEMO_VIDEO = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4";
function seedReelsIfMissing() {
  if (!isBrowser || readRaw(`${PREFIX}:__seeded_reels`)) return;
  try {
    const users = loadCollection("User");
    const find = (name) => users.find((u) => u.email === `${name}@mimilocks.local`);
    const people = ["aria", "kai", "luna", "max"].map(find).filter(Boolean);
    const admin = users.find((u) => u.role === "admin");
    if (!people.length) { writeRaw(`${PREFIX}:__seeded_reels`, "1"); return; }
    const tracks = loadCollection("MusicReview");
    const ago = (m) => new Date(Date.now() - m * 60000).toISOString();
    const pic = (seed) => `https://picsum.photos/seed/${seed}/720/1280`;
    const emails = users.map((u) => u.email);
    const pickLikes = (n, salt) => emails.filter((_, i) => (i * 7 + salt) % 5 < n);
    const reel = (u, i, extra) => ({
      id: uid(), created_date: ago(30 + i * 173), updated_date: ago(30 + i * 173), created_by: u.email,
      user_email: u.email, user_display_name: u.display_name, user_profile_picture: u.profile_picture || "",
      kind: "photo", media_url: "", cover_url: "", caption: "", tags: [], music_url: "", music_title: "", music_artist: "",
      edits: { trim_start: 0, trim_end: 0, filter: "none", speed: 1, muted: false, text: [] },
      likes: [], views: 0, duration: 7, ...extra,
    });
    const track = (i) => tracks[i % Math.max(1, tracks.length)] || null;
    const music = (i) => { const t = track(i); return t ? { music_url: t.music_url, music_title: t.title, music_artist: t.user_display_name } : {}; };
    const [aria, kai, luna, max] = [people[0], people[1] || people[0], people[2] || people[0], people[3] || people[0]];
    const tagsOf = (text) => [...text.matchAll(/#([\p{L}\p{N}_]{2,30})/gu)].map((m) => m[1].toLowerCase());
    const rows = [
      reel(aria, 0, { media_url: pic("reel-koi"), cover_url: pic("reel-koi"), caption: "koi pond study, 3 layers of wash 🐟 #watercolor #koi", edits: { trim_start: 0, trim_end: 0, filter: "sugar", speed: 1, muted: false, text: [{ id: "t1", text: "day 12 of koi 🐟", x: 0.5, y: 0.18, color: "#ffffff", bg: "rgba(217,87,127,0.85)", size: 0.06 }] }, likes: pickLikes(3, 1), views: 142, ...music(3) }),
      reel(kai, 1, { kind: "video", media_url: DEMO_VIDEO, cover_url: pic("reel-flower"), caption: "timelapse of tonight's neon study ✨ #digitalart #timelapse", edits: { trim_start: 0, trim_end: 0, filter: "vivid", speed: 1, muted: true, text: [{ id: "t1", text: "neon garden", x: 0.5, y: 0.82, color: "#ffffff", bg: "", size: 0.08 }] }, likes: pickLikes(4, 2), views: 388, duration: 5, ...music(1) }),
      reel(luna, 2, { media_url: pic("reel-dream"), cover_url: pic("reel-dream"), caption: "soft light, softer brushes ☁️ #landscape #dreamy", edits: { trim_start: 0, trim_end: 0, filter: "dreamy", speed: 1, muted: false, text: [] }, likes: pickLikes(4, 3), views: 510, ...music(0) }),
      reel(max, 3, { media_url: pic("reel-lofi"), cover_url: pic("reel-lofi"), caption: "drawing session soundtrack 🎧 #lofi #music", edits: { trim_start: 0, trim_end: 0, filter: "vintage", speed: 1, muted: false, text: [{ id: "t1", text: "press play & draw", x: 0.5, y: 0.5, color: "#ffe9f1", bg: "", size: 0.08 }] }, likes: pickLikes(2, 4), views: 97, ...music(0) }),
      reel(aria, 4, { kind: "video", media_url: DEMO_VIDEO, cover_url: pic("reel-bloom"), caption: "slow bloom 🌸 reference for my next piece #reference #watercolor", edits: { trim_start: 1, trim_end: 4.5, filter: "peach", speed: 0.5, muted: true, text: [] }, likes: pickLikes(3, 5), views: 205, duration: 5, ...music(2) }),
      reel(kai, 5, { media_url: pic("reel-city"), cover_url: pic("reel-city"), caption: "rainy city palette test 🌧️ #digitalart #colorstudy", edits: { trim_start: 0, trim_end: 0, filter: "cool", speed: 1, muted: false, text: [] }, likes: pickLikes(1, 6), views: 64, ...music(1) }),
      reel(luna, 6, { media_url: pic("reel-sunset"), cover_url: pic("reel-sunset"), caption: "golden hour speedpaint 🌅 #landscape #speedpaint", edits: { trim_start: 0, trim_end: 0, filter: "golden", speed: 1, muted: false, text: [{ id: "t1", text: "20 min challenge", x: 0.5, y: 0.14, color: "#2a1620", bg: "rgba(255,255,255,0.9)", size: 0.055 }] }, likes: pickLikes(5, 7), views: 902, ...music(3) }),
      reel(max, 7, { media_url: pic("reel-sketch"), cover_url: pic("reel-sketch"), caption: "sketchbook flip, be nice 🙈 #sketchbook #drawing", edits: { trim_start: 0, trim_end: 0, filter: "mono", speed: 1, muted: false, text: [] }, likes: pickLikes(2, 8), views: 51, ...music(0) }),
      ...(admin ? [reel(admin, 8, { media_url: pic("reel-hello"), cover_url: pic("reel-hello"), caption: "welcome to Sugerly reels 🍬 #hello", edits: { trim_start: 0, trim_end: 0, filter: "pop", speed: 1, muted: false, text: [{ id: "t1", text: "hi from sugerly 🍬", x: 0.5, y: 0.5, color: "#ffffff", bg: "rgba(217,87,127,0.85)", size: 0.07 }] }, likes: pickLikes(2, 9), views: 33, ...music(2) })] : []),
    ].map((r) => ({ ...r, tags: tagsOf(r.caption) }));
    saveCollection("Reel", [...loadCollection("Reel"), ...rows]);
    writeRaw(`${PREFIX}:__seeded_reels`, "1");
  } catch (e) {
    console.warn("[localBackend] reel seed skipped:", e);
  }
}

// Wipes every local record (used by the "Reset demo data" button in Settings).
export function resetLocalData() {
  if (!isBrowser) return;
  Object.keys(window.localStorage).filter((k) => k.startsWith(`${PREFIX}:`)).forEach((k) => window.localStorage.removeItem(k));
}

export function createLocalClient() {
  const ready = isBrowser ? ensureDefaultAdminAccount().then(seedIfEmpty).then(seedReelsIfMissing).catch((e) => console.warn("[localBackend] init skipped:", e)) : Promise.resolve();
  const withReady = (fn) => async (...args) => { await ready; return fn(...args); };
  // Make sure the first query after page load sees the seeded demo data.
  Object.values(entities).forEach((entity) => {
    ["list", "filter", "get"].forEach((m) => { entity[m] = withReady(entity[m].bind(entity)); });
  });
  return { entities, auth, integrations, mode: "local", resetLocalData };
}
