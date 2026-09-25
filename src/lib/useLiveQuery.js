import { useCallback, useEffect, useRef, useState } from "react";
import { base44 } from "@/api/base44Client";
import { applyEvent } from "@/api/queryUtils";

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
    load();
    if (!live) return () => { version.current++; };
    const unsub = base44.entities[entityName].subscribe((event) => {
      setData((prev) => applyEvent(prev, event, { sort }));
      if (!event.initial) onEventRef.current?.(event);
    }, query, { sort, limit });
    return () => { version.current++; unsub?.(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, enabled, live]);

  return { data, setData, loading, error, reload: load };
}
