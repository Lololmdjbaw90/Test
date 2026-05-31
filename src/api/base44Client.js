// Every page talks to this `base44` object.
// If Firebase env vars are present, it uses real Firebase Auth/Firestore/Storage.
// If not, it falls back to the local browser backend so the project still runs.
import { createLocalClient } from "./localBackend";
import { createFirebaseClient, hasFirebaseConfig } from "./firebaseBackend";

export const base44 = hasFirebaseConfig() ? createFirebaseClient() : createLocalClient();
export const backendMode = hasFirebaseConfig() ? "firebase" : "local";
