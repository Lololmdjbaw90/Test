import React, { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { useDelayedUnmount } from "@/components/common/Modal";
import { ArrowRight, CornerDownLeft, Image as ImageIcon, LogOut, Moon, Music, Palette, Search, Server, Sparkles, Sun, User, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { ACCENTS } from "@/lib/theme";
import { displayName, profileLink } from "@/lib/format";
import { ADMIN_SECTION, NAV_SECTIONS, ACCOUNT_ITEMS } from "./nav";
import { CREATE_ACTIONS } from "./CreateMenu";
import Avatar from "@/components/common/Avatar";

// Ctrl/⌘ + K palette: jump to pages, people, artworks, posts, servers and tracks.
export default function CommandPalette({ open, onClose, isDark, onToggleTheme }) {
  const navigate = useNavigate();
  const { user, isAdmin, logout, updateMe } = useAuth();
  const [q, setQ] = useState("");
  const [data, setData] = useState(null);
  const [index, setIndex] = useState(0);
  const listRef = useRef(null);
  const mounted = useDelayedUnmount(open, 180);

  useEffect(() => {
    if (!open) return;
    setQ("");
    setIndex(0);
    let cancelled = false;
    const safe = (p) => p.catch(() => []);
    Promise.all([
      safe(base44.entities.User.list("-last_seen", 200)),
      safe(base44.entities.Artwork.list("-created_date", 200)),
      safe(base44.entities.CommunityPost.list("-created_date", 200)),
      safe(base44.entities.Community.list("-created_date", 100)),
      safe(base44.entities.MusicReview.list("-created_date", 100)),
    ]).then(([users, artworks, posts, servers, tracks]) => { if (!cancelled) setData({ users, artworks, posts, servers, tracks }); });
    return () => { cancelled = true; };
  }, [open]);

  const groups = useMemo(() => {
    const term = q.trim().toLowerCase();
    const has = (...fields) => !term || fields.some((f) => String(f || "").toLowerCase().includes(term));
    const go = (to) => () => navigate(to);
    const pages = [...NAV_SECTIONS, ...(isAdmin ? [ADMIN_SECTION] : [])].flatMap((s) => s.items)
      .concat(ACCOUNT_ITEMS.map((i) => (i.path === "/Profile" ? { ...i, path: profileLink(user?.email) } : i)))
      .filter((p) => has(p.label))
      .map((p) => ({ id: `page-${p.label}`, icon: p.icon, label: p.label, hint: "Page", run: go(p.path) }));
    const actions = [
      ...CREATE_ACTIONS.map((a) => ({ id: `create-${a.to}`, icon: a.icon, label: a.label, hint: "Create", run: go(a.to) })),
      { id: "theme", icon: isDark ? Sun : Moon, label: isDark ? "Switch to light mode" : "Switch to dark mode", hint: "Theme", run: onToggleTheme },
      ...ACCENTS.map((a) => ({ id: `accent-${a.id}`, icon: Palette, label: `Accent: ${a.label}`, hint: "Theme", swatch: a.swatch, run: () => updateMe({ accent: a.id }) })),
      { id: "logout", icon: LogOut, label: "Log out", hint: "Account", run: logout },
    ].filter((a) => has(a.label, a.hint));
    const out = [
      { title: "Pages", items: pages.slice(0, term ? 8 : 6) },
      { title: "Actions", items: actions.slice(0, term ? 8 : 4) },
    ];
    if (data && term) {
      out.push({ title: "People", items: data.users.filter((u) => has(u.display_name, u.full_name, u.email)).slice(0, 5).map((u) => ({ id: `user-${u.id}`, avatar: u, label: displayName(u), hint: u.email, run: go(profileLink(u.email)) })) });
      out.push({ title: "Artworks", items: data.artworks.filter((a) => has(a.title, a.description, a.medium)).slice(0, 5).map((a) => ({ id: `art-${a.id}`, icon: ImageIcon, image: a.image_url, label: a.title, hint: a.medium?.replace("_", " "), run: go(`/Gallery?art=${a.id}`) })) });
      out.push({ title: "Posts", items: data.posts.filter((p) => has(p.title, p.description, p.user_display_name)).slice(0, 5).map((p) => ({ id: `post-${p.id}`, icon: Users, image: p.image_url, label: p.title || p.description?.slice(0, 50) || "Post", hint: `by ${p.user_display_name}`, run: go(`/Community?post=${p.id}`) })) });
      out.push({ title: "Servers", items: data.servers.filter((s) => has(s.name, s.description)).slice(0, 5).map((s) => ({ id: `srv-${s.id}`, icon: Server, emoji: s.icon_emoji, label: s.name, hint: `${s.member_emails?.length || 0} members`, run: go(`/CommunityChat?id=${s.id}`) })) });
      out.push({ title: "Music", items: data.tracks.filter((t) => has(t.title, t.genre, t.user_display_name)).slice(0, 5).map((t) => ({ id: `trk-${t.id}`, icon: Music, label: t.title, hint: t.genre || t.user_display_name, run: go(`/Music?track=${t.id}`) })) });
    }
    return out.filter((g) => g.items.length > 0);
  }, [q, data, isAdmin, isDark, user?.email, navigate, onToggleTheme, logout, updateMe]);

  const flat = useMemo(() => groups.flatMap((g) => g.items), [groups]);
  useEffect(() => { setIndex(0); }, [q]);
  useEffect(() => {
    listRef.current?.querySelector(`[data-index="${index}"]`)?.scrollIntoView({ block: "nearest" });
  }, [index]);

  const runItem = (item) => { if (!item) return; onClose(); setTimeout(() => item.run?.(), 0); };
  const onKeyDown = (e) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setIndex((i) => Math.min(flat.length - 1, i + 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setIndex((i) => Math.max(0, i - 1)); }
    else if (e.key === "Enter") { e.preventDefault(); runItem(flat[index]); }
    else if (e.key === "Escape") onClose();
  };

  let running = -1;
  if (!mounted) return null;
  return createPortal(
    <>
      {(
        <motion.div className="fixed inset-0 z-[150] flex items-start justify-center p-3 pt-[10vh]" initial={{ opacity: 0 }} animate={{ opacity: open ? 1 : 0 }} transition={{ duration: 0.15 }} style={{ pointerEvents: open ? "auto" : "none" }}>
          <div className="absolute inset-0 can-hover:backdrop-blur-sm" style={{ background: "rgb(20 8 14 / 0.4)" }} onClick={onClose} />
          <motion.div
            initial={{ opacity: 0, y: -16, scale: 0.97 }}
            animate={open ? { opacity: 1, y: 0, scale: 1 } : { opacity: 0, y: -10, scale: 0.98 }}
            transition={{ type: "spring", stiffness: 420, damping: 32 }}
            className="relative w-full max-w-xl rounded-3xl overflow-hidden"
            style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}
            role="dialog"
            aria-label="Search"
          >
            <div className="flex items-center gap-3 px-5 h-16 border-b" style={{ borderColor: "var(--border-c)" }}>
              <Search className="w-5 h-5 flex-shrink-0" style={{ color: "var(--accent-rose)" }} />
              <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={onKeyDown} placeholder="Search people, art, posts, servers…" className="flex-1 bg-transparent outline-none text-base" style={{ color: "var(--text-primary)" }} />
              <span className="kbd">Esc</span>
            </div>
            <div ref={listRef} className="max-h-[60vh] overflow-y-auto scroll p-2">
              {groups.length === 0 && (
                <div className="py-12 text-center">
                  <Sparkles className="w-6 h-6 mx-auto mb-2" style={{ color: "var(--accent-pink)" }} />
                  <p className="text-sm" style={{ color: "var(--text-muted)" }}>{data ? `No results for "${q}"` : "Searching…"}</p>
                </div>
              )}
              {groups.map((g) => (
                <div key={g.title} className="mb-1">
                  <p className="eyebrow px-3 pt-2 pb-1">{g.title}</p>
                  {g.items.map((item) => {
                    running += 1;
                    const i = running;
                    const active = i === index;
                    const Icon = item.icon || User;
                    return (
                      <button
                        key={item.id}
                        data-index={i}
                        onMouseMove={() => setIndex(i)}
                        onClick={() => runItem(item)}
                        className="relative w-full flex items-center gap-3 px-3 py-2.5 rounded-2xl text-left"
                      >
                        {active && <span className="absolute inset-0 rounded-2xl" style={{ background: "var(--pink-soft)" }} />}
                        <span className="relative w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0 overflow-hidden" style={{ background: item.swatch || "var(--surface-2)", color: "var(--accent-rose)" }}>
                          {item.avatar ? <Avatar src={item.avatar.profile_picture} name={displayName(item.avatar)} size={36} /> : item.image ? <img loading="lazy" decoding="async" src={item.image} alt="" className="w-full h-full object-cover" /> : item.emoji ? <span className="text-lg">{item.emoji}</span> : !item.swatch && <Icon className="w-4 h-4" />}
                        </span>
                        <span className="relative flex-1 min-w-0">
                          <span className="block text-sm font-semibold truncate" style={{ color: "var(--text-primary)" }}>{item.label}</span>
                          {item.hint && <span className="block text-xs truncate capitalize" style={{ color: "var(--text-muted)" }}>{item.hint}</span>}
                        </span>
                        {active && <ArrowRight className="relative w-4 h-4" style={{ color: "var(--accent-rose)" }} />}
                      </button>
                    );
                  })}
                </div>
              ))}
            </div>
            <div className="hidden sm:flex items-center gap-4 px-5 py-2.5 border-t text-[11px]" style={{ borderColor: "var(--border-c)", color: "var(--text-muted)" }}>
              <span className="flex items-center gap-1.5"><span className="kbd">↑</span><span className="kbd">↓</span> navigate</span>
              <span className="flex items-center gap-1.5"><span className="kbd"><CornerDownLeft className="w-3 h-3" /></span> open</span>
              <span className="flex items-center gap-1.5 ml-auto"><span className="kbd">Ctrl</span><span className="kbd">K</span> toggle</span>
            </div>
          </motion.div>
        </motion.div>
      )}
    </>,
    document.body,
  );
}
