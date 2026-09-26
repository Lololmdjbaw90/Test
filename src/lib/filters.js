// Photo & video filters.
// -----------------------------------------------------------------------------
// Each filter is a short list of CSS filter steps (plus an optional tint and
// vignette). Previews and videos use the CSS version directly; photos are
// "baked" with the exact same maths as a colour matrix on a canvas, so a
// posted photo looks identical everywhere (older iPhones included, which
// can't apply CSS filters when drawing to a canvas).
// -----------------------------------------------------------------------------

export const FILTERS = [
  { id: "none", name: "Original", steps: [] },
  { id: "sugar", name: "Sugar", steps: [["brightness", 1.06], ["contrast", 1.04], ["saturate", 1.15], ["hue-rotate", -8]], tint: "rgba(255,150,190,0.18)" },
  { id: "peach", name: "Peach", steps: [["brightness", 1.05], ["saturate", 1.2], ["sepia", 0.18]], tint: "rgba(255,170,120,0.16)" },
  { id: "dreamy", name: "Dreamy", steps: [["brightness", 1.1], ["contrast", 0.86], ["saturate", 1.1]], tint: "rgba(210,190,255,0.2)" },
  { id: "vivid", name: "Vivid", steps: [["contrast", 1.15], ["saturate", 1.55]] },
  { id: "pop", name: "Pop", steps: [["brightness", 1.05], ["contrast", 1.25], ["saturate", 1.35]], vignette: 0.25 },
  { id: "golden", name: "Golden", steps: [["brightness", 1.04], ["sepia", 0.3], ["saturate", 1.35], ["hue-rotate", -6]], vignette: 0.2 },
  { id: "cool", name: "Cool", steps: [["contrast", 1.05], ["saturate", 1.1], ["hue-rotate", 12]], tint: "rgba(120,170,255,0.14)" },
  { id: "fade", name: "Fade", steps: [["brightness", 1.08], ["contrast", 0.8], ["saturate", 0.8]] },
  { id: "vintage", name: "Vintage", steps: [["sepia", 0.45], ["contrast", 0.92], ["brightness", 1.05], ["saturate", 1.1]], vignette: 0.35 },
  { id: "mono", name: "Mono", steps: [["grayscale", 1], ["contrast", 1.05]] },
  { id: "noir", name: "Noir", steps: [["grayscale", 1], ["contrast", 1.45], ["brightness", 0.95]], vignette: 0.45 },
];
export const filterById = (id) => FILTERS.find((f) => f.id === id) || FILTERS[0];

// CSS for live previews and video playback.
export function filterCss(id) {
  const f = filterById(id);
  return f.steps.length ? f.steps.map(([fn, v]) => `${fn}(${fn === "hue-rotate" ? `${v}deg` : v})`).join(" ") : "none";
}

// Tint + vignette layers drawn on top of a preview (absolutely positioned),
// matching how they're baked into photos.
export function filterLayers(id) {
  const f = filterById(id);
  const layers = [];
  if (f.tint) layers.push({ background: f.tint, mixBlendMode: "soft-light" });
  if (f.vignette) layers.push({ background: `radial-gradient(ellipse at center, rgba(0,0,0,0) 45%, rgba(0,0,0,${f.vignette}) 100%)` });
  return layers;
}

// ---------- colour-matrix maths (Filter Effects spec) ----------
// Matrices are 3×4: [r, g, b, offset] per output channel, values 0..1.
const ID = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]];
function stepMatrix([fn, v]) {
  switch (fn) {
    case "brightness": return [[v, 0, 0, 0], [0, v, 0, 0], [0, 0, v, 0]];
    case "contrast": { const o = 0.5 - 0.5 * v; return [[v, 0, 0, o], [0, v, 0, o], [0, 0, v, o]]; }
    case "saturate": return [
      [0.213 + 0.787 * v, 0.715 - 0.715 * v, 0.072 - 0.072 * v, 0],
      [0.213 - 0.213 * v, 0.715 + 0.285 * v, 0.072 - 0.072 * v, 0],
      [0.213 - 0.213 * v, 0.715 - 0.715 * v, 0.072 + 0.928 * v, 0],
    ];
    case "grayscale": { const a = 1 - Math.min(1, v); return [
      [0.2126 + 0.7874 * a, 0.7152 - 0.7152 * a, 0.0722 - 0.0722 * a, 0],
      [0.2126 - 0.2126 * a, 0.7152 + 0.2848 * a, 0.0722 - 0.0722 * a, 0],
      [0.2126 - 0.2126 * a, 0.7152 - 0.7152 * a, 0.0722 + 0.9278 * a, 0],
    ]; }
    case "sepia": { const a = 1 - Math.min(1, v); return [
      [0.393 + 0.607 * a, 0.769 - 0.769 * a, 0.189 - 0.189 * a, 0],
      [0.349 - 0.349 * a, 0.686 + 0.314 * a, 0.168 - 0.168 * a, 0],
      [0.272 - 0.272 * a, 0.534 - 0.534 * a, 0.131 + 0.869 * a, 0],
    ]; }
    case "hue-rotate": {
      const r = (v * Math.PI) / 180, c = Math.cos(r), s = Math.sin(r);
      return [
        [0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0],
        [0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.14, 0.072 - c * 0.072 - s * 0.283, 0],
        [0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0],
      ];
    }
    default: return ID;
  }
}
// b ∘ a  (apply a first, then b)
function compose(b, a) {
  return b.map((row) => [0, 1, 2, 3].map((j) => row[0] * a[0][j] + row[1] * a[1][j] + row[2] * a[2][j] + (j === 3 ? row[3] : 0)));
}
export function filterMatrix(id) {
  return filterById(id).steps.reduce((m, step) => compose(stepMatrix(step), m), ID);
}

