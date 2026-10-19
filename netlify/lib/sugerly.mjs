// Shared helpers for Sugerly's payment functions (Netlify Functions).
//
// No packages needed: Stripe and Firebase are reached over their REST APIs.
// Settings (Netlify → Site configuration → Environment variables):
//   STRIPE_SECRET_KEY        sk_live_… (or sk_test_… to try it out)
//   STRIPE_WEBHOOK_SECRET    whsec_… (optional; payments are also confirmed
//                            when the buyer comes back from Stripe)
//   FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY  (the service account key's
//                            "client_email" and "private_key"), or the whole
//                            key as FIREBASE_SERVICE_ACCOUNT
//   SITE_URL                 optional, defaults to https://sugerly.netlify.app
//   LOGIN_SECRET             optional: any long random text. Login and backup
//                            codes are fingerprinted with it, so they keep
//                            working when the Firebase key is replaced.
// The same code also runs on Firebase (functions/index.js), where these come
// from GitHub secrets (.github/workflows/firebase-server.yml).
import crypto from "node:crypto";

// Where this server's settings are kept, for setup messages: Netlify's
// environment variables, or GitHub secrets when it runs on Firebase.
export const SETTINGS = process.env.SUGERLY_SETTINGS || "Netlify";
export const PROJECT = process.env.FIREBASE_PROJECT_ID || "umikoworks-86333";
// The Firebase web API key is a public identifier (it's in the app too).
const WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY || "AIzaSyA__4874dkVIZMdV5GWQVzWX0rSPET_W4E";
export const SITE = (process.env.SITE_URL || process.env.URL || "https://sugerly.netlify.app").replace(/\/$/, "");
const OWNERS = ["paologionfriddo90@gmail.com"];
export const CURRENCIES = ["usd", "eur", "gbp", "cad", "aud"];

// ---- responses -----------------------------------------------------------

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Sugerly-Token",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function reply(status, body) {
  return { statusCode: status, headers: { ...CORS, "Content-Type": "application/json" }, body: JSON.stringify(body) };
}

export function preflight(event) {
  return event.httpMethod === "OPTIONS" ? { statusCode: 204, headers: CORS, body: "" } : null;
}

export class Problem extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export async function handle(event, work, what = "payment server") {
  const early = preflight(event);
  if (early) return early;
  try {
    return reply(200, await work());
  } catch (e) {
    const status = e instanceof Problem ? e.status : 500;
    if (status === 500) console.error(e);
    // Unexpected errors keep a short reason so problems can be found quickly.
    return reply(status, { error: e instanceof Problem ? e.message : `Something went wrong on the ${what} (${String(e?.message || e).slice(0, 140)}). Please try again.` });
  }
}

export function body(event) {
  try {
    const raw = event.isBase64Encoded ? Buffer.from(event.body || "", "base64").toString("utf8") : event.body || "";
    return raw ? JSON.parse(raw) : {};
  } catch { return {}; }
}

// ---- who is asking --------------------------------------------------------

// Checks the Firebase ID token the app sends and returns { uid, email }.
// It comes in X-Sugerly-Token: Netlify can answer a Bearer token in the
// Authorization header itself (with a bare 401) before this code runs.
export async function signedInUser(event) {
  const h = event.headers || {};
  const header = h["x-sugerly-token"] || h["X-Sugerly-Token"] || h.authorization || h.Authorization || "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Problem(401, "Please log in again.");
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${WEB_API_KEY}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ idToken: token }),
  });
  const data = await res.json().catch(() => ({}));
  const user = data.users?.[0];
  if (!res.ok || !user?.email) throw new Problem(401, "Please log in again.");
  return { uid: user.localId, email: String(user.email).toLowerCase() };
}

export async function isAdmin(user) {
  if (OWNERS.includes(user.email)) return true;
  const doc = await getDoc("User", user.uid);
  return doc?.role === "admin";
}

// ---- Firebase (as the server, so it can do what the app can't) ------------

function serviceAccount() {
  const raw = (process.env.FIREBASE_SERVICE_ACCOUNT || "").trim();
  let key = null;
  if (raw) {
    const text = raw.startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
    key = JSON.parse(text);
  } else if (process.env.FIREBASE_PRIVATE_KEY) {
    const value = process.env.FIREBASE_PRIVATE_KEY.trim();
    // The whole key file pasted into FIREBASE_PRIVATE_KEY works too.
    let file = null;
    if (value.startsWith("{")) { try { file = JSON.parse(value); } catch { file = null; } }
    key = {
      client_email: (file?.client_email || process.env.FIREBASE_CLIENT_EMAIL || `firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com`).trim(),
      private_key: file?.private_key || value,
    };
  }
  if (!key) throw new Problem(503, "Payments aren't set up yet (missing Firebase key on the server).");
  key.private_key = cleanPem(key.private_key);
  return key;
}

