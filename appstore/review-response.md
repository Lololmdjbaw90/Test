# Sugerly — requested App Review information

Draft based on the source, 1 October 2026. Complete the bracketed fields and
physical-device checks before sending. An uploaded build or passing simulator
tests does not establish that the submitted build is ready for review.

Current blocker: the live call-ring and turn-credentials endpoints returned
404 on 1 October 2026. Deploy and verify the call backend before demonstrating
or claiming working background calls. See [background-calls.md](background-calls.md).

Paste the completed numbered response both into the App Review conversation
and into App Review Information → Notes. Put the demo password in the private
Sign-in Information fields, never in this repository.

1. Physical-device demonstration

   Recording: [ATTACH THE REAL RECORDING, OR PROVIDE AN ACCESSIBLE VIDEO LINK].
   Device: iPad Pro [MODEL], iPadOS [EXACT VERSION AND BUILD].
   App: Sugerly [VERSION] ([BUILD NUMBER]).
   [ONLY AFTER TESTING: We tested this exact build on the devices listed in
   the accompanying QA results. The recording starts with launching Sugerly
   and demonstrates registration, login, its main social features, reporting,
   blocking, and account deletion.]

2. Purpose and audience

   Sugerly is a social app for artists and people who enjoy art. It brings
   Community conversations, a Fanart gallery, reels, music discovery, profiles,
   direct messages, and community servers together. Users can share work in
   progress, receive comments, discover creators, and talk with friends. The
   Terms require users to be at least 13, or the higher minimum age applicable
   in their country. It is a consumer social app, not an employee-only app.

3. Access and main features

   Sign in with the demo credentials supplied in Sign-in Information:
   [DEMO ACCOUNT EMAIL]. No special sample files are required to browse.
   For the editor demonstration we use [OWNED SAMPLE PHOTO/VIDEO].
   If more than one account is required, supply [SECOND DEMO ACCOUNT] and
   [ARTIST DEMO ACCOUNT, IF COMMISSIONS ARE ENABLED]. Do not require reviewers
   to create their own accounts, buy an Apple Music subscription, or make a
   real card payment to see the basic features.

   - Home shows current activity, reels, artwork, music and daily rewards.
   - Community is the conversation feed; Fanart is the artwork gallery. Open
     an item to like, save, or comment. Use its overflow menu to report it.
   - The create menu opens post/artwork/reel creation. In the reel editor,
     import owned photos/video, edit text and its timeline, preview, then post.
   - Open another user's profile to follow, message, report, or block them.
     A two-account demo can show messaging and a call between mutual friends.
   - Servers provide community channels and voice rooms. Include a populated
     review server [SERVER NAME AND JOIN INSTRUCTIONS].
   - Profile → Settings includes appearance, privacy, help and account controls.
     Account → Delete account requests the current password. Demonstrate this
     with a separate disposable account, leaving the review account available.
   - MimiPlus is unlocked for a fixed term with earned MimiCoins. The current
     app does not sell MimiCoins and MimiPlus does not renew automatically.
   - Commissions support artist requests, quotes, orders and delivery. Card
     checkout uses Stripe on the US storefront; other storefronts hide that
     checkout. [CONFIRM LIVE PAYMENT CONFIGURATION AND PROVIDE A SAFE REVIEW
     FLOW/SEEDED ORDER. Do not describe a real-money transaction as a sandbox.]

