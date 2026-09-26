import React, { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Bookmark, ChevronLeft, ChevronRight, Link2, Maximize2, Pause, Play, Star, Trash2, X } from "lucide-react";
import Modal from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import LikeButton from "@/components/common/LikeButton";
import CommentSection from "./CommentSection";
import PingButton from "./PingButton";
import { usePlayer } from "@/lib/player";
import { toast } from "@/lib/toast";
import { profileLink, siteUrl, timeAgo } from "@/lib/format";
import { feedback } from "@/lib/feedback";

// Tap-to-open full-screen view of the image (pinch to zoom on phones).
function Lightbox({ src, alt, onClose }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === "Escape") { e.stopImmediatePropagation(); onClose(); } };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onClose]);
  return createPortal(
    <motion.div
      className="fixed inset-0 z-[140] flex items-center justify-center safe-top safe-x"
      style={{ background: "rgb(8 4 6 / 0.96)", touchAction: "pinch-zoom" }}
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}
      onClick={onClose}
      role="dialog" aria-modal="true" aria-label={alt}
    >
      <img src={src} alt={alt} className="max-w-full max-h-full object-contain select-none" draggable={false} />
      <button onClick={onClose} className="absolute top-[calc(env(safe-area-inset-top)+0.75rem)] right-3 w-11 h-11 rounded-full flex items-center justify-center text-white" style={{ background: "rgb(255 255 255 / 0.14)" }} aria-label="Close full screen"><X className="w-5 h-5" /></button>
    </motion.div>,
    document.body,
  );
}

