// "What's new": release notes that ship with the app, plus notes admins post
// from the Updates page (AppUpdate records). People see a one-time popup
// after an update and a dot on "What's new" until they've read it.
import { useEffect, useMemo, useState } from "react";
import { useLiveQuery } from "@/lib/useLiveQuery";

export const RELEASES = [
  {
    id: "v2.2", version: "2.2", date: "2026-09-27T08:00:00Z", emoji: "💬", title: "Replies, GIFs & Liquid Glass",
    items: [
      "Comments: reply to anyone, like comments, see the creator's replies, add emoji in one tap — and send GIFs.",
      "GIFs in comments, DMs and server chats (search GIPHY or paste any GIF link).",
      "Turn comments off on your reels when you post, or later from the ⋯ menu.",
      "A real iOS tab bar made of Liquid Glass in the iPhone and iPad app, and the app layout on iPad.",
      "A cleaner menu: the main places up front, big icons for exploring, the rest tucked away.",
      "Smoother scrolling and animations, and the logo no longer blinks.",
    ],
  },
  {
    id: "v2.1", version: "2.1", date: "2026-09-26T13:00:00Z", emoji: "✂️", title: "Video cuts & fancy text",
    items: [
      "Film in several clips: tap (or hold) to record, tap again to pause, delete the last clip, then tap ✓.",
      "Cuts in the editor: split at the playhead, delete, duplicate, reorder and trim every clip.",
      "Text you can pinch to resize and twist to rotate (or use the corner handle), with 5 fonts, 5 styles, 8 animations and a start / end time. Drag it to the bin to delete.",
      "Undo and redo for every edit, a 3s / 10s camera timer, and smoother, snappier Reels.",
      "In Reels: hold to watch at 2x, drag the progress bar to skip, and your new reel opens first after you post it.",
      "✨ Write with AI: get three caption ideas with hashtags from your picture when you post a reel or in Community.",
    ],
  },
  {
    id: "v2.0", version: "2.0", date: "2026-09-26T12:00:00Z", emoji: "🎬", title: "Reels are here",
    items: [
      "Reels: a full-screen feed of short videos and photos — swipe up for the next one, double-tap to like.",
      "A smart For you feed that learns from what you watch all the way through, re-watch, like, save and skip — and keeps learning while you scroll.",
      "Film right in the app with the front or back camera, flash (a bright screen flash for selfies), live filters and photo mode.",
      "A video editor: trim, filters, text you can drag anywhere, speed, music from Sugerly tracks and a cover frame.",
      "Photo filters when you share a post in Community.",
      "A redesigned post view: swipe between posts, double-tap to like, follow from the post, and \"More like this\".",
    ],
  },
  {
    id: "v1.9", version: "1.9", date: "2026-09-26T11:00:00Z", emoji: "🔊", title: "Cuter fonts, sounds & haptics",
    items: [
      "New Bubbly and Cute Here fonts for titles and labels.",
      "Little sounds and iPhone haptics for likes, saves, messages and more (Settings → Sounds & haptics).",
      "A tidier artwork view on phones and tablets, with swipe and full screen.",
      "Top Artists: proper gold, silver and bronze rings and a floating crown.",
    ],
  },
  {
    id: "v1.8", version: "1.8", date: "2026-09-26T10:00:00Z", emoji: "🍬", title: "Hello, Sugerly",
    items: [
      "Our new name and logo.",
      "Faster and smoother everywhere, especially on iPad.",
      "The Friends page no longer gets stuck loading, and your profile's Saved tab shows saved posts too.",
    ],
  },
  {
    id: "v1.7", version: "1.7", date: "2026-09-26T09:00:00Z", emoji: "🛡️", title: "Server roles & the iPhone app",
    items: [
      "Roles and permissions for servers, with private channels.",
      "Sugerly as an iPhone and iPad app.",
    ],
  },
];

const SEEN_KEY = "mimilocks:__updates_seen";
export function getUpdatesSeen() { try { return localStorage.getItem(SEEN_KEY) || ""; } catch { return ""; } }
export function markUpdatesSeen(iso = new Date().toISOString()) {
  try { localStorage.setItem(SEEN_KEY, iso); } catch { /* private mode */ }
  window.dispatchEvent(new Event("mimilocks:updates-seen"));
}

// Everything, newest first: [{ id, date, title, emoji, version?, items?, body?, custom? }]
export function useUpdates() {
  const { data: posted, loading } = useLiveQuery("AppUpdate", null, { sort: "-created_date", limit: 50 });
  const all = useMemo(() => [
    ...posted.map((u) => ({ id: u.id, date: u.created_date, title: u.title, emoji: u.emoji || "📣", body: u.body, custom: true, author: u.author_name })),
    ...RELEASES,
  ].sort((a, b) => new Date(b.date) - new Date(a.date)), [posted]);
  return { updates: all, loading };
}

// Unread updates for this person. New accounts start "caught up"; people who
// joined before an update see it.
export function useUnseenUpdates(user) {
  const { updates, loading } = useUpdates();
  const [seen, setSeen] = useState(getUpdatesSeen);
  useEffect(() => {
    const on = () => setSeen(getUpdatesSeen());
    window.addEventListener("mimilocks:updates-seen", on);
    return () => window.removeEventListener("mimilocks:updates-seen", on);
  }, []);
  const since = seen || user?.created_date || new Date().toISOString();
  const unseen = loading || !user ? [] : updates.filter((u) => new Date(u.date) > new Date(since));
  return { unseen, updates };
}
