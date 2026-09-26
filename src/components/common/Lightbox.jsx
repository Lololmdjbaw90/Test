import React, { useEffect } from "react";
import { createPortal } from "react-dom";
import { motion } from "framer-motion";
import { X } from "lucide-react";

// Tap-to-open full-screen view of an image (pinch to zoom on phones).
// Render inside <AnimatePresence> for the fade.
export default function Lightbox({ src, alt = "", onClose }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === "Escape") { e.stopImmediatePropagation(); onClose(); } };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onClose]);
  return createPortal(
    <motion.div
      className="fixed inset-0 z-[140] flex items-center justify-center safe-top safe-x"
      style={{ background: "rgb(8 4 6 / 0.96)", touchAction: "pinch-zoom" }}
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}
      onClick={onClose}
      role="dialog" aria-modal="true" aria-label={alt || "Full screen image"}
    >
      <img src={src} alt={alt} className="max-w-full max-h-full object-contain select-none" draggable={false} />
      <button onClick={onClose} className="absolute top-[calc(env(safe-area-inset-top)+0.75rem)] right-3 w-11 h-11 rounded-full flex items-center justify-center text-white" style={{ background: "rgb(255 255 255 / 0.14)" }} aria-label="Close full screen"><X className="w-5 h-5" /></button>
    </motion.div>,
    document.body,
  );
}
