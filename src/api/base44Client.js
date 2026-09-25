// Every page talks to this `base44` object.
// If Firebase env vars are present it uses real Firebase Auth/Firestore/Storage,
// otherwise it falls back to the local browser backend so the project still runs.
// Set VITE_BACKEND=local to force the local demo backend even when Firebase is configured.
import { createLocalClient } from "./localBackend";
import { createFirebaseClient, hasFirebaseConfig } from "./firebaseBackend";

const forced = String(import.meta.env.VITE_BACKEND || "").toLowerCase();
const useFirebase = forced === "local" ? false : hasFirebaseConfig();

export const base44 = useFirebase ? createFirebaseClient() : createLocalClient();
export const backendMode = useFirebase ? "firebase" : "local";
