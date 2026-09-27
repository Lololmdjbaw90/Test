import React, { forwardRef, useEffect, useImperativeHandle, useMemo, useRef, useState } from "react";
import { filterCss } from "@/lib/filters";
import { useMediaSrc } from "@/lib/media";
import { clipsOf, locate, totalLength } from "@/lib/clips";
import FilterLayers from "@/components/media/FilterLayers";
import { StickerLayer } from "./Sticker";
import { freshPreview } from "@/lib/musicCatalog";

export const PHOTO_SECONDS = 7;
export const SLIDE_SECONDS = 3;
// Length of a photo reel: one picture, or a slideshow of several.
export const photoLength = (count) => (count > 1 ? count * SLIDE_SECONDS : PHOTO_SECONDS);

// Older imports keep working.
export function TextStickers({ items = [] }) { return <StickerLayer items={items} />; }

// Shows only the stickers whose time range covers `t` (entrances replay as
// they appear, because display:none → visible restarts CSS animations).
function syncStickers(layer, t) {
  if (!layer) return;
  layer.querySelectorAll("[data-sticker]").forEach((el) => {
    const from = el.dataset.from === "" ? -1 : Number(el.dataset.from);
    const to = el.dataset.to === "" ? Infinity : Number(el.dataset.to);
    const show = t >= from && t <= to;
    const want = show ? "" : "none";
    if (el.style.display !== want) el.style.display = want;
  });
}

