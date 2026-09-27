import React, { useEffect, useRef, useState } from "react";
import { Loader2, Pause, Play, Search } from "lucide-react";
import { MUSIC_GENRES, catalogPage } from "@/lib/musicCatalog";
import LoadMore from "@/components/common/LoadMore";
import BottomSheet from "@/components/common/BottomSheet";
import { usePlayer } from "@/lib/player";
import { feedback } from "@/lib/feedback";

const PAGE = 25;

// Where the whole song plays. Record labels only let apps play 30-second
// previews of chart hits, so the full song opens in the listener's music
// app (these links open the app if it's installed, the website if not).
const FULL_SONG_APPS = [
  { id: "spotify", label: "Spotify", color: "#1DB954", url: (q) => `https://open.spotify.com/search/${encodeURIComponent(q)}` },
  { id: "apple", label: "Apple Music", color: "#FA2D48", url: (q) => `https://music.apple.com/search?term=${encodeURIComponent(q)}` },
  { id: "youtube", label: "YouTube Music", color: "#FF0000", url: (q) => `https://music.youtube.com/search?q=${encodeURIComponent(q)}` },
  { id: "deezer", label: "Deezer", color: "#A238FF", url: (q, t) => t.link || `https://www.deezer.com/search/${encodeURIComponent(q)}` },
];

// "Top charts" on the Music tab: today's hits by genre, and search. Songs
// play as 30-second previews; "Full song" opens the whole thing in Spotify,
// Apple Music, YouTube Music or Deezer. More load as you scroll.
export default function PopularMusic() {
  const player = usePlayer();
  const [genre, setGenre] = useState(0);
  const [query, setQuery] = useState("");
  const [tracks, setTracks] = useState([]);
  const [state, setState] = useState("loading"); // loading | more | done | error
  const [hasMore, setHasMore] = useState(false);
  const [fullFor, setFullFor] = useState(null);
  const next = useRef(0); // where the next page starts
  const ctrl = useRef(null);

  // First page for this genre / search…
  useEffect(() => {
    ctrl.current?.abort();
    const c = new AbortController();
    ctrl.current = c;
    setState("loading");
    setHasMore(false);
    const t = setTimeout(() => {
      catalogPage({ query, genre, index: 0, limit: PAGE, signal: c.signal })
        .then(({ tracks: list, hasMore: more }) => { next.current = PAGE; setTracks(list); setHasMore(more); setState("done"); })
        .catch((e) => { if (e.name !== "AbortError") { setTracks([]); setState("error"); } });
    }, query ? 350 : 0);
    return () => { clearTimeout(t); c.abort(); };
  }, [genre, query]);

  // …then the next ones as you scroll.
  const loadMore = () => {
    if (state !== "done" || !hasMore) return;
    const c = ctrl.current;
    setState("more");
    catalogPage({ query, genre, index: next.current, limit: PAGE, signal: c?.signal })
      .then(({ tracks: list, hasMore: more }) => {
        next.current += PAGE;
        setTracks((old) => { const seen = new Set(old.map((x) => x.id)); return [...old, ...list.filter((x) => !seen.has(x.id))]; });
        setHasMore(more && list.length > 0);
        setState("done");
      })
      .catch((e) => { if (e.name !== "AbortError") { setHasMore(false); setState("done"); } });
  };

  const play = (t) => { feedback("tap"); player.toggle(t, tracks); };
  const openFull = (t) => { feedback("tap"); if (player.track?.id === t.id && player.playing) player.toggle(t, tracks); setFullFor(t); };

  return (
    <section className="mb-10" aria-label="Discover music">
      <div className="flex items-end justify-between gap-3 mb-3">
        <div className="min-w-0">
          <h2 className="font-display text-2xl" style={{ color: "var(--text-primary)" }}>Top charts</h2>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>Today's hits · tap <strong>Full</strong> for the whole song</p>
        </div>
        <label className="flex items-center gap-2 h-10 px-3 rounded-full w-40 sm:w-60 flex-shrink-0" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)" }}>
          <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Songs or artists" className="flex-1 min-w-0 bg-transparent outline-none text-[16px] sm:text-sm" style={{ color: "var(--text-primary)" }} aria-label="Search music" />
        </label>
      </div>
      {!query && (
        <div className="flex gap-2 overflow-x-auto no-scrollbar pb-3 -mx-1 px-1">
          {MUSIC_GENRES.map((g) => (
            <button key={g.id} onClick={() => { feedback("tab"); setGenre(g.id); }} className="chip flex-shrink-0" data-active={genre === g.id} style={genre === g.id ? { background: "var(--accent-grad)", color: "#fff", borderColor: "transparent" } : undefined} aria-pressed={genre === g.id}>{g.label}</button>
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
              <button type="button" onClick={() => openFull(t)} className="tap-slop flex-shrink-0 h-8 px-3 rounded-full text-xs font-bold" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }} aria-label={`Full song: ${t.title}`}>Full</button>
            </div>
          );
        })}
      </div>
      {tracks.length > 0 && <LoadMore onMore={loadMore} hasMore={hasMore} loading={state === "more"} label="More songs" />}
      <p className="text-[11px] mt-2" style={{ color: "var(--text-muted)" }}>Previews by <a href="https://www.deezer.com" target="_blank" rel="noreferrer" className="underline">Deezer</a></p>

      <BottomSheet open={!!fullFor} onClose={() => setFullFor(null)} title="Listen to the full song" height="auto" label="Full song">
        {fullFor && (
          <div className="px-5 pb-5">
            <div className="flex items-center gap-3 mb-4">
              <span className="relative w-14 h-14 rounded-xl overflow-hidden flex-shrink-0" style={{ background: "var(--surface-2)" }}>{fullFor.cover && <img src={fullFor.cover} alt="" className="absolute inset-0 w-full h-full object-cover" />}</span>
              <div className="min-w-0">
                <p className="font-bold truncate" style={{ color: "var(--text-primary)" }}>{fullFor.title}</p>
                <p className="text-sm truncate" style={{ color: "var(--text-muted)" }}>{fullFor.artist}</p>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {FULL_SONG_APPS.map((a) => (
                <a key={a.id} href={a.url(`${fullFor.artist} ${fullFor.title}`, fullFor)} target="_blank" rel="noreferrer" onClick={() => { feedback("tap"); setFullFor(null); }} className="flex items-center gap-2.5 h-12 px-3 rounded-2xl font-bold text-sm" style={{ background: "var(--surface-2)", color: "var(--text-primary)", border: "1px solid var(--border-c)" }}>
                  <span className="w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: a.color }}><Play className="w-3 h-3 text-white fill-white ml-px" /></span>
                  {a.label}
                </a>
              ))}
            </div>
            <p className="text-[11px] mt-3 text-center" style={{ color: "var(--text-muted)" }}>Opens the song in your music app. Labels only allow 30-second previews inside other apps.</p>
          </div>
        )}
      </BottomSheet>
    </section>
  );
}
