import React, { useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown, Heart, Loader2, MessageCircle, MessageCircleOff, Send, Trash2, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { checkText } from "@/lib/moderation";
import { toast } from "@/lib/toast";
import { displayName, profileLink, timeAgo } from "@/lib/format";
import { notify } from "@/utils/notifications";
import Avatar from "@/components/common/Avatar";
import GifPicker from "@/components/common/GifPicker";
import RichText from "@/components/chat/RichText";
import { useBlocked } from "@/lib/safety";
import { feedback } from "@/lib/feedback";

const QUICK = ["❤️", "😂", "😍", "🔥", "👏", "😮", "🥺"];

// Moderates and posts a comment (or a reply / a GIF), notifying the owner and
// the person replied to. Returns true on success.
export async function sendComment({ entity = "Comment", field = "artwork_id", targetId, content, gif = "", replyTo = null, user, ownerEmail, link }) {
  content = String(content || "").trim();
  if (!user || (!content && !gif)) return false;
  if (content) {
    const mod = await checkText(content, { user, where: "comment" });
    if (!mod.safe) { toast.error("Comment blocked", { description: mod.reason }); return false; }
  }
  try {
    await base44.entities[entity].create({
      [field]: targetId,
      content,
      gif_url: gif || "",
      parent_id: replyTo ? (replyTo.parent_id || replyTo.id) : "",
      reply_to_email: replyTo?.user_email || "",
      reply_to_name: replyTo ? (replyTo.user_display_name || "") : "",
      user_email: user.email,
      user_display_name: displayName(user),
      user_full_name: displayName(user),
      user_profile_picture: user.profile_picture || "",
      likes: [],
    });
    const preview = content ? `"${content.slice(0, 60)}"` : "a GIF";
    const base = { from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture, link, entity_id: targetId };
    if (replyTo?.user_email && replyTo.user_email !== user.email) {
      await notify({ ...base, to_email: replyTo.user_email, type: "comment", message: `${displayName(user)} replied: ${preview}` });
    }
    if (ownerEmail && ownerEmail !== user.email && ownerEmail !== replyTo?.user_email) {
      await notify({ ...base, to_email: ownerEmail, type: "comment", message: `${displayName(user)} commented: ${preview}` });
    }
    return true;
  } catch (err) {
    toast.error(err?.message || "Could not post comment.");
    return false;
  }
}

function CommentRow({ c, me, ownerEmail, isReply, onReply, onLike, onDelete, liked, likeCount }) {
  const name = c.user_display_name || c.user_full_name || "Someone";
  const canDelete = me && (me.email === c.user_email || me.role === "admin" || me.email === ownerEmail);
  const [pop, setPop] = useState(0);
  return (
    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, x: -12 }} className={`flex gap-2.5 ${isReply ? "pl-11" : ""}`}>
      <Link to={profileLink(c.user_email)} className="flex-shrink-0"><Avatar src={c.user_profile_picture} name={name} size={isReply ? 26 : 34} /></Link>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5 flex-wrap">
          <Link to={profileLink(c.user_email)} className="text-[13px] font-bold" style={{ color: "var(--text-secondary)" }}>{name}</Link>
          {c.user_email === ownerEmail && <span className="px-1.5 py-px rounded-md text-[10px] font-bold text-white" style={{ background: "#ff4d7d" }}>Creator</span>}
        </div>
        <p className="text-[14px] leading-snug mt-0.5" style={{ color: "var(--text-primary)" }}>
          {c.reply_to_name && isReply && <span className="font-semibold" style={{ color: "rgb(var(--accent-rgb))" }}>@{c.reply_to_name} </span>}
          {c.content && <RichText text={c.content} />}
        </p>
        {c.gif_url && <img src={c.gif_url} alt="GIF" loading="lazy" className="mt-1.5 rounded-2xl max-w-[180px] max-h-48 object-cover" />}
        <div className="flex items-center gap-4 mt-1 text-xs font-semibold" style={{ color: "var(--text-muted)" }}>
          <span>{timeAgo(c.created_date)}</span>
          {me && <button type="button" onClick={() => onReply(c)} className="active:opacity-60">Reply</button>}
          {canDelete && <button type="button" onClick={() => onDelete(c)} className="active:opacity-60 flex items-center gap-1" aria-label="Delete comment"><Trash2 className="w-3.5 h-3.5" /></button>}
        </div>
      </div>
      <button type="button" onClick={() => { if (!liked) setPop((n) => n + 1); onLike(c); }} className="flex flex-col items-center gap-0.5 pt-1 w-8 flex-shrink-0 active:scale-90 transition-transform" aria-label={liked ? "Unlike comment" : "Like comment"} aria-pressed={liked}>
        <Heart key={pop} className={`w-[18px] h-[18px] ${pop ? "heart-pop" : ""}`} style={{ color: liked ? "#ff4d7d" : "var(--text-muted)", fill: liked ? "#ff4d7d" : "none" }} />
        <span className="text-[11px] font-semibold tabular-nums" style={{ color: "var(--text-muted)" }}>{likeCount || ""}</span>
      </button>
    </motion.div>
  );
}

