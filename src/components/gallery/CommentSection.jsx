import React, { useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Loader2, MessageCircle, Send, Trash2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { displayName, profileLink, timeAgo } from "@/lib/format";
import { notify } from "@/utils/notifications";
import Avatar from "@/components/common/Avatar";

// Moderates and posts a comment, notifying the owner. Returns true on success.
export async function sendComment({ entity = "Comment", field = "artwork_id", targetId, content, user, ownerEmail, link }) {
  content = String(content || "").trim();
  if (!user || !content) return false;
  const mod = await checkText(content, { user, where: "comment" });
  if (!mod.safe) { toast.error("Comment blocked", { description: mod.reason }); return false; }
  try {
    await base44.entities[entity].create({
      [field]: targetId,
      content,
      gif_url: "",
      user_email: user.email,
      user_display_name: displayName(user),
      user_full_name: displayName(user),
      user_profile_picture: user.profile_picture || "",
      likes: [],
    });
    if (ownerEmail && ownerEmail !== user.email) {
      await notify({ to_email: ownerEmail, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture, type: "comment", message: `${displayName(user)} commented: "${content.slice(0, 60)}"`, link, entity_id: targetId });
    }
    return true;
  } catch (err) {
    toast.error(err?.message || "Could not post comment.");
    return false;
  }
}

// Live comment thread. `entity` is "Comment" (artworks) or "CommunityComment" (posts).
export default function CommentSection({ entity = "Comment", field = "artwork_id", targetId, ownerEmail, link, compact = false }) {
  const { user } = useAuth();
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const { data: comments, loading } = useLiveQuery(entity, { [field]: targetId }, { sort: "created_date", limit: 200, enabled: !!targetId });

  const send = async (e) => {
    e?.preventDefault();
    if (!user || !text.trim() || sending) return;
    setSending(true);
    if (await sendComment({ entity, field, targetId, content: text, user, ownerEmail, link })) setText("");
    setSending(false);
  };

  const remove = async (id) => {
    try { await base44.entities[entity].delete(id); } catch (err) { toast.error(err?.message || "Could not delete comment."); }
  };

  return (
    <div className="space-y-3">
      <p className="eyebrow flex items-center gap-1.5"><MessageCircle className="w-3.5 h-3.5" /> Comments · {comments.length}</p>
      {loading ? (
        <div className="space-y-2">{[0, 1].map((i) => <div key={i} className="skeleton h-12" />)}</div>
      ) : (
        <div className={`space-y-3 ${compact ? "max-h-56" : "max-h-80"} overflow-y-auto scroll pr-1`}>
          {comments.length === 0 && <p className="text-sm py-4 text-center" style={{ color: "var(--text-muted)" }}>No comments yet — say something nice ✨</p>}
          <AnimatePresence initial={false}>
            {comments.map((c) => {
              const name = c.user_display_name || c.user_full_name || "Someone";
              const canDelete = user && (user.email === c.user_email || user.role === "admin" || user.email === ownerEmail);
              return (
                <motion.div key={c.id} layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, x: -10 }} className="flex gap-2.5 group">
                  <Link to={profileLink(c.user_email)}><Avatar src={c.user_profile_picture} name={name} size={30} /></Link>
                  <div className="flex-1 min-w-0 rounded-2xl rounded-tl-md px-3 py-2" style={{ background: "var(--surface-2)" }}>
                    <div className="flex items-baseline gap-2">
                      <Link to={profileLink(c.user_email)} className="text-xs font-bold hover:underline" style={{ color: "var(--text-primary)" }}>{name}</Link>
                      <span className="text-[10px]" style={{ color: "var(--text-muted)" }}>{timeAgo(c.created_date)}</span>
                    </div>
                    <p className="text-sm break-words whitespace-pre-wrap" style={{ color: "var(--text-secondary)" }}>{c.content}</p>
                  </div>
                  {canDelete && (
                    <button onClick={() => remove(c.id)} className="icon-btn w-7 h-7 opacity-0 group-hover:opacity-100 focus:opacity-100 self-center" aria-label="Delete comment"><Trash2 className="w-3.5 h-3.5" style={{ color: "var(--danger)" }} /></button>
                  )}
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
      )}
      {user ? (
        <form onSubmit={send} className="flex gap-2 items-center">
          <Avatar src={user.profile_picture} name={displayName(user)} size={30} />
          <input className="input flex-1 !rounded-full" placeholder="Add a comment…" value={text} onChange={(e) => setText(e.target.value)} maxLength={500} />
          <motion.button whileTap={{ scale: 0.9 }} type="submit" disabled={sending || !text.trim()} className="w-10 h-10 rounded-full flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40" style={{ background: "var(--accent-grad)" }} aria-label="Send comment">
            {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
          </motion.button>
        </form>
      ) : (
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Log in to comment.</p>
      )}
    </div>
  );
}
