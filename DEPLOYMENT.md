# Deploy Mimi Locks as a real website

## Fast Firebase Hosting deploy

Run these commands from the project folder:

```bash
npm install
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules,storage
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
