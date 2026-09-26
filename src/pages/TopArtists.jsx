import React, { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Crown, Heart, Image as ImageIcon, Trophy } from "lucide-react";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useAuth } from "@/lib/AuthContext";
import { displayName, profileLink } from "@/lib/format";
import { Page, PageHeader, EmptyState } from "@/components/common/Page";
import { Segmented } from "@/components/common/Controls";
import Avatar from "@/components/common/Avatar";
import { getLevelInfo } from "@/components/profile/LevelBadge";

const MEDALS = [
  { color: "#f0a020", bg: "linear-gradient(180deg,#ffe29a,#f0a020)", height: 150 },
  { color: "#94a3b8", bg: "linear-gradient(180deg,#e2e8f0,#94a3b8)", height: 110 },
  { color: "#c2773a", bg: "linear-gradient(180deg,#f5c9a0,#c2773a)", height: 84 },
];
const RANGES = [{ id: "all", label: "All time" }, { id: "month", label: "This month" }, { id: "week", label: "This week" }];

function Podium({ artists }) {
  const order = [artists[1], artists[0], artists[2]];
  const medalIndex = [1, 0, 2];
  return (
    <div className="flex items-end justify-center gap-3 sm:gap-6 mb-10 pt-6">
      {order.map((a, i) => {
        if (!a) return <div key={i} className="w-24 sm:w-36" />;
        const m = MEDALS[medalIndex[i]];
        const rank = medalIndex[i] + 1;
        return (
          <div key={a.email} className="flex flex-col items-center w-24 sm:w-36">
            <motion.div initial={{ opacity: 0, y: 20, scale: 0.8 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ delay: 0.5 + i * 0.15, type: "spring", stiffness: 260, damping: 18 }} className="flex flex-col items-center mb-3">
              {rank === 1 && <div className="anim-bob" style={{ animationDuration: "2.5s" }}><Crown className="w-7 h-7 mb-1" style={{ color: m.color, fill: m.color }} /></div>}
              <Link to={profileLink(a.email)} className="flex rounded-full">
                <Avatar src={a.profile_picture} name={displayName(a)} size={rank === 1 ? 84 : 66} style={{ boxShadow: `0 0 0 4px var(--surface), 0 0 0 7px ${m.color}` }} />
              </Link>
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
  const { data: users } = useLiveQuery("User", null, { live: false });

  const ranked = useMemo(() => {
    const since = range === "week" ? Date.now() - 7 * 86400000 : range === "month" ? Date.now() - 30 * 86400000 : 0;
    const stats = {};
    const add = (email, likes, isArt) => {
      if (!email) return;
      stats[email] = stats[email] || { posts: 0, art: 0, likes: 0 };
      stats[email].likes += likes;
      if (isArt) stats[email].art += 1; else stats[email].posts += 1;
    };
    posts.filter((p) => new Date(p.created_date).getTime() >= since).forEach((p) => add(p.user_email, p.likes?.length || 0, false));
    artworks.filter((a) => new Date(a.created_date).getTime() >= since).forEach((a) => add(a.user_email, a.likes?.length || 0, true));
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
