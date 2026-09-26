import React, { useLayoutEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { Search, X } from "lucide-react";

export function SearchInput({ value, onChange, placeholder = "Search…", className = "", autoFocus }) {
  return (
    <div className={`relative ${className}`}>
      <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 pointer-events-none" style={{ color: "var(--text-muted)" }} />
      <input className="input pl-10 pr-9" placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value)} autoFocus={autoFocus} />
      {value && (
        <button type="button" onClick={() => onChange("")} className="absolute right-2.5 top-1/2 -translate-y-1/2 w-6 h-6 rounded-full flex items-center justify-center" style={{ background: "var(--pink-soft)" }} aria-label="Clear search">
          <X className="w-3.5 h-3.5" style={{ color: "var(--text-muted)" }} />
        </button>
      )}
    </div>
  );
}

// Pill tabs with an animated sliding highlight. The highlight is measured and
// animated directly (no shared `layoutId`), because shared-layout elements can
// stall exit animations of the page or dialog they live in.
export function Segmented({ options, value, onChange, size = "md", className = "", stretch = false }) {
  const containerRef = useRef(null);
  const buttons = useRef({});
  const [pill, setPill] = useState(null);
  useLayoutEffect(() => {
    const measure = () => {
      const el = buttons.current[value];
      if (el) setPill({ x: el.offsetLeft, width: el.offsetWidth });
    };
    measure();
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(measure) : null;
    if (ro && containerRef.current) ro.observe(containerRef.current);
    return () => ro?.disconnect();
  }, [value, options.length, stretch]);
  const pad = size === "sm" ? "px-3 py-1.5 text-xs" : "px-4 py-2 text-sm";
  return (
    <div ref={containerRef} className={`relative ${stretch ? "flex" : "inline-flex"} items-center gap-1 p-1 rounded-full max-w-full overflow-x-auto no-scrollbar ${className}`} style={{ background: "var(--surface)", border: "1px solid var(--border-c)", boxShadow: "var(--shadow-sm)" }} role="tablist">
      {pill && (
        <motion.span
          aria-hidden="true"
          className="absolute top-1 bottom-1 left-0 rounded-full"
          initial={false}
          animate={{ x: pill.x, width: pill.width }}
          transition={{ type: "spring", stiffness: 420, damping: 34 }}
          style={{ background: "var(--accent-grad)", boxShadow: "0 4px 10px -4px rgb(var(--accent-rgb) / 0.6)" }}
        />
      )}
      {options.map((o) => {
        const active = value === o.id;
        const Icon = o.icon;
        return (
          <button
            key={o.id}
            ref={(el) => { buttons.current[o.id] = el; }}
            role="tab"
            aria-selected={active}
            onClick={() => onChange(o.id)}
            className={`relative flex items-center justify-center gap-1.5 rounded-full font-semibold whitespace-nowrap transition-colors duration-200 ${stretch ? "flex-1" : ""} ${pad}`}
            style={{ color: active ? "#fff" : "var(--text-secondary)" }}
          >
            {Icon && <Icon className="relative w-4 h-4" />}
            <span className="relative">{o.label}</span>
            {o.count > 0 && (
              <span className="relative text-[10px] font-bold min-w-[18px] h-[18px] px-1 rounded-full flex items-center justify-center" style={active ? { background: "rgb(255 255 255 / 0.25)" } : { background: "var(--pink-soft)", color: "var(--accent-rose)" }}>{o.count}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}

export function ChipRow({ options, value, onChange, className = "" }) {
  return (
    <div className={`flex gap-2 overflow-x-auto no-scrollbar pt-1 pb-3 -mt-1 -mb-2 px-1 -mx-1 ${className}`}>
      {options.map((o) => {
        const id = typeof o === "string" ? o : o.id;
        const label = typeof o === "string" ? o : o.label;
        return <button key={id} className="chip" data-active={value === id} onClick={() => onChange(id)}>{label}</button>;
      })}
    </div>
  );
}

export function Toggle({ checked, onChange, label, description }) {
  return (
    <label className="flex items-center gap-3 cursor-pointer select-none">
      <span className="flex-1 min-w-0">
        {label && <span className="block text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{label}</span>}
        {description && <span className="block text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>{description}</span>}
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className="relative w-11 h-6 rounded-full flex-shrink-0 transition-colors"
        style={{ background: checked ? "var(--accent-rose)" : "var(--border-strong)" }}
      >
        <motion.span initial={false} animate={{ left: checked ? 22 : 2 }} transition={{ type: "spring", stiffness: 500, damping: 32 }} className="absolute top-0.5 w-5 h-5 rounded-full bg-white shadow" />
      </button>
    </label>
  );
}
