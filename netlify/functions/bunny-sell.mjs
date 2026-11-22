import { body, handle, Problem, sellBunnyItem, signedInUser } from "../lib/sugerly.mjs";
export const handler = event => handle(event, async () => {
  if (event.httpMethod !== "POST") throw new Problem(405, "Use POST.");
  return sellBunnyItem(await signedInUser(event), body(event));
}, "creator shop");
