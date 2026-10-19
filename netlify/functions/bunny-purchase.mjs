import { body, handle, Problem, purchaseBunnyItem, signedInUser } from "../lib/sugerly.mjs";
export const handler = event => handle(event, async () => {
  if (event.httpMethod !== "POST") throw new Problem(405, "Use POST.");
  const user = await signedInUser(event);
  const input = body(event);
  return purchaseBunnyItem(user, String(input.item_id || ""), input.expected_price);
}, "bunny shop");
