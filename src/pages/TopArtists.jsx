import React, { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Crown, Heart, Image as ImageIcon, Trophy } from "lucide-react";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { usePeople } from "@/lib/people";
import { useAuth } from "@/lib/AuthContext";
import { displayName, profileLink } from "@/lib/format";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { Segmented } from "@/components/common/Controls";
import Avatar from "@/components/common/Avatar";
import { getLevelInfo } from "@/components/profile/LevelBadge";
import { likeCount } from "@/lib/likeCount";

const MEDALS = [
  { color: "#f0a020", bg: "linear-gradient(180deg,#ffe29a,#f0a020)", ring: "conic-gradient(from 210deg,#ffe7a3,#f0a020,#ffd36b,#d98a0f,#ffe7a3)", height: 150 },
  { color: "#94a3b8", bg: "linear-gradient(180deg,#e2e8f0,#94a3b8)", ring: "conic-gradient(from 210deg,#f1f5f9,#94a3b8,#e2e8f0,#7c8aa0,#f1f5f9)", height: 110 },
  { color: "#c2773a", bg: "linear-gradient(180deg,#f5c9a0,#c2773a)", ring: "conic-gradient(from 210deg,#f8d3ae,#c2773a,#eab07c,#a8612b,#f8d3ae)", height: 84 },
];

// A medal ring drawn as real, fixed-size circles (not a box-shadow), so it
// stays perfectly round and centred on every screen; the crown gets its own
// space above the ring instead of sitting on it.
function MedalAvatar({ artist, medal, rank }) {
  const size = rank === 1 ? 84 : 66;
  const ringW = rank === 1 ? 4 : 3;
  const gap = 3;
  const outer = size + 2 * (ringW + gap);
  return (
    <div className="relative flex-shrink-0" style={{ width: outer, height: outer }}>
      {rank === 1 && (
        <span className="absolute left-1/2 bottom-full mb-1.5" style={{ translate: "-50% 0" }} aria-hidden="true">
          <span className="block anim-bob" style={{ animationDuration: "2.8s" }}>
            <Crown className="block w-9 h-9" style={{ color: medal.color, fill: medal.color, filter: "drop-shadow(0 3px 4px rgb(240 160 32 / 0.35))" }} />
          </span>
        </span>
      )}
      <Link to={profileLink(artist.email)} aria-label={displayName(artist)} className="absolute inset-0 rounded-full grid place-items-center" style={{ background: medal.ring, boxShadow: `0 10px 22px -10px ${medal.color}` }}>
        <span className="rounded-full grid place-items-center" style={{ width: size + gap * 2, height: size + gap * 2, background: "var(--surface)" }}>
          <Avatar src={artist.profile_picture} name={displayName(artist)} size={size} />
        </span>
      </Link>
    </div>
  );
}
const RANGES = [{ id: "all", label: "All time" }, { id: "month", label: "This month" }, { id: "week", label: "This week" }];

function Podium({ artists }) {
  const order = [artists[1], artists[0], artists[2]];
  const medalIndex = [1, 0, 2];
  return (
    <div className="flex items-end justify-center gap-3 sm:gap-6 mb-10 pt-14">
      {order.map((a, i) => {
        if (!a) return <div key={i} className="w-24 sm:w-36" />;
        const m = MEDALS[medalIndex[i]];
        const rank = medalIndex[i] + 1;
        return (
          <div key={a.email} className="flex flex-col items-center w-24 sm:w-36">
            <motion.div initial={{ opacity: 0, y: 20, scale: 0.8 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ delay: 0.5 + i * 0.15, type: "spring", stiffness: 260, damping: 18 }} className="flex flex-col items-center mb-3">
              <MedalAvatar artist={a} medal={m} rank={rank} />
              <p className="font-bold text-sm mt-3 truncate max-w-full" style={{ color: "var(--text-primary)" }}>{displayName(a)}</p>
              <p className="text-xs font-bold flex items-center gap-1" style={{ color: "var(--accent-rose)" }}><Heart className="w-3 h-3 fill-current" />{a.likes}</p>
            </motion.div>
            <motion.div initial={{ height: 0 }} animate={{ height: m.height }} transition={{ delay: 0.15 + i * 0.12, type: "spring", stiffness: 120, damping: 18 }} className="w-full rounded-t-3xl flex items-start justify-center pt-3 overflow-hidden" style={{ background: m.bg, boxShadow: "var(--shadow-md)" }}>
              <span className="font-display text-4xl font-bold text-white drop-shadow">{rank}</span>
            </motion.div>
          </div>
        );
      })}
    </div>
  );
}

