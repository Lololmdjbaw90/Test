import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { base44 } from "@/api/base44Client";
import { sortRecords } from "@/api/queryUtils";
import { useLiveQuery } from "./useLiveQuery";

// Only the first page is live. Older pages use stable field/id cursors,
// avoiding an ever-growing realtime listener or offset scan.
export function usePagedQuery(entity, query = null, { sort = "-created_date", limit = 30, enabled = true } = {}) {
  const head = useLiveQuery(entity, query, { sort, limit, enabled });
  const [older, setOlder] = useState([]);
  const [more, setMore] = useState(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [pageError, setPageError] = useState(null);
  const key = JSON.stringify([entity, query, sort, limit, enabled]);
  const run = useRef({ key, cursor: null, busy: false });
  const previousHead = useRef({ key, rows: [] });
  // Invalidate pending work immediately when the query identity changes.
  if (run.current.key !== key) run.current = { key, cursor: null, busy: false };
  if (previousHead.current.key !== key) previousHead.current = { key, rows: [] };
  useEffect(() => { setOlder([]); setMore(null); setLoadingMore(false); setPageError(null); }, [key]);
  useEffect(() => () => { run.current = { key: null }; }, []);
  useEffect(() => {
    if (head.loading || head.error) return;
    const currentIds = new Set(head.data.map(row => row.id));
    const dropped = previousHead.current.rows.filter(row => !currentIds.has(row.id));
    previousHead.current.rows = head.data;
    if (!dropped.length) return;
    const tail = head.data.at(-1);
    // In a limited listener, a new record can push an existing row off the
    // first page without deleting it. Keep those rows in the loaded history.
    const displaced = tail && head.data.length >= limit
      ? dropped.filter(row => sortRecords([tail, row], sort)[1]?.id === row.id)
      : [];
    const displacedIds = new Set(displaced.map(row => row.id));
    const deletedIds = new Set(dropped.filter(row => !displacedIds.has(row.id)).map(row => row.id));
    setOlder(rows => sortRecords([...new Map([...rows.filter(row => !deletedIds.has(row.id)), ...displaced].map(row => [row.id, row])).values()], sort));
  }, [head.data, head.loading, head.error, limit, sort]);
  const data = useMemo(() => {
    const seen = new Set();
    return [...head.data, ...older].filter(row => { if (seen.has(row.id)) return false; seen.add(row.id); return true; });
  }, [head.data, older]);
  const loadMore = useCallback(async () => {
    const request = run.current;
    if (head.error && !head.loading) { await head.reload(); return; }
    if (!enabled || request.busy || head.loading || !head.data.length || more === false) return;
    request.busy = true;
    setLoadingMore(true); setPageError(null);
    const last = head.data.at(-1);
    const field = sort.replace(/^-/, "");
    try {
      const page = await base44.entities[entity].page(query, { sort, limit, cursor: request.cursor || { id: last.id, value: last[field] } });
      if (run.current !== request) return;
      request.cursor = page.cursor;
      setOlder(previous => [...new Map([...previous, ...page.rows].map(row => [row.id, row])).values()]);
      setMore(page.hasMore);
    } catch (error) { if (run.current === request) setPageError(error); }
    finally { request.busy = false; if (run.current === request) setLoadingMore(false); }
  }, [key, head.data, head.loading, head.error, head.reload, more]); // eslint-disable-line react-hooks/exhaustive-deps
  const setData = useCallback(updater => {
    head.setData(updater);
    setOlder(updater);
  }, [head.setData]);
  return { ...head, data, setData, loadMore, loadingMore, error: pageError || head.error, hasMore: enabled && (more ?? head.data.length >= limit) };
}
