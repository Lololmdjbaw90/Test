import React, { useRef, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown, ChevronsLeft, ChevronsRight, LogOut, Moon, Plus, Settings, Sun } from "lucide-react";
import Avatar from "@/components/common/Avatar";
import CreateMenu from "./CreateMenu";
import Popover from "@/components/common/Popover";
import { ADMIN_SECTION, EXPLORE_NAV, MORE_NAV, PRIMARY_NAV, isActivePath } from "./nav";
import AppIcon from "./AppIcon";
import { useAuth } from "@/lib/AuthContext";
import { displayName, profileLink } from "@/lib/format";
import { getLevelInfo } from "@/components/profile/LevelBadge";
import { BrandLogo, BrandMark } from "@/components/common/Brand";

export function Logo({ collapsed, bar }) {
  return (
    <Link to="/" className="flex items-center group" aria-label="Sugerly home">
      {bar ? (
        <BrandLogo height={40} shine />
      ) : collapsed ? (
        <BrandMark size={44} className="transition-transform duration-300 can-hover:group-hover:-rotate-6" />
      ) : (
        <BrandLogo height={52} className="-ml-1.5 transition-transform duration-300 can-hover:group-hover:-rotate-2" />
      )}
    </Link>
  );
}

function Badge({ value, collapsed }) {
  if (!(value > 0)) return null;
  return (
    <motion.span initial={{ scale: 0 }} animate={{ scale: 1 }} className={`text-[10px] font-bold text-white rounded-full flex items-center justify-center ${collapsed ? "absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1" : "relative min-w-[20px] h-5 px-1.5"}`} style={{ background: "var(--accent-rose)", boxShadow: "0 0 0 2px var(--surface)" }}>
      {value > 99 ? "99+" : value}
    </motion.span>
  );
}

// Tier 1: the main places — big app-icon tiles.
function PrimaryItem({ item, active, collapsed, badge }) {
  return (
    <Link to={item.path} title={collapsed ? item.label : undefined} aria-current={active ? "page" : undefined}
      className={`relative flex items-center gap-3 rounded-[18px] transition-transform active:scale-[0.97] ${collapsed ? "justify-center h-14 w-14 mx-auto" : "px-2 h-14"}`}>
      {active && <motion.span layoutId="side-lens" className="absolute inset-0 rounded-[18px] glass-lens" transition={{ type: "spring", stiffness: 500, damping: 36 }} />}
      {!active && <span className="absolute inset-0 rounded-[18px] opacity-0 can-hover:hover:opacity-100 transition-opacity" style={{ background: "var(--surface-2)" }} />}
      <AppIcon icon={item.icon} tint={item.tint} size={40} className="relative" />
      {!collapsed && <span className="relative flex-1 truncate text-[15px] font-bold" style={{ color: active ? "var(--text-primary)" : "var(--text-secondary)" }}>{item.label}</span>}
      <Badge value={badge} collapsed={collapsed} />
    </Link>
  );
}

// Tier 2 / 3: explore and the rest — plain rows, smaller for tier 3.
function NavItem({ item, active, collapsed, badge, small = false }) {
  const Icon = item.icon;
  return (
    <Link
      to={item.path}
      title={collapsed ? item.label : undefined}
      aria-current={active ? "page" : undefined}
      className={`relative flex items-center gap-3 rounded-2xl font-semibold transition-colors ${small ? "text-[13px]" : "text-sm"} ${collapsed ? `justify-center ${small ? "h-9 w-9" : "h-11 w-11"} mx-auto` : `px-3 ${small ? "h-9" : "h-10"}`}`}
      style={{ color: active ? "var(--accent-rose)" : small ? "var(--text-muted)" : "var(--text-secondary)" }}
    >
      {active && <span className="absolute inset-0 rounded-2xl enter-fade" style={{ background: "var(--pink-soft)", boxShadow: "inset 0 0 0 1px rgb(var(--accent-rgb) / 0.18)" }} />}
      {!active && <span className="absolute inset-0 rounded-2xl opacity-0 can-hover:hover:opacity-100 transition-opacity" style={{ background: "var(--surface-2)" }} />}
      {item.tint && !small && !collapsed ? (
        <span className="relative w-7 h-7 rounded-[9px] flex items-center justify-center flex-shrink-0" style={{ background: `linear-gradient(150deg, ${item.tint[0]}33, ${item.tint[1]}40)`, color: item.tint[1] }}><Icon className="w-4 h-4" /></span>
      ) : <Icon className={`relative flex-shrink-0 ${small ? "w-4 h-4" : "w-[18px] h-[18px]"}`} />}
      {!collapsed && <span className="relative flex-1 truncate">{item.label}</span>}
      <Badge value={badge} collapsed={collapsed} />
    </Link>
  );
}

