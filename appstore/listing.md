# Sugerly — App Store listing (copy & paste)

Everything App Store Connect asks for, ready to paste. Replace
`YOUR-SITE` with your Netlify address (see APP_STORE.md, step 3).

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
| Content rights | "Does your app contain, show, or access third-party content?" → **Yes** (users' posts, song previews from Deezer, GIFs from GIPHY) and you have the rights to use it |
| Price | Free |

## Version page

**Promotional text (170)**

> A cozy home for artists: share your art, film reels with music, chat with friends and join creative communities.

**Description**

> Sugerly is a friendly social app made for artists.
>
> SHARE YOUR ART
> Post drawings, paintings, cosplay, crafts and music. Get likes, comments and feedback from people who love to create.
>
> REELS
> Film short videos in clips or turn your pictures into a swipeable slideshow. Add filters, text, stickers and a song from the top charts, then post it to the Reels feed.
>
> CHAT & COMMUNITIES
> Message friends, start group chats, send GIFs, and join communities with text and voice channels.
>
> MUSIC
> Upload your own tracks, discover what other artists make, and browse today's popular songs.
>
> MAKE IT YOURS
> Pick your colour — the whole app and even the logo change to match. Earn XP, level up and collect coins just for fun.
>
> SAFE BY DESIGN
> Report any post, reel, comment, message or person, block anyone, and let our moderators handle the rest. Links aren't allowed in captions and bios to keep out spam and scams.

**Keywords (100)**

```
art,artist,drawing,painting,reels,sketch,creative,community,music,friends,chat,cosplay,anime,share
```

**Support URL:** `https://YOUR-SITE.netlify.app/Help`
**Marketing URL:** leave empty
**Privacy Policy URL:** `https://YOUR-SITE.netlify.app/Legal/privacy`
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
> Account deletion (Guideline 5.1.1(v)): Settings → Account & data → Delete account.
>
> Camera and microphone are only used when the user films a reel, takes a photo or joins a call. Song previews are 30-second previews from the Deezer API; GIFs come from GIPHY.

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

Not collected: location, contacts, health, financial info, browsing
history, search history, purchases, advertising data, diagnostics.

## Export compliance

Already answered in the app (`ITSAppUsesNonExemptEncryption = NO`) — App
Store Connect won't ask.
