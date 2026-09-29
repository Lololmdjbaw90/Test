// Admins only: refunds a paid order through Stripe and marks it refunded.
import { Problem, body, getDoc, handle, isAdmin, notify, signedInUser, stripe, updateDoc } from "../lib/sugerly.mjs";

export const handler = (event) => handle(event, async () => {
  if (event.httpMethod !== "POST") throw new Problem(405, "Use POST.");
  const user = await signedInUser(event);
  if (!(await isAdmin(user))) throw new Problem(403, "Only admins can refund.");
  const { orderId } = body(event);
  const order = await getDoc("CommissionOrder", orderId);
  if (!order) throw new Problem(404, "That order doesn't exist anymore.");
  if (order.status === "refunded") return { status: "refunded" };
  if (!order.payment_intent) throw new Problem(409, "This order wasn't paid by card.");
  if (order.payout_status === "paid_out") throw new Problem(409, "The artist was already paid for this one — refund it in Stripe by hand.");
  await stripe("refunds", { payment_intent: order.payment_intent, "metadata[order_id]": order.id });
  const now = new Date().toISOString();
  await updateDoc("CommissionOrder", order.id, { status: "refunded", refunded_at: now, updated_date: now });
  const from = { email: user.email, name: "Sugerly" };
  await notify(order.buyer_email, from, `Your payment for "${order.commission_title}" was refunded.`, `/Commissions?order=${order.id}`);
  await notify(order.artist_email, from, `The order "${order.commission_title}" was refunded to the buyer.`, `/Commissions?order=${order.id}`);
  return { status: "refunded" };
});
