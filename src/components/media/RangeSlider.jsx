import React, { useRef } from "react";

// Two-thumb slider for a time range. Touch friendly (big thumbs, no page scroll).
export default function RangeSlider({ min = 0, max = 1, from, to, onChange, onCommit, step = 0.1, format = (v) => v.toFixed(1), label }) {
  const track = useRef(null);
  const drag = useRef(null);
  const span = Math.max(0.0001, max - min);
  const pct = (v) => `${((v - min) / span) * 100}%`;
  const valueAt = (clientX) => {
    const r = track.current.getBoundingClientRect();
    const raw = min + ((clientX - r.left) / r.width) * span;
    return Math.round(Math.max(min, Math.min(max, raw)) / step) * step;
  };
  const onDown = (e) => {
    e.preventDefault();
    const v = valueAt(e.clientX);
    const which = Math.abs(v - from) <= Math.abs(v - to) ? "from" : "to";
    drag.current = which;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    move(v, which);
  };
  const move = (v, which = drag.current) => {
    if (which === "from") onChange(Math.min(v, to - step), to);
    else onChange(from, Math.max(v, from + step));
  };
  return (
    <div className="select-none" aria-label={label}>
      <div className="flex justify-between text-[11px] font-bold tabular-nums opacity-75 mb-1.5"><span>{format(from)}</span><span>{format(to)}</span></div>
      <div
        ref={track}
        className="relative h-8 flex items-center cursor-pointer"
        style={{ touchAction: "none" }}
        onPointerDown={onDown}
        onPointerMove={(e) => { if (drag.current) move(valueAt(e.clientX)); }}
        onPointerUp={() => { drag.current = null; onCommit?.(); }}
        onPointerCancel={() => { drag.current = null; onCommit?.(); }}
      >
        <div className="absolute inset-x-0 h-1.5 rounded-full" style={{ background: "rgb(255 255 255 / 0.18)" }} />
        <div className="absolute h-1.5 rounded-full" style={{ left: pct(from), width: `calc(${pct(to)} - ${pct(from)})`, background: "#ff4d7d" }} />
        {[from, to].map((v, i) => <span key={i} className="absolute w-6 h-6 -ml-3 rounded-full bg-white shadow-md" style={{ left: pct(v) }} role="slider" aria-valuenow={v} aria-label={i ? "Hide at" : "Show from"} />)}
      </div>
    </div>
  );
}
