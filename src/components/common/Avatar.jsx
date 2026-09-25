import React, { useState } from "react";
import { initials } from "@/lib/format";

// Round avatar with graceful fallback to an initial on a gradient.
export default function Avatar({ src, name, size = 36, online, nitro, className = "", square = false, style }) {
  const [err, setErr] = useState(false);
  const radius = square ? Math.round(size * 0.3) : 9999;
  const dot = Math.max(8, Math.round(size * 0.28));
  return (
    <span className={`relative inline-flex flex-shrink-0 ${className}`} style={{ width: size, height: size, ...style }}>
      {nitro && (
        <span className="absolute -inset-[3px] rounded-full" style={{ background: "conic-gradient(from 0deg,#c084fc,#818cf8,var(--accent-pink),#c084fc)", borderRadius: radius + 3 }} />
      )}
      {src && !err ? (
        <img
          src={src}
          alt=""
          loading="lazy"
          onError={() => setErr(true)}
          className="relative w-full h-full object-cover"
          style={{ borderRadius: radius, background: "var(--pink-soft)", boxShadow: nitro ? "0 0 0 2px var(--surface)" : undefined }}
        />
      ) : (
        <span
          className="relative w-full h-full flex items-center justify-center font-bold text-white select-none"
          style={{ borderRadius: radius, background: "var(--accent-grad)", fontSize: Math.max(10, size * 0.4), boxShadow: nitro ? "0 0 0 2px var(--surface)" : undefined }}
        >
          {initials(name)}
        </span>
      )}
      {online !== undefined && (
        <span
          className="absolute rounded-full"
          style={{ width: dot, height: dot, right: -1, bottom: -1, background: online ? "var(--success)" : "var(--text-muted)", border: "2px solid var(--surface)" }}
          title={online ? "Online" : "Offline"}
        />
      )}
    </span>
  );
}
