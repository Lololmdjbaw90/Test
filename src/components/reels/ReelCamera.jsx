import React, { useEffect, useRef, useState } from "react";
import { Image as ImageIcon, RefreshCcw, Sparkles, X, Zap, ZapOff } from "lucide-react";
import { filterCss } from "@/lib/filters";
import { feedback } from "@/lib/feedback";
import { toast } from "@/lib/toast";
import FilterLayers from "@/components/media/FilterLayers";
import FilterStrip from "@/components/media/FilterStrip";

export const MAX_SECONDS = 60;
const MAX_UPLOAD_MB = 60;

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

// Full-screen camera: film a video (hold or tap), snap a photo, flip camera,
// flash (the real torch on the back camera, a bright screen flash on the
// front), live filters, or pick something from the library.
export default function ReelCamera({ onClose, onCaptured }) {
  const videoRef = useRef(null);
  const fileRef = useRef(null);
  const recorderRef = useRef(null);
  const chunks = useRef([]);
  const startedAt = useRef(0);
  const [stream, setStream] = useState(null);
  const [error, setError] = useState("");
  const [facing, setFacing] = useState("user");
  const [mode, setMode] = useState("video");
  const [flash, setFlash] = useState(false);
  const [torch, setTorch] = useState(false); // back camera has a real torch
  const [filter, setFilter] = useState("none");
  const [showFilters, setShowFilters] = useState(false);
  const [recording, setRecording] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [screenFlash, setScreenFlash] = useState(false);
  const [thumb, setThumb] = useState("");

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
        setTorch(!!track?.getCapabilities?.()?.torch);
      } catch (e) {
        setError(e?.name === "NotAllowedError" ? "Camera access is off. Allow it in Settings, or pick a photo or video instead." : "No camera found — pick a photo or video instead.");
      }
    })();
    return () => { cancelled = true; current?.getTracks().forEach((t) => t.stop()); };
  }, [facing]);

  // Show the camera once the preview element exists.
  useEffect(() => {
    const v = videoRef.current;
    if (!v || !stream) return;
    v.srcObject = stream;
    v.play().catch(() => {});
  }, [stream]);

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
    const track = stream?.getVideoTracks()[0];
    if (!torch || !track) return false;
    try { await track.applyConstraints({ advanced: [{ torch: on }] }); return true; } catch { return false; }
  };
  const useScreenFlash = flash && !(torch && facing === "environment");

  // ---------- photo ----------
  const takePhoto = async () => {
    const v = videoRef.current;
    if (!v?.videoWidth) return;
    feedback("tap");
    if (flash) {
      if (useScreenFlash) { setScreenFlash(true); await new Promise((r) => setTimeout(r, 260)); } else { await setTorchOn(true); await new Promise((r) => setTimeout(r, 350)); }
    }
    const c = document.createElement("canvas");
    c.width = v.videoWidth; c.height = v.videoHeight;
    const ctx = c.getContext("2d");
    if (facing === "user") { ctx.translate(c.width, 0); ctx.scale(-1, 1); } // like a mirror, as you saw it
    ctx.drawImage(v, 0, 0);
    setScreenFlash(false);
    if (flash && !useScreenFlash) setTorchOn(false);
    const blob = await new Promise((r) => c.toBlob(r, "image/jpeg", 0.92));
    onCaptured({ kind: "photo", file: new File([blob], "photo.jpg", { type: "image/jpeg" }), url: URL.createObjectURL(blob), width: c.width, height: c.height, duration: 0, edits: { filter } });
  };

  // ---------- video ----------
  const startRecording = async () => {
    if (!stream) return;
    const type = pickRecorderType();
    if (!type) { toast.error("Recording isn't supported here — pick a video from your library."); return; }
    if (flash) { if (useScreenFlash) setScreenFlash(true); else await setTorchOn(true); }
    chunks.current = [];
    const rec = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 2_500_000 });
    rec.ondataavailable = (e) => { if (e.data?.size) chunks.current.push(e.data); };
    rec.onstop = async () => {
      setScreenFlash(false);
      setTorchOn(false);
      const blob = new Blob(chunks.current, { type: type.split(";")[0] });
      const url = URL.createObjectURL(blob);
      const meta = await probeVideo(url);
      const seconds = (performance.now() - startedAt.current) / 1000;
      onCaptured({ kind: "video", file: new File([blob], `reel.${type.includes("mp4") ? "mp4" : "webm"}`, { type: blob.type }), url, ...meta, duration: meta.duration || seconds, edits: { filter, mirror: facing === "user" } });
    };
    recorderRef.current = rec;
    rec.start(250);
    startedAt.current = performance.now();
    setRecording(true);
    feedback("toggle");
  };
  const stopRecording = () => {
    const rec = recorderRef.current;
    if (rec && rec.state !== "inactive") rec.stop();
    setRecording(false);
    feedback("success");
  };
  useEffect(() => {
    if (!recording) { setElapsed(0); return undefined; }
    const t = setInterval(() => {
      const s = (performance.now() - startedAt.current) / 1000;
      setElapsed(s);
      if (s >= MAX_SECONDS) stopRecording();
    }, 100);
    return () => clearInterval(t);
  }, [recording]); // eslint-disable-line react-hooks/exhaustive-deps

  const shutter = () => {
    if (mode === "photo") takePhoto();
    else if (recording) stopRecording();
    else startRecording();
  };

  // ---------- library ----------
  const pick = async (file) => {
    if (!file) return;
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

  const progress = Math.min(1, elapsed / MAX_SECONDS);
  const R = 38, C = 2 * Math.PI * R;
  return (
    <div className="absolute inset-0 flex flex-col text-white" style={{ background: screenFlash && recording ? "#fff" : "#000", transition: "background .2s" }}>
      <div className="relative flex-1 min-h-0 overflow-hidden" style={{ margin: screenFlash && recording ? 18 : 0, borderRadius: screenFlash && recording ? 28 : 0, transition: "margin .2s, border-radius .2s" }}>
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

        {/* top controls */}
        <div className="absolute top-0 inset-x-0 pt-[calc(env(safe-area-inset-top)+0.75rem)] px-3 flex items-start justify-between">
          <button onClick={onClose} className="w-11 h-11 rounded-full flex items-center justify-center" style={{ background: "rgb(0 0 0 / 0.35)" }} aria-label="Close camera"><X className="w-6 h-6" /></button>
          {recording && <span className="mt-2 px-3 py-1 rounded-full text-sm font-bold tabular-nums flex items-center gap-2" style={{ background: "rgb(239 68 68 / 0.9)" }}><span className="w-2 h-2 rounded-full bg-white animate-pulse" />{Math.floor(elapsed)}s</span>}
          <div className="flex flex-col gap-3">
            <button onClick={() => { feedback("tap"); setFacing((f) => (f === "user" ? "environment" : "user")); setThumb(""); }} disabled={recording} className="w-11 h-11 rounded-full flex items-center justify-center disabled:opacity-40" style={{ background: "rgb(0 0 0 / 0.35)" }} aria-label="Flip camera"><RefreshCcw className="w-5 h-5" /></button>
            <button onClick={() => { feedback("toggle"); setFlash((f) => !f); }} className="w-11 h-11 rounded-full flex items-center justify-center" style={{ background: flash ? "#ffd35c" : "rgb(0 0 0 / 0.35)", color: flash ? "#2a1620" : "#fff" }} aria-label={flash ? "Flash on" : "Flash off"} aria-pressed={flash} title={torch && facing === "environment" ? "Flash" : "Screen flash"}>{flash ? <Zap className="w-5 h-5 fill-current" /> : <ZapOff className="w-5 h-5" />}</button>
            <button onClick={() => { feedback("tap"); setShowFilters((v) => !v); }} className="w-11 h-11 rounded-full flex items-center justify-center" style={{ background: showFilters || filter !== "none" ? "rgb(var(--accent-rgb))" : "rgb(0 0 0 / 0.35)" }} aria-label="Filters" aria-pressed={showFilters}><Sparkles className="w-5 h-5" /></button>
          </div>
        </div>

        {showFilters && (
          <div className="absolute inset-x-0 bottom-3 px-2">
            <FilterStrip thumb={thumb} value={filter} onChange={setFilter} dark />
          </div>
        )}
      </div>

      {/* bottom controls */}
      <div className="flex-shrink-0 pt-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] px-6">
        <div className="flex items-center justify-between">
          <button onClick={() => fileRef.current?.click()} disabled={recording} className="w-12 h-12 rounded-xl flex items-center justify-center disabled:opacity-40" style={{ background: "rgb(255 255 255 / 0.14)" }} aria-label="Pick from library"><ImageIcon className="w-6 h-6" /></button>
          <button onClick={shutter} disabled={!stream} className="relative w-[88px] h-[88px] flex items-center justify-center disabled:opacity-40" aria-label={mode === "photo" ? "Take photo" : recording ? "Stop recording" : "Start recording"}>
            <svg className="absolute inset-0" viewBox="0 0 88 88" aria-hidden="true">
              <circle cx="44" cy="44" r={R} fill="none" stroke="rgb(255 255 255 / 0.35)" strokeWidth="6" />
              {recording && <circle cx="44" cy="44" r={R} fill="none" stroke="#ff4d7d" strokeWidth="6" strokeDasharray={C} strokeDashoffset={C * (1 - progress)} strokeLinecap="round" transform="rotate(-90 44 44)" />}
            </svg>
            <span className="block transition-all" style={{ width: recording ? 30 : 64, height: recording ? 30 : 64, borderRadius: recording ? 8 : 999, background: mode === "photo" ? "#fff" : "#ff4d7d" }} />
          </button>
          <span className="w-12" />
        </div>
        <div className="mt-4 flex justify-center gap-6 text-sm font-bold">
          {["photo", "video"].map((m) => (
            <button key={m} disabled={recording} onClick={() => { feedback("tab"); setMode(m); }} className="capitalize transition-opacity" style={{ opacity: mode === m ? 1 : 0.55 }}>{m}</button>
          ))}
        </div>
      </div>

      {screenFlash && !recording && <div className="fixed inset-0 z-[5] bg-white pointer-events-none" />}
      <input ref={fileRef} type="file" accept="image/*,video/*" className="hidden" onChange={(e) => { pick(e.target.files?.[0]); e.target.value = ""; }} />
    </div>
  );
}