// Applies a filter to a canvas in place (colour matrix, then tint + vignette).
export function applyFilterToCanvas(canvas, id) {
  const f = filterById(id);
  if (f.id === "none") return canvas;
  const ctx = canvas.getContext("2d");
  const { width: w, height: h } = canvas;
  if (f.steps.length) {
    const img = ctx.getImageData(0, 0, w, h);
    const d = img.data;
    const m = filterMatrix(id).map((row) => [row[0], row[1], row[2], row[3] * 255]);
    const clamp = (x) => (x < 0 ? 0 : x > 255 ? 255 : x);
    for (let i = 0; i < d.length; i += 4) {
      const r = d[i], g = d[i + 1], b = d[i + 2];
      d[i] = clamp(m[0][0] * r + m[0][1] * g + m[0][2] * b + m[0][3]);
      d[i + 1] = clamp(m[1][0] * r + m[1][1] * g + m[1][2] * b + m[1][3]);
      d[i + 2] = clamp(m[2][0] * r + m[2][1] * g + m[2][2] * b + m[2][3]);
    }
    ctx.putImageData(img, 0, 0);
  }
  if (f.tint) {
    ctx.save();
    ctx.globalCompositeOperation = "soft-light";
    ctx.fillStyle = f.tint;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }
  if (f.vignette) {
    const g = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.35, w / 2, h / 2, Math.hypot(w, h) / 2);
    g.addColorStop(0, "rgba(0,0,0,0)");
    g.addColorStop(1, `rgba(0,0,0,${f.vignette})`);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
  }
  return canvas;
}

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

// Draws text stickers ({ text, x, y (0..1), color, bg, size (fraction of width) }) onto a canvas.
export function drawTextStickers(canvas, stickers = []) {
  const ctx = canvas.getContext("2d");
  stickers.forEach((s) => {
    const size = Math.round((s.size || 0.07) * canvas.width);
    ctx.font = `700 ${size}px "Plus Jakarta Sans Variable", system-ui, sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const x = s.x * canvas.width, y = s.y * canvas.height;
    const lines = String(s.text || "").split("\n");
    const lh = size * 1.25;
    lines.forEach((line, i) => {
      const ly = y + (i - (lines.length - 1) / 2) * lh;
      if (s.bg) {
        const tw = ctx.measureText(line).width + size * 0.8;
        ctx.fillStyle = s.bg;
        const rx = x - tw / 2, ry = ly - lh / 2, r = size * 0.35;
        ctx.beginPath();
        ctx.moveTo(rx + r, ry); ctx.arcTo(rx + tw, ry, rx + tw, ry + lh, r); ctx.arcTo(rx + tw, ry + lh, rx, ry + lh, r);
        ctx.arcTo(rx, ry + lh, rx, ry, r); ctx.arcTo(rx, ry, rx + tw, ry, r); ctx.closePath(); ctx.fill();
      } else {
        ctx.shadowColor = "rgba(0,0,0,0.45)"; ctx.shadowBlur = size * 0.25;
      }
      ctx.fillStyle = s.color || "#fff";
      ctx.fillText(line, x, ly);
      ctx.shadowBlur = 0;
    });
  });
  return canvas;
}

// Photo → filtered (and optionally captioned) JPEG, at most `max` px on the long side.
export async function bakePhoto(source, { filter = "none", stickers = [], max = 1600, quality = 0.9 } = {}) {
  const src = typeof source === "string" ? source : URL.createObjectURL(source);
  try {
    const img = await loadImage(src);
    const scale = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(img.naturalWidth * scale);
    canvas.height = Math.round(img.naturalHeight * scale);
    canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
    applyFilterToCanvas(canvas, filter);
    if (stickers.length) drawTextStickers(canvas, stickers);
    const blob = await new Promise((r) => canvas.toBlob(r, "image/jpeg", quality));
    return new File([blob], "photo.jpg", { type: "image/jpeg" });
  } finally {
    if (typeof source !== "string") URL.revokeObjectURL(src);
  }
}
