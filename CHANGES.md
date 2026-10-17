# Changes

## A new camera (iOS app)

- **Rebuilt from scratch** in `native/Sugerly/Views/Camera/` (the old `CameraRecorder.swift` is gone). `CaptureCore` owns the capture session and does all camera work on its own queue (setting up, flipping, zooming, focus, torch, recording), so the screen never waits for the hardware. `CameraEngine` is what the screen reads: clips, lenses, zoom, focus, exposure, filter, recording state.
- **Lenses**: the back camera is the best virtual device (triple, dual wide, dual, wide), so 0.5× / 1× / 2× / 3× stops switch lenses by themselves, like the Camera app; pinch and hold-and-slide zoom keep working. Clips are 1080p with video stabilisation.
- **Focus and light**: tap to focus and expose there, slide up or down for brighter or darker, hold to lock both (AE/AF lock); the camera takes over again when the scene changes.
- **Live filters**: the same `ReelFilter`s as the editor, drawn live from a video data output through Core Image onto a sample-buffer display layer (only while a filter is on). Clips are filmed clean and the editor opens with the filter already on (`EditorModel.startWith`).
- **Screen**: the camera window is the reel's 9:16 shape under the status bar (full screen on 9:16 phones), with a clip bar, a labelled tool rail (icons only when space is short), lens stops, a new record button with a tick per clip, a two-tap delete, a discard question, and progress while clips are joined. Photos are cropped to what the window showed.
- **Joining clips** (`ClipStitcher`): one clip at normal speed is used as is; same-camera clips at normal speed are copied without re-encoding; anything else (front and back mixed, slow or fast clips) is drawn upright into one 1080×1920 video, so no clip comes out sideways or mirrored the wrong way.

## Better calls, smoother editor, whole landscape slides (iOS app)

- **Calls keep going outside the app**: `CallPiP` shows the other person's camera or screen in iOS's video-call picture-in-picture window (`AVPictureInPictureVideoCallViewController`) when you leave Sugerly; frames go through an `AVSampleBufferDisplayLayer` (I420 from browsers is repacked as NV12, rotation kept). Tapping the window reopens the call screen. Your camera keeps running there where iOS allows multitasking camera access (iOS 18+); otherwise it pauses when the camera is interrupted and the others see your picture.
- **FaceTime-style call screen**: one-to-one video (and shared screens in groups) fill the screen; the buttons hide after 5 s or on tap (never with VoiceOver, errors or while reconnecting); your own camera can be dragged to any corner.
- **Steadier, cheaper connections**: a network change (Wi-Fi ↔ mobile data) restarts ICE straight away, from either side (new `restart` signal; the website ignores it), and a dropped line shows "Reconnecting…". Signals are checked every 0.35 s while anyone is connecting and every 1.5 s once everyone is, and incoming-call checks only read calls from the last two minutes (most read nothing). iPhone's call timer starts when the other person really connects.
- **Video and sound**: 1280×720 at up to 30 fps with a bitrate ceiling (cameras keep moving smoothly on a weak line, screens stay sharp); the camera switches to the speaker; the speaker button follows AirPods and other routes; the proximity sensor turns the screen off on the earpiece.
- **Editor**: short timeline bars show their name beside them (never clipped), the top row drops the add buttons' names on narrow phones, stickers no longer redraw on every video frame (`StickerCanvas` is `Equatable` and each sticker is drawn into its own layer), vector stickers are made in the background, and big stickers and photos are shrunk off the main thread.
- **Slides**: pictures that aren't close to 9:16 (landscape drawings…) are shown whole over a blurred copy of themselves instead of being cropped, in the editor and in the posted reel (`SlideFraming`). Photo reels no longer move on by themselves.

## New profiles, steady loaders, light top bar (iOS app)

- **Profiles**: centred header (banner, the picture half over it with only a soft shadow, name, level, status, bio, badges and interests), one stats card, the buttons, then Posts / Art / Reels / Saved as four equal tabs with a sliding line (they always fit). Picture frames are gone: no frame picker, saving clears `avatar_frame`, and the shop no longer lists them. `FlowLayout` can centre its rows.
- **No more floating loaders**: endless animations started with `withAnimation(.repeatForever)` could carry other views' layout changes along forever (the reels loading line drifted up and down the screen). The shimmer, the reels skeleton and the buffering line are now drawn from the clock (`TimelineView`), the shimmer only on the placeholder's own shapes, and the two remaining pulses use scoped `.animation(_:value:)`.
- **Top bar**: iOS 26 still re-coloured the menu, search and bell buttons dark over dark pictures, so bar buttons now paint with colours fixed to the app's look (`Color.fixed(_:)`, `barScheme`). The menu button's picture is its round end (its border used to look like a ring around the photo).
- **Daily reward**: `RewardBurst` (glow, coins and sparkles, clock-driven) replaces the two thin rings, with a success haptic on Home.
- **Calls**: cameras fill the stage by default; double-tap shows the whole picture. `SectionSwitch` drops its icons when the names wouldn't fit.

## Server on Firebase (Netlify becomes the backup)

