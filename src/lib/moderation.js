import { base44 } from "@/api/base44Client";
import { sendModerationStrike } from "@/utils/discordWebhook";
import { analyze, moderationReasons } from "@/lib/modEngine";
import { moderateWithAI } from "@/lib/ai";
import { toast } from "@/lib/toast";

// Everything people write goes through here before it's saved:
//  1. a mute (from earlier strikes, or set by an admin) stops all posting;
//  2. cooldowns (slow mode) stop floods: a short gap between sends and a
//     cap per minute/hour, depending on where the text goes;
//  3. the same text twice in a row is caught;
//  4. the word filter (modEngine.js) decides clear cases on the device;
//  5. anything borderline gets a second opinion from Gemini when AI is on;
//  6. blocked bad behaviour adds strikes; strikes in the last day add up to
//     longer and longer mutes (2 min, 10 min, 1 h, 24 h).
// The iOS app does exactly the same (App/Moderation.swift).
//
//   const mod = await checkText(text, { user, where: "comment", kind: "comment" });
//   if (!mod.safe) toast.error(mod.reason);

// How often you can send, by where the text goes (seconds).
const LIMITS = {
  message: { gap: 0.8, burst: 8, window: 10 },
  comment: { gap: 4, burst: 6, window: 60 },
  post: { gap: 30, burst: 5, window: 3600 },
  caption: { gap: 30, burst: 8, window: 3600 },
  profile: { gap: 3, burst: 10, window: 600 },
  name: { gap: 2, burst: 20, window: 600 },
};
// Strike points in the last 24 hours -> how long you're muted.
const LADDER = [[8, 24 * 3600], [5, 3600], [3, 600], [2, 120]];
const AI_STRIKE = { hate: 2, threat: 2, sexual: 2, harassment: 1, scam: 1 };
const DAY = 86_400_000;

function kindOf(where = "") {
  const w = String(where).toLowerCase();
  if (w.includes("direct message") || w.startsWith("#") || w.includes("message") || w.includes("chat")) return "message";
  if (w.includes("comment")) return "comment";
  if (w.includes("name")) return "name";
  if (w.includes("bio") || w.includes("profile") || w.includes("status")) return "profile";
  if (w.includes("caption") || w.includes("reel") || w.includes("music") || w.includes("artwork") || w.includes("commission")) return "caption";
  return "post";
}

const keyFor = (user) => `sugerly:mod:${String(user?.email || "anon").toLowerCase()}`;
function load(user) {
  try { return JSON.parse(localStorage.getItem(keyFor(user)) || "{}") || {}; } catch { return {}; }
}
function save(user, state) {
  try { localStorage.setItem(keyFor(user), JSON.stringify(state)); } catch { /* private mode */ }
}

