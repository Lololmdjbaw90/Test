// Popular music for the Music tab: the Deezer charts and search (no key
// needed). Deezer's API has no CORS headers, so it's read with JSONP (a
// <script> tag), which works in browsers and in the iPhone / iPad app.
// Songs are Deezer's official 30-second previews, with album covers.
const API = "https://api.deezer.com";

export const MUSIC_GENRES = [
  { id: 0, label: "Top" }, { id: 132, label: "Pop" }, { id: 116, label: "Hip-Hop" }, { id: 113, label: "Dance" },
  { id: 165, label: "R&B" }, { id: 152, label: "Rock" }, { id: 197, label: "Latin" }, { id: 106, label: "Electro" }, { id: 16, label: "K-Pop & Asian" },
];

let seq = 0;
function jsonp(url, signal) {
  return new Promise((resolve, reject) => {
    const cb = `__sugerlyMusic${Date.now()}_${seq++}`;
    const script = document.createElement("script");
    const cleanup = () => { script.remove(); setTimeout(() => { delete window[cb]; }, 0); };
    window[cb] = (data) => { cleanup(); resolve(data); };
    script.onerror = () => { cleanup(); reject(new Error("Couldn't reach the music catalog.")); };
    signal?.addEventListener("abort", () => { window[cb] = () => cleanup(); reject(new DOMException("Aborted", "AbortError")); });
    script.src = `${url}${url.includes("?") ? "&" : "?"}output=jsonp&callback=${cb}`;
    document.head.appendChild(script);
  });
}

const toTrack = (t) => ({
  id: `deezer_${t.id}`,
  title: t.title_short || t.title,
  artist: t.artist?.name || "",
  src: t.preview,
  cover: t.album?.cover_big || t.album?.cover_medium || t.artist?.picture_medium || "",
  duration: 30,
  link: t.link || "https://www.deezer.com",
  kind: "catalog",
});

export async function catalogTracks({ query = "", genre = 0, limit = 30, signal } = {}) {
  const url = query.trim()
    ? `${API}/search?q=${encodeURIComponent(query.trim())}&limit=${limit}`
    : `${API}/chart/${genre}/tracks?limit=${limit}`;
  const json = await jsonp(url, signal);
  if (json?.error) throw new Error("The music catalog is busy — try again in a moment.");
  return (json?.data || []).filter((t) => t?.preview).map(toTrack);
}
