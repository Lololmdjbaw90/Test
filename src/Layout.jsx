import React, { useState, useEffect } from "react";
import { Link, useLocation } from "react-router-dom";
import { base44 } from "@/api/base44Client";
import { AnimatePresence, motion } from "framer-motion";
import { Grid2X2, Users, Music, UserCircle, Settings, Upload, ClipboardList, Store, UserCheck, Menu, X, Crown, MessageCircle, Shield } from "lucide-react";
import NotificationBell from "./components/notifications/NotificationBell";

const NAV = [
  { label: "Gallery", path: "/", icon: Grid2X2 },
  { label: "Community", path: "/Community", icon: Users },
  { label: "Music", path: "/Music", icon: Music },
  { label: "Friends", path: "/Friends", icon: UserCheck },
  { label: "Communities", path: "/Communities", icon: Users },
  { label: "Commissions", path: "/Commissions", icon: Store },
  { label: "Top Artists", path: "/TopArtists", icon: Crown },
  { label: "Messages", path: "/DirectMessages", icon: MessageCircle },
];
const ADMIN_NAV = [
  { label: "Upload", path: "/Upload", icon: Upload },
  { label: "Logs", path: "/Logs", icon: ClipboardList },
  { label: "Admin", path: "/Admin", icon: Shield },
];

function Avatar({ user, size = 8 }) {
  const [err, setErr] = useState(false);
  const cls = `w-${size} h-${size} rounded-full object-cover flex-shrink-0 bg-[var(--pink-soft)]`;
  if (user?.profile_picture && !err)
    return <img src={user.profile_picture} onError={() => setErr(true)} className={cls} alt="" />;
  return (
    <div className={`${cls} flex items-center justify-center text-sm font-semibold`} style={{ color: "var(--accent-rose)" }}>
      {user?.display_name?.[0]?.toUpperCase() || "?"}
    </div>
  );
}

