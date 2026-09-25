import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { motion } from "framer-motion";
import { AlertTriangle, X } from "lucide-react";

const SIZES = { sm: "max-w-sm", md: "max-w-md", lg: "max-w-lg", xl: "max-w-2xl", "2xl": "max-w-4xl" };

// Keeps content mounted for `ms` after `open` turns false so it can animate out,
// then unmounts it on a timer (independent of any nested animations).
export function useDelayedUnmount(open, ms = 220) {
  const [mounted, setMounted] = useState(open);
  useEffect(() => {
    if (open) { setMounted(true); return undefined; }
    const t = setTimeout(() => setMounted(false), ms);
    return () => clearTimeout(t);
  }, [open, ms]);
  return mounted || open;
}

// Accessible animated modal rendered in a portal. Closes on Escape / backdrop.
export default function Modal({ open, onClose, title, subtitle, children, footer, size = "md", padded = true, hideHeader = false, className = "" }) {
  const panelRef = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => { if (e.key === "Escape") onClose?.(); };
    document.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const t = setTimeout(() => panelRef.current?.querySelector("input,textarea,select,[autofocus]")?.focus(), 60);
    return () => { document.removeEventListener("keydown", onKey); document.body.style.overflow = prev; clearTimeout(t); };
  }, [open, onClose]);

  const mounted = useDelayedUnmount(open);
  if (!mounted) return null;
  return createPortal(
    <motion.div
      className="fixed inset-0 z-[120] flex items-end sm:items-center justify-center sm:p-4"
      initial={{ opacity: 0 }}
      animate={{ opacity: open ? 1 : 0 }}
      transition={{ duration: 0.18 }}
      style={{ pointerEvents: open ? "auto" : "none" }}
    >
      <div className="absolute inset-0 backdrop-blur-sm" style={{ background: "rgb(20 8 14 / 0.45)" }} onClick={onClose} />
      <motion.div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={typeof title === "string" ? title : undefined}
        initial={{ opacity: 0, y: 40, scale: 0.97 }}
        animate={open ? { opacity: 1, y: 0, scale: 1 } : { opacity: 0, y: 30, scale: 0.97, transition: { duration: 0.15 } }}
        transition={{ type: "spring", stiffness: 380, damping: 32 }}
        className={`relative w-full ${SIZES[size] || size} max-h-[92dvh] sm:max-h-[88vh] flex flex-col overflow-hidden rounded-t-[1.75rem] sm:rounded-[1.75rem] ${className}`}
        style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}
      >
        {!hideHeader && (title || subtitle) && (
          <div className="flex items-start gap-3 px-5 sm:px-6 pt-5 pb-3 flex-shrink-0">
            <div className="flex-1 min-w-0">
              <h2 className="font-display text-xl font-semibold truncate" style={{ color: "var(--text-primary)" }}>{title}</h2>
              {subtitle && <p className="text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>{subtitle}</p>}
            </div>
            <button onClick={onClose} className="icon-btn -mr-2 -mt-1" aria-label="Close"><X className="w-4 h-4" /></button>
          </div>
        )}
        {hideHeader && (
          <button onClick={onClose} className="icon-btn glass absolute top-3 right-3 z-10" aria-label="Close" style={{ border: "1px solid var(--border-c)" }}><X className="w-4 h-4" /></button>
        )}
        <div className={`flex-1 overflow-y-auto scroll ${padded ? "px-5 sm:px-6 pb-5" : ""}`}>{children}</div>
        {footer && <div className="flex items-center justify-end gap-2 px-5 sm:px-6 py-4 border-t flex-shrink-0" style={{ borderColor: "var(--border-c)" }}>{footer}</div>}
      </motion.div>
    </motion.div>,
    document.body,
  );
}

// ---------- confirm() replacement ----------
const ConfirmContext = createContext(null);

export function ConfirmProvider({ children }) {
  const [state, setState] = useState(null);
  const confirm = useCallback((opts) => new Promise((resolve) => {
    setState({ title: "Are you sure?", confirmLabel: "Confirm", danger: false, ...(typeof opts === "string" ? { message: opts } : opts), resolve });
  }), []);
  const close = (result) => { state?.resolve(result); setState(null); };
  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      <Modal open={!!state} onClose={() => close(false)} size="sm" hideHeader>
        {state && (
          <div className="pt-7 text-center">
            <motion.div initial={{ scale: 0.6, rotate: -8 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: "spring", stiffness: 400, damping: 16 }} className="w-14 h-14 rounded-2xl mx-auto mb-4 flex items-center justify-center" style={{ background: state.danger ? "rgb(224 82 107 / 0.12)" : "var(--pink-soft)", color: state.danger ? "var(--danger)" : "var(--accent-rose)" }}>
              <AlertTriangle className="w-6 h-6" />
            </motion.div>
            <h3 className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>{state.title}</h3>
            {state.message && <p className="text-sm mt-1.5" style={{ color: "var(--text-muted)" }}>{state.message}</p>}
            <div className="flex gap-2 mt-6">
              <button className="btn-outline flex-1" onClick={() => close(false)}>Cancel</button>
              <button className={`${state.danger ? "btn-danger" : "btn"} flex-1`} onClick={() => close(true)} autoFocus>{state.confirmLabel}</button>
            </div>
          </div>
        )}
      </Modal>
    </ConfirmContext.Provider>
  );
}

export function useConfirm() {
  const ctx = useContext(ConfirmContext);
  if (!ctx) throw new Error("useConfirm must be used within ConfirmProvider");
  return ctx;
}
