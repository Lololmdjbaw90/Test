import React, { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Bell, Check, Loader2 } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { toast } from "@/lib/toast";
import { displayName } from "@/lib/format";
import { notify } from "@/utils/notifications";
import Modal from "@/components/common/Modal";

// "Ping the artist" — a friendly nudge that shows up in their pings inbox.
export default function PingButton({ artwork, variant = "pill" }) {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const artist = artwork.user_email || artwork.created_by;
  if (!user || !artist || user.email === artist) return null;

  const send = async () => {
    setSending(true);
    try {
      await base44.entities.ArtworkPing.create({ artwork_id: artwork.id, artwork_title: artwork.title, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture || "", to_email: artist, message: message.trim() || null });
      await notify({ to_email: artist, from_email: user.email, from_display_name: displayName(user), from_profile_picture: user.profile_picture, type: "ping", message: `${displayName(user)} pinged you about "${artwork.title}"`, link: `/Gallery?art=${artwork.id}`, entity_id: artwork.id });
      setSent(true);
      setMessage("");
      setTimeout(() => { setSent(false); setOpen(false); }, 1500);
    } catch (e) {
      toast.error(e?.message || "Could not send ping.");
    }
    setSending(false);
  };

  return (
    <>
      <button
        onClick={(e) => { e.stopPropagation(); setOpen(true); }}
        className={variant === "overlay" ? "w-8 h-8 rounded-full flex items-center justify-center" : "chip"}
        style={variant === "overlay" ? { background: "rgb(255 255 255 / 0.92)", color: "#5b4450" } : undefined}
        title="Ping the artist"
        aria-label="Ping the artist"
      >
        <Bell className="w-4 h-4" />{variant !== "overlay" && "Ping artist"}
      </button>
      <Modal open={open} onClose={() => setOpen(false)} title="Ping the artist" subtitle={`About "${artwork.title}"`} size="sm">
        <AnimatePresence mode="wait">
          {sent ? (
            <motion.div key="sent" initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} className="flex flex-col items-center py-8 gap-3">
              <motion.div initial={{ scale: 0 }} animate={{ scale: 1 }} transition={{ type: "spring", stiffness: 400, damping: 12 }} className="w-14 h-14 rounded-full flex items-center justify-center text-white" style={{ background: "var(--accent-grad)" }}><Check className="w-7 h-7" /></motion.div>
              <p className="font-semibold" style={{ color: "var(--text-primary)" }}>Ping sent!</p>
            </motion.div>
          ) : (
            <motion.div key="form" className="space-y-3">
              <textarea className="input resize-none" rows={3} placeholder="Say something nice (optional)…" value={message} onChange={(e) => setMessage(e.target.value)} maxLength={280} />
              <div className="flex gap-2">
                <button className="btn-outline flex-1" onClick={() => setOpen(false)}>Cancel</button>
                <button className="btn flex-1" disabled={sending} onClick={send}>{sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Bell className="w-4 h-4" /> Send ping</>}</button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </Modal>
    </>
  );
}
