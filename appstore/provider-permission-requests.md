# Provider permission requests — prepared 22 October 2026

These are requests for clarification/approval, not licenses. The Deezer inquiry was sent on 22 October 2026 after owner authorization; the form confirmed successful delivery. Reply address: Sugerly’s published support inbox. No approval or license has been received. The GIPHY request has not been sent. Do not sign an agreement, accept a price, or claim approval based on this document.

## GIPHY

Destination: https://developers.giphy.com/dashboard/ (your own account/app), or the developer support contact listed at https://developers.giphy.com/docs/api/ .

Subject: Sugerly iOS/web integration — authorization, attribution and media handling review

Hello GIPHY developer team,

I develop Sugerly, an artist-focused social app for iPhone/iPad with a companion website: https://sugerly.netlify.app . App Store app ID: 6817305250; bundle ID: com.mimilocks.app.

We need to confirm the permitted integration and account/API-key requirements before public distribution. Our implementation searches GIFs/stickers for chats, comments, community channels and creative tools. Some tools also support profile media and placing stickers in images/videos. The current implementation can retain media in image caches and persist media URLs with user content. It currently has textual Powered by GIPHY attribution but needs the approved graphic attribution and per-content creator/source handling reviewed. We are not claiming these implementation choices have been approved.

Please confirm:
- Which separate keys are required for iOS, web and each integration section; whether our app needs production approval or a commercial agreement for its intended usage.
- Required branding, source/creator attribution and reporting/removal behavior for sent content.
- Permitted caching, persistent media links, profile images, transformations and image/video exports. If any need a separate agreement, please identify the permitted scope and approval process.
- Whether there are territorial or age-rating restrictions relevant to our rollout.

Please provide written confirmation of the authorized scope and any applicable agreement/fees. We will update the integration to your requirements before claiming compliance.

Thank you.

## Deezer

Destination: https://www.deezer-techservices.com/contact/ . Request referral to the developer/business licensing team if this channel does not handle API approvals.

Subject: Sugerly — commercial API preview usage and reel audio rights clarification

Hello Deezer team,

I develop Sugerly, an artist-focused social app for iOS/iPadOS and web: https://sugerly.netlify.app . App Store ID: 6817305250; bundle ID: com.mimilocks.app.

We request written confirmation of the permitted use of Deezer catalog metadata, cover artwork, charts/search and 30-second previews in this public app. Sugerly includes commission-related business features, so we are not assuming that a personal/non-commercial exception applies.

Our current integration also lets a user select a catalog preview as audio accompanying a short reel/slideshow, with preview looping. Please confirm whether this synchronization use is permitted at all, whether downloading/exporting a composed video changes the authorization required, and which recording/composition rights must be licensed separately. We do not assume that public API access or a Deezer subscription grants these rights.

Please identify the appropriate approval process, attribution/link-back, playback/caching limitations, territorial scope and any applicable contract/fees. If you cannot grant synchronization rights, please state the scope limited to discovery/preview playback and refer us to the relevant licensing route.

We will restrict unsupported uses rather than claim unconfirmed rights. Please provide documentation suitable for an App Review rights inquiry.

Thank you.

## What must be retained after a provider responds

Keep the agreement/approval, legal entity/account and app identifiers, approved keys, platforms/placements, territories, expiry, fees and permitted caching/export/synchronization scope in private business records. Do not commit keys, contracts containing personal details, or account passwords to GitHub. A working API response alone is not approval evidence.

## Findings verified in source

- The owner signed into GIPHY on 22 October 2026. Its existing app, named Sugarly (app ID 664372), contains the same key as the native fallback. Ownership is now confirmed. The dashboard identifies it as a free beta iOS SDK key, while this client uses direct REST API requests. REST API setup, attribution/caching and placement requirements remain under review.
- GifItem currently discards creator/source metadata, while the picker shows text-only branding.
- Native image/GIF infrastructure caches media; the provider documentation limits caching to approved integrations.
- Deezer chart previews are selectable for reels and expire/refresh by track ID. No synchronization license was found in the repository.
- GIPHY documentation supports creative integrations; editing is not automatically prohibited. The exact storage/export/attribution scope still needs confirmation. Do not claim every GIF requires a separately purchased license.

Sources: https://developers.giphy.com/docs/api/ ; https://support.giphy.com/hc/en-us/articles/360028134111-GIPHY-API-Terms-of-Service ; https://cdn-content.dzcdn.net/pdf/CGU-developers.pdf ; https://www.deezer-techservices.com/contact/ .