export function formatWait(ms) {
  const s = Math.max(1, Math.ceil(ms / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.ceil(s / 60);
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  return `${h} h${m % 60 ? ` ${m % 60} min` : ""}`;
}

// When you'll be able to post again (0 = now).
export function mutedUntil(user) {
  return Math.max(Number(load(user).mutedUntil) || 0, Number(user?.muted_until_ms) || 0);
}

function cooldownLeft(state, kind, now) {
  const limit = LIMITS[kind];
  const times = (state.actions?.[kind] || []).filter((t) => now - t < limit.window * 1000);
  const last = times[times.length - 1] || 0;
  if (now - last < limit.gap * 1000) return limit.gap * 1000 - (now - last);
  if (times.length >= limit.burst) return times[0] + limit.window * 1000 - now;
  return 0;
}

function record(state, kind, text, now) {
  const limit = LIMITS[kind];
  state.actions = state.actions || {};
  state.actions[kind] = [...(state.actions[kind] || []).filter((t) => now - t < limit.window * 1000), now].slice(-50);
  if (text) {
    state.recent = state.recent || {};
    state.recent[kind] = [...(state.recent[kind] || []).filter((r) => now - r.t < 120_000), { t: now, text }].slice(-10);
  }
}

// Adds strike points and works out the mute. Returns the mute end (ms) or 0.
async function strike(user, state, points, now) {
  if (!points) return 0;
  state.strikes = [...(state.strikes || []).filter((s) => now - s.t < DAY), { t: now, w: points }];
  const recent = state.strikes.reduce((sum, s) => sum + s.w, 0);
  const step = LADDER.find(([min]) => recent >= min);
  const until = step ? now + step[1] * 1000 : 0;
  if (until > (state.mutedUntil || 0)) state.mutedUntil = until;
  // The account keeps the count too, so the mute follows you to other devices
  // (the database rules only let these numbers go up, and stop posting while muted).
  const patch = { mod_strikes: (Number(user?.mod_strikes) || 0) + points };
  if (until > (Number(user?.muted_until_ms) || 0)) patch.muted_until_ms = until;
  base44.auth.updateMe?.(patch).catch(() => {});
  return until;
}

const withMute = (reason, until, now) => (until > now ? `${reason} You're on a cooldown for ${formatWait(until - now)}.` : reason);
const simple = (text) => String(text || "").toLowerCase().replace(/\s+/g, " ").trim();

export async function checkText(text, { user, where, kind, skipCooldown = false } = {}) {
  const clean = String(text || "").trim();
  const k = kind || kindOf(where);
  if (!user) return { safe: true, reason: "" };
  const now = Date.now();
  const state = load(user);

  // 1. muted?
  const until = mutedUntil(user);
  if (until > now) return { safe: false, reason: `You're on a cooldown for ${formatWait(until - now)} because of earlier messages.` };

  // 2. slow mode (admins skip it)
  if (!skipCooldown && user.role !== "admin") {
    const wait = cooldownLeft(state, k, now);
    if (wait > 0) return { safe: false, reason: `Slow down! You can send again in ${formatWait(wait)}.` };
  }

  if (!clean) {
    if (!skipCooldown) { record(state, k, "", now); save(user, state); }
    return { safe: true, reason: "" };
  }

  // 3. the same thing again
  if (["message", "comment", "post"].includes(k) && clean.length >= 4
    && (state.recent?.[k] || []).some((r) => now - r.t < 90_000 && r.text === simple(clean))) {
    return { safe: false, reason: moderationReasons.duplicate };
  }

  // 4. word filter
  const local = analyze(clean, k);
  if (local.blocked) {
    const mute = await strike(user, state, local.strike, now);
    save(user, state);
    if (local.strike) sendModerationStrike({ userEmail: user.email, displayName: user.display_name, reason: `${local.category}${where ? ` (${where})` : ""}`, content: clean });
    return { safe: false, reason: withMute(local.reason, mute, now), category: local.category };
  }

  // 5. AI second opinion on borderline text
  let support = local.support;
  if (local.needsAI) {
    const ai = await moderateWithAI(clean, { where: where || k, signals: local.signals });
    if (ai?.verdict === "block" && Number(ai.severity) >= 0.5 && ai.category !== "self_harm") {
      const mute = await strike(user, state, AI_STRIKE[ai.category] || 0, now);
      save(user, state);
      sendModerationStrike({ userEmail: user.email, displayName: user.display_name, reason: `AI: ${ai.category}${where ? ` (${where})` : ""}`, content: clean });
      return { safe: false, reason: withMute(String(ai.reason || moderationReasons[ai.category] || moderationReasons.spam).slice(0, 140), mute, now), category: ai.category };
    }
    support ||= !!ai?.support;
  }

  if (support) toast(moderationReasons.support);
  if (!skipCooldown) record(state, k, simple(clean), now);
  save(user, state);
  return { safe: true, reason: "" };
}

// Links aren't allowed in reel captions or bios (spam and scam protection).
const LINK = /(https?:\/\/|www\.|\b[a-z0-9-]{2,}\.(com|net|org|io|gg|co|me|ly|xyz|app|dev|tv|link|site|shop|info|biz|ru|to|cc|us|uk|it|de|fr|es)\b|discord\.gg|t\.me\/)/i;
export const hasLink = (text) => LINK.test(String(text || ""));
