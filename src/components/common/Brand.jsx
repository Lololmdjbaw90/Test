import React, { useEffect, useState } from "react";

// The Sugerly wordmark and its "S" mark (artwork lives in /public/brand;
// the full-size source is in /brand).
export const APP_NAME = "Sugerly";

// The wordmark comes in one color per accent (Settings → Appearance);
// Rose (pink) is the default. Width / height of each file after trimming.
const LOGO_RATIO = { rose: 1.978, lavender: 1.995, mint: 2.023, peach: 1.983, sky: 2.019 };
const currentAccent = () => {
  const a = typeof document !== "undefined" ? document.documentElement.getAttribute("data-accent") : "";
  return LOGO_RATIO[a] ? a : "rose";
};

// Follows the accent live (the theme code sets data-accent on <html>).
export function useAccent() {
  const [accent, setAccent] = useState(currentAccent);
  useEffect(() => {
    const mo = new MutationObserver(() => setAccent(currentAccent()));
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-accent"] });
    return () => mo.disconnect();
  }, []);
  return accent;
}

export function BrandLogo({ height = 40, className = "", style }) {
  const accent = useAccent();
  const [shown, setShown] = useState(accent);
  useEffect(() => {
    let active = true;
    const img = new Image();
    img.src = `/brand/sugerly-logo-${accent}-sm.webp`;
    img.decode().then(() => { if (active) setShown(accent); }).catch(() => {});
    return () => { active = false; };
  }, [accent]);
  const width = Math.round(height * 2.023);
  return (
    <img
      src={`/brand/sugerly-logo-${shown}-sm.webp`}
      sizes={`${width}px`}
      alt={APP_NAME}
      draggable={false}
      // Small and always on screen: decode right away and keep its space, so
      // it never blinks out when the header re-renders.
      decoding="sync"
      fetchpriority="high"
      width={width}
      height={height}
      className={`select-none ${className}`}
      style={{ height, width, objectFit: "contain", ...style }}
    />
  );
}

export function BrandMark({ size = 40, className = "", style }) {
  return (
    <img
      src="/brand/sugerly-mark.webp"
      alt={APP_NAME}
      draggable={false}
      decoding="sync"
      width={size}
      height={size}
      className={`select-none ${className}`}
      style={{ width: size, height: size, ...style }}
    />
  );
}
