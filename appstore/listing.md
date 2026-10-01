# Sugerly — App Store listing (copy & paste)

Listing draft. Verify every claim against the submitted build. For Apple's
additional-information request, complete [review-response.md](review-response.md)
and the physical-device checks before resubmitting.

## App information

| Field | Value |
| --- | --- |
| Name | Sugerly |
| Subtitle (30) | Share art, reels & music |
| Bundle ID | com.mimilocks.app |
| SKU | sugerly-ios-1 |
| Primary language | English (U.S.) |
| Primary category | Social Networking |
| Secondary category | Graphics & Design |
| Content rights | Third-party content is present. Verify provider/media/font permissions in [third-party-materials.md](third-party-materials.md) before asserting that distribution rights are secured. |
| Price | Free |
| Availability | All countries **except China mainland** (voice channels use CallKit, which isn't allowed there) |

## Version page

**Promotional text (170)**

> A cozy place to post your art, film little reels, chat with friends and meet people who love making things as much as you do.

**Description**

> Sugerly is a little corner of the internet for people who make things.
>
> Post your drawings, paintings, crafts, cosplay or music and get real feedback from other artists. Film a quick reel or turn a few pictures into a slideshow, add a song and some text, and share it.
>
> Chat with friends one on one or in a group, send GIFs and voice notes, or hang out in community servers with text and voice channels.
>
> Artists can open a small shop and take commissions. Someone asks for a piece, you agree on a price, and you send the finished art right in the app.
>
> You can make the whole app your own colour (the logo changes too), level up as you post, and collect coins for fun extras on your profile.
>
> If someone isn't being nice, you can report or block them in a couple of taps and our team will take a look.

**Keywords (100)**

```
art,artist,drawing,painting,reels,sketch,creative,community,music,friends,chat,cosplay,anime,share
```

**Support URL:** `https://sugerly.netlify.app/Help` (shows sugerlysupport@gmail.com)
**Marketing URL:** leave empty
**Privacy Policy URL:** `https://sugerly.netlify.app/Legal/privacy`
**Copyright:** `2026 <your name>`
**Version:** 1.0

## Screenshots

In `appstore/screenshots/`:

- **iPhone 6.9" display** → the 5 `iphone-*.png` files (1320 × 2868)
- **iPad 13" display** → the 5 `ipad-*.png` files (2064 × 2752)

Drag them in in order (1 → 5). Tip: screenshots from your real app with
real art look even better — take them on your iPhone later and replace these.

## App Review information

- **Sign-in required:** Yes → user name and password of a test account
  you made in the app (step 7 of APP_STORE.md).
- **Contact:** your name and phone number (only Apple sees these).
- **Notes:**

> Sugerly is a social app for artists. Users can post art, reels and music, comment, and chat.
>
> Safety (Guideline 1.2): every post, reel, comment, message and profile has Report (⋯ menu) and profiles have Block. Reports go to our moderators (Admin → Reports) and are reviewed within 24 hours. New users must agree to the Terms and Community Guidelines, which have zero tolerance for objectionable content. Captions and messages are filtered for abusive words; links are blocked in captions and bios.
>
> Account deletion (Guideline 5.1.1(v)): Settings → Account → Delete account (asks for the password, then deletes the account and everything the user posted).
>
> Support: Settings → Help & legal → Contact us (in-app), plus the Support URL. Terms, Privacy Policy and Community Guidelines are under Settings → Help & legal and on the sign-up screen.
>
> Commissions: artists sell custom artwork to other users. On the United States storefront buyers pay by card through Stripe (Guideline 3.1.1(a)); on other storefronts the in-app Pay button is hidden. Sugerly sells no digital content of its own and coins can't be bought.
>
> Camera and microphone are only used when the user films a reel, takes a photo or joins a call. Song previews are 30-second previews from the Deezer API; Apple Music subscribers can play whole songs through MusicKit; GIFs come from GIPHY.

## Age rating (questionnaire answers)

Answer honestly for what your users can post; for Sugerly as built:

- Cartoon or fantasy violence: None
- Realistic violence: None
- Sexual content / nudity: None
- Profanity or crude humour: Infrequent/Mild
- Alcohol, tobacco, drugs: None
- Horror/fear themes: None
- Gambling / contests: None
- Unrestricted web access: No
- **User-generated content: Yes**
- **Messaging and chat: Yes**
- Age assurance / parental controls: No

This usually gives **13+**.

## App Privacy ("nutrition label")

Data used to track you: **No**.

Data linked to the user, purpose **App Functionality** only:

| Category | Type |
| --- | --- |
| Contact Info | Email Address, Name |
| User Content | Photos or Videos, Audio Data, Emails or Text Messages (chat messages), Other User Content (posts, comments) |
| Identifiers | User ID |
| Purchases | Purchase History (commission orders) |
| Usage Data | Product Interaction (likes and views, for the feeds) |

Not collected: location, contacts, health, financial info (Stripe handles
cards), browsing history, search history, advertising data, diagnostics.

## Export compliance

Already answered in the app (`ITSAppUsesNonExemptEncryption = NO`) — App
Store Connect won't ask.
