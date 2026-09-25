import React from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { ImagePlus, Music, Server, Store, Upload } from "lucide-react";

export const CREATE_ACTIONS = [
  { label: "Share artwork", desc: "Post to the community feed", icon: ImagePlus, to: "/Community?compose=1" },
  { label: "Share a track", desc: "Upload music for everyone", icon: Music, to: "/Music?upload=1" },
  { label: "Start a server", desc: "Channels, roles & voice", icon: Server, to: "/Communities?create=1" },
  { label: "List a commission", desc: "Open your art for hire", icon: Store, to: "/Commissions?create=1" },
];

export default function CreateMenu({ onDone, isAdmin, className = "" }) {
  const navigate = useNavigate();
  const actions = isAdmin ? [...CREATE_ACTIONS, { label: "Upload to gallery", desc: "Curated gallery (admin)", icon: Upload, to: "/Upload" }] : CREATE_ACTIONS;
  return (
    <motion.div
      initial={{ opacity: 0, y: 8, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: 8, scale: 0.96 }}
      transition={{ type: "spring", stiffness: 420, damping: 30 }}
      className={`glass rounded-3xl p-2 w-72 ${className}`}
      style={{ border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}
    >
      {actions.map((a, i) => (
        <motion.button
          key={a.to}
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.035 }}
          onClick={() => { navigate(a.to); onDone?.(); }}
          className="w-full flex items-center gap-3 p-2.5 rounded-2xl text-left transition-colors hover:bg-[var(--pink-soft)]"
        >
          <span className="w-10 h-10 rounded-xl flex items-center justify-center text-white flex-shrink-0" style={{ background: "var(--accent-grad)" }}><a.icon className="w-4 h-4" /></span>
          <span className="min-w-0">
            <span className="block text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{a.label}</span>
            <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{a.desc}</span>
          </span>
        </motion.button>
      ))}
    </motion.div>
  );
}
