// Reads the Firebase service-account key from the environment, in whichever
// form it was saved as a GitHub secret:
//   - FIREBASE_SERVICE_ACCOUNT: the whole key file (JSON), even if the line
//     breaks got lost when pasting, or the same file base64-encoded;
//   - or two smaller secrets, FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY
//     (the "client_email" and "private_key" values from the key file), plus
//     FIREBASE_PROJECT_ID if it isn't the Sugerly project.
//
// `node scripts/firebase-key.mjs > key.json` writes the key as a file (for
// tools that want GOOGLE_APPLICATION_CREDENTIALS).

const DEFAULT_PROJECT = "umikoworks-86333";

// Rebuilds the PEM block when the line breaks became spaces or "\n" text.
function fixPem(pem) {
  const text = String(pem || "").replace(/\\n/g, "\n").trim();
  const m = /-----BEGIN PRIVATE KEY-----([\s\S]*?)-----END PRIVATE KEY-----/.exec(text);
  if (!m) return text;
  const body = m[1].replace(/\s+/g, "");
  const lines = body.match(/.{1,64}/g) || [];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
}

function parseJson(raw) {
  const text = String(raw || "").trim();
  if (!text) return null;
  if (text.startsWith("{")) return JSON.parse(text);
  // One-line base64 version of the file.
  const decoded = Buffer.from(text, "base64").toString("utf8").trim();
  if (decoded.startsWith("{")) return JSON.parse(decoded);
  throw new Error("not JSON");
}

export function readKey() {
  let key = null;
  try {
    key = parseJson(process.env.FIREBASE_SERVICE_ACCOUNT);
  } catch {
    throw new Error("FIREBASE_SERVICE_ACCOUNT isn't a valid key. Paste the whole key file (it starts with { and ends with }), or use FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY instead.");
  }
  if (!key && process.env.FIREBASE_PRIVATE_KEY) {
    key = {
      type: "service_account",
      project_id: (process.env.FIREBASE_PROJECT_ID || "").trim() || DEFAULT_PROJECT,
      client_email: (process.env.FIREBASE_CLIENT_EMAIL || "").trim() || `firebase-adminsdk-fbsvc@${DEFAULT_PROJECT}.iam.gserviceaccount.com`,
      private_key: process.env.FIREBASE_PRIVATE_KEY,
    };
  }
  if (!key) throw new Error("No Firebase key: add the FIREBASE_SERVICE_ACCOUNT secret (see .github/workflows/firebase-rules.yml).");
  key.private_key = fixPem(key.private_key);
  key.project_id = key.project_id || DEFAULT_PROJECT;
  if (!key.client_email || !key.private_key.includes("BEGIN PRIVATE KEY")) throw new Error("The Firebase key is missing client_email or private_key.");
  return key;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    process.stdout.write(JSON.stringify(readKey()));
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
