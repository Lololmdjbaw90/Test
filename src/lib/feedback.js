// Haptics and little UI sounds.
// -----------------------------------------------------------------------------
//   feedback("like")   → a medium tap on iPhone/iPad + a soft "pop"
//
// Haptics use the native Taptic Engine in the iOS app (Capacitor Haptics) and
// a short vibration on Android browsers. Sounds are tiny synthesized tones
// (Web Audio, no files to download); on iPhone and iPad they follow the
// silent switch. Both can be switched off in Settings → Sounds & haptics.
// -----------------------------------------------------------------------------
import { useEffect, useState } from "react";
import { Capacitor } from "@capacitor/core";
import { Haptics, ImpactStyle, NotificationType } from "@capacitor/haptics";

const KEY = "mimilocks:__feedback";
const EVENT = "mimilocks:feedback";
const DEFAULTS = { sounds: true, haptics: true };

export function getFeedbackPrefs() {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") }; } catch { return { ...DEFAULTS }; }
}
export function setFeedbackPrefs(patch) {
  const next = { ...getFeedbackPrefs(), ...patch };
  try { localStorage.setItem(KEY, JSON.stringify(next)); } catch { /* private mode */ }
  window.dispatchEvent(new CustomEvent(EVENT, { detail: next }));
  return next;
}
export function useFeedbackPrefs() {
  const [prefs, setPrefs] = useState(getFeedbackPrefs);
  useEffect(() => {
    const on = (e) => setPrefs(e.detail || getFeedbackPrefs());
    window.addEventListener(EVENT, on);
    return () => window.removeEventListener(EVENT, on);
  }, []);
  return [prefs, setFeedbackPrefs];
}

// ---------- haptics ----------
const native = () => Capacitor.isNativePlatform();
const HAPTIC_OF = {
  tap: "light", tab: "selection", toggle: "selection", like: "medium", unlike: "light", save: "light",
  send: "light", success: "success", error: "error", notify: "medium", swipe: "selection",
};

// haptic("light" | "medium" | "heavy" | "selection" | "success" | "warning" | "error")
export function haptic(kind = "light") {
  if (!getFeedbackPrefs().haptics) return;
  try {
    if (native()) {
      if (kind === "success" || kind === "warning" || kind === "error") {
        Haptics.notification({ type: kind === "success" ? NotificationType.Success : kind === "warning" ? NotificationType.Warning : NotificationType.Error });
      } else if (kind === "selection") {
        Haptics.selectionStart().then(() => Haptics.selectionChanged()).then(() => Haptics.selectionEnd()).catch(() => {});
      } else {
        Haptics.impact({ style: kind === "heavy" ? ImpactStyle.Heavy : kind === "medium" ? ImpactStyle.Medium : ImpactStyle.Light });
      }
    } else if (navigator.userActivation?.hasBeenActive) {
      navigator.vibrate?.(kind === "error" ? [20, 40, 20] : kind === "medium" || kind === "success" ? 18 : 8);
    }
  } catch { /* haptics are best-effort */ }
}

// ---------- sounds ----------
// Each sound is a few short tones: [frequency, glide-to, start offset, length, wave, volume].
const SOUNDS = {
  tap: [[1800, 0, 0, 0.03, "triangle", 0.03]],
  tab: [[1320, 0, 0, 0.035, "triangle", 0.035]],
  swipe: [[1100, 1500, 0, 0.04, "triangle", 0.03]],
  toggle: [[880, 1320, 0, 0.05, "triangle", 0.045]],
  like: [[620, 980, 0, 0.09, "sine", 0.09], [1318, 0, 0.06, 0.13, "sine", 0.05]],
  unlike: [[720, 460, 0, 0.08, "sine", 0.05]],
  save: [[520, 780, 0, 0.07, "triangle", 0.06], [1040, 0, 0.05, 0.07, "sine", 0.03]],
  send: [[560, 1250, 0, 0.12, "sine", 0.06]],
  success: [[784, 0, 0, 0.1, "sine", 0.06], [1175, 0, 0.08, 0.18, "sine", 0.06]],
  notify: [[988, 0, 0, 0.12, "sine", 0.06], [1319, 0, 0.1, 0.22, "sine", 0.05]],
  error: [[330, 250, 0, 0.13, "triangle", 0.06], [247, 0, 0.12, 0.15, "triangle", 0.05]],
};

let ctx = null;
let master = null;
function audio(create) {
  if (!ctx) {
    if (!create) return null;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    try {
      ctx = new AC();
      master = ctx.createGain();
      master.gain.value = 0.9;
      master.connect(ctx.destination);
    } catch { ctx = null; return null; }
  }
  if (ctx.state === "suspended") ctx.resume().catch(() => {});
  return ctx;
}

// Browsers only allow sound after the person has touched the page; get the
// audio engine ready on the first touch so later sounds (like a new
// notification) can play too.
if (typeof window !== "undefined") {
  const unlock = () => { if (getFeedbackPrefs().sounds) audio(true); window.removeEventListener("pointerdown", unlock, true); };
  window.addEventListener("pointerdown", unlock, true);
}

const lastPlayed = {};
export function playSound(name) {
  const tones = SOUNDS[name];
  if (!tones || !getFeedbackPrefs().sounds || document.hidden) return;
  const now = performance.now();
  if (now - (lastPlayed[name] || 0) < 60) return; // don't stack the same sound
  lastPlayed[name] = now;
  const ac = audio(navigator.userActivation ? navigator.userActivation.hasBeenActive : true);
  if (!ac || ac.state !== "running") return;
  const t = ac.currentTime + 0.005;
  tones.forEach(([f, f2, start, len, wave, vol]) => {
    const osc = ac.createOscillator();
    const gain = ac.createGain();
    osc.type = wave;
    osc.frequency.setValueAtTime(f, t + start);
    if (f2) osc.frequency.exponentialRampToValueAtTime(f2, t + start + len);
    gain.gain.setValueAtTime(0.0001, t + start);
    gain.gain.exponentialRampToValueAtTime(vol, t + start + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + start + len);
    osc.connect(gain).connect(master);
    osc.start(t + start);
    osc.stop(t + start + len + 0.03);
  });
}

// One call for both: feedback("like"), feedback("send"), feedback("notify")…
export function feedback(name) {
  haptic(HAPTIC_OF[name] || "light");
  playSound(name);
}
