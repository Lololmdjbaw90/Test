import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowUp, Bookmark, Download, Flame, Search, Sparkles, UserCheck, Users, X, Clock } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toggleLike } from "@/lib/likes";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";
import { splitFriendships, toggleFollow, useFriendships } from "@/lib/social";
import { setBlocked, useBlocked } from "@/lib/safety";
import { buildTaste, hashtags, hidePost, markSeen, rankFeed, relatedPosts, seenPosts, suggestPeople, suggestServers, trendingTags } from "@/lib/ranking";
import { exportToCsv } from "@/utils/exportCsv";
import { Page, EmptyState } from "@/components/common/Page";
import { SearchInput, Segmented } from "@/components/common/Controls";
import { useConfirm } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import FeedPost from "@/components/community/FeedPost";
import PostComposer from "@/components/community/PostComposer";
import PostViewer from "@/components/community/PostViewer";
import { ActiveCreators, ServerSuggestions, SuggestedPeople, TrendingTags } from "@/components/community/Discover";
import { feedback } from "@/lib/feedback";

const TABS = [
  { id: "foryou", label: "For you", icon: Sparkles },
  { id: "following", label: "Following", icon: UserCheck },
  { id: "latest", label: "Latest", icon: Clock },
  { id: "top", label: "Top", icon: Flame },
  { id: "saved", label: "Saved", icon: Bookmark },
];
const postText = (p) => `${p.title || ""} ${p.description || ""}`;

// Marks posts as seen once they've been mostly on screen for a moment, so the
// "For you" ranking can favour things you haven't scrolled past yet.
function useSeenTracker(count) {
  useEffect(() => {
    if (typeof IntersectionObserver === "undefined") return undefined;
    const timers = new Map();
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        const id = e.target.getAttribute("data-post-id");
        if (e.isIntersecting) { if (!timers.has(id)) timers.set(id, setTimeout(() => markSeen(id), 1200)); }
        else { clearTimeout(timers.get(id)); timers.delete(id); }
      });
    }, { threshold: 0.6 });
    document.querySelectorAll("[data-post-id]").forEach((el) => io.observe(el));
    return () => { io.disconnect(); timers.forEach(clearTimeout); };
  }, [count]);
}

