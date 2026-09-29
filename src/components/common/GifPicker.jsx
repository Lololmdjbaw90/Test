import React, { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { Link2, Loader2, Search, X } from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { fetchGifs, normalizeGifUrl, useGifKey } from "@/lib/gifs";
import { feedback } from "@/lib/feedback";

// A Discord-style GIF panel: trending GIFs, search as you type, tap to send.
export default function GifPicker({ onPick, onClose, className = "" }) {
  const { user } = useAuth();
  const { key, loading: keyLoading } = useGifKey();
  const [query, setQuery] = useState("");
  const [gifs, setGifs] = useState([]);
  const [state, setState] = useState("idle");
  const [error, setError] = useState("");
  const [link, setLink] = useState("");
  const inputRef = useRef(null);

  useEffect(() => { inputRef.current?.focus({ preventScroll: true }); }, [key]);
  useEffect(() => {
    if (!key) return undefined;
    const ctrl = new AbortController();
    setState("loading");
    const t = setTimeout(() => {
      fetchGifs(key, query.trim(), { signal: ctrl.signal })
        .then((list) => { setGifs(list); setState("done"); })
        .catch((e) => { if (e.name !== "AbortError") { setError(e.message); setState("error"); } });
    }, query ? 300 : 0);
    return () => { clearTimeout(t); ctrl.abort(); };
  }, [key, query]);

  const choose = (url) => { feedback("send"); onPick(url); };
  const pasted = normalizeGifUrl(link);

  return (
    <div className={`rounded-3xl overflow-hidden liquid-glass ${className}`} role="dialog" aria-label="GIFs">
      <div className="flex items-center gap-2 p-2">
        <div className="flex-1 flex items-center gap-2 h-10 px-3 rounded-full" style={{ background: "var(--surface-2)" }}>
          <Search className="w-4 h-4 flex-shrink-0" style={{ color: "var(--text-muted)" }} />
          <input ref={inputRef} value={key ? query : link} onChange={(e) => (key ? setQuery(e.target.value) : setLink(e.target.value))} placeholder={key ? "Search GIPHY" : "Paste a GIF link"} className="flex-1 min-w-0 bg-transparent outline-none text-[16px] sm:text-sm" style={{ color: "var(--text-primary)" }} aria-label={key ? "Search GIFs" : "GIF link"} />
        </div>
        <button type="button" onClick={onClose} className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: "var(--surface-2)" }} aria-label="Close GIFs"><X className="w-4 h-4" /></button>
      </div>

      {key ? (
        <>
          <div className="h-60 overflow-y-auto overscroll-contain px-2 pb-2">
            {state === "loading" && !gifs.length && <div className="h-full flex items-center justify-center"><Loader2 className="w-6 h-6 animate-spin" style={{ color: "var(--text-muted)" }} /></div>}
            {state === "error" && <p className="text-sm text-center py-10" style={{ color: "var(--danger)" }}>{error}</p>}
            {state === "done" && !gifs.length && <p className="text-sm text-center py-10" style={{ color: "var(--text-muted)" }}>No GIFs for “{query}”</p>}
            <div className="columns-2 sm:columns-3 gap-1.5 [column-fill:_balance]">
              {gifs.map((g) => (
                <button key={g.id} type="button" onClick={() => choose(g.url)} className="mb-1.5 block w-full rounded-xl overflow-hidden active:scale-95 transition-transform" style={{ aspectRatio: `${g.width} / ${g.height}`, background: "var(--surface-2)" }} aria-label={`Send GIF: ${g.title}`}>
                  <img src={g.preview} alt={g.title} loading="lazy" className="w-full h-full object-cover" />
                </button>
              ))}
            </div>
          </div>
          <p className="text-[10px] font-bold text-center pb-2 tracking-wide" style={{ color: "var(--text-muted)" }}>POWERED BY GIPHY</p>
        </>
      ) : (
        <div className="px-4 pb-4 pt-1 space-y-3 text-sm" style={{ color: "var(--text-secondary)" }}>
          {pasted ? (
            <button type="button" onClick={() => choose(pasted)} className="block mx-auto rounded-2xl overflow-hidden max-w-[220px] active:scale-95 transition-transform" aria-label="Send this GIF"><img src={pasted} alt="GIF preview" className="w-full" /></button>
          ) : (
            <p className="flex items-start gap-2"><Link2 className="w-4 h-4 mt-0.5 flex-shrink-0" /> {keyLoading ? "Loading…" : "Paste a link to a GIF (GIPHY, Tenor or any .gif)."}</p>
          )}
          {!keyLoading && (user?.role === "admin"
            ? <p className="text-xs">To search GIFs, add a free GIPHY key in <Link to="/Admin?tab=settings" className="font-bold underline" onClick={onClose}>Admin → Site → GIFs</Link>.</p>
            : <p className="text-xs" style={{ color: "var(--text-muted)" }}>GIF search isn't switched on yet.</p>)}
        </div>
      )}
    </div>
  );
}
