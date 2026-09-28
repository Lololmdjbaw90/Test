import React, { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Bookmark, Check, ChevronLeft, ChevronRight, Heart, Link2, Maximize2, MessageCircle, Sparkles, Trash2, UserPlus } from "lucide-react";
import Modal from "@/components/common/Modal";
import Lightbox from "@/components/common/Lightbox";
import Avatar from "@/components/common/Avatar";
import LikeButton from "@/components/common/LikeButton";
import CommentSection from "@/components/gallery/CommentSection";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { feedback } from "@/lib/feedback";
import { displayName, profileLink, siteUrl, timeAgo } from "@/lib/format";
import { likeCount as countLikes } from "@/lib/likeCount";

// Caption with tappable #hashtags.
function Caption({ text, onTag }) {
  if (!text) return null;
  const parts = String(text).split(/(#[\p{L}\p{N}_]{2,30})/gu);
  return (
    <p className="text-[15px] leading-relaxed whitespace-pre-wrap" style={{ color: "var(--text-secondary)" }}>
      {parts.map((p, i) => (p.startsWith("#") && onTag
        ? <button key={i} className="font-semibold" style={{ color: "var(--accent-rose)" }} onClick={() => onTag(p.slice(1).toLowerCase())}>{p}</button>
        : <React.Fragment key={i}>{p}</React.Fragment>))}
    </p>
  );
}

function Thumb({ post, onOpen, className = "" }) {
  return (
    <button onClick={() => onOpen(post.id)} className={`relative block overflow-hidden rounded-2xl text-left group ${className}`} style={{ background: "var(--surface-2)" }} aria-label={post.title || post.description || "Open post"}>
      {post.image_url ? (
        <img src={post.image_url} alt="" loading="lazy" decoding="async" className="absolute inset-0 w-full h-full object-cover transition-transform duration-500 can-hover:group-hover:scale-105" />
      ) : (
        <span className="absolute inset-0 p-3 flex items-center justify-center text-center text-[13px] font-semibold leading-snug" style={{ background: "var(--accent-grad)", color: "#fff" }}><span className="line-clamp-4">{post.title || post.description}</span></span>
      )}
      {countLikes(post) > 0 && <span className="absolute bottom-1.5 left-1.5 px-1.5 py-0.5 rounded-full text-[10px] font-bold text-white flex items-center gap-1" style={{ background: "rgb(0 0 0 / 0.45)" }}><Heart className="w-3 h-3 fill-current" />{countLikes(post)}</span>}
    </button>
  );
}

// The post view: big picture (swipe for the next post, double-tap to like,
// tap for full screen), the artist with a follow button, one row of actions,
// the caption, comments, more from the artist and "More like this".
export default function PostViewer(incoming) {
  // While the window closes, keep showing what was open (the parent
  // already cleared it) so the close animation doesn't collapse.
  const last = useRef(incoming);
  if (incoming.post) last.current = incoming;
  const isOpen = !!incoming.post;
  const { post, onClose, liked, likeCount, onLike, onDelete, position, onPrev, onNext, saved, onSave, author, following, onFollow, related = [], moreFromAuthor = [], onOpenPost, onTag, likers = [] } = isOpen ? incoming : { ...last.current, onClose: incoming.onClose };
  const { user } = useAuth();
  const canDelete = post && user && (user.email === post.user_email || user.role === "admin");
  const [zoom, setZoom] = useState(false);
  const [hearts, setHearts] = useState([]);
  const dir = useRef(0);
  const dragged = useRef(false);
  const tapTimer = useRef(null);
  const commentsRef = useRef(null);
  const topRef = useRef(null);
  const prev = onPrev ? () => { dir.current = -1; feedback("swipe"); onPrev(); } : null;
  const next = onNext ? () => { dir.current = 1; feedback("swipe"); onNext(); } : null;
  const name = author ? displayName(author) : post?.user_display_name;
  const picture = author?.profile_picture ?? post?.user_profile_picture;
  const isMe = user && post && user.email === post.user_email;

  // Opening another post from inside the viewer starts at the top again.
  useEffect(() => {
    let el = topRef.current;
    while (el && el !== document.body) { if (el.scrollHeight > el.clientHeight + 2 && /(auto|scroll)/.test(getComputedStyle(el).overflowY)) { el.scrollTo({ top: 0 }); break; } el = el.parentElement; }
    topRef.current?.querySelectorAll(".lg\\:overflow-y-auto").forEach((d) => d.scrollTo({ top: 0 }));
  }, [post?.id]);

  useEffect(() => {
    if (!isOpen) { setZoom(false); return undefined; }
    const onKey = (e) => {
      if (["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
      if (e.key === "ArrowLeft") prev?.();
      if (e.key === "ArrowRight") next?.();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isOpen, post, onPrev, onNext]); // eslint-disable-line react-hooks/exhaustive-deps

  const share = async () => {
    const url = siteUrl(`/Community?post=${post.id}`);
    try {
      if (navigator.share && window.matchMedia("(pointer: coarse)").matches) { await navigator.share({ title: post.title || `${name} on Sugerly`, url }); return; }
    } catch { return; }
    try { await navigator.clipboard.writeText(url); toast.success("Link copied"); } catch { toast(url); }
  };
  const burst = (x, y) => {
    const id = Date.now();
    setHearts((h) => [...h, { id, x, y }]);
    setTimeout(() => setHearts((h) => h.filter((p) => p.id !== id)), 850);
    feedback("like");
    if (!liked) onLike?.();
  };
  const onMediaClick = (e) => {
    if (dragged.current) return;
    const r = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - r.left, y = e.clientY - r.top;
    if (tapTimer.current) { clearTimeout(tapTimer.current); tapTimer.current = null; burst(x, y); return; }
    tapTimer.current = setTimeout(() => { tapTimer.current = null; if (post.image_url) setZoom(true); }, 260);
  };
  const focusComments = () => {
    feedback("tap");
    const box = commentsRef.current;
    box?.scrollIntoView({ behavior: "smooth", block: "center" });
    setTimeout(() => box?.querySelector("input, textarea")?.focus({ preventScroll: true }), 350);
  };
  const open = (id) => { dir.current = 0; onOpenPost?.(id); };

  return (
    <Modal open={isOpen} onClose={onClose} size={post?.image_url ? "max-w-6xl" : "max-w-4xl"} padded={false} hideHeader autoFocus={false}>
      {post && (
        <div ref={topRef} className="flex flex-col lg:flex-row lg:h-[84vh]">
          {/* media */}
          <div className="relative lg:flex-1 flex items-center justify-center overflow-hidden px-3 pt-8 pb-4 sm:p-6 lg:p-8" style={{ background: "#140a10", minHeight: post.image_url ? "min(46vh, 420px)" : "min(36vh, 320px)" }}>
            {post.image_url && <img src={post.image_url} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-30 blur-2xl scale-110" />}
            <span className="sm:hidden absolute top-2 left-1/2 w-10 h-1 rounded-full" style={{ translate: "-50% 0", background: "rgb(255 255 255 / 0.35)" }} aria-hidden="true" />
            <AnimatePresence mode="wait" initial={false}>
              <motion.div
                key={post.id}
                className="relative max-w-full cursor-pointer select-none"
                initial={{ opacity: 0, x: dir.current * 48 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: dir.current * -48 }}
                transition={{ duration: 0.22, ease: [0.2, 0.8, 0.2, 1] }}
                drag={prev || next ? "x" : false}
                dragConstraints={{ left: 0, right: 0 }}
                dragElastic={0.5}
                onDragStart={() => { dragged.current = true; }}
                onDragEnd={(e, info) => {
                  setTimeout(() => { dragged.current = false; }, 0);
                  if ((info.offset.x < -70 || info.velocity.x < -500) && next) next();
                  else if ((info.offset.x > 70 || info.velocity.x > 500) && prev) prev();
                }}
                onClick={onMediaClick}
              >
                {post.image_url ? (
                  <img src={post.image_url} alt={post.title || ""} draggable={false} className="w-auto max-w-full max-h-[48vh] sm:max-h-[56vh] lg:max-h-[74vh] object-contain rounded-2xl shadow-2xl" />
                ) : (
                  <div className="w-[min(88vw,520px)] aspect-[4/3] rounded-3xl p-8 flex items-center justify-center text-center shadow-2xl" style={{ background: "var(--accent-grad)" }}>
                    <p className="font-display text-2xl sm:text-3xl leading-snug text-white line-clamp-6">{post.title || post.description}</p>
                  </div>
                )}
                {hearts.map((h) => (
                  <motion.span key={h.id} className="absolute pointer-events-none" style={{ left: h.x - 44, top: h.y - 44 }} initial={{ scale: 0.3, opacity: 0 }} animate={{ scale: [0.3, 1.2, 1], opacity: [0, 1, 0], y: [0, -8, -40] }} transition={{ duration: 0.8 }}>
                    <Heart className="w-[88px] h-[88px] drop-shadow-xl" style={{ color: "#ff4d7d", fill: "#ff4d7d" }} />
                  </motion.span>
                ))}
              </motion.div>
            </AnimatePresence>
            {prev && <button onClick={prev} className="hidden sm:flex absolute left-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full glass items-center justify-center" style={{ color: "var(--text-primary)" }} aria-label="Previous post"><ChevronLeft className="w-5 h-5" /></button>}
            {next && <button onClick={next} className="hidden sm:flex absolute right-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full glass items-center justify-center" style={{ color: "var(--text-primary)" }} aria-label="Next post"><ChevronRight className="w-5 h-5" /></button>}
            <div className="absolute bottom-3 inset-x-3 flex items-center justify-between pointer-events-none">
              {position && position.total > 1 ? <span className="px-2.5 py-1 rounded-full text-[11px] font-bold text-white tabular-nums" style={{ background: "rgb(0 0 0 / 0.45)" }}>{position.index} / {position.total}</span> : <span />}
              {post.image_url && <button onClick={() => setZoom(true)} className="pointer-events-auto w-9 h-9 rounded-full flex items-center justify-center text-white" style={{ background: "rgb(0 0 0 / 0.45)" }} aria-label="View full screen"><Maximize2 className="w-4 h-4" /></button>}
            </div>
          </div>

          {/* details */}
          <div className="lg:w-[420px] flex flex-col min-h-0">
            <div className="p-4 sm:p-6 space-y-4 lg:overflow-y-auto scroll flex-1">
              <div className="flex items-center gap-3 lg:pr-10">
                <Link to={profileLink(post.user_email)} onClick={onClose} className="flex items-center gap-3 flex-1 min-w-0 group">
                  <Avatar src={picture} name={name} size={44} />
                  <span className="min-w-0">
                    <span className="block text-sm font-bold truncate group-hover:underline" style={{ color: "var(--text-primary)" }}>{name}</span>
                    <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{timeAgo(post.created_date)}</span>
                  </span>
                </Link>
                {onFollow && !isMe && (
                  <button onClick={() => { feedback("tap"); onFollow(post.user_email); }} className={following ? "btn-outline !min-h-0 !py-1.5 text-xs" : "btn !min-h-0 !py-1.5 text-xs"}>
                    {following ? <><Check className="w-3.5 h-3.5" /> Following</> : <><UserPlus className="w-3.5 h-3.5" /> Follow</>}
                  </button>
                )}
              </div>

              {post.title && <h2 className="font-display text-[1.7rem] leading-tight" style={{ color: "var(--text-primary)" }}>{post.title}</h2>}
              <Caption text={post.description} onTag={onTag ? (t) => { onClose(); onTag(t); } : null} />

              <div className="grid grid-flow-col auto-cols-fr gap-2">
                <LikeButton variant="tile" liked={liked} count={likeCount} onToggle={onLike} />
                <button onClick={focusComments} className="action-tile"><MessageCircle className="w-5 h-5" /><span>Comment</span></button>
                <button onClick={share} className="action-tile"><Link2 className="w-5 h-5" /><span>Share</span></button>
                {onSave && <button onClick={onSave} className="action-tile" data-active={saved} aria-pressed={saved}><Bookmark className={`w-5 h-5 ${saved ? "fill-current" : ""}`} /><span>{saved ? "Saved" : "Save"}</span></button>}
              </div>

              {likers.length > 0 && (
                <div className="flex items-center gap-2 text-[13px]" style={{ color: "var(--text-secondary)" }}>
                  <span className="flex -space-x-1.5">{likers.slice(0, 3).map((u) => <Avatar key={u.email} src={u.profile_picture} name={displayName(u)} size={22} style={{ boxShadow: "0 0 0 2px var(--surface)", borderRadius: 9999 }} />)}</span>
                  <span>Liked by <strong style={{ color: "var(--text-primary)" }}>{likers[0].email === user?.email ? "you" : displayName(likers[0])}</strong>{likeCount > 1 && <> and <strong style={{ color: "var(--text-primary)" }}>{likeCount - 1} other{likeCount - 1 === 1 ? "" : "s"}</strong></>}</span>
                </div>
              )}

              {canDelete && onDelete && (
                <div className="flex justify-end -mt-1"><button onClick={onDelete} className="btn-ghost text-xs !min-h-0 !py-1.5" style={{ color: "var(--danger)" }}><Trash2 className="w-3.5 h-3.5" /> Delete post</button></div>
              )}

              {moreFromAuthor.length > 0 && onOpenPost && (
                <section>
                  <p className="eyebrow mb-2">More from {name}</p>
                  <div className="flex gap-2 overflow-x-auto no-scrollbar -mx-1 px-1">
                    {moreFromAuthor.map((p) => <Thumb key={p.id} post={p} onOpen={open} className="w-24 h-24 flex-shrink-0" />)}
                  </div>
                </section>
              )}

              <div className="divider" />
              <div ref={commentsRef}>
                <CommentSection entity="CommunityComment" field="post_id" targetId={post.id} ownerEmail={post.user_email} link={`/Community?post=${post.id}`} />
              </div>

              {related.length > 0 && onOpenPost && (
                <section className="pt-2">
                  <p className="eyebrow mb-2 flex items-center gap-1.5"><Sparkles className="w-3.5 h-3.5" /> More like this</p>
                  <div className="grid grid-cols-3 lg:grid-cols-2 gap-2">
                    {related.map((p) => <Thumb key={p.id} post={p} onOpen={open} className="aspect-square" />)}
                  </div>
                </section>
              )}
            </div>
          </div>
        </div>
      )}
      <AnimatePresence>{zoom && post?.image_url && <Lightbox key="zoom" src={post.image_url} alt={post.title || ""} onClose={() => setZoom(false)} />}</AnimatePresence>
    </Modal>
  );
}
