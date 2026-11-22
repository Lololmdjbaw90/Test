# Native screenshots — 22 November 2026

Captured from the last successfully uploaded native build, 183, source
`2b482de97e268f9697e07dfda303e382b8e3d5de`, with local-only fictional demo
content. Build 184 was cancelled and 185 failed. The currently released
App Store build is still 167, so these assets are staged in Asset Library
for the newer interface and are not assigned to the live 167 product page.

Capture-only branch: `codex/store-screenshots-20261122`.
The demo harness is DEBUG-only and does not replace shipping screens.

## Uploaded set

- iPhone 17 Pro Max: 1320 × 2868, Home, Community, chat list, conversation,
  bunny customization.
- iPad Pro 13-inch (M4): 2064 × 2752, chat list, conversation,
  bunny customization.

Local demo names and messages are fictional. No private conversations are
included. Original simulator screenshots are retained at native resolution.

Two additional iPad feed captures were withheld because their sidebars
display third-party catalog music artwork whose authorization is unconfirmed.
No third-party clearance is inferred from those captures or the app's approval.

## Validation

Capture jobs 45040941309 (iPhone) and 45040944703 (iPad) both passed
`StoreScreenshotTests/testCaptureStorePages`, which waits for visible content
before attaching screenshots. All captures were inspected visually.
Earlier blank captures were rejected and were not uploaded.

Uploading an asset does not publish it or mean Apple has approved it.
These screenshots require asset review and placement with the corresponding
app version before appearing on the public product page.
