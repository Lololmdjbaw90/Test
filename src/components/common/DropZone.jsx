import React, { useRef, useState } from "react";
import { motion } from "framer-motion";
import { ImagePlus, X } from "lucide-react";

// Click-or-drag file picker with an image preview.
export default function DropZone({ accept = "image/*", preview, onFile, onClear, label = "Drop an image here or click to browse", hint, height = 200, icon: Icon = ImagePlus }) {
  const inputRef = useRef(null);
  const [over, setOver] = useState(false);
  const pick = (file) => {
    if (!file) return;
    const kind = accept.split(",")[0].split("/")[0];
    if (accept !== "*" && kind !== "*" && !file.type.startsWith(kind) && !accept.includes(file.type)) return;
    onFile?.(file);
  };
  if (preview) {
    return (
      <motion.div initial={{ opacity: 0, scale: 0.98 }} animate={{ opacity: 1, scale: 1 }} className="relative rounded-2xl overflow-hidden" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)" }}>
        <img loading="lazy" decoding="async" src={preview} alt="" className="w-full object-cover" style={{ maxHeight: height * 1.6 }} />
        {onClear && (
          <button type="button" onClick={onClear} className="icon-btn glass absolute top-3 right-3" style={{ border: "1px solid var(--border-c)" }} aria-label="Remove image"><X className="w-4 h-4" /></button>
        )}
      </motion.div>
    );
  }
  return (
    <>
      <motion.button
        type="button"
        onClick={() => inputRef.current?.click()}
        onDragOver={(e) => { e.preventDefault(); setOver(true); }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => { e.preventDefault(); setOver(false); pick(e.dataTransfer.files?.[0]); }}
        animate={{ scale: over ? 1.01 : 1 }}
        className="w-full rounded-2xl flex flex-col items-center justify-center gap-2.5 text-center px-4 transition-colors"
        style={{ height, border: `2px dashed ${over ? "var(--accent-rose)" : "var(--border-strong)"}`, background: over ? "var(--pink-soft)" : "var(--surface-2)" }}
      >
        <motion.span animate={{ y: over ? -4 : 0 }} className="w-12 h-12 rounded-2xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}>
          <Icon className="w-5 h-5" />
        </motion.span>
        <span className="text-sm font-semibold" style={{ color: "var(--text-secondary)" }}>{label}</span>
        {hint && <span className="text-xs" style={{ color: "var(--text-muted)" }}>{hint}</span>}
      </motion.button>
      <input ref={inputRef} type="file" accept={accept} className="hidden" onChange={(e) => { pick(e.target.files?.[0]); e.target.value = ""; }} />
    </>
  );
}
