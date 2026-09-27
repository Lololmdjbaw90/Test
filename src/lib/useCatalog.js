import { useCallback, useEffect, useRef, useState } from "react";
import { catalogPage } from "./musicCatalog";

export function useCatalog({ query = "", genre = 0 } = {}) {
  const [tracks, setTracks] = useState([]);
  const [state, setState] = useState("loading");
  const [hasMore, setHasMore] = useState(true);
  const session = useRef(null);
  const loadMore = useCallback(async () => {
    const s = session.current;
    if (!s || s.busy || s.done || s.ctrl.signal.aborted) return;
    s.busy = true;
    setState("loading");
    try {
      const page = await catalogPage({ query: s.query, genre: s.genre, offset: s.offset, signal: s.ctrl.signal });
      if (session.current !== s || s.ctrl.signal.aborted) return;
      s.offset = page.nextOffset;
      s.done = !page.hasMore;
      setTracks(prev => [...new Map([...prev, ...page.tracks].map(t => [t.id, t])).values()]);
      setHasMore(page.hasMore);
      setState("done");
    } catch (e) {
      if (session.current === s && e.name !== "AbortError") setState("error");
    } finally { s.busy = false; }
  }, []);
  useEffect(() => {
    const s = { query, genre, offset: 0, busy: false, done: false, ctrl: new AbortController() };
    session.current = s;
    setTracks([]); setHasMore(true); setState("loading");
    const timer = setTimeout(loadMore, query ? 350 : 0);
    return () => { clearTimeout(timer); s.ctrl.abort(); };
  }, [query, genre, loadMore]);
  return { tracks, state, hasMore, loadMore };
}