export default function Sidebar({ collapsed, onToggleCollapsed, badges = {}, onToggleTheme, isDark }) {
  const { user, isAdmin, logout } = useAuth();
  const location = useLocation();
  const [createOpen, setCreateOpen] = useState(false);
  const createRef = useRef(null);
  const more = isAdmin ? [...MORE_NAV, ...ADMIN_SECTION.items] : MORE_NAV;
  const moreActive = more.some((i) => isActivePath(location.pathname, i.path));
  const [moreOpen, setMoreOpen] = useState(() => { try { return localStorage.getItem("mimilocks:__side_more") !== "closed"; } catch { return true; } });
  const toggleMore = () => setMoreOpen((v) => { try { localStorage.setItem("mimilocks:__side_more", v ? "closed" : "open"); } catch { /* ignore */ } return !v; });
  const level = getLevelInfo(user?.xp || 0);

  return (
    <motion.aside
      animate={{ width: collapsed ? 84 : 264 }}
      transition={{ type: "spring", stiffness: 320, damping: 34 }}
      className="hidden desk:flex flex-col h-full flex-shrink-0 relative z-30 glass"
      style={{ borderRight: "1px solid var(--border-c)" }}
    >
      <div className={`h-[84px] flex items-center flex-shrink-0 ${collapsed ? "justify-center" : "px-5"}`}>
        <Logo collapsed={collapsed} />
      </div>

      <div className="relative px-4 pb-2">
        <button ref={createRef} onClick={() => setCreateOpen((v) => !v)} className={`btn w-full ${collapsed ? "px-0" : ""}`} title="Create" aria-expanded={createOpen}>
          <motion.span animate={{ rotate: createOpen ? 45 : 0 }} className="inline-flex"><Plus className="w-4 h-4" /></motion.span>
          {!collapsed && "Create"}
        </button>
        <Popover open={createOpen} onClose={() => setCreateOpen(false)} anchorRef={createRef} placement={collapsed ? "right-start" : "bottom-start"} width={290} label="Create">
          <CreateMenu isAdmin={isAdmin} onDone={() => setCreateOpen(false)} />
        </Popover>
      </div>

      <nav className="flex-1 overflow-y-auto no-scrollbar px-3 py-2 space-y-5" aria-label="Main">
        <div className="space-y-1">
          {PRIMARY_NAV.map((item) => <PrimaryItem key={item.path} item={item} active={isActivePath(location.pathname, item.path)} collapsed={collapsed} badge={item.badge ? badges[item.badge] : 0} />)}
        </div>
        <div>
          {!collapsed ? <p className="eyebrow px-3 mb-1.5">Explore</p> : <div className="divider mx-3 mb-2 opacity-60" />}
          <div className="space-y-0.5">
            {EXPLORE_NAV.map((item) => <NavItem key={item.path} item={item} active={isActivePath(location.pathname, item.path)} collapsed={collapsed} badge={item.badge ? badges[item.badge] : 0} />)}
          </div>
        </div>
        <div>
          {!collapsed ? (
            <button onClick={toggleMore} className="w-full flex items-center gap-1 eyebrow px-3 mb-1.5" aria-expanded={moreOpen || moreActive}>
              More <ChevronDown className={`w-3.5 h-3.5 transition-transform ${moreOpen || moreActive ? "" : "-rotate-90"}`} />
            </button>
          ) : <div className="divider mx-3 mb-2 opacity-60" />}
          {(moreOpen || moreActive || collapsed) && (
            <div className="space-y-0.5 enter-fade">
              {more.map((item) => <NavItem key={item.path} item={item} small active={isActivePath(location.pathname, item.path)} collapsed={collapsed} badge={item.badge ? badges[item.badge] : 0} />)}
            </div>
          )}
        </div>
      </nav>

      <div className="p-3 space-y-2 flex-shrink-0">
        <div className={`flex ${collapsed ? "flex-col items-center" : "items-center"} gap-1`}>
          <button onClick={onToggleTheme} className="icon-btn" title={isDark ? "Light mode" : "Dark mode"} aria-label="Toggle dark mode">
            <AnimatePresence mode="wait" initial={false}>
              <motion.span key={isDark ? "moon" : "sun"} initial={{ rotate: -90, opacity: 0 }} animate={{ rotate: 0, opacity: 1 }} exit={{ rotate: 90, opacity: 0 }} transition={{ duration: 0.2 }} className="inline-flex">
                {isDark ? <Moon className="w-4 h-4" /> : <Sun className="w-4 h-4" />}
              </motion.span>
            </AnimatePresence>
          </button>
          <Link to="/Settings" className="icon-btn" title="Settings" aria-label="Settings"><Settings className="w-4 h-4" /></Link>
          {!collapsed && <div className="flex-1" />}
          <button onClick={onToggleCollapsed} className="icon-btn" title={collapsed ? "Expand sidebar" : "Collapse sidebar"} aria-label="Toggle sidebar">
            {collapsed ? <ChevronsRight className="w-4 h-4" /> : <ChevronsLeft className="w-4 h-4" />}
          </button>
        </div>

        {user && (
          <div className={`card-sm flex items-center gap-2.5 ${collapsed ? "p-1.5 justify-center" : "p-2.5"}`}>
            <Link to={profileLink(user.email)} className="flex items-center gap-2.5 flex-1 min-w-0" title={collapsed ? displayName(user) : undefined}>
              <Avatar src={user.profile_picture} name={displayName(user)} size={collapsed ? 40 : 38} nitro={user.nitro_active} online />
              {!collapsed && (
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{displayName(user)}</span>
                  <span className="block text-[11px] font-semibold truncate" style={{ color: level.current.color }}>Lv.{level.current.level} · {level.current.title}</span>
                </span>
              )}
            </Link>
            {!collapsed && <button onClick={logout} className="icon-btn" title="Log out" aria-label="Log out"><LogOut className="w-4 h-4" /></button>}
          </div>
        )}
      </div>
    </motion.aside>
  );
}