// Rebuilds the key however it was pasted: with or without quotes, with
// "\n" written out or real line breaks, or without the BEGIN/END lines.
function cleanPem(value) {
  const text = String(value || "").replace(/\\n/g, "\n");
  const hasBegin = /-----BEGIN PRIVATE KEY-----/.test(text);
  const hasEnd = /-----END PRIVATE KEY-----/.test(text);
  const middle = text
    .replace(/[\s\S]*-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----[\s\S]*/, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  cleanPem.info = { hasBegin, hasEnd, length: middle.length };
  if (middle.length < 100) return text;
  return `-----BEGIN PRIVATE KEY-----\n${middle.match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----\n`;
}

const DATASTORE = "https://www.googleapis.com/auth/datastore";
const tokens = new Map();
async function googleToken(scope = DATASTORE) {
  const cached = tokens.get(scope);
  if (cached && cached.expires > Date.now() + 60_000) return cached.value;
  let key;
  try {
    key = serviceAccount();
  } catch (e) {
    if (e instanceof Problem) throw e;
    throw new Problem(503, `Payments setup: FIREBASE_SERVICE_ACCOUNT on ${SETTINGS} isn't a valid key file.`);
  }
  if (!key.client_email || !String(key.client_email).includes("@")) {
    throw new Problem(503, `Payments setup: FIREBASE_CLIENT_EMAIL on ${SETTINGS} is missing or wrong.`);
  }
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({
    iss: key.client_email, sub: key.client_email, aud: "https://oauth2.googleapis.com/token",
    scope, iat: now, exp: now + 3600,
  })}`;
  let signature;
  try {
    signature = crypto.createSign("RSA-SHA256").update(unsigned).sign(key.private_key).toString("base64url");
  } catch {
    // Says what's there (never the key itself): a full key is about 1,600 characters.
    const info = cleanPem.info || {};
    throw new Problem(503, `Payments setup: FIREBASE_PRIVATE_KEY on ${SETTINGS} is incomplete (start line: ${info.hasBegin ? "yes" : "missing"}, end line: ${info.hasEnd ? "yes" : "missing"}, ${info.length ?? 0} of about 1,600 characters). Paste the whole private_key, from -----BEGIN to END PRIVATE KEY-----.`);
  }
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${signature}` }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    // Usually the key was deleted in Google Cloud or doesn't match the email.
    throw new Problem(503, `Payments setup: Google refused the Firebase key on ${SETTINGS} (${data.error_description || data.error || res.status}). Make a new key and put it in ${SETTINGS}.`);
  }
  tokens.set(scope, { value: data.access_token, expires: Date.now() + data.expires_in * 1000 });
  return data.access_token;
}

const DOCS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function encode(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  if (typeof v === "object") return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)])) } };
  return { stringValue: String(v) };
}

function decode(v) {
  if (!v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("nullValue" in v) return null;
  if ("timestampValue" in v) return v.timestampValue;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(decode);
  if ("mapValue" in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, decode(x)]));
  return null;
}

function fromDocument(doc) {
  const out = Object.fromEntries(Object.entries(doc.fields || {}).map(([k, v]) => [k, decode(v)]));
  out.id = doc.name.split("/").pop();
  return out;
}

async function firestore(path, init = {}) {
  const res = await fetch(`${DOCS}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${await googleToken()}`, "Content-Type": "application/json", ...(init.headers || {}) },
  });
  if (res.status === 404) return null;
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 || res.status === 403) {
    throw new Problem(503, `Payments setup: the Firebase key on ${SETTINGS} can't use the database (${data.error?.status || res.status}). Check it's from the umikoworks-86333 project.`);
  }
  if (!res.ok) throw new Error(`Firestore ${res.status}: ${data.error?.message || ""}`);
  return data;
}

export async function getDoc(collection, id) {
  if (!id || /[/]/.test(id)) return null;
  const doc = await firestore(`/${collection}/${encodeURIComponent(id)}`);
  return doc ? fromDocument(doc) : null;
}

export async function updateDoc(collection, id, fields) {
  const mask = Object.keys(fields).map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join("&");
  const doc = await firestore(`/${collection}/${encodeURIComponent(id)}?${mask}&currentDocument.exists=true`, {
    method: "PATCH",
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, encode(v)])) }),
  });
  return doc ? fromDocument(doc) : null;
}

