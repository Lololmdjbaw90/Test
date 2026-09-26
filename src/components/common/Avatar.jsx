import React, { useState } from "react";
import { initials } from "@/lib/format";

// Round avatar with graceful fallback to an initial on a gradient.
// `ring` draws a solid outline of that many px (in `ringColor`) around the
// avatar itself, so it always stays a perfect circle — use it instead of
// wrapping the avatar in another element with a shadow or padding.
export default function Avatar({ src, name, size = 36, online, nitro, className = "", square = false, style, ring = 0, ringColor = "var(--surface)" }) {
  const [err, setErr] = useState(false);
  const radius = square ? Math.round(size * 0.3) : 9999;
  const dot = Math.max(8, Math.round(size * 0.28));
  const nitroWidth = nitro ? 3 : 0;
  const outline = ring ? `0 0 0 ${ring + nitroWidth}px ${ringColor}` : undefined;
  return (
    <span className={`relative inline-flex flex-shrink-0 align-middle ${className}`} style={{ width: size, height: size, borderRadius: radius, boxShadow: outline, ...style }}>
      {nitro && (
        <span className="absolute -inset-[3px]" style={{ background: "conic-gradient(from 0deg,#c084fc,#818cf8,var(--accent-pink),#c084fc)", borderRadius: radius === 9999 ? 9999 : radius + 3 }} />
      )}
      {src && !err ? (
        <img
          src={src}
          alt=""
          loading="lazy"
          decoding="async"
          onError={() => setErr(true)}
          className="relative w-full h-full object-cover"
          style={{ borderRadius: radius, background: "var(--pink-soft)", boxShadow: nitro ? "0 0 0 2px var(--surface)" : undefined }}
        />
      ) : (
        <span
          className="relative w-full h-full flex items-center justify-center font-bold text-white select-none leading-none"
          style={{ borderRadius: radius, background: "var(--accent-grad)", fontSize: Math.max(10, size * 0.4), boxShadow: nitro ? "0 0 0 2px var(--surface)" : undefined }}
        >
          {initials(name)}
        </span>
      )}
      {online !== undefined && (
        <span
          className="absolute rounded-full"
          style={{ width: dot, height: dot, right: -1, bottom: -1, background: online ? "var(--success)" : "var(--text-muted)", border: `${size > 60 ? 3 : 2}px solid var(--surface)` }}
          title={online ? "Online" : "Offline"}
        />
      )}
    </span>
  );
}
