// Rings people's iPhones for a call even when Sugerly is closed: an Apple
// "VoIP" push, which makes iOS wake the app and show its own incoming-call
// screen. The caller's app calls this right after starting a call.
//
// Set these in Netlify → Site configuration → Environment variables, from
// developer.apple.com → Certificates, IDs & Profiles → Keys → "+" with
// "Apple Push Notifications service (APNs)" ticked:
//   APNS_KEY       the whole text of the downloaded AuthKey_XXXXXXXXXX.p8 file
//   APNS_KEY_ID    the key's 10-character Key ID
//   APPLE_TEAM_ID  your 10-character Team ID (developer.apple.com → Account → Membership)
// Without them nothing breaks: calls still ring inside the app while it's open.
import crypto from "node:crypto";
import http2 from "node:http2";
import { Problem, body, getDoc, handle, signedInUser } from "../lib/sugerly.mjs";

const TOPIC = "com.mimilocks.app.voip";
const HOSTS = { production: "api.push.apple.com", sandbox: "api.sandbox.push.apple.com" };
let signed = null;

// The key however it was pasted (with or without line breaks or "\n").
function pem(raw) {
  const text = String(raw || "").replace(/\\n/g, "\n");
  const middle = text
    .replace(/[\s\S]*-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----[\s\S]*/, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  if (middle.length < 40) return null;
  return `-----BEGIN PRIVATE KEY-----\n${middle.match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----\n`;
}

// Apple's sign-in for pushes, remade every 45 minutes.
function apnsToken() {
  const key = pem(process.env.APNS_KEY);
  const keyId = (process.env.APNS_KEY_ID || "").trim();
  const team = (process.env.APPLE_TEAM_ID || "").trim();
  if (!key || !keyId || !team) return null;
  if (signed && Date.now() - signed.made < 45 * 60 * 1000) return signed.value;
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const head = b64({ alg: "ES256", kid: keyId });
  const claims = b64({ iss: team, iat: Math.floor(Date.now() / 1000) });
  const sig = crypto.sign("sha256", Buffer.from(`${head}.${claims}`), { key, dsaEncoding: "ieee-p1363" }).toString("base64url");
  signed = { value: `${head}.${claims}.${sig}`, made: Date.now() };
  return signed.value;
}

function send(host, device, payload, auth) {
  return new Promise((resolve) => {
    const client = http2.connect(`https://${host}`);
    const done = (result) => { try { client.close(); } catch {} resolve(result); };
    client.on("error", (e) => done({ status: 0, reason: String(e?.message || e) }));
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${device}`,
      authorization: `bearer ${auth}`,
      "apns-topic": TOPIC,
      "apns-push-type": "voip",
      "apns-priority": "10",
      // A call is only worth ringing now; don't deliver it late.
      "apns-expiration": "0",
      "content-type": "application/json",
    });
    let status = 0;
    let text = "";
    req.setEncoding("utf8");
    req.setTimeout(8000, () => { req.close(); done({ status: 0, reason: "timeout" }); });
    req.on("response", (h) => { status = Number(h[":status"]) || 0; });
    req.on("data", (chunk) => { text += chunk; });
    req.on("end", () => {
      let reason = "";
      try { reason = JSON.parse(text).reason || ""; } catch {}
      done({ status, reason });
    });
    req.on("error", (e) => done({ status: 0, reason: String(e?.message || e) }));
    req.end(JSON.stringify(payload));
  });
}

export const handler = (event) => handle(event, async () => {
  const user = await signedInUser(event);
  const id = String(body(event).call_id || "");
  const call = await getDoc("Call", id);
  if (!call) throw new Problem(404, "That call doesn't exist.");
  if (String(call.caller_email || "").toLowerCase() !== user.email) throw new Problem(403, "Only the caller can ring.");
  if (call.status !== "ringing") return { sent: 0, devices: 0, failures: [] };
  const auth = apnsToken();
  if (!auth) return { sent: 0, setup: false, devices: 0, failures: [] };

  const payload = {
    aps: {},
    call_id: call.id,
    caller_email: user.email,
    caller_name: call.caller_name || "",
    is_group: call.conversation_type === "group",
    group_name: call.group_name || "",
    conversation_id: call.conversation_id || "",
    started_at: call.started_at || Date.now(),
  };
  const others = [...new Set((call.member_emails || []).map((e) => String(e).toLowerCase()))]
    .filter((e) => e && e !== user.email)
    .slice(0, 25);
  let sent = 0;
  let devices = 0;
  const failures = [];
  await Promise.all(others.map(async (email) => {
    const device = await getDoc("PushToken", email).catch(() => null);
    const address = String(device?.voip_token || "").replace(/[^0-9a-f]/gi, "");
    if (!address) return;
    devices += 1;
    const first = device.env === "sandbox" ? "sandbox" : "production";
    let result = await send(HOSTS[first], address, payload, auth);
    // A test build's address only works on Apple's test server (and back).
    if (result.status === 400 && result.reason === "BadDeviceToken") {
      result = await send(HOSTS[first === "sandbox" ? "production" : "sandbox"], address, payload, auth);
    }
    if (result.status === 200) sent += 1;
    else {
      // Apple's reason (e.g. InvalidProviderToken, TopicDisallowed) so the
      // caller's app can say what's wrong.
      failures.push(result.reason || `status ${result.status}`);
      console.log(`Call push not delivered: ${result.status} ${result.reason}`);
    }
  }));
  return { sent, setup: true, devices, failures };
});
