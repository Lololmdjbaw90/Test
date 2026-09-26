# Sugerly

A cozy home for artists: a curated gallery, a community feed, music sharing,
Discord-style servers with text + voice channels, direct messages and group
chats, voice/video calls, commissions, profiles with levels and a coin shop.
Runs as a website, an installable app, and a native **iPhone / iPad app**.

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

Then open http://localhost:3000.
Demo login (offline mode only): **admin@mimilocks.local / admin123**.

## Reels

- `src/pages/Reels.jsx` — the feed (For you / Following, `?r=<id>` opens a reel, `?tag=` filters, `?create=1` opens the studio).
- `src/lib/reelRank.js` — the recommendation algorithm (explained at the top of the file). Watch signals stay on the device.
- `src/components/reels/` — the player (`ReelMedia`), one reel with its buttons (`ReelItem`), the camera with multi-clip recording (`ReelCamera`), the editor with undo / redo (`ReelEditor`), the cuts filmstrip (`ClipTimeline`), text stickers (`Sticker`) and the studio flow (`ReelStudio`).
- `src/lib/clips.js` — video cuts. Reels are never re-encoded: `edits.clips` lists the parts of the original video to play, in order, and the player jumps between them.
- `src/lib/filters.js` — the filter presets: CSS for previews and videos, the same maths as a colour matrix for photos.
- Reel data lives in the `Reel` collection; comments use `CommunityComment` with `post_id = "reel_<id>"`.
- In the offline demo, videos are kept in IndexedDB (`src/lib/media.js`).

## App updates

`src/lib/updates.js` holds the release notes that ship with the app (add a new entry at the top for each release). Admins can also post updates from the What's new page; they're stored in the `AppUpdate` collection.

## Fonts, sounds & haptics

- Fonts are bundled with the app: Bubbly (headings), Cute Here (labels and
  Bubbly's missing digits) and Plus Jakarta Sans (body). Sources are in
  `brand/`, the web versions in `src/assets/fonts/`.
- `src/lib/feedback.js` plays haptics (native Taptic Engine in the iOS app)
  and tiny synthesized sounds: `feedback("like" | "save" | "send" | "success" |
  "error" | "notify" | "tab" | "toggle" | "tap" | "swipe")`. People can turn
  either off in Settings → Sounds & haptics.

## Admins

**paologionfriddo90@gmail.com** is the site owner: always an admin, and the
only account that can make or remove admins (Admin panel → Users → Make admin /
Remove admin). Other admins can moderate but can't change anyone's role or edit
the owner. To change the owner, edit `SITE_OWNERS` in `src/lib/admin.js` **and**
`siteOwners()` in `firestore.rules`, then redeploy the rules.

## iPhone, iPad and installable app

- **Installable web app** — open the site in Safari → Share → Add to Home
  Screen (Chrome / Edge / Android get an Install button). Full screen, works
  offline, app icon, splash.
- **Native iOS app** — `npm run ios` builds the site and opens the Xcode
  project in `ios/` (iPhone + iPad) on a Mac. No Mac? GitHub Actions builds an
  `.ipa` for you (install it with Sideloadly / AltStore).

Step-by-step instructions, including TestFlight / App Store: **[IOS_APP.md](IOS_APP.md)**.

## Features

- **Home dashboard** — greeting, level/XP progress, daily reward with streaks,
  featured art, trending posts, fresh tracks, top artists, friends online, your servers.
- **Gallery** — masonry grid with 3D tilt, filters, sorting, search, saved
  collection, full-screen viewer (← / → keys), comments, pings, share links,
  soundtrack playback. Admins upload and feature pieces.
- **Community** — a social feed: story-style row of people who posted recently,
  double-tap to like, "liked by" friends, inline comments, save, share,
  hashtags with trending tags, suggested people and servers, and
  For you / Following / Latest / Top / Saved tabs.
- **Smart recommendations** — the "For you" feed, suggested people, servers
  and music are ranked from who you follow and befriend, what you like,
  comment on and listen to, your interests, engagement, freshness and
  variety. Every pick shows why ("Liked by Luna", "Follows you"…), and
  "Not interested" tunes it. See `src/lib/ranking.js`.
- **Music** — a streaming-style home: picked-for-you hero, Made for you,
  trending chart with play counts, browse by mood, artists, friend activity
  (what friends are listening to); a global mini player keeps playing while
  you browse; shuffle, queue, seek.
- **Servers** — templates, text + voice channels, roles with colors,
  role-restricted channels, pins, replies, reactions, @mentions (with
  notifications), search, member list with profile cards (roles, bio, join
  dates, quick message), invites, kick, server settings.
- **Roles & permissions** — Discord-style: administrator, manage server /
  channels / roles, kick, invites, send, attach, react, mention roles, pin,
  manage messages, and voice connect / speak / video. An @everyone set of
  defaults, a role hierarchy (you can only manage people and roles below
  you), private channels and posting limits per role. Management actions
  (channels, roles, kicking, deleting/pinning others' messages, server
  settings) and server membership are also enforced by the Firestore rules.
- **Voice channels & calls** — WebRTC voice/video with camera, screen
  sharing, speaking indicators, mute/deafen, per-person volume and device
  picker. Voice channels show who's inside before you join; DMs and group
  chats have voice/video calls with ringing, decline, missed-call and
  duration messages. The call keeps running while you browse (a "return to
  call" bar sits at the top). Works across devices with Firebase.
- **Messages** — DMs and group chats with read receipts, reactions, images,
  emoji picker, unread badges and new-message toasts.
- **Friends, profiles, followers** — friend requests, follow, guestbook, name
  styles, levels, MimiNitro and an XP boost in the coin shop.
- **Commissions** — tiers with prices and delivery times, sample galleries,
  open/closed status, message the artist.
- **Admin** — stats, 14-day activity chart, user roles, content moderation,
  a Reports queue, server management, site announcement banner, default
  accent, activity logs.
- **Safety** — report posts and people, block users (hides their posts,
  comments, messages, notifications and calls), automatic text moderation,
  and full account deletion in Settings.
- **Everywhere** — Ctrl/⌘ K command palette, light/dark/system themes, five
  accent colors, notifications, toasts, reduced-motion support. Phone layout
  with a bottom tab bar, back button and safe areas for the notch and home
  indicator; compact sidebar on iPad; offline notice.

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
  lib/          auth context, theme, player, voice, calls, ranking, safety, permissions,
                pwa (install + service worker), native (iOS app), helpers
  pwa/          service worker template (built to /sw.js)
  components/   layout (sidebar, palette, mini player), common UI, feature components
  pages/        one file per route
ios/            native iPhone/iPad app (Capacitor + Xcode), see IOS_APP.md
```

All data access goes through `base44.entities.<Name>` (`list`, `filter`, `get`,
`create`, `update`, `delete`, `subscribe`), so pages work the same on both backends.
