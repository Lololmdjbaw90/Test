# App stability and iOS build

This branch continues `claude/roblox-chat-gui-modules-2o4brz` at `ccbda3a0`.
The four uncommitted changes described in the handoff were not in GitHub;
the slideshow and chart music picker were implemented on the saved editor.
The `tool` state is declared before the music query uses it.

## Delivered

- Select up to 20 photos; preview, upload and play them in order, three seconds each. Single photos retain their seven-second duration.
- Choose chart previews or community tracks in the reel editor. Chart previews are 30 seconds, not full songs.
- Catalog pagination uses provider offsets; search cancels stale requests and has a timeout/retry path.
- Separate playback progress context keeps audio clock ticks out of the music lists.
- Decode the next accent wordmark before swapping it; preserve the logo's layout. A matching startup screen hands off to React.
- Remove the transformed page entrance that changes fixed overlays' containing block.
- Serialize incoming SDP/ICE work per peer; reduce speaking-analysis sampling.
- Join/leave membership uses atomic Firestore array operations instead of overwriting a stale member list.
- Native tab bar hide completions are versioned, so an interrupted hide cannot conceal a reopened bar. Remove duplicate storyboard window creation and enable variable frame duration on supported iPhones.
- Build numbers advance with GitHub runs; IPA packaging verifies that the bundled web entrypoint and Capacitor config exist.

## Validation

`npm ci`, `npm run build`, and `npx cap sync ios` pass on Windows.
`scripts/app-regression.mjs` runs against `npm run dev:demo` using Playwright
and Edge (override `BROWSER_CHANNEL` if necessary). It covers three-photo
reel posting/playback with music, music scroll pagination, server creation,
timestamp-tie cursor paging, two-peer WebRTC connection/leave and runtime errors.
Catalog responses are deterministic fixtures; the test does not establish
external catalog uptime, music licensing, Firebase production access, TURN
availability, or device FPS.

The iOS workflow produces an **unsigned** IPA with bundled assets; signing is
still required to install it. TestFlight/App Store distribution needs Apple
certificates/profiles and an export workflow. Capacitor remains the native
container, with native tab bar, permissions and plugins; this is not a SwiftUI rewrite.

## Scale boundary

Reels, community posts and community discovery now fetch 30-row cursor pages.
Only their first page is realtime. Firestore paging uses an ordered field plus
document ID to handle timestamp ties; older pages never use offset scans or an
unbounded fallback. Add the new community indexes before using filtered paging
in production. Firebase deployment runs only on the existing app branch or main,
not on this review branch.

This is **not a billion-record capacity claim**. Remaining backend work includes:

1. Normalize community membership, follows and likes into individual documents;
   existing arrays and permission maps cannot grow without limit.
2. Produce bounded recommendation candidates on a backend, then rank that set;
   client ranking currently operates on loaded pages and is not global search.
3. Replace global user/comment lookups and client-computed totals with indexed
   queries, denormalized author summaries and server-maintained counters.
4. Put transcoded video variants and images behind object storage/CDN; introduce
   an SFU and authenticated TURN service for larger or restricted-network calls.
5. Load-test database indexes, write contention, cache behavior, queue backlogs,
   media egress and p95/p99 latency against explicit traffic targets before
   promising any capacity. Test scrolling and memory on real iPhone/iPad devices.

Older pages are not realtime subscriptions; changes to those records may require
a refresh. Full search across all records requires a backend search service.
