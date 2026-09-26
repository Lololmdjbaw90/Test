import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, Navigate, useLocation, useNavigate, useOutlet } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, LogOut, MessageCircle, Megaphone, Moon, Plus, Search, Settings, Sun, X } from "lucide-react";
import Sidebar, { Logo } from "@/components/layout/Sidebar";
import CommandPalette from "@/components/layout/CommandPalette";
import CreateMenu from "@/components/layout/CreateMenu";
import MiniPlayer from "@/components/layout/MiniPlayer";
import VoiceDock from "@/components/voice/VoiceDock";
import { InstallBanner } from "@/components/layout/InstallApp";
import ReportHost from "@/components/safety/ReportDialog";
import CallManager from "@/components/voice/CallManager";
import { ADMIN_SECTION, MOBILE_NAV, NAV_SECTIONS, isActivePath } from "@/components/layout/nav";
import Popover from "@/components/common/Popover";
import { useMediaQuery } from "@/lib/useMediaQuery";
import NotificationBell from "@/components/notifications/NotificationBell";
import Avatar from "@/components/common/Avatar";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { applyTheme } from "@/lib/theme";
import { toast } from "@/lib/toast";
import { displayName, profileLink } from "@/lib/format";
import { messagePreview } from "@/lib/calls";
import ErrorBoundary from "@/components/common/ErrorBoundary";

const FULL_HEIGHT = ["/communitychat", "/directmessages"];
const EXTRA_TITLES = { "/profile": "Profile", "/settings": "Settings", "/communitychat": "Server", "/upload": "Upload art" };
function pageTitle(pathname) {
  const p = pathname.toLowerCase();
  const item = [...NAV_SECTIONS, ADMIN_SECTION].flatMap((s) => s.items).find((i) => i.path.toLowerCase() === p);
  const label = p === "/" ? "" : item?.label || EXTRA_TITLES[p] || "";
  return label ? `${label} · Sugerly` : "Sugerly";
}
// True when there's an in-app page to go back to (React Router stores the index).
const canGoBack = () => (window.history.state?.idx ?? 0) > 0;