// Plays one reel: a video cut into clips (sped up / slowed, filtered) or a
// photo (slow zoom), with text stickers and optional music. A small frame
// loop keeps cuts exact and drives the progress bar without re-rendering.
// Only reels next to the one on screen mount their media.
const ReelMedia = forwardRef(function ReelMedia({ reel, active, near, paused, soundOn, speedBoost = 1, onProgress, onLoop, onBlocked, onBuffering }, ref) {
  const edits = reel.edits || {};
  const src = useMediaSrc(near ? reel.media_url : "");
  const cover = useMediaSrc(reel.cover_url || (reel.kind === "photo" ? reel.media_url : ""));
  const [musicUrl, setMusicUrl] = useState(reel.music_url || "");
  useEffect(() => {
    const id = String(reel.music_source || "").startsWith("deezer:") ? reel.music_source.slice(7) : "";
    if (!id || !near) return undefined;
    let alive = true;
    freshPreview(id).then((u) => { if (alive && u) setMusicUrl(u); });
    return () => { alive = false; };
  }, [reel.music_source, near]);
  const music = useMediaSrc(near ? musicUrl : "");
  const slides = reel.kind === "photo" && (reel.media_urls || []).length > 1 ? reel.media_urls : null;
  const photoTotal = photoLength(slides?.length || 1);
  const [slide, setSlide] = useState(0);
  const slideRef = useRef(0);
  const trackRef = useRef(null);
  // Slideshows scroll sideways like TikTok photo posts using
  // manual swipes, without automatic movement.
  const goToSlide = (i) => {
    slideRef.current = i;
    setSlide(i);
    const el = trackRef.current;
    if (el) el.scrollTo({ left: i * el.clientWidth, behavior: i === 0 ? "auto" : "smooth" });
  };
  const onSlideScroll = (e) => {
    const el = e.currentTarget;
    const i = Math.round(el.scrollLeft / Math.max(1, el.clientWidth));
    if (i === slideRef.current) return;
    slideRef.current = i;
    setSlide(i);
    elapsed.current = i * SLIDE_SECONDS;
    cb.current.onProgress?.((i + 1) / slides.length);
    syncStickers(layerRef.current, elapsed.current);
  };
  const videoRef = useRef(null);
  const audioRef = useRef(null);
  const layerRef = useRef(null);
  const [fit, setFit] = useState("cover");
  const [duration, setDuration] = useState(0);
  const [cycle, setCycle] = useState(0);
  const elapsed = useRef(0);
  const clipIndex = useRef(0);
  const clips = useMemo(() => clipsOf(edits, duration), [edits, duration]);
  const total = reel.kind === "video" ? totalLength(clips) : photoTotal;
  const rate = (edits.speed || 1) * speedBoost;
  const videoSound = soundOn && !edits.muted;
  const cb = useRef({});
  cb.current = { onProgress, onLoop, onBuffering };

  const seekOutput = (t) => {
    const v = videoRef.current;
    if (!v) return;
    const { index, source } = locate(clips, Math.max(0, Math.min(total - 0.05, t)));
    clipIndex.current = index;
    try { v.currentTime = source; } catch { /* not loaded yet */ }
  };

  useImperativeHandle(ref, () => ({
    // Called straight from a tap, so iOS lets the sound start.
    unlock() {
      const v = videoRef.current, a = audioRef.current;
      if (v) { v.muted = !!edits.muted; v.play().catch(() => {}); }
      if (a) { a.muted = false; a.play().catch(() => {}); }
    },
    // Seek to a fraction (0..1) of the reel.
    seek(fraction) {
      if (reel.kind === "video") { seekOutput(fraction * total); cb.current.onProgress?.(fraction); }
      else { elapsed.current = fraction * photoTotal; cb.current.onProgress?.(fraction); }
    },
  }));

  // Play / pause / rate.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = !videoSound;
    v.playbackRate = rate;
    if (active && !paused) {
      v.play().catch((e) => {
        if (e?.name === "NotAllowedError" && !v.muted) { v.muted = true; onBlocked?.(); v.play().catch(() => {}); }
      });
    } else {
      v.pause();
      if (!active) { clipIndex.current = 0; try { v.currentTime = clips[0]?.start || 0; } catch { /* not loaded */ } }
    }
  }, [active, paused, videoSound, rate, src]); // eslint-disable-line react-hooks/exhaustive-deps

  // Music.
  useEffect(() => {
    const a = audioRef.current;
    if (!a) return;
    a.muted = !soundOn;
    a.playbackRate = speedBoost;
    if (active && !paused && soundOn) a.play().catch(() => onBlocked?.());
    else { a.pause(); if (!active) { try { a.currentTime = 0; } catch { /* not loaded */ } } }
  }, [active, paused, soundOn, music, speedBoost]); // eslint-disable-line react-hooks/exhaustive-deps

  // Frame loop for videos: exact cuts, progress, sticker timing.
  useEffect(() => {
    if (reel.kind !== "video" || !active) return undefined;
    let raf;
    const tick = () => {
      const v = videoRef.current;
      if (v && clips.length && !paused) {
        let i = Math.min(clipIndex.current, clips.length - 1);
        const c = clips[i];
        // Out of the current clip (seeked, or just loaded)? Find where we are.
        if (v.currentTime < c.start - 0.25 || v.currentTime > c.end + 0.25) {
          const found = clips.findIndex((k) => v.currentTime >= k.start - 0.05 && v.currentTime < k.end);
          if (found >= 0) i = clipIndex.current = found;
          else { clipIndex.current = 0; v.currentTime = clips[0].start; }
        } else if (v.currentTime >= c.end - 0.03 || v.ended) {
          // End of a clip: jump to the next one (or loop the reel).
          // (Clips that continue where the last one ended don't need a seek.)
          if (i + 1 < clips.length) { i = clipIndex.current = i + 1; if (Math.abs(v.currentTime - clips[i].start) > 0.08) v.currentTime = clips[i].start; }
          else { clipIndex.current = 0; v.currentTime = clips[0].start; cb.current.onLoop?.(); }
          if (v.paused && active && !paused) v.play().catch(() => {});
        }
        let out = 0;
        for (let k = 0; k < clipIndex.current; k++) out += clips[k].end - clips[k].start;
        out += Math.max(0, v.currentTime - clips[clipIndex.current].start);
        cb.current.onProgress?.(total ? Math.min(1, out / total) : 0);
        syncStickers(layerRef.current, out);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [reel.kind, active, paused, clips, total]); // eslint-disable-line react-hooks/exhaustive-deps

  // Photos: a timer drives the progress bar, stickers and the loop.
  useEffect(() => {
    if (reel.kind !== "photo" || slides || !active || paused) return undefined;
    let last = performance.now();
    let raf;
    const tick = (now) => {
      elapsed.current += ((now - last) / 1000) * speedBoost;
      last = now;
      if (elapsed.current >= photoTotal) { elapsed.current = 0; cb.current.onLoop?.(); if (slides) goToSlide(0); else setCycle((c) => c + 1); }
      if (slides) {
        const i = Math.min(slides.length - 1, Math.floor(elapsed.current / SLIDE_SECONDS));
        if (i !== slideRef.current) goToSlide(i);
      }
      cb.current.onProgress?.(elapsed.current / photoTotal);
      syncStickers(layerRef.current, elapsed.current);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [reel.kind, active, paused, speedBoost, photoTotal]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (!active) { elapsed.current = 0; cb.current.onProgress?.(0); if (slides) goToSlide(0); } }, [active]); // eslint-disable-line react-hooks/exhaustive-deps

  const css = filterCss(edits.filter);
  const photoSrc = src || cover;
  return (
    <div className="absolute inset-0 overflow-hidden bg-black" style={{ containerType: "inline-size" }}>
      {cover && fit === "contain" && <img src={cover} alt="" aria-hidden="true" className="absolute inset-0 w-full h-full object-cover opacity-40 blur-2xl scale-110" />}
      {reel.kind === "video" ? (
        <>
          {cover && <img src={cover} alt="" aria-hidden="true" className={`absolute inset-0 w-full h-full ${fit === "contain" ? "object-contain" : "object-cover"}`} style={{ filter: css }} />}
          {near && (
            <video
              ref={videoRef}
              src={src || undefined}
              playsInline
              muted
              preload={active ? "auto" : "metadata"}
              onWaiting={() => cb.current.onBuffering?.(true)}
              onStalled={() => cb.current.onBuffering?.(true)}
              onPlaying={() => cb.current.onBuffering?.(false)}
              onCanPlay={() => cb.current.onBuffering?.(false)}
              onLoadedMetadata={(e) => {
                const v = e.currentTarget;
                setDuration(v.duration || 0);
                setFit(v.videoWidth && v.videoHeight && v.videoWidth / v.videoHeight > 0.8 ? "contain" : "cover");
                v.playbackRate = rate;
                const first = clipsOf(edits, v.duration || 0)[0];
                if (first?.start) v.currentTime = first.start;
              }}
              className={`absolute inset-0 w-full h-full ${fit === "contain" ? "object-contain" : "object-cover"}`}
              style={{ filter: css, transform: edits.mirror ? "scaleX(-1)" : undefined }}
            />
          )}
        </>
      ) : slides ? (
        <>
          <div ref={trackRef} onScroll={onSlideScroll} className="absolute inset-0 flex overflow-x-auto overflow-y-hidden snap-x snap-mandatory no-scrollbar" style={{ touchAction: "pan-x pan-y", overscrollBehaviorX: "contain" }}>
            {slides.map((u, i) => (
              <img key={i} src={u} alt={i === 0 ? reel.caption || "" : ""} draggable={false} loading={i < 2 ? "eager" : "lazy"} className="w-full h-full flex-shrink-0 object-cover snap-center snap-always" style={{ filter: css }} />
            ))}
          </div>
          <div className="absolute inset-x-0 top-[calc(env(safe-area-inset-top)+3.9rem)] flex justify-center gap-1.5 pointer-events-none">
            {slides.map((_, i) => <span key={i} className="h-1.5 rounded-full transition-all duration-300" style={{ width: i === slide ? 16 : 6, background: i === slide ? "#fff" : "rgb(255 255 255 / 0.5)" }} />)}
          </div>
        </>
      ) : photoSrc ? (
        <img
          key={`${reel.id}-${cycle}`}
          src={photoSrc}
          alt={reel.caption || ""}
          draggable={false}
          className="absolute inset-0 w-full h-full object-cover"
          style={{ filter: css, animationPlayState: paused ? "paused" : "running", animationDuration: `${PHOTO_SECONDS}s` }}
        />
      ) : null}
      <FilterLayers filter={edits.filter} />
      {/* Remounts when the reel comes on screen, so text entrances play then. */}
      <StickerLayer key={active ? "on" : "off"} items={edits.text} layerRef={layerRef} />
      {near && music && <audio ref={audioRef} src={music} loop preload="auto" />}
    </div>
  );
});

export default ReelMedia;
