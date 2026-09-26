import React, { useEffect, useRef, useState } from "react";
import { feedback } from "@/lib/feedback";

const FRAMES = 8;
const MIN_SPAN = 1;

// Filmstrip thumbnails for a video (drawn by seeking a hidden copy).
function useFilmstrip(url, duration) {
  const [frames, setFrames] = useState([]);
  useEffect(() => {
    if (!url || !duration) return undefined;
    let cancelled = false;
    const v = document.createElement("video");
    v.muted = true; v.playsInline = true; v.preload = "auto"; v.src = url;
    const c = document.createElement("canvas");
    const out = [];
    const grab = (i) => {
      if (cancelled || i >= FRAMES) { if (!cancelled) setFrames(out.slice()); return; }
      const t = Math.min(duration - 0.05, (duration / FRAMES) * (i + 0.5));
      v.onseeked = () => {
        c.width = 72; c.height = Math.round(72 * (v.videoHeight || 16) / (v.videoWidth || 9));
        try { c.getContext("2d").drawImage(v, 0, 0, c.width, c.height); out.push(c.toDataURL("image/jpeg", 0.6)); } catch { out.push(""); }
        setFrames(out.slice());
        grab(i + 1);
      };
      v.currentTime = t;
    };
    v.onloadeddata = () => grab(0);
    return () => { cancelled = true; v.removeAttribute("src"); v.load(); };
  }, [url, duration]);
  return frames;
}

// Pick the part of the clip to keep: drag either handle (max `maxSpan` s).
export default function TrimBar({ url, duration, start, end, onChange, playhead = 0, maxSpan = 60 }) {
  const frames = useFilmstrip(url, duration);
  const track = useRef(null);
  const drag = useRef(null);
  const d = Math.max(0.1, duration);
  const pct = (t) => `${(t / d) * 100}%`;

  const onDown = (which) => (e) => {
    e.preventDefault();
    e.currentTarget.setPointerCapture?.(e.pointerId);
    drag.current = which;
  };
  const onMove = (e) => {
    if (!drag.current || !track.current) return;
    const r = track.current.getBoundingClientRect();
    const t = Math.max(0, Math.min(d, ((e.clientX - r.left) / r.width) * d));
    if (drag.current === "start") {
      let s = Math.min(t, end - MIN_SPAN);
      if (end - s > maxSpan) s = end - maxSpan;
      onChange(Math.max(0, s), end);
    } else {
      let en = Math.max(t, start + MIN_SPAN);
      if (en - start > maxSpan) en = start + maxSpan;
      onChange(start, Math.min(d, en));
    }
  };
  const onUp = () => { if (drag.current) feedback("tap"); drag.current = null; };

  return (
    <div className="select-none">
      <div className="flex justify-between text-xs font-bold tabular-nums mb-2 opacity-80">
        <span>{start.toFixed(1)}s</span>
        <span>{(end - start).toFixed(1)}s selected</span>
        <span>{end.toFixed(1)}s</span>
      </div>
      <div ref={track} className="relative h-14 rounded-xl overflow-hidden touch-none" onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp} style={{ background: "rgb(255 255 255 / 0.08)" }}>
        <div className="absolute inset-0 flex">
          {Array.from({ length: FRAMES }).map((_, i) => (
            <div key={i} className="flex-1 h-full bg-center bg-cover" style={{ backgroundImage: frames[i] ? `url(${frames[i]})` : undefined, opacity: 0.9 }} />
          ))}
        </div>
        <div className="absolute inset-y-0 left-0 bg-black/60" style={{ width: pct(start) }} />
        <div className="absolute inset-y-0 right-0 bg-black/60" style={{ left: pct(end) }} />
        <div className="absolute inset-y-0 border-y-[3px] pointer-events-none" style={{ left: pct(start), width: `calc(${pct(end)} - ${pct(start)})`, borderColor: "#fff" }} />
        <div className="absolute inset-y-0 w-0.5 bg-white/90 pointer-events-none" style={{ left: pct(Math.min(end, Math.max(start, playhead))) }} />
        {["start", "end"].map((which) => (
          <button
            key={which}
            type="button"
            onPointerDown={onDown(which)}
            className="absolute inset-y-0 w-5 -ml-2.5 flex items-center justify-center cursor-ew-resize touch-none"
            style={{ left: pct(which === "start" ? start : end) }}
            aria-label={which === "start" ? "Trim start" : "Trim end"}
          >
            <span className="w-3.5 h-full rounded-md bg-white flex items-center justify-center"><span className="w-0.5 h-5 rounded bg-neutral-400" /></span>
          </button>
        ))}
      </div>
    </div>
  );
}
