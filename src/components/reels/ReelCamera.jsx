import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Check, Delete, Image as ImageIcon, RefreshCcw, Sparkles, Timer, X, Zap, ZapOff } from "lucide-react";
import { filterCss } from "@/lib/filters";
import { feedback } from "@/lib/feedback";
import { toast } from "@/lib/toast";
import FilterLayers from "@/components/media/FilterLayers";
import FilterStrip from "@/components/media/FilterStrip";
import { nativeTorchAvailable, screenFlashBrightness, setNativeTorch } from "@/lib/flash";

export const MAX_SECONDS = 60;
const MAX_UPLOAD_MB = 60;
const HOLD_MS = 420; // press longer than this = hold to record, let go to pause
const TIMERS = [0, 3, 10];

function pickRecorderType() {
  if (typeof MediaRecorder === "undefined") return "";
  return ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm"].find((t) => { try { return MediaRecorder.isTypeSupported(t); } catch { return false; } }) || "";
}

// Reads a picked / recorded video's length and size.
export function probeVideo(url) {
  return new Promise((resolve) => {
    const v = document.createElement("video");
    v.preload = "metadata";
    v.muted = true;
    v.playsInline = true;
    const done = () => resolve({ duration: Number.isFinite(v.duration) ? v.duration : 0, width: v.videoWidth, height: v.videoHeight });
    v.onloadedmetadata = () => {
      // Recorded webm files report Infinity until you seek to the end.
      if (!Number.isFinite(v.duration)) { v.currentTime = 1e7; v.ontimeupdate = () => { v.ontimeupdate = null; done(); }; } else done();
    };
    v.onerror = () => resolve({ duration: 0, width: 0, height: 0 });
    v.src = url;
  });
}

const segLen = (s) => s.end - s.start;
const uid = () => `c${Math.random().toString(36).slice(2, 9)}`;

