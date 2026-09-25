import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, Navigate, useLocation, useOutlet } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { MessageCircle, Megaphone, Plus, Search, X } from "lucide-react";
import Sidebar, { Logo } from "@/components/layout/Sidebar";
import CommandPalette from "@/components/layout/CommandPalette";
import CreateMenu from "@/components/layout/CreateMenu";
import MiniPlayer from "@/components/layout/MiniPlayer";
import { MOBILE_NAV, isActivePath } from "@/components/layout/nav";
import NotificationBell from "@/components/notifications/NotificationBell";
import Avatar from "@/components/common/Avatar";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { applyTheme } from "@/lib/theme";
import { pageTransition } from "@/lib/motion";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";

const FULL_HEIGHT = ["/communitychat", "/directmessages"];

function AnnouncementBar({ config }) {
  const text = config?.announcement_active ? String(config.announcement || "").trim() : "";
  const key = `mimilocks:__dismissed:${text}`;
  const [dismissed, setDismissed] = useState(() => { try { return !!localStorage.getItem(key); } catch { return false; } });
  useEffect(() => { try { setDismissed(!!localStorage.getItem(key)); } catch { /* ignore */ } }, [key]);
  if (!text || dismissed) return null;
  return (
    <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} className="relative flex-shrink-0 overflow-hidden text-white" style={{ background: config.announcement_color ? `linear-gradient(90deg, ${config.announcement_color}, rgb(var(--accent-rgb)))` : "var(--accent-grad)", backgroundSize: "200% 100%", animation: "gradient-pan 8s ease infinite" }}>
      <div className="flex items-center gap-2.5 px-4 py-2 text-xs sm:text-sm font-semibold">
        <Megaphone className="w-4 h-4 flex-shrink-0" />
        <span className="flex-1 truncate">{text}</span>
        <button onClick={() => { try { localStorage.setItem(key, "1"); } catch { /* ignore */ } setDismissed(true); }} className="w-6 h-6 rounded-full flex items-center justify-center hover:bg-white/20" aria-label="Dismiss announcement"><X className="w-3.5 h-3.5" /></button>
      </div>
    </motion.div>
  );
}

function TopBar({ onSearch, user }) {
  return (
    <header className="flex-shrink-0 h-16 flex items-center gap-3 px-4 sm:px-6 relative z-20 glass" style={{ borderBottom: "1px solid var(--border-c)" }}>
      <div className="md:hidden"><Logo collapsed /></div>
      <button onClick={onSearch} className="flex-1 max-w-md hidden sm:flex items-center gap-3 h-10 px-4 rounded-full text-sm transition-colors hover:border-[rgb(var(--accent-rgb)/0.4)]" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)", color: "var(--text-muted)" }}>
        <Search className="w-4 h-4" />
        <span className="flex-1 text-left">Search Mimi Locks…</span>
        <span className="kbd">Ctrl</span><span className="kbd -ml-2">K</span>
      </button>
      <div className="flex-1" />
      <button onClick={onSearch} className="icon-btn icon-btn-bordered sm:hidden" aria-label="Search"><Search className="w-[18px] h-[18px]" /></button>
      {user && <NotificationBell me={user} />}
      {user && (
        <Link to={profileLink(user.email)} className="md:hidden" aria-label="Your profile">
          <Avatar src={user.profile_picture} name={displayName(user)} size={36} nitro={user.nitro_active} />
        </Link>
      )}
    </header>
  );
}

