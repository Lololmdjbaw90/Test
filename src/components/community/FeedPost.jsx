import React, { useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Ban, Bookmark, EyeOff, Flag, Flame, Heart, Link2, Loader2, MessageCircle, MoreHorizontal, Send, Share2, Sparkles, Sprout, Trash2, UserRound, Users } from "lucide-react";
import { openReport } from "@/lib/safety";
import Avatar from "@/components/common/Avatar";
import Popover from "@/components/common/Popover";
import RichText from "@/components/chat/RichText";
import { sendComment } from "@/components/gallery/CommentSection";
import { toast } from "@/lib/toast";
import { displayName, isOnline, profileLink, siteUrl, timeAgo } from "@/lib/format";
import { haptic } from "@/lib/native";

const REASON_ICON = { heart: Heart, friend: Users, sparkles: Sparkles, flame: Flame, sprout: Sprout };
const TEXT_BACKGROUNDS = [
  "linear-gradient(145deg, rgb(var(--accent-2-rgb) / 0.45), rgb(var(--accent-rgb) / 0.2))",
  "linear-gradient(145deg, #e9e1ff, #c9b8ff)",
  "linear-gradient(145deg, #dff7ee, #a7e8d2)",
  "linear-gradient(145deg, #ffe9dc, #ffc4a6)",
];

export async function sharePost(post) {
  const url = siteUrl(`/Community?post=${post.id}`);
  if (navigator.share && window.matchMedia("(pointer: coarse)").matches) {
    try { await navigator.share({ title: post.title || "Mimi Locks post", url }); return; } catch { /* cancelled */ }
  }
  try { await navigator.clipboard.writeText(url); toast.success("Link copied"); } catch { toast(url); }
}

function ActionButton({ onClick, label, active, activeColor, children, count }) {
  return (
    <motion.button whileTap={{ scale: 0.85 }} onClick={onClick} className="h-10 min-w-10 px-2 rounded-full flex items-center justify-center gap-1.5 text-sm font-semibold transition-colors hover:bg-[var(--surface-2)]" style={{ color: active ? activeColor : "var(--text-secondary)" }} aria-label={label} aria-pressed={active}>
      {children}
      {count > 0 && <span className="tabular-nums">{count}</span>}
    </motion.button>
  );
}

