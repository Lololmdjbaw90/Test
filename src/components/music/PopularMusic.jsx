import React, { useEffect, useState } from "react";
import { ExternalLink, Loader2, Pause, Play, Search } from "lucide-react";
import { MUSIC_GENRES, catalogTracks } from "@/lib/musicCatalog";
import { usePlayer } from "@/lib/player";
import { feedback } from "@/lib/feedback";

// "Top charts" on the Music tab: popular songs by genre, and search.
export default function PopularMusic() {
  const player = usePlayer();
  const [genre, setGenre] = useState(0);
  const [query, setQuery] = useState("");
  const [tracks, setTracks] = useState([]);
  const [state, setState] = useState("loading");

  useEffect(() => {
    const ctrl = new AbortController();
    setState("loading");
    const t = setTimeout(() => {
      catalogTracks({ query, genre, signal: ctrl.signal })
        .then((list) => { setTracks(list); setState("done"); })
        .catch((e) => { if (e.name !== "AbortError") setState("error"); });
    }, query ? 350 : 0);
    return () => { clearTimeout(t); ctrl.abort(); };
  }, [genre, query]);

  const play = (t) => { feedback("tap"); player.toggle(t, tracks); };

  return (
    <section className="mb-10" aria-label="Discover music">
      <div className="flex items-end justify-between gap-3 mb-3">
        <div>
          <h2 className="font-display text-2xl" style={{ color: "var(--text-primary)" }}>Top charts</h2>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>Today's most popular songs · 30-second previews from <a href="https://www.deezer.com" target="_blank" rel="noreferrer" className="font-semibold underline">Deezer</a></p>
        </div>
        <label className="flex items-center gap-2 h-10 px-3 rounded-full w-44 sm:w-60" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)" }}>
          <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Songs or artists" className="flex-1 min-w-0 bg-transparent outline-none text-[16px] sm:text-sm" style={{ color: "var(--text-primary)" }} aria-label="Search music" />
        </label>
      </div>
      {!query && (
        <div className="flex gap-2 overflow-x-auto no-scrollbar pb-3 -mx-1 px-1">
          {MUSIC_GENRES.map((g) => (
            <button key={g.id} onClick={() => { feedback("tab"); setGenre(g.id); }} className="flex-shrink-0 px-3.5 py-1.5 rounded-full text-xs font-bold transition-colors" style={{ background: genre === g.id ? "var(--accent-grad)" : "var(--surface-2)", color: genre === g.id ? "#fff" : "var(--text-secondary)" }} aria-pressed={genre === g.id}>{g.label}</button>
          ))}
        </div>
      )}
      {state === "loading" && !tracks.length && <div className="py-10 flex justify-center"><Loader2 className="w-6 h-6 animate-spin" style={{ color: "var(--text-muted)" }} /></div>}
      {state === "error" && <p className="text-sm py-6 text-center" style={{ color: "var(--text-muted)" }}>Couldn't load the charts right now — try again in a moment.</p>}
      {state === "done" && !tracks.length && <p className="text-sm py-6 text-center" style={{ color: "var(--text-muted)" }}>No songs found.</p>}
      <div className="grid sm:grid-cols-2 gap-2">
        {tracks.map((t, i) => {
          const current = player.track?.id === t.id;
          const playing = current && player.playing;
          return (
            <div key={t.id} className="rise-in flex items-center gap-3 p-2 rounded-2xl transition-colors" style={{ "--d": `${Math.min(i, 10) * 25}ms`, background: current ? "var(--pink-soft)" : "var(--surface)", border: "1px solid var(--border-c)" }}>
              <button onClick={() => play(t)} className="relative w-14 h-14 rounded-xl overflow-hidden flex-shrink-0 active:scale-95 transition-transform" style={{ background: "var(--surface-2)" }} aria-label={playing ? `Pause ${t.title}` : `Play ${t.title}`}>
                {t.cover && <img src={t.cover} alt="" loading="lazy" className="absolute inset-0 w-full h-full object-cover" />}
                <span className="absolute inset-0 flex items-center justify-center" style={{ background: "rgb(0 0 0 / 0.28)" }}>{playing ? <Pause className="w-5 h-5 text-white fill-white" /> : <Play className="w-5 h-5 text-white fill-white ml-0.5" />}</span>
              </button>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold truncate" style={{ color: "var(--text-primary)" }}>{t.title}</p>
                <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}><span className="font-bold tabular-nums">{i + 1}</span> · {t.artist}</p>
              </div>
              <a href={t.link} target="_blank" rel="noreferrer" className="icon-btn w-8 h-8 flex-shrink-0" aria-label={`Open ${t.title} on Deezer`}><ExternalLink className="w-3.5 h-3.5" /></a>
            </div>
          );
        })}
      </div>
    </section>
  );
}
