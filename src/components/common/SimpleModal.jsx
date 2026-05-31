import React, { useEffect } from "react";
import { motion } from "framer-motion";
import { X } from "lucide-react";

// Small reusable modal shell used by the reconstructed server modals.
// Closes on Escape and backdrop click; matches the app's CSS-variable theme.
// Animated entrance (backdrop fade + content pop) via framer-motion.
export default function SimpleModal({ title, onClose, children, footer, maxWidth = "max-w-md" }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === "Escape") onClose?.(); };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.16 }}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 backdrop-blur-sm"
      style={{ background: "rgba(0,0,0,0.4)" }}
      onClick={onClose}
    >
      <motion.div
        initial={{ opacity: 0, scale: 0.96, y: 10 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        transition={{ type: "spring", stiffness: 320, damping: 26 }}
        className={`w-full ${maxWidth} rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[85vh]`}
        style={{ background: "var(--surface)", border: "1px solid var(--border-c)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-5 h-14 border-b flex-shrink-0" style={{ borderColor: "var(--border-c)" }}>
          <h2 className="font-semibold text-sm truncate" style={{ color: "var(--text-primary)" }}>{title}</h2>
          <button onClick={onClose} className="p-1 rounded-lg transition-colors hover:bg-black/[0.04]"><X className="w-4 h-4" style={{ color: "var(--text-muted)" }} /></button>
        </div>
        <div className="overflow-y-auto flex-1">{children}</div>
        {footer && <div className="flex items-center justify-end gap-2 px-5 h-14 border-t flex-shrink-0" style={{ borderColor: "var(--border-c)" }}>{footer}</div>}
      </motion.div>
    </motion.div>
  );
}
