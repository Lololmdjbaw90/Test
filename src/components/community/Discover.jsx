import React from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Check, Hash, Plus, Server, TrendingUp, UserPlus, X } from "lucide-react";
import Avatar from "@/components/common/Avatar";
import { displayName, isOnline, profileLink } from "@/lib/format";

// Story-style row of people who posted recently. A colourful ring means
// there's something you haven't seen yet.
export function ActiveCreators({ me, creators, onOpen, onCompose }) {
  if (!creators.length && !me) return null;
  return (
    <div className="flex gap-3.5 overflow-x-auto no-scrollbar -mx-4 px-4 sm:mx-0 sm:px-0 pb-1">
      {me && (
        <button onClick={onCompose} className="flex flex-col items-center gap-1.5 w-[68px] flex-shrink-0" aria-label="Create a post">
          <span className="relative flex p-[5px] rounded-full" style={{ background: "var(--border-c)" }}>
            <Avatar src={me.profile_picture} name={displayName(me)} size={58} ring={2} ringColor="var(--app-bg)" />
            <span className="absolute -bottom-0.5 -right-0.5 w-6 h-6 rounded-full flex items-center justify-center text-white" style={{ background: "var(--accent-grad)", boxShadow: "0 0 0 3px var(--app-bg)" }}><Plus className="w-3.5 h-3.5" /></span>
          </span>
          <span className="text-[11px] font-semibold truncate w-full text-center" style={{ color: "var(--text-secondary)" }}>Your post</span>
        </button>
      )}
      {creators.map((c, i) => (
        <button
          key={c.email}
          onClick={() => onOpen(c)}
          className="enter-pop flex flex-col items-center gap-1.5 w-[68px] flex-shrink-0"
          style={{ "--d": `${Math.min(i, 8) * 35}ms` }}
          aria-label={`${c.name}'s latest post`}
        >
          <span className="flex p-[5px] rounded-full" style={{ background: c.unseen ? "conic-gradient(from 200deg, #f59e0b, rgb(var(--accent-rgb)), #a855f7, #f59e0b)" : "var(--border-strong)" }}>
            <Avatar src={c.user?.profile_picture || c.picture} name={c.name} size={58} ring={2} ringColor="var(--app-bg)" online={c.user ? (isOnline(c.user) || undefined) : undefined} />
          </span>
          <span className="text-[11px] font-semibold truncate w-full text-center" style={{ color: c.unseen ? "var(--text-primary)" : "var(--text-muted)" }}>{c.name.split(" ")[0]}</span>
        </button>
      ))}
    </div>
  );
}

function FollowButton({ following, onClick, small }) {
  return (
    <motion.button whileTap={{ scale: 0.92 }} onClick={onClick} className={following ? "btn-outline" : "btn"} style={small ? { padding: "0.35rem 0.8rem", fontSize: 12 } : { padding: "0.45rem 0.95rem", fontSize: 13 }}>
      {following ? <><Check className="w-3.5 h-3.5" /> Following</> : <><UserPlus className="w-3.5 h-3.5" /> Follow</>}
    </motion.button>
  );
}

