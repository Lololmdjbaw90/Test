# Mimi Locks on iPhone and iPad

There are two ways to get Mimi Locks onto an iPhone or iPad. Both use the same
code as the website, so every feature (feed, music, servers, DMs, voice and
video calls) works in all of them.

| | Installable web app | Native iOS app |
|---|---|---|
| Needs a Mac? | No | Yes (Xcode) |
| Cost | Free | Free on your own devices; $99/year Apple Developer Program for TestFlight / App Store |
| How people get it | Safari → Share → Add to Home Screen | App Store, TestFlight, or installed from Xcode |
| Full screen, home-screen icon, works offline | ✓ | ✓ |
| Keeps playing music / calls with the screen locked | Limited by iOS | ✓ (background audio) |
| Haptics, native status bar & keyboard handling | – | ✓ |

---

## 1. Installable web app (no Mac needed)

1. Put the site online over HTTPS (see `DEPLOYMENT.md`, or drag the `dist`
   folder onto https://app.netlify.com/drop).
2. On the iPhone or iPad, open the site in **Safari**.
3. Tap **Share** → **Add to Home Screen** → **Add**.

Mimi Locks now opens from its own icon, full screen, without Safari's bars.
The site also shows these steps as a small tip on phones and tablets, and
under **Settings → Get the app**. On Android and in desktop Chrome / Edge
there's a real **Install** button instead.

What makes this work: `public/manifest.json`, the icons in `public/icons/`,
and a service worker (`src/pwa/sw.template.js`, built to `/sw.js`) that
precaches the app so it starts instantly and even offline.

---

## 2. Native iOS app (Capacitor)

The `ios/` folder is a ready Xcode project (iPhone + iPad, iOS 15+) that wraps
the built site with [Capacitor](https://capacitorjs.com). It's already set up
with:

- App name **Mimi Locks**, bundle id `com.mimilocks.app` (change it in
  `capacitor.config.json` **and** in Xcode → Signing & Capabilities before
  publishing — it must be unique to you).
- App icon and light/dark launch screens.
- Permission texts for the camera and microphone (calls) and photos (uploads).
- Background audio, so music and calls keep going when the screen locks.
- Status bar that follows the light/dark theme, haptic taps on likes, sends
  and calls, and the tab bar hiding while the keyboard is open.
- All orientations on iPad (Split View / Slide Over work).

### What you need

- A Mac with the latest **Xcode** from the Mac App Store (Xcode 15 at minimum).
- **Node.js 22 or newer** (Capacitor 8 requires it).
- An Apple ID. A free one lets you run the app on your own iPhone/iPad; the
  paid Apple Developer Program is needed for TestFlight and the App Store.

### Run it on your iPhone or iPad

```bash
npm install
npm run ios          # builds the site, copies it into ios/, opens Xcode
```

In Xcode:

1. Select the **App** target → **Signing & Capabilities** → choose your
   **Team** (your Apple ID). If Xcode complains about the bundle id, change it
   to something unique like `com.yourname.mimilocks`.
2. Plug in your iPhone or iPad (or pick a simulator) at the top of the window.
3. Press **▶ Run**.

The first time on a real device, iOS may ask you to trust the developer:
**Settings → General → VPN & Device Management**.

### After changing the website code

```bash
npm run ios:sync     # rebuild the site and copy it into the iOS project
```

Then press Run in Xcode again.

### Publishing to TestFlight / the App Store

1. Join the Apple Developer Program and create the app in
   [App Store Connect](https://appstoreconnect.apple.com) with the same bundle id.
2. In Xcode: set the version (General → Identity), choose **Any iOS Device**,
   then **Product → Archive** → **Distribute App** → **App Store Connect**.
3. Add screenshots (iPhone and iPad), a description and a privacy policy URL
   in App Store Connect, then submit for review — or share it with testers
   through TestFlight first.

Apple checks that social apps can handle bad behaviour, and that people
can delete their account. Mimi Locks covers these — mention them in your
review notes:

- **Report** any post (⋯ menu) or person (⋯ on their profile). Reports go to
  **Admin → Reports**, where admins remove the content or dismiss the report.
- **Block** someone from a post or their profile: their posts, comments,
  messages, notifications and calls disappear for you. Manage blocks in
  **Settings → Account & data**.
- Posts, comments and messages are **automatically moderated** for abusive text.
- **Delete account** in **Settings → Account & data** removes the profile,
  posts, tracks, comments, sent messages and owned servers.

### Firebase notes for the app

- Sign-in uses email and password, which works inside the app with no extra
  setup (the app starts Firebase Auth in a mode that suits iOS web views).
- Share and invite links point at your public site. Set `VITE_PUBLIC_URL` in
  `.env` to your site's address; otherwise they use
  `https://<your-project-id>.web.app`.
- Deploy the Firestore rules and indexes once (`firebase deploy --only
  firestore:rules,firestore:indexes,storage`) — calls and play counts need them.
