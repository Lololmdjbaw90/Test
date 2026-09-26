import React from "react";
import { Link } from "react-router-dom";
import { Link2, Trash2 } from "lucide-react";
import Modal from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import LikeButton from "@/components/common/LikeButton";
import CommentSection from "@/components/gallery/CommentSection";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { profileLink, siteUrl, timeAgo } from "@/lib/format";

export default function PostViewer({ post, onClose, liked, likeCount, onLike, onDelete }) {
  const { user } = useAuth();
  const canDelete = post && user && (user.email === post.user_email || user.role === "admin");
  const share = async () => {
    const url = siteUrl(`/Community?post=${post.id}`);
    try { await navigator.clipboard.writeText(url); toast.success("Link copied"); } catch { toast(url); }
  };
  return (
    <Modal open={!!post} onClose={onClose} size={post?.image_url ? "max-w-5xl" : "lg"} padded={false} hideHeader>
      {post && (
        <div className={`flex flex-col ${post.image_url ? "lg:flex-row lg:h-[80vh]" : ""}`}>
          {post.image_url && (
            <div className="relative lg:flex-1 flex items-center justify-center overflow-hidden min-h-[40vh] lg:min-h-0" style={{ background: "#140a10" }}>
              <img src={post.image_url} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-30 blur-2xl scale-110" />
              <img src={post.image_url} alt={post.title || ""} className="relative max-w-full max-h-[40vh] lg:max-h-[76vh] object-contain rounded-xl" />
            </div>
          )}
          <div className={`${post.image_url ? "lg:w-[400px]" : ""} p-5 sm:p-6 space-y-4 overflow-y-auto scroll`}>
            <Link to={profileLink(post.user_email)} className="flex items-center gap-3 pr-10 group" onClick={onClose}>
              <Avatar src={post.user_profile_picture} name={post.user_display_name} size={42} />
              <span>
                <span className="block text-sm font-bold group-hover:underline" style={{ color: "var(--text-primary)" }}>{post.user_display_name}</span>
                <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{timeAgo(post.created_date)}</span>
              </span>
            </Link>
            {post.title && <h2 className="font-display text-2xl font-semibold" style={{ color: "var(--text-primary)" }}>{post.title}</h2>}
            {post.description && <p className="text-sm leading-relaxed whitespace-pre-wrap" style={{ color: "var(--text-secondary)" }}>{post.description}</p>}
            <div className="flex flex-wrap gap-2">
              <LikeButton liked={liked} count={likeCount} onToggle={onLike} />
              <button onClick={share} className="chip"><Link2 className="w-4 h-4" /> Share</button>
              {canDelete && <button onClick={onDelete} className="chip" style={{ color: "var(--danger)" }}><Trash2 className="w-4 h-4" /> Delete</button>}
            </div>
            <div className="divider" />
            <CommentSection entity="CommunityComment" field="post_id" targetId={post.id} ownerEmail={post.user_email} link={`/Community?post=${post.id}`} />
          </div>
        </div>
      )}
    </Modal>
  );
}
