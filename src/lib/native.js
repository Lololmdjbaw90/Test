// Native iOS app (Capacitor) integration. Everything here is a no-op in the
// browser, so the same build runs as a website, an installed web app and the
// iPhone / iPad app.
import { Capacitor } from "@capacitor/core";

export const isNative = () => Capacitor.isNativePlatform();

// Haptics live in feedback.js (they follow the Settings → Sounds & haptics
// switch); re-exported here for existing imports.
import { haptic } from "./feedback";
export { haptic };

export async function initNative() {
  if (!isNative()) return;
  document.documentElement.classList.add("native-app");

  // Every tap on a control gets a light haptic, like a native app. Buttons
  // with their own feedback (likes, sends…) fire first and win.
  document.addEventListener("click", (e) => {
    const el = e.target.closest?.('button, a[href], [role="tab"], [role="switch"], [role="option"], [role="menuitem"], input[type="checkbox"], input[type="radio"], summary');
    if (!el || el.disabled || el.getAttribute("aria-disabled") === "true") return;
    haptic(el.matches('[role="tab"], [role="switch"], [role="option"], input[type="checkbox"], input[type="radio"]') ? "selection" : "light");
  });
  const [{ StatusBar, Style }, { Keyboard }] = await Promise.all([import("@capacitor/status-bar"), import("@capacitor/keyboard")]);

  // Status bar text follows the app theme (light text on dark, dark on light).
  const syncStatusBar = (dark) => StatusBar.setStyle({ style: dark ? Style.Dark : Style.Light }).catch(() => {});
  syncStatusBar(document.documentElement.classList.contains("dark"));
  window.addEventListener("mimilocks:theme", (e) => syncStatusBar(e.detail?.dark));

  // Hide the bottom tab bar while the keyboard is up, so the text box has room.
  Keyboard.addListener("keyboardWillShow", () => document.documentElement.classList.add("keyboard-open")).catch?.(() => {});
  Keyboard.addListener("keyboardWillHide", () => document.documentElement.classList.remove("keyboard-open")).catch?.(() => {});
}
