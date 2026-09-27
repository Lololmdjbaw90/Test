// GIFs from GIPHY, for comments and chats (like Discord's GIF picker).
// -----------------------------------------------------------------------------
// GIPHY needs a free API key: https://developers.giphy.com → Create an App →
// API. An admin pastes it once in Admin → Site → GIFs (it's saved in the site
// settings), or set VITE_GIPHY_KEY when building. Without a key people can
// still paste a GIF link.
// -----------------------------------------------------------------------------
import { useLiveQuery } from "@/lib/useLiveQuery";

const ENV_KEY = import.meta.env.VITE_GIPHY_KEY || "";

export function useGifKey() {
  const { data, loading } = useLiveQuery("SiteConfig", { key: "global" }, { live: false });
  return { key: ENV_KEY || data[0]?.giphy_key || "", loading: !ENV_KEY && loading };
}

const pick = (g) => {
  const i = g.images || {};
  const small = i.fixed_width_downsampled || i.fixed_width || i.downsized || i.original;
  const full = i.fixed_width || i.downsized_medium || i.original;
  return {
    id: g.id,
    title: g.title || "GIF",
    preview: small?.webp || small?.url,
    url: full?.webp || full?.url,
    width: Number(full?.width) || 200,
    height: Number(full?.height) || 200,
  };
};

export async function fetchGifs(key, query = "", { limit = 24, offset = 0, signal } = {}) {
  const params = new URLSearchParams({ api_key: key, limit: String(limit), offset: String(offset), rating: "pg-13", bundle: "messaging_non_clips" });
  if (query) params.set("q", query);
  const res = await fetch(`https://api.giphy.com/v1/gifs/${query ? "search" : "trending"}?${params}`, { signal });
  if (res.status === 401 || res.status === 403) throw new Error("The GIF key isn't valid — check it in Admin → Site → GIFs.");
  if (res.status === 429) throw new Error("Too many GIF searches right now — try again in a minute.");
  if (!res.ok) throw new Error("Couldn't load GIFs.");
  const json = await res.json();
  return (json.data || []).map(pick).filter((g) => g.url);
}

// Links people paste: GIPHY / Tenor pages or any direct .gif / .webp.
export function normalizeGifUrl(raw) {
  const text = String(raw || "").trim();
  if (!/^https:\/\//i.test(text)) return "";
  const giphy = text.match(/giphy\.com\/(?:gifs|media)\/(?:[^/]*-)?([A-Za-z0-9]{8,})/);
  if (giphy) return `https://i.giphy.com/${giphy[1]}.webp`;
  if (/\.(gif|webp)(\?.*)?$/i.test(text) || /^https:\/\/(media\d*\.)?(giphy|tenor)\.com\//i.test(text) || /^https:\/\/media\.tenor\.com\//i.test(text)) return text;
  return "";
}
