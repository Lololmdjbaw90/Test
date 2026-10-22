# App Review resubmission — 22 October 2026

Sugerly iOS 1.0, build **167**, was resubmitted in App Store Connect. The visible status after submission was **In attesa di verifica** (Waiting for Review). This is not an approval.

- Signed upload: GitHub Actions run 39777593109, successful; application source dc5c4f17.
- Original Home sidebar content is retained: palettes, invites, art tips and personal stats. Only sidebar card surfaces/shadows/borders are removed. Home's wallpaper spans the feed and side extras; side extras scroll independently.
- Rounded body/navigation text and bundled OFL Bubblegum headings remain.
- The same first-release policy disables Deezer catalog playback/reuse and GIPHY search/provider media loading for every account and region. Original uploads and creation tools remain.
- Sidebar/palette/invite interaction test passed in run 39777597107, including Copy code. The subsequent test could not terminate/restart the simulator app; the recording-scroll test passed when rerun alone in run 39778941769.
- Earlier provider policy and editor looping/export regression checks passed in run 39743819884. iPhone Home navigation/scroll checks passed in run 39746428069.
- App Review Notes and the description were updated. The six-question response was sent to Apple, with Sugerly-physical-walkthrough.mp4 attached to both review information and the reply.
- The physical recording predates this release, starts inside the app, and does not clearly establish login or coin-unlock coverage. These limits were disclosed to Apple. Updated physical-device frame rates have not been certified by simulator checks.
- Existing automatic release after Apple's approval was preserved.

Confirmation image is kept locally under work/apple-build167-waiting-review.png; recordings, private credentials and local work artifacts are not committed.