// Full-screen camera. Film in several clips like TikTok: tap (or hold) to
// record, tap again (or let go) to pause, delete the last clip, then Done.
// Every clip becomes a cut in the editor. Also: photos, flip camera, flash
// (the real torch on the back camera, a bright screen on the front), a 3s /
// 10s timer, live filters, and picking from the library.
export default function ReelCamera({ onClose, onCaptured }) {
  const videoRef = useRef(null);
  const fileRef = useRef(null);
  const recorderRef = useRef(null);
  const chunks = useRef([]);
  const typeRef = useRef("");
  const fileClock = useRef(0); // seconds already written to the file
  const segStart = useRef(0);
  const segmentsRef = useRef([]);
  const discard = useRef(false);
  const press = useRef(null);
  const countTimer = useRef(null);
  const [stream, setStream] = useState(null);
  const [error, setError] = useState("");
  const [facing, setFacing] = useState("user");
  const [mode, setMode] = useState("video");
  const [flash, setFlash] = useState(false);
  const [torch, setTorch] = useState(false); // "web" | "native" | false — the back camera's real light
  const [filter, setFilter] = useState("none");
  const [showFilters, setShowFilters] = useState(false);
  const [recording, setRecording] = useState(false);
  const [segments, setSegmentsState] = useState([]);
  const [live, setLive] = useState(0);
  const [screenFlash, setScreenFlash] = useState(false);
  const [thumb, setThumb] = useState("");
  const [timer, setTimer] = useState(0);
  const [countdown, setCountdown] = useState(0);
  const [finishing, setFinishing] = useState(false);
  const [confirmClose, setConfirmClose] = useState(false);
  const recordingRef = useRef(false);
  const finalizeRef = useRef(null);

  const setSegments = (fn) => {
    segmentsRef.current = typeof fn === "function" ? fn(segmentsRef.current) : fn;
    setSegmentsState(segmentsRef.current);
  };
  const kept = segments.reduce((s, x) => s + segLen(x), 0);
  const total = kept + (recording ? live : 0);
  const hasClips = segments.length > 0;

  // Start / switch the camera.
  useEffect(() => {
    let cancelled = false;
    let current = null;
    (async () => {
      if (!navigator.mediaDevices?.getUserMedia) { setError("This device can't open the camera here — pick a photo or video instead."); return; }
      const video = { facingMode: facing, width: { ideal: 1080 }, height: { ideal: 1920 } };
      try {
        current = await navigator.mediaDevices.getUserMedia({ video, audio: true }).catch(() => navigator.mediaDevices.getUserMedia({ video, audio: false }));
        if (cancelled) { current.getTracks().forEach((t) => t.stop()); return; }
        setStream(current);
        setError("");
        const track = current.getVideoTracks()[0];
        const webTorch = !!track?.getCapabilities?.()?.torch;
        setTorch(webTorch ? "web" : facing === "environment" && await nativeTorchAvailable() ? "native" : false);
      } catch (e) {
        setError(e?.name === "NotAllowedError" ? "Camera access is off. Allow it in Settings, or pick a photo or video instead." : "No camera found — pick a photo or video instead.");
      }
    })();
    return () => { cancelled = true; setNativeTorch(false); current?.getTracks().forEach((t) => t.stop()); };
  }, [facing]);

  // Never leave the light on or the screen at full brightness.
  useEffect(() => () => { setNativeTorch(false); screenFlashBrightness(false); }, []);

  // Show the camera once the preview element exists.
  useEffect(() => {
    const v = videoRef.current;
    if (!v || !stream) return;
    v.srcObject = stream;
    v.play().catch(() => {});
  }, [stream]);

  // Stop a recorder that's still running if the camera closes.
  useEffect(() => () => {
    clearInterval(countTimer.current);
    const rec = recorderRef.current;
    if (rec && rec.state !== "inactive") { discard.current = true; try { rec.stop(); } catch { /* already stopped */ } }
  }, []);

  // A small preview frame for the filter thumbnails.
  useEffect(() => {
    if (!stream || thumb) return undefined;
    const t = setTimeout(() => {
      const v = videoRef.current;
      if (!v?.videoWidth) return;
      const c = document.createElement("canvas");
      c.width = 120; c.height = Math.round(120 * v.videoHeight / v.videoWidth);
      c.getContext("2d").drawImage(v, 0, 0, c.width, c.height);
      try { setThumb(c.toDataURL("image/jpeg", 0.7)); } catch { /* tainted */ }
    }, 700);
    return () => clearTimeout(t);
  }, [stream, thumb]);

  const setTorchOn = async (on) => {
    if (torch === "native") return setNativeTorch(on);
    const track = stream?.getVideoTracks()[0];
    if (torch !== "web" || !track) return false;
    try { await track.applyConstraints({ advanced: [{ torch: on }] }); return true; } catch { return false; }
  };
  // Front camera: the screen is the flash. Back camera: the real light.
  const useScreenFlash = flash && facing === "user";
  const screenOn = () => { setScreenFlash(true); screenFlashBrightness(true); };
  const lightsOff = () => {
    setScreenFlash(false);
    screenFlashBrightness(false);
    if (flash && !useScreenFlash && mode === "photo") setTorchOn(false);
  };
  // Video on the back camera: the light stays on while flash is on, like TikTok.
  useEffect(() => {
    if (!torch || facing !== "environment") return;
    setTorchOn(flash && mode === "video");
  }, [flash, mode, torch, facing]); // eslint-disable-line react-hooks/exhaustive-deps
  const toggleFlash = () => {
    feedback("toggle");
    if (!flash && facing === "environment" && !torch) toast("This camera has no flash — flip to the front camera for a screen flash.");
    setFlash((f) => !f);
  };

  // ---------- photo ----------
  const takePhoto = async () => {
    const v = videoRef.current;
    if (!v?.videoWidth) return;
    feedback("tap");
    if (flash) {
      // Give the camera time to adjust to the light before taking the picture.
      if (useScreenFlash) { screenOn(); await new Promise((r) => setTimeout(r, 650)); } else if (await setTorchOn(true)) { await new Promise((r) => setTimeout(r, 600)); }
    }
    const c = document.createElement("canvas");
    c.width = v.videoWidth; c.height = v.videoHeight;
    const ctx = c.getContext("2d");
    if (facing === "user") { ctx.translate(c.width, 0); ctx.scale(-1, 1); } // like a mirror, as you saw it
    ctx.drawImage(v, 0, 0);
    lightsOff();
    const blob = await new Promise((r) => c.toBlob(r, "image/jpeg", 0.92));
    onCaptured({ kind: "photo", file: new File([blob], "photo.jpg", { type: "image/jpeg" }), url: URL.createObjectURL(blob), width: c.width, height: c.height, duration: 0, edits: { filter } });
  };

  // ---------- video (one file, recorded in clips) ----------
  finalizeRef.current = async () => {
    lightsOff();
    const type = typeRef.current;
    recorderRef.current = null;
    if (discard.current) { discard.current = false; chunks.current = []; return; }
    const blob = new Blob(chunks.current, { type: type.split(";")[0] });
    chunks.current = [];
    const url = URL.createObjectURL(blob);
    const meta = await probeVideo(url);
    const clock = fileClock.current;
    const duration = meta.duration || clock;
    // Our clock and the file's timestamps drift slightly; scale to match.
    const k = meta.duration && clock ? meta.duration / clock : 1;
    const clips = segmentsRef.current
      .map((s) => ({ id: uid(), start: Math.max(0, s.start * k), end: Math.min(duration, s.end * k) }))
      .filter((c) => c.end - c.start > 0.1);
    if (!clips.length) { setFinishing(false); URL.revokeObjectURL(url); return; }
    onCaptured({
      kind: "video", file: new File([blob], `reel.${type.includes("mp4") ? "mp4" : "webm"}`, { type: blob.type }), url, ...meta, duration,
      edits: { filter, mirror: facing === "user", clips, trim_start: clips[0].start, trim_end: clips[clips.length - 1].end },
    });
  };

  const beginClip = async () => {
    if (!stream || finishing) return;
    let rec = recorderRef.current;
    if (!rec) {
      const type = pickRecorderType();
      if (!type) { toast.error("Recording isn't supported here — pick a video from your library."); return; }
      typeRef.current = type;
      chunks.current = [];
      fileClock.current = 0;
      discard.current = false;
      rec = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 2_500_000 });
      rec.ondataavailable = (e) => { if (e.data?.size) chunks.current.push(e.data); };
      rec.onstop = () => finalizeRef.current?.(); // latest filter / callbacks
      recorderRef.current = rec;
      rec.start(250);
    } else if (rec.state === "paused") {
      rec.resume();
    }
    if (flash) { if (useScreenFlash) screenOn(); else setTorchOn(true); }
    segStart.current = performance.now();
    recordingRef.current = true;
    setLive(0);
    setRecording(true);
    setShowFilters(false);
    feedback("toggle");
  };

  // Ends the clip being filmed. Returns false if the recorder can't pause.
  const endClip = () => {
    const rec = recorderRef.current;
    if (!rec || !recordingRef.current) return true;
    recordingRef.current = false;
    const len = (performance.now() - segStart.current) / 1000;
    const start = fileClock.current;
    fileClock.current += len;
    if (len >= 0.2) setSegments((s) => [...s, { start, end: start + len }]);
    setRecording(false);
    setLive(0);
    lightsOff();
    if (typeof rec.pause === "function" && rec.state === "recording") { rec.pause(); return true; }
    return false;
  };

  const finish = () => {
    if (finishing) return;
    const canContinue = endClip();
    const rec = recorderRef.current;
    if (!segmentsRef.current.length || !rec) { if (!canContinue) setSegments([]); return; }
    setFinishing(true);
    feedback("success");
    rec.stop();
  };

  const pauseClip = () => {
    const canPause = endClip();
    feedback("tap");
    if (!canPause) finish(); // older phones: one clip only
  };

  const deleteLast = () => {
    if (!segments.length) return;
    feedback("error");
    setSegments((s) => s.slice(0, -1));
  };

  const startOver = () => {
    const rec = recorderRef.current;
    if (rec && rec.state !== "inactive") { discard.current = true; rec.stop(); }
    recordingRef.current = false;
    setRecording(false);
    setSegments([]);
    setConfirmClose(false);
  };

  // Recording clock + auto-finish at the length limit.
  useEffect(() => {
    if (!recording) return undefined;
    const t = setInterval(() => {
      const len = (performance.now() - segStart.current) / 1000;
      setLive(len);
      if (kept + len >= MAX_SECONDS) finish();
    }, 80);
    return () => clearInterval(t);
  }, [recording, kept]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---------- timer ----------
  const runCountdown = (then) => {
    let n = timer;
    setCountdown(n);
    feedback("tap");
    countTimer.current = setInterval(() => {
      n -= 1;
      if (n <= 0) { clearInterval(countTimer.current); setCountdown(0); then(); return; }
      setCountdown(n);
      feedback("tap");
    }, 1000);
  };
  const cancelCountdown = () => { clearInterval(countTimer.current); setCountdown(0); feedback("tap"); };

  // ---------- shutter: tap to start/pause, or hold to record ----------
  const start = () => {
    if (mode === "photo") { if (timer) runCountdown(takePhoto); else takePhoto(); return; }
    if (timer) runCountdown(beginClip); else beginClip();
  };
  const onShutterDown = (e) => {
    if (!stream || finishing) return;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    if (countdown) { cancelCountdown(); press.current = null; return; }
    if (mode === "video" && recording) { press.current = { stop: true }; return; }
    if (mode === "video" && !timer) { press.current = { t: performance.now(), started: true }; beginClip(); return; }
    press.current = { t: performance.now(), started: false };
  };
  const onShutterUp = () => {
    const p = press.current;
    press.current = null;
    if (!p) return;
    if (p.stop) { pauseClip(); return; }
    if (p.started) { if (performance.now() - p.t > HOLD_MS) pauseClip(); return; } // held: let go to pause
    start();
  };
  // Keyboard / switch control.
  const onShutterKey = (e) => {
    if (e.detail !== 0) return; // pointer clicks are handled above
    if (countdown) cancelCountdown();
    else if (mode === "video" && recording) pauseClip();
    else start();
  };

  // ---------- library ----------
  const pick = async (list) => {
    const files = [...(list || [])];
    const file = files[0];
    if (!file) return;
    // Several pictures at once make a slideshow reel.
    const pics = files.filter((f) => f.type.startsWith("image/")).slice(0, 10);
    if (pics.length > 1) {
      const urls = pics.map((f) => URL.createObjectURL(f));
      onCaptured({ kind: "photo", file: pics[0], url: urls[0], files: pics, urls, width: 0, height: 0, duration: 0, edits: { filter } });
      return;
    }
    const isVideo = file.type.startsWith("video/");
    if (!isVideo && !file.type.startsWith("image/")) { toast.error("Pick a photo or a video."); return; }
    if (file.size > MAX_UPLOAD_MB * 1024 * 1024) { toast.error(`That file is over ${MAX_UPLOAD_MB} MB — try a shorter clip.`); return; }
    const url = URL.createObjectURL(file);
    if (isVideo) {
      const meta = await probeVideo(url);
      onCaptured({ kind: "video", file, url, ...meta, edits: { filter } });
    } else {
      onCaptured({ kind: "photo", file, url, width: 0, height: 0, duration: 0, edits: { filter } });
    }
  };

  const close = () => { if (hasClips || recording) { if (recording) endClip(); setConfirmClose(true); } else onClose(); };

  // Progress ring: one arc per clip, with small gaps between them.
  const R = 40, C = 2 * Math.PI * R, GAP = 2.5;
  const arcs = [];
  let acc = 0;
  for (const s of [...segments.map(segLen), ...(recording ? [live] : [])]) {
    const len = (Math.min(s, MAX_SECONDS - acc) / MAX_SECONDS) * C;
    arcs.push({ from: (acc / MAX_SECONDS) * C, len: Math.max(0.5, len - GAP) });
    acc += s;
  }
  const busy = recording || hasClips;
  const lit = screenFlash && recording;

  return (
    <div className="absolute inset-0 flex flex-col text-white" style={{ background: lit ? "#fff8f2" : "#000", transition: "background .2s" }}>
      <div className="relative flex-1 min-h-0 overflow-hidden" style={{ margin: lit ? "44px 30px 16px" : 0, borderRadius: lit ? 30 : 0, transition: "margin .25s, border-radius .25s" }}>
        {stream ? (
          <video ref={videoRef} playsInline muted autoPlay className="absolute inset-0 w-full h-full object-cover" style={{ filter: filterCss(filter), transform: facing === "user" ? "scaleX(-1)" : undefined }} />
        ) : (
          <div className="absolute inset-0 flex flex-col items-center justify-center text-center px-8 gap-4">
            <Sparkles className="w-10 h-10 opacity-70" />
            <p className="text-sm opacity-80 max-w-xs">{error || "Opening the camera…"}</p>
            <button className="btn" onClick={() => fileRef.current?.click()}><ImageIcon className="w-4 h-4" /> Pick from library</button>
          </div>
        )}
        <FilterLayers filter={filter} />

        {/* clip bar across the top, like TikTok */}
        {mode === "video" && busy && (
          <div className="absolute top-[calc(env(safe-area-inset-top)+0.35rem)] inset-x-3 h-1 rounded-full overflow-hidden flex gap-[2px]" style={{ background: "rgb(255 255 255 / 0.22)" }}>
            {segments.map((s, i) => <span key={i} className="h-full" style={{ width: `${(segLen(s) / MAX_SECONDS) * 100}%`, background: "#ff4d7d" }} />)}
            {recording && <span className="h-full" style={{ width: `${(live / MAX_SECONDS) * 100}%`, background: "#fff" }} />}
          </div>
        )}

        {/* top controls */}
        <div className="absolute top-0 inset-x-0 pt-[calc(env(safe-area-inset-top)+0.9rem)] px-3 flex items-start justify-between">
          <button onClick={close} className="w-11 h-11 rounded-full flex items-center justify-center active:scale-90 transition-transform" style={{ background: "rgb(0 0 0 / 0.35)" }} aria-label="Close camera"><X className="w-6 h-6" /></button>
          {mode === "video" && busy && (
            <span className="mt-2 px-3 py-1 rounded-full text-sm font-bold tabular-nums flex items-center gap-2 enter-pop" style={{ background: recording ? "rgb(239 68 68 / 0.9)" : "rgb(0 0 0 / 0.45)" }}>
              {recording && <span className="w-2 h-2 rounded-full bg-white rec-dot" />}
              {total.toFixed(1)}s{!recording && ` · ${segments.length} clip${segments.length === 1 ? "" : "s"}`}
            </span>
          )}
          <div className="flex flex-col gap-3 transition-opacity duration-200" style={{ opacity: recording ? 0 : 1, pointerEvents: recording ? "none" : undefined }}>
            <button onClick={() => { feedback("tap"); setFacing((f) => (f === "user" ? "environment" : "user")); setThumb(""); }} disabled={busy} className="w-11 h-11 rounded-full flex items-center justify-center disabled:opacity-40 active:scale-90 transition-transform" style={{ background: "rgb(0 0 0 / 0.35)" }} aria-label="Flip camera"><RefreshCcw className="w-5 h-5" /></button>
            <button onClick={toggleFlash} className="w-11 h-11 rounded-full flex items-center justify-center active:scale-90 transition-transform" style={{ background: flash ? "#ffd35c" : "rgb(0 0 0 / 0.35)", color: flash ? "#2a1620" : "#fff" }} aria-label={flash ? "Flash on" : "Flash off"} aria-pressed={flash} title={facing === "environment" ? (torch ? "Flash" : "No flash on this camera") : "Screen flash"}>{flash ? <Zap className="w-5 h-5 fill-current" /> : <ZapOff className="w-5 h-5" />}</button>
            <button onClick={() => { feedback("toggle"); setTimer((t) => TIMERS[(TIMERS.indexOf(t) + 1) % TIMERS.length]); }} className="relative w-11 h-11 rounded-full flex items-center justify-center active:scale-90 transition-transform" style={{ background: timer ? "#fff" : "rgb(0 0 0 / 0.35)", color: timer ? "#2a1620" : "#fff" }} aria-label={timer ? `Timer ${timer} seconds` : "Timer off"}>
              <Timer className="w-5 h-5" />
              {timer > 0 && <span className="absolute -right-1 -bottom-1 min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-bold flex items-center justify-center enter-pop" style={{ background: "#ff4d7d", color: "#fff" }}>{timer}</span>}
            </button>
            <button onClick={() => { feedback("tap"); setShowFilters((v) => !v); }} className="w-11 h-11 rounded-full flex items-center justify-center active:scale-90 transition-transform" style={{ background: showFilters || filter !== "none" ? "rgb(var(--accent-rgb))" : "rgb(0 0 0 / 0.35)" }} aria-label="Filters" aria-pressed={showFilters}><Sparkles className="w-5 h-5" /></button>
          </div>
        </div>

        {countdown > 0 && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none" aria-live="assertive">
            <span key={countdown} className="count-pop font-display text-[120px] leading-none" style={{ textShadow: "0 6px 30px rgb(0 0 0 / 0.5)" }}>{countdown}</span>
          </div>
        )}

        <AnimatePresence>
          {showFilters && !recording && (
            <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 16 }} transition={{ duration: 0.18 }} className="absolute inset-x-0 bottom-3 px-2">
              <FilterStrip thumb={thumb} value={filter} onChange={setFilter} dark />
            </motion.div>
          )}
        </AnimatePresence>

        {mode === "video" && !busy && !countdown && stream && (
          <p className="absolute inset-x-0 bottom-3 text-center text-xs font-bold opacity-70 pointer-events-none transition-opacity" style={{ opacity: showFilters ? 0 : 0.7 }}>Tap to film · hold to film while pressed · film in several clips</p>
        )}
      </div>

      {/* bottom controls */}
      <div className="flex-shrink-0 pt-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] px-6">
        <div className="flex items-center justify-between">
          <div className="relative w-14 h-12">
            <AnimatePresence initial={false}>
              {hasClips && !recording && (
                <motion.button key="del" initial={{ opacity: 0, scale: 0.6 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.6 }} transition={{ duration: 0.16 }} onClick={deleteLast} disabled={finishing} className="absolute inset-0 m-auto w-12 h-12 rounded-full flex items-center justify-center active:scale-90 transition-transform" style={{ background: "rgb(255 255 255 / 0.14)" }} aria-label="Delete last clip"><Delete className="w-6 h-6" /></motion.button>
              )}
              {!busy && (
                <motion.button key="lib" initial={{ opacity: 0, scale: 0.6 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.6 }} transition={{ duration: 0.16 }} onClick={() => fileRef.current?.click()} className="absolute inset-0 m-auto w-12 h-12 rounded-xl flex items-center justify-center active:scale-90 transition-transform" style={{ background: "rgb(255 255 255 / 0.14)" }} aria-label="Pick from library"><ImageIcon className="w-6 h-6" /></motion.button>
              )}
            </AnimatePresence>
          </div>
          <button
            onPointerDown={onShutterDown}
            onPointerUp={onShutterUp}
            onPointerCancel={() => { if (press.current?.started || press.current?.stop) pauseClip(); press.current = null; }}
            onClick={onShutterKey}
            onContextMenu={(e) => e.preventDefault()}
            disabled={!stream || finishing}
            className="relative w-[92px] h-[92px] flex items-center justify-center disabled:opacity-40 select-none"
            style={{ touchAction: "none", WebkitTouchCallout: "none", transform: recording ? "scale(1.12)" : "scale(1)", transition: "transform .25s cubic-bezier(.2,.9,.3,1.3)" }}
            aria-label={countdown ? "Cancel timer" : mode === "photo" ? "Take photo" : recording ? "Pause recording" : hasClips ? "Record another clip" : "Start recording"}
          >
            <svg className="absolute inset-0" viewBox="0 0 92 92" aria-hidden="true">
              <circle cx="46" cy="46" r={R} fill="none" stroke="rgb(255 255 255 / 0.35)" strokeWidth="6" />
              {mode === "video" && arcs.map((a, i) => (
                <circle key={i} cx="46" cy="46" r={R} fill="none" stroke={recording && i === arcs.length - 1 ? "#fff" : "#ff4d7d"} strokeWidth="6" strokeDasharray={`${a.len} ${C}`} strokeDashoffset={-a.from} transform="rotate(-90 46 46)" />
              ))}
            </svg>
            <span className="block" style={{ width: recording ? 32 : 66, height: recording ? 32 : 66, borderRadius: recording ? 9 : 999, background: mode === "photo" ? "#fff" : "#ff4d7d", transition: "all .25s cubic-bezier(.2,.9,.3,1.2)", boxShadow: mode === "video" ? "0 0 24px rgb(255 77 125 / 0.45)" : "none" }} />
          </button>
          <div className="w-14 flex justify-center">
            <AnimatePresence>
              {mode === "video" && hasClips && (
                <motion.button key="done" initial={{ opacity: 0, scale: 0.6 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.6 }} onClick={finish} disabled={finishing || kept < 0.5} className="w-12 h-12 rounded-full flex items-center justify-center active:scale-90 transition-transform disabled:opacity-50" style={{ background: "#ff4d7d", boxShadow: "0 6px 18px rgb(255 77 125 / 0.45)" }} aria-label="Done recording">
                  {finishing ? <span className="w-5 h-5 rounded-full border-2 border-white/40 border-t-white animate-spin" /> : <Check className="w-6 h-6" />}
                </motion.button>
              )}
            </AnimatePresence>
          </div>
        </div>
        <div className="relative mt-4 flex justify-center gap-6 text-sm font-bold transition-opacity" style={{ opacity: busy ? 0 : 1, pointerEvents: busy ? "none" : undefined }}>
          {["photo", "video"].map((m) => (
            <button key={m} disabled={busy} onClick={() => { feedback("tab"); setMode(m); }} className="relative capitalize px-1 pb-1 transition-opacity" style={{ opacity: mode === m ? 1 : 0.55 }}>
              {m}
              {mode === m && <motion.span layoutId="cam-mode" className="absolute left-1/2 -ml-[3px] -bottom-1 w-1.5 h-1.5 rounded-full bg-white" />}
            </button>
          ))}
        </div>
      </div>

      <AnimatePresence>
        {confirmClose && (
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="absolute inset-0 z-10 flex items-end justify-center p-4 pb-[calc(env(safe-area-inset-bottom)+1rem)]" style={{ background: "rgb(0 0 0 / 0.55)" }} onClick={() => setConfirmClose(false)}>
            <motion.div initial={{ y: 40 }} animate={{ y: 0 }} exit={{ y: 40 }} transition={{ type: "spring", damping: 26, stiffness: 320 }} className="w-full max-w-sm rounded-3xl p-4 space-y-2" style={{ background: "#1c1418" }} onClick={(e) => e.stopPropagation()} role="dialog" aria-label="Discard clips?">
              <p className="text-center font-bold pb-1">Discard your {segments.length} clip{segments.length === 1 ? "" : "s"}?</p>
              <button onClick={() => { feedback("error"); startOver(); }} className="w-full py-3 rounded-2xl font-bold" style={{ background: "rgb(239 68 68 / 0.18)", color: "#ff6b6b" }}>Start over</button>
              <button onClick={() => { feedback("error"); startOver(); onClose(); }} className="w-full py-3 rounded-2xl font-bold" style={{ background: "rgb(255 255 255 / 0.08)" }}>Discard and close</button>
              <button onClick={() => setConfirmClose(false)} className="w-full py-3 rounded-2xl font-bold" style={{ background: "rgb(255 255 255 / 0.14)" }}>Keep filming</button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {screenFlash && !recording && <div className="fixed inset-0 z-[5] pointer-events-none enter-fade" style={{ background: "#fff8f2" }} />}
      <input ref={fileRef} type="file" accept="image/*,video/*" multiple className="hidden" onChange={(e) => { pick(e.target.files); e.target.value = ""; }} />
    </div>
  );
}
