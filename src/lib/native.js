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

  // Keyboard: the web view keeps its size (capacitor.config.json: resize
  // "none") and doesn't scroll itself; the page's bottom glides up with the
  // keyboard instead (--kb, see index.css). The tab bar steps aside.
  const root = document.documentElement;
  Keyboard.setScroll?.({ isDisabled: true })?.catch?.(() => {});
  const safeBottom = () => {
    const probe = document.createElement("div");
    probe.style.cssText = "position:absolute;visibility:hidden;pointer-events:none;height:env(safe-area-inset-bottom,0px)";
    document.body.appendChild(probe);
    const h = probe.offsetHeight;
    probe.remove();
    return h;
  };
  Keyboard.addListener("keyboardWillShow", (info) => {
    // The strip under the keyboard's top edge that the home-indicator padding
    // already covers stays behind the keyboard.
    root.style.setProperty("--kb", `${Math.max(0, (info?.keyboardHeight || 0) - safeBottom())}px`);
    root.classList.add("keyboard-open");
  }).catch?.(() => {});
  Keyboard.addListener("keyboardDidShow", () => {
    const el = document.activeElement;
    if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) el.scrollIntoView?.({ block: "nearest" });
  }).catch?.(() => {});
  Keyboard.addListener("keyboardWillHide", () => {
    root.style.setProperty("--kb", "0px");
    root.classList.remove("keyboard-open");
  }).catch?.(() => {});
  Keyboard.addListener("keyboardDidHide", () => { if (window.scrollY) window.scrollTo(0, 0); }).catch?.(() => {});
}
