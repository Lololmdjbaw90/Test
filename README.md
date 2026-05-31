# Mimi Locks — Complete Source Export

## Stack
React 18 + Vite + Tailwind CSS + Framer Motion
Base44 SDK (auth, database, file uploads, AI/LLM, real-time subscriptions)
React Router v6 + TanStack React Query

## Setup
1. npm install
2. Copy .env.example → .env and fill in VITE_BASE44_APP_ID
3. npm run dev

## Env Variables
VITE_BASE44_APP_ID=your_app_id
VITE_DISCORD_WEBHOOK_URL=your_discord_webhook_url   # optional, for moderation alerts

## Notes
Most files contain complete, runnable source code.
A small number of large server/community sub-components are marked "Full source: see ... in Base44 Code tab".
Their full source is in the Base44 dashboard → Code tab → click the file name.
Core pages (App, Layout, Gallery, Profile, Communities, CommunityChat, Friends, Commissions,
DirectMessages), ChatArea, MemberList, ArtworkCard and all config files are fully embedded.

## Entities (database schemas)
Artwork, ArtworkPing, ChannelMessage, Comment, Commission, Community,
CommunityComment, CommunityPost, CustomEmoji, DirectMessage, Friendship,
GroupChat, Log, MusicReview, Notification, ServerChannel, ServerMember,
ServerRole, SiteConfig, Sticker, Webhook

## Real Firebase backend

This version includes a Firebase backend adapter. Add a `.env` file using `.env.example`, enable Firebase Authentication, Firestore and Storage, then run `npm install` and `npm run dev`.

Without Firebase env vars, the app falls back to local browser demo storage.

See `FIREBASE_SETUP.md` and `DEPLOYMENT.md`.
