import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { resolveAudioUrl } from "@/lib/demoAudio";
import { base44 } from "@/api/base44Client";
import { recordPlay } from "@/lib/ranking";
import { addOne } from "@/lib/likes";

// Listening history feeds music recommendations; shared tracks ({ kind: "track" })
// also get a public play count, bumped once per track per session.
const countedPlays = new Set();
function onTrackStart(t) {
  recordPlay(t);
  // "Friend activity" on the Music page shows what people are listening to.
  if (t.kind === "track") base44.auth.updateMe({ listening: { id: t.id, title: t.title, artist: t.artist, cover: t.cover || "", at: Date.now() } }).catch(() => {});
  if (t.kind !== "track" || countedPlays.has(t.id)) return;
  countedPlays.add(t.id);
  base44.entities.MusicReview.get(t.id)
    .then((row) => row && addOne("MusicReview", row, "plays"))
    .catch(() => {});
}

// Global audio player: tracks keep playing while you move around the site.
// track = { id, title, artist, src, cover }
const PlayerContext = createContext(null);

export function PlayerProvider({ children }) {
  const audioRef = useRef(null);
  const [track, setTrack] = useState(null);
  const [queue, setQueue] = useState([]);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolumeState] = useState(() => {
    const v = parseFloat(localStorage.getItem("mimilocks:__volume"));
    return Number.isFinite(v) ? v : 0.8;
  });

  useEffect(() => { if (audioRef.current) audioRef.current.volume = volume; }, [volume]);

  const load = useCallback((next) => {
    const audio = audioRef.current;
    if (!audio || !next) return;
    setTrack(next);
    setTime(0);
    setDuration(0);
    audio.src = resolveAudioUrl(next.src);
    audio.play().catch(() => setPlaying(false));
    onTrackStart(next);
  }, []);

  const play = useCallback((next, list) => {
    if (!next?.src) return;
    if (list) setQueue(list.filter((t) => t.src));
    if (track?.id === next.id) { audioRef.current?.play().catch(() => {}); return; }
    load(next);
  }, [track?.id, load]);

  const pause = useCallback(() => audioRef.current?.pause(), []);
  const toggle = useCallback((next, list) => {
    if (next && track?.id !== next.id) { play(next, list); return; }
    const audio = audioRef.current;
    if (!audio || !track) return;
    if (audio.paused) audio.play().catch(() => {}); else audio.pause();
  }, [track, play]);

  const step = useCallback((dir) => {
    if (!track || queue.length === 0) return;
    const i = queue.findIndex((t) => t.id === track.id);
    const next = queue[(i + dir + queue.length) % queue.length];
    if (next) load(next);
  }, [track, queue, load]);

  const seek = useCallback((seconds) => {
    if (audioRef.current && Number.isFinite(seconds)) audioRef.current.currentTime = seconds;
  }, []);

  const setVolume = useCallback((v) => {
    setVolumeState(v);
    try { localStorage.setItem("mimilocks:__volume", String(v)); } catch { /* ignore */ }
  }, []);

  const close = useCallback(() => {
    audioRef.current?.pause();
    setTrack(null);
    setPlaying(false);
  }, []);

  const value = useMemo(() => ({
    track, queue, playing, time, duration, volume,
    play, pause, toggle, next: () => step(1), prev: () => step(-1), seek, setVolume, close,
    isCurrent: (id) => track?.id === id,
    isPlaying: (id) => track?.id === id && playing,
  }), [track, queue, playing, time, duration, volume, play, pause, toggle, step, seek, setVolume, close]);

  return (
    <PlayerContext.Provider value={value}>
      {children}
      <audio
        ref={audioRef}
        preload="metadata"
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onTimeUpdate={(e) => setTime(e.currentTarget.currentTime)}
        onLoadedMetadata={(e) => setDuration(e.currentTarget.duration || 0)}
        onEnded={() => (queue.length > 1 ? step(1) : setPlaying(false))}
        onError={() => setPlaying(false)}
      />
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const ctx = useContext(PlayerContext);
  if (!ctx) throw new Error("usePlayer must be used within a PlayerProvider");
  return ctx;
}

export function formatTime(s) {
  if (!Number.isFinite(s) || s < 0) return "0:00";
  const m = Math.floor(s / 60);
  return `${m}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
}