export default function TopArtistsPage() {
  const { user } = useAuth();
  const [range, setRange] = useState("all");
  const { data: posts, loading } = useLiveQuery("CommunityPost", null, { sort: "-created_date", limit: 500 });
  const { data: artworks } = useLiveQuery("Artwork", null, { sort: "-created_date", limit: 500 });
  const users = usePeople(useMemo(() => [...posts, ...artworks].map((p) => p.user_email), [posts, artworks]), { recentLimit: 50 });

  const ranked = useMemo(() => {
    const since = range === "week" ? Date.now() - 7 * 86400000 : range === "month" ? Date.now() - 30 * 86400000 : 0;
    const stats = {};
    const add = (email, likes, isArt) => {
      if (!email) return;
      stats[email] = stats[email] || { posts: 0, art: 0, likes: 0 };
      stats[email].likes += likes;
      if (isArt) stats[email].art += 1; else stats[email].posts += 1;
    };
    posts.filter((p) => new Date(p.created_date).getTime() >= since).forEach((p) => add(p.user_email, likeCount(p), false));
    artworks.filter((a) => new Date(a.created_date).getTime() >= since).forEach((a) => add(a.user_email, likeCount(a), true));
    return users.filter((u) => stats[u.email]).map((u) => ({ ...u, ...stats[u.email] })).sort((a, b) => b.likes - a.likes || b.posts + b.art - (a.posts + a.art)).slice(0, 25);
  }, [posts, artworks, users, range]);
  const myRank = ranked.findIndex((a) => a.email === user?.email);

  return (
    <Page width="max-w-3xl">
      <PageHeader eyebrow="Leaderboard" title="Top artists" subtitle="Ranked by likes on posts and gallery pieces" icon={Trophy}>
        <Segmented options={RANGES} value={range} onChange={setRange} size="sm" />
      </PageHeader>
      {loading ? (
        <div className="space-y-3">{Array.from({ length: 5 }).map((_, i) => <div key={i} className="skeleton h-16" />)}</div>
      ) : ranked.length === 0 ? (
        <EmptyState icon={Trophy} title="No artists ranked yet" text="Likes on posts and artworks put people on the board." />
      ) : (
        <>
          <Podium key={range} artists={ranked.slice(0, 3)} />
          {myRank >= 0 && (
            <div className="card-sm p-3 mb-4 text-sm font-semibold text-center" style={{ color: "var(--accent-rose)", background: "var(--pink-soft)" }}>You're #{myRank + 1} {range === "all" ? "all time" : range === "month" ? "this month" : "this week"} ✨</div>
          )}
          <div className="space-y-2">
            {ranked.slice(3).map((a, i) => {
              const level = getLevelInfo(a.xp || 0);
              return (
                <motion.div className="enter-side" style={{ "--d": `${Math.round((0.6 + i * 0.04) * 1000)}ms`, "--enter-x": "-16px" }} key={a.email}>
                  <Link to={profileLink(a.email)} className="card-sm card-hover p-3 flex items-center gap-3" style={a.email === user?.email ? { borderColor: "rgb(var(--accent-rgb) / 0.5)" } : undefined}>
                    <span className="w-8 text-center font-display text-lg font-semibold" style={{ color: "var(--text-muted)" }}>{i + 4}</span>
                    <Avatar src={a.profile_picture} name={displayName(a)} size={42} nitro={a.nitro_active} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(a)}</p>
                      <p className="text-[11px] font-semibold" style={{ color: level.current.color }}>Lv.{level.current.level} {level.current.title}</p>
                    </div>
                    <span className="hidden sm:flex items-center gap-1 text-xs" style={{ color: "var(--text-muted)" }}><ImageIcon className="w-3.5 h-3.5" />{a.posts + a.art}</span>
                    <span className="text-sm font-bold flex items-center gap-1 w-14 justify-end" style={{ color: "var(--accent-rose)" }}><Heart className="w-3.5 h-3.5 fill-current" />{a.likes}</span>
                  </Link>
                </motion.div>
              );
            })}
          </div>
        </>
      )}
    </Page>
  );
}
