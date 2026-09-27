import React from "react";

// An iOS-style app icon: a rounded square with a gradient and a glossy rim.
export default function AppIcon({ icon: Icon, tint = ["#ff8fb1", "#ff4d7d"], size = 44, className = "" }) {
  const r = Math.round(size * 0.29);
  return (
    <span
      className={`relative inline-flex items-center justify-center flex-shrink-0 text-white ${className}`}
      style={{ width: size, height: size, borderRadius: r, background: `linear-gradient(150deg, ${tint[0]}, ${tint[1]})`, boxShadow: `inset 0 1px 1px rgb(255 255 255 / 0.55), inset 0 -2px 4px rgb(0 0 0 / 0.08), 0 4px 12px -4px ${tint[1]}80` }}
      aria-hidden="true"
    >
      <Icon style={{ width: size * 0.48, height: size * 0.48 }} strokeWidth={2.2} />
    </span>
  );
}
