import React from "react";
import { FILTERS, filterCss } from "@/lib/filters";
import { feedback } from "@/lib/feedback";
import FilterLayers from "./FilterLayers";

// Horizontal row of filter previews (Instagram / TikTok style).
export default function FilterStrip({ thumb, value, onChange, dark = false, className = "" }) {
  return (
    <div className={`flex gap-2.5 overflow-x-auto no-scrollbar px-1 py-1 ${className}`} role="listbox" aria-label="Filters">
      {FILTERS.map((f) => {
        const active = f.id === value;
        return (
          <button
            key={f.id}
            type="button"
            role="option"
            aria-selected={active}
            onClick={() => { if (!active) feedback("tap"); onChange(f.id); }}
            className="flex flex-col items-center gap-1.5 flex-shrink-0"
          >
            <span className="relative block w-16 h-16 rounded-2xl overflow-hidden transition-transform" style={{ boxShadow: active ? "0 0 0 2px #fff, 0 0 0 4px rgb(var(--accent-rgb))" : "0 0 0 1px rgb(255 255 255 / 0.15)", scale: active ? "1.04" : "1" }}>
              {thumb ? <img src={thumb} alt="" draggable={false} className="w-full h-full object-cover" style={{ filter: filterCss(f.id) }} /> : <span className="block w-full h-full" style={{ background: "linear-gradient(135deg,#f7c6d4,#b58be0)", filter: filterCss(f.id) }} />}
              <FilterLayers filter={f.id} />
            </span>
            <span className="text-[11px] font-bold" style={{ color: active ? (dark ? "#fff" : "var(--accent-rose)") : dark ? "rgb(255 255 255 / 0.7)" : "var(--text-muted)" }}>{f.name}</span>
          </button>
        );
      })}
    </div>
  );
}
