// Publishes firestore.rules and storage.rules to the Firebase project, using
// the service account key in the FIREBASE_SERVICE_ACCOUNT environment
// variable (the JSON file from Firebase console → Project settings →
// Service accounts → Generate new private key).
//
// Run by .github/workflows/firebase-rules.yml; locally:
//   FIREBASE_SERVICE_ACCOUNT="$(cat key.json)" node scripts/deploy-rules.mjs
import { readFileSync } from "node:fs";
import { cert, initializeApp } from "firebase-admin/app";
import { getSecurityRules } from "firebase-admin/security-rules";
import { readKey } from "./firebase-key.mjs";

let key;
try { key = readKey(); } catch (e) {
  console.error(e.message);
  process.exit(1);
}
const env = Object.fromEntries(readFileSync(".env", "utf8").split("\n").filter((l) => /^\w+=/.test(l)).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim()]));
const projectId = key.project_id;
if (env.VITE_FIREBASE_PROJECT_ID && env.VITE_FIREBASE_PROJECT_ID !== projectId) {
  console.error(`The key is for "${projectId}" but the app uses "${env.VITE_FIREBASE_PROJECT_ID}". Generate the key in the right project.`);
  process.exit(1);
}
const bucket = env.VITE_FIREBASE_STORAGE_BUCKET || `${projectId}.appspot.com`;

initializeApp({ credential: cert(key), projectId, storageBucket: bucket });
const rules = getSecurityRules();

const firestore = await rules.releaseFirestoreRulesetFromSource(readFileSync("firestore.rules", "utf8"));
console.log(`✓ Firestore rules published to ${projectId} (${firestore.name})`);

try {
  const storage = await rules.releaseStorageRulesetFromSource(readFileSync("storage.rules", "utf8"), bucket);
  console.log(`✓ Storage rules published to ${bucket} (${storage.name})`);
} catch (e) {
  // Storage has to be switched on in the console once before it has rules.
  console.error(`✗ Storage rules: ${e.message}\n  If Storage isn't set up yet, open Firebase console → Storage → Get started, then run this again.`);
  process.exitCode = 1;
}
