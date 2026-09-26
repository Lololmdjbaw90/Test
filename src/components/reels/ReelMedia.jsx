import React, { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
import { filterCss } from "@/lib/filters";
import { useMediaSrc } from "@/lib/media";
import FilterLayers from "@/components/media/FilterLayers";

export const PHOTO_SECONDS = 7;

// Text stickers placed on a reel (positions are 0..1 of the frame; sizes are
// a fraction of the frame width, so they scale with the screen).
export function TextStickers({ items = [], className = "" }) {
  return (items || []).map((t) => (
    <span
      key={t.id}
      className={`absolute pointer-events-none text-center font-bold leading-tight whitespace-pre-wrap max-w-[86%] ${className}`}
      style={{
        left: `${t.x * 100}%`, top: `${t.y * 100}%`, translate: "-50% -50%",
        fontSize: `${(t.size || 0.07) * 100}cqw`, color: t.color || "#fff",
        background: t.bg || "transparent", padding: t.bg ? "0.2em 0.55em" : 0, borderRadius: "0.45em",
        textShadow: t.bg ? "none" : "0 2px 8px rgb(0 0 0 / 0.55)",
      }}
    >
      {t.text}
    </span>
  ));
}

// Plays one reel: a video (trimmed, sped up / slowed, filtered) or a photo
// (slow zoom), with its text stickers and optional music. Only reels next to
// the one on screen mount their media, so long feeds stay light.
// onProgress(0..1) is called often — update the DOM directly, not React state.
const ReelMedia = forwardRef(function ReelMedia({ reel, active, near, paused, soundOn, onProgress, onLoop, onBlocked }, ref) {
  const edits = reel.edits || {};
  const src = useMediaSrc(near ? reel.media_url : "");
  const cover = useMediaSrc(reel.cover_url || (reel.kind === "photo" ? reel.media_url : ""));
  const music = useMediaSrc(near ? reel.music_url : "");
  const videoRef = useRef(null);
  const audioRef = useRef(null);
  const [fit, setFit] = useState("cover");
  const [cycle, setCycle] = useState(0);
  const elapsed = useRef(0);
  const speed = edits.speed || 1;
  const trimStart = edits.trim_start || 0;
  const videoSound = soundOn && !edits.muted;

  const trimEnd = () => {
    const d = videoRef.current?.duration || 0;
    return edits.trim_end && edits.trim_end > trimStart ? Math.min(edits.trim_end, d || edits.trim_end) : d;
  };

  // Called straight from a tap, so iOS lets the sound start.
  useImperativeHandle(ref, () => ({
    unlock() {
      const v = videoRef.current, a = audioRef.current;
      if (v) { v.muted = !!edits.muted; v.play().catch(() => {}); }
      if (a) { a.muted = false; a.play().catch(() => {}); }
    },
  }));

  // Play / pause the video with the feed.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = !videoSound;
    v.playbackRate = speed;
    if (active && !paused) {
      if (v.currentTime < trimStart) v.currentTime = trimStart;
      v.play().catch((e) => {
        if (e?.name === "NotAllowedError" && !v.muted) { v.muted = true; onBlocked?.(); v.play().catch(() => {}); }
      });
    } else {
      v.pause();
      if (!active) { try { v.currentTime = trimStart; } catch { /* not loaded yet */ } }
    }
  }, [active, paused, videoSound, speed, trimStart, src]); // eslint-disable-line react-hooks/exhaustive-deps

  // Music track.
  useEffect(() => {
    const a = audioRef.current;
    if (!a) return;
    a.muted = !soundOn;
    if (active && !paused && soundOn) a.play().catch(() => onBlocked?.());
    else { a.pause(); if (!active) { try { a.currentTime = 0; } catch { /* not loaded */ } } }
  }, [active, paused, soundOn, music]); // eslint-disable-line react-hooks/exhaustive-deps

  // Photos: a timer drives the progress bar and the loop.
  useEffect(() => {
    if (reel.kind !== "photo" || !active || paused) return undefined;
    const begin = performance.now() - elapsed.current * 1000;
    let raf;
    const tick = () => {
      const t = (performance.now() - begin) / 1000;
      if (t >= PHOTO_SECONDS) { elapsed.current = 0; onProgress?.(1); onLoop?.(); setCycle((c) => c + 1); return; }
      elapsed.current = t;
      onProgress?.(t / PHOTO_SECONDS);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [reel.kind, active, paused, cycle]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (!active) { elapsed.current = 0; onProgress?.(0); } }, [active]); // eslint-disable-line react-hooks/exhaustive-deps

  const onTime = () => {
    const v = videoRef.current;
    if (!v) return;
    const end = trimEnd();
    if (end && v.currentTime >= end - 0.05) {
      v.currentTime = trimStart;
      onLoop?.();
      if (active && !paused) v.play().catch(() => {});
    }
    const span = Math.max(0.1, end - trimStart);
    onProgress?.(Math.min(1, Math.max(0, (v.currentTime - trimStart) / span)));
  };

  const css = filterCss(edits.filter);
  const photoSrc = src || cover;
  return (
    <div className="absolute inset-0 overflow-hidden bg-black" style={{ containerType: "inline-size" }}>
      {cover && fit === "contain" && <img src={cover} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-40 blur-2xl scale-110" />}
      {reel.kind === "video" ? (
        near ? (
          <video
            ref={videoRef}
            src={src || undefined}
            poster={cover || undefined}
            playsInline
            muted
            preload={active ? "auto" : "metadata"}
            onTimeUpdate={onTime}
            onEnded={onTime}
            onLoadedMetadata={(e) => {
              const v = e.currentTarget;
              setFit(v.videoWidth && v.videoHeight && v.videoWidth / v.videoHeight > 0.8 ? "contain" : "cover");
              v.playbackRate = speed;
              if (trimStart) v.currentTime = trimStart;
            }}
            className={`absolute inset-0 w-full h-full ${fit === "contain" ? "object-contain" : "object-cover"}`}
            style={{ filter: css, transform: edits.mirror ? "scaleX(-1)" : undefined }}
          />
        ) : cover ? <img src={cover} alt="" className="absolute inset-0 w-full h-full object-cover" style={{ filter: css }} /> : null
      ) : photoSrc ? (
        <img
          key={`${reel.id}-${cycle}`}
          src={photoSrc}
          alt={reel.caption || ""}
          draggable={false}
          className={`absolute inset-0 w-full h-full object-cover ${active ? "reel-kenburns" : ""}`}
          style={{ filter: css, animationPlayState: paused ? "paused" : "running", animationDuration: `${PHOTO_SECONDS}s` }}
        />
      ) : null}
      <FilterLayers filter={edits.filter} />
      <TextStickers items={edits.text} />
      {near && music && <audio ref={audioRef} src={music} loop preload="auto" />}
    </div>
  );
});

export default ReelMedia;
