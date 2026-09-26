import React from "react";

// The Sugerly wordmark and its "S" mark (artwork lives in /public/brand;
// the full-size source is in /brand).
export const APP_NAME = "Sugerly";

export function BrandLogo({ height = 40, className = "", style }) {
  return (
    <img
      src="/brand/sugerly-logo-sm.webp"
      srcSet="/brand/sugerly-logo-sm.webp 360w, /brand/sugerly-logo.webp 720w"
      sizes={`${Math.round(height * 1.84)}px`}
      alt={APP_NAME}
      draggable={false}
      decoding="async"
      className={`select-none ${className}`}
      style={{ height, width: "auto", ...style }}
    />
  );
}

export function BrandMark({ size = 40, className = "", style }) {
  return (
    <img
      src="/brand/sugerly-mark.webp"
      alt={APP_NAME}
      draggable={false}
      decoding="async"
      className={`select-none ${className}`}
      style={{ width: size, height: size, ...style }}
    />
  );
}
