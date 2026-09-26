import React, { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Heart } from "lucide-react";
import { haptic } from "@/lib/native";

const PARTICLES = Array.from({ length: 8 }, (_, i) => {
  const angle = (i / 8) * Math.PI * 2;
  return { x: Math.cos(angle) * 22, y: Math.sin(angle) * 22 };
});

// Heart toggle with a little particle burst when liking.
export default function LikeButton({ liked, count, onToggle, variant = "pill", disabled, className = "", label }) {
  const [burst, setBurst] = useState(0);
  const click = (e) => {
    e.stopPropagation();
    e.preventDefault();
    if (disabled) return;
    if (!liked) setBurst((b) => b + 1);
    haptic(liked ? "light" : "medium");
    onToggle?.();
  };
  const styles = {
    pill: liked
      ? { background: "var(--accent-grad)", color: "#fff", boxShadow: "var(--shadow-accent)" }
      : { background: "var(--pink-soft)", color: "var(--accent-rose)" },
    overlay: liked
      ? { background: "var(--accent-grad)", color: "#fff" }
      : { background: "rgb(255 255 255 / 0.92)", color: "#5b4450" },
    plain: { color: liked ? "var(--accent-rose)" : "var(--text-muted)" },
  };
  const pad = variant === "plain" ? "px-1 py-0.5" : "px-3 py-1.5";
  return (
    <button
      type="button"
      onClick={click}
      disabled={disabled}
      aria-pressed={liked}
      aria-label={label || (liked ? "Unlike" : "Like")}
      className={`relative inline-flex items-center gap-1.5 rounded-full text-xs font-bold transition-colors disabled:opacity-60 ${pad} ${className}`}
      style={styles[variant]}
    >
      <span className="relative inline-flex">
        <motion.span key={liked ? "on" : "off"} initial={{ scale: liked ? 0.4 : 1 }} animate={{ scale: 1 }} transition={{ type: "spring", stiffness: 600, damping: 12 }} className="inline-flex">
          <Heart className={`w-4 h-4 ${liked ? "fill-current" : ""}`} />
        </motion.span>
        <AnimatePresence>
          {burst > 0 && liked && (
            <motion.span key={burst} className="absolute inset-0 pointer-events-none" initial="a" animate="b" exit={{ opacity: 0 }}>
              {PARTICLES.map((p, i) => (
                <motion.span
                  key={i}
                  className="absolute left-1/2 top-1/2 w-1.5 h-1.5 rounded-full"
                  style={{ background: i % 2 ? "var(--accent-pink)" : "var(--accent-rose)", marginLeft: -3, marginTop: -3 }}
                  variants={{ a: { x: 0, y: 0, opacity: 1, scale: 1 }, b: { x: p.x, y: p.y, opacity: 0, scale: 0.4 } }}
                  transition={{ duration: 0.55, ease: "easeOut" }}
                />
              ))}
            </motion.span>
          )}
        </AnimatePresence>
      </span>
      {count !== undefined && (
        <span className="relative inline-flex overflow-hidden tabular-nums" style={{ minWidth: "1ch" }}>
          <motion.span key={count} initial={{ y: liked ? 10 : -10, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={{ type: "spring", stiffness: 500, damping: 30 }}>
            {count}
          </motion.span>
        </span>
      )}
    </button>
  );
}