4. External services and platforms

   - Google Firebase Authentication: email/password accounts and sessions.
   - Cloud Firestore and Firebase Storage: profiles, posts, messages, call
     signalling, metadata and uploaded media.
   - Netlify: public support/legal pages and server functions for calls,
     commissions and relay credentials.
   - Apple Push Notification service / PushKit and CallKit: incoming VoIP
     calls and system call controls. ReplayKit broadcasts screen frames;
     WebRTC sends audio/video to other call participants.
   - Google and Cloudflare STUN; Cloudflare TURN or Metered TURN when the
     corresponding backend credentials are configured. [CONFIRM THE ACTIVE
     RELAY PROVIDER; unconfigured alternatives are not active services.]
   - Deezer: music discovery metadata, artwork and short preview playback.
   - Apple Music / MusicKit: optional subscriber-authorized full-song playback.
     Sugerly does not sell an Apple Music subscription.
   - GIPHY: GIF/sticker search and media, subject to its API terms.
   - Stripe: commission card checkout and associated payment processing.
     Artist payout details can include PayPal/bank information; the presence
     of these fields does not establish an automatic PayPal API integration.
   - Google Gemini via Firebase AI Logic: moderation second opinions and
     optional caption assistance where enabled. [CONFIRM ENABLED FEATURES AND
     ENSURE PRIVACY DISCLOSURES/CONSENT MATCH THE ACTUAL SUBMITTED BUILD.]

5. Regional behavior

   The core social navigation is the same across supported storefronts.
   Commission card checkout is limited to the United States storefront.
   Apple Music access depends on authorization, subscription and local
   catalog availability; Deezer previews and GIPHY results depend on their
   providers' availability. The listing recommends excluding mainland China
   because this implementation uses CallKit. [CONFIRM THE ACTUAL COUNTRY
   SELECTION IN APP STORE CONNECT; it cannot be determined from source.]
   We therefore do not claim identical content and payments in every region.

6. Protected material and regulated services

   Sugerly is a social/art app; it does not implement medical, financial
   trading, gambling or other regulated professional services.
   Users are required by the Terms to own or have permission for uploads and
   can report content through the app. These Terms are not proof that every
   uploaded artwork or song is licensed. MusicKit, Deezer and GIPHY usage must
   meet the providers' terms, including any required attribution and production
   approvals. We cannot claim separate music synchronization/distribution
   licenses based on API access alone.

   Documentation: [ATTACH APPLICABLE FONT/MEDIA LICENSES AND PROVIDER
   AUTHORIZATIONS AFTER RESOLVING THE ITEMS IN third-party-materials.md].
   Do not state that all rights are secured until those items are resolved.

## Recording and physical QA checklist

Use the exact build selected for review. Prefer the latest public iPadOS
release for the final recording; record the exact beta version if beta is
the only device currently available, and disclose that instead of calling it
the latest public release. An iPad recording does not replace iPhone QA for
an app that supports iPhone. Test on a physical iPhone as well.

1. In Settings → General → About, note the device/OS version. In TestFlight,
   note Sugerly's version/build. Enable Screen Recording in Control Center.
2. Begin recording on the Home Screen, then launch Sugerly. Use original
   sample art/media and avoid exposing personal messages or credentials.
3. Register a disposable account, accept the terms, and complete onboarding.
   Log out and log back in so both flows are shown.
4. Scroll Home, open Community and Fanart, open a post, like/save/comment,
   post owned artwork, and demonstrate Report and Block on a demo profile.
5. Create a short reel, add and time text, preview, and publish. Show Music
   browsing and any optional features actually enabled for that account.
6. Show a populated server and two-account chat. Test calls on Wi-Fi and
   cellular/different networks, then with the receiving app backgrounded and
   the device locked. Test answer, decline, caller cancellation, mute and end.
   Open the receiving app once after installation to register its push token.
7. During a connected call, start screen broadcast using the system picker,
   switch to another app, verify the other device receives the screen, then
   stop sharing and confirm frames stop. Test rotation and both call hangups.
8. Demonstrate earned-coin MimiPlus and commission screens if enabled. Include
   any accessible paid-content flow; do not make unnecessary real purchases.
9. Delete the disposable account from Profile → Settings → Account. Verify
   that it cannot log back in and that deletion actually completes.
10. Verify Home/Settings scrolling, keyboard navigation, reel controls,
    portrait/landscape iPad layouts, media permissions and offline recovery.
    Record failures and fix them before marking a device as passed.

QA results to complete: device/model; exact OS; app build; test date; each
flow tested; pass/fail; recording link; known issues. Do not send simulator
screenshots as a substitute for Apple's requested physical-device recording.

Reference: [Reply to App Review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages/)
and [App Review guidance](https://developer.apple.com/app-store/review/).
