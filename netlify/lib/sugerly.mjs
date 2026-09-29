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
import crypto from "node:crypto";

export const PROJECT = process.env.FIREBASE_PROJECT_ID || "umikoworks-86333";
// The Firebase web API key is a public identifier (it's in the app too).
const WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY || "AIzaSyA__4874dkVIZMdV5GWQVzWX0rSPET_W4E";
export const SITE = (process.env.SITE_URL || process.env.URL || "https://sugerly.netlify.app").replace(/\/$/, "");
const OWNERS = ["paologionfriddo90@gmail.com"];
export const CURRENCIES = ["usd", "eur", "gbp", "cad", "aud"];

// ---- responses -----------------------------------------------------------

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
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

export async function handle(event, work) {
  const early = preflight(event);
  if (early) return early;
  try {
    return reply(200, await work());
  } catch (e) {
    const status = e instanceof Problem ? e.status : 500;
    if (status === 500) console.error(e);
    return reply(status, { error: e instanceof Problem ? e.message : "Something went wrong. Please try again." });
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
export async function signedInUser(event) {
  const header = event.headers?.authorization || event.headers?.Authorization || "";
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
    key = {
      client_email: (process.env.FIREBASE_CLIENT_EMAIL || `firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com`).trim(),
      private_key: process.env.FIREBASE_PRIVATE_KEY,
    };
  }
  if (!key) throw new Problem(503, "Payments aren't set up yet (missing Firebase key on the server).");
  // Rebuild the PEM block if its line breaks got lost when pasting.
  const pem = String(key.private_key).replace(/\\n/g, "\n");
  const m = /-----BEGIN PRIVATE KEY-----([\s\S]*?)-----END PRIVATE KEY-----/.exec(pem);
  const bodyText = m ? m[1].replace(/\s+/g, "") : "";
  key.private_key = m ? `-----BEGIN PRIVATE KEY-----\n${bodyText.match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----\n` : pem;
  return key;
}

let cachedToken = null;
async function googleToken() {
  if (cachedToken && cachedToken.expires > Date.now() + 60_000) return cachedToken.value;
  const key = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({
    iss: key.client_email, sub: key.client_email, aud: "https://oauth2.googleapis.com/token",
    scope: "https://www.googleapis.com/auth/datastore", iat: now, exp: now + 3600,
  })}`;
  const signature = crypto.createSign("RSA-SHA256").update(unsigned).sign(key.private_key).toString("base64url");
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${signature}` }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Google token: ${data.error_description || data.error || res.status}`);
  cachedToken = { value: data.access_token, expires: Date.now() + data.expires_in * 1000 };
  return cachedToken.value;
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

export async function findOne(collection, field, value) {
  const res = await firestore(":runQuery", {
    method: "POST",
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: collection }], where: { fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: encode(value) } }, limit: 1 } }),
  });
  const hit = (res || []).find((r) => r.document);
  return hit ? fromDocument(hit.document) : null;
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
  const key = (process.env.STRIPE_SECRET_KEY || "").trim();
  if (!key) throw new Problem(503, "Card payments aren't set up yet (missing Stripe key on the server).");
  return key;
}

export async function stripe(path, params, method = "POST") {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: { Authorization: `Bearer ${stripeKey()}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: method === "GET" ? undefined : new URLSearchParams(params),
  });
  const data = await res.json();
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