export async function addDoc(collection, fields) {
  const doc = await firestore(`/${collection}`, {
    method: "POST",
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, encode(v)])) }),
  });
  return doc ? fromDocument(doc) : null;
}

// Creates the document, or replaces it whole.
export async function setDoc(collection, id, fields) {
  const doc = await firestore(`/${collection}/${encodeURIComponent(id)}`, {
    method: "PATCH",
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, encode(v)])) }),
  });
  return doc ? fromDocument(doc) : null;
}

export async function deleteDoc(collection, id) {
  if (!id || /[/]/.test(id)) return;
  await firestore(`/${collection}/${encodeURIComponent(id)}`, { method: "DELETE" });
}

export function docName(collection, id) {
  return `projects/${PROJECT}/databases/(default)/documents/${collection}/${id}`;
}

// Documents where every [field, op, value] matches (op: EQUAL, ARRAY_CONTAINS…).
export async function findMany(collection, filters, limit = 300) {
  const where = filters.map(([field, op, value]) => ({ fieldFilter: { field: { fieldPath: field }, op, value: encode(value) } }));
  const res = await firestore(":runQuery", {
    method: "POST",
    body: JSON.stringify({ structuredQuery: {
      from: [{ collectionId: collection }],
      where: where.length === 1 ? where[0] : { compositeFilter: { op: "AND", filters: where } },
      limit,
    } }),
  });
  return (res || []).filter((r) => r.document).map((r) => fromDocument(r.document));
}

// Several changes at once (up to 500): deletes, or removing from a list.
export async function commit(writes) {
  if (!writes.length) return;
  await firestore(":commit", { method: "POST", body: JSON.stringify({ writes }) });
}

export function removeFromList(collection, id, field, value) {
  return {
    transform: {
      document: docName(collection, id),
      fieldTransforms: [{ fieldPath: field, removeAllFromArray: { values: [encode(value)] } }],
    },
    currentDocument: { exists: true },
  };
}

export async function findOne(collection, field, value) {
  const res = await firestore(":runQuery", {
    method: "POST",
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection }], where: { fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: encode(value) } }, limit: 1 } }),
  });
  const hit = (res || []).find((r) => r.document);
  return hit ? fromDocument(hit.document) : null;
}

// ---- Firebase Auth (as the server) -----------------------------------------

const AUTH_SCOPE = "https://www.googleapis.com/auth/identitytoolkit https://www.googleapis.com/auth/cloud-platform";

async function authAdmin(method, payload) {
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts${method}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await googleToken(AUTH_SCOPE)}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 || res.status === 403) {
    throw new Problem(503, `Login setup: the Firebase key on ${SETTINGS} can't manage accounts (${data.error?.status || res.status}).`);
  }
  if (!res.ok) {
    const code = String(data.error?.message || res.status);
    if (code.includes("WEAK_PASSWORD")) throw new Problem(400, "Use at least 6 characters for your password.");
    if (code.includes("USER_NOT_FOUND")) throw new Problem(404, "That account doesn't exist any more.");
    throw new Error(`Auth ${res.status}: ${code}`);
  }
  return data;
}

// The account for an email: { uid, email, disabled }, or null.
export async function findAccount(email) {
  const clean = String(email || "").trim().toLowerCase();
  if (!clean.includes("@")) return null;
  const data = await authAdmin(":lookup", { email: [clean] });
  const user = data.users?.[0];
  return user ? { uid: user.localId, email: String(user.email || clean).toLowerCase(), disabled: !!user.disabled } : null;
}

export function setPassword(uid, password) {
  return authAdmin(":update", { localId: uid, password });
}

export function deleteAccount(uid) {
  return authAdmin(":delete", { localId: uid });
}

