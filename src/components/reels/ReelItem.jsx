import React, { memo, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Bookmark, Check, FastForward, Flag, Heart, Loader2, MessageCircle, MessageCircleOff, MoreHorizontal, Music2, Play, Plus, Send, Sparkles, ThumbsDown, Trash2, Volume2, VolumeX } from "lucide-react";
import Avatar from "@/components/common/Avatar";
import Popover from "@/components/common/Popover";
import ReelMedia from "./ReelMedia";
import { recordReelSignal } from "@/lib/reelRank";
import { feedback } from "@/lib/feedback";
import { useMediaSrc } from "@/lib/media";
import { displayName, profileLink, timeAgo } from "@/lib/format";

const compact = (n) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(1)}K` : String(n || 0));
const BURST = Array.from({ length: 8 }, (_, i) => { const a = (i / 8) * Math.PI * 2; return { "--bx": `${Math.cos(a) * 30}px`, "--by": `${Math.sin(a) * 30}px` }; });

function RailButton({ icon: Icon, label, count, active, activeColor = "#ff4d7d", onClick, fill, pop, burst, delay = 0 }) {
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick?.(e); }} className="rise-in flex flex-col items-center gap-1 text-white select-none" style={{ "--d": `${delay}ms` }} aria-label={label} aria-pressed={active}>
      <span className="relative w-12 h-12 rounded-full flex items-center justify-center transition-transform duration-150 active:scale-[0.85] glass-chip">
        <span key={`pop${pop}`} className={pop ? "heart-pop inline-flex" : "inline-flex"}>
          <Icon className="w-[26px] h-[26px]" style={active ? { color: activeColor, fill: fill ? activeColor : "none" } : undefined} strokeWidth={2.2} />
        </span>
        {burst > 0 && <span key={`burst${burst}`} className="absolute inset-0 pointer-events-none">{BURST.map((st, i) => <span key={i} className="burst-dot absolute left-1/2 top-1/2 -ml-1 -mt-1 w-2 h-2 rounded-full" style={{ ...st, background: i % 2 ? activeColor : "#ffd35c" }} />)}</span>}
      </span>
      {count !== undefined && <span key={`n${count}`} className="text-[12px] font-bold tabular-nums enter-fade" style={{ textShadow: "0 1px 3px rgb(0 0 0 / 0.6)" }}>{compact(count)}</span>}
    </button>
  );
}

function Caption({ text, onTag }) {
  const [open, setOpen] = useState(false);
  if (!text) return null;
  const parts = String(text).split(/(#[\p{L}\p{N}_]{2,30})/gu);
  return (
    <p onClick={(e) => { e.stopPropagation(); setOpen((v) => !v); }} className={`text-[14px] leading-snug transition-all ${open ? "" : "line-clamp-2"}`} style={{ textShadow: "0 1px 3px rgb(0 0 0 / 0.5)" }}>
      {parts.map((p, i) => (p.startsWith("#")
        ? <button key={i} className="font-bold" onClick={(e) => { e.stopPropagation(); onTag?.(p.slice(1).toLowerCase()); }}>{p}</button>
        : <React.Fragment key={i}>{p}</React.Fragment>))}
    </p>
  );
}

// Spinning record with the reel's cover, like TikTok's sound disc.
function MusicDisc({ reel, spinning }) {
  const cover = useMediaSrc(reel.cover_url || "");
  return (
    <span className="rise-in w-11 h-11 rounded-full p-[7px] flex-shrink-0" style={{ "--d": "260ms", background: "repeating-radial-gradient(circle, #1a1017 0 2px, #2a1a24 2px 4px)", boxShadow: "0 2px 10px rgb(0 0 0 / 0.4)" }}>
      <span className="anim-spin block w-full h-full rounded-full overflow-hidden bg-neutral-700" data-paused={!spinning} style={{ animationDuration: "5s" }}>
        {cover ? <img src={cover} alt="" className="w-full h-full object-cover" /> : <Music2 className="w-full h-full p-1 text-white" />}
      </span>
    </span>
  );
}

// One full-screen reel. `actions` is a stable object from the page.
function ReelItem({ reel, reason, active, near, me, author, following, liked, saved, commentCount, soundOn, actions }) {
  const mediaRef = useRef(null);
  const progressRef = useRef(null);
  const [paused, setPaused] = useState(false);
  const [boost, setBoost] = useState(false);
  const [buffering, setBuffering] = useState(false);
  const [showSpinner, setShowSpinner] = useState(false);
  const [scrub, setScrub] = useState(null); // 0..1 while scrubbing
  const [hearts, setHearts] = useState([]);
  const [menuOpen, setMenuOpen] = useState(false);
  const [likePop, setLikePop] = useState(0);
  const [justFollowed, setJustFollowed] = useState(false);
  const menuRef = useRef(null);
  const press = useRef(null);
  const lastTap = useRef(0);
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
    const viewTimer = setTimeout(() => { if (!watch.current.counted) { watch.current.counted = true; actions.viewed(reel); } }, 2000);
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
  // Only show the spinner if loading takes a moment (no flicker).
  useEffect(() => {
    if (!buffering || !active) { setShowSpinner(false); return undefined; }
    const t = setTimeout(() => setShowSpinner(true), 350);
    return () => clearTimeout(t);
  }, [buffering, active]);

  const setProgress = (p) => { if (progressRef.current && scrub === null) progressRef.current.style.transform = `scaleX(${p})`; };
  const onLoop = () => { watch.current.loops += 1; };

  const likeAt = (x, y) => {
    const id = Date.now();
    setHearts((h) => [...h, { id, x, y, r: Math.round(Math.random() * 30 - 15) }]);
    setTimeout(() => setHearts((h) => h.filter((p) => p.id !== id)), 900);
    feedback("like");
    if (!liked) { setLikePop((n) => n + 1); actions.like(reel); }
  };

  // ---------- touch: tap = pause (or sound on), double tap = like, hold = 2x ----------
  const onPointerDown = (e) => {
    if (e.button && e.button !== 0) return;
    press.current = { x: e.clientX, y: e.clientY, held: false, t: setTimeout(() => { if (press.current) { press.current.held = true; setBoost(true); feedback("tap"); } }, 380) };
  };
  const endPress = (e, cancelled) => {
    const p = press.current;
    press.current = null;
    if (!p) return;
    clearTimeout(p.t);
    if (p.held) { setBoost(false); return; }
    if (cancelled || Math.hypot(e.clientX - p.x, e.clientY - p.y) > 12) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left, y = e.clientY - rect.top;
    const now = performance.now();
    if (now - lastTap.current < 280) { clearTimeout(tapTimer.current); lastTap.current = 0; likeAt(x, y); return; }
    lastTap.current = now;
    // First tap anywhere turns the sound on (it must happen inside the tap for iOS).
    if (!soundOn) { actions.setSound(true); mediaRef.current?.unlock(); feedback("tap"); lastTap.current = 0; return; }
    tapTimer.current = setTimeout(() => { setPaused((v) => !v); feedback("tap"); }, 260);
  };

  // ---------- scrubbing ----------
  const scrubTo = (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    const f = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    setScrub(f);
    if (progressRef.current) progressRef.current.style.transform = `scaleX(${f})`;
    mediaRef.current?.seek(f);
  };

  return (
    <div className="absolute inset-0 select-none" style={{ touchAction: "pan-y" }} onPointerDown={onPointerDown} onPointerUp={(e) => endPress(e, false)} onPointerCancel={(e) => endPress(e, true)} onPointerLeave={(e) => { if (press.current?.held) endPress(e, true); }} onContextMenu={(e) => e.preventDefault()}>
      <ReelMedia ref={mediaRef} reel={reel} active={active} near={near} paused={paused || scrub !== null} soundOn={soundOn} speedBoost={boost ? 2 : 1} onProgress={setProgress} onLoop={onLoop} onBlocked={() => actions.setSound(false)} onBuffering={setBuffering} />
      <div className="absolute inset-x-0 top-0 h-28 pointer-events-none" style={{ background: "linear-gradient(to bottom, rgb(0 0 0 / 0.45), transparent)" }} />
      <div className="absolute inset-x-0 bottom-0 h-72 pointer-events-none" style={{ background: "linear-gradient(to top, rgb(0 0 0 / 0.7), transparent)" }} />

      <AnimatePresence>
        {paused && active && scrub === null && (
          <motion.span key="paused" initial={{ opacity: 0, scale: 1.4 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.7 }} transition={{ type: "spring", stiffness: 420, damping: 24 }} className="absolute left-1/2 top-1/2 w-20 h-20 -ml-10 -mt-10 rounded-full flex items-center justify-center pointer-events-none" style={{ background: "rgb(0 0 0 / 0.35)" }}>
            <Play className="w-9 h-9 text-white fill-white ml-1" />
          </motion.span>
        )}
        {boost && (
          <motion.span key="boost" initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.18 }} className="absolute left-1/2 top-[calc(env(safe-area-inset-top)+4.5rem)] -translate-x-1/2 px-3 py-1.5 rounded-full text-sm font-bold text-white flex items-center gap-1.5 pointer-events-none" style={{ background: "rgb(0 0 0 / 0.5)" }}>
            <FastForward className="w-4 h-4 fill-white" /> 2x speed
          </motion.span>
        )}
      </AnimatePresence>
      {showSpinner && <span className="absolute left-1/2 top-1/2 -ml-5 -mt-5 w-10 h-10 flex items-center justify-center pointer-events-none enter-fade"><Loader2 className="w-9 h-9 text-white/80 animate-spin" /></span>}
      {hearts.map((h) => (
        <motion.span key={h.id} className="absolute pointer-events-none" style={{ left: h.x - 48, top: h.y - 48, rotate: `${h.r}deg` }} initial={{ scale: 0.3, opacity: 0 }} animate={{ scale: [0.3, 1.25, 1], opacity: [0, 1, 1, 0], y: [0, -10, -70] }} transition={{ duration: 0.9, times: [0, 0.3, 1] }}>
          <Heart className="w-24 h-24 drop-shadow-xl" style={{ color: "#ff4d7d", fill: "#ff4d7d" }} />
        </motion.span>
      ))}

      {!soundOn && active && (
        <span className="absolute left-1/2 top-[calc(env(safe-area-inset-top)+4rem)] -translate-x-1/2 px-3 py-1.5 rounded-full text-xs font-bold text-white flex items-center gap-1.5 pointer-events-none enter-fade" style={{ background: "rgb(0 0 0 / 0.45)" }}>
          <VolumeX className="w-3.5 h-3.5" /> Tap for sound
        </span>
      )}

      {/* action rail */}
      <div key={active ? "rail-on" : "rail"} className="absolute right-2 bottom-24 flex flex-col items-center gap-3.5 z-10" onPointerDown={(e) => e.stopPropagation()} onPointerUp={(e) => e.stopPropagation()}>
        <div className="relative mb-3 rise-in">
          <Link to={profileLink(reel.user_email)} className="block rounded-full" style={{ boxShadow: "0 0 0 2px #fff" }} aria-label={name}>
            <Avatar src={picture} name={name} size={48} />
          </Link>
          <AnimatePresence>
            {me && reel.user_email !== me.email && (!following || justFollowed) && (
              <motion.button
                key={following ? "done" : "add"}
                initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0, opacity: 0 }} transition={{ type: "spring", stiffness: 500, damping: 22 }}
                onClick={() => { if (following) return; feedback("success"); setJustFollowed(true); actions.follow(reel.user_email); setTimeout(() => setJustFollowed(false), 1200); }}
                className="absolute -bottom-3 left-1/2 -ml-3 w-6 h-6 rounded-full flex items-center justify-center text-white"
                style={{ background: following ? "#22c55e" : "#ff4d7d" }}
                aria-label={following ? "Following" : `Follow ${name}`}
              >
                {following ? <Check className="w-4 h-4" strokeWidth={3} /> : <Plus className="w-4 h-4" strokeWidth={3} />}
              </motion.button>
            )}
          </AnimatePresence>
        </div>
        <RailButton icon={Heart} label={liked ? "Unlike" : "Like"} count={likes} active={liked} fill pop={likePop} burst={likePop} delay={40} onClick={() => { feedback(liked ? "unlike" : "like"); if (!liked) setLikePop((n) => n + 1); actions.like(reel); }} />
        <RailButton icon={reel.comments_off ? MessageCircleOff : MessageCircle} label="Comments" count={reel.comments_off ? undefined : commentCount} delay={80} onClick={() => { feedback("tap"); actions.comments(reel); }} />
        <RailButton icon={Bookmark} label={saved ? "Unsave" : "Save"} active={saved} activeColor="#ffd35c" fill pop={saved ? 1 : 0} delay={120} onClick={() => actions.save(reel)} />
        <RailButton icon={Send} label="Share" delay={160} onClick={() => actions.share(reel)} />
        <button ref={menuRef} onClick={(e) => { e.stopPropagation(); setMenuOpen(true); }} className="rise-in w-12 h-12 rounded-full flex items-center justify-center text-white active:scale-90 transition-transform" style={{ background: "rgb(255 255 255 / 0.13)", "--d": "200ms" }} aria-label="More options"><MoreHorizontal className="w-6 h-6" /></button>
        {reel.music_title && <MusicDisc reel={reel} spinning={active && !paused && soundOn} />}
        <Popover open={menuOpen} onClose={() => setMenuOpen(false)} anchorRef={menuRef} placement="left-end" width={240} label="Reel options">
          <div className="p-2 pt-0">
            <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }} onClick={() => { setMenuOpen(false); actions.hide(reel); }}><ThumbsDown className="w-4 h-4" /> Not interested</button>
            {me && reel.user_email !== me.email && <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }} onClick={() => { setMenuOpen(false); actions.report(reel); }}><Flag className="w-4 h-4" /> Report</button>}
            {me && me.email === reel.user_email && <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--text-primary)" }} onClick={() => { setMenuOpen(false); actions.setComments(reel, !!reel.comments_off); }}>{reel.comments_off ? <MessageCircle className="w-4 h-4" /> : <MessageCircleOff className="w-4 h-4" />} {reel.comments_off ? "Turn on comments" : "Turn off comments"}</button>}
            {me && (me.email === reel.user_email || me.role === "admin") && <button className="w-full flex items-center gap-3 p-3 rounded-xl text-sm font-semibold hover:bg-[var(--surface-2)]" style={{ color: "var(--danger)" }} onClick={() => { setMenuOpen(false); actions.remove(reel); }}><Trash2 className="w-4 h-4" /> Delete reel</button>}
          </div>
        </Popover>
      </div>

      {/* caption */}
      <div key={active ? "cap-on" : "cap"} className="absolute left-0 right-20 bottom-7 px-4 text-white space-y-1.5 z-10" onPointerDown={(e) => e.stopPropagation()} onPointerUp={(e) => e.stopPropagation()}>
        <div className="rise-in flex items-center gap-2 flex-wrap">
          <Link to={profileLink(reel.user_email)} className="font-bold text-[15px]" style={{ textShadow: "0 1px 3px rgb(0 0 0 / 0.5)" }}>@{name}</Link>
          <span className="text-xs opacity-75">· {timeAgo(reel.created_date)}</span>
        </div>
        {reason && <span className="rise-in inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full" style={{ background: "rgb(255 255 255 / 0.16)", "--d": "60ms" }}><Sparkles className="w-3 h-3" /> {reason}</span>}
        <div className="rise-in" style={{ "--d": "100ms" }}><Caption text={reel.caption} onTag={actions.tag} /></div>
        {reel.music_title && (
          <div className="rise-in flex items-center gap-2 text-[13px] overflow-hidden" style={{ "--d": "140ms" }}>
            <Music2 className="w-4 h-4 flex-shrink-0" />
            <span className="marquee-mask flex-1 min-w-0"><span className={`inline-block whitespace-nowrap ${active ? "marquee" : ""}`}>{reel.music_title} · {reel.music_artist || "Sugerly"}</span></span>
          </div>
        )}
      </div>

      {soundOn && active && (
        <button onPointerDown={(e) => e.stopPropagation()} onPointerUp={(e) => e.stopPropagation()} onClick={(e) => { e.stopPropagation(); feedback("tap"); actions.setSound(false); }} className="absolute right-3 top-[calc(env(safe-area-inset-top)+4.25rem)] w-9 h-9 rounded-full flex items-center justify-center text-white z-10 enter-fade" style={{ background: "rgb(0 0 0 / 0.35)" }} aria-label="Mute"><Volume2 className="w-4 h-4" /></button>
      )}

      {/* progress — drag it to scrub */}
      <div
        className="absolute inset-x-0 bottom-0 h-7 flex items-end z-10 cursor-pointer"
        style={{ touchAction: "none" }}
        onPointerDown={(e) => { e.stopPropagation(); e.currentTarget.setPointerCapture?.(e.pointerId); scrubTo(e); feedback("tap"); }}
        onPointerMove={(e) => { if (scrub !== null) scrubTo(e); }}
        onPointerUp={(e) => { e.stopPropagation(); setScrub(null); }}
        onPointerCancel={() => setScrub(null)}
        role="slider" aria-label="Seek" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round((scrub ?? 0) * 100)}
      >
        <div className="relative w-full transition-[height] duration-150" style={{ height: scrub !== null ? 6 : 3, background: "rgb(255 255 255 / 0.22)" }}>
          <div ref={progressRef} className="h-full origin-left" style={{ background: "#fff", transform: "scaleX(0)" }} />
          {scrub !== null && <span className="absolute -top-2 w-4 h-4 -ml-2 rounded-full bg-white shadow" style={{ left: `${scrub * 100}%`, top: -5 }} />}
        </div>
      </div>
    </div>
  );
}

export default memo(ReelItem);
