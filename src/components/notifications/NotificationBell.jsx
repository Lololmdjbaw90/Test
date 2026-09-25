import React, { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { AtSign, Bell, CheckCheck, Heart, MessageCircle, Trash2, UserCheck, UserPlus } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toast } from "@/lib/toast";
import { timeAgo } from "@/lib/format";
import Avatar from "@/components/common/Avatar";

const TYPE_ICONS = { follow: UserPlus, like: Heart, comment: MessageCircle, friend_request: UserPlus, friend_accepted: UserCheck, mention: AtSign, dm: MessageCircle, ping: Bell };
const TYPE_COLORS = { follow: "#7c5cf0", like: "#e0526b", comment: "#7c5cf0", friend_request: "#f0a020", friend_accepted: "#17a673", mention: "var(--accent-rose)", dm: "#2f80e0", ping: "var(--accent-rose)" };

export default function NotificationBell({ me }) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  const { data: notifications, setData } = useLiveQuery("Notification", me?.email ? { to_email: me.email } : null, {
    sort: "-created_date",
    limit: 50,
    enabled: !!me?.email,
    onEvent: (ev) => { if (ev.type === "create" && ev.data?.message) toast(ev.data.message, { icon: <Bell className="w-5 h-5" /> }); },
  });

  useEffect(() => {
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);

  const unread = notifications.filter((n) => !n.is_read).length;
  const markAllRead = async () => {
    const pending = notifications.filter((n) => !n.is_read);
    setData((p) => p.map((n) => ({ ...n, is_read: true })));
    await Promise.all(pending.map((n) => base44.entities.Notification.update(n.id, { is_read: true }).catch(() => {})));
  };
  const openItem = (n) => {
    if (!n.is_read) { base44.entities.Notification.update(n.id, { is_read: true }).catch(() => {}); setData((p) => p.map((x) => (x.id === n.id ? { ...x, is_read: true } : x))); }
    setOpen(false);
    if (n.link) navigate(n.link);
  };
  const del = async (id, e) => {
    e.stopPropagation();
    setData((p) => p.filter((n) => n.id !== id));
    await base44.entities.Notification.delete(id).catch(() => {});
  };
  const clearAll = async () => {
    const all = notifications;
    setData([]);
    await Promise.all(all.map((n) => base44.entities.Notification.delete(n.id).catch(() => {})));
  };

  return (
    <div ref={ref} className="relative">
      <button onClick={() => setOpen((v) => !v)} className="icon-btn icon-btn-bordered relative" data-active={open} aria-label={`Notifications${unread ? ` (${unread} unread)` : ""}`}>
        <motion.span animate={unread ? { rotate: [0, -14, 12, -8, 6, 0] } : {}} transition={{ duration: 0.8, repeat: unread ? Infinity : 0, repeatDelay: 4 }} className="inline-flex"><Bell className="w-[18px] h-[18px]" /></motion.span>
        <AnimatePresence>
          {unread > 0 && (
            <motion.span initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }} className="absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-bold text-white flex items-center justify-center" style={{ background: "var(--accent-rose)", border: "2px solid var(--surface)" }}>
              {unread > 9 ? "9+" : unread}
            </motion.span>
          )}
        </AnimatePresence>
      </button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.97 }}
            transition={{ type: "spring", stiffness: 420, damping: 32 }}
            className="fixed sm:absolute left-3 right-3 sm:left-auto sm:right-0 top-16 sm:top-[calc(100%+10px)] z-[100] sm:w-[380px] max-h-[70vh] flex flex-col rounded-3xl overflow-hidden"
            style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)", transformOrigin: "top right" }}
          >
            <div className="flex items-center gap-2 px-5 py-4 border-b" style={{ borderColor: "var(--border-c)" }}>
              <span className="font-display text-lg font-semibold flex-1" style={{ color: "var(--text-primary)" }}>Notifications</span>
              {unread > 0 && <button onClick={markAllRead} className="chip-sm"><CheckCheck className="w-3 h-3" /> Mark read</button>}
              {notifications.length > 0 && <button onClick={clearAll} className="text-xs font-semibold px-2 py-1 rounded-lg hover:bg-[var(--pink-soft)]" style={{ color: "var(--text-muted)" }}>Clear</button>}
            </div>
            <div className="flex-1 overflow-y-auto scroll">
              {notifications.length === 0 ? (
                <div className="py-14 text-center px-6">
                  <Bell className="w-8 h-8 mx-auto mb-3" style={{ color: "var(--border-strong)" }} />
                  <p className="text-sm font-semibold" style={{ color: "var(--text-secondary)" }}>You're all caught up</p>
                  <p className="text-xs mt-1" style={{ color: "var(--text-muted)" }}>Likes, comments and friend requests show up here.</p>
                </div>
              ) : (
                <AnimatePresence initial={false}>
                  {notifications.map((n) => {
                    const Icon = TYPE_ICONS[n.type] || Bell;
                    const color = TYPE_COLORS[n.type] || "var(--accent-rose)";
                    return (
                      <motion.div
                        key={n.id}
                        layout
                        initial={{ opacity: 0, x: -10 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: 30, height: 0 }}
                        onClick={() => openItem(n)}
                        className="group flex items-start gap-3 px-5 py-3.5 cursor-pointer transition-colors hover:bg-[var(--surface-2)]"
                        style={{ background: n.is_read ? "transparent" : "var(--pink-soft)" }}
                      >
                        <span className="relative flex-shrink-0">
                          <Avatar src={n.from_profile_picture} name={n.from_display_name} size={38} />
                          <span className="absolute -bottom-1 -right-1 w-5 h-5 rounded-full flex items-center justify-center" style={{ background: color, border: "2px solid var(--surface)" }}><Icon className="w-2.5 h-2.5 text-white" /></span>
                        </span>
                        <span className="flex-1 min-w-0">
                          <span className="block text-sm leading-snug" style={{ color: "var(--text-primary)" }}>{n.message}</span>
                          <span className="block text-[11px] mt-0.5" style={{ color: "var(--text-muted)" }}>{timeAgo(n.created_date)}</span>
                        </span>
                        {!n.is_read && <span className="w-2 h-2 rounded-full mt-1.5 flex-shrink-0" style={{ background: "var(--accent-rose)" }} />}
                        <button onClick={(e) => del(n.id, e)} className="icon-btn w-7 h-7 opacity-0 group-hover:opacity-100 focus:opacity-100" aria-label="Delete notification"><Trash2 className="w-3.5 h-3.5" style={{ color: "var(--danger)" }} /></button>
                      </motion.div>
                    );
                  })}
                </AnimatePresence>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