// One post in the social feed.
export default function FeedPost({ post, reason, me, author, comments = [], likers = [], following, onFollow, liked, onLike, saved, onSave, onOpen, onTag, onDelete, onHide, onBlock, index = 0 }) {
  const [burst, setBurst] = useState(0);
  const [menu, setMenu] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [reply, setReply] = useState("");
  const [sending, setSending] = useState(false);
  const menuRef = useRef(null);
  const tapTimer = useRef(null);
  const name = author ? displayName(author) : post.user_display_name;
  const isMine = post.user_email === me?.email;
  const likeCount = (post.likes || []).length;
  const text = post.description || "";
  const long = text.length > 260;
  const textOnly = !post.image_url;
  const bigText = textOnly && text.length > 0 && text.length <= 140;
  const bg = TEXT_BACKGROUNDS[(post.id || "").charCodeAt(0) % TEXT_BACKGROUNDS.length || 0];
  const ReasonIcon = reason ? REASON_ICON[reason.icon] || Sparkles : null;

  // Double-tap (or double-click) the media to like; a single tap opens the post.
  const onMediaClick = () => {
    if (tapTimer.current) {
      clearTimeout(tapTimer.current);
      tapTimer.current = null;
      setBurst((b) => b + 1);
      haptic("medium");
      if (!liked) onLike();
      return;
    }
    tapTimer.current = setTimeout(() => { tapTimer.current = null; onOpen(); }, 260);
  };
  const submitReply = async (e) => {
    e.preventDefault();
    if (!reply.trim() || sending) return;
    setSending(true);
    if (await sendComment({ entity: "CommunityComment", field: "post_id", targetId: post.id, content: reply, user: me, ownerEmail: post.user_email, link: `/Community?post=${post.id}` })) setReply("");
    setSending(false);
  };

  const friendLiker = likers[0];
  const lastComments = comments.slice(-2);

  return (
    <motion.article
      initial={{ opacity: 0, y: 18 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: Math.min(index, 6) * 0.04, type: "spring", stiffness: 260, damping: 28 }}
      className="card !rounded-[1.75rem] overflow-hidden"
      data-post-id={post.id}
    >
      {reason && (
        <div className="flex items-center gap-1.5 px-4 pt-3 -mb-1 text-[11px] font-bold" style={{ color: "var(--text-muted)" }}>
          <ReasonIcon className="w-3.5 h-3.5" style={{ color: "var(--accent-rose)" }} /> {reason.text}
        </div>
      )}
      <header className="flex items-center gap-3 px-4 pt-3 pb-2.5">
        <Link to={profileLink(post.user_email)} className="flex-shrink-0">
          <Avatar src={author?.profile_picture || post.user_profile_picture} name={name} size={42} online={author ? isOnline(author) : undefined} nitro={author?.nitro_active} />
        </Link>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 min-w-0">
            <Link to={profileLink(post.user_email)} className="text-sm font-bold truncate hover:underline" style={{ color: "var(--text-primary)" }}>{name}</Link>
            {!isMine && !following && onFollow && (
              <>
                <span style={{ color: "var(--text-muted)" }}>·</span>
                <button onClick={() => onFollow(post.user_email)} className="text-sm font-bold flex-shrink-0 hover:opacity-80" style={{ color: "var(--accent-rose)" }}>Follow</button>
              </>
            )}
          </div>
          <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>{timeAgo(post.created_date)}{post.title ? ` · ${post.title}` : ""}</p>
        </div>
        <button ref={menuRef} onClick={() => setMenu((v) => !v)} className="icon-btn" aria-label="Post options" aria-expanded={menu}><MoreHorizontal className="w-5 h-5" /></button>
        <Popover open={menu} onClose={() => setMenu(false)} anchorRef={menuRef} placement="bottom-end" width={230} label="Post options">
          <div className="p-2 grid gap-0.5">
            {[
              { icon: Link2, label: "Copy link", run: () => sharePost(post) },
              { icon: UserRound, label: `Go to ${name.split(" ")[0]}'s profile`, to: profileLink(post.user_email) },
              !isMine && onHide && { icon: EyeOff, label: "Not interested", run: () => onHide(post) },
              !isMine && { icon: Flag, label: "Report post", run: () => openReport({ type: "post", id: post.id, owner: post.user_email, preview: post.description || post.title, link: `/Community?post=${post.id}` }), danger: true },
              !isMine && onBlock && { icon: Ban, label: `Block ${name.split(" ")[0]}`, run: () => onBlock(post.user_email, name), danger: true },
              onDelete && { icon: Trash2, label: "Delete post", run: () => onDelete(post), danger: true },
            ].filter(Boolean).map((a) => {
              const cls = "flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-sm font-semibold text-left transition-colors hover:bg-[var(--surface-2)]";
              const style = { color: a.danger ? "var(--danger)" : "var(--text-primary)" };
              return a.to
                ? <Link key={a.label} to={a.to} onClick={() => setMenu(false)} className={cls} style={style}><a.icon className="w-4 h-4" /> {a.label}</Link>
                : <button key={a.label} onClick={() => { setMenu(false); a.run(); }} className={cls} style={style}><a.icon className="w-4 h-4" /> {a.label}</button>;
            })}
          </div>
        </Popover>
      </header>

      {!bigText && text && (
        <div className="px-4 pb-3 text-[15px] leading-relaxed cursor-pointer" style={{ color: "var(--text-primary)" }} onClick={(e) => { if (!e.target.closest("a,button")) onOpen(); }}>
          <RichText text={long && !expanded ? `${text.slice(0, 240).trimEnd()}…` : text} onTag={onTag} />
          {long && !expanded && <button onClick={() => setExpanded(true)} className="ml-1 text-sm font-semibold" style={{ color: "var(--text-muted)" }}>more</button>}
        </div>
      )}

      <div className="relative select-none cursor-pointer" onClick={onMediaClick} role="button" tabIndex={0} aria-label="Open post (double-tap to like)" onKeyDown={(e) => { if (e.key === "Enter") onOpen(); }}>
        {post.image_url ? (
          <div className="relative" style={{ background: "var(--surface-2)" }}>
            <img src={post.image_url} alt={post.title || ""} loading={index < 2 ? "eager" : "lazy"} className="w-full max-h-[620px] object-cover" draggable={false} style={{ minHeight: 160 }} />
          </div>
        ) : bigText ? (
          <div className="mx-4 mb-1 rounded-3xl px-6 py-10 flex items-center justify-center text-center min-h-[180px]" style={{ background: bg }}>
            <p className="font-display text-2xl sm:text-[1.7rem] leading-snug" style={{ color: "#2a1620" }}><RichText text={text} onTag={onTag} /></p>
          </div>
        ) : null}
        <AnimatePresence>
          {burst > 0 && (
            <motion.span
              key={burst}
              initial={{ scale: 0.2, opacity: 0 }}
              animate={{ scale: [0.2, 1.25, 1], opacity: [0, 1, 1] }}
              exit={{ scale: 1.4, opacity: 0 }}
              transition={{ duration: 0.45 }}
              onAnimationComplete={() => setTimeout(() => setBurst(0), 250)}
              className="absolute inset-0 flex items-center justify-center pointer-events-none"
            >
              <Heart className="w-24 h-24 fill-current drop-shadow-xl" style={{ color: "#fff" }} />
            </motion.span>
          )}
        </AnimatePresence>
      </div>

      <div className="px-2 pt-1.5 flex items-center">
        <ActionButton onClick={() => { haptic(liked ? "light" : "medium"); onLike(); }} label={liked ? "Unlike" : "Like"} active={liked} activeColor="var(--accent-rose)" count={likeCount}>
          <motion.span key={liked ? "on" : "off"} initial={{ scale: 0.6 }} animate={{ scale: 1 }} transition={{ type: "spring", stiffness: 500, damping: 15 }} className="inline-flex">
            <Heart className={`w-[22px] h-[22px] ${liked ? "fill-current" : ""}`} />
          </motion.span>
        </ActionButton>
        <ActionButton onClick={onOpen} label="Comments" count={comments.length}><MessageCircle className="w-[22px] h-[22px]" /></ActionButton>
        <ActionButton onClick={() => sharePost(post)} label="Share"><Share2 className="w-[21px] h-[21px]" /></ActionButton>
        <div className="flex-1" />
        <ActionButton onClick={onSave} label={saved ? "Remove from saved" : "Save"} active={saved} activeColor="var(--text-primary)">
          <Bookmark className={`w-[22px] h-[22px] ${saved ? "fill-current" : ""}`} />
        </ActionButton>
      </div>

      <div className="px-4 pb-4 space-y-1.5">
        {likeCount > 0 && (
          <div className="flex items-center gap-2 text-[13px]" style={{ color: "var(--text-secondary)" }}>
            {likers.length > 0 && <span className="flex -space-x-1.5">{likers.slice(0, 3).map((u) => <Avatar key={u.email} src={u.profile_picture} name={displayName(u)} size={20} style={{ boxShadow: "0 0 0 2px var(--surface)", borderRadius: 9999 }} />)}</span>}
            <span>
              Liked by <strong style={{ color: "var(--text-primary)" }}>{friendLiker ? (friendLiker.email === me?.email ? "you" : displayName(friendLiker)) : `${likeCount} ${likeCount === 1 ? "person" : "people"}`}</strong>
              {friendLiker && likeCount > 1 && <> and <strong style={{ color: "var(--text-primary)" }}>{likeCount - 1} {likeCount - 1 === 1 ? "other" : "others"}</strong></>}
            </span>
          </div>
        )}
        {comments.length > 2 && <button onClick={onOpen} className="text-[13px] font-semibold" style={{ color: "var(--text-muted)" }}>View all {comments.length} comments</button>}
        {lastComments.map((c) => (
          <p key={c.id} className="text-[13px] leading-snug line-clamp-2" style={{ color: "var(--text-secondary)" }}>
            <Link to={profileLink(c.user_email)} className="font-bold mr-1.5 hover:underline" style={{ color: "var(--text-primary)" }}>{c.user_display_name || "Someone"}</Link>
            {c.content}
          </p>
        ))}
        {me && (
          <form onSubmit={submitReply} className="flex items-center gap-2 pt-1.5">
            <Avatar src={me.profile_picture} name={displayName(me)} size={26} />
            <input value={reply} onChange={(e) => setReply(e.target.value)} placeholder="Add a comment…" maxLength={500} className="flex-1 min-w-0 bg-transparent text-[13px] outline-none py-1.5" style={{ color: "var(--text-primary)" }} aria-label={`Comment on ${name}'s post`} />
            <AnimatePresence>
              {reply.trim() && (
                <motion.button initial={{ opacity: 0, scale: 0.8 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }} type="submit" disabled={sending} className="text-sm font-bold flex items-center gap-1" style={{ color: "var(--accent-rose)" }} aria-label="Post comment">
                  {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />} Post
                </motion.button>
              )}
            </AnimatePresence>
          </form>
        )}
      </div>
    </motion.article>
  );
}
