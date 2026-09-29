// Card payments for commissions, through the payment server on this site
// (netlify/functions). The server checks who you are with your login token.
import { base44 } from "@/api/base44Client";

export const CURRENCIES = ["usd", "eur", "gbp", "cad", "aud"];

export function money(amount, currency = "usd") {
  const n = Number(amount) || 0;
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: String(currency || "usd").toUpperCase(), maximumFractionDigits: Number.isInteger(n) ? 0 : 2 }).format(n);
  } catch {
    return `$${n}`;
  }
}

export async function callPayments(name, body) {
  const user = base44.firebase?.auth?.currentUser;
  if (!user) throw new Error("Please log in again.");
  const token = await user.getIdToken();
  const res = await fetch(`/.netlify/functions/${name}`, {
    method: "POST",
    // Not the Authorization header: Netlify can answer that one itself.
    headers: { "Content-Type": "application/json", "X-Sugerly-Token": token },
    body: JSON.stringify(body || {}),
  });
  const data = await res.json().catch(() => ({}));
  // A 404 without our JSON means the payment server isn't deployed at all.
  if (res.status === 404 && !data.error) throw new Error("Card payments aren't switched on yet (the payment server isn't deployed). Ask the Sugerly team.");
  if (!res.ok) throw new Error((typeof data.error === "string" && data.error) || data.msg || `Payments aren't available right now (${res.status}).`);
  return data;
}

export const ORDER_STATUS = {
  requested: { label: "Requested", color: "#7c5cf0", step: 0 },
  accepted: { label: "Waiting for payment", color: "#f0a020", step: 1 },
  paid: { label: "Paid", color: "#2f80e0", step: 2 },
  in_progress: { label: "In progress", color: "#2f80e0", step: 3 },
  delivered: { label: "Delivered", color: "#e8457c", step: 4 },
  refund_requested: { label: "Refund asked", color: "#e0526b", step: 4 },
  completed: { label: "Completed", color: "#17a673", step: 5 },
  declined: { label: "Declined", color: "#94a3b8", step: -1 },
  cancelled: { label: "Cancelled", color: "#94a3b8", step: -1 },
  refunded: { label: "Refunded", color: "#94a3b8", step: -1 },
};

export const isActiveOrder = (o) => !["declined", "cancelled", "completed", "refunded"].includes(o.status);
export const earnings = (o) => (o.artist_earnings != null ? Number(o.artist_earnings) : Number(o.price || 0) * 0.9);
