import React, { useEffect } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion, useDragControls } from "framer-motion";
import { X } from "lucide-react";

// TikTok-style sheet: slides up from the bottom, drag the handle (or the
// header) down to close, tap outside to close.
export default function BottomSheet({ open, onClose, title, children, height = "72dvh", dark = false, label }) {
  const drag = useDragControls();
  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);
  const bg = dark ? "#161014" : "var(--surface)";
  const fg = dark ? "#fff" : "var(--text-primary)";
  return createPortal(
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-[130]" role="dialog" aria-modal="true" aria-label={label || title}>
          <motion.div className="absolute inset-0" style={{ background: "rgb(0 0 0 / 0.45)" }} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose} />
          <motion.div
            className="absolute inset-x-0 bottom-0 mx-auto w-full max-w-lg flex flex-col rounded-t-[1.6rem] overflow-hidden"
            style={{ height, maxHeight: "88dvh", background: bg, color: fg, boxShadow: "0 -10px 40px rgb(0 0 0 / 0.25)", paddingBottom: "env(safe-area-inset-bottom)" }}
            initial={{ y: "100%" }} animate={{ y: 0 }} exit={{ y: "100%" }}
            transition={{ type: "spring", damping: 32, stiffness: 340 }}
            drag="y" dragControls={drag} dragListener={false}
            dragConstraints={{ top: 0, bottom: 0 }} dragElastic={{ top: 0, bottom: 0.9 }}
            onDragEnd={(_, info) => { if (info.offset.y > 110 || info.velocity.y > 600) onClose(); }}
          >
            <div className="flex-shrink-0 pt-2 pb-2 px-4 cursor-grab active:cursor-grabbing select-none" style={{ touchAction: "none" }} onPointerDown={(e) => drag.start(e)}>
              <div className="mx-auto w-10 h-1.5 rounded-full mb-2" style={{ background: dark ? "rgb(255 255 255 / 0.25)" : "var(--border-c)" }} />
              <div className="relative flex items-center justify-center min-h-[28px]">
                <p className="text-sm font-bold">{title}</p>
                <button onClick={onClose} onPointerDown={(e) => e.stopPropagation()} className="absolute right-0 w-8 h-8 rounded-full flex items-center justify-center" aria-label="Close"><X className="w-5 h-5" /></button>
              </div>
            </div>
            <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 pb-4">{children}</div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>,
    document.body,
  );
}
