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
const ROSE = "#d9577f";

export function getStoredTheme() {
  try { return JSON.parse(localStorage.getItem(KEY) || "{}"); } catch { return {}; }
}

// ---- colour maths -----------------------------------------------------------

export function hexToRgb(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || "").trim());
  if (!m) return null;
  const v = parseInt(m[1], 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

export function rgbToHex([r, g, b]) {
  return "#" + [r, g, b].map((x) => Math.round(Math.max(0, Math.min(255, x))).toString(16).padStart(2, "0")).join("");
}

// Hue 0-360, saturation + value 0-1 (same as iOS getHue).
function rgbToHsv([r, g, b]) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return [h, max ? d / max : 0, max];
}

function hsvToRgb(h, s, v) {
  h = ((h % 360) + 360) % 360;
  const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
}

function rgbToHslString([r, g, b]) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  let h = 0, s = 0;
  if (d) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;
  }
  return `${Math.round(h)} ${Math.round(s * 100)}% ${Math.round(l * 100)}%`;
}

// The CSS filter that turns the rose artwork (logo, Mimi) to another colour:
// rotate the hue from rose and match how strong the colour is.
export function tintFilter(mainHex) {
  const target = hexToRgb(mainHex);
  if (!target) return "none";
  const [h0, s0] = rgbToHsv(hexToRgb(ROSE));
  const [h1, s1] = rgbToHsv(target);
  const sat = Math.max(0, Math.min(1.5, s1 / Math.max(s0, 0.01)));
  return `hue-rotate(${Math.round(h1 - h0)}deg) saturate(${sat.toFixed(2)})`;
}

// Sub tones that go with a main colour: lighter, its neighbours on the
// colour wheel, a soft opposite and a deeper shade.
export function subToneIdeas(mainHex) {
  const rgb = hexToRgb(mainHex);
  if (!rgb) return [];
  const [h, s, v] = rgbToHsv(rgb);
  const tone = (dh, ds, dv) => rgbToHex(hsvToRgb(h + dh, Math.max(0, Math.min(1, s * ds)), Math.max(0, Math.min(1, v + dv))));
  return [tone(0, 0.5, 0.15), tone(25, 0.8, 0.1), tone(-25, 0.8, 0.1), tone(180, 0.45, 0.12), tone(0, 1, -0.22)];
}

// Your own colours win; then the admin's site colours, unless you picked a
// preset other than rose. Returns { main, sub } or null.
export function resolveCustom(user, siteConfig) {
  if (hexToRgb(user?.accent_main)) return { main: user.accent_main, sub: hexToRgb(user.accent_sub) ? user.accent_sub : user.accent_main };
  const accent = user?.accent || "rose";
  if (accent === "rose" && hexToRgb(siteConfig?.app_primary)) {
    return { main: siteConfig.app_primary, sub: hexToRgb(siteConfig.app_secondary) ? siteConfig.app_secondary : siteConfig.app_primary };
  }
  return null;
}

const CUSTOM_PROPS = ["--accent-rgb", "--accent-2-rgb", "--primary", "--ring", "--art-filter"];

// CSS variables for a custom colour (also saved, so index.html can apply
// them before first paint).
function customVars(custom) {
  const main = hexToRgb(custom?.main);
  if (!main) return null;
  const sub = hexToRgb(custom.sub) || main;
  return {
    "--accent-rgb": main.join(" "),
    "--accent-2-rgb": sub.join(" "),
    "--primary": rgbToHslString(main),
    "--ring": rgbToHslString(main),
    "--art-filter": tintFilter(custom.main),
  };
}

function applyCustom(vars) {
  const root = document.documentElement;
  CUSTOM_PROPS.forEach((p) => root.style.removeProperty(p));
  if (!vars) { root.removeAttribute("data-custom"); return; }
  Object.entries(vars).forEach(([k, v]) => root.style.setProperty(k, v));
  root.setAttribute("data-custom", "1");
}

let mediaListener = null;

// `custom` is { main, sub } (hex), null to clear it, or left out to keep the
// last one.
export function applyTheme({ theme, accent, custom } = {}) {
  const stored = getStoredTheme();
  const next = {
    theme: theme || stored.theme || "light",
    accent: accent || stored.accent || "rose",
    custom: custom === undefined ? stored.custom || null : custom,
  };
  next.vars = customVars(next.custom);
  const root = document.documentElement;
  const media = window.matchMedia?.("(prefers-color-scheme: dark)");
  const isDark = next.theme === "dark" || (next.theme === "system" && media?.matches);
  root.classList.toggle("dark", !!isDark);
  root.setAttribute("data-accent", next.accent);
  applyCustom(next.vars);
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
