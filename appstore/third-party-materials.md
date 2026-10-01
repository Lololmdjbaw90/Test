# Third-party material inventory — unresolved rights

Source audit, 1 October 2026. This inventory identifies integrations; it does
not establish authorization outside the license files actually present.

| Material | Where it appears | Evidence found / action needed |
| --- | --- | --- |
| Seven editor fonts: Bubblegum Sans, Pacifico, Lilita One, Balsamiq Sans, Modak, Caveat Brush, Chela One | Reel text editor | Unmodified font files with bundled SIL OFL licenses in `native/Sugerly/Resources/EditorFonts/`. These replaced the supplied personal-use/demo fonts. |
| Plus Jakarta Sans | Body text | Font metadata identifies the project authors and OFL. Preserve the actual license with every bundled distribution; verify the converted/static font files against the upstream license. |
| Bubbly and Cute Here | Heading/label fonts, native and old web assets | No license document found in the repository; font license metadata is empty. Obtain an app-embedding/distribution license from the identified author, or replace them with verified OFL fonts before claiming rights. A downloaded font is not a license. |
| Deezer tracks, album covers and previews | Music, Home, reel sound picker/playback | API URLs and preview playback found. No separate commercial music synchronization/distribution authorization found. Verify the provider's terms and obtain authorization for any use beyond permitted previews; otherwise remove/restrict that use. Selecting a chart song for a reel needs particular attention. |
| Apple Music songs and artwork | Optional MusicKit playback | MusicKit is used with user authorization/subscription. Verify Apple Music identity/developer terms; this does not authorize exporting songs into user videos. |
| GIPHY GIFs/stickers | Chats, comments, profile and reel editor | API integration and textual attribution found. Confirm production approval, required logo/source attribution, and that editing/export use is permitted; API access alone is not unlimited redistribution rights. |
| User art, fanart, photos, music and videos | Community, Fanart, reels, chats | Upload ownership clauses and report/block controls exist. No per-upload licenses can be proved from repository source. Use owned original content in review screenshots and demo accounts. |
| Logos, icons and other bundled graphics | Splash, Home, profile assets, App Store images | Asset files exist; verify their provenance and retain any author permissions. Do not infer ownership solely from files being bundled. |

Provider references:

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Deezer developer terms](https://cdns-content.dzcdn.net/pdf/CGV-fr.pdf)
- [GIPHY API terms](https://support.giphy.com/hc/en-us/articles/360028134111-GIPHY-API-Terms-of-Service)
- [GIPHY production-key requirements](https://support.giphy.com/hc/en-us/articles/360035158592-What-conditions-does-my-app-project-need-to-meet-in-order-to-get-a-production-API-Key)

No purchase, licensing agreement, or rights document has been fabricated or
submitted. Resolve these items before checking Apple's content-rights box.
