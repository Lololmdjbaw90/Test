import React, { useMemo, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { Ban, Bookmark, Calendar, Check, Clock, Flag, Grid3X3, Heart, Loader2, MessageCircle, MessageSquare, MoreHorizontal, Pencil, Shield, Sparkles, UserCheck, UserPlus, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useFriendships } from "@/lib/social";
import { toggleLike } from "@/lib/likes";
import { toast } from "@/lib/toast";
import { compactNumber, displayName, isNitro, isOnline, profileLink, timeAgo } from "@/lib/format";
import { Page, EmptyState, CenterSpinner } from "@/components/common/Page";
import { Segmented } from "@/components/common/Controls";
import Avatar from "@/components/common/Avatar";
import PostCard from "@/components/community/PostCard";
import PostViewer from "@/components/community/PostViewer";
import ProfileMessageBoard from "@/components/profile/ProfileMessageBoard";
import NameStylePicker, { getNameStyle } from "@/components/profile/NameStylePicker";
import LevelBadge, { getLevelInfo } from "@/components/profile/LevelBadge";
import NitroBadge from "@/components/profile/NitroBadge";
import NitroShop from "@/components/profile/NitroShop";
import { notify } from "@/utils/notifications";
import Popover from "@/components/common/Popover";
import { useConfirm } from "@/components/common/Modal";
import { openReport, setBlocked, useBlocked } from "@/lib/safety";

function Banner({ profile }) {
  const nitro = isNitro(profile);
  return (
    <div className="relative h-44 sm:h-60 rounded-[2rem] overflow-hidden grain" style={{ boxShadow: "var(--shadow-md)" }}>
      {profile.banner_url ? (
        <img loading="lazy" decoding="async" src={profile.banner_url} alt="" className="absolute inset-0 w-full h-full object-cover" />
      ) : (
        <div className="absolute inset-0" style={{ background: nitro ? "linear-gradient(120deg,#8b5cf6,#c084fc,#ee8fae,#7cbeff)" : `linear-gradient(120deg, ${profile.banner_color || "rgb(var(--accent-2-rgb))"}, rgb(var(--accent-rgb)))` }} />
      )}
      <div className="orb w-72 h-72 -top-20 right-10" style={{ "--orb": "rgb(255 255 255 / 0.25)" }} />
      <div className="anim-sweep absolute inset-0 pointer-events-none" style={{ background: "linear-gradient(105deg,transparent 35%,rgb(255 255 255 / 0.18) 50%,transparent 65%)" }} />
    </div>
  );
}

function Stat({ value, label, delay }) {
  return (
    <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay }} className="text-center px-1 sm:px-3 min-w-0">
      <p className="font-display text-2xl font-semibold" style={{ color: "var(--text-primary)" }}>{compactNumber(value)}</p>
      <p className="text-[10px] sm:text-[11px] font-bold uppercase tracking-wide sm:tracking-wider truncate" style={{ color: "var(--text-muted)" }}>{label}</p>
    </motion.div>
  );
}