function MobileNav({ badges, isAdmin }) {
  const location = useLocation();
  const [createOpen, setCreateOpen] = useState(false);
  useEffect(() => setCreateOpen(false), [location.pathname]);
  return (
    <>
      <AnimatePresence>
        {createOpen && (
          <>
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="md:hidden fixed inset-0 z-[70] backdrop-blur-sm" style={{ background: "rgb(20 8 14 / 0.35)" }} onClick={() => setCreateOpen(false)} />
            <div className="md:hidden fixed z-[75] left-1/2 -translate-x-1/2 bottom-[92px]"><CreateMenu isAdmin={isAdmin} onDone={() => setCreateOpen(false)} /></div>
          </>
        )}
      </AnimatePresence>
      <nav className="md:hidden fixed bottom-0 inset-x-0 z-[65] glass safe-bottom" style={{ borderTop: "1px solid var(--border-c)" }} aria-label="Main">
        <div className="flex items-center justify-around h-[72px] px-2">
          {MOBILE_NAV.map((item) => {
            if (item.label === "create") {
              return (
                <motion.button key="create" whileTap={{ scale: 0.9 }} onClick={() => setCreateOpen((v) => !v)} className="w-14 h-14 -mt-6 rounded-2xl flex items-center justify-center text-white" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }} aria-label="Create" aria-expanded={createOpen}>
                  <motion.span animate={{ rotate: createOpen ? 45 : 0 }} className="inline-flex"><Plus className="w-6 h-6" /></motion.span>
                </motion.button>
              );
            }
            const active = isActivePath(location.pathname, item.path);
            const Icon = item.icon;
            const badge = item.badge ? badges[item.badge] : 0;
            return (
              <Link key={item.path} to={item.path} className="relative flex flex-col items-center justify-center gap-1 w-16 h-14 rounded-2xl" style={{ color: active ? "var(--accent-rose)" : "var(--text-muted)" }}>
                {active && <motion.span layoutId="mobile-nav-active" className="absolute inset-1 rounded-2xl" style={{ background: "var(--pink-soft)" }} transition={{ type: "spring", stiffness: 420, damping: 34 }} />}
                <span className="relative">
                  <Icon className="w-5 h-5" />
                  {badge > 0 && <span className="absolute -top-1.5 -right-2 min-w-[16px] h-4 px-1 rounded-full text-[9px] font-bold text-white flex items-center justify-center" style={{ background: "var(--accent-rose)" }}>{badge > 9 ? "9+" : badge}</span>}
                </span>
                <span className="relative text-[10px] font-bold">{item.label}</span>
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}

// App shell: sidebar, top bar, animated page outlet, mobile nav and global widgets.
export default function Layout() {
  const location = useLocation();
  const outlet = useOutlet();
  const { user, isAdmin, updateMe } = useAuth();
  const mainRef = useRef(null);
  const [collapsed, setCollapsed] = useState(() => { try { return localStorage.getItem("mimilocks:__sidebar") === "collapsed"; } catch { return false; } });
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [isDark, setIsDark] = useState(() => document.documentElement.classList.contains("dark"));

  const { data: siteConfigs } = useLiveQuery("SiteConfig", { key: "global" }, { enabled: !!user });
  const siteConfig = siteConfigs[0];

  // Apply the user's theme + accent (falling back to the site default accent).
  useEffect(() => {
    if (!user) return;
    applyTheme({ theme: user.theme || "light", accent: user.accent || siteConfig?.default_accent || "rose" });
    setIsDark(document.documentElement.classList.contains("dark"));
  }, [user?.theme, user?.accent, siteConfig?.default_accent]);

  // Unread DM + pending friend request badges, with a toast for new messages.
  const onDmsPage = location.pathname.toLowerCase() === "/directmessages";
  const onDmsPageRef = useRef(onDmsPage);
  onDmsPageRef.current = onDmsPage;
  const { data: dms } = useLiveQuery("DirectMessage", user ? { member_emails: { $contains: user.email } } : null, {
    sort: "-created_date",
    limit: 100,
    enabled: !!user,
    onEvent: (ev) => {
      if (ev.type !== "create" || ev.data?.user_email === user?.email || onDmsPageRef.current) return;
      toast(`${ev.data.user_display_name || "Someone"}: ${String(ev.data.content || "sent an image").slice(0, 80)}`, { icon: <MessageCircle className="w-5 h-5" />, description: ev.data.conversation_type === "group" ? ev.data.group_name : "Direct message" });
    },
  });
  const { data: requests } = useLiveQuery("Friendship", user ? { receiver_email: user.email, status: "pending" } : null, { enabled: !!user });
  const badges = useMemo(() => ({
    dms: new Set(dms.filter((m) => m.user_email !== user?.email && !(m.read_by || []).includes(user?.email)).map((m) => m.conversation_id)).size,
    friends: requests.length,
  }), [dms, requests, user?.email]);

  const toggleTheme = useCallback(() => {
    const next = document.documentElement.classList.contains("dark") ? "light" : "dark";
    applyTheme({ theme: next });
    setIsDark(next === "dark");
    updateMe({ theme: next }).catch(() => {});
  }, [updateMe]);

  useEffect(() => {
    const onKey = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") { e.preventDefault(); setPaletteOpen((v) => !v); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => { mainRef.current?.scrollTo({ top: 0 }); }, [location.pathname]);

  const toggleCollapsed = () => setCollapsed((c) => {
    try { localStorage.setItem("mimilocks:__sidebar", c ? "expanded" : "collapsed"); } catch { /* ignore */ }
    return !c;
  });

  if (user && !user.onboarding_completed) return <Navigate to="/Onboarding" replace />;

  const fullHeight = FULL_HEIGHT.includes(location.pathname.toLowerCase());
  const hideMobileNav = location.pathname.toLowerCase() === "/communitychat";

  return (
    <div className="app-shell flex h-[100dvh] overflow-hidden">
      <Sidebar collapsed={collapsed} onToggleCollapsed={toggleCollapsed} badges={badges} onToggleTheme={toggleTheme} isDark={isDark} />
      <div className="flex-1 min-w-0 flex flex-col relative">
        <AnnouncementBar config={siteConfig} />
        {!fullHeight && <TopBar onSearch={() => setPaletteOpen(true)} user={user} />}
        <main ref={mainRef} id="main" className={`flex-1 min-h-0 relative ${fullHeight ? `overflow-hidden ${hideMobileNav ? "" : "pb-[72px] md:pb-0"}` : "overflow-y-auto overflow-x-hidden scroll"}`}>
          {/* Enter-only transition keyed by route; no exit phase that could stall navigation. */}
          <motion.div key={location.pathname} initial={pageTransition.initial} animate={pageTransition.animate} className={fullHeight ? "h-full" : "min-h-full"}>
            {outlet}
          </motion.div>
        </main>
      </div>
      {!hideMobileNav && <MobileNav badges={badges} isAdmin={isAdmin} />}
      <MiniPlayer raised={!hideMobileNav} />
      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} isDark={isDark} onToggleTheme={toggleTheme} />
    </div>
  );
}
