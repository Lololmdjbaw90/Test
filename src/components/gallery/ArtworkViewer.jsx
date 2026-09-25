import React, { useEffect } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Bookmark, ChevronLeft, ChevronRight, Link2, Pause, Play, Star, Trash2 } from "lucide-react";
import Modal from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import LikeButton from "@/components/common/LikeButton";
import CommentSection from "./CommentSection";
import PingButton from "./PingButton";
import { usePlayer } from "@/lib/player";
import { toast } from "@/lib/toast";
import { profileLink, timeAgo } from "@/lib/format";

// Full-screen artwork viewer with ←/→ navigation.
export default function ArtworkViewer({ artwork, onClose, onPrev, onNext, liked, likeCount, onLike, saved, onSave, isAdmin, onToggleFeatured, onDelete }) {
  const player = usePlayer();

  useEffect(() => {
    if (!artwork) return undefined;
    const onKey = (e) => {
      if (["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
      if (e.key === "ArrowLeft") onPrev?.();
      if (e.key === "ArrowRight") onNext?.();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [artwork, onPrev, onNext]);

  const share = async () => {
    const url = `${window.location.origin}/Gallery?art=${artwork.id}`;
    try { await navigator.clipboard.writeText(url); toast.success("Link copied"); } catch { toast(url); }
  };
  const track = artwork?.music_url ? { id: `art-${artwork.id}`, title: artwork.title, artist: artwork.user_display_name || "Gallery", src: artwork.music_url, cover: artwork.image_url } : null;
  const playing = track && player.isPlaying(track.id);

  return (
    <Modal open={!!artwork} onClose={onClose} size="max-w-6xl" padded={false} hideHeader>
      {artwork && (
        <div className="flex flex-col lg:flex-row lg:h-[82vh]">
          <div className="relative lg:flex-1 flex items-center justify-center min-h-[42vh] lg:min-h-0 overflow-hidden" style={{ background: "#140a10" }}>
            <img src={artwork.image_url} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-30 blur-2xl scale-110" />
            <AnimatePresence mode="wait">
              <motion.img
                key={artwork.id}
                src={artwork.image_url}
                alt={artwork.title}
                initial={{ opacity: 0, scale: 0.96 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 1.02 }}
                transition={{ duration: 0.3 }}
                className="relative max-w-full max-h-[42vh] lg:max-h-[78vh] object-contain rounded-xl shadow-2xl"
              />
            </AnimatePresence>
            {onPrev && <button onClick={onPrev} className="absolute left-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full glass flex items-center justify-center" style={{ color: "var(--text-primary)" }} aria-label="Previous artwork"><ChevronLeft className="w-5 h-5" /></button>}
            {onNext && <button onClick={onNext} className="absolute right-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full glass flex items-center justify-center" style={{ color: "var(--text-primary)" }} aria-label="Next artwork"><ChevronRight className="w-5 h-5" /></button>}
          </div>
          <div className="lg:w-[400px] flex flex-col min-h-0">
            <div className="p-5 sm:p-6 space-y-4 overflow-y-auto scroll flex-1">
              <div className="pr-10">
                <div className="flex flex-wrap gap-1.5 mb-2">
                  {artwork.featured && <span className="badge-pink"><Star className="w-3 h-3 fill-current" /> Featured</span>}
                  {artwork.medium && <span className="badge-pink capitalize">{artwork.medium.replace("_", " ")}</span>}
                  {artwork.year && <span className="badge-pink">{artwork.year}</span>}
                </div>
                <h2 className="font-display text-3xl font-semibold leading-tight" style={{ color: "var(--text-primary)" }}>{artwork.title}</h2>
              </div>
              {artwork.user_email && (
                <Link to={profileLink(artwork.user_email)} className="flex items-center gap-3 group">
                  <Avatar src={artwork.user_profile_picture} name={artwork.user_display_name} size={40} />
                  <span>
                    <span className="block text-sm font-bold group-hover:underline" style={{ color: "var(--text-primary)" }}>{artwork.user_display_name}</span>
                    <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{timeAgo(artwork.created_date)}</span>
                  </span>
                </Link>
              )}
              {artwork.description && <p className="text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>{artwork.description}</p>}

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

              <div className="flex flex-wrap items-center gap-2">
                <LikeButton liked={liked} count={likeCount} onToggle={onLike} />
                <button onClick={onSave} className="chip" data-active={saved} aria-pressed={saved}><Bookmark className={`w-4 h-4 ${saved ? "fill-current" : ""}`} />{saved ? "Saved" : "Save"}</button>
                <button onClick={share} className="chip"><Link2 className="w-4 h-4" /> Share</button>
                <PingButton artwork={artwork} />
              </div>

              {isAdmin && (
                <div className="flex gap-2 pt-1">
                  <button onClick={onToggleFeatured} className="btn-outline text-xs"><Star className={`w-3.5 h-3.5 ${artwork.featured ? "fill-current" : ""}`} />{artwork.featured ? "Unfeature" : "Feature"}</button>
                  <button onClick={onDelete} className="btn-ghost text-xs" style={{ color: "var(--danger)" }}><Trash2 className="w-3.5 h-3.5" /> Delete</button>
                </div>
              )}

              <div className="divider" />
              <CommentSection entity="Comment" field="artwork_id" targetId={artwork.id} ownerEmail={artwork.user_email || artwork.created_by} link={`/Gallery?art=${artwork.id}`} />
            </div>
          </div>
        </div>
      )}
    </Modal>
  );
}
