# Mini Device Card Glass Container Reference

This document captures the **current** Dashboard mini device card container style (`MiniDeviceCard`) as implemented in code.

## Source of Truth

- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/DashboardView.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AppCardStyle.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/GlassTheme.swift`

## Container Shape + Layout

- Component: `MiniDeviceCard`
- Aspect ratio: `1:1`
- Corner radius: `20` (`miniCardCornerRadius`)
- Background entry point: `miniCardBackground`
- Clip shape: rounded rectangle (continuous)

## Light Mode Container (Current Approved Glass Look)

When `colorScheme == .light`, the card now uses the **same shared liquid glass recipe as Device Stats**:

- `LiquidGlassBackground(cornerRadius: 20, tint: nil, clarity: .clear)`

Lift/shadow:

- In light mode, external card lift shadows are disabled (`.clear`) to keep the container visually soft and integrated with backdrop color.

## Dark Mode Container (Fallback Glass System)

When not light mode, `MiniDeviceCard` uses:

- `AppCardBackground(style: AppCardStyles.glass(...))`
- Tone:
  - `.active` if device power is on
  - `.inactive` if off
- Radius: `20`

This resolves to `GlassTheme` tokens:

- Fill:
  - active: `Color.white.opacity(0.13)`
  - inactive: `Color.white.opacity(0.08)`
- Strokes:
  - outer: `Color.white.opacity(0.22)` (1pt)
  - inner: `Color.white.opacity(0.10)` (1pt, inset by 1)
- Shadows:
  - ambient: black `0.11`, radius `7`, y `2`
  - key: black `0.20`, radius `14`, y `7`

Extra lift is added on the card container in dark mode:

- ambient lift: black `0.15`, radius `10`, y `4`
- key lift: black `0.28`, radius `22`, y `14`

## Text Colors Used Inside Mini Card

- Light mode:
  - primary: `Color.white.opacity(0.92)`
  - secondary: `Color.white.opacity(0.74)`
- Dark mode:
  - `AppTheme.tokens(for: .dark).textPrimary`
  - `AppTheme.tokens(for: .dark).textSecondary`

## Notes

- The mini card container intentionally does **not** share the exact same recipe as the device stats container.
- Light mode mini card is tuned to be more transparent and backdrop-reactive through ultra-thin material + micro overlays, with minimal explicit tint density.
