import React from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Crown, MessageCircle } from "lucide-react";
import Avatar from "@/components/common/Avatar";
import LikeButton from "@/components/common/LikeButton";
import { profileLink, timeAgo } from "@/lib/format";

const TEXT_BACKGROUNDS = [
  "linear-gradient(145deg, rgb(var(--accent-2-rgb) / 0.35), rgb(var(--accent-rgb) / 0.12))",
  "linear-gradient(145deg, #e9e1ff, #c9b8ff)",
  "linear-gradient(145deg, #dff7ee, #a7e8d2)",
  "linear-gradient(145deg, #ffe9dc, #ffc4a6)",
];

export default function PostCard({ post, index = 0, onOpen, liked, likeCount, onLike, isTopArtist }) {
  const bg = TEXT_BACKGROUNDS[(post.id || "").charCodeAt(0) % TEXT_BACKGROUNDS.length || 0];
  return (
    <motion.article
      exit={{ opacity: 0, scale: 0.96 }}
      whileHover={{ y: -4 }}
      className="enter card-sm !rounded-3xl overflow-hidden group cursor-pointer"
      style={{ "--d": `${Math.min(index, 12) * 40}ms` }}
      onClick={onOpen}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === "Enter") onOpen?.(); }}
    >
      {post.image_url ? (
        <div className="relative overflow-hidden" style={{ background: "var(--surface-2)" }}>
          <img src={post.image_url} alt={post.title || ""} loading="lazy" className="w-full object-cover transition-transform duration-700 group-hover:scale-[1.05]" style={{ minHeight: 120 }} />
        </div>
      ) : (
        <div className="p-5 pb-3" style={{ background: bg }}>
          <p className="font-display text-xl leading-snug line-clamp-6" style={{ color: "#2a1620" }}>“{post.description || post.title}”</p>
        </div>
      )}
      <div className="p-4">
        {post.title && post.image_url && <h3 className="font-semibold text-sm mb-1 line-clamp-1" style={{ color: "var(--text-primary)" }}>{post.title}</h3>}
        {post.description && post.image_url && <p className="text-xs line-clamp-2 mb-3" style={{ color: "var(--text-secondary)" }}>{post.description}</p>}
        <div className="flex items-center gap-2">
          <Link to={profileLink(post.user_email)} onClick={(e) => e.stopPropagation()} className="flex items-center gap-2 min-w-0 flex-1 group/author">
            <Avatar src={post.user_profile_picture} name={post.user_display_name} size={28} />
            <span className="min-w-0">
              <span className="text-xs font-bold truncate flex items-center gap-1 group-hover/author:underline" style={{ color: "var(--text-primary)" }}>
                {isTopArtist && <Crown className="w-3 h-3 flex-shrink-0" style={{ color: "#f0a020" }} />}{post.user_display_name}
              </span>
              <span className="block text-[10px]" style={{ color: "var(--text-muted)" }}>{timeAgo(post.created_date)}</span>
            </span>
          </Link>
          <span className="icon-btn w-8 h-8 pointer-events-none" aria-hidden="true"><MessageCircle className="w-4 h-4" /></span>
          <LikeButton liked={liked} count={likeCount} onToggle={onLike} variant="plain" />
        </div>
      </div>
    </motion.article>
  );
}
