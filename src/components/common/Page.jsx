import React from "react";
import { motion } from "framer-motion";
import { Loader2 } from "lucide-react";
import { fadeUp, stagger } from "@/lib/motion";

// Standard page container + header used by every content page.
export function Page({ children, className = "", width = "max-w-6xl" }) {
  return <div className={`${width} mx-auto w-full px-4 sm:px-6 lg:px-8 pt-5 sm:pt-8 pb-28 md:pb-12 ${className}`}>{children}</div>;
}

export function PageHeader({ eyebrow, title, subtitle, icon: Icon, actions, children }) {
  return (
    <motion.header variants={stagger(0, 0.06)} initial="hidden" animate="show" className="mb-6 sm:mb-8">
      <div className="flex flex-wrap items-end gap-4">
        <div className="flex items-center gap-3.5 flex-1 min-w-[220px]">
          {Icon && (
            <motion.div variants={fadeUp} className="w-12 h-12 rounded-2xl flex items-center justify-center flex-shrink-0 text-white" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }}>
              <Icon className="w-5 h-5" />
            </motion.div>
          )}
          <div className="min-w-0">
            {eyebrow && <motion.p variants={fadeUp} className="eyebrow mb-1">{eyebrow}</motion.p>}
            <motion.h1 variants={fadeUp} className="font-display text-3xl sm:text-4xl font-semibold leading-tight" style={{ color: "var(--text-primary)" }}>{title}</motion.h1>
            {subtitle && <motion.p variants={fadeUp} className="text-sm mt-1" style={{ color: "var(--text-muted)" }}>{subtitle}</motion.p>}
          </div>
        </div>
        {actions && <motion.div variants={fadeUp} className="flex items-center gap-2 flex-wrap">{actions}</motion.div>}
      </div>
      {children && <motion.div variants={fadeUp} className="mt-5">{children}</motion.div>}
    </motion.header>
  );
}

export function EmptyState({ icon: Icon, title, text, action, className = "" }) {
  return (
    <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} className={`flex flex-col items-center justify-center text-center py-16 px-6 gap-3 ${className}`}>
      {Icon && (
        <motion.div
          animate={{ y: [0, -6, 0] }}
          transition={{ duration: 3.2, repeat: Infinity, ease: "easeInOut" }}
          className="w-16 h-16 rounded-3xl flex items-center justify-center mb-1"
          style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}
        >
          <Icon className="w-7 h-7" />
        </motion.div>
      )}
      <p className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>{title}</p>
      {text && <p className="text-sm max-w-sm" style={{ color: "var(--text-muted)" }}>{text}</p>}
      {action && <div className="mt-2">{action}</div>}
    </motion.div>
  );
}

export function Spinner({ className = "w-5 h-5" }) {
  return <Loader2 className={`${className} animate-spin`} style={{ color: "var(--accent-rose)" }} />;
}

export function CenterSpinner() {
  return <div className="flex items-center justify-center py-24"><Spinner className="w-6 h-6" /></div>;
}
