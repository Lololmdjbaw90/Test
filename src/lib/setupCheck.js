// Checks that the Firebase project has this version's security rules.
// Every release that adds a collection (like Reel or AppUpdate) needs the
// rules re-published; until then the server answers "Missing or insufficient
// permissions". Admins see a card explaining the 2-minute fix.
import { useEffect, useState } from "react";
import { base44, backendMode } from "@/api/base44Client";
import firestoreRules from "../../firestore.rules?raw";
import storageRules from "../../storage.rules?raw";

export { firestoreRules, storageRules };
export const projectId = import.meta.env.VITE_FIREBASE_PROJECT_ID || "";
export const consoleLinks = {
  firestore: `https://console.firebase.google.com/project/${projectId}/firestore/rules`,
  storage: `https://console.firebase.google.com/project/${projectId}/storage`,
};

const isDenied = (e) => /permission|insufficient/i.test(`${e?.code || ""} ${e?.message || ""}`);

let cached = null;
export async function checkRules() {
  if (backendMode !== "firebase") return { ok: true, local: true };
  if (cached) return cached;
  const probes = [["Reel", () => base44.entities.Reel.list(null, 1)], ["AppUpdate", () => base44.entities.AppUpdate.list(null, 1)]];
  const missing = [];
  for (const [name, run] of probes) {
    try { await run(); } catch (e) { if (isDenied(e)) missing.push(name); }
  }
  cached = { ok: missing.length === 0, missing };
  return cached;
}
export function resetRulesCheck() { cached = null; }

export function useRulesCheck(enabled = true, nonce = 0) {
  const [state, setState] = useState(null);
  useEffect(() => {
    if (!enabled) return undefined;
    let alive = true;
    checkRules().then((r) => { if (alive) setState(r); }).catch(() => {});
    return () => { alive = false; };
  }, [enabled, nonce]);
  return state;
}
