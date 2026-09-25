import { base44 } from "@/api/base44Client";
import { sendModerationStrike } from "@/utils/discordWebhook";

// Runs user text through the moderation integration (the local word filter,
// or an LLM if one is wired up). Returns { safe, reason }.
export async function checkText(text, { user, where } = {}) {
  const clean = String(text || "").trim();
  if (!clean) return { safe: true, reason: "" };
  try {
    const result = await base44.integrations.Core.InvokeLLM({
      prompt: `Content moderator. JSON only. Is this message safe? Text: "${clean}". Flag hate speech, explicit NSFW, violence. {"safe":true/false,"reason":""}`,
      response_json_schema: { type: "object", properties: { safe: { type: "boolean" }, reason: { type: "string" } } },
    });
    if (result && result.safe === false) {
      sendModerationStrike({ userEmail: user?.email, displayName: user?.display_name, reason: `${result.reason || "Blocked"}${where ? ` (${where})` : ""}`, content: clean });
      return { safe: false, reason: result.reason || "That message isn't allowed here." };
    }
  } catch { /* fail open: moderation is best-effort */ }
  return { safe: true, reason: "" };
}
