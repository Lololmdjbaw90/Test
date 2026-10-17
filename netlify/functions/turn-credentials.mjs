// Relay (TURN) servers for voice calls. Two phones on different networks
// (e.g. one on mobile data) often can't reach each other directly; a relay
// passes the audio between them. Short-lived logins, only for signed-in people.
//
// Set ONE of these in Netlify → Environment variables:
//   Cloudflare (free up to 1,000 GB a month):
//     CLOUDFLARE_TURN_KEY_ID, CLOUDFLARE_TURN_API_TOKEN
//   Metered.ca:
//     METERED_TURN_APP (the part before .metered.live), METERED_TURN_API_KEY
import { Problem, SETTINGS, handle, signedInUser } from "../lib/sugerly.mjs";

const STUN = [{ urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] }];

async function cloudflare() {
  const id = process.env.CLOUDFLARE_TURN_KEY_ID, token = process.env.CLOUDFLARE_TURN_API_TOKEN;
  if (!id || !token) return null;
  const res = await fetch(`https://rtc.live.cloudflare.com/v1/turn/keys/${id}/credentials/generate-ice-servers`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ttl: 86400 }),
  });
  if (!res.ok) throw new Problem(502, `Call relay (Cloudflare) said ${res.status}. Check the TURN key in ${SETTINGS}.`);
  const data = await res.json();
  const list = Array.isArray(data.iceServers) ? data.iceServers : data.iceServers ? [data.iceServers] : [];
  return list;
}

async function metered() {
  const app = process.env.METERED_TURN_APP, key = process.env.METERED_TURN_API_KEY;
  if (!app || !key) return null;
  const res = await fetch(`https://${app}.metered.live/api/v1/turn/credentials?apiKey=${encodeURIComponent(key)}`);
  if (!res.ok) throw new Problem(502, `Call relay (Metered) said ${res.status}. Check the TURN key in ${SETTINGS}.`);
  const list = await res.json();
  return Array.isArray(list) ? list : [];
}

export const handler = (event) => handle(event, async () => {
  await signedInUser(event);
  const relays = (await cloudflare()) || (await metered()) || [];
  return { iceServers: [...STUN, ...relays], relay: relays.length > 0 };
});
