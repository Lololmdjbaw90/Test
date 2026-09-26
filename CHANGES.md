# Changes

## Fonts, sounds & haptics, better artwork viewer (this update)

### New
- **Brand fonts**: Bubbly for titles and headings (with Cute Here filling in digits and punctuation Bubbly doesn't have) and Cute Here for small labels. Plus Jakarta Sans is now bundled too, so no fonts load from Google: the app draws its first screen immediately and works offline.
- **Sounds & haptics**: a matching tap on iPhone/iPad and a tiny sound for likes, saves, sending, success/error messages, new notifications and messages, tab switches and toggles. Sounds follow the iPhone's silent switch; both can be turned off in Settings → Sounds & haptics.
- **Artwork viewer, reorganised for phones and tablets**: a big image you can swipe left/right between pieces and tap for full screen (with a "3 / 12" counter), then title, artist, one row of Like / Save / Share / Ping buttons, the description, and a small separate row for admin tools.

### Fixed
- Top Artists: the crown no longer sits on the #1 ring, and the gold/silver/bronze rings are real circles that stay round on every screen.
- Viewers (artwork, post, commission, group info) no longer open scrolled down to the comment box or pop up the keyboard.


## Sugerly logo, smoother app, admin owner (this update)

### New
- **Sugerly branding**: the new logo in the sidebar, top bar, login, onboarding and loading screens, plus new app icons, favicons and iOS splash screens. The app is now called Sugerly everywhere people see it (internal ids like the iOS bundle id are unchanged so existing installs and saved data keep working).
- **Site owner**: paologionfriddo90@gmail.com is always an admin and is the only one who can add or remove admins (Admin panel → Users). Enforced in the Firestore rules too.
- The profile **Saved** tab now shows saved Community posts as well as saved gallery pieces.

### Faster
- Firebase lists now use one live listener instead of a fetch plus a listener (half the reads, no re-sorting for every document), and writes no longer re-read your profile first.
- Page, list and looping animations run in CSS on the GPU instead of JavaScript; the sidebar highlight no longer measures the page on every navigation.
- No full-screen blur, blend modes or blurred floating shapes on phones and tablets; the music equalizer no longer re-lays out the page every frame; images load lazily and decode off the main thread.
- In a benchmark with the CPU slowed 4× (like a tablet), pages do about half as much work while idle and 30–70% less while scrolling.

### Fixed
- **Friends** could sit on the loading skeleton forever: friends and requests now show without waiting for the whole member list, lists stop "loading" after 10 seconds at most, and the suggestions tolerate unusual profile data.
- A crash inside one page now shows a "Try again / Reload" screen instead of a blank app.
- Gallery cards show the like button and title on touch screens (they only appeared on mouse hover before).


## Server roles & permissions, smoother animations, .ipa builds (this update)

### New
- **Role permissions** for servers: administrator, manage server / channels / roles, kick members, create invites, send messages, attach images, add reactions, mention roles & @everyone, pin messages, manage messages, and voice connect / speak / video.
- **@everyone defaults**, a **role hierarchy** with reordering (you can only manage roles and people below your highest role, and can't hand out permissions you don't have), and **private channels**.
- `@Role` and `@everyone` mentions now notify people (with the Mention permission).
- **.ipa builds without a Mac**: a GitHub Actions workflow builds the iOS app and uploads an `.ipa` to install with Sideloadly / AltStore. See `IOS_APP.md`.

### Fixed
- Security: members could give themselves roles and remove other people from a server by writing to the database directly; creating channels/roles and posting now also check server membership and permissions in the Firestore rules.
- "Jump to latest" buttons slid in off-centre; DM bubbles, comments and notifications could slide from stale positions after scrolling.
- The Community feed renders 10 posts at a time and loads more as you scroll.
- Active chips / tab pills: the glow was cut off in a hard rectangle and gradients left a light sliver at the edges.
- Hover lifts and shine effects no longer stick after tapping on iPhone / iPad.

### Firebase
- Server rules changed and Community docs gain `perm_index` / `everyone_permissions`. Redeploy: `firebase deploy --only firestore:rules`. The permission index fills in automatically the first time an owner or role manager opens each server.

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