export default function Layout({ children }) {
  const location = useLocation();
  const [user, setUser] = useState(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [isDark, setIsDark] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    base44.auth.me().then(u => {
      setUser(u); setIsAdmin(u?.role === "admin"); setIsDark(u?.theme === "dark");
      if (!u?.onboarding_completed && !location.pathname.includes("Onboarding")) window.location.href = "/Onboarding";
      base44.auth.updateMe({ last_seen: new Date().toISOString() }).catch(() => {});
    }).catch(() => {});
    const interval = setInterval(() => { base44.auth.updateMe({ last_seen: new Date().toISOString() }).catch(() => {}); }, 2 * 60 * 1000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => { setMobileOpen(false); }, [location.pathname]);

  const allNav = [...NAV, ...(isAdmin ? ADMIN_NAV : [])];
  const isChat = location.pathname.includes("CommunityChat");

  return (
    <div className={`app-shell ${isDark ? "dark" : ""}`} style={{ display: "flex", height: "100dvh", maxHeight: "100dvh", overflow: "hidden", background: "var(--app-bg)" }}>
      <aside className="hidden md:flex flex-col w-64 flex-shrink-0 h-full border-r shadow-sm" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
        <div className="h-16 flex items-center px-5 border-b flex-shrink-0" style={{ borderColor: "var(--border-c)" }}>
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-2xl flex items-center justify-center text-white text-sm font-bold shadow-sm" style={{ background: "linear-gradient(135deg, var(--accent-pink), var(--accent-rose))" }}>M</div>
            <span className="font-semibold text-sm" style={{ color: "var(--text-primary)" }}>Mimi Locks</span>
          </div>
        </div>
        <nav className="flex-1 overflow-y-auto py-3 px-3 space-y-0.5 scroll">
          {allNav.map(item => {
            const active = location.pathname === item.path || (item.path === "/" && location.pathname === "/Gallery");
            const Icon = item.icon;
            return (
              <Link key={item.path} to={item.path} className="flex items-center gap-3 px-3 py-2.5 rounded-2xl text-sm font-semibold transition-all"
                style={active ? { background: "var(--pink-soft)", color: "var(--accent-rose)", boxShadow: "inset 0 0 0 1px var(--border-c)" } : { color: "var(--text-secondary)" }}
                onMouseEnter={e => !active && (e.currentTarget.style.background = "var(--pink-soft)")}
                onMouseLeave={e => !active && (e.currentTarget.style.background = "transparent")}>
                <Icon className="w-4 h-4 flex-shrink-0" />{item.label}
              </Link>
            );
          })}
        </nav>
        {user && (<div className="px-3 py-2 border-t flex-shrink-0 flex items-center gap-2" style={{ borderColor: "var(--border-c)" }}><NotificationBell me={user} /><div className="flex-1" /></div>)}
        {user && (
          <div className="p-3 pb-3 flex-shrink-0">
            <Link to={`/Profile?email=${encodeURIComponent(user.email)}`} className="flex items-center gap-2.5 p-2 rounded-xl transition-all" style={{ color: "var(--text-primary)" }}
              onMouseEnter={e => e.currentTarget.style.background = "var(--pink-soft)"} onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
              <Avatar user={user} size={8} />
              <div className="flex-1 min-w-0">
                <p className="text-xs font-semibold truncate">{user.display_name || user.full_name}</p>
                <p className="text-[10px]" style={{ color: "var(--text-muted)" }}>{user.role}</p>
              </div>
              <Settings className="w-3.5 h-3.5 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
            </Link>
          </div>
        )}
      </aside>
      <div className="md:hidden fixed top-0 left-0 right-0 z-50 h-14 flex items-center justify-between px-4 border-b shadow-sm" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
        <button onClick={() => setMobileOpen(true)} className="w-9 h-9 rounded-xl flex items-center justify-center" style={{ background: "var(--pink-soft)" }}>
          <Menu className="w-4 h-4" style={{ color: "var(--accent-rose)" }} />
        </button>
        <span className="font-semibold text-sm" style={{ color: "var(--text-primary)" }}>Mimi Locks</span>
        <div className="flex items-center gap-2">
          {user && <NotificationBell me={user} />}
          {user ? <Link to={`/Profile?email=${encodeURIComponent(user.email)}`}><Avatar user={user} size={9} /></Link> : <div className="w-9" />}
        </div>
      </div>
      <AnimatePresence>
        {mobileOpen && (
          <>
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="md:hidden fixed inset-0 bg-black/30 z-40 backdrop-blur-sm" onClick={() => setMobileOpen(false)} />
            <motion.aside initial={{ x: "-100%" }} animate={{ x: 0 }} exit={{ x: "-100%" }} transition={{ type: "spring", damping: 30, stiffness: 300 }}
              className="md:hidden fixed left-0 top-0 bottom-0 w-64 z-50 flex flex-col border-r" style={{ background: "var(--surface)", borderColor: "var(--border-c)" }}>
              <div className="h-14 px-4 flex items-center justify-between border-b flex-shrink-0" style={{ borderColor: "var(--border-c)" }}>
                <span className="font-semibold text-sm" style={{ color: "var(--text-primary)" }}>Menu</span>
                <button onClick={() => setMobileOpen(false)} className="w-8 h-8 rounded-full flex items-center justify-center" style={{ background: "var(--pink-soft)" }}>
                  <X className="w-4 h-4" style={{ color: "var(--accent-rose)" }} />
                </button>
              </div>
              <nav className="flex-1 overflow-y-auto py-3 px-3 space-y-0.5 scroll">
                {allNav.map(item => {
                  const active = location.pathname === item.path || (item.path === "/" && location.pathname === "/Gallery");
                  const Icon = item.icon;
                  return (
                    <Link key={item.path} to={item.path} className="flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium transition-all"
                      style={active ? { background: "var(--pink-soft)", color: "var(--accent-rose)", boxShadow: "inset 0 0 0 1px var(--border-c)" } : { color: "var(--text-secondary)" }}>
                      <Icon className="w-4 h-4 flex-shrink-0" />{item.label}
                    </Link>
                  );
                })}
                {user && (<>
                  <div className="divider my-2" />
                  <Link to={`/Profile?email=${encodeURIComponent(user.email)}`} className="flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium" style={{ color: "var(--text-secondary)" }}><UserCircle className="w-4 h-4" /> Profile</Link>
                  <Link to="/Settings" className="flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium" style={{ color: "var(--text-secondary)" }}><Settings className="w-4 h-4" /> Settings</Link>
                </>)}
              </nav>
            </motion.aside>
          </>
        )}
      </AnimatePresence>
      <main className="flex-1 min-w-0 flex flex-col overflow-hidden" style={{ minHeight: 0 }}>
        <div className="md:hidden h-14 flex-shrink-0" />
        <div className={`flex-1 overflow-hidden ${isChat ? "flex flex-col" : "overflow-y-auto scroll"}`} style={{ background: "var(--app-bg)", minHeight: 0 }}>
          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.18, ease: "easeOut" }}
              className={isChat ? "flex flex-col overflow-hidden" : "min-h-full"}
              style={isChat ? { flex: 1, minHeight: 0 } : {}}
            >{children}</motion.div>
          </AnimatePresence>
        </div>
        {!isChat && (
          <nav className="md:hidden flex-shrink-0 flex items-center justify-around px-2 border-t"
            style={{ background: "var(--surface)", borderColor: "var(--border-c)", height: "calc(56px + env(safe-area-inset-bottom, 0px))", paddingBottom: "max(env(safe-area-inset-bottom, 0px), 4px)" }}>
            {NAV.slice(0, 5).map(item => {
              const active = location.pathname === item.path || (item.path === "/" && location.pathname === "/Gallery");
              const Icon = item.icon;
              return (
                <Link key={item.path} to={item.path} className="flex flex-col items-center justify-center gap-0.5 min-h-[44px] min-w-[44px] px-2">
                  <Icon className="w-5 h-5" style={{ color: active ? "var(--accent-rose)" : "var(--text-muted)" }} />
                  <span className="text-[9px] font-medium" style={{ color: active ? "var(--accent-rose)" : "var(--text-muted)" }}>{item.label.split(" ")[0]}</span>
                </Link>
              );
            })}
          </nav>
        )}
      </main>
    </div>
  );
}