// A one-time sign-in pass for an account: the app trades it for a normal
// session (signInWithCustomToken). Good for an hour, used once.
export function customToken(uid) {
  const key = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({
    iss: key.client_email, sub: key.client_email,
    aud: "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
    iat: now, exp: now + 3600, uid,
  })}`;
  const signature = crypto.createSign("RSA-SHA256").update(unsigned).sign(key.private_key).toString("base64url");
  return `${unsigned}.${signature}`;
}

// Codes are only ever stored as this keyed fingerprint, never as typed.
// Without LOGIN_SECRET the Firebase key is the secret, so a new key means
// new backup codes.
export function fingerprint(text) {
  const secret = (process.env.LOGIN_SECRET || "").trim() || serviceAccount().private_key;
  return crypto.createHmac("sha256", `sugerly-login:${secret}`).update(String(text)).digest("hex");
}

export function sameFingerprint(a, b) {
  const x = Buffer.from(String(a || ""));
  const y = Buffer.from(String(b || ""));
  return x.length === y.length && x.length > 0 && crypto.timingSafeEqual(x, y);
}

// ---- email -----------------------------------------------------------------

// Sugerly's own emails (login and password codes). Either service works:
//   BREVO_API_KEY + MAIL_FROM (the sender address you verified in Brevo), or
//   RESEND_API_KEY + MAIL_FROM (an address on the domain you verified there).
export function mailReady() {
  return Boolean((process.env.BREVO_API_KEY || process.env.RESEND_API_KEY || "").trim());
}

export async function sendMail({ to, subject, html, text }) {
  const from = (process.env.MAIL_FROM || "").trim();
  const name = "Sugerly";
  const brevo = (process.env.BREVO_API_KEY || "").trim();
  const resend = (process.env.RESEND_API_KEY || "").trim();
  let res;
  if (brevo) {
    if (!from) throw new Problem(503, `Email setup: add MAIL_FROM on ${SETTINGS} (the sender email you verified in Brevo).`);
    if (brevo.startsWith("xsmtpsib-")) {
      throw new Problem(503, `Email setup: BREVO_API_KEY on ${SETTINGS} is Brevo's SMTP key. In Brevo → SMTP & API → API keys, make an API key (it starts with xkeysib-) and paste that instead.`);
    }
    res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": brevo, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ sender: { name, email: from }, to: [{ email: to }], subject, htmlContent: html, textContent: text }),
    });
  } else if (resend) {
    res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resend}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: `${name} <${from || "onboarding@resend.dev"}>`, to: [to], subject, html, text }),
    });
  } else {
    throw new Problem(503, "Email codes aren't switched on yet.");
  }
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    const detail = String(data.message || data.code || "");
    if (res.status === 401 || res.status === 403) {
      if (/\bIP\b|ip address/i.test(detail)) {
        throw new Problem(503, `Email setup: Brevo is blocking the server's address. In Brevo → Settings → Security → Authorised IPs, turn off blocking of unknown IP addresses.`);
      }
      throw new Problem(503, `Email setup: the email service didn't accept the API key on ${SETTINGS}${brevo ? " (it should start with xkeysib-)" : ""}. ${detail.slice(0, 80)}`.trim());
    }
    throw new Problem(502, `The email didn't send (${(detail || String(res.status)).slice(0, 120)}).`);
  }
}

// Sugerly's cut of each commission, set by admins (Site settings).
export async function feePercent() {
  const config = await findOne("SiteConfig", "key", "global").catch(() => null);
  const n = Number(config?.commission_fee_percent);
  return Number.isFinite(n) && n >= 0 && n <= 50 ? n : 10;
}

export function notify(to, from, message, link) {
  const now = new Date().toISOString();
  return addDoc("Notification", {
    to_email: to, from_email: from?.email || "", from_display_name: from?.name || "Sugerly", from_profile_picture: "",
    type: "commission", message, link, is_read: false, created_by: from?.email || "sugerly", created_date: now, updated_date: now,
  }).catch(() => null);
}

// ---- Stripe --------------------------------------------------------------