// Artwork viewer. Phones and tablets: the image on top (swipe for the next
// piece, tap for full screen), then title and artist, one row of actions,
// details and comments. Desktop: image left, details right; ←/→ to browse.
export default function ArtworkViewer({ artwork, position, onClose, onPrev, onNext, liked, likeCount, onLike, saved, onSave, isAdmin, onToggleFeatured, onDelete }) {
  const player = usePlayer();
  const [zoom, setZoom] = useState(false);
  const dir = useRef(0);
  const dragged = useRef(false);
  const prev = onPrev ? () => { dir.current = -1; feedback("swipe"); onPrev(); } : null;
  const next = onNext ? () => { dir.current = 1; feedback("swipe"); onNext(); } : null;

  useEffect(() => {
    if (!artwork) { setZoom(false); return undefined; }
    const onKey = (e) => {
      if (["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
      if (e.key === "ArrowLeft") prev?.();
      if (e.key === "ArrowRight") next?.();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [artwork, onPrev, onNext]); // eslint-disable-line react-hooks/exhaustive-deps

  const share = async () => {
    const url = siteUrl(`/Gallery?art=${artwork.id}`);
    try {
      if (navigator.share && window.matchMedia("(pointer: coarse)").matches) { await navigator.share({ title: artwork.title, url }); return; }
    } catch { return; /* cancelled */ }
    try { await navigator.clipboard.writeText(url); toast.success("Link copied"); } catch { toast(url); }
  };
  const track = artwork?.music_url ? { id: `art-${artwork.id}`, title: artwork.title, artist: artwork.user_display_name || "Gallery", src: artwork.music_url, cover: artwork.image_url } : null;
  const playing = track && player.isPlaying(track.id);
  const tags = artwork ? [artwork.medium && artwork.medium.replace("_", " "), artwork.year].filter(Boolean) : [];

  return (
    <Modal open={!!artwork} onClose={onClose} size="max-w-6xl" padded={false} hideHeader autoFocus={false}>
      {artwork && (
        <div className="flex flex-col lg:flex-row lg:h-[82vh]">
          {/* Image */}
          <div className="relative lg:flex-1 flex items-center justify-center px-3 pt-8 pb-4 sm:p-6 lg:p-8 overflow-hidden" style={{ background: "#140a10", minHeight: "min(46vh, 420px)" }}>
            <img src={artwork.image_url} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-30 blur-2xl scale-110" />
            <span className="sm:hidden absolute top-2 left-1/2 w-10 h-1 rounded-full" style={{ translate: "-50% 0", background: "rgb(255 255 255 / 0.35)" }} aria-hidden="true" />
            <AnimatePresence mode="wait" initial={false}>
              <motion.img
                key={artwork.id}
                src={artwork.image_url}
                alt={artwork.title}
                draggable={false}
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
                onClick={() => { if (!dragged.current) setZoom(true); }}
                className="relative w-auto max-w-full max-h-[48vh] sm:max-h-[56vh] lg:max-h-[74vh] object-contain rounded-2xl shadow-2xl cursor-zoom-in select-none"
              />
            </AnimatePresence>
            {prev && <button onClick={prev} className="hidden sm:flex absolute left-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full glass items-center justify-center" style={{ color: "var(--text-primary)" }} aria-label="Previous artwork"><ChevronLeft className="w-5 h-5" /></button>}
            {next && <button onClick={next} className="hidden sm:flex absolute right-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full glass items-center justify-center" style={{ color: "var(--text-primary)" }} aria-label="Next artwork"><ChevronRight className="w-5 h-5" /></button>}
            <div className="absolute bottom-3 inset-x-3 flex items-center justify-between pointer-events-none">
              {position && position.total > 1 ? <span className="px-2.5 py-1 rounded-full text-[11px] font-bold text-white tabular-nums" style={{ background: "rgb(0 0 0 / 0.45)" }}>{position.index} / {position.total}</span> : <span />}
              <button onClick={() => setZoom(true)} className="pointer-events-auto w-9 h-9 rounded-full flex items-center justify-center text-white" style={{ background: "rgb(0 0 0 / 0.45)" }} aria-label="View full screen"><Maximize2 className="w-4 h-4" /></button>
            </div>
          </div>

          {/* Details */}
          <div className="lg:w-[400px] flex flex-col min-h-0">
            <div className="p-4 sm:p-6 space-y-4 lg:overflow-y-auto scroll flex-1">
              <div className="lg:pr-10">
                <h2 className="font-display text-[1.9rem] leading-tight" style={{ color: "var(--text-primary)" }}>{artwork.title}</h2>
                {(tags.length > 0 || artwork.featured) && (
                  <div className="flex flex-wrap gap-1.5 mt-2">
                    {artwork.featured && <span className="badge-pink"><Star className="w-3 h-3 fill-current" /> Featured</span>}
                    {tags.map((t) => <span key={t} className="badge-pink capitalize" style={{ color: "var(--text-secondary)", background: "var(--surface-2)", borderColor: "var(--border-c)" }}>{t}</span>)}
                  </div>
                )}
              </div>

              {artwork.user_email && (
                <Link to={profileLink(artwork.user_email)} className="flex items-center gap-3 p-2 -mx-2 rounded-2xl transition-colors can-hover:hover:bg-[var(--surface-2)] active:bg-[var(--surface-2)]">
                  <Avatar src={artwork.user_profile_picture} name={artwork.user_display_name} size={42} />
                  <span className="flex-1 min-w-0">
                    <span className="block text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{artwork.user_display_name}</span>
                    <span className="block text-xs" style={{ color: "var(--text-muted)" }}>Posted {timeAgo(artwork.created_date)}</span>
                  </span>
                  <ChevronRight className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
                </Link>
              )}

              <div className="grid grid-flow-col auto-cols-fr gap-2">
                <LikeButton variant="tile" liked={liked} count={likeCount} onToggle={onLike} />
                <button onClick={onSave} className="action-tile" data-active={saved} aria-pressed={saved}><Bookmark className={`w-5 h-5 ${saved ? "fill-current" : ""}`} /><span>{saved ? "Saved" : "Save"}</span></button>
                <button onClick={share} className="action-tile"><Link2 className="w-5 h-5" /><span>Share</span></button>
                <PingButton artwork={artwork} variant="tile" />
              </div>

              {artwork.description && <p className="text-[15px] leading-relaxed whitespace-pre-line" style={{ color: "var(--text-secondary)" }}>{artwork.description}</p>}

              {track && (
                <button onClick={() => player.toggle(track, [track])} className="w-full card-sm p-3 flex items-center gap-3 text-left card-hover">
                  <span className="w-10 h-10 rounded-full flex items-center justify-center text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}>{playing ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4 ml-0.5" />}</span>
                  <span className="flex-1">
                    <span className="block text-sm font-bold" style={{ color: "var(--text-primary)" }}>Background music</span>
                    <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{playing ? "Playing — keeps going while you browse" : "Play the soundtrack for this piece"}</span>
                  </span>
                  {playing && <span className="equalizer" style={{ color: "var(--accent-rose)" }}><span /><span /><span /></span>}
                </button>
              )}

              {isAdmin && (
                <div className="flex items-center gap-1 rounded-2xl px-3 py-1.5" style={{ background: "var(--surface-2)" }}>
                  <span className="eyebrow flex-1">Admin</span>
                  <button onClick={onToggleFeatured} className="btn-ghost text-xs !min-h-0 !py-1.5"><Star className={`w-3.5 h-3.5 ${artwork.featured ? "fill-current" : ""}`} />{artwork.featured ? "Unfeature" : "Feature"}</button>
                  <button onClick={onDelete} className="btn-ghost text-xs !min-h-0 !py-1.5" style={{ color: "var(--danger)" }}><Trash2 className="w-3.5 h-3.5" /> Delete</button>
                </div>
              )}

              <div className="divider" />
              <CommentSection entity="Comment" field="artwork_id" targetId={artwork.id} ownerEmail={artwork.user_email || artwork.created_by} link={`/Gallery?art=${artwork.id}`} />
            </div>
          </div>
        </div>
      )}
      <AnimatePresence>{zoom && artwork && <Lightbox key="zoom" src={artwork.image_url} alt={artwork.title} onClose={() => setZoom(false)} />}</AnimatePresence>
    </Modal>
  );
}