- **One Cloud Function, same code**: `functions/index.js` runs `netlify/functions/*.mjs` unchanged as `api` (Netlify-style requests in, Netlify-style answers out, the raw body kept so Stripe signatures still match). Settings come from one Secret Manager secret, `SUGERLY_ENV`, filled from GitHub secrets by `.github/workflows/firebase-server.yml`, which also puts the website on Firebase Hosting (`/api/**` and `/.netlify/functions/**` go to the function, so `paid.html` works as is).
- **Setup messages say where settings live** (`SETTINGS`: "Netlify", or "GitHub" on Firebase), and `LOGIN_SECRET` (optional) fingerprints login and backup codes so they survive a new Firebase key.
- **iOS app**: account, payments, call ringing and the call relay all go through `Backend.call`, which tries Firebase, then Netlify, then Netlify's preview copy. Only an answer with Sugerly's own JSON counts, so a server that isn't deployed (or can't be reached) simply hands over to the next.

## One set of hashtags for everything, and trending tags (iOS app + ranking job)

- **`tags` on every post, reel, drawing and song**: a list of lowercase tags without the `#` (letters, numbers and `_`, 2–40 long, at most 10, the same rule everywhere). The iOS app saves it when posting; `scripts/rank.mjs` fills it in for older things, things made on the website and edited captions. A tag's page finds everything with one indexed `array-contains` query per kind, a page at a time (indexes in `firestore.indexes.json`).
- **Trending tags** (`scripts/rank.mjs`, section 3): every run scores the tags of the last three days (how loved each thing is, halving every day, and how many different people use the tag) and writes the top 40 to `SiteConfig/trending_tags` (`{ key: "trending_tags", tags: [{ tag, score, uses, people }], updated_date }`). Apps ignore it once it's two days old. The website's `SiteConfig { key: "global" }` lookups are unaffected.
- **For You**: the iOS app's on-device taste learns from #tags across reels, posts and drawings, and the reels feed pulls in a few reels for the tags you like most.

## Comments v2, GIFs, native Liquid Glass tab bar, smoother app (this update)

### New
- **Comments** (`src/components/gallery/CommentSection.jsx`): likes on comments, threaded replies ("View N replies", @name), a Creator badge, a quick emoji row and GIFs. Your new comment shows first, then the most liked. Replying notifies the person you replied to.
- **GIFs** (`src/lib/gifs.js`, `src/components/common/GifPicker.jsx`): a Discord-style GIPHY picker in comments, DMs and server channels. An admin adds a free GIPHY key in Admin → Site → GIFs; without one, people can paste any GIF link.
- **Comments off**: creators can switch comments off when posting a reel or from the reel's ⋯ menu (enforced in the database rules too).
- **Native iOS tab bar** (`ios/App/App/NativeTabBar.swift`, `src/lib/nativeTabBar.js`): in the iPhone/iPad app the tab bar is a real UIKit view over the web view, made of Liquid Glass (`UIGlassEffect`) when built with Xcode 26 (the IPA workflow picks Xcode 26 when the runner has it), with a blur on older iOS. It hides itself while sheets, viewers, the camera or the keyboard are up.
- **Navigation by importance**: the sidebar has big app-icon tiles for Home, Community, Reels and Messages, medium rows for exploring, and a foldable "More"; the phone/tablet menu leads with big icons.
- **App layout on iPad**: touch tablets use the phone-style app layout (floating tab bar, menu behind the avatar) instead of the desktop sidebar (`desk:` screen in `tailwind.config.js`).
- **AI**: now uses `gemini-3.8-flash` (with fallbacks) and explains App Check if Firebase blocks AI Logic; optional web App Check with `VITE_RECAPTCHA_ENTERPRISE_KEY`.

### Faster
- Live blur only on the top bar, tab bar and sheets; other glass is drawn without blur on phones and tablets, and not at all over playing video.
- The logo decodes right away and keeps its space, so it no longer blinks out.

## Video cuts, text you can rotate and scale, AI captions, smoother Reels

### New
- **Film in clips** (`src/components/reels/ReelCamera.jsx`): tap the shutter to record and tap again to pause, or hold it and let go. A bar across the top and the ring around the shutter show each clip; delete the last clip, record more, then tap ✓. A 3 s / 10 s timer with a countdown. Closing with clips asks before discarding them.
- **Cuts** (`src/lib/clips.js`, `src/components/reels/ClipTimeline.jsx`): a filmstrip of clips in the editor. Split at the playhead, delete, duplicate, move earlier / later, and drag a clip's edges to trim it. Nothing is re-encoded: the reel stores `edits.clips` (`[{ id, start, end }]` in seconds of the original file) and the player jumps from clip to clip. Older reels with only `trim_start` / `trim_end` still play, and new reels keep those fields too.
- **Text stickers** (`src/components/reels/Sticker.jsx`): drag to move (snaps to the centre), pinch to resize, twist to rotate (snaps to 0° / 90°), or use the corner handle with one finger; drag onto the bin to delete. Five fonts (Classic, Bubbly, Cute, Serif, Mono), five styles (Plain, Label, Outline, Neon, Shadow), eight animations (Pop, Fade, Rise, Type, Bounce, Wiggle, Pulse) and, on videos, when the text shows and hides. Text on photo reels now stays live (so it animates) instead of being drawn into the picture.
- **Undo / redo** for every edit in the editor (a whole gesture is one step).
- **Reels feed**: hold to play at 2x, drag the progress bar to skip, a spinner while a video buffers, animated like / save buttons and a spinning music disc.

