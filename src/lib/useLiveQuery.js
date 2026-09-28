import { useCallback, useEffect, useRef, useState } from "react";
import { base44 } from "@/api/base44Client";
import { applyEvent } from "@/api/queryUtils";

// A list that never loads (dead connection, stalled request) shouldn't leave
// a page on skeletons forever: after this long we show whatever we have.
const LOADING_TIMEOUT = 10000;

// Loads an entity list and keeps it in sync with realtime create/update/delete
// events from either backend.
//
//   const { data, loading, reload, setData } = useLiveQuery("CommunityPost", null, { sort: "-created_date" });
//   const { data } = useLiveQuery("Comment", { artwork_id: id }, { sort: "created_date", enabled: !!id });
export function useLiveQuery(entityName, query = null, { sort = null, limit = null, enabled = true, live = true, onEvent } = {}) {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(enabled);
  const [error, setError] = useState(null);
  const key = JSON.stringify([entityName, query, sort, limit]);
  const onEventRef = useRef(onEvent);
  onEventRef.current = onEvent;
  const version = useRef(0);

  const load = useCallback(async () => {
    const entity = base44.entities[entityName];
    const run = ++version.current;
    setLoading(true);
    try {
      const rows = query ? await entity.filter(query, sort, limit) : await entity.list(sort, limit);
      if (run === version.current) { setData(rows); setError(null); }
    } catch (e) {
      if (run === version.current) { setError(e); console.warn(`[useLiveQuery] ${entityName}:`, e?.message || e); }
    } finally {
      if (run === version.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  useEffect(() => {
    if (!enabled) { setData([]); setLoading(false); return undefined; }
    const entity = base44.entities[entityName];
    const watchdog = setTimeout(() => setLoading(false), LOADING_TIMEOUT);

    // Firebase: one listener delivers the first page and every change after
    // it, so each list is read once instead of twice.
    if (live && entity.watch) {
      let active = true;
      setLoading(true);
      const unsub = entity.watch(query, { sort, limit }, (rows, changes) => {
        if (!active) return;
        version.current++; // a snapshot is newer than any reload() in flight
        setData(rows);
        setError(null);
        setLoading(false);
        changes.forEach((ev) => onEventRef.current?.(ev));
      }, (e) => {
        if (!active) return;
        setError(e);
        setLoading(false);
      });
      return () => { active = false; clearTimeout(watchdog); unsub?.(); };
    }

    load().finally(() => clearTimeout(watchdog));
    if (!live) return () => { clearTimeout(watchdog); version.current++; };
    const unsub = entity.subscribe((event) => {
      setData((prev) => applyEvent(prev, event, { sort }));
      if (!event.initial) onEventRef.current?.(event);
    }, query, { sort, limit });
    return () => { clearTimeout(watchdog); version.current++; unsub?.(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, enabled, live]);

  return { data, setData, loading, error, reload: load };
}

// Older pages behind a newest-first live list (long chats): `older` holds
// what loadOlder() fetched, newest first, `more` whether there may be more.
//
//   const { older, more, loadOlder } = useOlderPages("DirectMessage", q, raw, { pageSize: 100, liveLimit: 200 });
export function useOlderPages(entityName, query, rows, { pageSize = 100, liveLimit = 0 } = {}) {
  const [older, setOlder] = useState([]);
  const [more, setMore] = useState(true);
  const [busy, setBusy] = useState(false);
  const key = JSON.stringify([entityName, query]);
  useEffect(() => { setOlder([]); setMore(true); }, [key]);
  const loadOlder = useCallback(async () => {
    const oldest = [...rows, ...older].map((r) => r.created_date).filter(Boolean).sort()[0];
    if (!oldest || busy) return;
    setBusy(true);
    try {
      const page = await base44.entities[entityName].filter({ ...query, created_date: { $lt: oldest } }, "-created_date", pageSize);
      setOlder((o) => {
        const have = new Set([...rows, ...o].map((r) => r.id));
        return [...o, ...page.filter((r) => !have.has(r.id))];
      });
      setMore(page.length >= pageSize);
    } catch (e) {
      console.warn(`[useOlderPages] ${entityName}:`, e?.message || e);
    } finally {
      setBusy(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, rows, older, busy, pageSize]);
  return { older, more: more && rows.length >= liveLimit, loadOlder, busy };
}
