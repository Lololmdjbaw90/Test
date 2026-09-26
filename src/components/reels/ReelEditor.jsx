import React, { useEffect, useRef, useState } from "react";
import { ArrowLeft, Check, Gauge, ImageIcon, Music2, Pause, Play, Plus, Scissors, Sparkles, Trash2, Type, Volume2, VolumeX } from "lucide-react";
import { filterCss } from "@/lib/filters";
import { feedback } from "@/lib/feedback";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { useMediaSrc } from "@/lib/media";
import FilterLayers from "@/components/media/FilterLayers";
import FilterStrip from "@/components/media/FilterStrip";
import TrimBar from "./TrimBar";
import { MAX_SECONDS } from "./ReelCamera";

const COLORS = ["#ffffff", "#2a1620", "#ff4d7d", "#ffd35c", "#7ce0b8", "#7cbeff", "#b58be0", "#ff9f6b"];
const SPEEDS = [0.5, 1, 1.5, 2];

function MusicRow({ track, selected, onPick }) {
  return (
    <button onClick={onPick} className="w-full flex items-center gap-3 p-2 rounded-xl text-left transition-colors" style={{ background: selected ? "rgb(255 255 255 / 0.14)" : "transparent" }}>
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

// Edits are saved with the reel and applied when it plays (nothing is
// re-encoded, so editing is instant and works on every phone).
export default function ReelEditor({ media, edits, setEdits, music, setMusic, coverTime, setCoverTime, onBack, onNext }) {
  const isVideo = media.kind === "video";
  const [tool, setTool] = useState("filters");
  const [playing, setPlaying] = useState(true);
  const [selected, setSelected] = useState(null);
  const [playhead, setPlayhead] = useState(0);
  const videoRef = useRef(null);
  const audioRef = useRef(null);
  const frameRef = useRef(null);
  const dragging = useRef(null);
  const musicSrc = useMediaSrc(music?.url || "");
  const { data: tracks } = useLiveQuery("MusicReview", null, { sort: "-created_date", limit: 40, live: false });
  const duration = media.duration || 0;
  const trimEnd = edits.trim_end || Math.min(duration, MAX_SECONDS);
  const set = (patch) => setEdits((e) => ({ ...e, ...patch }));

  // Preview playback inside the trim window.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.playbackRate = edits.speed || 1;
    v.muted = !!edits.muted;
    if (playing && tool !== "cover") v.play().catch(() => {}); else v.pause();
  }, [playing, edits.speed, edits.muted, tool]);
  useEffect(() => {
    const a = audioRef.current;
    if (!a) return;
    if (playing) a.play().catch(() => {}); else a.pause();
  }, [playing, musicSrc]);
  useEffect(() => { if (tool === "cover" && videoRef.current) videoRef.current.currentTime = coverTime; }, [tool, coverTime]);
  const onTime = () => {
    const v = videoRef.current;
    if (!v || tool === "cover") return;
    setPlayhead(v.currentTime);
    if (v.currentTime >= trimEnd - 0.05 || v.currentTime < (edits.trim_start || 0) - 0.2) v.currentTime = edits.trim_start || 0;
  };

  // ---------- text stickers ----------
  const texts = edits.text || [];
  const setTexts = (fn) => setEdits((e) => ({ ...e, text: fn(e.text || []) }));
  const current = texts.find((t) => t.id === selected);
  const addText = () => {
    const id = `t${Date.now().toString(36)}`;
    setTexts((list) => [...list, { id, text: "Your text", x: 0.5, y: 0.4 + list.length * 0.08, color: "#ffffff", bg: "", size: 0.075 }]);
    setSelected(id);
    setTool("text");
    feedback("tap");
  };
  const patchText = (patch) => setTexts((list) => list.map((t) => (t.id === selected ? { ...t, ...patch } : t)));
  const onStickerDown = (id) => (e) => {
    e.stopPropagation();
    setSelected(id);
    setTool("text");
    dragging.current = { id, moved: false };
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };
  const onFrameMove = (e) => {
    const d = dragging.current;
    if (!d || !frameRef.current) return;
    const r = frameRef.current.getBoundingClientRect();
    const x = Math.max(0.05, Math.min(0.95, (e.clientX - r.left) / r.width));
    const y = Math.max(0.05, Math.min(0.95, (e.clientY - r.top) / r.height));
    d.moved = true;
    setTexts((list) => list.map((t) => (t.id === d.id ? { ...t, x, y } : t)));
  };
  const onFrameUp = () => { dragging.current = null; };

  const TOOLS = [
    { id: "filters", label: "Filters", icon: Sparkles },
    ...(isVideo ? [{ id: "trim", label: "Trim", icon: Scissors }] : []),
    { id: "text", label: "Text", icon: Type },
    ...(isVideo ? [{ id: "speed", label: "Speed", icon: Gauge }] : []),
    { id: "sound", label: "Sound", icon: Music2 },
    ...(isVideo ? [{ id: "cover", label: "Cover", icon: ImageIcon }] : []),
  ];

  return (
    <div className="absolute inset-0 flex flex-col bg-black text-white">
      <div className="flex items-center justify-between px-3 pt-[calc(env(safe-area-inset-top)+0.5rem)] pb-2">
        <button onClick={onBack} className="w-10 h-10 rounded-full flex items-center justify-center" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Back to camera"><ArrowLeft className="w-5 h-5" /></button>
        <span className="font-display text-lg">Edit</span>
        <button onClick={() => { feedback("tap"); onNext(); }} className="btn !min-h-0 !py-2">Next</button>
      </div>

      {/* preview */}
      <div className="flex-1 min-h-0 flex items-center justify-center px-4">
        <div
          ref={frameRef}
          className="relative h-full max-h-full aspect-[9/16] max-w-full rounded-2xl overflow-hidden bg-neutral-900 touch-none"
          style={{ containerType: "inline-size" }}
          onPointerMove={onFrameMove}
          onPointerUp={onFrameUp}
          onPointerCancel={onFrameUp}
          onClick={() => { if (tool !== "text") setPlaying((p) => !p); else setSelected(null); }}
        >
          {isVideo ? (
            <video ref={videoRef} src={media.url} playsInline autoPlay loop={false} onTimeUpdate={onTime} onEnded={() => { const v = videoRef.current; if (v) { v.currentTime = edits.trim_start || 0; v.play().catch(() => {}); } }}
              className="absolute inset-0 w-full h-full object-cover" style={{ filter: filterCss(edits.filter), transform: edits.mirror ? "scaleX(-1)" : undefined }} />
          ) : (
            <img src={media.url} alt="" className="absolute inset-0 w-full h-full object-cover" style={{ filter: filterCss(edits.filter) }} />
          )}
          <FilterLayers filter={edits.filter} />
          {texts.map((t) => (
            <span
              key={t.id}
              onPointerDown={onStickerDown(t.id)}
              onClick={(e) => e.stopPropagation()}
              className="absolute text-center font-bold leading-tight whitespace-pre-wrap max-w-[86%] cursor-move"
              style={{
                left: `${t.x * 100}%`, top: `${t.y * 100}%`, translate: "-50% -50%",
                fontSize: `${t.size * 100}cqw`, color: t.color, background: t.bg || "transparent",
                padding: t.bg ? "0.2em 0.55em" : 0, borderRadius: "0.45em",
                textShadow: t.bg ? "none" : "0 2px 8px rgb(0 0 0 / 0.55)",
                outline: selected === t.id ? "2px dashed rgb(255 255 255 / 0.8)" : "none", outlineOffset: 4,
              }}
            >
              {t.text || " "}
            </span>
          ))}
          {!playing && tool !== "text" && <span className="absolute left-1/2 top-1/2 -ml-8 -mt-8 w-16 h-16 rounded-full flex items-center justify-center pointer-events-none" style={{ background: "rgb(0 0 0 / 0.4)" }}><Play className="w-7 h-7 fill-white ml-1" /></span>}
          {musicSrc && <audio ref={audioRef} src={musicSrc} loop autoPlay />}
        </div>
      </div>

      {/* tool panel */}
      <div className="flex-shrink-0 px-4 pt-3 min-h-[128px]">
        {tool === "filters" && <FilterStrip thumb={media.kind === "photo" ? media.url : media.thumb} value={edits.filter || "none"} onChange={(id) => set({ filter: id })} dark />}
        {tool === "trim" && isVideo && (
          <TrimBar url={media.url} duration={duration} start={edits.trim_start || 0} end={trimEnd} playhead={playhead} maxSpan={MAX_SECONDS}
            onChange={(s, e) => { set({ trim_start: s, trim_end: e }); if (videoRef.current) videoRef.current.currentTime = s; }} />
        )}
        {tool === "text" && (
          current ? (
            <div className="space-y-3">
              <div className="flex gap-2">
                <input className="flex-1 min-w-0 rounded-xl px-3 py-2.5 text-[16px] font-semibold outline-none" style={{ background: "rgb(255 255 255 / 0.12)", color: "#fff" }} value={current.text} maxLength={80} onChange={(e) => patchText({ text: e.target.value })} aria-label="Sticker text" autoFocus />
                <button onClick={() => patchText({ bg: current.bg ? "" : current.color === "#ffffff" ? "rgba(217,87,127,0.9)" : "rgba(255,255,255,0.92)", color: current.bg ? current.color : current.color === "#ffffff" ? "#ffffff" : current.color })} className="px-3 rounded-xl text-xs font-bold" style={{ background: current.bg ? "#fff" : "rgb(255 255 255 / 0.12)", color: current.bg ? "#2a1620" : "#fff" }} aria-pressed={!!current.bg}>Aa</button>
                <button onClick={() => { setTexts((l) => l.filter((t) => t.id !== selected)); setSelected(null); feedback("tap"); }} className="w-11 rounded-xl flex items-center justify-center" style={{ background: "rgb(255 255 255 / 0.12)" }} aria-label="Delete text"><Trash2 className="w-4 h-4" /></button>
              </div>
              <div className="flex items-center gap-2">
                {COLORS.map((c) => <button key={c} onClick={() => patchText({ color: c })} className="w-7 h-7 rounded-full flex-shrink-0" style={{ background: c, boxShadow: current.color === c ? "0 0 0 2px #000, 0 0 0 4px #fff" : "0 0 0 1px rgb(255 255 255 / 0.3)" }} aria-label={`Colour ${c}`} />)}
                <input type="range" min="0.045" max="0.14" step="0.005" value={current.size} onChange={(e) => patchText({ size: Number(e.target.value) })} className="flex-1 min-w-0 range-call" aria-label="Text size" />
              </div>
            </div>
          ) : (
            <div className="flex flex-col items-center gap-2 pt-2">
              <button onClick={addText} className="btn"><Plus className="w-4 h-4" /> Add text</button>
              <p className="text-xs opacity-60">Drag text to move it · tap it to edit</p>
            </div>
          )
        )}
        {tool === "speed" && (
          <div className="flex justify-center gap-2 pt-3">
            {SPEEDS.map((s) => <button key={s} onClick={() => { feedback("tap"); set({ speed: s }); }} className="px-4 py-2 rounded-full text-sm font-bold" style={{ background: (edits.speed || 1) === s ? "#fff" : "rgb(255 255 255 / 0.12)", color: (edits.speed || 1) === s ? "#2a1620" : "#fff" }}>{s}x</button>)}
          </div>
        )}
        {tool === "sound" && (
          <div className="space-y-2">
            {isVideo && (
              <button onClick={() => { feedback("toggle"); set({ muted: !edits.muted }); }} className="w-full flex items-center gap-3 p-2.5 rounded-xl" style={{ background: "rgb(255 255 255 / 0.08)" }}>
                {edits.muted ? <VolumeX className="w-5 h-5" /> : <Volume2 className="w-5 h-5" />}
                <span className="flex-1 text-left text-sm font-bold">Original sound</span>
                <span className="text-xs font-bold opacity-70">{edits.muted ? "Off" : "On"}</span>
              </button>
            )}
            <div className="max-h-40 overflow-y-auto no-scrollbar space-y-1">
              <button onClick={() => setMusic(null)} className="w-full flex items-center gap-3 p-2 rounded-xl text-left" style={{ background: !music ? "rgb(255 255 255 / 0.14)" : "transparent" }}>
                <span className="w-10 h-10 rounded-lg flex items-center justify-center" style={{ background: "rgb(255 255 255 / 0.1)" }}><VolumeX className="w-4 h-4" /></span>
                <span className="flex-1 text-sm font-bold">No music</span>
                {!music && <Check className="w-5 h-5" style={{ color: "#ff4d7d" }} />}
              </button>
              {tracks.map((t) => <MusicRow key={t.id} track={t} selected={music?.url === t.music_url} onPick={() => { feedback("tap"); setMusic({ url: t.music_url, title: t.title, artist: t.user_display_name }); setPlaying(true); }} />)}
            </div>
          </div>
        )}
        {tool === "cover" && isVideo && (
          <div className="space-y-2 pt-1">
            <p className="text-xs font-bold opacity-70 text-center">Slide to choose the cover frame</p>
            <input type="range" min={edits.trim_start || 0} max={Math.max((edits.trim_start || 0) + 0.1, trimEnd - 0.05)} step="0.05" value={coverTime} onChange={(e) => setCoverTime(Number(e.target.value))} className="w-full range-call" aria-label="Cover frame" />
          </div>
        )}
      </div>

      {/* tool tabs */}
      <div className="flex-shrink-0 flex justify-around px-2 pt-2 pb-[calc(env(safe-area-inset-bottom)+0.5rem)]">
        {TOOLS.map((t) => (
          <button key={t.id} onClick={() => { feedback("tab"); if (t.id === "text" && !texts.length) addText(); else setTool(t.id); }} className="flex flex-col items-center gap-1 px-2 py-1.5 rounded-xl text-[11px] font-bold transition-colors" style={{ color: tool === t.id ? "#fff" : "rgb(255 255 255 / 0.55)", background: tool === t.id ? "rgb(255 255 255 / 0.1)" : "transparent" }} aria-pressed={tool === t.id}>
            <t.icon className="w-5 h-5" />{t.label}
          </button>
        ))}
        <button onClick={() => setPlaying((p) => !p)} className="flex flex-col items-center gap-1 px-2 py-1.5 text-[11px] font-bold" style={{ color: "rgb(255 255 255 / 0.55)" }} aria-label={playing ? "Pause preview" : "Play preview"}>
          {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5" />}{playing ? "Pause" : "Play"}
        </button>
      </div>
    </div>
  );
}