export default function ProfilePage() {
  const navigate = useNavigate();
  const { user: me, updateMe } = useAuth();
  const [params, setParams] = useSearchParams();
  const email = (params.get("email") || me?.email || "").toLowerCase();
  const isOwn = me?.email === email;
  const [tab, setTab] = useState("posts");
  const [busy, setBusy] = useState(false);
  const [menu, setMenu] = useState(false);
  const menuRef = useRef(null);
  const confirm = useConfirm();
  const blockedSet = useBlocked();
  const isBlocked = !isOwn && blockedSet.has(email);

  const { data: userRows, loading } = useLiveQuery("User", { email }, { enabled: !!email });
  const profile = isOwn ? { ...(userRows[0] || {}), ...me } : userRows[0];
  const { data: posts, setData: setPosts } = useLiveQuery("CommunityPost", { user_email: email }, { sort: "-created_date", enabled: !!email });
  const { data: followers } = useLiveQuery("User", { following: { $contains: email } }, { enabled: !!email });
  const { data: artworks } = useLiveQuery("Artwork", null, { sort: "-created_date", enabled: isOwn && tab === "saved", live: false });
  const { data: recentPosts, setData: setRecentPosts } = useLiveQuery("CommunityPost", null, { sort: "-created_date", limit: 300, enabled: isOwn && tab === "saved", live: false });
  const { friendships } = useFriendships(me?.email);
  const friendship = friendships.find((f) => (f.requester_email === email && f.receiver_email === me?.email) || (f.receiver_email === email && f.requester_email === me?.email));

  const totalLikes = useMemo(() => posts.reduce((s, p) => s + (p.likes?.length || 0), 0), [posts]);
  const following = (me?.following || []).includes(email);
  const savedArt = artworks.filter((a) => (me?.saved_artworks || []).includes(a.id));
  // Posts bookmarked in the Community feed live here too.
  const savedPosts = recentPosts.filter((p) => (me?.saved_posts || []).includes(p.id));
  const openPostId = params.get("post");
  const openPost = posts.find((p) => p.id === openPostId) || null;
  const setOpenPost = (id) => setParams((p) => { const n = new URLSearchParams(p); if (id) n.set("post", id); else n.delete("post"); return n; });

  if (loading && !profile?.email) return <CenterSpinner />;
  if (!profile?.email) return <Page><EmptyState icon={Users} title="Profile not found" text="This person may have left, or the link is wrong." action={<Link to="/" className="btn">Go home</Link>} /></Page>;

  const name = displayName(profile);
  const style = getNameStyle(profile.name_style);
  const nitro = isNitro(profile);
  const level = getLevelInfo(profile.xp || 0);

  const toggleBlock = async () => {
    setMenu(false);
    if (!isBlocked && !(await confirm({ title: `Block ${name}?`, message: "You won't see their posts, comments or messages, and they can't call you. They won't be told.", confirmLabel: "Block", danger: true }))) return;
    try {
      await setBlocked({ me, email, updateMe, block: !isBlocked });
      toast.success(isBlocked ? `${name} is unblocked` : `${name} is blocked`);
    } catch (e) { toast.error(e?.message || "Could not update."); }
  };
  const toggleFollow = async () => {
    setBusy(true);
    const next = following ? (me.following || []).filter((e) => e !== email) : [...(me.following || []), email];
    try {
      await updateMe({ following: next });
      if (!following) await notify({ to_email: email, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "follow", message: `${displayName(me)} started following you`, link: `/Profile?email=${encodeURIComponent(me.email)}` });
    } catch (e) { toast.error(e?.message || "Could not update follow."); }
    setBusy(false);
  };
  const addFriend = async () => {
    setBusy(true);
    try {
      await base44.entities.Friendship.create({ requester_email: me.email, requester_display_name: displayName(me), requester_profile_picture: me.profile_picture || "", receiver_email: email, receiver_display_name: name, receiver_profile_picture: profile.profile_picture || "", status: "pending" });
      await notify({ to_email: email, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "friend_request", message: `${displayName(me)} sent you a friend request`, link: "/Friends" });
      toast.success("Friend request sent");
    } catch (e) { toast.error(e?.message || "Could not send request."); }
    setBusy(false);
  };
  const acceptFriend = async () => {
    setBusy(true);
    try {
      await base44.entities.Friendship.update(friendship.id, { status: "accepted" });
      await notify({ to_email: email, from_email: me.email, from_display_name: displayName(me), from_profile_picture: me.profile_picture, type: "friend_accepted", message: `${displayName(me)} accepted your friend request`, link: "/Friends" });
      toast.success(`You and ${name} are now friends`);
    } catch (e) { toast.error(e?.message || "Could not accept."); }
    setBusy(false);
  };
  const removePost = async (post) => {
    try { await base44.entities.CommunityPost.delete(post.id); setOpenPost(null); toast.success("Post deleted"); } catch (e) { toast.error(e?.message || "Could not delete."); }
  };

  const tabs = [
    { id: "posts", label: "Posts", icon: Grid3X3, count: posts.length },
    { id: "guestbook", label: "Guestbook", icon: MessageCircle },
    ...(isOwn ? [{ id: "saved", label: "Saved", icon: Bookmark }, { id: "shop", label: "Shop", icon: Sparkles }] : []),
  ];

  return (
    <Page width="max-w-5xl">
      <Banner profile={profile} />
      <div className="px-2 sm:px-6 -mt-16 sm:-mt-20 relative">
        <div className="flex flex-col sm:flex-row sm:items-start gap-4 sm:gap-6">
          <motion.div initial={{ scale: 0.7, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: "spring", stiffness: 260, damping: 18 }} className="flex w-fit">
            <Avatar src={profile.profile_picture} name={name} size={132} nitro={nitro} online={isOnline(profile)} ring={6} ringColor="var(--app-bg)" />
          </motion.div>
          <div className="flex-1 min-w-0 sm:pt-[92px]">
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-3xl sm:text-4xl leading-tight" style={style.preview()}>{name}</h1>
              {isOwn && <NameStylePicker currentStyle={profile.name_style} name={name} />}
            </div>
            <div className="flex flex-wrap items-center gap-2 mt-2">
              {profile.role === "admin" && <span className="badge-pink"><Shield className="w-3 h-3" /> Admin</span>}
              <LevelBadge xp={profile.xp || 0} />
              <NitroBadge active={nitro} />
              <span className="text-xs flex items-center gap-1" style={{ color: "var(--text-muted)" }}><Calendar className="w-3.5 h-3.5" /> Joined {new Date(profile.created_date || Date.now()).toLocaleDateString(undefined, { month: "short", year: "numeric" })}</span>
              {!isOnline(profile) && profile.last_seen && <span className="text-xs flex items-center gap-1" style={{ color: "var(--text-muted)" }}><Clock className="w-3.5 h-3.5" /> Active {timeAgo(profile.last_seen)}</span>}
            </div>
          </div>
          <div className="flex flex-wrap gap-2 sm:pt-[96px]">
            {isOwn ? (
              <Link to="/Settings" className="btn-outline"><Pencil className="w-4 h-4" /> Edit profile</Link>
            ) : (
              <>
                <button onClick={toggleFollow} disabled={busy} className={following ? "btn-outline" : "btn"}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : following ? <><Check className="w-4 h-4" /> Following</> : <><UserPlus className="w-4 h-4" /> Follow</>}</button>
                {!friendship && <button onClick={addFriend} disabled={busy} className="btn-outline"><Users className="w-4 h-4" /> Add friend</button>}
                {friendship?.status === "pending" && friendship.receiver_email === me?.email && <button onClick={acceptFriend} disabled={busy} className="btn-outline"><UserCheck className="w-4 h-4" /> Accept request</button>}
                {friendship?.status === "pending" && friendship.requester_email === me?.email && <span className="chip"><Clock className="w-4 h-4" /> Request sent</span>}
                {friendship?.status === "accepted" && <button onClick={() => navigate(`/DirectMessages?with=${encodeURIComponent(email)}`)} className="btn-outline"><MessageSquare className="w-4 h-4" /> Message</button>}
              </>
            )}
            {!isOwn && me && (
              <>
                <button ref={menuRef} onClick={() => setMenu((v) => !v)} className="icon-btn icon-btn-bordered" aria-label="More options" aria-expanded={menu}><MoreHorizontal className="w-5 h-5" /></button>
                <Popover open={menu} onClose={() => setMenu(false)} anchorRef={menuRef} placement="bottom-end" width={230} label="Profile options">
                  <div className="p-2 grid gap-0.5">
                    <button onClick={() => { setMenu(false); openReport({ type: "user", id: profile.id || email, owner: email, preview: `${name}${profile.bio ? ` — ${profile.bio}` : ""}`, link: profileLink(email) }); }} className="flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-sm font-semibold text-left transition-colors hover:bg-[var(--surface-2)]" style={{ color: "var(--danger)" }}><Flag className="w-4 h-4" /> Report {name.split(" ")[0]}</button>
                    <button onClick={toggleBlock} className="flex items-center gap-2.5 px-3 py-2.5 rounded-xl text-sm font-semibold text-left transition-colors hover:bg-[var(--surface-2)]" style={{ color: isBlocked ? "var(--text-primary)" : "var(--danger)" }}><Ban className="w-4 h-4" /> {isBlocked ? "Unblock" : "Block"} {name.split(" ")[0]}</button>
                  </div>
                </Popover>
              </>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-[1fr_auto] gap-5 mt-6 items-start">
          <div>
            {profile.bio ? <p className="text-sm leading-relaxed max-w-2xl" style={{ color: "var(--text-secondary)" }}>{profile.bio}</p> : isOwn && <Link to="/Settings" className="text-sm font-semibold" style={{ color: "var(--accent-rose)" }}>+ Add a bio</Link>}
            {profile.interests?.length > 0 && <div className="flex flex-wrap gap-1.5 mt-3">{profile.interests.map((i) => <span key={i} className="badge-pink">{i}</span>)}</div>}
          </div>
          <div className="card-sm grid grid-cols-4 md:flex divide-x py-3 min-w-0" style={{ borderColor: "var(--border-c)" }}>
            <Stat value={posts.length} label="Posts" delay={0.1} />
            <Stat value={totalLikes} label="Likes" delay={0.15} />
            <Stat value={followers.length} label="Followers" delay={0.2} />
            <Stat value={(profile.following || []).length} label="Following" delay={0.25} />
          </div>
        </div>

        {level.next && isOwn && (
          <div className="mt-5 max-w-md">
            <div className="flex justify-between text-[11px] font-semibold mb-1.5" style={{ color: "var(--text-muted)" }}><span>{level.xpInLevel} / {level.xpNeeded} XP to {level.next.title}</span><span>{Math.round(level.progress)}%</span></div>
            <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--border-c)" }}><motion.div className="h-full rounded-full" style={{ background: `linear-gradient(90deg, ${level.current.color}, ${level.next.color})` }} initial={{ width: 0 }} animate={{ width: `${level.progress}%` }} transition={{ duration: 1.1, delay: 0.3 }} /></div>
          </div>
        )}

        {isBlocked ? (
          <div className="mt-8 card !rounded-3xl p-8 text-center">
            <Ban className="w-8 h-8 mx-auto mb-3" style={{ color: "var(--text-muted)" }} />
            <p className="font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>You blocked {name}</p>
            <p className="text-sm mt-1 mb-4" style={{ color: "var(--text-muted)" }}>You won't see their posts, comments or messages, and they can't call you.</p>
            <button onClick={toggleBlock} className="btn-outline">Unblock</button>
          </div>
        ) : <>
        <div className="mt-8 mb-6"><Segmented options={tabs} value={tab} onChange={setTab} /></div>

        <AnimatePresence mode="wait">
          <motion.div key={tab} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} transition={{ duration: 0.22 }}>
            {tab === "posts" && (posts.length === 0 ? (
              <EmptyState icon={Grid3X3} title="No posts yet" text={isOwn ? "Share your first piece with the community." : `${name} hasn't posted yet.`} action={isOwn && <Link to="/Community?compose=1" className="btn">Create a post</Link>} />
            ) : (
              <div className="columns-1 sm:columns-2 lg:columns-3 gap-5">
                {posts.map((p, i) => (
                  <div key={p.id} className="break-inside-avoid mb-5">
                    <PostCard post={p} index={i} onOpen={() => setOpenPost(p.id)} liked={!!me && (p.likes || []).includes(me.email)} likeCount={p.likes?.length || 0} onLike={() => toggleLike({ entity: "CommunityPost", record: p, user: me, setData: setPosts, message: "liked your post", link: `/Community?post=${p.id}` })} />
                  </div>
                ))}
              </div>
            ))}
            {tab === "guestbook" && <ProfileMessageBoard profileUser={profile} />}
            {tab === "saved" && isOwn && (savedArt.length === 0 && savedPosts.length === 0 ? (
              <EmptyState icon={Bookmark} title="Nothing saved yet" text="Tap the bookmark on posts and gallery pieces to collect them here." action={<Link to="/Community" className="btn">Browse the feed</Link>} />
            ) : (
              <div className="space-y-8">
              {savedPosts.length > 0 && (
                <div>
                  <p className="eyebrow mb-3">Posts · {savedPosts.length}</p>
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
                    {savedPosts.map((p, i) => (
                      <PostCard key={p.id} post={p} index={i} onOpen={() => navigate(`/Community?post=${p.id}`)} liked={!!me && (p.likes || []).includes(me.email)} likeCount={p.likes?.length || 0} onLike={() => toggleLike({ entity: "CommunityPost", record: p, user: me, setData: setRecentPosts, message: "liked your post", link: `/Community?post=${p.id}` })} />
                    ))}
                  </div>
                </div>
              )}
              {savedArt.length > 0 && (
              <div>
              <p className="eyebrow mb-3">Artworks · {savedArt.length}</p>
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
                {savedArt.map((a, i) => (
                  <motion.div className="enter-pop" style={{ "--d": `${Math.round((i * 0.04) * 1000)}ms` }} key={a.id}>
                    <Link to={`/Gallery?art=${a.id}`} className="group block rounded-3xl overflow-hidden aspect-square relative" style={{ boxShadow: "var(--shadow-sm)" }}>
                      <img loading="lazy" decoding="async" src={a.image_url} alt={a.title} className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110" />
                      <span className="absolute inset-x-0 bottom-0 p-3 text-white text-sm font-semibold truncate" style={{ background: "linear-gradient(to top, rgb(20 8 14 / 0.7), transparent)" }}>{a.title}</span>
                    </Link>
                  </motion.div>
                ))}
              </div>
              </div>
              )}
              </div>
            ))}
            {tab === "shop" && isOwn && <NitroShop />}
          </motion.div>
        </AnimatePresence>
        </>}
      </div>

      <PostViewer post={openPost} onClose={() => setOpenPost(null)} liked={!!openPost && !!me && (openPost.likes || []).includes(me.email)} likeCount={openPost?.likes?.length || 0} onLike={() => openPost && toggleLike({ entity: "CommunityPost", record: openPost, user: me, setData: setPosts, message: "liked your post", link: `/Community?post=${openPost.id}` })} onDelete={() => openPost && removePost(openPost)} />
    </Page>
  );
}
