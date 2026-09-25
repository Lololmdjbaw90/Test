import React, { useRef, useState, useCallback, useEffect } from "react";
import { motion } from "framer-motion";
import { Check, X, ZoomIn, ZoomOut } from "lucide-react";

const SIZE = 260;

// Circular avatar cropper: drag to reposition, wheel/slider to zoom.
export default function ImageCropper({ imageSrc, onCrop, onCancel, output = 400 }) {
  const canvasRef = useRef(null);
  const imgRef = useRef(null);
  const drag = useRef(null);
  const [scale, setScale] = useState(1);
  const [minScale, setMinScale] = useState(0.3);
  const [offset, setOffset] = useState({ x: 0, y: 0 });

  useEffect(() => {
    const img = new Image();
    img.onload = () => {
      imgRef.current = img;
      const fit = Math.max(SIZE / img.naturalWidth, SIZE / img.naturalHeight);
      setMinScale(fit * 0.5);
      setScale(fit);
      setOffset({ x: 0, y: 0 });
    };
    img.src = imageSrc;
  }, [imageSrc]);

  const geometry = useCallback((size) => {
    const img = imgRef.current;
    const ratio = size / SIZE;
    const w = img.naturalWidth * scale * ratio;
    const h = img.naturalHeight * scale * ratio;
    return { w, h, x: size / 2 - w / 2 + offset.x * ratio, y: size / 2 - h / 2 + offset.y * ratio };
  }, [scale, offset]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !imgRef.current) return;
    const ctx = canvas.getContext("2d");
    const { w, h, x, y } = geometry(SIZE);
    ctx.clearRect(0, 0, SIZE, SIZE);
    ctx.globalAlpha = 0.35;
    ctx.drawImage(imgRef.current, x, y, w, h);
    ctx.globalAlpha = 1;
    ctx.save();
    ctx.beginPath();
    ctx.arc(SIZE / 2, SIZE / 2, SIZE / 2 - 6, 0, Math.PI * 2);
    ctx.clip();
    ctx.drawImage(imgRef.current, x, y, w, h);
    ctx.restore();
    ctx.beginPath();
    ctx.arc(SIZE / 2, SIZE / 2, SIZE / 2 - 6, 0, Math.PI * 2);
    ctx.strokeStyle = "rgba(255,255,255,0.9)";
    ctx.lineWidth = 3;
    ctx.stroke();
  }, [geometry, scale, offset]);

  const handleCrop = () => {
    if (!imgRef.current) return;
    const out = document.createElement("canvas");
    out.width = output;
    out.height = output;
    const ctx = out.getContext("2d");
    const { w, h, x, y } = geometry(output);
    ctx.drawImage(imgRef.current, x, y, w, h);
    out.toBlob((blob) => {
      const file = new File([blob], "avatar.jpg", { type: "image/jpeg" });
      onCrop(file, URL.createObjectURL(blob));
    }, "image/jpeg", 0.9);
  };

  return (
    <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="flex flex-col items-center gap-4">
      <p className="text-xs font-semibold" style={{ color: "var(--text-muted)" }}>Drag to reposition · scroll to zoom</p>
      <div
        className="rounded-3xl overflow-hidden cursor-grab active:cursor-grabbing select-none touch-none"
        style={{ width: SIZE, height: SIZE, background: "#1b1016", boxShadow: "var(--shadow-md)" }}
        onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); drag.current = { x: e.clientX - offset.x, y: e.clientY - offset.y }; }}
        onPointerMove={(e) => { if (drag.current) setOffset({ x: e.clientX - drag.current.x, y: e.clientY - drag.current.y }); }}
        onPointerUp={() => { drag.current = null; }}
        onWheel={(e) => setScale((s) => Math.max(minScale, Math.min(minScale * 10, s * (e.deltaY > 0 ? 0.94 : 1.06))))}
      >
        <canvas ref={canvasRef} width={SIZE} height={SIZE} />
      </div>
      <div className="flex items-center gap-3 w-full max-w-[260px]">
        <ZoomOut className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
        <input type="range" min={minScale} max={minScale * 10} step={0.001} value={scale} onChange={(e) => setScale(parseFloat(e.target.value))} className="flex-1" style={{ accentColor: "var(--accent-rose)" }} aria-label="Zoom" />
        <ZoomIn className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
      </div>
      <div className="flex gap-2 w-full max-w-[260px]">
        <button type="button" onClick={onCancel} className="btn-outline flex-1"><X className="w-4 h-4" /> Cancel</button>
        <button type="button" onClick={handleCrop} className="btn flex-1"><Check className="w-4 h-4" /> Use photo</button>
      </div>
    </motion.div>
  );
}
