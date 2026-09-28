import { base44 } from "@/api/base44Client";
import { notify } from "@/utils/notifications";
import { displayName } from "@/lib/format";
import { toast } from "@/lib/toast";

// Invite friends: everyone has an invite code; when someone new signs up
// with it the inviter gets 400 coins (collected next time they open Sugerly).
// One Referral record per new account (id = the new person's uid), same as
// the iOS app (App/Referrals.swift).
export const INVITE_REWARD = 400;

export const inviteCodeFor = (id) => String(id || "").replace(/[^a-z0-9]/gi, "").slice(0, 8).toUpperCase();
export const inviteLink = (code) => `${window.location.origin}/Login?ref=${code}`;
export const inviteText = (code) => `Come draw with me on Sugerly! Sign up with my invite code ${code}: ${inviteLink(code)}`;

const fb = () => base44.firebase;
const firestore = () => import("firebase/firestore");

// Saves your code on your account so others can find you by it.
export async function ensureInviteCode(user) {
  if (!user?.id || user.invite_code) return;
  await base44.auth.updateMe({ invite_code: inviteCodeFor(user.id) }).catch(() => {});
}

// A new account: link it to whoever invited you.
export async function redeemInvite(raw, user) {
  const code = String(raw || "").trim().toUpperCase();
  const uid = fb()?.auth?.currentUser?.uid;
  if (code.length < 6 || !user?.email || !fb()?.db || !uid) return false;
  const [inviter] = await base44.entities.User.filter({ invite_code: code }, null, 1).catch(() => []);
  if (!inviter?.email || inviter.email === user.email) {
    toast("That invite code wasn't found, but you're in!");
    return false;
  }
  const { doc, setDoc } = await firestore();
  const now = new Date().toISOString();
  try {
    await setDoc(doc(fb().db, "Referral", uid), {
      inviter_email: inviter.email, inviter_uid: inviter.id, invitee_email: user.email, invitee_uid: uid,
      invitee_name: displayName(user), code, claimed: false, created_date: now, updated_date: now, created_by: user.email,
    });
    notify({ to_email: inviter.email, from_email: user.email, from_display_name: displayName(user), type: "invite", message: `${displayName(user)} joined Sugerly with your invite! Collect your ${INVITE_REWARD} coins.`, link: "/Profile" }).catch?.(() => {});
    return true;
  } catch {
    return false;
  }
}

// Collects 400 coins for each friend who joined with your code.
let claiming = false;
export async function claimInvites(user, updateMe) {
  if (claiming || !user?.email || !fb()?.db) return 0;
  claiming = true;
  try {
    const { collection, getDocs, limit, query, updateDoc, where, doc } = await firestore();
    const snap = await getDocs(query(collection(fb().db, "Referral"), where("inviter_email", "==", user.email), where("claimed", "==", false), limit(20)));
    let count = 0;
    for (const row of snap.docs) {
      try {
        await updateDoc(doc(fb().db, "Referral", row.id), { claimed: true, claimed_date: new Date().toISOString() });
        count += 1;
      } catch { /* someone else claimed it */ }
    }
    if (count) {
      await updateMe({ coins: (user.coins || 0) + count * INVITE_REWARD, invites_joined: (user.invites_joined || 0) + count });
      toast.success(count === 1 ? `A friend joined with your invite: +${INVITE_REWARD} coins!` : `${count} friends joined with your invite: +${count * INVITE_REWARD} coins!`);
    }
    return count;
  } catch {
    return 0;
  } finally {
    claiming = false;
  }
}
