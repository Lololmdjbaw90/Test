// Sugerly's server on Firebase (Cloud Functions). It runs the same code as
// Netlify: scripts/sync-server.mjs copies netlify/functions and netlify/lib in
// here before each deploy, and this file serves them as one function, "api":
//   https://us-central1-umikoworks-86333.cloudfunctions.net/api/<name>
//   https://umikoworks-86333.web.app/api/<name> (and /.netlify/functions/<name>,
//   so the website's own pages work unchanged)
// Its settings (Stripe, email, Apple push, the Firebase key…) come from one
// secret, SUGERLY_ENV, which .github/workflows/firebase-server.yml fills from
// the repository's GitHub secrets.
import { readdirSync } from "node:fs";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const SETTINGS = defineSecret("SUGERLY_ENV");
const CODE = new URL("./netlify/functions/", import.meta.url);
const NAMES = new Set(readdirSync(CODE).filter((f) => f.endsWith(".mjs")).map((f) => f.slice(0, -4)));
if (!NAMES.size) throw new Error("No server code in functions/netlify: run node scripts/sync-server.mjs first.");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Sugerly-Token",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// The settings become plain environment variables, as on Netlify. Done once,
// before any of the Netlify code loads (it reads some of them as it loads).
let settingsCount = -1;
function loadSettings() {
  if (settingsCount >= 0) return;
  settingsCount = 0;
  let values = {};
  try {
    values = JSON.parse(process.env.SUGERLY_ENV || "{}");
  } catch {
    console.error("SUGERLY_ENV isn't valid JSON, so the server runs without its settings.");
  }
  for (const [key, value] of Object.entries(values)) {
    if (typeof value !== "string" || !value || process.env[key] !== undefined) continue;
    process.env[key] = value;
    settingsCount += 1;
  }
  // Setup messages then point at GitHub secrets instead of Netlify.
  process.env.SUGERLY_SETTINGS ||= "GitHub";
}

const loaded = new Map();
function handlerFor(name) {
  if (!loaded.has(name)) {
    const job = import(new URL(`${name}.mjs`, CODE).href).then((m) => m.handler);
    job.catch(() => loaded.delete(name));
    loaded.set(name, job);
  }
  return loaded.get(name);
}

// The request in the shape Netlify hands its functions.
function netlifyEvent(req, url) {
  const headers = {};
  for (const [key, value] of Object.entries(req.headers)) {
    headers[key.toLowerCase()] = Array.isArray(value) ? value.join(", ") : String(value ?? "");
  }
  return {
    httpMethod: req.method,
    path: url.pathname,
    headers,
    queryStringParameters: Object.fromEntries(url.searchParams),
    body: Buffer.isBuffer(req.rawBody) ? req.rawBody.toString("utf8") : "",
    isBase64Encoded: false,
  };
}

function send(res, status, headers, body) {
  res.status(status);
  for (const [key, value] of Object.entries(headers || {})) res.setHeader(key, value);
  // Answers are never kept by the website's cache.
  if (!res.getHeader("Cache-Control")) res.setHeader("Cache-Control", "no-store");
  res.end(body ?? "");
}

function sendJson(res, status, value) {
  send(res, status, { ...CORS, "Content-Type": "application/json" }, JSON.stringify(value));
}

export const api = onRequest(
  { region: "us-central1", invoker: "public", secrets: [SETTINGS], maxInstances: 10 },
  async (req, res) => {
    try {
      const url = new URL(req.originalUrl || req.url || "/", "http://localhost");
      const name = url.pathname.split("/").filter(Boolean).pop() || "";
      loadSettings();
      if (!NAMES.has(name)) {
        // The bare address (or /status) says it's up; the deploy job checks it.
        if (["", "api", "functions", "status"].includes(name)) return sendJson(res, 200, { ok: true, server: "firebase", functions: [...NAMES].sort(), settings: settingsCount });
        return sendJson(res, 404, { error: "There's no such part of the Sugerly server." });
      }
      const handler = await handlerFor(name);
      const out = (await handler(netlifyEvent(req, url), {})) || { statusCode: 204 };
      const headers = { ...(out.headers || {}), ...(out.multiValueHeaders || {}) };
      send(res, out.statusCode || 200, headers, out.isBase64Encoded ? Buffer.from(out.body || "", "base64") : out.body);
    } catch (e) {
      console.error(e);
      if (!res.headersSent) sendJson(res, 500, { error: `Something went wrong on the server (${String(e?.message || e).slice(0, 140)}). Please try again.` });
    }
  },
);

export { accountChatCleanup } from "./account-cleanup.js";
