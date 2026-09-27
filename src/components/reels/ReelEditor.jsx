import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, Check, Gauge, ImageIcon, Music2, Pause, Play, Plus, Redo2, RotateCw, Scissors, Sparkles, Trash2, Type, Undo2, Volume2, VolumeX, X } from "lucide-react";
import { filterCss } from "@/lib/filters";
import { feedback } from "@/lib/feedback";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useMediaSrc } from "@/lib/media";
import { clipsOf, locate, totalLength } from "@/lib/clips";
import FilterLayers from "@/components/media/FilterLayers";
import FilterStrip from "@/components/media/FilterStrip";
import RangeSlider from "@/components/media/RangeSlider";
import ClipTimeline from "./ClipTimeline";
import { STICKER_ANIMS, STICKER_COLORS, STICKER_FONTS, STICKER_STYLES, StickerView, normalizeSticker } from "./Sticker";
import { MAX_SECONDS } from "./ReelCamera";
import { photoDuration, slideAt } from "@/lib/slideshow";
import ReelMusicPicker from "./ReelMusicPicker";

const SPEEDS = [0.5, 1, 1.5, 2];
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// Undo / redo. Live changes (a finger still moving) replace the current
// state; the next normal change saves the step.
function useHistory(initial) {
  // `base` is the state from before the live change that's still going on.
  const [h, setH] = useState({ past: [], present: initial, future: [], base: null });
  const set = useCallback((updater, { live = false } = {}) => {
    setH((cur) => {
      const next = typeof updater === "function" ? updater(cur.present) : updater;
      if (live) return { ...cur, present: next, base: cur.base ?? cur.present };
      const base = cur.base ?? cur.present;
      if (base === next) return { ...cur, present: next, base: null };
      return { past: [...cur.past.slice(-50), base], present: next, future: [], base: null };
    });
  }, []);
  const undo = useCallback(() => setH((cur) => {
    // An unfinished live change is undone first.
    if (cur.base && cur.base !== cur.present) return { past: cur.past, present: cur.base, future: [cur.present, ...cur.future], base: null };
    if (!cur.past.length) return cur.base ? { ...cur, base: null } : cur;
    return { past: cur.past.slice(0, -1), present: cur.past[cur.past.length - 1], future: [cur.present, ...cur.future], base: null };
  }), []);
  const redo = useCallback(() => setH((cur) => (cur.future.length ? { past: [...cur.past, cur.base ?? cur.present], present: cur.future[0], future: cur.future.slice(1), base: null } : cur)), []);
  return { state: h.present, set, undo, redo, canUndo: h.past.length > 0 || (!!h.base && h.base !== h.present), canRedo: h.future.length > 0 };
}

function MusicRow({ track, selected, onPick }) {
  return (
    <button onClick={onPick} className="w-full flex items-center gap-3 p-2 rounded-xl text-left transition-colors active:scale-[0.98]" style={{ background: selected ? "rgb(255 255 255 / 0.14)" : "transparent" }}>
      <span className="w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 overflow-hidden" style={{ background: "rgb(255 255 255 / 0.1)" }}>
        {track.cover_url ? <img src={track.cover_url} alt="" className="w-full h-full object-cover" /> : <Music2 className="w-4 h-4" />}
      </span>
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-bold truncate">{track.title}</span>
        <span className="block text-xs opacity-60 truncate">{track.user_display_name}{track.genre ? ` · ${track.genre}` : ""}</span>
      </span>
      {selected && <Check className="w-5 h-5 flex-shrink-0" style={{ color: "#ff4d7d" }} />}
    </button>
  );
}

function Chips({ items, value, onPick, render }) {
  return (
    <div className="flex gap-2 overflow-x-auto no-scrollbar -mx-1 px-1 py-0.5">
      {items.map((it) => {
        const on = it.id === value;
        return (
          <button key={it.id} onClick={() => { if (!on) feedback("tap"); onPick(it.id); }} className="flex-shrink-0 px-3.5 py-2 rounded-full text-xs font-bold transition-all active:scale-95" style={{ background: on ? "#fff" : "rgb(255 255 255 / 0.12)", color: on ? "#2a1620" : "#fff" }} aria-pressed={on}>
            {render ? render(it) : it.label}
          </button>
        );
      })}
    </div>
  );
}

