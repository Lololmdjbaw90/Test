import React from "react";
import { motion, useMotionValue, useSpring, useTransform } from "framer-motion";
import { Bookmark, Music, Star } from "lucide-react";
import LikeButton from "@/components/common/LikeButton";
import Avatar from "@/components/common/Avatar";

// Gallery tile with a subtle 3D tilt that follows the cursor.
export default function ArtworkCard({ artwork, index = 0, onOpen, liked, likeCount, onLike, saved, onSave }) {
  const mx = useMotionValue(0.5);
  const my = useMotionValue(0.5);
  const rotateX = useSpring(useTransform(my, [0, 1], [5, -5]), { stiffness: 200, damping: 20 });
  const rotateY = useSpring(useTransform(mx, [0, 1], [-5, 5]), { stiffness: 200, damping: 20 });

  const onMove = (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    mx.set((e.clientX - r.left) / r.width);
    my.set((e.clientY - r.top) / r.height);
  };
  const onLeave = () => { mx.set(0.5); my.set(0.5); };

  return (
    <motion.div
      exit={{ opacity: 0, scale: 0.95 }}
      className="enter"
      style={{ perspective: 900, "--d": `${Math.min(index, 12) * 35}ms` }}
    >
      <motion.div
        role="button"
        tabIndex={0}
        onClick={onOpen}
        onKeyDown={(e) => { if (e.key === "Enter") onOpen?.(); }}
        onMouseMove={onMove}
        onMouseLeave={onLeave}
        style={{ rotateX, rotateY, transformStyle: "preserve-3d" }}
        className="group relative cursor-pointer rounded-3xl overflow-hidden card-sm !rounded-3xl"
        aria-label={`Open ${artwork.title}`}
      >
        <div className="relative overflow-hidden" style={{ background: "var(--surface-2)" }}>
          <img src={artwork.image_url} alt={artwork.title} loading="lazy" className="w-full object-cover transition-transform duration-700 ease-out group-hover:scale-[1.06]" style={{ minHeight: 120 }} />
          <div className="absolute inset-0 can-hover:opacity-0 can-hover:group-hover:opacity-100 transition-opacity duration-300" style={{ background: "linear-gradient(to top, rgb(20 8 14 / 0.7), transparent 50%)" }} />
          <div className="absolute top-3 left-3 flex gap-1.5">
            {artwork.featured && <span className="badge-pink glass !text-[10px]"><Star className="w-3 h-3 fill-current" /> Featured</span>}
            {artwork.music_url && <span className="badge-pink glass !text-[10px]"><Music className="w-3 h-3" /></span>}
          </div>
          <button
            onClick={(e) => { e.stopPropagation(); onSave?.(); }}
            className="absolute top-3 right-3 w-9 h-9 rounded-full flex items-center justify-center transition-all can-hover:opacity-0 group-hover:opacity-100 focus:opacity-100"
            style={saved ? { background: "var(--accent-grad)", color: "#fff", opacity: 1 } : { background: "rgb(255 255 255 / 0.92)", color: "#5b4450" }}
            aria-label={saved ? "Remove from saved" : "Save"}
            aria-pressed={saved}
          >
            <Bookmark className={`w-4 h-4 ${saved ? "fill-current" : ""}`} />
          </button>
          <div className="absolute bottom-0 inset-x-0 p-3 flex items-end gap-2 transition-all duration-300 can-hover:translate-y-2 can-hover:opacity-0 can-hover:group-hover:translate-y-0 can-hover:group-hover:opacity-100">
            <div className="flex-1 min-w-0 text-white">
              <p className="font-display text-base font-semibold truncate">{artwork.title}</p>
              {artwork.user_display_name && <p className="text-[11px] opacity-80 truncate">by {artwork.user_display_name}</p>}
            </div>
            <LikeButton variant="overlay" liked={liked} count={likeCount} onToggle={onLike} />
          </div>
        </div>
        <div className="px-3.5 py-3 flex items-center gap-2 md:hidden">
          <Avatar src={artwork.user_profile_picture} name={artwork.user_display_name} size={22} />
          <p className="text-xs font-semibold truncate flex-1" style={{ color: "var(--text-primary)" }}>{artwork.title}</p>
          <LikeButton variant="plain" liked={liked} count={likeCount} onToggle={onLike} />
        </div>
      </motion.div>
    </motion.div>
  );
}
