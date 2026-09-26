import React, { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Bookmark, Flag, Heart, MessageCircle, MoreHorizontal, Music2, Play, Plus, Send, Sparkles, ThumbsDown, Trash2, Volume2, VolumeX } from "lucide-react";
import Avatar from "@/components/common/Avatar";
import Popover from "@/components/common/Popover";
import ReelMedia from "./ReelMedia";
import { recordReelSignal } from "@/lib/reelRank";
import { feedback } from "@/lib/feedback";
import { displayName, profileLink, timeAgo } from "@/lib/format";

const compact = (n) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(1)}K` : String(n || 0));

function RailButton({ icon: Icon, label, count, active, activeColor = "#ff4d7d", onClick, fill }) {
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick?.(e); }} className="flex flex-col items-center gap-1 text-white" aria-label={label} aria-pressed={active}>
      <span className="w-11 h-11 rounded-full flex items-center justify-center transition-transform active:scale-90" style={{ background: "rgb(255 255 255 / 0.12)" }}>
        <Icon className="w-6 h-6" style={active ? { color: activeColor, fill: fill ? activeColor : "none" } : undefined} strokeWidth={2.2} />
      </span>
      {count !== undefined && <span className="text-[11px] font-bold tabular-nums" style={{ textShadow: "0 1px 3px rgb(0 0 0 / 0.6)" }}>{compact(count)}</span>}
    </button>
  );
}

// Caption with tappable #hashtags; long captions expand on tap.
function Caption({ text, onTag }) {
  const [open, setOpen] = useState(false);
  if (!text) return null;
  const parts = String(text).split(/(#[\p{L}\p{N}_]{2,30})/gu);
  return (
    <p onClick={(e) => { e.stopPropagation(); setOpen((v) => !v); }} className={`text-[14px] leading-snug ${open ? "" : "line-clamp-2"}`} style={{ textShadow: "0 1px 3px rgb(0 0 0 / 0.5)" }}>
      {parts.map((p, i) => (p.startsWith("#")
        ? <button key={i} className="font-bold" onClick={(e) => { e.stopPropagation(); onTag?.(p.slice(1).toLowerCase()); }}>{p}</button>
        : <React.Fragment key={i}>{p}</React.Fragment>))}
    </p>
  );
}

// One full-screen reel.
export default function ReelItem({ reel, reason, active, near, me, author, following, liked, saved, commentCount, soundOn, onSoundOn, onBlocked, onLike, onSave, onFollow, onComments, onShare, onHide, onReport, onDelete, onTag, onViewed }) {
  const mediaRef = useRef(null);
  const progressRef = useRef(null);
  const [paused, setPaused] = useState(false);
  const [hearts, setHearts] = useState([]);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);
  const tapTimer = useRef(null);
  const watch = useRef({ start: 0, ms: 0, loops: 0, counted: false });
  const likes = (reel.likes || []).length;
  const name = author ? displayName(author) : reel.user_display_name;
  const picture = author?.profile_picture ?? reel.user_profile_picture;

  // Watch-time tracking for the algorithm (and the view counter).
  useEffect(() => {
    if (!active) return undefined;
    setPaused(false);
    watch.current = { start: performance.now(), ms: 0, loops: 0, counted: false };
    const viewTimer = setTimeout(() => { if (!watch.current.counted) { watch.current.counted = true; onViewed?.(reel); } }, 2000);
    return () => {
      clearTimeout(viewTimer);
      const w = watch.current;
      const ms = w.ms + (w.start ? performance.now() - w.start : 0);
      recordReelSignal(reel, { ms, completed: w.loops > 0, skipped: ms < 1500 && w.loops === 0 });
    };
  }, [active, reel.id]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!active) return;
    const w = watch.current;
    if (paused && w.start) { w.ms += performance.now() - w.start; w.start = 0; }
    if (!paused && !w.start) w.start = performance.now();
  }, [paused, active]);

  const setProgress = (p) => { if (progressRef.current) progressRef.current.style.transform = `scaleX(${p})`; };
  const onLoop = () => { watch.current.loops += 1; };

  const likeAt = (x, y) => {
    const id = Date.now();
    setHearts((h) => [...h, { id, x, y, r: Math.round(Math.random() * 30 - 15) }]);
    setTimeout(() => setHearts((h) => h.filter((p) => p.id !== id)), 900);
    feedback("like");
    if (!liked) onLike(reel);
  };
  const onTap = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left, y = e.clientY - rect.top;
    if (tapTimer.current) { clearTimeout(tapTimer.current); tapTimer.current = null; likeAt(x, y); return; }
    // First tap anywhere turns the sound on (must happen inside the tap for iOS).
    if (!soundOn) { onSoundOn(); mediaRef.current?.unlock(); feedback("tap"); return; }
    tapTimer.current = setTimeout(() => { tapTimer.current = null; setPaused((p) => !p); feedback("tap"); }, 240);
  };

  return (
    <div className="absolute inset-0 select-none" onClick={onTap}>
      <ReelMedia ref={mediaRef} reel={reel} active={active} near={near} paused={paused} soundOn={soundOn} onProgress={setProgress} onLoop={onLoop} onBlocked={onBlocked} />
      {/* readability gradients */}
      <div className="absolute inset-x-0 top-0 h-28 pointer-events-none" style={{ background: "linear-gradient(to bottom, rgb(0 0 0 / 0.45), transparent)" }} />
      <div className="absolute inset-x-0 bottom-0 h-64 pointer-events-none" style={{ background: "linear-gradient(to top, rgb(0 0 0 / 0.65), transparent)" }} />

      <AnimatePresence>
        {paused && active && (
          <motion.span initial={{ opacity: 0, scale: 1.3 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.8 }} className="absolute left-1/2 top-1/2 w-20 h-20 -ml-10 -mt-10 rounded-full flex items-center justify-center pointer-events-none" style={{ background: "rgb(0 0 0 / 0.35)" }}>
            <Play className="w-9 h-9 text-white fill-white ml-1" />
          </motion.span>
        )}
      </AnimatePresence>
      {hearts.map((h) => (
        <motion.span key={h.id} className="absolute pointer-events-none" style={{ left: h.x - 48, top: h.y - 48, rotate: `${h.r}deg` }} initial={{ scale: 0.3, opacity: 0 }} animate={{ scale: [0.3, 1.2, 1], opacity: [0, 1, 1], y: [0, -10, -60] }} transition={{ duration: 0.85, times: [0, 0.35, 1] }}>
          <Heart className="w-24 h-24 drop-shadow-xl" style={{ color: "#ff4d7d", fill: "#ff4d7d" }} />
        </motion.span>
      ))}

      {!soundOn && active && (
        <span className="absolute left-1/2 top-16 -translate-x-1/2 mt-[env(safe-area-inset-top)] px-3 py-1.5 rounded-full text-xs font-bold text-white flex items-center gap-1.5 pointer-events-none" style={{ background: "rgb(0 0 0 / 0.45)" }}>
          <VolumeX className="w-3.5 h-3.5" /> Tap for sound
        </span>
      )}

      {/* action rail */}
      <div className="absolute right-2.5 bottom-24 flex flex-col items-center gap-4 z-10" onClick={(e) => e.stopPropagation()}>
        <div className="relative mb-2">
          <Link to={profileLink(reel.user_email)} className="block rounded-full" style={{ boxShadow: "0 0 0 2px #fff" }} aria-label={name}>
            <Avatar src={picture} name={name} size={46} />
          </Link>
          {me && reel.user_email !== me.email && !following && (
            <button onClick={() => { feedback("tap"); onFollow(reel.user_email); }} className="absolute -bottom-2.5 left-1/2 -translate-x-1/2 w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ background: "#ff4d7d" }} aria-label={`Follow ${name}`}><Plus className="w-4 h-4" strokeWidth={3} /></button>
          )}
        </div>
        <RailButton icon={Heart} label={liked ? "Unlike" : "Like"} count={likes} active={liked} fill onClick={() => { feedback(liked ? "unlike" : "like"); onLike(reel); }} />
        <RailButton icon={MessageCircle} label="Comments" count={commentCount} onClick={() => { feedback("tap"); onComments(reel); }} />
        <RailButton icon={Bookmark} label={saved ? "Unsave" : "Save"} active={saved} activeColor="#ffd35c" fill onClick={() => onSave(reel)} />
        <RailButton icon={Send} label="Share" onClick={() => onShare(reel)} />
        <button ref={menuRef} onClick={() => setMenuOpen(true)} className="w-11 h-11 rounded-full flex items-center justify-center text-white" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="More options"><MoreHorizontal className="w-6 h-6" /></button>
        <Popover open={menuOpen} onClose={() => setMenuOpen(false)} anchorRef={menuRef} placement="left-end" width={240} label="Reel options">
          <div className="p-2 pt-0">
            <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }} onClick={() => { setMenuOpen(false); onHide(reel); }}><ThumbsDown className="w-4 h-4" /> Not interested</button>
            {me && reel.user_email !== me.email && <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }} onClick={() => { setMenuOpen(false); onReport(reel); }}><Flag className="w-4 h-4" /> Report</button>}
            {onDelete && <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--danger)" }} onClick={() => { setMenuOpen(false); onDelete(reel); }}><Trash2 className="w-4 h-4" /> Delete reel</button>}
          </div>
        </Popover>
      </div>

      {/* caption */}
      <div className="absolute left-0 right-20 bottom-5 px-4 text-white space-y-1.5 z-10" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-2 flex-wrap">
          <Link to={profileLink(reel.user_email)} className="font-bold text-[15px]" style={{ textShadow: "0 1px 3px rgb(0 0 0 / 0.5)" }}>@{name}</Link>
          <span className="text-xs opacity-75">· {timeAgo(reel.created_date)}</span>
        </div>
        {reason && <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full" style={{ background: "rgb(255 255 255 / 0.16)" }}><Sparkles className="w-3 h-3" /> {reason}</span>}
        <Caption text={reel.caption} onTag={onTag} />
        {reel.music_title && (
          <div className="flex items-center gap-2 text-[13px] overflow-hidden">
            <Music2 className={`w-4 h-4 flex-shrink-0 ${active && !paused && soundOn ? "anim-spin" : ""}`} style={{ animationDuration: "3s" }} />
            <span className="marquee-mask flex-1 min-w-0"><span className={`inline-block whitespace-nowrap ${active ? "marquee" : ""}`}>{reel.music_title} · {reel.music_artist || "Sugerly"}</span></span>
          </div>
        )}
      </div>

      {/* sound toggle + progress */}
      {soundOn && (
        <button onClick={(e) => { e.stopPropagation(); onSoundOn(false); }} className="absolute right-3 top-[calc(env(safe-area-inset-top)+4.25rem)] w-9 h-9 rounded-full flex items-center justify-center text-white z-10" style={{ background: "rgb(0 0 0 / 0.35)" }} aria-label="Mute"><Volume2 className="w-4 h-4" /></button>
      )}
      <div className="absolute inset-x-0 bottom-0 h-[3px] pointer-events-none" style={{ background: "rgb(255 255 255 / 0.2)" }}>
        <div ref={progressRef} className="h-full origin-left" style={{ background: "#fff", transform: "scaleX(0)", transition: "transform 0.25s linear" }} />
      </div>
    </div>
  );
}
