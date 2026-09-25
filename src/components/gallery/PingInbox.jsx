import React, { useState } from "react";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { BellRing, Trash2, X } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { timeAgo } from "@/lib/format";
import Avatar from "@/components/common/Avatar";

export default function PingInbox() {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const { data: pings, setData } = useLiveQuery("ArtworkPing", user ? { to_email: user.email } : null, { sort: "-created_date", limit: 30, enabled: !!user });
  if (!user) return null;
  const del = async (id) => { setData((p) => p.filter((x) => x.id !== id)); await base44.entities.ArtworkPing.delete(id).catch(() => {}); };

  return (
    <div className="relative">
      <button onClick={() => setOpen((o) => !o)} className="btn-outline relative" aria-expanded={open}>
        <BellRing className="w-4 h-4" /> Pings
        {pings.length > 0 && <span className="min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-bold text-white flex items-center justify-center" style={{ background: "var(--accent-rose)" }}>{pings.length > 9 ? "9+" : pings.length}</span>}
      </button>
      <AnimatePresence>
        {open && (
          <>
            <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} />
            <motion.div initial={{ opacity: 0, y: 8, scale: 0.97 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: 8 }} className="absolute right-0 top-12 z-40 w-80 rounded-3xl overflow-hidden" style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}>
              <div className="px-4 py-3 border-b flex items-center justify-between" style={{ borderColor: "var(--border-c)" }}>
                <span className="font-display font-semibold" style={{ color: "var(--text-primary)" }}>Pings</span>
                <button onClick={() => setOpen(false)} className="icon-btn w-7 h-7" aria-label="Close"><X className="w-4 h-4" /></button>
              </div>
              <div className="max-h-72 overflow-y-auto scroll">
                {pings.length === 0 ? (
                  <div className="text-center py-10 px-4">
                    <BellRing className="w-6 h-6 mx-auto mb-2" style={{ color: "var(--text-muted)" }} />
                    <p className="text-sm" style={{ color: "var(--text-muted)" }}>No pings yet</p>
                  </div>
                ) : pings.map((ping) => (
                  <div key={ping.id} className="flex items-start gap-3 px-4 py-3 group border-b last:border-0" style={{ borderColor: "var(--border-c)" }}>
                    <Avatar src={ping.from_profile_picture} name={ping.from_display_name} size={32} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm" style={{ color: "var(--text-primary)" }}><strong>{ping.from_display_name}</strong> pinged you{ping.artwork_title ? <> about <Link className="font-semibold hover:underline" style={{ color: "var(--accent-rose)" }} to={`/Gallery?art=${ping.artwork_id}`} onClick={() => setOpen(false)}>{ping.artwork_title}</Link></> : ""}</p>
                      {ping.message && <p className="text-xs mt-1 italic" style={{ color: "var(--text-secondary)" }}>“{ping.message}”</p>}
                      <p className="text-[10px] mt-1" style={{ color: "var(--text-muted)" }}>{timeAgo(ping.created_date)}</p>
                    </div>
                    <button onClick={() => del(ping.id)} className="icon-btn w-7 h-7 opacity-0 group-hover:opacity-100 focus:opacity-100" aria-label="Delete ping"><Trash2 className="w-3.5 h-3.5" style={{ color: "var(--danger)" }} /></button>
                  </div>
                ))}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
