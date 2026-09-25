import React, { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { AnimatePresence } from "framer-motion";
import { Download, Flame, Shield, Sparkles, UserCheck, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toggleLike } from "@/lib/likes";
import { toast } from "@/lib/toast";
import { exportToCsv } from "@/utils/exportCsv";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { SearchInput, Segmented } from "@/components/common/Controls";
import { useConfirm } from "@/components/common/Modal";
import PostCard from "@/components/community/PostCard";
import PostComposer from "@/components/community/PostComposer";
import PostViewer from "@/components/community/PostViewer";

const TABS = [
  { id: "latest", label: "Latest", icon: Sparkles },
  { id: "top", label: "Top this week", icon: Flame },
  { id: "following", label: "Following", icon: UserCheck },
];

export default function CommunityPage() {
  const { user } = useAuth();
  const confirm = useConfirm();
  const [params, setParams] = useSearchParams();
  const [tab, setTab] = useState("latest");
  const [search, setSearch] = useState("");
  const { data: posts, setData, loading } = useLiveQuery("CommunityPost", null, { sort: "-created_date", limit: 300 });

  const topEmail = useMemo(() => {
    const stats = {};
    posts.forEach((p) => { if (p.user_email) stats[p.user_email] = (stats[p.user_email] || 0) + (p.likes?.length || 0); });
    return Object.entries(stats).sort((a, b) => b[1] - a[1])[0]?.[0] || null;
  }, [posts]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    let list = posts.filter((p) => !q || [p.title, p.description, p.user_display_name].some((f) => String(f || "").toLowerCase().includes(q)));
    if (tab === "following") list = list.filter((p) => (user?.following || []).includes(p.user_email));
    if (tab === "top") {
      const weekAgo = Date.now() - 7 * 86400000;
      list = list.filter((p) => new Date(p.created_date).getTime() > weekAgo).sort((a, b) => (b.likes?.length || 0) - (a.likes?.length || 0));
    }
    return list;
  }, [posts, search, tab, user?.following]);

  const openId = params.get("post");
  const open = posts.find((p) => p.id === openId) || null;
  const setOpen = (id) => setParams((p) => { const n = new URLSearchParams(p); if (id) n.set("post", id); else n.delete("post"); n.delete("compose"); return n; });

  const like = (post) => toggleLike({ entity: "CommunityPost", record: post, user, setData, message: `liked your post${post.title ? ` "${post.title}"` : ""}`, link: `/Community?post=${post.id}` });
  const remove = async (post) => {
    const ok = await confirm({ title: "Delete post?", message: "This can't be undone.", confirmLabel: "Delete", danger: true });
    if (!ok) return;
    try { await base44.entities.CommunityPost.delete(post.id); setOpen(null); toast.success("Post deleted"); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };

  return (
    <Page width="max-w-7xl">
      <PageHeader
        eyebrow="Share & discover"
        title="Community"
        subtitle={`${posts.length} posts from ${new Set(posts.map((p) => p.user_email)).size} artists`}
        icon={Users}
        actions={<>
          <span className="badge-pink !py-1.5" style={{ color: "var(--success)", background: "rgb(23 166 115 / 0.1)", borderColor: "rgb(23 166 115 / 0.25)" }}><Shield className="w-3.5 h-3.5" /> Moderated</span>
          <button onClick={() => exportToCsv(filtered.map((p) => ({ title: p.title || "", user: p.user_display_name, likes: p.likes?.length || 0, date: p.created_date })), "community")} className="icon-btn icon-btn-bordered" title="Export CSV" aria-label="Export CSV"><Download className="w-4 h-4" /></button>
        </>}
      >
        <div className="flex flex-col md:flex-row gap-3 md:items-center">
          <Segmented options={TABS} value={tab} onChange={setTab} size="sm" />
          <SearchInput value={search} onChange={setSearch} placeholder="Search posts and artists…" className="md:w-72 md:ml-auto" />
        </div>
      </PageHeader>

      {user && <PostComposer autoOpen={params.get("compose") === "1"} />}

      {loading ? (
        <div className="columns-1 sm:columns-2 lg:columns-3 xl:columns-4 gap-5">
          {Array.from({ length: 8 }).map((_, i) => <div key={i} className="skeleton mb-5 break-inside-avoid" style={{ height: 200 + (i % 3) * 80 }} />)}
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={tab === "following" ? UserCheck : Users}
          title={tab === "following" ? "Nothing from people you follow" : tab === "top" ? "No posts this week yet" : "No posts found"}
          text={tab === "following" ? "Follow artists from their profile to see their posts here." : "Be the first to share something!"}
        />
      ) : (
        <div className="columns-1 sm:columns-2 lg:columns-3 xl:columns-4 gap-5">
          <AnimatePresence>
            {filtered.map((p, i) => (
              <div key={p.id} className="break-inside-avoid mb-5">
                <PostCard post={p} index={i} onOpen={() => setOpen(p.id)} liked={!!user && (p.likes || []).includes(user.email)} likeCount={p.likes?.length || 0} onLike={() => like(p)} isTopArtist={p.user_email === topEmail} />
              </div>
            ))}
          </AnimatePresence>
        </div>
      )}

      <PostViewer post={open} onClose={() => setOpen(null)} liked={!!open && !!user && (open.likes || []).includes(user.email)} likeCount={open?.likes?.length || 0} onLike={() => open && like(open)} onDelete={() => open && remove(open)} />
    </Page>
  );
}
