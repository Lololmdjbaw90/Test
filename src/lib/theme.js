// Theme + accent handling. The choice is stored on the user profile (so it
// follows them across devices) and mirrored to localStorage so the right
// colors are applied before first paint (see the inline script in index.html).

export const ACCENTS = [
  { id: "rose", label: "Rose", swatch: "linear-gradient(135deg,#ee8fae,#d9577f)" },
  { id: "lavender", label: "Lavender", swatch: "linear-gradient(135deg,#b19cff,#7c5cf0)" },
  { id: "mint", label: "Mint", swatch: "linear-gradient(135deg,#5fd3b0,#16a37f)" },
  { id: "peach", label: "Peach", swatch: "linear-gradient(135deg,#ffaa80,#ee6e40)" },
  { id: "sky", label: "Sky", swatch: "linear-gradient(135deg,#7cbeff,#2f80e0)" },
];

export const THEMES = [
  { id: "light", label: "Light" },
  { id: "dark", label: "Dark" },
  { id: "system", label: "System" },
];

const KEY = "mimilocks:__theme";

export function getStoredTheme() {
  try { return JSON.parse(localStorage.getItem(KEY) || "{}"); } catch { return {}; }
}

let mediaListener = null;

export function applyTheme({ theme, accent } = {}) {
  const stored = getStoredTheme();
  const next = { theme: theme || stored.theme || "light", accent: accent || stored.accent || "rose" };
  const root = document.documentElement;
  const media = window.matchMedia?.("(prefers-color-scheme: dark)");
  const isDark = next.theme === "dark" || (next.theme === "system" && media?.matches);
  root.classList.toggle("dark", !!isDark);
  root.setAttribute("data-accent", next.accent);
  if (media) {
    if (mediaListener) media.removeEventListener?.("change", mediaListener);
    mediaListener = next.theme === "system" ? () => applyTheme(next) : null;
    if (mediaListener) media.addEventListener?.("change", mediaListener);
  }
  try { localStorage.setItem(KEY, JSON.stringify(next)); } catch { /* ignore */ }
  // Match the browser / iOS status bar to the app background.
  document.querySelectorAll('meta[name="theme-color"]').forEach((m) => {
    m.setAttribute("content", isDark ? "#110a0f" : "#fbf7f6");
    m.removeAttribute("media");
  });
  window.dispatchEvent(new CustomEvent("mimilocks:theme", { detail: { dark: !!isDark } }));
  return next;
}
