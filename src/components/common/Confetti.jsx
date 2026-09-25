import React, { useMemo } from "react";
import { motion } from "framer-motion";

const COLORS = ["#ee8fae", "#d9577f", "#b19cff", "#5fd3b0", "#ffaa80", "#7cbeff", "#ffd166"];

// One-shot confetti burst from the center of its (relative) parent.
export default function Confetti({ count = 60 }) {
  const pieces = useMemo(() => Array.from({ length: count }, (_, i) => {
    const angle = Math.random() * Math.PI * 2;
    const dist = 120 + Math.random() * 260;
    return {
      id: i,
      x: Math.cos(angle) * dist,
      y: Math.sin(angle) * dist * 0.7 - 80,
      rotate: Math.random() * 720 - 360,
      color: COLORS[i % COLORS.length],
      w: 6 + Math.random() * 6,
      h: 8 + Math.random() * 10,
      delay: Math.random() * 0.15,
    };
  }), [count]);
  return (
    <div className="pointer-events-none absolute inset-0 overflow-visible" aria-hidden="true">
      {pieces.map((p) => (
        <motion.span
          key={p.id}
          className="absolute left-1/2 top-1/2 rounded-sm"
          style={{ width: p.w, height: p.h, background: p.color }}
          initial={{ x: 0, y: 0, opacity: 1, rotate: 0, scale: 0.6 }}
          animate={{ x: p.x, y: [0, p.y, p.y + 260], opacity: [1, 1, 0], rotate: p.rotate, scale: 1 }}
          transition={{ duration: 1.8, delay: p.delay, ease: [0.2, 0.8, 0.4, 1] }}
        />
      ))}
    </div>
  );
}
