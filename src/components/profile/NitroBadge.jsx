import React from "react";
import { Sparkles } from "lucide-react";

export default function NitroBadge({ active = false }) {
  if (!active) return null;
  return (
    <span className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-bold text-white" style={{ background: "linear-gradient(135deg,#8b5cf6,#c084fc,#ee8fae)", backgroundSize: "200% auto", animation: "gradient-pan 4s linear infinite", boxShadow: "0 4px 14px rgb(139 92 246 / 0.35)" }}>
      <Sparkles className="w-3 h-3" /> Nitro
    </span>
  );
}