export function SuggestedPeople({ items, followingSet, onFollow, variant = "list", onDismiss }) {
  if (!items.length) return null;
  if (variant === "carousel") {
    return (
      <div className="card !rounded-[1.75rem] py-4">
        <div className="flex items-center justify-between px-4 mb-3">
          <p className="font-bold text-sm" style={{ color: "var(--text-primary)" }}>Suggested for you</p>
          <Link to="/Friends" className="text-xs font-bold" style={{ color: "var(--accent-rose)" }}>See all</Link>
        </div>
        <div className="flex gap-3 overflow-x-auto no-scrollbar px-4 snap-x">
          {items.map(({ user, reason }) => (
            <div key={user.email} className="snap-start flex-shrink-0 w-40 rounded-3xl p-4 flex flex-col items-center text-center gap-2 relative" style={{ background: "var(--surface-2)" }}>
              {onDismiss && <button onClick={() => onDismiss(user.email)} className="absolute top-2 right-2 w-6 h-6 rounded-full flex items-center justify-center" style={{ color: "var(--text-muted)" }} aria-label={`Dismiss ${displayName(user)}`}><X className="w-3.5 h-3.5" /></button>}
              <Link to={profileLink(user.email)}><Avatar src={user.profile_picture} name={displayName(user)} size={64} online={isOnline(user) || undefined} /></Link>
              <div className="min-w-0 w-full">
                <Link to={profileLink(user.email)} className="block text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(user)}</Link>
                <p className="text-[11px] truncate" style={{ color: "var(--text-muted)" }}>{reason}</p>
              </div>
              <FollowButton small following={followingSet.has(user.email)} onClick={() => onFollow(user.email)} />
            </div>
          ))}
        </div>
      </div>
    );
  }
  return (
    <section>
      <div className="flex items-center justify-between mb-2">
        <p className="font-bold text-sm" style={{ color: "var(--text-secondary)" }}>Suggested for you</p>
        <Link to="/Friends" className="text-xs font-bold" style={{ color: "var(--accent-rose)" }}>See all</Link>
      </div>
      <div className="space-y-1">
        {items.map(({ user, reason }, i) => (
          <div key={user.email} className="enter-side flex items-center gap-3 py-1.5" style={{ "--d": `${i * 40}ms`, "--enter-x": "10px" }}>
            <Link to={profileLink(user.email)}><Avatar src={user.profile_picture} name={displayName(user)} size={40} online={isOnline(user) || undefined} /></Link>
            <div className="flex-1 min-w-0">
              <Link to={profileLink(user.email)} className="block text-sm font-bold truncate hover:underline" style={{ color: "var(--text-primary)" }}>{displayName(user)}</Link>
              <p className="text-[11px] truncate" style={{ color: "var(--text-muted)" }}>{reason}</p>
            </div>
            <button onClick={() => onFollow(user.email)} className="text-xs font-bold flex-shrink-0 px-2 py-1 rounded-lg transition-colors hover:bg-[var(--pink-soft)]" style={{ color: followingSet.has(user.email) ? "var(--text-muted)" : "var(--accent-rose)" }}>
              {followingSet.has(user.email) ? "Following" : "Follow"}
            </button>
          </div>
        ))}
      </div>
    </section>
  );
}

export function TrendingTags({ tags, active, onTag, variant = "list" }) {
  if (!tags.length) return null;
  if (variant === "chips") {
    return (
      <div className="flex gap-2 overflow-x-auto no-scrollbar -mx-4 px-4 sm:-mx-1 sm:px-1 pt-1 pb-3 -mt-1 -mb-2">
        <span className="chip !cursor-default flex-shrink-0" style={{ background: "transparent", borderColor: "transparent" }}><TrendingUp className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> Trending</span>
        {tags.map((t) => <button key={t.tag} className="chip flex-shrink-0" data-active={active === t.tag} onClick={() => onTag(active === t.tag ? null : t.tag)}>#{t.tag}</button>)}
      </div>
    );
  }
  return (
    <section>
      <p className="font-bold text-sm mb-2 flex items-center gap-1.5" style={{ color: "var(--text-secondary)" }}><TrendingUp className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> Trending now</p>
      <div className="space-y-0.5">
        {tags.map((t, i) => (
          <button key={t.tag} onClick={() => onTag(active === t.tag ? null : t.tag)} className="w-full flex items-center gap-3 px-2 py-2 rounded-xl text-left transition-colors hover:bg-[var(--surface-2)]" style={active === t.tag ? { background: "var(--pink-soft)" } : undefined}>
            <span className="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0" style={{ background: "var(--surface-2)", color: "var(--accent-rose)" }}><Hash className="w-4 h-4" /></span>
            <span className="flex-1 min-w-0">
              <span className="block text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>#{t.tag}</span>
              <span className="block text-[11px]" style={{ color: "var(--text-muted)" }}>{i === 0 ? "🔥 Top today · " : ""}{t.posts} post{t.posts === 1 ? "" : "s"}</span>
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}

export function ServerSuggestions({ items }) {
  if (!items.length) return null;
  return (
    <section>
      <p className="font-bold text-sm mb-2 flex items-center gap-1.5" style={{ color: "var(--text-secondary)" }}><Server className="w-4 h-4" style={{ color: "var(--accent-rose)" }} /> Servers for you</p>
      <div className="space-y-1">
        {items.map(({ community: c, reason }) => (
          <Link key={c.id} to={`/CommunityChat?id=${c.id}`} className="flex items-center gap-3 px-2 py-2 rounded-xl transition-colors hover:bg-[var(--surface-2)]">
            <span className="w-10 h-10 rounded-2xl overflow-hidden flex items-center justify-center text-xl flex-shrink-0" style={{ background: "var(--pink-soft)" }}>{c.icon_url ? <img loading="lazy" decoding="async" src={c.icon_url} alt="" className="w-full h-full object-cover" /> : c.icon_emoji || "💬"}</span>
            <span className="flex-1 min-w-0">
              <span className="block text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{c.name}</span>
              <span className="block text-[11px] truncate" style={{ color: "var(--text-muted)" }}>{reason}</span>
            </span>
            <span className="text-xs font-bold px-2.5 py-1 rounded-full" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}>View</span>
          </Link>
        ))}
      </div>
    </section>
  );
}
