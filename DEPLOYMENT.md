# Deploy Sugerly as a real website

## Fast Firebase Hosting deploy

Run these commands from the project folder:

```bash
npm install
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules,firestore:indexes,storage
npm run build
firebase deploy
```

The project is already linked to Firebase project:

```text
umikoworks-86333
```

So you do not need to paste random SDK code into source files. The config is already in `.env`. We are not feeding JavaScript into the terminal like soup into a printer.

## Required Firebase Console setup

Enable:

```text
Authentication → Email/Password
Firestore Database
Storage
```

## Admin setup

1. Create an account inside the app.
2. Open Firebase Console.
3. Go to Firestore Database → `User`.
4. Open your user document.
5. Set `role` to `admin`.
6. Log out and back in.
7. Promote other admins from **Admin Panel → Users** inside the app.

## Vercel / Netlify

Both configs are included (`vercel.json`, `netlify.toml`) with SPA rewrites. They build with `npm run build` and read the Firebase config from `.env`. Remember to deploy Firestore rules + indexes with the Firebase CLI as shown above.

## Login server (email codes, quick login, backup codes)

`netlify/functions/account.mjs` gives the app more ways to log in: a code by
email (and resetting a password with a code), quick login with a QR code,
backup codes, and lets admins delete an account. It uses the same Firebase
key as the payment server (`FIREBASE_SERVICE_ACCOUNT`, or
`FIREBASE_PRIVATE_KEY` + `FIREBASE_CLIENT_EMAIL`).

Emails need one email service. In Netlify → Site configuration → Environment
variables add either:

- `BREVO_API_KEY` (Brevo → SMTP & API → API keys) and `MAIL_FROM` (the sender
  address you verified in Brevo → Senders). Free plan: 300 emails a day, no
  domain needed.
- or `RESEND_API_KEY` and `MAIL_FROM` (an address on a domain verified in
  Resend).

Without them quick login, backup codes and admin delete still work; "Forgot
password?" falls back to Firebase's reset link email.

## Production build

```bash
npm run build
```

This creates the `dist` folder.

## Deploy only hosting

```bash
firebase deploy --only hosting
```

## Deploy everything

```bash
firebase deploy
```
