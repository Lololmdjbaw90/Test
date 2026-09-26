// Installable app support: service worker registration and install prompts.
// - Android / desktop Chrome & Edge fire `beforeinstallprompt`, which we keep
//   so an "Install" button can open the real install dialog.
// - iPhone / iPad Safari have no prompt: people use Share → Add to Home Screen,
//   so we show those steps instead.
// - Inside the native iOS app (Capacitor) none of this applies.
import { useEffect, useState } from "react";

export const isNativeApp = () => typeof window !== "undefined" && !!window.Capacitor?.isNativePlatform?.();
export const isStandalone = () =>
  typeof window !== "undefined" && (window.matchMedia?.("(display-mode: standalone)").matches || window.navigator.standalone === true);
// iPadOS reports itself as a Mac, so also check for a touch screen.
export const isIOS = () =>
  typeof navigator !== "undefined" && (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1));

let deferredPrompt = null;
const listeners = new Set();
const changed = () => listeners.forEach((fn) => fn());

if (typeof window !== "undefined") {
  window.addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); deferredPrompt = e; changed(); });
  window.addEventListener("appinstalled", () => { deferredPrompt = null; changed(); });
}

export function registerServiceWorker() {
  if (!import.meta.env.PROD || isNativeApp() || typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch((e) => console.warn("[pwa] service worker not registered:", e?.message));
  });
}

export function useInstallApp() {
  const [, rerender] = useState(0);
  useEffect(() => {
    const fn = () => rerender((n) => n + 1);
    listeners.add(fn);
    return () => listeners.delete(fn);
  }, []);
  const installed = isStandalone() || isNativeApp();
  return {
    installed,
    canPrompt: !!deferredPrompt && !installed,
    ios: isIOS() && !installed,
    async prompt() {
      if (!deferredPrompt) return false;
      deferredPrompt.prompt();
      const choice = await deferredPrompt.userChoice.catch(() => null);
      deferredPrompt = null;
      changed();
      return choice?.outcome === "accepted";
    },
  };
}
