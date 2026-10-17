// The server's settings for Firebase (the SUGERLY_ENV secret, see
// functions/index.js), made from the GitHub secrets the deploy job passes in:
// the Firebase key plus the same values Netlify has. Writes them as JSON to
// the file it's given, for `firebase functions:secrets:set`; the job's log
// only gets the names.
import { writeFileSync } from "node:fs";
import { readKey } from "./firebase-key.mjs";

const file = process.argv[2];
if (!file) throw new Error("Usage: node scripts/server-settings.mjs <file.json>");

const NAMES = [
  "STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET",
  "BREVO_API_KEY", "RESEND_API_KEY", "MAIL_FROM",
  "APNS_KEY", "APNS_KEY_ID", "APPLE_TEAM_ID",
  "CLOUDFLARE_TURN_KEY_ID", "CLOUDFLARE_TURN_API_TOKEN", "METERED_TURN_APP", "METERED_TURN_API_KEY",
  "LOGIN_SECRET", "SITE_URL", "FIREBASE_WEB_API_KEY",
];

const key = readKey();
const settings = {
  FIREBASE_SERVICE_ACCOUNT: JSON.stringify(key),
  FIREBASE_PROJECT_ID: key.project_id,
  // Payment pages and email pictures come from the Firebase website.
  SITE_URL: `https://${key.project_id}.web.app`,
  SUGERLY_SETTINGS: "GitHub",
};
for (const name of NAMES) {
  const value = String(process.env[name] || "").trim();
  if (value) settings[name] = value;
}
writeFileSync(file, JSON.stringify(settings), { mode: 0o600 });
console.log(`Server settings: ${Object.keys(settings).join(", ")}`);
const missing = ["STRIPE_SECRET_KEY", "MAIL_FROM", "APNS_KEY"].filter((name) => !settings[name]);
if (missing.length) console.log(`::warning title=Some server settings are empty::${missing.join(", ")}. Add them as GitHub secrets if you use them (see .github/workflows/firebase-server.yml).`);
