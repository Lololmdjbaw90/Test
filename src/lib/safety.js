// Safety tools: reporting, blocking and account deletion.
// (Also what the App Store asks of apps with user-generated content.)
import { useMemo } from "react";
import { deleteDoc, doc } from "firebase/firestore";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { displayName } from "@/lib/format";

export const REPORT_REASONS = [
  "Spam or scam",
  "Harassment or bullying",
  "Hate speech",
  "Nudity or sexual content",
  "Violence or threats",
  "Stolen art / copyright",
  "Pretending to be someone else",
  "Something else",
];

// ---------- reporting ----------
// target = { type: "post" | "comment" | "track" | "message" | "user", id, owner, preview, link }
export async function fileReport(me, target, reason, details = "") {
  await base44.entities.Report.create({
    target_type: target.type,
    target_id: target.id,
    target_owner_email: target.owner || "",
    target_preview: String(target.preview || "").slice(0, 280),
    link: target.link || "",
    reason,
    details: String(details || "").slice(0, 1000),
    reporter_email: me.email,
    reporter_name: displayName(me),
    status: "open",
  });
}

// The report dialog lives once in the app shell; open it from anywhere.
const reportListeners = new Set();
export function openReport(target) { reportListeners.forEach((fn) => fn(target)); }
export function onOpenReport(fn) { reportListeners.add(fn); return () => reportListeners.delete(fn); }

// ---------- blocking ----------
export function useBlocked() {
  const { user } = useAuth();
  return useMemo(() => new Set(user?.blocked || []), [user?.blocked]);
}

// Blocking also unfollows them and removes any friendship between you.
export async function setBlocked({ me, email, updateMe, block }) {
  const blocked = new Set(me.blocked || []);
  if (block) blocked.add(email); else blocked.delete(email);
  const patch = { blocked: [...blocked] };
  if (block) patch.following = (me.following || []).filter((e) => e !== email);
  await updateMe(patch);
  if (block) {
    const F = base44.entities.Friendship;
    const rows = [
      ...(await F.filter({ requester_email: me.email, receiver_email: email }).catch(() => [])),
      ...(await F.filter({ requester_email: email, receiver_email: me.email }).catch(() => [])),
    ];
    await Promise.all(rows.map((f) => F.delete(f.id).catch(() => {})));
  }
}

// ---------- account deletion ----------
// Checks the password, deletes what you created, then the account itself.
// Messages you sent are removed; other people's copies of group chats stay.
export async function deleteMyAccount(me, password, onProgress = () => {}) {
  await base44.auth.verifyPassword(password);
  const E = base44.entities;
  const mine = (name, query) => E[name].filter(query).catch(() => []);
  const remove = (name, rows) => Promise.all(rows.map((r) => E[name].delete(r.id).catch(() => {})));

  onProgress("Removing your posts and tracks…");
  await remove("CommunityPost", await mine("CommunityPost", { user_email: me.email }));
  await remove("MusicReview", await mine("MusicReview", { user_email: me.email }));
  await remove("Commission", await mine("Commission", { artist_email: me.email }));
  await remove("Reel", await mine("Reel", { user_email: me.email }));
  await remove("Artwork", await mine("Artwork", { created_by: me.email }));

  onProgress("Removing your comments and messages…");
  await remove("CommunityComment", await mine("CommunityComment", { user_email: me.email }));
  await remove("CommunityComment", await mine("CommunityComment", { post_id: `profile_${me.email}` }));
  await remove("Comment", await mine("Comment", { user_email: me.email }));
  await remove("ChannelMessage", await mine("ChannelMessage", { user_email: me.email }));
  const dms = await mine("DirectMessage", { member_emails: { $contains: me.email } });
  await remove("DirectMessage", dms.filter((m) => m.user_email === me.email));

  onProgress("Leaving servers and groups…");
  await remove("Friendship", [...await mine("Friendship", { requester_email: me.email }), ...await mine("Friendship", { receiver_email: me.email })]);
  await remove("Notification", await mine("Notification", { to_email: me.email }));
  await remove("ServerMember", await mine("ServerMember", { user_email: me.email }));
  const servers = await mine("Community", { member_emails: { $contains: me.email } });
  await Promise.all(servers.map((c) => (c.owner_email === me.email
    ? E.Community.delete(c.id)
    : E.Community.update(c.id, { member_emails: (c.member_emails || []).filter((e) => e !== me.email) })).catch(() => {})));
  const groups = await mine("GroupChat", { member_emails: { $contains: me.email } });
  await Promise.all(groups.map((g) => (g.owner_email === me.email
    ? E.GroupChat.delete(g.id)
    : E.GroupChat.update(g.id, { member_emails: g.member_emails.filter((e) => e !== me.email), member_display_names: Object.fromEntries(Object.entries(g.member_display_names || {}).filter(([e]) => e !== me.email)) })).catch(() => {})));

  const db = base44.firebase?.db;
  if (db && me.id) await deleteDoc(doc(db, "PayoutInfo", me.id)).catch(() => {});

  onProgress("Deleting your account…");
  await base44.auth.deleteAccount();
}
