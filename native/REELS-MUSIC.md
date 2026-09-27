# Native Reels and Music handoff

Based on Claude's native phase-one commit `5b71876d`. This branch preserves its authentication, Community, Chat, and Profile implementations.

## Added

- Website-inspired rose colors, branded headings and logo shine, card borders, floating navigation, and a branded launch/loading screen.
- Native vertical Reels paging and horizontal, manually swipeable photo posts. Only the selected reel plays; players are released when leaving it or backgrounding the app.
- Video or multi-photo publishing using the same Firestore/Storage schema as the website. Choose a soundtrack from chart previews or uploaded community tracks.
- Likes, reports, and paginated reel comments with replies, likes, and deletion permissions inherited from the existing comment UI and server rules.
- Music charts/search and community tracks, incremental loading, and a persistent mini-player. Deezer music is a 30-second preview, not a licensed full-song catalog. Reel playback refreshes Deezer preview URLs.
- Stable Firestore cursors ordered by creation date and document ID. Reels/Music fetch at most 31 documents per page, without a collection-scan fallback. Comments use the existing ascending post_id/created_date index.
- Native caption/bio link detection and server rule changes for those fields. The production-rule workflow excludes this review branch: rules still require deployment through the normal production branch.
- Website photo posts stop advancing automatically and no longer apply the single-photo zoom class.

## Validation and remaining work

The macOS workflow builds and packages an unsigned iPhone/iPad IPA for iOS 17+. Signing is still required for installation. The web production build passes.

This is not full website feature parity. Native calls/server channels, the complete advanced reel editor, offline uploads, saved-reel browsing, background audio controls, and full music-upload management remain future work. Existing web edits such as stickers and complex multi-cut timelines are not yet fully rendered by the native player. Real-device frame-rate and keyboard/GIF testing remains necessary; compilation does not prove performance. Cursor paging reduces reads but does not establish billion-record scalability; existing array-based likes and legacy Community/Chat queries also need further backend work at that scale.
