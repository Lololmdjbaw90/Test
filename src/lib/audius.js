// Real music on the Music tab from Audius (https://audius.co): a free, open
// music platform with an API that needs no key. Songs stream straight from
// Audius; we show the artist and link back, as Audius asks.
const API = "https://api.audius.co/v1";
const APP = "Sugerly";

export const AUDIUS_GENRES = ["All", "Electronic", "Hip-Hop/Rap", "Pop", "Lo-Fi", "R&B/Soul", "Alternative", "Ambient", "Rock"];

const toTrack = (t) => ({
  id: `audius_${t.id}`,
  title: t.title,
  artist: t.user?.name || "Audius artist",
  src: `${API}/tracks/${t.id}/stream?app_name=${APP}`,
  cover: t.artwork?.["480x480"] || t.artwork?.["150x150"] || "",
  genre: t.genre || "",
  mood: t.mood || "",
  duration: t.duration || 0,
  plays: t.play_count || 0,
  link: t.permalink ? `https://audius.co${t.permalink}` : "https://audius.co",
  kind: "audius",
});

export async function audiusTracks({ query = "", genre = "All", limit = 24, signal } = {}) {
  const params = new URLSearchParams({ app_name: APP, limit: String(limit) });
  let path = "/tracks/trending";
  if (query.trim()) { path = "/tracks/search"; params.set("query", query.trim()); }
  else if (genre && genre !== "All") params.set("genre", genre);
  const res = await fetch(`${API}${path}?${params}`, { signal });
  if (!res.ok) throw new Error("Couldn't reach Audius right now.");
  const json = await res.json();
  return (json.data || []).filter((t) => t && t.id && t.is_streamable !== false).map(toTrack);
}
