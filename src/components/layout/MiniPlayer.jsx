import React from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Music2, Pause, Play, SkipBack, SkipForward, Volume2, VolumeX, X } from "lucide-react";
import { formatTime, usePlayer, usePlayerProgress } from "@/lib/player";

// Floating player that keeps the current track going across pages.
export default function MiniPlayer({ raised }) {
  const p = { ...usePlayer(), ...usePlayerProgress() };
  const pct = p.duration ? (p.time / p.duration) * 100 : 0;
  return (
    <AnimatePresence>
      {p.track && (
        <motion.div
          initial={{ opacity: 0, y: 40, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 40, scale: 0.95 }}
          transition={{ type: "spring", stiffness: 360, damping: 30 }}
          className={`fixed z-[60] left-3 right-3 mx-auto max-w-[560px] desk:mx-0 desk:left-auto desk:right-5 desk:w-[360px] ${raised ? "bottom-[calc(80px+env(safe-area-inset-bottom))]" : "bottom-[calc(0.75rem+env(safe-area-inset-bottom))]"} desk:bottom-5 glass rounded-3xl overflow-hidden`}
          style={{ border: "1px solid var(--border-c)", boxShadow: "var(--shadow-lg)" }}
          role="region"
          aria-label="Music player"
        >
          <div className="flex items-center gap-3 p-3 pb-2">
            <div
              data-paused={!p.playing}
              className="anim-spin w-12 h-12 rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center text-white"
              style={{ background: "var(--accent-grad)", boxShadow: "0 0 0 3px var(--surface), 0 0 0 4px var(--border-c)" }}
            >
              {p.track.cover ? <img key={p.track.cover} src={p.track.cover} alt="" className="w-full h-full object-cover" onError={(e) => { e.currentTarget.style.display = "none"; }} /> : <Music2 className="w-5 h-5" />}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{p.track.title}</p>
              <p className="text-xs truncate flex items-center gap-1.5" style={{ color: "var(--text-muted)" }}>
                <span className={`equalizer ${p.playing ? "" : "paused"}`} style={{ color: "var(--accent-rose)" }}><span /><span /><span /></span>
                {p.track.artist}
              </p>
            </div>
            <div className="flex items-center gap-0.5">
              {p.queue.length > 1 && <button className="icon-btn hidden sm:inline-flex" onClick={p.prev} aria-label="Previous"><SkipBack className="w-4 h-4" /></button>}
              <motion.button whileTap={{ scale: 0.9 }} onClick={() => p.toggle()} className="w-10 h-10 rounded-full flex items-center justify-center text-white" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }} aria-label={p.playing ? "Pause" : "Play"}>
                {p.playing ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4 ml-0.5" />}
              </motion.button>
              {p.queue.length > 1 && <button className="icon-btn" onClick={p.next} aria-label="Next"><SkipForward className="w-4 h-4" /></button>}
              <button className="icon-btn" onClick={p.close} aria-label="Close player"><X className="w-4 h-4" /></button>
            </div>
          </div>
          <div className="flex items-center gap-2 px-4 pb-3">
            <span className="text-[10px] tabular-nums w-8" style={{ color: "var(--text-muted)" }}>{formatTime(p.time)}</span>
            <div
              className="relative flex-1 h-1.5 rounded-full cursor-pointer group"
              style={{ background: "var(--border-c)" }}
              onClick={(e) => { const r = e.currentTarget.getBoundingClientRect(); p.seek(((e.clientX - r.left) / r.width) * p.duration); }}
              role="slider"
              aria-label="Seek"
              aria-valuemin={0}
              aria-valuemax={Math.round(p.duration)}
              aria-valuenow={Math.round(p.time)}
            >
              <div className="absolute inset-y-0 left-0 rounded-full" style={{ width: `${pct}%`, background: "var(--accent-grad)" }} />
              <div className="absolute top-1/2 -translate-y-1/2 w-3 h-3 rounded-full bg-white opacity-0 group-hover:opacity-100 transition-opacity" style={{ left: `calc(${pct}% - 6px)`, boxShadow: "var(--shadow-sm)" }} />
            </div>
            <span className="text-[10px] tabular-nums w-8 text-right" style={{ color: "var(--text-muted)" }}>{formatTime(p.duration)}</span>
            <button className="icon-btn w-7 h-7 hidden desk:inline-flex" onClick={() => p.setVolume(p.volume > 0 ? 0 : 0.8)} aria-label={p.volume > 0 ? "Mute" : "Unmute"}>
              {p.volume > 0 ? <Volume2 className="w-3.5 h-3.5" /> : <VolumeX className="w-3.5 h-3.5" />}
            </button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
