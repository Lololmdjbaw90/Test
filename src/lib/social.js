import { useMemo } from "react";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { displayName } from "@/lib/format";
import { notify } from "@/utils/notifications";

// All friendships involving `email`. Queried in two halves so each query is
// allowed by the Firestore rules (you can only read your own friendships).
export function useFriendships(email) {
  const sent = useLiveQuery("Friendship", email ? { requester_email: email } : null, { enabled: !!email });
  const received = useLiveQuery("Friendship", email ? { receiver_email: email } : null, { enabled: !!email });
  const friendships = useMemo(() => {
    const map = new Map();
    [...sent.data, ...received.data].forEach((f) => map.set(f.id, f));
    return [...map.values()];
  }, [sent.data, received.data]);
  return {
    friendships,
    loading: sent.loading || received.loading,
    reload: () => { sent.reload(); received.reload(); },
  };
}

export function splitFriendships(friendships, email) {
  const other = (f) => (f.requester_email === email ? f.receiver_email : f.requester_email);
  const accepted = friendships.filter((f) => f.status === "accepted");
  return {
    accepted,
    incoming: friendships.filter((f) => f.status === "pending" && f.receiver_email === email),
    outgoing: friendships.filter((f) => f.status === "pending" && f.requester_email === email),
    friendEmails: accepted.map(other),
    other,
  };
}

export const dmConversationId = (a, b) => [a, b].sort().join("__dm__");

// Follow / unfollow `email`, notifying them on a new follow.
export async function toggleFollow({ me, email, updateMe }) {
  const following = (me.following || []).includes(email);
  const next = following ? (me.following || []).filter((e) => e !== email) : [...(me.following || []), email];
  await updateMe({ following: next });
  if (!following) {
    await notify({ to_email: email, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "follow", message: `${displayName(me)} started following you`, link: `/Profile?email=${encodeURIComponent(me.email)}` }).catch(() => {});
  }
  return !following;
}
