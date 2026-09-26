import React, { useEffect, useRef, useState } from "react";
import { ArrowLeft, ArrowRight, Copy, Scissors, Trash2 } from "lucide-react";
import { clipLength, duplicateClip, moveClip, removeClip, splitAt, totalLength, trimClip } from "@/lib/clips";
import { feedback } from "@/lib/feedback";

// Thumbnails across the whole source video (drawn by seeking a hidden copy).
function useFrames(url, duration) {
  const [frames, setFrames] = useState([]);
  useEffect(() => {
    if (!url || !duration) return undefined;
    let cancelled = false;
    const step = Math.max(0.5, duration / 36);
    const times = [];
    for (let t = 0; t < duration; t += step) times.push(t);
    const v = document.createElement("video");
    v.muted = true; v.playsInline = true; v.preload = "auto"; v.src = url;
    const c = document.createElement("canvas");
    const out = [];
    const grab = (i) => {
      if (cancelled || i >= times.length) return;
      v.onseeked = () => {
        c.width = 48; c.height = Math.round(48 * (v.videoHeight || 16) / (v.videoWidth || 9));
        try { c.getContext("2d").drawImage(v, 0, 0, c.width, c.height); out.push({ t: times[i], src: c.toDataURL("image/jpeg", 0.55) }); } catch { /* ignore */ }
        if (i % 4 === 3 || i === times.length - 1) setFrames(out.slice());
        grab(i + 1);
      };
      v.currentTime = Math.min(duration - 0.05, times[i] + 0.01);
    };
    v.onloadeddata = () => grab(0);
    return () => { cancelled = true; v.removeAttribute("src"); v.load(); };
  }, [url, duration]);
  return frames;
}

