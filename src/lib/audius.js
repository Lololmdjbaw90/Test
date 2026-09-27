// Full-length songs from Audius (https://audius.co): a free, open music
// platform where independent artists share their music. The API needs no
// key; songs stream straight from Audius and we credit the artist and link
// back, as Audius asks. (Chart hits only exist as 30-second previews for
// apps — see musicCatalog.js.)
const API = "https://api.audius.co/v1";
const APP = "Sugerly";

export const AUDIUS_GENRES = ["All", "Electronic", "Hip-Hop/Rap", "Pop", "Lo-Fi", "R&B/Soul", "Alternative", "Ambient", "Rock"];

const toTrack = (t) => ({
  id: `audius_${t.id}`,
  title: t.title,
  artist: t.user?.name || "Audius artist",
  src: `${API}/tracks/${t.id}/stream?app_name=${APP}`,
  cover: t.artwork?.["480x480"] || t.artwork?.["150x150"] || "",
  duration: t.duration || 0,
  link: t.permalink ? `https://audius.co${t.permalink}` : "https://audius.co",
  kind: "audius",
});

// Trending (or search results) — up to 100 songs; the list shows them a
// page at a time.
export async function audiusTracks({ query = "", genre = "All", limit = 100, signal } = {}) {
  const params = new URLSearchParams({ app_name: APP, limit: String(limit) });
  let path = "/tracks/trending";
  if (query.trim()) { path = "/tracks/search"; params.set("query", query.trim()); }
  else if (genre && genre !== "All") params.set("genre", genre);
  const res = await fetch(`${API}${path}?${params}`, { signal });
  if (!res.ok) throw new Error("Couldn't reach Audius right now.");
  const json = await res.json();
  return (json.data || []).filter((t) => t && t.id && t.is_streamable !== false).map(toTrack);
}
