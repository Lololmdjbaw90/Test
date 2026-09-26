import React, { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { CheckCircle2, AlertCircle, Info, X } from "lucide-react";
import { useMediaQuery } from "@/lib/useMediaQuery";
import { feedback } from "@/lib/feedback";

// Tiny global toast system: call toast("Saved"), toast.success(...), toast.error(...)
// from anywhere; <Toaster /> (mounted once in App) renders them.
const subscribers = new Set();
let counter = 0;

function push(message, { type = "info", description, duration = 3200, icon } = {}) {
  const t = { id: ++counter, message, type, description, duration, icon };
  subscribers.forEach((fn) => fn(t));
  return t.id;
}

export const toast = Object.assign((message, opts) => push(message, opts), {
  success: (message, opts) => { feedback("success"); return push(message, { ...opts, type: "success" }); },
  error: (message, opts) => { feedback("error"); return push(message, { ...opts, type: "error", duration: 4500 }); },
  info: (message, opts) => push(message, { ...opts, type: "info" }),
});

const ICONS = { success: CheckCircle2, error: AlertCircle, info: Info };
const COLORS = { success: "var(--success)", error: "var(--danger)", info: "var(--accent-rose)" };

export function Toaster() {
  const top = useMediaQuery("(max-width: 767px)"); // phones: toasts drop in from the top
  const [items, setItems] = useState([]);
  useEffect(() => {
    const onToast = (t) => {
      setItems((prev) => [...prev.slice(-3), t]);
      setTimeout(() => setItems((prev) => prev.filter((x) => x.id !== t.id)), t.duration);
    };
    subscribers.add(onToast);
    return () => subscribers.delete(onToast);
  }, []);

  return (
    <div className="fixed z-[200] top-[calc(env(safe-area-inset-top)+0.75rem)] md:top-auto md:bottom-5 left-1/2 -translate-x-1/2 md:left-auto md:right-5 md:translate-x-0 flex flex-col gap-2 w-[min(92vw,380px)] pointer-events-none" aria-live="polite">
      <AnimatePresence initial={false}>
        {items.map((t) => {
          const Icon = ICONS[t.type] || Info;
          return (
            <motion.div
              key={t.id}
              layout
              initial={{ opacity: 0, y: top ? -24 : 24, scale: 0.94 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={top ? { opacity: 0, y: -16, scale: 0.96, transition: { duration: 0.18 } } : { opacity: 0, x: 40, scale: 0.96, transition: { duration: 0.18 } }}
              transition={{ type: "spring", stiffness: 420, damping: 30 }}
              className="pointer-events-auto glass flex items-start gap-3 rounded-2xl px-4 py-3"
              style={{ border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}
              role="status"
            >
              <span className="mt-0.5 flex-shrink-0" style={{ color: COLORS[t.type] }}>{t.icon || <Icon className="w-5 h-5" />}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{t.message}</p>
                {t.description && <p className="text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>{t.description}</p>}
              </div>
              <button onClick={() => setItems((prev) => prev.filter((x) => x.id !== t.id))} className="flex-shrink-0 opacity-60 hover:opacity-100" aria-label="Dismiss">
                <X className="w-4 h-4" style={{ color: "var(--text-muted)" }} />
              </button>
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>
  );
}
