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
// Switches only once the new logo is decoded, so it never blinks or flickers.
const decoded = new Set();
function whenReady(accent) {
  const url = `/brand/sugerly-logo-${accent}-sm.webp`;
  if (decoded.has(url)) return Promise.resolve();
  const img = new Image();
  img.src = url;
  return (img.decode ? img.decode() : Promise.resolve()).catch(() => {}).then(() => { decoded.add(url); });
}
let warmed = false;
function warmLogos() {
  if (warmed) return;
  warmed = true;
  const run = () => Object.keys(LOGO_RATIO).forEach((a) => whenReady(a));
  (window.requestIdleCallback || ((f) => setTimeout(f, 1500)))(run);
}

export function useAccent() {
  const [accent, setAccent] = useState(currentAccent);
  useEffect(() => {
    warmLogos();
    let latest = currentAccent();
    const mo = new MutationObserver(() => {
      const next = currentAccent();
      if (next === latest) return;
      latest = next;
      whenReady(next).then(() => { if (latest === next) setAccent(next); });
    });
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-accent"] });
    return () => mo.disconnect();
  }, []);
  return accent;
}

export function BrandLogo({ height = 40, className = "", style, shine = false }) {
  const accent = useAccent();
  const width = Math.round(height * LOGO_RATIO[accent]);
  const img = (
    <img
      src={`/brand/sugerly-logo-${accent}-sm.webp`}
      srcSet={`/brand/sugerly-logo-${accent}-sm.webp 360w, /brand/sugerly-logo-${accent}.webp 720w`}
      sizes={`${width}px`}
      alt={APP_NAME}
      draggable={false}
      // Small and always on screen: decode right away and keep its space, so
      // it never blinks out when the header re-renders.
      decoding="sync"
      fetchpriority="high"
      width={width}
      height={height}
      className={`select-none ${shine ? "" : className}`}
      style={{ height, width, ...(shine ? {} : style) }}
    />
  );
  if (!shine) return img;
  // A soft shine that sweeps across now and then, and a tiny twinkle.
  return (
    <span className={`logo-shine ${className}`} style={{ width, height, "--logo": `url(/brand/sugerly-logo-${accent}-sm.webp)`, ...style }}>
      {img}
      <span className="logo-shine-sweep" aria-hidden="true" />
      <span className="logo-sparkle" aria-hidden="true" />
    </span>
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
