import React from "react";
import { Link, useLocation } from "react-router-dom";
import { motion } from "framer-motion";
import { Compass, Home } from "lucide-react";

export default function PageNotFound() {
  const location = useLocation();
  return (
    <div className="min-h-full flex items-center justify-center p-6 relative overflow-hidden">
      <div className="orb orb-a w-80 h-80 top-10 left-10" />
      <div className="orb orb-b w-96 h-96 bottom-0 right-0" />
      <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="relative text-center max-w-md">
        <motion.p initial={{ scale: 0.6, rotate: -8 }} animate={{ scale: 1, rotate: 0 }} transition={{ type: "spring", stiffness: 200, damping: 12 }} className="font-display text-[8rem] leading-none font-semibold gradient-text">404</motion.p>
        <h1 className="font-display text-3xl font-semibold mt-2" style={{ color: "var(--text-primary)" }}>This page wandered off</h1>
        <p className="text-sm mt-3" style={{ color: "var(--text-muted)" }}>We couldn't find <code className="px-1.5 py-0.5 rounded-md" style={{ background: "var(--surface-2)" }}>{location.pathname}</code>. It may have moved or never existed.</p>
        <div className="flex gap-2 justify-center mt-7">
          <Link to="/" className="btn"><Home className="w-4 h-4" /> Go home</Link>
          <Link to="/Gallery" className="btn-outline"><Compass className="w-4 h-4" /> Explore art</Link>
        </div>
      </motion.div>
    </div>
  );
}
