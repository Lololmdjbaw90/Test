import React from "react";
import { Zap } from "lucide-react";

export const LEVELS = [
  { level: 1, xpRequired: 0, title: "Newcomer", color: "#94a3b8" },
  { level: 2, xpRequired: 100, title: "Sketcher", color: "#3b82f6" },
  { level: 3, xpRequired: 300, title: "Artisan", color: "#10b981" },
  { level: 4, xpRequired: 700, title: "Creator", color: "#8b5cf6" },
  { level: 5, xpRequired: 1500, title: "Master", color: "#f0a020" },
  { level: 6, xpRequired: 3000, title: "Luminary", color: "#f97316" },
  { level: 7, xpRequired: 6000, title: "Legend", color: "#e86d98" },
  { level: 8, xpRequired: 10000, title: "Mimi Elite", color: "#db2777" },
];

export function getLevelInfo(xp = 0) {
  let current = LEVELS[0], next = LEVELS[1];
  for (let i = LEVELS.length - 1; i >= 0; i--) {
    if (xp >= LEVELS[i].xpRequired) { current = LEVELS[i]; next = LEVELS[i + 1] || null; break; }
  }
  const xpInLevel = xp - current.xpRequired;
  const xpNeeded = next ? next.xpRequired - current.xpRequired : 0;
  return { current, next, xpInLevel, xpNeeded, progress: next ? Math.min(100, (xpInLevel / xpNeeded) * 100) : 100 };
}

export default function LevelBadge({ xp = 0 }) {
  const { current } = getLevelInfo(xp);
  return (
    <span className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-bold" style={{ background: `${current.color}1f`, color: current.color, border: `1px solid ${current.color}40` }}>
      <Zap className="w-3 h-3" />Lv.{current.level} · {current.title}
    </span>
  );
}
