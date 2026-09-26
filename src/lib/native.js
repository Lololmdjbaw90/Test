// Native iOS app (Capacitor) integration. Everything here is a no-op in the
// browser, so the same build runs as a website, an installed web app and the
// iPhone / iPad app.
import { Capacitor } from "@capacitor/core";
import { Haptics, ImpactStyle, NotificationType } from "@capacitor/haptics";

export const isNative = () => Capacitor.isNativePlatform();

// Light tap feedback: native haptics in the app, a tiny vibration on Android web.
export function haptic(kind = "light") {
  try {
    if (isNative()) {
      if (kind === "success") Haptics.notification({ type: NotificationType.Success });
      else Haptics.impact({ style: kind === "medium" ? ImpactStyle.Medium : ImpactStyle.Light });
    } else if (navigator.userActivation?.hasBeenActive) {
      navigator.vibrate?.(kind === "medium" ? 18 : 8);
    }
  } catch { /* haptics are best-effort */ }
}

export async function initNative() {
  if (!isNative()) return;
  document.documentElement.classList.add("native-app");
  const [{ StatusBar, Style }, { Keyboard }] = await Promise.all([import("@capacitor/status-bar"), import("@capacitor/keyboard")]);

  // Status bar text follows the app theme (light text on dark, dark on light).
  const syncStatusBar = (dark) => StatusBar.setStyle({ style: dark ? Style.Dark : Style.Light }).catch(() => {});
  syncStatusBar(document.documentElement.classList.contains("dark"));
  window.addEventListener("mimilocks:theme", (e) => syncStatusBar(e.detail?.dark));

  // Hide the bottom tab bar while the keyboard is up, so the text box has room.
  Keyboard.addListener("keyboardWillShow", () => document.documentElement.classList.add("keyboard-open")).catch?.(() => {});
  Keyboard.addListener("keyboardWillHide", () => document.documentElement.classList.remove("keyboard-open")).catch?.(() => {});
}
