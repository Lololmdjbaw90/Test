# Changes

## iPhone & iPad app, safety tools and polish (this update)

### New
- **Native iOS app** (Capacitor): Xcode project in `ios/` for iPhone and iPad with app icon, light/dark launch screens, camera/mic/photos permissions, background audio, haptics, status bar that follows the theme and the tab bar hiding while typing. `npm run ios` builds and opens it. See `IOS_APP.md`.
- **Installable web app**: new icons, manifest, and a service worker that precaches the app so it starts instantly and offline (recent images are kept too). Install tip on phones/tablets and a "Get the app" section in Settings.
- **Report** posts and people; admins review them in **Admin → Reports**.
- **Block** people from a post or profile: hides their posts, comments, messages, notifications and calls. Manage in Settings.
- **Delete account** in Settings (asks for your password, removes your content and sign-in).

### Improved
- Safe areas for the notch / Dynamic Island / home indicator; no zoom-in when tapping text fields on iPhone; no grey tap flash; no whole-app rubber-banding.
- Buttons that only appeared on mouse hover are now always visible on touch screens; message actions appear when you tap a message.
- Back button on phones, tap the current tab to scroll to top, page titles, offline notice, toasts that no longer cover the tab bar, mini player clear of the home indicator.
- The tab bar steps aside inside a conversation; iPad portrait uses the compact sidebar.
- Share/invite links use your public site address (also inside the app).
- `/AdminPanel` now redirects to the admin page.

## Calls, social feed and recommendations (this update)

### New
- **Voice & video calls** in DMs and group chats: ringing card with accept / accept with video / decline, 45s ring timeout, "call in progress" banner to join, and call summaries in the chat (missed, declined, duration).
- **Voice channels rebuilt**: lobby showing who's inside, call stage with video tiles, spotlight for screen shares, picture-in-picture self view, per-person volume, mic/camera picker, join/leave sounds. The connection survives navigation, with a "return to call" bar at the top of the app.
- **Social Community feed**: stories-style row, double-tap to like, "liked by", inline comments, save/bookmarks, share, hashtags, trending tags, suggested people and servers, "Not interested".
- **Recommendation engine** (`src/lib/ranking.js`) for the feed, Home, suggested people, Friends → Discover, Servers → Discover and Music.
- **Music home**: picked-for-you hero, Made for you shelf, trending chart with play counts, moods, artists, friend activity.
- **Server member profile cards** from the member list and chat avatars (roles, bio, join dates, message, kick).
- Mobile: "More" sheet with every page, bottom-sheet menus, tap-to-show message actions.

### Fixed
- Open/close animations that stuttered or froze (CSS hover effects fought framer-motion transforms; dialogs emptied while closing; menus got clipped or landed off-screen on phones).
- Profile stats overflowing on narrow phones.

### Firebase
- New `Call` collection with rules and an index, and a rule letting anyone bump a track's play count by exactly one. Redeploy: `firebase deploy --only firestore:rules,firestore:indexes`.

## Redesign + everything working (this update)

### Fixed
- **Realtime was broken in Firebase mode**: chat, DMs and notifications expected create/update/delete events but Firebase sent whole snapshots. Both backends now emit the same events.
- **Friends, DMs and group chats failed under the Firestore rules** (queries weren't filtered to the signed-in user). All queries are now rule-compliant.
- Sorted + filtered Firestore queries no longer need composite indexes to work (client-side fallback); `firestore.indexes.json` is included for speed.
- **Security**: server chat rendered messages with `dangerouslySetInnerHTML` (anyone could inject HTML/script). Messages are now rendered safely with links and @mentions.
- Server pages got stuck loading for normal members (they tried to create member rows for other people); `Community.filter({ id })` never matched in Firestore.
- Server chat loaded the oldest 100 messages instead of the newest.
- Mobile channel drawer rendered empty; channel/server settings were shown to everyone.
- DM window wiped the message list on every new message in local mode.
- Dark mode didn't apply to dialogs; the page layout remounted on every navigation; onboarding showed inside the sidebar layout.
- Profile owners couldn't delete guestbook messages under the rules; group members couldn't leave groups.
- Seeded commissions all showed as "Closed"; gallery filters didn't match seeded mediums.
- Windows-only `node_modules` and a stale `dist/` were committed — both are now git-ignored (run `npm install`).
- Removed the scraped `rendered-styles.css` and the placeholder stub components.

### New
- Full redesign: new typography (Fraunces + Plus Jakarta Sans), glass sidebar, soft gradients, light/dark/system themes and five accent colors.
- Animations throughout: page transitions, staggered reveals, 3D tilt cards, like bursts, confetti, animated podium, count-ups, equalizers, a spinning vinyl player.
- Home dashboard with daily rewards and streaks.
- Ctrl/⌘ K command palette (people, art, posts, servers, tracks, actions).
- Global music mini player that keeps playing across pages; demo tracks play in offline mode.
- Gallery viewer with keyboard navigation, saves/bookmarks, sorting, share links.
- Community composer (text or image posts), Top this week / Following tabs.
- Servers: templates, roles (create/color/assign), role-restricted channels, pins panel, replies, reactions, @mention autocomplete + notifications, search, invites, leave/kick, delete server.
- **Voice channels across devices** (Firestore signalling) with live "who's in voice".
- DMs: read receipts, reactions, images, emoji picker, group info (add/remove/leave), unread badges and new-message toasts.
- Friends/follow system with follower counts, profile guestbook, name styles (premium ones via MimiNitro), coin shop.
- Commissions with tiers, delivery times, sample galleries and "message the artist".
- Admin: stats, activity chart, promote/demote admins, content moderation, site announcement banner + default accent, logs timeline.
- Password reset email (Firebase), friendlier auth errors, data export, "reset demo data".
- `npm run dev:demo`, `npm run emulators` + `npm run dev:emulator` for testing against local Firebase emulators.

## Firebase-connected version

- Added your Firebase web config to `.env` and `.env.example`.
- Added `.firebaserc` linked to `umikoworks-86333`.
- Added real Firebase Authentication login and create-account flow.
- Added Firestore-backed users, posts, artworks, comments, likes, follows, servers, channels, messages, direct messages, group chats, notifications, and site settings.
- Added real direct-message chat instead of the placeholder shell.
- Added `DirectMessage` to local and Firebase backend entities.
- Added Firestore security rules so users cannot edit or delete other users’ content.
- Added Storage rules for authenticated user uploads.
- Updated deployment instructions with clean Firebase commands.
