// Shared query helpers used by both the local and the Firebase backend so that
// `filter()` / `subscribe()` behave identically no matter where data lives.
//
// Query objects map field -> condition:
//   { channel_id: "abc" }                      equality
//   { member_emails: { $contains: "a@b.c" } }  array contains value
//   { status: { $in: ["open", "paused"] } }    value is one of
//   { created_date: { $lt: "2025-01-01" } }    before / after ($lt, $gt)
//
// Sort strings are a field name, prefixed with "-" for descending.

export function isOperator(value) {
  return !!value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).some((k) => k.startsWith("$"));
}

export function matchesQuery(record, query) {
  if (!query) return true;
  if (!record) return false;
  return Object.keys(query).every((field) => {
    const cond = query[field];
    const value = record[field];
    if (isOperator(cond)) {
      if ("$contains" in cond && !(Array.isArray(value) && value.includes(cond.$contains))) return false;
      if ("$in" in cond && !(Array.isArray(cond.$in) && cond.$in.includes(value))) return false;
      if ("$lt" in cond && !(value != null && value < cond.$lt)) return false;
      if ("$gt" in cond && !(value != null && value > cond.$gt)) return false;
      return true;
    }
    if (Array.isArray(cond)) return JSON.stringify(cond) === JSON.stringify(value);
    return value === cond;
  });
}

export function sortRecords(records, sort) {
  if (!sort) return records;
  const desc = sort.charAt(0) === "-";
  const field = desc ? sort.slice(1) : sort;
  const sorted = [...records].sort((a, b) => {
    const av = a?.[field], bv = b?.[field];
    if (av == null && bv == null) return 0;
    if (av == null) return -1;
    if (bv == null) return 1;
    if (typeof av === "number" && typeof bv === "number") return av - bv;
    const as = String(av), bs = String(bv);
    return as < bs ? -1 : as > bs ? 1 : 0;
  });
  return desc ? sorted.reverse() : sorted;
}

export function sortAndLimit(records, sort, limit) {
  const sorted = sortRecords(records, sort);
  return limit != null ? sorted.slice(0, limit) : sorted;
}

// Apply a realtime event ({ type, id, data }) to a list held in React state.
// Creates and updates are upserts so duplicate deliveries are harmless.
export function applyEvent(list, event, { sort, prepend = false } = {}) {
  if (!event) return list;
  if (event.type === "delete") return list.filter((r) => r.id !== event.id);
  if (!event.data) return list;
  const exists = list.some((r) => r.id === event.data.id);
  let next = exists
    ? list.map((r) => (r.id === event.data.id ? { ...r, ...event.data } : r))
    : prepend ? [event.data, ...list] : [...list, event.data];
  if (sort) next = sortRecords(next, sort);
  return next;
}
