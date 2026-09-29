// Checks with Stripe whether a checkout was paid and, if so, marks the order
// paid. Called by the "payment done" page (with the session id) and by the
// app when you come back from paying (with the order id).
import { Problem, body, getDoc, handle, settle, signedInUser, stripe } from "../lib/sugerly.mjs";

export const handler = (event) => handle(event, async () => {
  const input = { ...(event.queryStringParameters || {}), ...body(event) };
  let sessionId = input.session_id;
  if (!sessionId && input.orderId) {
    const user = await signedInUser(event);
    const order = await getDoc("CommissionOrder", input.orderId);
    if (!order) throw new Problem(404, "That order doesn't exist anymore.");
    if (![order.buyer_email, order.artist_email].includes(user.email)) throw new Problem(403, "Not your order.");
    if (!order.stripe_session_id) return { status: order.status, orderId: order.id };
    sessionId = order.stripe_session_id;
  }
  if (!sessionId || !/^cs_[A-Za-z0-9_]+$/.test(sessionId)) throw new Problem(400, "Missing payment.");
  const session = await stripe(`checkout/sessions/${sessionId}`, null, "GET");
  return settle(session);
});
