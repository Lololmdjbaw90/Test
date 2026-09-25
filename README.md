# Mimi Locks

A cozy home for artists: a curated gallery, a community feed, music sharing,
Discord-style servers with text + voice channels, direct messages and group
chats, commissions, profiles with levels and a coin shop.

## Stack

React 18 · Vite · Tailwind CSS · Framer Motion · React Router 6 ·
Firebase (Auth, Firestore, Storage) — with an offline demo backend that runs
entirely in the browser when Firebase isn't configured.

## Quick start

```bash
npm install
npm run dev          # uses Firebase if .env has a config (it does in this repo)
npm run dev:demo     # offline demo with sample data, no Firebase needed
```

Demo login (offline mode only): **admin@mimilocks.local / admin123**.

## Features

- **Home dashboard** — greeting, level/XP progress, daily reward with streaks,
  featured art, trending posts, fresh tracks, top artists, friends online, your servers.
- **Gallery** — masonry grid with 3D tilt, filters, sorting, search, saved
  collection, full-screen viewer (← / → keys), comments, pings, share links,
  soundtrack playback. Admins upload and feature pieces.
- **Community** — post images or text, likes with a heart burst, comments,
  Latest / Top this week / Following tabs, deep links to posts, moderation.
- **Music** — upload tracks with cover, genre and mood; a global mini player
  keeps playing while you browse; shuffle, queue, seek.
- **Servers** — templates, text + voice channels, roles with colors,
  role-restricted channels, pins, replies, reactions, @mentions (with
  notifications), search, member list, invites, kick, server settings.
- **Voice channels** — WebRTC calls with speaking indicators, mute/deafen and
  live "who's in voice" in the channel list. Works across devices with Firebase.
- **Messages** — DMs and group chats with read receipts, reactions, images,
  emoji picker, unread badges and new-message toasts.
- **Friends, profiles, followers** — friend requests, follow, guestbook, name
  styles, levels, MimiNitro and an XP boost in the coin shop.
- **Commissions** — tiers with prices and delivery times, sample galleries,
  open/closed status, message the artist.
- **Admin** — stats, 14-day activity chart, user roles, content moderation,
  server management, site announcement banner, default accent, activity logs.
- **Everywhere** — Ctrl/⌘ K command palette, light/dark/system themes, five
  accent colors, notifications, toasts, responsive mobile layout with a
  bottom nav, reduced-motion support.

## Environment

| Variable | Purpose |
| --- | --- |
| `VITE_FIREBASE_*` | Firebase web config (already in `.env`). |
| `VITE_BACKEND=local` | Force the offline demo backend. |
| `VITE_FIREBASE_EMULATOR_HOST` | Use local Firebase emulators. |
| `VITE_TURN_URL`, `VITE_TURN_USERNAME`, `VITE_TURN_CREDENTIAL` | Optional TURN relay for voice on strict networks. |
| `VITE_DISCORD_WEBHOOK_URL` | Optional Discord alerts when moderation blocks content. |

## Firebase

See `FIREBASE_SETUP.md`. In short: enable Email/Password auth, Firestore and
Storage, then deploy rules **and indexes**:

```bash
npx firebase-tools deploy --only firestore:rules,firestore:indexes,storage
```

### Testing against emulators

```bash
npm run emulators      # terminal 1 (needs Java)
npm run dev:emulator   # terminal 2
```

The emulators enforce the real `firestore.rules` / `storage.rules` and use a
`demo-` project, so nothing touches production data.

## Project layout

```
src/
  api/          base44Client (backend switch), firebaseBackend, localBackend, queryUtils
  lib/          auth context, theme, player, voice, live queries, toasts, helpers
  components/   layout (sidebar, palette, mini player), common UI, feature components
  pages/        one file per route
```

All data access goes through `base44.entities.<Name>` (`list`, `filter`, `get`,
`create`, `update`, `delete`, `subscribe`), so pages work the same on both backends.
