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

// A new version that has downloaded and is waiting to take over.
let waitingWorker = null;
let applying = false;
const updateListeners = new Set();
const setWaiting = (w) => { waitingWorker = w; updateListeners.forEach((fn) => fn()); };

export function registerServiceWorker() {
  if (!import.meta.env.PROD || isNativeApp() || typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").then((reg) => {
      if (reg.waiting && navigator.serviceWorker.controller) setWaiting(reg.waiting);
      reg.addEventListener("updatefound", () => {
        const w = reg.installing;
        w?.addEventListener("statechange", () => { if (w.state === "installed" && navigator.serviceWorker.controller) setWaiting(w); });
      });
      // Look for a new version now and then, and whenever the app comes back.
      const check = () => reg.update().catch(() => {});
      setInterval(check, 30 * 60 * 1000);
      document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") check(); });
    }).catch((e) => console.warn("[pwa] service worker not registered:", e?.message));
    let reloading = false;
    // Reload only when you tapped "Update" (the first install also changes the controller).
    navigator.serviceWorker.addEventListener("controllerchange", () => { if (!applying || reloading) return; reloading = true; window.location.reload(); });
  });
}

// { ready, apply } — apply() switches to the new version and reloads.
export function useAppUpdate() {
  const [, rerender] = useState(0);
  useEffect(() => {
    const fn = () => rerender((n) => n + 1);
    updateListeners.add(fn);
    return () => updateListeners.delete(fn);
  }, []);
  return {
    ready: !!waitingWorker,
    apply() { applying = true; waitingWorker?.postMessage("skip-waiting"); },
  };
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
