import { Capacitor } from "@capacitor/core";

// Sugerly is an iPhone / iPad app. The public website (netlify.toml sets
// VITE_LEGAL_SITE) only hosts Help & legal: the App Store's privacy policy
// and support links point there.
export const LEGAL_SITE = import.meta.env.VITE_LEGAL_SITE === "true" && !Capacitor.isNativePlatform();
