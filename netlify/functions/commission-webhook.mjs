// Stripe webhook (optional but recommended): marks orders paid even if the
// buyer closes the page before coming back. In Stripe → Developers →
// Webhooks, add https://sugerly.netlify.app/.netlify/functions/commission-webhook
// for "checkout.session.completed" and put its signing secret in
// STRIPE_WEBHOOK_SECRET.
import crypto from "node:crypto";
import { reply, settle } from "../lib/sugerly.mjs";

function verified(raw, header, secret) {
  const parts = Object.fromEntries(String(header || "").split(",").map((p) => p.split("=")).filter((p) => p.length === 2));
  const signatures = String(header || "").split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  const t = Number(parts.t);
  if (!t || !signatures.length || Math.abs(Date.now() / 1000 - t) > 600) return false;
  const expected = crypto.createHmac("sha256", secret).update(`${t}.${raw}`).digest("hex");
  return signatures.some((s) => s.length === expected.length && crypto.timingSafeEqual(Buffer.from(s), Buffer.from(expected)));
}

export const handler = async (event) => {
  const secret = (process.env.STRIPE_WEBHOOK_SECRET || "").trim();
  if (!secret) return reply(503, { error: "Webhook secret not set." });
  const raw = event.isBase64Encoded ? Buffer.from(event.body || "", "base64").toString("utf8") : event.body || "";
  const header = event.headers?.["stripe-signature"] || event.headers?.["Stripe-Signature"];
  if (!verified(raw, header, secret)) return reply(400, { error: "Bad signature." });
  try {
    const evt = JSON.parse(raw);
    if (evt.type === "checkout.session.completed" || evt.type === "checkout.session.async_payment_succeeded") {
      await settle(evt.data.object);
    }
    return reply(200, { received: true });
  } catch (e) {
    console.error(e);
    return reply(500, { error: "Couldn't handle the event." });
  }
};