export default function CommunityPage() {
  const { user: me, updateMe, isAdmin } = useAuth();
  const confirm = useConfirm();
  const [params, setParams] = useSearchParams();
  const [tab, setTab] = useState("foryou");
  const [search, setSearch] = useState("");
  const [searchOpen, setSearchOpen] = useState(false);
  const [refresh, setRefresh] = useState(0);
  const [dismissed, setDismissed] = useState(() => new Set());
  const tag = params.get("tag");

  const { data: posts, setData, loading } = useLiveQuery("CommunityPost", null, { sort: "-created_date", limit: 300 });
  const { data: allComments, loading: commentsLoading } = useLiveQuery("CommunityComment", null, { sort: "-created_date", limit: 600 });
  const { data: users } = useLiveQuery("User", null, { live: false });
  const { data: communities } = useLiveQuery("Community", null, { live: false });
  const { friendships } = useFriendships(me?.email);
  const { friendEmails } = splitFriendships(friendships, me?.email);

  const usersByEmail = useMemo(() => Object.fromEntries(users.map((u) => [u.email, u])), [users]);
  const blocked = useBlocked();
  const comments = useMemo(() => allComments.filter((c) => !String(c.post_id || "").startsWith("profile_") && !blocked.has(c.user_email)), [allComments, blocked]);
  const commentsByPost = useMemo(() => {
    const m = {};
    [...comments].reverse().forEach((c) => { (m[c.post_id] = m[c.post_id] || []).push(c); });
    return m;
  }, [comments]);
  // Only what the ranking uses: saving a post mustn't re-rank the whole feed.
  const taste = useMemo(() => buildTaste({ me, friends: friendEmails, posts, comments }), [me?.email, me?.following, me?.interests, friendEmails, posts, comments]); // eslint-disable-line react-hooks/exhaustive-deps
  const circle = useMemo(() => new Set([...taste.following, ...taste.friends]), [taste]);
  const followingSet = taste.following;
  const saved = useMemo(() => new Set(me?.saved_posts || []), [me?.saved_posts]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return posts.filter((p) => !blocked.has(p.user_email) && (!q || [p.title, p.description, p.user_display_name].some((f) => String(f || "").toLowerCase().includes(q))) && (!tag || hashtags(postText(p)).includes(tag)));
  }, [posts, search, tag, blocked]);

  const listNow = useMemo(() => {
    if (tab === "foryou") return rankFeed(filtered, { taste, comments, users: usersByEmail });
    let list = filtered;
    if (tab === "following") list = list.filter((p) => circle.has(p.user_email) || p.user_email === me?.email);
    if (tab === "saved") list = list.filter((p) => saved.has(p.id));
    if (tab === "top") {
      const weekAgo = Date.now() - 7 * 86400000;
      list = list.filter((p) => new Date(p.created_date).getTime() > weekAgo).sort((a, b) => ((b.likes?.length || 0) + (commentsByPost[b.id]?.length || 0) * 2) - ((a.likes?.length || 0) + (commentsByPost[a.id]?.length || 0) * 2));
    }
    return list.map((post) => ({ post, reason: null }));
  }, [filtered, tab, taste, comments, usersByEmail, circle, saved, commentsByPost, me?.email, refresh]); // eslint-disable-line react-hooks/exhaustive-deps

  // Keep the order stable while you scroll: likes and new posts don't reshuffle
  // the feed. New posts wait behind a "new posts" pill (yours show up at once).
  const ready = !loading && !commentsLoading;
  const frozen = useRef({ key: null, ids: [] });
  const feedKey = `${tab}|${tag}|${search}|${refresh}`;
  const { feed, freshCount } = useMemo(() => {
    const byId = new Map(listNow.map((x) => [x.post.id, x]));
    if (!ready) return { feed: [], freshCount: 0 };
    if (frozen.current.key !== feedKey || tab === "saved") frozen.current = { key: feedKey, ids: listNow.map((x) => x.post.id) };
    const known = new Set(frozen.current.ids);
    const fresh = listNow.filter((x) => !known.has(x.post.id));
    const mine = fresh.filter((x) => x.post.user_email === me?.email);
    if (mine.length) frozen.current.ids = [...mine.map((x) => x.post.id), ...frozen.current.ids];
    return { feed: frozen.current.ids.map((id) => byId.get(id)).filter(Boolean), freshCount: fresh.length - mine.length };
  }, [listNow, feedKey, ready, tab, me?.email]);
  // Render the feed in pages of 10 so long feeds stay smooth; more load as you near the end.
  const PAGE = 10;
  const [visibleCount, setVisibleCount] = useState(PAGE);
  useEffect(() => { setVisibleCount(PAGE); }, [feedKey]);
  const shown = feed.slice(0, visibleCount);
  const sentinelRef = useRef(null);
  useEffect(() => {
    const el = sentinelRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return undefined;
    const io = new IntersectionObserver((entries) => { if (entries[0].isIntersecting) setVisibleCount((n) => n + PAGE); }, { rootMargin: "900px 0px" });
    io.observe(el);
    return () => io.disconnect();
  }, [shown.length, feed.length]);
  useSeenTracker(shown.length);

  const people = useMemo(() => suggestPeople(users, { me, taste, posts, limit: 8 }).filter((x) => !dismissed.has(x.user.email) && !blocked.has(x.user.email)), [users, me, taste, posts, dismissed, blocked]);
  const servers = useMemo(() => suggestServers(communities, { me, taste, limit: 3 }), [communities, me, taste]);
  const tags = useMemo(() => trendingTags(posts, { limit: 6 }), [posts]);
  const creators = useMemo(() => {
    const seen = seenPosts();
    const byAuthor = new Map();
    posts.forEach((p) => {
      if (p.user_email === me?.email || blocked.has(p.user_email) || Date.now() - new Date(p.created_date).getTime() > 3 * 86400000) return;
      const c = byAuthor.get(p.user_email) || { email: p.user_email, name: usersByEmail[p.user_email] ? displayName(usersByEmail[p.user_email]) : p.user_display_name, user: usersByEmail[p.user_email], picture: p.user_profile_picture, latest: p, unseen: false };
      if (!seen[p.id]) c.unseen = true;
      if (new Date(p.created_date) > new Date(c.latest.created_date)) c.latest = p;
      byAuthor.set(p.user_email, c);
    });
    return [...byAuthor.values()].sort((a, b) => Number(b.unseen) - Number(a.unseen) || (taste.affinity.get(b.email) || 0) - (taste.affinity.get(a.email) || 0)).slice(0, 14);
  }, [posts, me?.email, usersByEmail, taste, feed.length]); // eslint-disable-line react-hooks/exhaustive-deps

  const openId = params.get("post");
  const open = posts.find((p) => p.id === openId) || null;
  const update = (fn) => setParams((p) => { const n = new URLSearchParams(p); fn(n); return n; });
  const setOpen = (id) => { if (id) markSeen(id); update((n) => { if (id) n.set("post", id); else n.delete("post"); n.delete("compose"); }); };
  // Where the open post sits in the feed you're looking at (for swiping), and
  // what to suggest below it.
  const openIndex = open ? feed.findIndex((x) => x.post.id === open.id) : -1;
  const moreFromAuthor = useMemo(() => (open ? posts.filter((p) => p.user_email === open.user_email && p.id !== open.id).slice(0, 8) : []), [open, posts]);
  const related = useMemo(() => relatedPosts(open, filtered, { limit: 6, exclude: blocked }).filter((p) => p.user_email !== open?.user_email || moreFromAuthor.length === 0), [open, filtered, blocked, moreFromAuthor.length]);
  const setTag = (t) => { update((n) => { if (t) n.set("tag", t); else n.delete("tag"); }); document.getElementById("main")?.scrollTo({ top: 0, behavior: "smooth" }); };

  const like = (post) => toggleLike({ entity: "CommunityPost", record: post, user: me, setData, message: `liked your post${post.title ? ` "${post.title}"` : ""}`, link: `/Community?post=${post.id}` });
  const follow = async (email) => {
    try {
      const now = await toggleFollow({ me, email, updateMe });
      if (now) toast.success(`Following ${usersByEmail[email] ? displayName(usersByEmail[email]) : email.split("@")[0]}`);
    } catch (e) { toast.error(e?.message || "Could not update follow."); }
  };
  const save = async (post) => {
    feedback("save");
    const was = saved.has(post.id);
    const next = was ? [...saved].filter((id) => id !== post.id) : [...saved, post.id];
    // Shows at once; the save finishes in the background.
    updateMe({ saved_posts: next }).catch((e) => toast.error(e?.message || "Could not save."));
    if (!was) toast.success("Saved", { description: "Find it in the Saved tab" });
  };
  const remove = async (post) => {
    const ok = await confirm({ title: "Delete post?", message: "This can't be undone.", confirmLabel: "Delete", danger: true });
    if (!ok) return;
    try { await base44.entities.CommunityPost.delete(post.id); setOpen(null); toast.success("Post deleted"); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };
  const block = async (email, name) => {
    const ok = await confirm({ title: `Block ${name}?`, message: "You won't see their posts, comments or messages, and they can't call you. They won't be told.", confirmLabel: "Block", danger: true });
    if (!ok) return;
    try { await setBlocked({ me, email, updateMe, block: true }); toast.success(`${name} is blocked`, { description: "Unblock any time in Settings" }); } catch (e) { toast.error(e?.message || "Could not block."); }
  };
  const hide = (post) => {
    hidePost(post);
    setRefresh((r) => r + 1);
    toast("Got it — you'll see fewer posts like this", { icon: <Sparkles className="w-5 h-5" /> });
  };
  const showNew = () => { setRefresh((r) => r + 1); document.getElementById("main")?.scrollTo({ top: 0, behavior: "smooth" }); };
  const likersOf = (p) => [...(p.likes || [])].sort((a, b) => Number(circle.has(b)) - Number(circle.has(a)) || Number(b === me?.email) - Number(a === me?.email)).map((e) => usersByEmail[e]).filter(Boolean);

  const emptyText = {
    foryou: ["Nothing here yet", "Be the first to share something!"],
    following: ["Nothing from people you follow", "Follow artists and add friends to fill this feed."],
    latest: ["No posts found", "Try a different search."],
    top: ["No posts this week yet", "Likes and comments from the last 7 days land here."],
    saved: ["No saved posts", "Tap the bookmark on any post to keep it here."],
  }[tab];

  return (
    <Page width="max-w-[1120px]">
      <div className="grid lg:grid-cols-[minmax(0,1fr)_320px] gap-8 xl:gap-12 items-start">
        <div className="min-w-0 w-full max-w-[640px] mx-auto">
          <header className="flex items-center gap-3 mb-5">
            <div className="flex-1 min-w-0">
              <h1 className="font-display text-3xl sm:text-4xl font-semibold leading-tight" style={{ color: "var(--text-primary)" }}>Community</h1>
            </div>
            <button onClick={() => setSearchOpen((v) => !v)} className="icon-btn icon-btn-bordered" aria-label="Search posts" aria-expanded={searchOpen}><Search className="w-[18px] h-[18px]" /></button>
            {isAdmin && <button onClick={() => exportToCsv(feed.map(({ post: p }) => ({ title: p.title || "", user: p.user_display_name, likes: p.likes?.length || 0, date: p.created_date })), "community")} className="icon-btn icon-btn-bordered" title="Export CSV" aria-label="Export CSV"><Download className="w-4 h-4" /></button>}
          </header>
          <AnimatePresence initial={false}>
            {searchOpen && (
              <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} className="overflow-hidden">
                <SearchInput value={search} onChange={setSearch} placeholder="Search posts and people…" className="mb-4" autoFocus />
              </motion.div>
            )}
          </AnimatePresence>

          <div className="mb-5"><ActiveCreators me={me} creators={creators} onOpen={(c) => setOpen(c.latest.id)} onCompose={() => update((n) => n.set("compose", "1"))} /></div>
          {me && <PostComposer autoOpen={params.get("compose") === "1"} />}

          <div className="sticky top-0 z-20 -mx-4 px-4 sm:-mx-2 sm:px-2 py-2.5 mb-3 glass sm:rounded-b-2xl" style={{ borderBottom: "1px solid var(--border-c)" }}>
            <div className="overflow-x-auto no-scrollbar"><Segmented options={TABS} value={tab} onChange={setTab} size="sm" /></div>
          </div>
          <div className="lg:hidden mb-4"><TrendingTags tags={tags} active={tag} onTag={setTag} variant="chips" /></div>
          {tag && (
            <motion.div initial={{ opacity: 0, y: -6 }} animate={{ opacity: 1, y: 0 }} className="mb-4 flex items-center gap-2">
              <span className="text-sm" style={{ color: "var(--text-muted)" }}>Showing</span>
              <button onClick={() => setTag(null)} className="chip" data-active="true">#{tag} <X className="w-3.5 h-3.5" /></button>
            </motion.div>
          )}

          <AnimatePresence>
            {freshCount > 0 && (
              <motion.div initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }} className="sticky top-16 z-20 flex justify-center pointer-events-none mb-2">
                <button onClick={showNew} className="btn pointer-events-auto !py-2 text-xs" style={{ boxShadow: "var(--shadow-accent)" }}><ArrowUp className="w-4 h-4" /> {freshCount} new post{freshCount === 1 ? "" : "s"}</button>
              </motion.div>
            )}
          </AnimatePresence>

          {!ready ? (
            <div className="space-y-5">{[0, 1, 2].map((i) => <div key={i} className="card !rounded-[1.75rem] p-4 space-y-3"><div className="flex gap-3 items-center"><div className="skeleton w-10 h-10 !rounded-full" /><div className="skeleton h-4 w-32" /></div><div className="skeleton h-64" /></div>)}</div>
          ) : feed.length === 0 ? (
            <>
              <EmptyState icon={tab === "saved" ? Bookmark : tab === "following" ? UserCheck : Users} title={tag ? `No posts with #${tag}` : emptyText[0]} text={emptyText[1]} />
              {tab === "following" && <div className="lg:hidden"><SuggestedPeople items={people} followingSet={followingSet} onFollow={follow} variant="carousel" /></div>}
            </>
          ) : (
            <div className="space-y-5">
              {shown.map(({ post, reason }, i) => (
                <React.Fragment key={post.id}>
                  <FeedPost
                    post={post}
                    index={i}
                    reason={reason}
                    me={me}
                    author={usersByEmail[post.user_email]}
                    comments={commentsByPost[post.id] || []}
                    likers={likersOf(post)}
                    following={followingSet.has(post.user_email)}
                    onFollow={follow}
                    liked={!!me && (post.likes || []).includes(me.email)}
                    onLike={() => like(post)}
                    saved={saved.has(post.id)}
                    onSave={() => save(post)}
                    onOpen={() => setOpen(post.id)}
                    onTag={setTag}
                    onHide={hide}
                    onBlock={block}
                    onDelete={me && (me.email === post.user_email || isAdmin) ? remove : null}
                  />
                  {i === 2 && people.length > 0 && <div className="lg:hidden"><SuggestedPeople items={people} followingSet={followingSet} onFollow={follow} variant="carousel" onDismiss={(e) => setDismissed((s) => new Set(s).add(e))} /></div>}
                </React.Fragment>
              ))}
              {shown.length < feed.length ? (
                <div ref={sentinelRef} className="space-y-5" aria-hidden="true">
                  <div className="card !rounded-[1.75rem] p-4 space-y-3"><div className="flex gap-3 items-center"><div className="skeleton w-10 h-10 !rounded-full" /><div className="skeleton h-4 w-32" /></div><div className="skeleton h-48" /></div>
                </div>
              ) : (
              <div className="text-center py-8">
                <p className="text-2xl mb-1">✨</p>
                <p className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>You're all caught up</p>
                <p className="text-sm" style={{ color: "var(--text-muted)" }}>{tab === "foryou" ? "Check out Latest or follow more artists for new things." : "That's everything for now."}</p>
              </div>
              )}
            </div>
          )}
        </div>

        <aside className="hidden lg:block sticky top-6 space-y-7 pt-2">
          {me && (
            <Link to={profileLink(me.email)} className="flex items-center gap-3 group">
              <Avatar src={me.profile_picture} name={displayName(me)} size={48} nitro={me.nitro_active} />
              <span className="flex-1 min-w-0">
                <span className="block text-sm font-bold truncate group-hover:underline" style={{ color: "var(--text-primary)" }}>{displayName(me)}</span>
                <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{posts.filter((p) => p.user_email === me.email).length} posts · {followingSet.size} following</span>
              </span>
            </Link>
          )}
          <SuggestedPeople items={people.slice(0, 5)} followingSet={followingSet} onFollow={follow} />
          <TrendingTags tags={tags} active={tag} onTag={setTag} />
          <ServerSuggestions items={servers} />
        </aside>
      </div>

      <PostViewer
        post={open}
        onClose={() => setOpen(null)}
        liked={!!open && !!me && (open.likes || []).includes(me.email)}
        likeCount={open?.likes?.length || 0}
        onLike={() => open && like(open)}
        onDelete={() => open && remove(open)}
        position={openIndex >= 0 ? { index: openIndex + 1, total: feed.length } : null}
        onPrev={openIndex > 0 ? () => setOpen(feed[openIndex - 1].post.id) : null}
        onNext={openIndex >= 0 && openIndex < feed.length - 1 ? () => setOpen(feed[openIndex + 1].post.id) : null}
        saved={!!open && saved.has(open.id)}
        onSave={() => open && save(open)}
        author={open ? usersByEmail[open.user_email] : null}
        following={!!open && followingSet.has(open.user_email)}
        onFollow={follow}
        likers={open ? likersOf(open) : []}
        moreFromAuthor={moreFromAuthor}
        related={related}
        onOpenPost={setOpen}
        onTag={setTag}
      />
    </Page>
  );
}
