import React from "react";

// Text stickers on reels.
// { id, text, x, y (0..1 of the frame), size (fraction of frame width),
//   rot (degrees), color, font, style, anim, from, to (seconds, optional) }
export const STICKER_FONTS = [
  { id: "sans", label: "Classic", css: { fontFamily: '"Plus Jakarta Sans Variable", system-ui, sans-serif', fontWeight: 800 } },
  { id: "bubbly", label: "Bubbly", css: { fontFamily: '"Bubbly", "Cute Here", system-ui, sans-serif', fontWeight: 400, letterSpacing: "0.02em" } },
  { id: "cute", label: "Cute", css: { fontFamily: '"Cute Here", system-ui, sans-serif', fontWeight: 400, letterSpacing: "0.03em" } },
  { id: "serif", label: "Serif", css: { fontFamily: 'Georgia, "Times New Roman", serif', fontWeight: 700, fontStyle: "italic" } },
  { id: "mono", label: "Mono", css: { fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace', fontWeight: 700 } },
];
export const STICKER_STYLES = [
  { id: "plain", label: "Plain" },
  { id: "pill", label: "Label" },
  { id: "outline", label: "Outline" },
  { id: "neon", label: "Neon" },
  { id: "shadow", label: "Shadow" },
];
export const STICKER_ANIMS = [
  { id: "none", label: "None" },
  { id: "pop", label: "Pop" },
  { id: "fade", label: "Fade" },
  { id: "rise", label: "Rise" },
  { id: "type", label: "Type" },
  { id: "bounce", label: "Bounce" },
  { id: "wiggle", label: "Wiggle" },
  { id: "pulse", label: "Pulse" },
];
export const STICKER_COLORS = ["#ffffff", "#2a1620", "#ff4d7d", "#ffd35c", "#7ce0b8", "#7cbeff", "#b58be0", "#ff9f6b"];

const isLight = (hex) => {
  const h = String(hex || "#fff").replace("#", "");
  const n = h.length === 3 ? h.split("").map((c) => c + c).join("") : h.padEnd(6, "f");
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16));
  return (r * 299 + g * 587 + b * 114) / 1000 > 150;
};

// Older reels stored { bg } instead of a style.
export function normalizeSticker(s) {
  return { rot: 0, font: "sans", anim: "none", ...s, style: s.style || (s.bg ? "pill" : "plain"), size: s.size || 0.07 };
}

export function stickerTextCss(raw) {
  const s = normalizeSticker(raw);
  const color = s.color || "#ffffff";
  const contrast = isLight(color) ? "#2a1620" : "#ffffff";
  const font = (STICKER_FONTS.find((f) => f.id === s.font) || STICKER_FONTS[0]).css;
  const base = { ...font, color, fontSize: `${s.size * 100}cqw`, lineHeight: 1.15, whiteSpace: "pre-wrap", textAlign: "center", display: "inline-block" };
  switch (s.style) {
    case "pill": return { ...base, background: s.bg || (isLight(color) ? "rgba(217,87,127,0.92)" : "rgba(255,255,255,0.94)"), padding: "0.18em 0.55em", borderRadius: "0.45em", boxShadow: "0 0.08em 0.3em rgb(0 0 0 / 0.18)" };
    case "outline": return { ...base, WebkitTextStroke: `0.07em ${contrast}`, paintOrder: "stroke fill" };
    case "neon": return { ...base, color: "#fff", textShadow: `0 0 0.06em #fff, 0 0 0.22em ${color}, 0 0 0.5em ${color}, 0 0 0.9em ${color}` };
    case "shadow": return { ...base, textShadow: `0.07em 0.07em 0 ${contrast}` };
    default: return { ...base, textShadow: "0 0.05em 0.3em rgb(0 0 0 / 0.55)" };
  }
}

// One sticker. `children` can add editing handles.
export function StickerView({ sticker, className = "", style, innerProps, children, ...rest }) {
  const s = normalizeSticker(sticker);
  return (
    <span
      data-sticker={s.id}
      data-from={s.from ?? ""}
      data-to={s.to ?? ""}
      className={`absolute max-w-[92%] ${className}`}
      style={{ left: `${s.x * 100}%`, top: `${s.y * 100}%`, transform: `translate(-50%, -50%) rotate(${s.rot}deg)`, ...style }}
      {...rest}
    >
      <span className={`sticker-anim-${s.anim}`} style={stickerTextCss(s)} {...innerProps}>{s.text || " "}</span>
      {children}
    </span>
  );
}

// All stickers of a reel, for playback (pointer-events off).
export function StickerLayer({ items = [], layerRef }) {
  if (!items?.length) return null;
  return (
    <div ref={layerRef} className="absolute inset-0 pointer-events-none">
      {items.map((s) => <StickerView key={s.id} sticker={s} />)}
    </div>
  );
}
