# Background calls and screen sharing — deployment and device check

The app includes PushKit/CallKit for ringing outside Sugerly and a ReplayKit
broadcast upload extension for whole-screen sharing. Source compilation does
not verify APNs credentials, deployed server configuration or physical devices.
This session could not inspect the live Netlify environment.

Deployment probe on 1 October 2026: unauthenticated POST requests to both
`https://sugerly.netlify.app/.netlify/functions/call-ring` and
`https://sugerly.netlify.app/.netlify/functions/turn-credentials` returned 404.
The existing commission-checkout function returned 401, as expected without
credentials. Calls cannot use these missing endpoints until they are deployed;
changing only the IPA cannot fix this server-side failure.

## Server configuration

The deployed Netlify site must include `netlify/functions/call-ring.mjs` and
`netlify/lib/call-ring-policy.mjs`. It accepts an authenticated Firebase request
from the caller, checks the call and sends a VoIP push to eligible recipients.
It refuses calls older than 45 seconds and excludes answered/declined members.

The following variables must be present in Netlify's server environment:

| Variable | Value |
| --- | --- |
| `APNS_KEY` | Private `.p8` text from an Apple developer key authorized for APNs. Never put it in the app, repository, screenshots or chat. |
| `APNS_KEY_ID` | That APNs key's identifier. |
| `APPLE_TEAM_ID` | The Apple Developer team identifier for `com.mimilocks.app`. |

The App Store Connect upload API key is not automatically an APNs-authorized
key. The push topic is `com.mimilocks.app.voip`. Debug tokens use the sandbox;
TestFlight/App Store release tokens use production. Provisioning must preserve
the app's push entitlement and the bundle identifier. Set secrets through the
hosting provider's private settings, then redeploy the function if required.

For calls across different networks, configure a TURN provider as well. The
backend supports Cloudflare (`CLOUDFLARE_TURN_KEY_ID` and
`CLOUDFLARE_TURN_API_TOKEN`) or Metered (`METERED_TURN_APP` and
`METERED_TURN_API_KEY`); confirm names against `turn-credentials.mjs` before
entering them. STUN-only calls may fail on restrictive networks.

## Physical-device verification

1. Install the tested TestFlight build on two devices and sign in with two
   demo accounts. Follow each other. Open each app at least once so its VoIP
   token uploads. Allow microphone access before testing a locked-device call.
2. Start a call from account A. Put B's app in the background, then repeat with
   B locked. Confirm the system incoming-call screen appears, answer and speak
   both ways. Test decline and caller cancellation before answering.
3. Test Wi-Fi to cellular/different networks. Confirm mute, speaker/Bluetooth,
   camera changes and ending a call from system controls.
4. Start screen sharing from the call. Use the system Start Broadcast sheet,
   switch to another app, rotate the iPad, and confirm A sees B's live screen.
   Stop sharing, then hang up; both actions must stop further screen frames.
5. Sign out of B and confirm calls to that account no longer ring that device.
   Test token replacement after reinstalling. The current token schema stores
   one device per account; signing in on another device replaces its address.

The call screen's `ringNote` distinguishes a missing APNs setup, a recipient
without a token, an unreachable server and an APNs delivery error. Preserve
the exact error when diagnosing; do not expose device tokens in public logs.

Screen sharing requires the user to start a broadcast. It does not silently
capture other apps, and protected content may appear black. ReplayKit screen
frames are currently video only; the call microphone carries speech, not
system audio from other apps.

References: [Apple PushKit call delivery](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit)
and [ReplayKit](https://developer.apple.com/documentation/replaykit).