- **✨ Write with AI** (`src/lib/ai.js`, `src/components/ai/AICaptionHelper.jsx`): when you post a reel or in Community, AI looks at your picture (or the reel's cover frame) and anything you've typed and offers three captions with hashtags (and titles for posts). Powered by Gemini through Firebase AI Logic, so there's no server to run; the SDK only downloads the first time someone uses it. Admins switch it on once in the Firebase console and can test it in Admin → Site → AI features.
- **Rules publish themselves**: `.github/workflows/firebase-rules.yml` publishes `firestore.rules`, `storage.rules` and the Firestore indexes to Firebase whenever they change, once the `FIREBASE_SERVICE_ACCOUNT` secret is added to the GitHub repo (see the top of that file).

### Faster
- Reels only re-render when their own data changes, the feed re-ranks when the phone is idle instead of mid-swipe, and ranking stops early once the next reels are settled.

### Fixed
- The reel you just posted now always opens first (it could land second if it arrived after the feed was ranked).
- "Missing or insufficient permissions" when posting a reel or an update: it happens when the Firebase project still has older security rules. Admins now see a red banner ("Fix it") and a card in Admin → Site with the rules to copy, links to the Firebase console and a "Check again" button. Permission errors everywhere now say what to do instead of the raw Firebase message.


## Reels, the reel studio, a better post view and app updates

### New
- **Reels** (`/Reels`, in the tab bar): a full-screen, snap-scrolling feed of short videos and photos. Swipe up for the next one, tap for sound or to pause, double-tap to like, and use the side buttons to follow, comment, save, share or say "Not interested". Every reel says why it's in your feed.
- **A smart For you algorithm** (`src/lib/reelRank.js`): learns from watch time, full watches and re-watches, quick swipes away, likes, saves, comments, shares and "Not interested". It builds a creator and hashtag taste from those signals, scores reels on taste, smoothed like rate, popularity and freshness, stops the same creator or hashtag from repeating back to back, and gives about 1 in 6 slots to creators you haven't met. It keeps learning while you scroll: the reels below the next one are re-ranked after every reel.
- **Reel studio**: film in the app (front / back camera, flash — the real torch on the back camera and a bright screen flash for selfies — live filters, photo or video mode, 60 s max) or pick from your library, then edit: trim with a filmstrip, 12 filters, text you drag anywhere, speed (0.5x–2x), original sound on/off, music from Sugerly tracks and a cover frame. Video edits are saved with the reel and applied when it plays; photos have them drawn in.
- **Photo filters** in the Community post composer (drawn into the picture before it's uploaded).
- **Post view remade**: swipe (or ←/→) between posts in the feed you opened it from, double-tap to like, tap for full screen, follow the artist, Like / Comment / Share / Save tiles, tappable hashtags, "More from" the artist and "More like this".
- **What's new**: release notes in the app (`/Updates`, also in the menu), a one-time popup after an update, an unread badge, and admins can post their own updates. The web app also shows "A new version is ready — Update" when one has downloaded.

### Changed
- Phones: the tab bar is now Home · Community · ＋ · Reels · Chat; everything else is in the menu behind your avatar (top right). The tab bar turns dark over Reels.
- Videos up to 60 MB can be uploaded (pictures and audio stay at 20 MB).

### For your Firebase project
- Deploy the rules and indexes again: `npx firebase-tools deploy --only firestore:rules,firestore:indexes,storage` (new `Reel` and `AppUpdate` collections and the video size limit).


## Fonts, sounds & haptics, better artwork viewer

### New
- **Brand fonts**: Bubbly for titles and headings (with Cute Here filling in digits and punctuation Bubbly doesn't have) and Cute Here for small labels. Plus Jakarta Sans is now bundled too, so no fonts load from Google: the app draws its first screen immediately and works offline.
- **Sounds & haptics**: a matching tap on iPhone/iPad and a tiny sound for likes, saves, sending, success/error messages, new notifications and messages, tab switches and toggles. Sounds follow the iPhone's silent switch; both can be turned off in Settings → Sounds & haptics.
- **Artwork viewer, reorganised for phones and tablets**: a big image you can swipe left/right between pieces and tap for full screen (with a "3 / 12" counter), then title, artist, one row of Like / Save / Share / Ping buttons, the description, and a small separate row for admin tools.

### Fixed
- Top Artists: the crown no longer sits on the #1 ring, and the gold/silver/bronze rings are real circles that stay round on every screen.
- Viewers (artwork, post, commission, group info) no longer open scrolled down to the comment box or pop up the keyboard.


## Sugerly logo, smoother app, admin owner

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


## Server roles & permissions, smoother animations, .ipa builds

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

## iPhone & iPad app, safety tools and polish

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

## Calls, social feed and recommendations

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

## Redesign + everything working

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
