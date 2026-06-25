# Unified Style Direction - 2026-06-24

This note captures the current visual direction to preserve while the app's glass and control styling is being unified.

## Button State Baseline

Use the Devices tab location filter pills as the current button-state reference:

- Source: `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/DeviceControlView.swift`
- Component: `LocationPillButton`
- Examples: `All`, `Bedroom`, `Living Room`

## Accepted Qualities

- Selected and non-selected states should feel like part of the same glass control family.
- The selected state can become more filled and readable, but should not feel like a separate heavy card.
- The non-selected state should remain visible enough to read as an available choice.
- Pressing a control should not create a white flash or a temporary hard-white layer.
- Press feedback should be subtle and stable, preferably scale or motion rather than a new bright overlay.
- Font color is still to be determined.

## Reuse Candidates

This state language is a candidate for:

- Location and category filters.
- Compact segmented choices.
- Secondary mode toggles where both selected and non-selected states need to remain visible.

Do not apply this automatically to the Apple native tab bar or system-owned dock styling. Those should stay native unless a separate decision changes that direction.

## Current Open Questions

- Final selected font color.
- Final non-selected font color.
- Whether this becomes the default pill recipe across setup, devices, automation, and detail surfaces.
