# Background Rendering Root Cause and Fix

## Summary
The app intermittently showed:
- a clipped/split background (one side photo, one side old/fallback background),
- a transient zoomed/cropped frame,
- then sometimes a full black screen.

## Why It Happened
The issue came from unstable background composition and fallback behavior:

1. `AppBackground` switched between two render paths at runtime based on `UIImage(named:)` checks.
2. The photo layer was composited in a way that could produce partial draws during layout/render transitions.
3. When a frame did not fully paint, the view stack could briefly reveal fallback/underlying layers, which looked black.
4. Global UIKit appearance had previously introduced opaque fallback behavior (`systemBackground` + `isOpaque = true`), which made any missed paint frame visually obvious as black.

## What We Changed
File: `Aesdetic-Control/Views/Components/AppBackground.swift`

1. Always render a full-canvas neutral base first (`neutralGlassLayer`).
2. Overlay the photo on top only if asset exists, but do not branch between full background modes per frame.
3. Cache the photo lookup once (`private static let alpineImage = UIImage(named: ...)`) instead of repeated runtime checks.
4. Keep photo rendering full-canvas (`scaledToFill`, infinite frame, safe-area coverage) and avoid unstable split composition behavior.

Related global safety (already applied):
- `Aesdetic_ControlApp.swift` uses transparent window + clear UIKit container backgrounds so background layers do not fall through to opaque system color.

## Why It Works Now
The current path is stable because:

1. There is always a guaranteed painted base layer.
2. The photo layer is a deterministic overlay, not a mutually exclusive mode that can flicker during recomposition.
3. Image availability is resolved once, reducing frame-to-frame branching.
4. Transparent window/container configuration prevents black fallback from bleeding through transient hierarchy updates.

## Notes
- Logs like `gradient.hydrate.bootstrap` and `gradient.hydrate.live` are device gradient hydration logs (WebSocket/device state), not app background rendering logs.

## Quick Regression Check
1. Cold launch app.
2. Switch tabs quickly (`Dashboard`, `Devices`, `Automation`, `Wellness`).
3. Open/close sheets.
4. Confirm no vertical split, no clipped side, and no black full-screen frame.