// CapCut-style cuts: each kept clip is a block; split at the playhead,
// delete, duplicate, reorder, or drag a selected clip's edges to trim it.
export default function ClipTimeline({ url, sourceDuration, clips, onChange, time, onSeek, selected, onSelect, maxLength = 60 }) {
  const frames = useFrames(url, sourceDuration);
  const trackRef = useRef(null);
  const drag = useRef(null);
  const total = totalLength(clips);
  const pxPerSec = Math.max(28, Math.min(90, 300 / Math.max(1, total)));
  const width = Math.max(1, total * pxPerSec);

  // Keep the playhead in view.
  useEffect(() => {
    const el = trackRef.current;
    if (!el || drag.current) return;
    const x = time * pxPerSec;
    if (x < el.scrollLeft + 24 || x > el.scrollLeft + el.clientWidth - 24) el.scrollTo({ left: Math.max(0, x - el.clientWidth / 2) });
  }, [time, pxPerSec]);

  const seekFromEvent = (e) => {
    const el = trackRef.current;
    const r = el.getBoundingClientRect();
    const x = e.clientX - r.left + el.scrollLeft - 12;
    onSeek(Math.max(0, Math.min(total, x / pxPerSec)));
  };
  const onEdgeDown = (i, side) => (e) => {
    e.stopPropagation();
    e.currentTarget.setPointerCapture?.(e.pointerId);
    drag.current = { i, side, x: e.clientX, clip: { ...clips[i] } };
  };
  const onEdgeMove = (e) => {
    const d = drag.current;
    if (!d) return;
    const delta = (e.clientX - d.x) / pxPerSec;
    const next = trimClip(clips, d.i, d.side === "start" ? { start: d.clip.start + delta } : { end: d.clip.end + delta }, sourceDuration);
    if (totalLength(next) <= maxLength + 0.01) onChange(next, { live: true });
  };
  const onEdgeUp = () => { if (drag.current) { drag.current = null; feedback("tap"); onChange(clips); } };

  const act = (fn, sound = "tap") => { feedback(sound); fn(); };
  const split = () => act(() => {
    const r = splitAt(clips, time);
    if (r.index < 0) return;
    onChange(r.clips);
    onSelect(r.index);
  }, "toggle");
  const sel = Math.min(selected ?? 0, clips.length - 1);

  let acc = 0;
  return (
    <div className="space-y-3 select-none">
      <div className="flex items-center justify-between text-xs font-bold tabular-nums opacity-80">
        <span>{time.toFixed(1)}s</span>
        <span>{clips.length} clip{clips.length === 1 ? "" : "s"} · {total.toFixed(1)}s{total > maxLength ? ` (max ${maxLength}s)` : ""}</span>
      </div>
      <div
        ref={trackRef}
        className="relative overflow-x-auto no-scrollbar rounded-xl"
        style={{ touchAction: "pan-x" }}
        onPointerMove={onEdgeMove}
        onPointerUp={onEdgeUp}
        onPointerCancel={onEdgeUp}
        onClick={seekFromEvent}
      >
        <div className="relative h-16 px-3" style={{ width: width + 24 }}>
          {clips.map((c, i) => {
            const left = acc * pxPerSec + 12;
            const w = clipLength(c) * pxPerSec;
            acc += clipLength(c);
            const inside = frames.filter((f) => f.t >= c.start - 0.25 && f.t < c.end);
            const isSel = i === sel;
            return (
              <div
                key={c.id}
                className="absolute top-1 bottom-1 rounded-lg overflow-hidden transition-[box-shadow] duration-150"
                style={{ left, width: Math.max(8, w - 3), boxShadow: isSel ? "0 0 0 2.5px #fff" : "0 0 0 1px rgb(255 255 255 / 0.15)", background: "rgb(255 255 255 / 0.08)" }}
                onClick={(e) => { e.stopPropagation(); if (!isSel) { feedback("tap"); onSelect(i); } seekFromEvent(e); }}
              >
                <div className="absolute inset-0 flex">
                  {inside.map((f) => <img key={f.t} src={f.src} alt="" draggable={false} className="h-full w-auto object-cover flex-shrink-0 opacity-90" />)}
                </div>
                <span className="absolute left-1 top-1 px-1 rounded text-[10px] font-bold bg-black/50">{clipLength(c).toFixed(1)}s</span>
                {isSel && (
                  <>
                    <button type="button" onPointerDown={onEdgeDown(i, "start")} className="absolute left-0 inset-y-0 w-4 bg-white flex items-center justify-center cursor-ew-resize" style={{ touchAction: "none" }} aria-label="Trim clip start"><span className="w-0.5 h-5 rounded bg-neutral-400" /></button>
                    <button type="button" onPointerDown={onEdgeDown(i, "end")} className="absolute right-0 inset-y-0 w-4 bg-white flex items-center justify-center cursor-ew-resize" style={{ touchAction: "none" }} aria-label="Trim clip end"><span className="w-0.5 h-5 rounded bg-neutral-400" /></button>
                  </>
                )}
              </div>
            );
          })}
          <div className="absolute top-0 bottom-0 w-0.5 rounded-full bg-[#ff4d7d] pointer-events-none" style={{ left: time * pxPerSec + 12, boxShadow: "0 0 6px #ff4d7d" }}>
            <span className="absolute -top-1 -left-[5px] w-3 h-3 rounded-full bg-[#ff4d7d]" />
          </div>
        </div>
      </div>
      <div className="flex justify-center gap-1.5">
        <button onClick={split} className="flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-bold bg-white text-[#2a1620] active:scale-95 transition-transform"><Scissors className="w-4 h-4" /> Split</button>
        <button onClick={() => act(() => { onChange(removeClip(clips, sel)); onSelect(Math.max(0, sel - 1)); })} disabled={clips.length < 2} className="flex items-center gap-1.5 px-3 py-2 rounded-full text-xs font-bold disabled:opacity-35 active:scale-95 transition-transform" style={{ background: "rgb(255 255 255 / 0.12)" }}><Trash2 className="w-4 h-4" /> Delete</button>
        <button onClick={() => act(() => { const next = duplicateClip(clips, sel); if (totalLength(next) <= maxLength + 0.01) { onChange(next); onSelect(sel + 1); } })} className="flex items-center gap-1.5 px-3 py-2 rounded-full text-xs font-bold active:scale-95 transition-transform" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Duplicate clip"><Copy className="w-4 h-4" /> Copy</button>
        <button onClick={() => act(() => { onChange(moveClip(clips, sel, -1)); onSelect(Math.max(0, sel - 1)); })} disabled={sel === 0} className="w-9 h-9 rounded-full flex items-center justify-center disabled:opacity-35 active:scale-95 transition-transform" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Move clip earlier"><ArrowLeft className="w-4 h-4" /></button>
        <button onClick={() => act(() => { onChange(moveClip(clips, sel, 1)); onSelect(Math.min(clips.length - 1, sel + 1)); })} disabled={sel >= clips.length - 1} className="w-9 h-9 rounded-full flex items-center justify-center disabled:opacity-35 active:scale-95 transition-transform" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Move clip later"><ArrowRight className="w-4 h-4" /></button>
      </div>
    </div>
  );
}
