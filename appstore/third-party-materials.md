# Third-party material inventory â€” unresolved rights

Source audit, updated 22 October 2026. This inventory identifies integrations; it does
not establish authorization outside the license files actually present.

| Material | Where it appears | Evidence found / action needed |
| --- | --- | --- |
| Seven editor fonts: Bubblegum Sans, Pacifico, Lilita One, Balsamiq Sans, Modak, Caveat Brush, Chela One | Reel text editor | Unmodified font files with bundled SIL OFL licenses in `native/Sugerly/Resources/EditorFonts/`. These replaced the supplied personal-use/demo fonts. |
| Plus Jakarta Sans | Body text | Font metadata identifies the project authors and OFL; the OFL text is now bundled in `native/Sugerly/Resources/Fonts/PlusJakartaSans-OFL.txt`. The web dependency also contains its license. |
| Original Bubbly and Cute Here | Removed from native/web bundles; legacy style keys retained | Original Downloads archives have no license text. Cute Here's author lists personal use only. Bubbly's original author lists it as 100% Free, without explicit embedding terms. Both were replaced with OFL Bubblegum Sans and Caveat Brush; licenses are bundled in both app/web source directories. Old reels retain their style keys but render with these replacements. |
| Deezer tracks, album covers and previews | Music, Home, reel sound picker/playback | API URLs and preview playback found. A permission/scope inquiry was sent to Deezer on 22 October 2026; no approval has been received. No separate commercial music synchronization/distribution authorization found. Verify the provider's terms and obtain authorization for any use beyond permitted previews; otherwise remove/restrict that use. Selecting a chart song for a reel needs particular attention. |
| Apple Music songs and artwork | Optional MusicKit playback | MusicKit is used with user authorization/subscription. Verify Apple Music identity/developer terms; this does not authorize exporting songs into user videos. |
| GIPHY GIFs/stickers | Chats, comments, profile and reel editor | API integration and textual attribution found. The owner’s GIPHY dashboard confirms its existing Sugarly iOS SDK beta key matches the native key. Confirm REST API key suitability, required logo/source attribution, caching and editing/export scope; API access alone is not unlimited redistribution rights. |
| UI effects rendered with Earshot 0.3.0 | Reward, likes, messages and switches | Generated offline from procedural forge bank entries. MIT license bundled in `native/Sugerly/Resources/Sounds/Earshot-LICENSE.txt`; generation source and sound IDs documented. This does not clear unrelated songs or artwork. |
| User art, fanart, photos, music and videos | Community, Fanart, reels, chats | Upload ownership clauses and report/block controls exist. No per-upload licenses can be proved from repository source. Use owned original content in review screenshots and demo accounts. |
| Logos, icons and other bundled graphics | Splash, Home, profile assets, App Store images | Asset files exist; verify their provenance and retain any author permissions. Do not infer ownership solely from files being bundled. |

Provider references:

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Deezer developer terms](https://cdns-content.dzcdn.net/pdf/CGV-fr.pdf)
- [GIPHY API terms](https://support.giphy.com/hc/en-us/articles/360028134111-GIPHY-API-Terms-of-Service)
- [GIPHY production-key requirements](https://support.giphy.com/hc/en-us/articles/360035158592-What-conditions-does-my-app-project-need-to-meet-in-order-to-get-a-production-API-Key)

No purchase, licensing agreement, or rights document has been fabricated or
submitted. Resolve these items before checking Apple's content-rights box.

## First-release restriction — build 162

At the owner’s request, native catalog browsing and provider playback/loading are disabled by a compile-time policy for every account and region. Deezer reel playback/reuse and legacy draft selections are blocked. GIPHY search is hidden; provider URLs are blocked before image/GIF download. Own uploads and local GIF/sticker creation remain. No provider approval is claimed. Policy and editor playback regression checks accompany the build.
