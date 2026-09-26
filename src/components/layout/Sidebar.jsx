import React, { useRef, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronsLeft, ChevronsRight, LogOut, Moon, Plus, Settings, Sun } from "lucide-react";
import Avatar from "@/components/common/Avatar";
import CreateMenu from "./CreateMenu";
import Popover from "@/components/common/Popover";
import { ADMIN_SECTION, NAV_SECTIONS, isActivePath } from "./nav";
import { useAuth } from "@/lib/AuthContext";
import { displayName, profileLink } from "@/lib/format";
import { getLevelInfo } from "@/components/profile/LevelBadge";
import { BrandLogo, BrandMark } from "@/components/common/Brand";

export function Logo({ collapsed, bar }) {
  return (
    <Link to="/" className="flex items-center group" aria-label="Sugerly home">
      {bar ? (
        <BrandLogo height={40} />
      ) : collapsed ? (
        <BrandMark size={44} className="transition-transform duration-300 can-hover:group-hover:-rotate-6" />
      ) : (
        <BrandLogo height={52} className="-ml-1.5 transition-transform duration-300 can-hover:group-hover:-rotate-2" />
      )}
    </Link>
  );
}

function NavItem({ item, active, collapsed, badge }) {
  const Icon = item.icon;
  return (
    <Link
      to={item.path}
      title={collapsed ? item.label : undefined}
      className={`relative flex items-center gap-3 rounded-2xl text-sm font-semibold transition-colors ${collapsed ? "justify-center h-11 w-11 mx-auto" : "px-3 h-11"}`}
      style={{ color: active ? "var(--accent-rose)" : "var(--text-secondary)" }}
    >
      {active && <span className="absolute inset-0 rounded-2xl enter-fade" style={{ background: "var(--pink-soft)", boxShadow: "inset 0 0 0 1px rgb(var(--accent-rgb) / 0.18)" }} />}
      {!active && <span className="absolute inset-0 rounded-2xl opacity-0 hover:opacity-100 transition-opacity" style={{ background: "var(--surface-2)" }} />}
      <Icon className="relative w-[18px] h-[18px] flex-shrink-0" />
      {!collapsed && <span className="relative flex-1 truncate">{item.label}</span>}
      {badge > 0 && (
        <motion.span initial={{ scale: 0 }} animate={{ scale: 1 }} className={`relative text-[10px] font-bold text-white rounded-full flex items-center justify-center ${collapsed ? "absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1" : "min-w-[20px] h-5 px-1.5"}`} style={{ background: "var(--accent-rose)", ...(collapsed ? { position: "absolute" } : {}) }}>
          {badge > 99 ? "99+" : badge}
        </motion.span>
      )}
    </Link>
  );
}

export default function Sidebar({ collapsed, onToggleCollapsed, badges = {}, onToggleTheme, isDark }) {
  const { user, isAdmin, logout } = useAuth();
  const location = useLocation();
  const [createOpen, setCreateOpen] = useState(false);
  const createRef = useRef(null);
  const sections = isAdmin ? [...NAV_SECTIONS, ADMIN_SECTION] : NAV_SECTIONS;
  const level = getLevelInfo(user?.xp || 0);

  return (
    <motion.aside
      animate={{ width: collapsed ? 84 : 264 }}
      transition={{ type: "spring", stiffness: 320, damping: 34 }}
      className="hidden md:flex flex-col h-full flex-shrink-0 relative z-30 glass"
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

      <nav className="flex-1 overflow-y-auto no-scrollbar px-3 py-2 space-y-5">
        {sections.map((section) => (
          <div key={section.label}>
            {!collapsed ? <p className="eyebrow px-3 mb-1.5">{section.label}</p> : <div className="divider mx-3 mb-2 opacity-60" />}
            <div className="space-y-0.5">
              {section.items.map((item) => (
                <NavItem key={item.path} item={item} active={isActivePath(location.pathname, item.path)} collapsed={collapsed} badge={item.badge ? badges[item.badge] : 0} />
              ))}
            </div>
          </div>
        ))}
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
