import { base44 } from "@/api/base44Client";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { notify } from "@/utils/notifications";

// Optimistically toggles `user` in record.likes and notifies the owner on a new like.
export async function toggleLike({ entity, record, user, setData, message, link }) {
  if (!user || !record) return;
  const likes = record.likes || [];
  const liked = likes.includes(user.email);
  const next = liked ? likes.filter((e) => e !== user.email) : [...likes, user.email];
  const patch = (value) => setData?.((list) => list.map((r) => (r.id === record.id ? { ...r, likes: value } : r)));
  patch(next);
  try {
    await base44.entities[entity].update(record.id, { likes: next });
    const owner = record.user_email || record.created_by;
    if (!liked && owner && owner !== user.email) {
      await notify({ to_email: owner, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture, type: "like", message: `${displayName(user)} ${message}`, link, entity_id: record.id });
    }
  } catch (e) {
    patch(likes);
    toast.error(e?.message || "Could not update like.");
  }
}
