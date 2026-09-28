# Continuation of Claude's moderation/performance work

Based on Claude's pushed commit `f56ecb0f`. The two moderation files in the pasted transcript were not present in that branch; they were recreated and connected to the current write paths.

## Implemented

- One shared JSON text policy, copied into the iOS bundle by `node scripts/sync-moderation.mjs`. Web and native rules cover English/Italian abuse examples, common Unicode/leet/spaced-letter evasion, threats, targeted harassment, scam phrases, sensitive number/address patterns, flooding, and caption/bio links.
- Guards on entity creation, editing, profile changes and signup names; native atomic write sets also pass through the gate. Reel text overlays are included. Reports and audit records intentionally accept quoted offensive material.
- Message/comment/post/profile cooldowns of 1.2/2.5/5/1.5 seconds, duplicate-create checks, and temporary local pauses after three clear violations within ten minutes. Setup records such as channels and roles are moderated without throttling multi-step server creation. Likes/presence/count-only updates bypass text checks.
- Positive capitalized enthusiasm, ordinary dates, game/idiom examples, and requests for mental-health support do not earn strikes. Ambiguous wording asks for a rephrase without a strike.
- Removed web page-entry motion; native navigation-path changes disable transition animation while leaving ordinary button feedback intact.
- Settings uses lazy sections and rasterized wallpaper thumbnails. Underlying wallpaper motion pauses for shell overlays/sheets and backgrounded scenes. Replaced large blurred background shapes with radial gradients.
- Decorative scroll-driven depth on the web and iOS 18+, with static fallback on iOS 17 and Reduce Motion/still-background support. No continuously running parallax timer.

## Boundaries and blocked work

These are client-side safety checks, **not server-enforced moderation or account-wide sanctions**. Reloading/changing clients can bypass local cooldowns and temporary pauses. Authoritative moderation needs a trusted write service plus security rules preventing direct client bypass. The word policy is not a comprehensive multilingual classifier.

No new AI submission was added. Automatic approval review rejected transmitting user-written text (including private messages) to Google Firebase AI Logic/Gemini without explicit approval. A clarification is pending. The existing moderation preflight now stays local and no longer sends rejected text to the Discord webhook. Unrelated existing AI tools are unchanged.

GitHub refused to start the native build because recent account payments failed or the spending limit needs increasing. No new IPA or native compiler/test success is claimed. After resolving GitHub Billing & plans, rerun **Build native iOS app (.ipa)** on `codex/finish-moderation`.

## Checks

- `node scripts/test-moderation.mjs`: shared policy examples and limiter behavior.
- `node scripts/sync-moderation.mjs --check`: identical web/native policy data.
- `npm run build`: web production compilation.
- `scripts/test-write-gates.mjs`: demo-mode browser integration checks; set `PLAYWRIGHT_MODULE` to an installed Playwright package and run the demo server on port 3000.
- CI runs `node scripts/test-native-policy.mjs` to execute the actual Swift policy against the same fixtures before the iOS build. This check could not run while GitHub billing blocked the runner.

Native performance and navigation still need real-device verification. Image/video content moderation is outside this text-only change.
