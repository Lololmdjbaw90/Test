// After the buyer approves the finished art (status "completed" with a
// rating), counts the review and the sale on the artist's listing once.
import { Problem, body, getDoc, handle, notify, signedInUser, updateDoc } from "../lib/sugerly.mjs";

export const handler = (event) => handle(event, async () => {
  if (event.httpMethod !== "POST") throw new Problem(405, "Use POST.");
  const user = await signedInUser(event);
  const { orderId } = body(event);
  const order = await getDoc("CommissionOrder", orderId);
  if (!order) throw new Problem(404, "That order doesn't exist anymore.");
  if (order.buyer_email !== user.email) throw new Problem(403, "Not your order.");
  if (order.status !== "completed") throw new Problem(409, "Approve the delivery first.");
  if (order.review_counted) return { ok: true };
  const now = new Date().toISOString();
  await updateDoc("CommissionOrder", order.id, { review_counted: true, updated_date: now });
  const rating = Math.max(0, Math.min(5, Math.round(Number(order.rating) || 0)));
  const listing = await getDoc("Commission", order.commission_id);
  if (listing) {
    const fields = { orders_completed: (Number(listing.orders_completed) || 0) + 1, updated_date: now };
    if (rating > 0) {
      fields.rating_sum = (Number(listing.rating_sum) || 0) + rating;
      fields.rating_count = (Number(listing.rating_count) || 0) + 1;
    }
    await updateDoc("Commission", listing.id, fields);
  }
  await notify(order.artist_email, { email: order.buyer_email, name: order.buyer_name },
    `${order.buyer_name || "Your client"} approved "${order.commission_title}"${rating ? ` and gave you ${rating} star${rating === 1 ? "" : "s"}` : ""}!`,
    `/Commissions?order=${order.id}`);
  return { ok: true };
});