// Live comment thread with replies, likes and GIFs.
// `entity` is "Comment" (artworks) or "CommunityComment" (posts, reels, profiles).
// `sheet`: fills a bottom sheet (list scrolls with the sheet, input sticks to the bottom).
// `disabled`: the creator turned comments off.
export default function CommentSection({ entity = "Comment", field = "artwork_id", targetId, ownerEmail, link, compact = false, showTitle = true, sheet = false, disabled = false }) {
  const { user } = useAuth();
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [replyTo, setReplyTo] = useState(null);
  const [gifOpen, setGifOpen] = useState(false);
  const [open, setOpen] = useState(() => new Set()); // threads showing their replies
  const [likeOverride, setLikeOverride] = useState({}); // optimistic likes
  const mounted = useRef(Date.now());
  const inputRef = useRef(null);
  const blocked = useBlocked();
  const { data: allComments, loading } = useLiveQuery(entity, { [field]: targetId }, { sort: "created_date", limit: 300, enabled: !!targetId });
  const comments = allComments.filter((c) => !blocked.has(c.user_email));

  const likesOf = (c) => likeOverride[c.id] ?? (c.likes || []);
  const { tops, repliesOf } = useMemo(() => {
    const byParent = {};
    const top = [];
    comments.forEach((c) => { if (c.parent_id) (byParent[c.parent_id] ||= []).push(c); else top.push(c); });
    const fresh = (c) => c.user_email === user?.email && new Date(c.created_date).getTime() >= mounted.current - 2000;
    // Your new comments first, then the most liked, then the newest.
    top.sort((a, b) => (fresh(b) - fresh(a)) || ((b.likes || []).length - (a.likes || []).length) || (new Date(b.created_date) - new Date(a.created_date)));
    return { tops: top, repliesOf: byParent };
  }, [comments, user?.email]); // eslint-disable-line react-hooks/exhaustive-deps

  const post = async ({ gif = "" } = {}) => {
    if (!user || sending || (!text.trim() && !gif)) return;
    setSending(true);
    const ok = await sendComment({ entity, field, targetId, content: text, gif, replyTo, user, ownerEmail, link });
    if (ok) {
      feedback("send");
      if (replyTo) setOpen((s) => new Set(s).add(replyTo.parent_id || replyTo.id));
      setText(""); setReplyTo(null); setGifOpen(false);
    }
    setSending(false);
  };
  const like = async (c) => {
    if (!user) return;
    const cur = likesOf(c);
    const on = !cur.includes(user.email);
    const next = on ? [...cur, user.email] : cur.filter((e) => e !== user.email);
    feedback(on ? "like" : "unlike");
    setLikeOverride((m) => ({ ...m, [c.id]: next }));
    try { await base44.entities[entity].update(c.id, { likes: next }); } catch (e) {
      setLikeOverride((m) => { const n = { ...m }; delete n[c.id]; return n; });
      toast.error(e?.message || "Could not like that comment.");
    }
  };
  const remove = async (c) => {
    try {
      await base44.entities[entity].delete(c.id);
      await Promise.all((repliesOf[c.id] || []).map((r) => base44.entities[entity].delete(r.id).catch(() => {})));
    } catch (err) { toast.error(err?.message || "Could not delete comment."); }
  };
  const startReply = (c) => { feedback("tap"); setReplyTo(c); setTimeout(() => inputRef.current?.focus(), 30); };
  const toggleThread = (id) => { feedback("tap"); setOpen((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; }); };

  if (disabled) {
    return (
      <div className="flex flex-col items-center justify-center text-center gap-2 py-12" style={{ color: "var(--text-muted)" }}>
        <MessageCircleOff className="w-8 h-8" />
        <p className="text-sm font-semibold">Comments are turned off</p>
      </div>
    );
  }

  const rowProps = (c) => ({ c, me: user, ownerEmail, onReply: startReply, onLike: like, onDelete: remove, liked: !!user && likesOf(c).includes(user.email), likeCount: likesOf(c).length });
  return (
    <div className={sheet ? "flex flex-col flex-1" : "space-y-3"}>
      {showTitle && <p className="eyebrow flex items-center gap-1.5"><MessageCircle className="w-3.5 h-3.5" /> Comments · {comments.length}</p>}
      {loading ? (
        <div className="space-y-3 flex-1">{[0, 1, 2].map((i) => <div key={i} className="skeleton h-12" />)}</div>
      ) : (
        <div className={sheet ? "flex-1 space-y-4 pb-3" : `space-y-4 ${compact ? "max-h-56" : "max-h-96"} overflow-y-auto scroll pr-1`}>
          {comments.length === 0 && <p className="text-sm py-8 text-center" style={{ color: "var(--text-muted)" }}>No comments yet — be the first ✨</p>}
          <AnimatePresence initial={false}>
            {tops.map((c) => {
              const replies = repliesOf[c.id] || [];
              const shown = open.has(c.id);
              return (
                <div key={c.id} className="space-y-3">
                  <CommentRow {...rowProps(c)} />
                  {shown && replies.map((r) => <CommentRow key={r.id} {...rowProps(r)} isReply />)}
                  {replies.length > 0 && (
                    <button type="button" onClick={() => toggleThread(c.id)} className="ml-11 flex items-center gap-2 text-xs font-bold" style={{ color: "var(--text-muted)" }}>
                      <span className="w-6 h-px" style={{ background: "var(--border-c)" }} />
                      {shown ? "Hide replies" : `View ${replies.length} ${replies.length === 1 ? "reply" : "replies"}`}
                      <ChevronDown className={`w-3.5 h-3.5 transition-transform ${shown ? "rotate-180" : ""}`} />
                    </button>
                  )}
                </div>
              );
            })}
          </AnimatePresence>
        </div>
      )}

      {user ? (
        <div className={sheet ? "sticky bottom-0 -mx-4 px-4 pt-2 pb-2 space-y-2 liquid-sheet !shadow-none" : "space-y-2"}>
          <AnimatePresence>
            {gifOpen && (
              <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 12 }} transition={{ duration: 0.18 }}>
                <GifPicker onPick={(url) => post({ gif: url })} onClose={() => setGifOpen(false)} />
              </motion.div>
            )}
          </AnimatePresence>
          {replyTo && (
            <div className="flex items-center gap-2 text-xs font-semibold px-1" style={{ color: "var(--text-muted)" }}>
              <span className="flex-1 truncate">Replying to <span style={{ color: "var(--text-primary)" }}>@{replyTo.user_display_name}</span></span>
              <button type="button" onClick={() => setReplyTo(null)} className="w-6 h-6 rounded-full flex items-center justify-center" aria-label="Cancel reply"><X className="w-3.5 h-3.5" /></button>
            </div>
          )}
          <div className="flex gap-1 justify-between px-1">
            {QUICK.map((e) => <button key={e} type="button" onClick={() => { feedback("tap"); setText((t) => t + e); inputRef.current?.focus(); }} className="text-xl w-9 h-9 rounded-full active:scale-90 transition-transform" aria-label={`Add ${e}`}>{e}</button>)}
          </div>
          <form onSubmit={(e) => { e.preventDefault(); post(); }} className="flex gap-2 items-center">
            <Avatar src={user.profile_picture} name={displayName(user)} size={32} />
            <div className="flex-1 min-w-0 flex items-center rounded-full pl-4 pr-1 h-11" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)" }}>
              <input ref={inputRef} className="flex-1 min-w-0 bg-transparent outline-none text-[16px] sm:text-sm" style={{ color: "var(--text-primary)" }} placeholder={replyTo ? `Reply to ${replyTo.user_display_name}…` : "Add a comment…"} value={text} onChange={(e) => setText(e.target.value)} maxLength={500} aria-label="Comment" />
              <button type="button" onClick={() => { feedback("tap"); setGifOpen((v) => !v); }} className="px-2 h-8 rounded-full text-[11px] font-black tracking-wide" style={{ background: gifOpen ? "rgb(var(--accent-rgb))" : "transparent", color: gifOpen ? "#fff" : "var(--text-muted)", border: gifOpen ? "none" : "1.5px solid var(--text-muted)" }} aria-label="GIFs" aria-pressed={gifOpen}>GIF</button>
            </div>
            <motion.button whileTap={{ scale: 0.9 }} type="submit" disabled={sending || !text.trim()} className="w-10 h-10 rounded-full flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40" style={{ background: "var(--accent-grad)" }} aria-label="Send comment">
              {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            </motion.button>
          </form>
        </div>
      ) : (
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>Log in to comment.</p>
      )}
    </div>
  );
}
