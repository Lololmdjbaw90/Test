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

## 5. Deploy rules first

```bash
firebase deploy --only firestore:rules,storage
```

These rules block normal users from editing or deleting other users’ artwork, comments, messages, posts, site settings, and admin-only data.

## 6. Run locally

```bash
npm run dev
```

Open the local Vite URL.

## 7. Create your account

Open the website and click **Create one** on the login page.

Then go to Firebase Console → Firestore Database → `User` collection → your user document.

Change:

```text
role: "user"
```

to:

```text
role: "admin"
```

Log out and log back in. The Admin Panel will unlock.

## 8. Deploy the website

```bash
npm run build
firebase deploy
```

Your Firebase Hosting site will then be live.

## 9. What is saved for real

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
