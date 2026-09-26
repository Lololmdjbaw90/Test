// DM and group calls, built on the voice rooms in voice.js.
// -----------------------------------------------------------------------------
// A `Call` doc rings everyone in the conversation and tracks the call's status:
//   ringing -> active (someone answered) -> ended
// Media flows through the voice room whose id is the call id. When the call
// finishes, a small "call" message is posted into the conversation
// (missed / declined / ended with its duration).
// -----------------------------------------------------------------------------
import { base44 } from "@/api/base44Client";
import voice, { VOICE_STALE_MS } from "@/lib/voice";
import { displayName } from "@/lib/format";

export const RING_MS = 45000;
const Call = () => base44.entities.Call;

export function formatDuration(ms) {
  const s = Math.max(0, Math.round((ms || 0) / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = String(s % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}

const otherEmail = (call, me) => (call.member_emails || []).find((e) => e !== me?.email) || me?.email;

export function callTitle(call, me) {
  if (call.conversation_type === "group") return call.group_name || "Group call";
  const other = otherEmail(call, me);
  return call.member_names?.[other] || other?.split("@")[0] || "Call";
}

export function callLink(call, me) {
  return call.conversation_type === "group" ? `/DirectMessages?c=${call.conversation_id}` : `/DirectMessages?with=${encodeURIComponent(otherEmail(call, me))}`;
}

export const callRoom = (call, me) => ({ id: call.id, name: callTitle(call, me), type: "call", conversationId: call.conversation_id, link: callLink(call, me) });

// Is this call still something you can pick up or join?
export function isLiveCall(call, now = Date.now()) {
  if (!call || call.status === "ended") return false;
  return call.status === "active" || now - (call.started_at || 0) < RING_MS;
}

export async function startCall({ conversation, me, video = false, pictures = {} }) {
  const isGroup = conversation.type === "group";
  const members = isGroup ? [...new Set(conversation.group.member_emails || [])].sort() : [me.email, conversation.otherUser.email].sort();
  const names = isGroup ? { ...(conversation.group.member_display_names || {}) } : { [conversation.otherUser.email]: displayName(conversation.otherUser) };
  names[me.email] = displayName(me);
  const call = await Call().create({
    conversation_id: conversation.id,
    conversation_type: isGroup ? "group" : "dm",
    group_name: isGroup ? conversation.group.name : "",
    caller_email: me.email,
    caller_name: displayName(me),
    caller_picture: me.profile_picture || "",
    member_emails: members,
    member_names: names,
    member_pictures: Object.fromEntries(members.filter((e) => e !== me.email).map((e) => [e, pictures[e] || (isGroup ? "" : conversation.otherUser.profile_picture) || ""])),
    status: "ringing",
    video: !!video,
    declined_by: [],
    joined_emails: [me.email],
    started_at: Date.now(),
    answered_at: null,
    ended_at: null,
  });
  await voice.join(callRoom(call, me), me, { video });
  return call;
}

export async function joinCall(call, me, { video = false } = {}) {
  await Call().update(call.id, {
    status: "active",
    joined_emails: [...new Set([...(call.joined_emails || []), me.email])],
    answered_at: call.answered_at || Date.now(),
  }).catch((e) => console.warn("[calls] could not mark answered:", e?.message));
  return voice.join(callRoom(call, me), me, { video });
}

export async function declineCall(call, me) {
  const patch = { declined_by: [...new Set([...(call.declined_by || []), me.email])] };
  // Declining a one-to-one call ends it; group calls keep ringing the others.
  if (call.conversation_type !== "group" && call.status === "ringing") Object.assign(patch, { status: "ended", ended_at: Date.now() });
  await Call().update(call.id, patch).catch(() => {});
}

async function postCallMessage(call, user, outcome, duration) {
  await base44.entities.DirectMessage.create({
    conversation_id: call.conversation_id,
    conversation_type: call.conversation_type,
    group_name: call.group_name || "",
    type: "call",
    call_outcome: outcome,
    call_duration: duration,
    call_video: !!call.video,
    content: "",
    image_url: "",
    user_email: user.email,
    user_display_name: user.display_name || user.email.split("@")[0],
    user_profile_picture: user.profile_picture || "",
    member_emails: call.member_emails,
    read_by: [user.email],
    reactions: {},
    is_edited: false,
  }).catch((e) => console.warn("[calls] could not post call message:", e?.message));
}

// Runs whenever we leave a call room: ends the call when nobody is left
// (or always, for one-to-one calls) and posts the summary message once.
async function onLeftRoom({ room, user }) {
  if (room?.type !== "call" || !user?.email) return;
  const call = await Call().get(room.id).catch(() => null);
  if (!call) return;
  const answered = !!call.answered_at || call.status === "active";
  if (call.conversation_type === "group" && call.status !== "ended") {
    const docs = await base44.entities.VoicePresence.filter({ channel_id: call.id }).catch(() => []);
    const others = docs.filter((d) => d.user_email !== user.email && Date.now() - (d.last_active || 0) < VOICE_STALE_MS);
    if (others.length > 0) return; // the call carries on without us
  }
  const alreadyEnded = call.status === "ended";
  if (!alreadyEnded) await Call().update(call.id, { status: "ended", ended_at: Date.now() }).catch(() => {});
  if (answered) {
    if (!alreadyEnded) await postCallMessage(call, user, "ended", Date.now() - call.answered_at);
  } else if (call.caller_email === user.email) {
    await postCallMessage(call, user, (call.declined_by || []).length ? "declined" : "missed", 0);
  }
}
if (typeof window !== "undefined") voice.onLeave(onLeftRoom);

// One-line summary for message previews, toasts and the call bubble.
export function callSummary(msg, meEmail) {
  const kind = msg.call_video ? "Video call" : "Voice call";
  const mine = msg.user_email === meEmail;
  switch (msg.call_outcome) {
    case "missed": return mine ? `${kind} · No answer` : `Missed ${kind.toLowerCase()}`;
    case "declined": return mine ? `${kind} · Declined` : `Declined ${kind.toLowerCase()}`;
    default: return `${kind} · ${formatDuration(msg.call_duration)}`;
  }
}

export function messagePreview(msg, meEmail) {
  if (msg.type === "call") return `📞 ${callSummary(msg, meEmail)}`;
  if (msg.shared_reel) return `🎬 ${msg.content?.split("\n")[0]?.startsWith("🎬") ? "Sent a reel" : msg.content.split("\n")[0]}`;
  return msg.content || "📷 Image";
}
