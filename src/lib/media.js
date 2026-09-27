// Media URLs that need resolving before an <img> / <video> can use them:
// - "localmedia:<id>" — videos and big files saved by the offline demo
//   backend in IndexedDB (localStorage is far too small for video)
// - "demo:<name>"     — generated demo music loops
import { useEffect, useState } from "react";
import { resolveAudioUrl } from "@/lib/demoAudio";

const DB = "sugerly-media";
const STORE = "files";
function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
export async function putLocalMedia(file) {
  const id = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
  const db = await openDb();
  await new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put(file, id);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
  return `localmedia:${id}`;
}
async function getLocalMedia(id) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const req = db.transaction(STORE).objectStore(STORE).get(id);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

const cache = new Map();
export async function resolveMediaUrl(url) {
  if (!url) return "";
  if (cache.has(url)) return cache.get(url);
  let out = url;
  if (url.startsWith("localmedia:")) {
    const blob = await getLocalMedia(url.slice(11)).catch(() => null);
    out = blob ? URL.createObjectURL(blob) : "";
  } else if (url.startsWith("demo:")) {
    out = await resolveAudioUrl(url);
  }
  cache.set(url, out);
  return out;
}
const needsResolving = (url) => !!url && (url.startsWith("localmedia:") || url.startsWith("demo:"));

// const src = useMediaSrc(reel.media_url)
export function useMediaSrc(url) {
  const [src, setSrc] = useState(() => (needsResolving(url) ? cache.get(url) || "" : url || ""));
  useEffect(() => {
    if (!needsResolving(url)) { setSrc(url || ""); return undefined; }
    let alive = true;
    resolveMediaUrl(url).then((u) => { if (alive) setSrc(u); });
    return () => { alive = false; };
  }, [url]);
  return needsResolving(url) ? src : url || "";
}
