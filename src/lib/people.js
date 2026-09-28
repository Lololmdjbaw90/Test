import { useEffect, useMemo, useSyncExternalStore } from "react";
import { base44 } from "@/api/base44Client";

// People looked up by email (30 per request) and remembered for the visit,
// plus the most recently active ones for suggestions and pickers, so pages
// never download every account (there could be millions).
const cache = new Map(); // email -> user, or null when there's no account
const pending = new Set();
const listeners = new Set();
let version = 0;
let recent = null;
let recentLoad = null;
const emit = () => { version += 1; listeners.forEach((l) => l()); };
const subscribe = (l) => { listeners.add(l); return () => listeners.delete(l); };
const getVersion = () => version;
const remember = (rows) => rows.forEach((u) => { if (u?.email) cache.set(u.email, u); });

async function fetchEmails(emails) {
  const todo = [...new Set(emails)].filter((e) => e && !cache.has(e) && !pending.has(e));
  if (!todo.length) return;
  todo.forEach((e) => pending.add(e));
  for (let i = 0; i < todo.length; i += 30) {
    const chunk = todo.slice(i, i + 30);
    remember(await base44.entities.User.filter({ email: { $in: chunk } }, null, 30).catch(() => []));
    chunk.forEach((e) => { pending.delete(e); if (!cache.has(e)) cache.set(e, null); });
  }
  emit();
}

function loadRecent(limit) {
  if (!recentLoad) {
    recentLoad = base44.entities.User.list("-last_seen", limit).catch(() => []).then((rows) => {
      recent = rows;
      remember(rows);
      emit();
    });
  }
  return recentLoad;
}

// The most recently active people plus everyone in `emails` (authors on
// screen, members, and so on), as one list.
export function usePeople(emails = [], { recentLimit = 300 } = {}) {
  const v = useSyncExternalStore(subscribe, getVersion, getVersion);
  const key = [...new Set((emails || []).filter(Boolean))].sort().join("\n");
  useEffect(() => { loadRecent(recentLimit); }, [recentLimit]);
  useEffect(() => { if (key) fetchEmails(key.split("\n")); }, [key]);
  return useMemo(() => {
    const out = new Map();
    (recent || []).forEach((u) => out.set(u.email, cache.get(u.email) || u));
    if (key) key.split("\n").forEach((e) => { const u = cache.get(e); if (u) out.set(e, u); });
    return [...out.values()];
  }, [v, key]); // eslint-disable-line react-hooks/exhaustive-deps
}
