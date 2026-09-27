import React, { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowRight, Crown, Flame, Gift, Heart, Image as ImageIcon, MessageCircle, Music2, Pause, Play, Server, Sparkles, Star, Users } from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { buildTaste, rankFeed } from "@/lib/ranking";
import { useFriendships, splitFriendships } from "@/lib/social";
import { usePlayer } from "@/lib/player";
import { toast } from "@/lib/toast";
import { compactNumber, displayName, greeting, isOnline, profileLink, timeAgo } from "@/lib/format";
import { fadeUp, stagger } from "@/lib/motion";
import { Page } from "@/components/common/Page";
import Avatar from "@/components/common/Avatar";
import Confetti from "@/components/common/Confetti";
import { getLevelInfo } from "@/components/profile/LevelBadge";

const todayKey = () => new Date().toISOString().slice(0, 10);
const yesterdayKey = () => new Date(Date.now() - 86400000).toISOString().slice(0, 10);

function SectionTitle({ icon: Icon, title, to, linkLabel = "See all" }) {
  return (
    <div className="flex items-center gap-2.5 mb-4">
      <span className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}><Icon className="w-4 h-4" /></span>
      <h2 className="font-display text-xl sm:text-2xl font-semibold flex-1" style={{ color: "var(--text-primary)" }}>{title}</h2>
      {to && <Link to={to} className="text-xs font-bold flex items-center gap-1 group" style={{ color: "var(--accent-rose)" }}>{linkLabel}<ArrowRight className="w-3.5 h-3.5 transition-transform group-hover:translate-x-0.5" /></Link>}
    </div>
  );
}

function DailyReward() {
  const { user, updateMe } = useAuth();
  const [burst, setBurst] = useState(false);
  const claimed = user?.last_daily_claim === todayKey();
  const streak = user?.last_daily_claim === yesterdayKey() || claimed ? user?.daily_streak || 1 : 0;
  const claim = async () => {
    const nextStreak = user?.last_daily_claim === yesterdayKey() ? (user?.daily_streak || 0) + 1 : 1;
    const reward = 20 + Math.min(nextStreak, 7) * 5;
    setBurst(true);
    try {
      await updateMe({ last_daily_claim: todayKey(), daily_streak: nextStreak, coins: (user?.coins || 0) + reward, xp: (user?.xp || 0) + 10 });
      toast.success(`+${reward} coins · +10 XP`, { description: nextStreak > 1 ? `${nextStreak}-day streak — keep it going!` : "Come back tomorrow to start a streak." });
    } catch (e) { toast.error(e?.message || "Could not claim reward."); }
    setTimeout(() => setBurst(false), 2000);
  };
  return (
    <div className="relative">
      {burst && <Confetti count={40} />}
      <motion.button
        whileHover={!claimed ? { y: -2 } : {}}
        whileTap={!claimed ? { scale: 0.97 } : {}}
        onClick={claim}
        disabled={claimed}
        className="relative flex items-center gap-3 rounded-2xl px-4 py-3 text-left w-full sm:w-auto"
        style={claimed ? { background: "var(--surface)", border: "1px solid var(--border-c)" } : { background: "var(--accent-grad)", color: "#fff", boxShadow: "var(--shadow-accent)" }}
      >
        <span className={`${claimed ? "" : "anim-wiggle"} w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0`} style={{ animationDuration: "3s", background: claimed ? "var(--pink-soft)" : "rgb(255 255 255 / 0.2)", color: claimed ? "var(--accent-rose)" : "#fff" }}>
          <Gift className="w-5 h-5" />
        </span>
        <span>
          <span className="block text-sm font-bold" style={{ color: claimed ? "var(--text-primary)" : "#fff" }}>{claimed ? "Daily reward claimed" : "Claim daily reward"}</span>
          <span className="block text-xs flex items-center gap-1" style={{ color: claimed ? "var(--text-muted)" : "rgb(255 255 255 / 0.85)" }}>
            <Flame className="w-3 h-3" /> {streak > 0 ? `${streak}-day streak` : "Start a streak today"}
          </span>
        </span>
      </motion.button>
    </div>
  );
}

