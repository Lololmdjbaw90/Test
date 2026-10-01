// Calls are short-lived invitations. Never replay old calls to PushKit or
// ring a member who already answered/declined on another device.
export function ringRecipients(call, caller, now = Date.now()) {
  const started = Number(call.started_at);
  if (call.status !== "ringing" || !Number.isFinite(started) || started <= 0
      || now - started >= 45_000 || started - now > 5_000) return [];
  const excluded = new Set([caller, ...(call.joined_emails || []), ...(call.declined_by || [])]
    .map((email) => String(email).trim().toLowerCase()));
  return [...new Set((call.member_emails || []).map((email) => String(email).trim().toLowerCase()))]
    .filter((email) => email && !excluded.has(email)).slice(0, 25);
}
