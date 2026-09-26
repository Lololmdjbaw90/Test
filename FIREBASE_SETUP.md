# Mimi Locks Firebase setup

This project is now wired to your Firebase project:

- Project ID: `umikoworks-86333`
- Auth domain: `umikoworks-86333.firebaseapp.com`
- Storage bucket: `umikoworks-86333.firebasestorage.app`

The app uses Firebase Authentication, Cloud Firestore, and Firebase Storage. So yes, actual accounts and saved data, not the old fake-browser-memory theater.

## 1. Install dependencies

```bash
npm install
npm install firebase
```

`firebase` is already listed in `package.json`, but running the command again is harmless.

## 2. Install Firebase CLI

```bash
npm install -g firebase-tools
firebase login
```

## 3. You usually do not need `firebase init`

This zip already includes:

- `firebase.json`
- `.firebaserc`
- `firestore.rules`
- `storage.rules`
- `.env`
- `.env.example`

If Firebase asks for a project, choose:

```text
umikoworks-86333
```

If you still run `firebase init`, choose:

```text
Hosting
Firestore
Storage
```

Use these answers:

```text
Public directory: dist
Configure as single-page app: Yes
Overwrite index.html: No
Firestore rules file: firestore.rules
Storage rules file: storage.rules
```

## 4. Enable Firebase products

In Firebase Console, enable these:

1. Authentication → Sign-in method → Email/Password
2. Firestore Database → Create database
3. Storage → Get started

Without these, the app cannot create accounts, save posts, save messages, upload artwork, or do anything useful. Shocking, I know.

## 5. Deploy rules and indexes first

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

These rules block normal users from editing or deleting other users’ artwork, comments, messages, posts, site settings, and admin-only data.

The indexes in `firestore.indexes.json` make sorted chat/feed queries fast. If they aren't deployed yet the app still works (it sorts on the client and logs a hint in the console), but deploy them for anything beyond a small community.

## 6. Run locally

```bash
npm run dev
```

Open the local Vite URL.

## 7. Create your account

Open the website, choose **Sign up** on the login page and finish the short onboarding.

Then go to Firebase Console → Firestore Database → `User` collection → your user document.

Change:

```text
role: "user"
```

to:

```text
role: "admin"
```

Log out and log back in. The Admin Panel will unlock. From then on you can promote other members from **Admin Panel → Users → Make admin** — no console needed.

## 8. Voice channels and calls

Voice channels and DM/group calls use WebRTC with signalling through Firestore (`VoicePresence` and `VoiceSignal` collections; calls also use a `Call` document for ringing and status). All are covered by the rules and indexes above, so redeploy them after updating. Public STUN servers are used by default. If some members can't hear each other (strict corporate/mobile networks), add a TURN server in `.env`:

```text
VITE_TURN_URL=turn:turn.example.com:3478
VITE_TURN_USERNAME=...
VITE_TURN_CREDENTIAL=...
```

## 9. Try everything locally with emulators

```bash
npm run emulators      # needs Java installed
npm run dev:emulator
```

This uses a `demo-mimilocks` project against local emulators that enforce the same rules, so you can test sign-ups, chat and uploads without touching real data.

## 10. Deploy the website

```bash
npm run build
firebase deploy
```

Your Firebase Hosting site will then be live.

## 11. What is saved for real

With Firebase enabled, these are stored in Firestore:

- users and profiles
- artworks
- artwork comments
- community feed posts
- likes
- follows/friendships
- servers/communities
- server channels
- server messages
- direct messages
- group messages
- notifications
- site settings
- admin moderation data

Uploaded files are stored in Firebase Storage.