// Edits are saved with the reel and applied when it plays (nothing is
// re-encoded, so editing is instant and works on every phone).
export default function ReelEditor({ media, initial, onChange, onBack, onNext }) {
  const isVideo = media.kind === "video";
  const { state, set, undo, redo, canUndo, canRedo } = useHistory(initial);
  const { edits, music, coverTime } = state;
  const clips = useMemo(() => (isVideo ? clipsOf(edits, media.duration) : []), [isVideo, edits, media.duration]);
  const total = isVideo ? totalLength(clips) : photoDuration(media.photos?.length || 1);
  const [tool, setTool] = useState(isVideo ? "cuts" : "filters");
  const [playing, setPlaying] = useState(true);
  const [time, setTime] = useState(0);
  const [selectedClip, setSelectedClip] = useState(0);
  const [selected, setSelected] = useState(null);
  const [textTab, setTextTab] = useState("font");
  const [editingText, setEditingText] = useState(false);
  const [guides, setGuides] = useState({ x: false, y: false });
  const [trashHot, setTrashHot] = useState(false);
  const [dragging, setDragging] = useState(false);
  const videoRef = useRef(null);
  const audioRef = useRef(null);
  const stageRef = useRef(null);
  const inputRef = useRef(null);
  const clipIndex = useRef(0);
  const timeRef = useRef(0);
  const musicSrc = useMediaSrc(music?.url || "");
  const { data: tracks } = useLiveQuery("MusicReview", null, { sort: "-created_date", limit: 40, live: false, enabled: tool === "sound" });

  useEffect(() => { onChange?.(state); }, [state]); // eslint-disable-line react-hooks/exhaustive-deps
  const setEdits = (fn, opts) => set((s) => ({ ...s, edits: typeof fn === "function" ? fn(s.edits) : { ...s.edits, ...fn } }), opts);
  const setClips = (next, opts) => setEdits((e) => ({ ...e, clips: next, trim_start: next[0]?.start || 0, trim_end: next[next.length - 1]?.end || 0 }), opts);

  // ---------- preview playback (follows the cuts) ----------
  const seek = useCallback((t) => {
    const v = videoRef.current;
    t = clamp(t, 0, Math.max(0, total - 0.02));
    timeRef.current = t;
    setTime(t);
    if (!v || !isVideo) return;
    const { index, source } = locate(clips, t);
    clipIndex.current = index;
    try { v.currentTime = source; } catch { /* not ready */ }
  }, [clips, total, isVideo]);

  useEffect(() => {
    const v = videoRef.current;
    if (v) {
      v.playbackRate = edits.speed || 1;
      v.muted = !!edits.muted;
      if (playing && tool !== "cover" && !dragging) v.play().catch(() => {}); else v.pause();
    }
    const a = audioRef.current;
    if (a) { if (playing && tool !== "cover") a.play().catch(() => {}); else a.pause(); }
  }, [playing, edits.speed, edits.muted, tool, dragging, musicSrc]);

  useEffect(() => {
    let raf;
    let last = performance.now();
    let lastUi = 0;
    const tick = (now) => {
      const v = videoRef.current;
      if (isVideo && v && clips.length) {
        let i = Math.min(clipIndex.current, clips.length - 1);
        const c = clips[i];
        if (v.currentTime < c.start - 0.25 || v.currentTime > c.end + 0.25) {
          const f = clips.findIndex((k) => v.currentTime >= k.start - 0.05 && v.currentTime < k.end);
          if (f >= 0) i = clipIndex.current = f; else { clipIndex.current = 0; v.currentTime = clips[0].start; }
        } else if (!v.paused && (v.currentTime >= c.end - 0.03 || v.ended)) {
          if (i + 1 < clips.length) { i = clipIndex.current = i + 1; if (Math.abs(v.currentTime - clips[i].start) > 0.08) v.currentTime = clips[i].start; }
          else { clipIndex.current = 0; v.currentTime = clips[0].start; }
          if (v.paused && playing) v.play().catch(() => {});
        }
        let out = 0;
        for (let k = 0; k < clipIndex.current; k++) out += clips[k].end - clips[k].start;
        timeRef.current = out + Math.max(0, v.currentTime - clips[clipIndex.current].start);
      } else if (!isVideo && playing) {
        timeRef.current = (timeRef.current + (now - last) / 1000) % total;
      }
      last = now;
      if (now - lastUi > 70) { lastUi = now; setTime(timeRef.current); }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [isVideo, clips, playing, total]);

  useEffect(() => { if (tool === "cover") seek(coverTime || 0); }, [tool, coverTime]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- text stickers ----------
  const texts = (edits.text || []).map(normalizeSticker);
  const current = texts.find((t) => t.id === selected);
  const setTexts = (fn, opts) => setEdits((e) => ({ ...e, text: fn((e.text || []).map(normalizeSticker)) }), opts);
  const patchSticker = (id, patch, opts) => setTexts((list) => list.map((t) => (t.id === id ? { ...t, ...patch } : t)), opts);
  const addText = () => {
    const id = `t${Date.now().toString(36)}`;
    setTexts((list) => [...list, { id, text: "Tap to edit", x: 0.5, y: clamp(0.4 + list.length * 0.09, 0.15, 0.85), size: 0.08, rot: 0, color: "#ffffff", font: "sans", style: "plain", anim: "pop" }]);
    setSelected(id);
    setTool("text");
    setTextTab("font");
    setEditingText(true);
    feedback("tap");
  };
  const deleteSticker = (id) => { setTexts((list) => list.filter((t) => t.id !== id)); setSelected(null); setEditingText(false); feedback("error"); };
  useEffect(() => { if (editingText) setTimeout(() => { inputRef.current?.focus(); inputRef.current?.select(); }, 60); }, [editingText, selected]);

  // Gestures on the preview: drag to move, pinch to resize, twist to rotate,
  // the corner handle does both with one finger, drag onto the bin to delete.
  const pointers = useRef(new Map());
  const g = useRef(null);
  const stagePoint = (e) => {
    const r = stageRef.current.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top, w: r.width, h: r.height };
  };
  const startPinch = () => {
    const [a, b] = [...pointers.current.values()];
    const s = texts.find((t) => t.id === g.current?.id);
    if (!a || !b || !s) return;
    g.current = { mode: "pinch", id: s.id, dist: Math.hypot(b.x - a.x, b.y - a.y), angle: Math.atan2(b.y - a.y, b.x - a.x), mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, orig: s, moved: true };
  };
  const onStageDown = (e) => {
    const p = stagePoint(e);
    pointers.current.set(e.pointerId, p);
    try { stageRef.current.setPointerCapture(e.pointerId); } catch { /* synthetic or already released */ }
    const handle = e.target.closest("[data-handle]");
    const el = e.target.closest("[data-edit-sticker]");
    if (pointers.current.size === 2 && g.current?.id) { startPinch(); return; }
    if (handle && current) {
      const cx = current.x * p.w, cy = current.y * p.h;
      g.current = { mode: handle.dataset.handle, id: current.id, cx, cy, dist: Math.hypot(p.x - cx, p.y - cy), angle: Math.atan2(p.y - cy, p.x - cx), orig: current, moved: true };
      return;
    }
    if (el) {
      const id = el.dataset.editSticker;
      const s = texts.find((t) => t.id === id);
      const wasSelected = selected === id;
      setSelected(id);
      setTool("text");
      g.current = { mode: "drag", id, start: p, orig: s, moved: false, t: performance.now(), wasSelected };
      return;
    }
    g.current = { mode: "tap", start: p, moved: false, t: performance.now() };
  };
  const onStageMove = (e) => {
    if (!pointers.current.has(e.pointerId)) return;
    const p = stagePoint(e);
    pointers.current.set(e.pointerId, p);
    const G = g.current;
    if (!G) return;
    if (G.mode === "tap" || G.mode === "drag") {
      if (Math.hypot(p.x - G.start.x, p.y - G.start.y) > 6) G.moved = true;
    }
    if (G.mode === "drag" && G.moved) {
      if (!dragging) setDragging(true);
      let x = clamp(G.orig.x + (p.x - G.start.x) / p.w, 0.03, 0.97);
      let y = clamp(G.orig.y + (p.y - G.start.y) / p.h, 0.03, 0.97);
      const snapX = Math.abs(x - 0.5) < 0.025, snapY = Math.abs(y - 0.5) < 0.02;
      if (snapX) x = 0.5;
      if (snapY) y = 0.5;
      if ((snapX && !guides.x) || (snapY && !guides.y)) feedback("tap");
      if (snapX !== guides.x || snapY !== guides.y) setGuides({ x: snapX, y: snapY });
      const hot = p.y > p.h - 90 && Math.abs(p.x - p.w / 2) < 60;
      if (hot !== trashHot) { setTrashHot(hot); if (hot) feedback("toggle"); }
      patchSticker(G.id, { x, y }, { live: true });
    } else if (G.mode === "pinch") {
      const [a, b] = [...pointers.current.values()];
      if (!a || !b) return;
      const dist = Math.hypot(b.x - a.x, b.y - a.y);
      let rot = G.orig.rot + ((Math.atan2(b.y - a.y, b.x - a.x) - G.angle) * 180) / Math.PI;
      const snapped = Math.round(rot / 90) * 90;
      if (Math.abs(rot - snapped) < 4) rot = snapped;
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      patchSticker(G.id, {
        size: clamp(G.orig.size * (dist / Math.max(1, G.dist)), 0.03, 0.32),
        rot: Math.round(rot * 10) / 10,
        x: clamp(G.orig.x + (mid.x - G.mid.x) / p.w, 0.03, 0.97),
        y: clamp(G.orig.y + (mid.y - G.mid.y) / p.h, 0.03, 0.97),
      }, { live: true });
    } else if (G.mode === "rotate") {
      const dist = Math.hypot(p.x - G.cx, p.y - G.cy);
      let rot = G.orig.rot + ((Math.atan2(p.y - G.cy, p.x - G.cx) - G.angle) * 180) / Math.PI;
      const snapped = Math.round(rot / 90) * 90;
      if (Math.abs(rot - snapped) < 4) rot = snapped;
      patchSticker(G.id, { size: clamp(G.orig.size * (dist / Math.max(1, G.dist)), 0.03, 0.32), rot: Math.round(rot * 10) / 10 }, { live: true });
    }
  };
  const onStageUp = (e) => {
    pointers.current.delete(e.pointerId);
    const G = g.current;
    if (!G) return;
    if (pointers.current.size > 0) {
      // One finger lifted: the pinch is over (the other finger does nothing more).
      if (G.mode === "pinch") { g.current = null; set((s) => s); feedback("tap"); }
      return;
    }
    g.current = null;
    setDragging(false);
    setGuides({ x: false, y: false });
    if (G.mode === "drag" && G.moved && trashHot) { setTrashHot(false); deleteSticker(G.id); return; }
    setTrashHot(false);
    if (G.mode === "drag" && !G.moved) {
      if (G.wasSelected) setEditingText(true); // tap a selected sticker to type
      return;
    }
    if (G.mode === "tap" && !G.moved) {
      if (selected) { setSelected(null); setEditingText(false); } else setPlaying((v) => !v);
      return;
    }
    set((s) => s); // commit the gesture as one undo step
    if (G.moved) feedback("tap");
  };

  const TOOLS = [
    ...(isVideo ? [{ id: "cuts", label: "Cuts", icon: Scissors }] : []),
    { id: "text", label: "Text", icon: Type },
    { id: "filters", label: "Filters", icon: Sparkles },
    ...(isVideo ? [{ id: "speed", label: "Speed", icon: Gauge }] : []),
    { id: "sound", label: "Sound", icon: Music2 },
    ...(isVideo ? [{ id: "cover", label: "Cover", icon: ImageIcon }] : []),
  ];

  return (
    <div className="absolute inset-0 flex flex-col bg-black text-white">
      {/* header */}
      <div className="flex items-center gap-2 px-3 pt-[calc(env(safe-area-inset-top)+0.5rem)] pb-2">
        <button onClick={onBack} className="w-10 h-10 rounded-full flex items-center justify-center active:scale-90 transition-transform" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Back to camera"><ArrowLeft className="w-5 h-5" /></button>
        <div className="flex-1 flex justify-center gap-1">
          <button onClick={() => { feedback("tap"); undo(); }} disabled={!canUndo} className="w-10 h-10 rounded-full flex items-center justify-center disabled:opacity-30 active:scale-90 transition-transform" aria-label="Undo"><Undo2 className="w-5 h-5" /></button>
          <button onClick={() => { feedback("tap"); redo(); }} disabled={!canRedo} className="w-10 h-10 rounded-full flex items-center justify-center disabled:opacity-30 active:scale-90 transition-transform" aria-label="Redo"><Redo2 className="w-5 h-5" /></button>
        </div>
        <button onClick={() => { feedback("tap"); setPlaying(false); onNext(); }} className="btn !min-h-0 !py-2 !px-5">Next</button>
      </div>

      {/* preview */}
      <div className="flex-1 min-h-0 flex items-center justify-center px-4">
        <div
          ref={stageRef}
          className="relative h-full max-h-full aspect-[9/16] max-w-full rounded-2xl overflow-hidden bg-neutral-900"
          style={{ containerType: "inline-size", touchAction: "none" }}
          onPointerDown={onStageDown}
          onPointerMove={onStageMove}
          onPointerUp={onStageUp}
          onPointerCancel={onStageUp}
        >
          {isVideo ? (
            <video ref={videoRef} src={media.url} playsInline autoPlay muted={!!edits.muted}
              className="absolute inset-0 w-full h-full object-cover pointer-events-none" style={{ filter: filterCss(edits.filter), transform: edits.mirror ? "scaleX(-1)" : undefined }} />
          ) : (
            <img src={media.photos?.[slideAt(time, media.photos.length)]?.url || media.url} alt="" draggable={false} className="absolute inset-0 w-full h-full object-cover pointer-events-none" style={{ filter: filterCss(edits.filter) }} />
          )}
          <FilterLayers filter={edits.filter} />
          {/* centre guides */}
          {guides.x && <span className="absolute inset-y-0 left-1/2 w-px bg-[#ff4d7d]/80 pointer-events-none" />}
          {guides.y && <span className="absolute inset-x-0 top-1/2 h-px bg-[#ff4d7d]/80 pointer-events-none" />}
          {texts.map((t) => {
            const inTime = !isVideo || ((t.from ?? -1) <= time && time <= (t.to ?? Infinity));
            const isSel = selected === t.id;
            return (
              <StickerView
                key={t.id}
                sticker={t}
                data-edit-sticker={t.id}
                className="cursor-move"
                style={{ opacity: inTime || isSel ? 1 : 0.35, zIndex: isSel ? 5 : 1, transition: "opacity .2s" }}
              >
                {isSel && (
                  <>
                    <span className="absolute -inset-2 rounded-lg pointer-events-none" style={{ border: "1.5px dashed rgb(255 255 255 / 0.9)" }} />
                    <span data-handle="rotate" className="absolute -right-4 -bottom-4 w-8 h-8 rounded-full bg-white text-[#2a1620] flex items-center justify-center shadow-lg" style={{ transform: `rotate(${-t.rot}deg)` }} aria-label="Resize and rotate"><RotateCw className="w-4 h-4" /></span>
                    <button type="button" onPointerDown={(e) => e.stopPropagation()} onClick={(e) => { e.stopPropagation(); deleteSticker(t.id); }} className="absolute -left-4 -top-4 w-7 h-7 rounded-full bg-white text-[#2a1620] flex items-center justify-center shadow-lg" style={{ transform: `rotate(${-t.rot}deg)` }} aria-label="Delete text"><X className="w-4 h-4" /></button>
                  </>
                )}
              </StickerView>
            );
          })}
          {/* bin */}
          <AnimatePresence>
            {dragging && (
              <motion.span initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0, scale: trashHot ? 1.2 : 1 }} exit={{ opacity: 0, y: 20 }} className="absolute left-1/2 bottom-5 -ml-7 w-14 h-14 rounded-full flex items-center justify-center pointer-events-none" style={{ background: trashHot ? "#ef4444" : "rgb(0 0 0 / 0.55)", border: "2px solid rgb(255 255 255 / 0.6)" }}>
                <Trash2 className="w-6 h-6" />
              </motion.span>
            )}
          </AnimatePresence>
          {!playing && !dragging && tool !== "text" && tool !== "cover" && (
            <span className="absolute left-1/2 top-1/2 -ml-8 -mt-8 w-16 h-16 rounded-full flex items-center justify-center pointer-events-none enter-pop" style={{ background: "rgb(0 0 0 / 0.4)" }}><Play className="w-7 h-7 fill-white ml-1" /></span>
          )}
          {musicSrc && <audio ref={audioRef} src={musicSrc} loop autoPlay />}
          {/* progress */}
          <div className="absolute inset-x-3 bottom-2 h-1 rounded-full pointer-events-none" style={{ background: "rgb(255 255 255 / 0.25)" }}>
            <div className="h-full rounded-full bg-white" style={{ width: `${(time / Math.max(0.1, total)) * 100}%` }} />
          </div>
        </div>
      </div>

      {/* tool panel */}
      <div className="flex-shrink-0 px-4 pt-3 min-h-[150px]">
        <AnimatePresence mode="wait" initial={false}>
          <motion.div key={tool + (tool === "text" ? (current ? "-sel" : "-none") : "")} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.16 }}>
            {tool === "cuts" && isVideo && (
              <ClipTimeline
                url={media.url} sourceDuration={media.duration} clips={clips} maxLength={MAX_SECONDS}
                onChange={(next, opts) => setClips(next, opts)}
                time={time} onSeek={(t) => { setPlaying(false); seek(t); }}
                selected={selectedClip} onSelect={setSelectedClip}
              />
            )}
            {tool === "filters" && <FilterStrip thumb={media.kind === "photo" ? media.url : media.thumb} value={edits.filter || "none"} onChange={(id) => setEdits({ filter: id })} dark />}
            {tool === "text" && (current ? (
              <div className="space-y-2.5">
                <div className="flex gap-2">
                  <input
                    ref={inputRef}
                    className="flex-1 min-w-0 rounded-xl px-3 py-2.5 text-[16px] font-semibold outline-none"
                    style={{ background: "rgb(255 255 255 / 0.12)", color: "#fff" }}
                    value={current.text}
                    maxLength={80}
                    onFocus={() => setEditingText(true)}
                    onBlur={() => { setEditingText(false); set((s) => s); }}
                    onChange={(e) => patchSticker(current.id, { text: e.target.value }, { live: true })}
                    onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
                    aria-label="Sticker text"
                  />
                  <button onClick={addText} className="w-11 rounded-xl flex items-center justify-center active:scale-90 transition-transform" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Add another text"><Plus className="w-5 h-5" /></button>
                </div>
                <div className="flex gap-1 text-[11px] font-bold">
                  {[["font", "Font"], ["style", "Style"], ["color", "Colour"], ["anim", "Animate"], ...(isVideo ? [["time", "Timing"]] : []), ["size", "Size"]].map(([id, label]) => (
                    <button key={id} onClick={() => { feedback("tap"); setTextTab(id); }} className="px-2.5 py-1.5 rounded-full transition-colors" style={{ background: textTab === id ? "rgb(255 255 255 / 0.18)" : "transparent", color: textTab === id ? "#fff" : "rgb(255 255 255 / 0.6)" }}>{label}</button>
                  ))}
                </div>
                {textTab === "font" && <Chips items={STICKER_FONTS} value={current.font} onPick={(id) => patchSticker(current.id, { font: id })} render={(f) => <span style={{ ...f.css, fontWeight: f.css.fontWeight, fontSize: 14 }}>{f.label}</span>} />}
                {textTab === "style" && <Chips items={STICKER_STYLES} value={current.style} onPick={(id) => patchSticker(current.id, { style: id })} />}
                {textTab === "anim" && <Chips items={STICKER_ANIMS} value={current.anim} onPick={(id) => patchSticker(current.id, { anim: id })} />}
                {textTab === "color" && (
                  <div className="flex items-center gap-2.5 py-1">
                    {STICKER_COLORS.map((c) => <button key={c} onClick={() => { feedback("tap"); patchSticker(current.id, { color: c }); }} className="w-8 h-8 rounded-full flex-shrink-0 transition-transform active:scale-90" style={{ background: c, boxShadow: current.color === c ? "0 0 0 2px #000, 0 0 0 4px #fff" : "0 0 0 1px rgb(255 255 255 / 0.3)" }} aria-label={`Colour ${c}`} />)}
                  </div>
                )}
                {textTab === "time" && isVideo && (
                  <RangeSlider min={0} max={Math.max(0.2, total)} from={current.from ?? 0} to={current.to ?? total} step={0.1}
                    format={(v) => `${v.toFixed(1)}s`}
                    onChange={(from, to) => patchSticker(current.id, { from: from <= 0.05 ? null : from, to: to >= total - 0.05 ? null : to }, { live: true })}
                    onCommit={() => set((s) => s)} label="When the text shows" />
                )}
                {textTab === "size" && (
                  <div className="space-y-2 py-1">
                    <label className="flex items-center gap-3 text-xs font-bold"><span className="w-12 opacity-70">Size</span><input type="range" min="0.03" max="0.32" step="0.005" value={current.size} onChange={(e) => patchSticker(current.id, { size: Number(e.target.value) }, { live: true })} onPointerUp={() => set((s) => s)} className="flex-1 range-call" aria-label="Text size" /></label>
                    <label className="flex items-center gap-3 text-xs font-bold"><span className="w-12 opacity-70">Rotate</span><input type="range" min="-180" max="180" step="1" value={current.rot} onChange={(e) => patchSticker(current.id, { rot: Number(e.target.value) }, { live: true })} onPointerUp={() => set((s) => s)} className="flex-1 range-call" aria-label="Rotation" /><span className="w-10 text-right tabular-nums">{Math.round(current.rot)}°</span></label>
                  </div>
                )}
              </div>
            ) : (
              <div className="flex flex-col items-center gap-2.5 pt-2">
                <button onClick={addText} className="btn"><Plus className="w-4 h-4" /> Add text</button>
                <p className="text-xs opacity-60 text-center">Drag to move · pinch to resize · twist to rotate<br />Tap text to edit · drag it to the bin to delete</p>
              </div>
            ))}
            {tool === "speed" && (
              <div className="flex justify-center gap-2 pt-3">
                {SPEEDS.map((s) => <button key={s} onClick={() => { feedback("tap"); setEdits({ speed: s }); }} className="px-5 py-2.5 rounded-full text-sm font-bold transition-all active:scale-95" style={{ background: (edits.speed || 1) === s ? "#fff" : "rgb(255 255 255 / 0.12)", color: (edits.speed || 1) === s ? "#2a1620" : "#fff" }}>{s}x</button>)}
              </div>
            )}
            {tool === "sound" && (
              <div className="space-y-2">
                {isVideo && (
                  <button onClick={() => { feedback("toggle"); setEdits({ muted: !edits.muted }); }} className="w-full flex items-center gap-3 p-2.5 rounded-xl active:scale-[0.98] transition-transform" style={{ background: "rgb(255 255 255 / 0.08)" }}>
                    {edits.muted ? <VolumeX className="w-5 h-5" /> : <Volume2 className="w-5 h-5" />}
                    <span className="flex-1 text-left text-sm font-bold">Original sound</span>
                    <span className="text-xs font-bold opacity-70">{edits.muted ? "Off" : "On"}</span>
                  </button>
                )}
                <ReelMusicPicker selected={music} onPick={(music) => { set((s) => ({ ...s, music })); setPlaying(true); }} />
                <div className="max-h-40 overflow-y-auto no-scrollbar space-y-1">
                  <button onClick={() => set((s) => ({ ...s, music: null }))} className="w-full flex items-center gap-3 p-2 rounded-xl text-left" style={{ background: !music ? "rgb(255 255 255 / 0.14)" : "transparent" }}>
                    <span className="w-10 h-10 rounded-lg flex items-center justify-center" style={{ background: "rgb(255 255 255 / 0.1)" }}><VolumeX className="w-4 h-4" /></span>
                    <span className="flex-1 text-sm font-bold">No music</span>
                    {!music && <Check className="w-5 h-5" style={{ color: "#ff4d7d" }} />}
                  </button>
                  {tracks.map((t) => <MusicRow key={t.id} track={t} selected={music?.url === t.music_url} onPick={() => { feedback("tap"); set((s) => ({ ...s, music: { url: t.music_url, title: t.title, artist: t.user_display_name } })); setPlaying(true); }} />)}
                </div>
              </div>
            )}
            {tool === "cover" && isVideo && (
              <div className="space-y-2 pt-1">
                <p className="text-xs font-bold opacity-70 text-center">Slide to choose the cover frame</p>
                <input type="range" min={0} max={Math.max(0.1, total - 0.05)} step="0.05" value={coverTime || 0} onChange={(e) => set((s) => ({ ...s, coverTime: Number(e.target.value) }), { live: true })} onPointerUp={() => set((s) => s)} className="w-full range-call" aria-label="Cover frame" />
              </div>
            )}
          </motion.div>
        </AnimatePresence>
      </div>

      {/* tool tabs */}
      <div className="flex-shrink-0 flex justify-around px-2 pt-2 pb-[calc(env(safe-area-inset-bottom)+0.5rem)]">
        {TOOLS.map((t) => (
          <button key={t.id} onClick={() => { feedback("tab"); if (t.id === "text" && !texts.length) addText(); else setTool(t.id); }} className="relative flex flex-col items-center gap-1 px-2.5 py-1.5 rounded-xl text-[11px] font-bold transition-colors active:scale-90" style={{ color: tool === t.id ? "#fff" : "rgb(255 255 255 / 0.55)" }} aria-pressed={tool === t.id}>
            <span className="absolute inset-0 rounded-xl transition-all duration-200" style={{ background: "rgb(255 255 255 / 0.12)", opacity: tool === t.id ? 1 : 0, transform: `scale(${tool === t.id ? 1 : 0.7})` }} />
            <t.icon className="relative w-5 h-5" /><span className="relative">{t.label}</span>
          </button>
        ))}
        <button onClick={() => { feedback("tap"); setPlaying((p) => !p); }} className="flex flex-col items-center gap-1 px-2 py-1.5 text-[11px] font-bold active:scale-90 transition-transform" style={{ color: "rgb(255 255 255 / 0.55)" }} aria-label={playing ? "Pause preview" : "Play preview"}>
          {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5" />}{playing ? "Pause" : "Play"}
        </button>
      </div>
    </div>
  );
}

