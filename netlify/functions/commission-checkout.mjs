// Starts a Stripe card checkout for an accepted commission order and returns
// the page to pay on. Only the buyer can pay, and only the agreed price.
import { CURRENCIES, Problem, SITE, body, getDoc, handle, signedInUser, stripe, toMinor, updateDoc } from "../lib/sugerly.mjs";

export const handler = (event) => handle(event, async () => {
  if (event.httpMethod !== "POST") throw new Problem(405, "Use POST.");
  const user = await signedInUser(event);
  const { orderId } = body(event);
  const order = await getDoc("CommissionOrder", orderId);
  if (!order) throw new Problem(404, "That order doesn't exist anymore.");
  if (order.buyer_email !== user.email) throw new Problem(403, "Only the buyer can pay for this order.");
  if (order.status !== "accepted") throw new Problem(409, order.status === "paid" ? "This order is already paid." : "The artist needs to accept the order first.");
  const currency = CURRENCIES.includes(order.currency) ? order.currency : "usd";
  const amount = toMinor(order.price);
  if (!(amount >= 50)) throw new Problem(400, "The price is too low for a card payment.");
  if (amount > 1_000_000) throw new Problem(400, "The price is too high.");

  const session = await stripe("checkout/sessions", {
    mode: "payment",
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": currency,
    "line_items[0][price_data][unit_amount]": String(amount),
    "line_items[0][price_data][product_data][name]": [order.commission_title, order.tier_name].filter(Boolean).join(" · ").slice(0, 250) || "Commission",
    "line_items[0][price_data][product_data][description]": `Commission by ${order.artist_name || "a Sugerly artist"}`.slice(0, 250),
    customer_email: user.email,
    client_reference_id: order.id,
    "metadata[order_id]": order.id,
    "payment_intent_data[metadata][order_id]": order.id,
    "payment_intent_data[description]": `Sugerly commission ${order.id}`,
    success_url: `${SITE}/paid.html?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${SITE}/paid.html?cancelled=1`,
  });
  await updateDoc("CommissionOrder", order.id, { stripe_session_id: session.id, updated_date: new Date().toISOString() });
  return { url: session.url, id: session.id };
});
