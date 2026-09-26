// AI helpers, powered by Gemini through Firebase AI Logic.
// -----------------------------------------------------------------------------
// Nothing to host: the app talks to Gemini with the Firebase project it
// already uses. An admin switches it on once in the Firebase console
// (Build → AI Logic → Get started → Gemini Developer API); Admin → Site has a
// "Test AI" button. The SDK is only downloaded the first time someone uses AI.
// -----------------------------------------------------------------------------
import { base44, backendMode } from "@/api/base44Client";

export const aiAvailable = backendMode === "firebase" && String(import.meta.env.VITE_AI || "").toLowerCase() !== "off";
const MODELS = [import.meta.env.VITE_AI_MODEL || "gemini-2.5-flash", "gemini-flash-latest"];

let sdk = null;
async function generate(parts, { schema, temperature = 0.9 } = {}) {
  if (!aiAvailable) throw new Error("AI needs the online version of Sugerly.");
  sdk = sdk || await import("firebase/ai");
  const ai = sdk.getAI(base44.firebase.app, { backend: new sdk.GoogleAIBackend() });
  let lastError;
  for (const name of MODELS) {
    try {
      const model = sdk.getGenerativeModel(ai, {
        model: name,
        generationConfig: { temperature, ...(schema ? { responseMimeType: "application/json", responseSchema: schema } : {}) },
      });
      const result = await model.generateContent(parts);
      const text = result.response.text();
      return schema ? JSON.parse(text) : text;
    } catch (e) {
      lastError = e;
      if (!/not.?found|404|not supported/i.test(String(e?.message))) break; // only retry for a retired model
    }
  }
  throw friendlyAIError(lastError);
}

export function friendlyAIError(e) {
  const msg = String(e?.message || e || "");
  let text = "AI couldn't answer right now. Try again in a moment.";
  if (/api.?(key|has not been used|not enabled|disabled)|SERVICE_DISABLED|API_NOT_ACTIVATED|firebasevertexai|generativelanguage.*(disabled|enable)/i.test(msg)) {
    text = "AI isn't switched on for this app yet — an admin can turn it on in Admin → Site → AI features.";
  } else if (/quota|429|RESOURCE_EXHAUSTED|rate/i.test(msg)) {
    text = "AI is busy right now. Try again in a minute.";
  } else if (/safety|blocked|SAFETY/i.test(msg)) {
    text = "AI didn't want to write about this one — try a different picture.";
  } else if (/network|fetch|offline|Failed to fetch/i.test(msg)) {
    text = "No connection — AI needs the internet.";
  }
  const err = new Error(text);
  err.cause = e;
  err.setup = text.includes("switched on");
  return err;
}

// A picture (File / Blob / URL) → a small JPEG part for Gemini.
async function imagePart(source, max = 768) {
  if (!source) return null;
  let blob = source;
  if (typeof source === "string") blob = await (await fetch(source)).blob();
  try {
    const bmp = await createImageBitmap(blob);
    const scale = Math.min(1, max / Math.max(bmp.width, bmp.height));
    const c = document.createElement("canvas");
    c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale);
    c.getContext("2d").drawImage(bmp, 0, 0, c.width, c.height);
    const data = c.toDataURL("image/jpeg", 0.8).split(",")[1];
    return { inlineData: { mimeType: "image/jpeg", data } };
  } catch {
    return null; // not a picture we can read (e.g. a GIF frame failed) — write from text only
  }
}

const CAPTIONS_SCHEMA = {
  type: "object",
  properties: {
    options: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          caption: { type: "string" },
          hashtags: { type: "array", items: { type: "string" } },
        },
        required: ["caption", "hashtags"],
      },
    },
  },
  required: ["options"],
};

// Three caption ideas for a reel or a Community post:
// [{ title, caption, hashtags: ["art", …] }]
export async function suggestCaptions({ image, kind = "post", draft = "", title = "" } = {}) {
  const pic = await imagePart(image);
  const what = kind === "reel" ? "a short video (this is a frame from it) posted to Reels" : "a post in the Community feed";
  const prompt = [
    "You write captions for Sugerly, a friendly social app for artists (drawings, paintings, music, cosplay, crafts).",
    `Write 3 different caption options for ${what}.`,
    pic ? "Base them on what you see in the picture." : "There is no picture, so work from the draft.",
    draft.trim() || title.trim() ? `The artist's draft: "${[title, draft].filter(Boolean).join(" — ").slice(0, 500)}". Keep their meaning and language.` : "Write in English.",
    "Each caption: at most 140 characters, warm and a bit playful, one emoji at most, no hashtags inside the caption, never mention AI.",
    kind === "post" ? "Also give each option a short title (at most 40 characters)." : "Leave title empty.",
    "Give 2–5 lowercase hashtags per option without the # sign, specific to the art style and subject.",
  ].join("\n");
  const out = await generate([prompt, ...(pic ? [pic] : [])], { schema: CAPTIONS_SCHEMA });
  return (out?.options || [])
    .filter((o) => o?.caption)
    .slice(0, 3)
    .map((o) => ({
      title: String(o.title || "").slice(0, 80),
      caption: String(o.caption).replace(/\s*#\S+/g, "").trim().slice(0, 200),
      hashtags: [...new Set((o.hashtags || []).map((h) => String(h).replace(/^#/, "").toLowerCase().replace(/[^\p{L}\p{N}_]/gu, "")).filter((h) => h.length >= 2))].slice(0, 5),
    }));
}

// Caption text with its hashtags appended, the way the app stores them.
export const withHashtags = (o) => [o.caption, o.hashtags.map((h) => `#${h}`).join(" ")].filter(Boolean).join(" ");

// Admin check: one tiny request.
export async function testAI() {
  const text = await generate(["Reply with the single word: ready"], { temperature: 0 });
  return String(text).trim();
}
