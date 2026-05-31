# Changes in this Firebase-connected version

- Added your Firebase web config to `.env` and `.env.example`.
- Added `.firebaserc` linked to `umikoworks-86333`.
- Added real Firebase Authentication login and create-account flow.
- Added Firestore-backed users, posts, artworks, comments, likes, follows, servers, channels, messages, direct messages, group chats, notifications, and site settings.
- Added real direct-message chat instead of the placeholder shell.
- Added `DirectMessage` to local and Firebase backend entities.
- Added Firestore security rules so users cannot edit or delete other users’ content.
- Added Storage rules for authenticated user uploads.
- Updated deployment instructions with clean Firebase commands.