function Hero({ stats }) {
  const { user } = useAuth();
  const level = getLevelInfo(user?.xp || 0);
  return (
    <motion.section variants={fadeUp} className="relative overflow-hidden rounded-[2rem] p-6 sm:p-10 mb-10 grain" style={{ background: "linear-gradient(135deg, rgb(var(--accent-2-rgb) / 0.28), rgb(var(--accent-rgb) / 0.12) 55%, var(--surface))", border: "1px solid var(--border-c)" }}>
      <div className="orb orb-a w-80 h-80 -top-24 -right-16" />
      <div className="orb orb-c w-64 h-64 -bottom-24 left-1/3" />
      <div className="relative flex flex-col lg:flex-row lg:items-end gap-8">
        <div className="flex-1 min-w-0">
          <p className="eyebrow mb-3">{new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</p>
          <h1 className="font-display text-4xl sm:text-5xl lg:text-6xl font-semibold leading-[1.02] text-balance" style={{ color: "var(--text-primary)" }}>
            {greeting()},<br /><em className="gradient-text" style={{ paddingRight: 4 }}>{displayName(user)}</em>
          </h1>
          <p className="mt-4 text-sm sm:text-base max-w-lg" style={{ color: "var(--text-secondary)" }}>Here's what's happening across Sugerly today — fresh art, new tracks and friends online.</p>
          <div className="mt-6 flex flex-wrap gap-3 items-center">
            <DailyReward />
            <Link to="/Community?compose=1" className="btn-outline"><ImageIcon className="w-4 h-4" /> Share something</Link>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-3 lg:w-[380px]">
          {[
            { label: "Level", value: level.current.level, sub: level.current.title, color: level.current.color },
            { label: "Coins", value: compactNumber(user?.coins || 0), sub: "MimiCoins" },
            { label: "Friends", value: stats.friends, sub: `${stats.online} online` },
          ].map((s) => (
            <div key={s.label} className="glass rounded-2xl p-3.5 text-center" style={{ border: "1px solid var(--border-c)" }}>
              <p className="font-display text-2xl sm:text-3xl font-semibold" style={{ color: s.color || "var(--text-primary)" }}>{s.value}</p>
              <p className="text-[10px] font-bold uppercase tracking-wider mt-0.5" style={{ color: "var(--text-muted)" }}>{s.label}</p>
              <p className="text-[11px] truncate" style={{ color: "var(--text-secondary)" }}>{s.sub}</p>
            </div>
          ))}
          <div className="col-span-3">
            <div className="flex justify-between text-[11px] font-semibold mb-1.5" style={{ color: "var(--text-muted)" }}>
              <span>{level.next ? `${level.xpInLevel} / ${level.xpNeeded} XP to Lv.${level.next.level}` : "Max level reached"}</span>
              <span>{Math.round(level.progress)}%</span>
            </div>
            <div className="h-2 rounded-full overflow-hidden" style={{ background: "var(--border-c)" }}>
              <motion.div className="h-full rounded-full" style={{ background: "var(--accent-grad)" }} initial={{ width: 0 }} animate={{ width: `${level.progress}%` }} transition={{ duration: 1.2, ease: [0.2, 0.8, 0.2, 1], delay: 0.3 }} />
            </div>
          </div>
        </div>
      </div>
    </motion.section>
  );
}

export default function Home() {
  const { user } = useAuth();
  const player = usePlayer();
  const { data: artworks, loading: artLoading } = useLiveQuery("Artwork", null, { sort: "-created_date", limit: 40 });
  const { data: posts } = useLiveQuery("CommunityPost", null, { sort: "-created_date", limit: 60 });
  const { data: tracks } = useLiveQuery("MusicReview", null, { sort: "-created_date", limit: 8 });
  const { data: servers } = useLiveQuery("Community", null, { sort: "-created_date", limit: 50 });
  const { data: users } = useLiveQuery("User", null, { sort: "-last_seen", limit: 100, live: false });
  const { friendships } = useFriendships(user?.email);
  const { friendEmails } = splitFriendships(friendships, user?.email);

  const featured = useMemo(() => {
    // Featured pieces first, then the newest work.
    return [...artworks.filter((a) => a.featured), ...artworks.filter((a) => !a.featured)].slice(0, 10);
  }, [artworks]);
  // Same engine as the Community "For you" feed, so Home shows what you'd most likely enjoy.
  const taste = useMemo(() => buildTaste({ me: user, friends: friendEmails, posts }), [user, friendEmails, posts]);
  const trending = useMemo(() => rankFeed(posts.filter((p) => p.user_email !== user?.email), { taste }).slice(0, 6).map((x) => x.post), [posts, taste, user?.email]);
  const topArtists = useMemo(() => {
    const stats = {};
    posts.forEach((p) => { if (!p.user_email) return; stats[p.user_email] = (stats[p.user_email] || 0) + (p.likes?.length || 0); });
    return users.filter((u) => stats[u.email] !== undefined).map((u) => ({ ...u, likes: stats[u.email] })).sort((a, b) => b.likes - a.likes).slice(0, 5);
  }, [posts, users]);
  const friendsList = useMemo(() => users.filter((u) => friendEmails.includes(u.email)).sort((a, b) => Number(isOnline(b)) - Number(isOnline(a))), [users, friendEmails]);
  const myServers = useMemo(() => servers.filter((s) => s.member_emails?.includes(user?.email)).slice(0, 6), [servers, user?.email]);
  const queue = tracks.filter((t) => t.music_url).map((t) => ({ id: t.id, title: t.title, artist: t.user_display_name, src: t.music_url, cover: t.cover_url }));

  return (
    <Page>
      <motion.div variants={stagger(0, 0.08)} initial="hidden" animate="show">
        <Hero stats={{ friends: friendEmails.length, online: friendsList.filter(isOnline).length }} />

        <motion.section variants={fadeUp} className="mb-12">
          <SectionTitle icon={Star} title="Featured art" to="/Gallery" />
          <div className="flex gap-4 overflow-x-auto no-scrollbar snap-x snap-mandatory -mx-4 px-4 sm:mx-0 sm:px-0 pb-2">
            {artLoading && Array.from({ length: 5 }).map((_, i) => <div key={i} className="skeleton flex-shrink-0 w-60 h-72 rounded-3xl" />)}
            {featured.map((a, i) => (
              <motion.div key={a.id} className="enter-side snap-start flex-shrink-0" style={{ "--d": `${Math.round((0.1 + i * 0.05) * 1000)}ms`, "--enter-x": "30px" }}>
                <Link to={`/Gallery?art=${a.id}`} className="group relative block w-60 h-72 rounded-3xl overflow-hidden" style={{ boxShadow: "var(--shadow-md)" }}>
                  <img src={a.image_url} alt={a.title} loading="lazy" className="absolute inset-0 w-full h-full object-cover transition-transform duration-700 group-hover:scale-110" />
                  <div className="absolute inset-0" style={{ background: "linear-gradient(to top, rgb(20 8 14 / 0.75), transparent 55%)" }} />
                  <div className="absolute bottom-0 inset-x-0 p-4 text-white">
                    <p className="font-display text-lg font-semibold leading-tight truncate">{a.title}</p>
                    <p className="text-xs opacity-80 flex items-center gap-1.5 mt-1"><Heart className="w-3 h-3 fill-current" />{a.likes?.length || 0}<span className="opacity-60">·</span><span className="capitalize truncate">{a.medium?.replace("_", " ")}</span></p>
                  </div>
                </Link>
              </motion.div>
            ))}
          </div>
        </motion.section>

        <div className="grid lg:grid-cols-3 gap-8 lg:gap-10">
          <motion.section variants={fadeUp} className="lg:col-span-2">
            <SectionTitle icon={Flame} title="For you in the community" to="/Community" />
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {trending.map((p, i) => (
                <motion.div className="enter" style={{ "--d": `${Math.round((0.15 + i * 0.05) * 1000)}ms`, "--enter-y": "20px" }} key={p.id}>
                  <Link to={`/Community?post=${p.id}`} className="group card-sm overflow-hidden block card-hover">
                    <div className="aspect-[4/5] overflow-hidden" style={{ background: "var(--surface-2)" }}>
                      {p.image_url ? <img src={p.image_url} alt={p.title || ""} loading="lazy" className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-105" /> : <div className="w-full h-full p-4 flex items-end font-display text-lg leading-snug" style={{ color: "var(--text-secondary)" }}>“{p.description?.slice(0, 90)}”</div>}
                    </div>
                    <div className="p-3 flex items-center gap-2">
                      <Avatar src={p.user_profile_picture} name={p.user_display_name} size={24} />
                      <span className="text-xs font-semibold truncate flex-1" style={{ color: "var(--text-secondary)" }}>{p.user_display_name}</span>
                      <span className="text-xs font-bold flex items-center gap-1" style={{ color: "var(--accent-rose)" }}><Heart className="w-3 h-3 fill-current" />{p.likes?.length || 0}</span>
                    </div>
                  </Link>
                </motion.div>
              ))}
            </div>
          </motion.section>

          <div className="space-y-10">
            <motion.section variants={fadeUp}>
              <SectionTitle icon={Music2} title="Fresh tracks" to="/Music" />
              <div className="card p-2">
                {tracks.slice(0, 5).map((t) => {
                  const playing = player.isPlaying(t.id);
                  const track = queue.find((q) => q.id === t.id);
                  return (
                    <div key={t.id} className="flex items-center gap-3 p-2 rounded-2xl hover:bg-[var(--surface-2)] transition-colors">
                      <motion.button whileTap={{ scale: 0.9 }} onClick={() => track && player.toggle(track, queue)} disabled={!track} className="w-10 h-10 rounded-xl flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40" style={{ background: "var(--accent-grad)" }} aria-label={playing ? `Pause ${t.title}` : `Play ${t.title}`}>
                        {playing ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4 ml-0.5" />}
                      </motion.button>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-bold truncate" style={{ color: player.isCurrent(t.id) ? "var(--accent-rose)" : "var(--text-primary)" }}>{t.title}</p>
                        <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>{t.user_display_name}{t.genre ? ` · ${t.genre}` : ""}</p>
                      </div>
                      {playing && <span className="equalizer" style={{ color: "var(--accent-rose)" }}><span /><span /><span /></span>}
                    </div>
                  );
                })}
                {tracks.length === 0 && <p className="text-sm text-center py-6" style={{ color: "var(--text-muted)" }}>No tracks yet.</p>}
              </div>
            </motion.section>

            <motion.section variants={fadeUp}>
              <SectionTitle icon={Crown} title="Top artists" to="/TopArtists" />
              <div className="card p-2">
                {topArtists.map((a, i) => (
                  <Link key={a.email} to={profileLink(a.email)} className="flex items-center gap-3 p-2 rounded-2xl hover:bg-[var(--surface-2)] transition-colors">
                    <span className="w-6 text-center font-display font-semibold" style={{ color: ["#f0a020", "#94a3b8", "#c2773a"][i] || "var(--text-muted)" }}>{i + 1}</span>
                    <Avatar src={a.profile_picture} name={displayName(a)} size={36} nitro={a.nitro_active} />
                    <span className="flex-1 min-w-0 text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{displayName(a)}</span>
                    <span className="text-xs font-bold flex items-center gap-1" style={{ color: "var(--accent-rose)" }}><Heart className="w-3 h-3 fill-current" />{a.likes}</span>
                  </Link>
                ))}
                {topArtists.length === 0 && <p className="text-sm text-center py-6" style={{ color: "var(--text-muted)" }}>Post art to get on the board!</p>}
              </div>
            </motion.section>
          </div>
        </div>

        <div className="grid md:grid-cols-2 gap-8 lg:gap-10 mt-12">
          <motion.section variants={fadeUp}>
            <SectionTitle icon={Users} title="Friends" to="/Friends" linkLabel="Manage" />
            {friendsList.length === 0 ? (
              <div className="card p-6 text-center">
                <p className="text-sm mb-3" style={{ color: "var(--text-muted)" }}>Add friends to see who's around.</p>
                <Link to="/Friends" className="btn text-xs">Find people</Link>
              </div>
            ) : (
              <div className="flex gap-4 overflow-x-auto no-scrollbar pb-2">
                {friendsList.map((f) => (
                  <Link key={f.email} to={profileLink(f.email)} className="flex flex-col items-center gap-2 w-20 flex-shrink-0 group">
                    <motion.span whileHover={{ y: -3 }}><Avatar src={f.profile_picture} name={displayName(f)} size={60} online={isOnline(f)} nitro={f.nitro_active} /></motion.span>
                    <span className="text-xs font-semibold truncate w-full text-center" style={{ color: "var(--text-secondary)" }}>{displayName(f)}</span>
                  </Link>
                ))}
              </div>
            )}
          </motion.section>

          <motion.section variants={fadeUp}>
            <SectionTitle icon={Server} title="Your servers" to="/Communities" linkLabel="Browse" />
            <div className="grid grid-cols-2 gap-3">
              {myServers.map((s) => (
                <Link key={s.id} to={`/CommunityChat?id=${s.id}`} className="card-sm card-hover p-3 flex items-center gap-3">
                  <span className="w-11 h-11 rounded-2xl flex items-center justify-center text-xl overflow-hidden flex-shrink-0" style={{ background: "var(--pink-soft)" }}>{s.icon_url ? <img loading="lazy" decoding="async" src={s.icon_url} alt="" className="w-full h-full object-cover" /> : s.icon_emoji || "💬"}</span>
                  <span className="min-w-0">
                    <span className="block text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{s.name}</span>
                    <span className="block text-[11px]" style={{ color: "var(--text-muted)" }}>{s.member_emails?.length || 0} members</span>
                  </span>
                </Link>
              ))}
              {myServers.length === 0 && (
                <div className="card p-6 text-center col-span-2">
                  <p className="text-sm mb-3" style={{ color: "var(--text-muted)" }}>Join a server to chat with the community.</p>
                  <Link to="/Communities" className="btn text-xs"><MessageCircle className="w-3.5 h-3.5" /> Explore servers</Link>
                </div>
              )}
            </div>
          </motion.section>
        </div>

        <motion.p variants={fadeUp} className="desktop-only text-center text-xs mt-14 flex items-center justify-center gap-1.5" style={{ color: "var(--text-muted)" }}>
          <Sparkles className="w-3.5 h-3.5" /> Tip: press <span className="kbd">Ctrl</span><span className="kbd">K</span> to search anything · last activity {timeAgo(posts[0]?.created_date)}
        </motion.p>
      </motion.div>
    </Page>
  );
}