function OfflineBar() {
  const [online, setOnline] = useState(() => navigator.onLine !== false);
  useEffect(() => {
    const up = () => setOnline(true);
    const down = () => setOnline(false);
    window.addEventListener("online", up);
    window.addEventListener("offline", down);
    return () => { window.removeEventListener("online", up); window.removeEventListener("offline", down); };
  }, []);
  return (
    <AnimatePresence initial={false}>
      {!online && (
        <motion.div initial={{ height: 0 }} animate={{ height: "auto" }} exit={{ height: 0 }} className="flex-shrink-0 overflow-hidden">
          <p className="text-center text-xs font-bold py-1.5 text-white" style={{ background: "#6b5b64" }}>You're offline — changes will sync when you reconnect</p>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function AnnouncementBar({ config }) {
  const text = config?.announcement_active ? String(config.announcement || "").trim() : "";
  const key = `mimilocks:__dismissed:${text}`;
  const [dismissed, setDismissed] = useState(() => { try { return !!localStorage.getItem(key); } catch { return false; } });
  useEffect(() => { try { setDismissed(!!localStorage.getItem(key)); } catch { /* ignore */ } }, [key]);
  if (!text || dismissed) return null;
  return (
    <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} className="relative flex-shrink-0 overflow-hidden text-white" style={{ background: config.announcement_color ? `linear-gradient(90deg, ${config.announcement_color}, rgb(var(--accent-rgb)))` : "var(--accent-grad)" }}>
      <div className="flex items-center gap-2.5 px-4 py-2 text-xs sm:text-sm font-semibold">
        <Megaphone className="w-4 h-4 flex-shrink-0" />
        <span className="flex-1 truncate">{text}</span>
        <button onClick={() => { try { localStorage.setItem(key, "1"); } catch { /* ignore */ } setDismissed(true); }} className="w-6 h-6 rounded-full flex items-center justify-center hover:bg-white/20" aria-label="Dismiss announcement"><X className="w-3.5 h-3.5" /></button>
      </div>
    </motion.div>
  );
}

function TopBar({ onSearch, user }) {
  const location = useLocation();
  const navigate = useNavigate();
  // Phones (and the installed app, which has no browser back button) get a
  // back arrow once you've moved away from Home.
  const showBack = location.pathname !== "/" && canGoBack();
  return (
    <header className="flex-shrink-0 h-16 flex items-center gap-3 px-4 sm:px-6 relative z-20 glass" style={{ borderBottom: "1px solid var(--border-c)" }}>
      <div className="md:hidden flex items-center gap-1">
        {showBack ? (
          <button onClick={() => navigate(-1)} className="icon-btn -ml-2" aria-label="Go back"><ArrowLeft className="w-5 h-5" /></button>
        ) : <Logo bar />}
      </div>
      <button onClick={onSearch} className="flex-1 max-w-md hidden sm:flex items-center gap-3 h-10 px-4 rounded-full text-sm transition-colors hover:border-[rgb(var(--accent-rgb)/0.4)]" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)", color: "var(--text-muted)" }}>
        <Search className="w-4 h-4" />
        <span className="flex-1 min-w-0 text-left truncate">Search Sugerly…</span>
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

function MoreSheet({ open, onClose, anchorRef, badges, isDark, onToggleTheme }) {
  const { user, isAdmin, logout } = useAuth();
  const location = useLocation();
  const sections = isAdmin ? [...NAV_SECTIONS, ADMIN_SECTION] : NAV_SECTIONS;
  return (
    <Popover open={open} onClose={onClose} anchorRef={anchorRef} placement="top-end" width={340} label="More">
      <div className="px-4 pb-4 pt-1 space-y-4">
        {user && (
          <Link to={profileLink(user.email)} onClick={onClose} className="card-sm p-3 flex items-center gap-3">
            <Avatar src={user.profile_picture} name={displayName(user)} size={44} nitro={user.nitro_active} online />
            <span className="flex-1 min-w-0">
              <span className="block font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(user)}</span>
              <span className="block text-xs" style={{ color: "var(--text-muted)" }}>View your profile</span>
            </span>
          </Link>
        )}
        {sections.map((section) => (
          <div key={section.label}>
            <p className="eyebrow mb-2 px-1">{section.label}</p>
            <div className="grid grid-cols-4 gap-2">
              {section.items.map((item) => {
                const active = isActivePath(location.pathname, item.path);
                const badge = item.badge ? badges[item.badge] : 0;
                return (
                  <Link key={item.path} to={item.path} onClick={onClose} className="relative flex flex-col items-center gap-1.5 py-2.5 rounded-2xl transition-colors" style={{ background: active ? "var(--pink-soft)" : "var(--surface-2)", color: active ? "var(--accent-rose)" : "var(--text-secondary)" }}>
                    <item.icon className="w-5 h-5" />
                    <span className="text-[10px] font-bold text-center leading-tight px-1">{item.label}</span>
                    {badge > 0 && <span className="absolute top-1.5 right-2 min-w-[16px] h-4 px-1 rounded-full text-[9px] font-bold text-white flex items-center justify-center" style={{ background: "var(--accent-rose)" }}>{badge > 9 ? "9+" : badge}</span>}
                  </Link>
                );
              })}
            </div>
          </div>
        ))}
        <div className="grid grid-cols-3 gap-2">
          <button onClick={onToggleTheme} className="btn-outline !px-2">{isDark ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}{isDark ? "Light" : "Dark"}</button>
          <Link to="/Settings" onClick={onClose} className="btn-outline !px-2"><Settings className="w-4 h-4" /> Settings</Link>
          <button onClick={logout} className="btn-outline !px-2" style={{ color: "var(--danger)" }}><LogOut className="w-4 h-4" /> Log out</button>
        </div>
      </div>
    </Popover>
  );
}

function MobileNav({ badges, isAdmin, isDark, onToggleTheme }) {
  const location = useLocation();
  const [sheet, setSheet] = useState(null); // "create" | "more" | null
  const createRef = useRef(null);
  const moreRef = useRef(null);
  useEffect(() => setSheet(null), [location.pathname, location.search]);
  const moreActive = !MOBILE_NAV.some((i) => i.path && isActivePath(location.pathname, i.path));
  return (
    <>
      <Popover open={sheet === "create"} onClose={() => setSheet(null)} anchorRef={createRef} placement="top-center" width={300} label="Create">
        <p className="eyebrow px-5 pt-1">Create something</p>
        <CreateMenu isAdmin={isAdmin} onDone={() => setSheet(null)} className="pb-4" />
      </Popover>
      <MoreSheet open={sheet === "more"} onClose={() => setSheet(null)} anchorRef={moreRef} badges={badges} isDark={isDark} onToggleTheme={onToggleTheme} />
      <nav className="mobile-tabbar md:hidden fixed bottom-0 inset-x-0 z-[65] glass safe-bottom" style={{ borderTop: "1px solid var(--border-c)" }} aria-label="Main">
        <div className="flex items-center justify-around h-[68px] px-2">
          {MOBILE_NAV.map((item) => {
            if (item.label === "create") {
              return (
                <motion.button key="create" ref={createRef} whileTap={{ scale: 0.9 }} onClick={() => setSheet((v) => (v === "create" ? null : "create"))} className="w-14 h-14 -mt-6 rounded-2xl flex items-center justify-center text-white" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }} aria-label="Create" aria-expanded={sheet === "create"}>
                  <motion.span animate={{ rotate: sheet === "create" ? 45 : 0 }} className="inline-flex"><Plus className="w-6 h-6" /></motion.span>
                </motion.button>
              );
            }
            const isMore = item.label === "More";
            const active = isMore ? moreActive || sheet === "more" : isActivePath(location.pathname, item.path);
            const Icon = item.icon;
            const badge = isMore ? (badges.friends || 0) : item.badge ? badges[item.badge] : 0;
            const inner = (
              <>
                {active && <span className="absolute inset-1 rounded-2xl enter-fade" style={{ background: "var(--pink-soft)" }} />}
                <span className="relative">
                  <Icon className="w-5 h-5" />
                  {badge > 0 && <span className="absolute -top-1.5 -right-2 min-w-[16px] h-4 px-1 rounded-full text-[9px] font-bold text-white flex items-center justify-center" style={{ background: "var(--accent-rose)" }}>{badge > 9 ? "9+" : badge}</span>}
                </span>
                <span className="relative text-[10px] font-bold">{item.label}</span>
              </>
            );
            const cls = "relative flex flex-col items-center justify-center gap-1 w-16 h-14 rounded-2xl";
            const style = { color: active ? "var(--accent-rose)" : "var(--text-muted)" };
            // Tapping the tab you're already on scrolls back to the top, like native apps.
            const onTabClick = (e) => {
              if (!active) return;
              e.preventDefault();
              document.getElementById("main")?.scrollTo({ top: 0, behavior: "smooth" });
            };
            return isMore ? (
              <button key="more" ref={moreRef} onClick={() => setSheet((v) => (v === "more" ? null : "more"))} className={cls} style={style} aria-label="More pages" aria-expanded={sheet === "more"}>{inner}</button>
            ) : (
              <Link key={item.path} to={item.path} onClick={onTabClick} className={cls} style={style} aria-current={active ? "page" : undefined}>{inner}</Link>
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
  const [collapsedPref, setCollapsed] = useState(() => { try { return localStorage.getItem("mimilocks:__sidebar") === "collapsed"; } catch { return false; } });
  // Tablets in portrait (iPad) get the compact icon sidebar so content has room.
  const tablet = useMediaQuery("(min-width: 768px) and (max-width: 1023px)");
  const [tabletOpen, setTabletOpen] = useState(false);
  const collapsed = tablet ? !tabletOpen : collapsedPref;
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
      if (Date.now() - new Date(ev.data?.created_date || 0).getTime() > 600000) return; // an older message sliding into the list
      toast(`${ev.data.user_display_name || "Someone"}: ${messagePreview(ev.data, user?.email).slice(0, 80)}`, { icon: <MessageCircle className="w-5 h-5" />, description: ev.data.conversation_type === "group" ? ev.data.group_name : "Direct message" });
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
  useEffect(() => { document.title = pageTitle(location.pathname); }, [location.pathname]);

  const toggleCollapsed = () => (tablet ? setTabletOpen((v) => !v) : setCollapsed((c) => {
    try { localStorage.setItem("mimilocks:__sidebar", c ? "expanded" : "collapsed"); } catch { /* ignore */ }
    return !c;
  }));

  if (user && !user.onboarding_completed) return <Navigate to="/Onboarding" replace />;

  const fullHeight = FULL_HEIGHT.includes(location.pathname.toLowerCase());
  const path = location.pathname.toLowerCase();
  // Inside a server or an open conversation the tab bar steps aside (like iMessage).
  const inConversation = path === "/directmessages" && /[?&](with|c)=/.test(location.search);
  const hideMobileNav = path === "/communitychat" || inConversation;

  return (
    <div className="app-shell flex h-[100dvh] overflow-hidden safe-top safe-x">
      <Sidebar collapsed={collapsed} onToggleCollapsed={toggleCollapsed} badges={badges} onToggleTheme={toggleTheme} isDark={isDark} />
      <div className="flex-1 min-w-0 flex flex-col relative">
        <OfflineBar />
        <InstallBanner />
        <AnnouncementBar config={siteConfig} />
        <VoiceDock />
        {!fullHeight && <TopBar onSearch={() => setPaletteOpen(true)} user={user} />}
        <main ref={mainRef} id="main" className={`flex-1 min-h-0 relative ${fullHeight ? `overflow-hidden ${hideMobileNav ? "" : "pb-[calc(72px+env(safe-area-inset-bottom))] md:pb-0"}` : "overflow-y-auto overflow-x-hidden scroll"}`}>
          {/* Enter-only transition keyed by route; no exit phase that could stall navigation. */}
          <div key={location.pathname} className={`page-enter ${fullHeight ? "h-full" : "min-h-full"}`}>
            <ErrorBoundary resetKey={location.pathname}>{outlet}</ErrorBoundary>
          </div>
        </main>
      </div>
      {!hideMobileNav && <MobileNav badges={badges} isAdmin={isAdmin} isDark={isDark} onToggleTheme={toggleTheme} />}
      <MiniPlayer raised={!hideMobileNav} />
      {user && <CallManager me={user} />}
      {user && <ReportHost />}
      <CommandPalette open={paletteOpen} onClose={() => setPaletteOpen(false)} isDark={isDark} onToggleTheme={toggleTheme} />
    </div>
  );
}