function stripeKey() {
  const key = (process.env.STRIPE_SECRET_KEY || "").trim().replace(/^["']|["']$/g, "");
  if (!key) throw new Problem(503, "Card payments aren't set up yet (missing Stripe key on the server).");
  // Never echo the value back: just say what kind of thing is there.
  if (/BEGIN PRIVATE KEY|private_key/.test(key)) {
    throw new Problem(503, `Payments setup: STRIPE_SECRET_KEY on ${SETTINGS} holds the Firebase key by mistake. Put your Stripe secret key there (it starts with sk_test_ or sk_live_).`);
  }
  if (key.startsWith("pk_")) {
    throw new Problem(503, `Payments setup: STRIPE_SECRET_KEY on ${SETTINGS} is the publishable key (pk_…). Use the secret key, which starts with sk_test_ or sk_live_.`);
  }
  if (!/^(sk|rk)_(test|live)_[A-Za-z0-9]+$/.test(key)) {
    throw new Problem(503, `Payments setup: STRIPE_SECRET_KEY on ${SETTINGS} isn't a Stripe secret key. It should start with sk_test_ or sk_live_.`);
  }
  return key;
}

export async function stripe(path, params, method = "POST") {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: { Authorization: `Bearer ${stripeKey()}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: method === "GET" ? undefined : new URLSearchParams(params),
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401) {
    // Stripe's own text repeats part of the key, so it isn't passed on.
    throw new Problem(503, `Payments setup: Stripe didn't accept STRIPE_SECRET_KEY on ${SETTINGS}. Copy the secret key again from Stripe → Developers → API keys.`);
  }
  if (!res.ok) throw new Problem(502, data.error?.message || "Stripe didn't accept that.");
  return data;
}

export const toMinor = (amount) => Math.round(Number(amount) * 100);
export const fromMinor = (minor) => Math.round(Number(minor)) / 100;

// Marks an order paid once Stripe says the checkout is paid. Safe to call
// more than once (from the webhook and when the buyer comes back).
export async function settle(session) {
  const orderId = session.metadata?.order_id || session.client_reference_id;
  if (!orderId || session.payment_status !== "paid") return { status: "unpaid" };
  const order = await getDoc("CommissionOrder", orderId);
  if (!order) return { status: "missing" };
  if (order.status !== "accepted") return { status: order.status, orderId };
  const fee = await feePercent();
  const amount = fromMinor(session.amount_total);
  const now = new Date().toISOString();
  await updateDoc("CommissionOrder", orderId, {
    status: "paid", paid_at: now, amount_paid: amount, currency: session.currency,
    fee_percent: fee, artist_earnings: Math.round(amount * (100 - fee)) / 100,
    stripe_session_id: session.id, payment_intent: typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id || "",
    updated_date: now,
  });
  const buyer = { email: order.buyer_email, name: order.buyer_name };
  await notify(order.artist_email, buyer, `${order.buyer_name || "Someone"} paid for "${order.commission_title}". Time to create!`, `/Commissions?order=${orderId}`);
  return { status: "paid", orderId };
}
// An idempotent purchase: item price, balance and ownership share one transaction.
// Only this server can create BunnyPurchase records.
export async function purchaseBunnyItem(user, itemID, expectedPrice) {
  if (!/^[A-Za-z0-9_-]{1,160}$/.test(itemID)) throw new Problem(400, "Choose a valid item.");
  const purchaseID = crypto.createHash("sha256").update(`${user.uid}:${itemID}`).digest("hex");
  for (let attempt = 0; attempt < 4; attempt++) {
    const { transaction } = await firestore(":beginTransaction", { method: "POST", body: JSON.stringify({ options: { readWrite: {} } }) });
    try {
      const names = [docName("BunnyItem", itemID), docName("User", user.uid), docName("BunnyPurchase", purchaseID)];
      const rows = await firestore(":batchGet", { method: "POST", body: JSON.stringify({ documents: names, transaction }) });
      const found = new Map(rows.filter(r => r.found).map(r => [r.found.name, fromDocument(r.found)]));
      const item = found.get(names[0]), profile = found.get(names[1]), owned = found.get(names[2]);
      if (!item) throw new Problem(404, "This item is no longer available.");
      if (!profile) throw new Problem(404, "Your profile is unavailable. Sign in again.");
      if (owned) {
        await firestore(":rollback", { method: "POST", body: JSON.stringify({ transaction }) });
        return { owned: true, coins: profile.coins };
      }
      const price = item.price_coins ?? 0;
      if (!Number.isSafeInteger(price) || price < 0 || price > 1000000) throw new Problem(400, "This item's price needs correcting.");
      if (expectedPrice !== price) throw new Problem(409, "The price changed. Reopen the shop before buying.");
      const balance = profile.coins ?? 0;
      if (!Number.isSafeInteger(balance) || balance < price) throw new Problem(400, "You don't have enough coins.");
      const fields = value => Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encode(v)]));
      await firestore(":commit", { method: "POST", body: JSON.stringify({ transaction, writes: [
        { update: { name: names[1], fields: fields({ coins: balance - price, updated_date: new Date().toISOString() }) }, updateMask: { fieldPaths: ["coins", "updated_date"] } },
        { update: { name: names[2], fields: fields({ user_email: user.email, user_id: user.uid, item_id: itemID, price_coins: price, created_date: new Date().toISOString() }) }, currentDocument: { exists: false } },
      ] }) });
      return { owned: true, coins: balance - price };
    } catch (error) {
      await firestore(":rollback", { method: "POST", body: JSON.stringify({ transaction }) }).catch(() => {});
      if (attempt < 3 && /Firestore 409|ABORTED/.test(error.message)) continue;
      throw error;
    }
  }
}
