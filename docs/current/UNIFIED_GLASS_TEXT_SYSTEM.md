# Unified Glass Text System

## Rules

- App-owned glass surfaces use `AppTheme.text(.glassPrimary/.glassSecondary/.glassTertiary, for:)` or `AppSemanticTheme.textPrimary/textSecondary/textTertiary`.
- Selected app-owned controls keep white text and show selection through stronger glass, frost, stroke, or opacity. Do not use black-on-white inversion for selected controls.
- Editable fields may use `AppTheme.text(.fieldPrimary/.fieldSecondary, for:)` when native or page-colored input text is more readable.
- Status messages use white glass text. Use `AppTheme.statusAccent(_:for:)` only for small severity markers, not full colored labels.
- Native system surfaces, including the bottom `TabView` tab bar, keep Apple-defined styling.
- Dashboard text on photo/glass backgrounds may use a soft ambient legibility blur, but glass containers should not receive extra local drop shadows.

## Dashboard Legibility

- Use `DashboardReadabilityScrim` for broad, low-opacity background support. It is a dashboard-local overlay, not a global dark veil.
- Use `dashboardLegibility(strength:)` only on text or tiny text-owned symbols that sit directly on bright or busy backgrounds.
- The legibility treatment is two soft black shadows with low opacity, large blur radii, `x: 0`, and a gentle downward y-offset. It should read as ambient separation, not a visible cast shadow.
- Do not apply text legibility modifiers to liquid-glass containers or to text inside those containers, including `AppOverviewCard`, `MiniDeviceCard`, action chips, empty-state glass cards, or buttons. Those surfaces should rely on their native glass, stroke, material, hierarchy, and design-system lift.
- For bright or custom backgrounds, prefer adaptive tint, local surface strength, or a background readability layer before adding more text shadow.

## Raw Color Allowlist

Raw `Color.white`, `Color.black`, red, green, orange, blue, and gray are allowed only for:

- lamp color swatches, gradients, and color previews;
- shadows, masks, separators, and glass highlights;
- native input chrome where SwiftUI or UIKit owns legibility;
- tiny severity dots or markers;
- preview-only backgrounds.

All app-owned text and SF Symbols outside those cases should route through `AppTheme`.
