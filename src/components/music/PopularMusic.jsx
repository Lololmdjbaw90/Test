import React, { useEffect, useRef, useState } from "react";
import { ExternalLink, Loader2, Pause, Play, Search } from "lucide-react";
import { MUSIC_GENRES, catalogPage } from "@/lib/musicCatalog";
import { AUDIUS_GENRES, audiusTracks } from "@/lib/audius";
import LoadMore from "@/components/common/LoadMore";
import { usePlayer } from "@/lib/player";
import { feedback } from "@/lib/feedback";

const PAGE = 25;
const SOURCES = [
  { id: "charts", label: "Top charts" },
  { id: "full", label: "Full songs" },
];

// Discover music on the Music tab:
// - Top charts: today's hits (Deezer), 30-second previews — that's all the
//   big labels allow apps to play.
// - Full songs: whole tracks from independent artists (Audius).
// Both load more as you scroll.
export default function PopularMusic() {
  const player = usePlayer();
  const [source, setSource] = useState("charts");
  const [genre, setGenre] = useState(0);
  const [fullGenre, setFullGenre] = useState("All");
  const [query, setQuery] = useState("");
  const [tracks, setTracks] = useState([]);
  const [state, setState] = useState("loading"); // loading | more | done | error
  const [hasMore, setHasMore] = useState(false);
  const next = useRef(0); // charts: where the next page starts
  const all = useRef([]); // full songs: everything fetched, shown a page at a time
  const ctrl = useRef(null);

  // First page for this source / genre / search…
  useEffect(() => {
    ctrl.current?.abort();
    const c = new AbortController();
    ctrl.current = c;
    setState("loading");
    setHasMore(false);
    const t = setTimeout(() => {
      const first = source === "full"
        ? audiusTracks({ query, genre: fullGenre, signal: c.signal }).then((list) => {
          all.current = list;
          return { tracks: list.slice(0, PAGE), hasMore: list.length > PAGE };
        })
        : catalogPage({ query, genre, index: 0, limit: PAGE, signal: c.signal });
      first
        .then(({ tracks: list, hasMore: more }) => { next.current = PAGE; setTracks(list); setHasMore(more); setState("done"); })
        .catch((e) => { if (e.name !== "AbortError") { setTracks([]); setState("error"); } });
    }, query ? 350 : 0);
    return () => { clearTimeout(t); c.abort(); };
  }, [source, genre, fullGenre, query]);

  // …then the next ones as you scroll.
  const loadMore = () => {
    if (state !== "done" || !hasMore) return;
    if (source === "full") {
      next.current += PAGE;
      setTracks(all.current.slice(0, next.current));
      setHasMore(all.current.length > next.current);
      return;
    }
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

  return (
    <section className="mb-10" aria-label="Discover music">
      <div className="flex items-end justify-between gap-3 mb-3">
        <div className="min-w-0">
          <div className="flex gap-1 p-1 rounded-full w-max mb-2" role="tablist" aria-label="Music source" style={{ background: "var(--surface-2)" }}>
            {SOURCES.map((x) => (
              <button key={x.id} role="tab" aria-selected={source === x.id} onClick={() => { if (x.id !== source) { feedback("tab"); setSource(x.id); } }} className="px-3.5 py-1.5 rounded-full font-display text-lg leading-none transition-colors" style={{ background: source === x.id ? "var(--surface)" : "transparent", color: source === x.id ? "var(--text-primary)" : "var(--text-muted)", boxShadow: source === x.id ? "var(--shadow-sm)" : "none" }}>{x.label}</button>
            ))}
          </div>
          {source === "full" ? (
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>Whole songs from independent artists on <a href="https://audius.co" target="_blank" rel="noreferrer" className="font-semibold underline">Audius</a></p>
          ) : (
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>Today's hits · 30-second previews from <a href="https://www.deezer.com" target="_blank" rel="noreferrer" className="font-semibold underline">Deezer</a></p>
          )}
        </div>
        <label className="flex items-center gap-2 h-10 px-3 rounded-full w-40 sm:w-60 flex-shrink-0" style={{ background: "var(--surface-2)", border: "1px solid var(--border-c)" }}>
          <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Songs or artists" className="flex-1 min-w-0 bg-transparent outline-none text-[16px] sm:text-sm" style={{ color: "var(--text-primary)" }} aria-label="Search music" />
        </label>
      </div>
      {!query && (
        <div className="flex gap-2 overflow-x-auto no-scrollbar pb-3 -mx-1 px-1">
          {source === "full"
            ? AUDIUS_GENRES.map((g) => (
              <button key={g} onClick={() => { feedback("tab"); setFullGenre(g); }} className="chip flex-shrink-0" data-active={fullGenre === g} style={fullGenre === g ? { background: "var(--accent-grad)", color: "#fff", borderColor: "transparent" } : undefined} aria-pressed={fullGenre === g}>{g === "All" ? "Trending" : g}</button>
            ))
            : MUSIC_GENRES.map((g) => (
              <button key={g.id} onClick={() => { feedback("tab"); setGenre(g.id); }} className="chip flex-shrink-0" data-active={genre === g.id} style={genre === g.id ? { background: "var(--accent-grad)", color: "#fff", borderColor: "transparent" } : undefined} aria-pressed={genre === g.id}>{g.label}</button>
            ))}
        </div>
      )}
      {state === "loading" && !tracks.length && <div className="py-10 flex justify-center"><Loader2 className="w-6 h-6 animate-spin" style={{ color: "var(--text-muted)" }} /></div>}
      {state === "error" && <p className="text-sm py-6 text-center" style={{ color: "var(--text-muted)" }}>{source === "full" ? "Couldn't reach Audius right now — try again in a moment." : "Couldn't load the charts right now — try again in a moment."}</p>}
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
              <a href={t.link} target="_blank" rel="noreferrer" className="icon-btn w-8 h-8 flex-shrink-0" aria-label={`Open ${t.title} on ${t.kind === "audius" ? "Audius" : "Deezer"}`}><ExternalLink className="w-3.5 h-3.5" /></a>
            </div>
          );
        })}
      </div>
      {tracks.length > 0 && <LoadMore onMore={loadMore} hasMore={hasMore} loading={state === "more"} label="More songs" />}
    </section>
  );
}
