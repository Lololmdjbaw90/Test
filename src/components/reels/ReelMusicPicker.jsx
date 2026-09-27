import React, { useState } from "react";
import { useCatalog } from "@/lib/useCatalog";
import LoadMore from "@/components/common/LoadMore";

export default function ReelMusicPicker({ selected, onPick }) {
  const [query, setQuery] = useState("");
  const { tracks, state, hasMore, loadMore } = useCatalog({ query });
  return <section aria-label="Choose reel music" className="space-y-2">
    <input aria-label="Search reel music" value={query} onChange={e => setQuery(e.target.value)} placeholder="Search songs or artists" className="w-full rounded-xl p-2 text-black" />
    <p className="text-xs opacity-70">Chart music · 30-second previews</p>
    <div className="max-h-44 overflow-y-auto">
      {tracks.map(track => <button key={track.id} type="button" aria-pressed={selected?.url === track.src} onClick={() => onPick({ url: track.src, title: track.title, artist: track.artist })} className="w-full p-2 flex items-center gap-3 rounded-xl text-left" style={{ background: selected?.url === track.src ? "#ffffff30" : "transparent" }}>
        <img src={track.cover} alt="" loading="lazy" className="w-9 h-9 rounded-lg" />
        <span className="min-w-0"><span className="block text-sm font-bold truncate">{track.title}</span><span className="block text-xs opacity-70 truncate">{track.artist}</span></span>
      </button>)}
      {state === "done" && !tracks.length && <p className="text-sm p-2">No songs found.</p>}
      <LoadMore hasMore={hasMore} loading={state === "loading"} error={state === "error"} onLoad={loadMore} />
    </div>
  </section>;
}
