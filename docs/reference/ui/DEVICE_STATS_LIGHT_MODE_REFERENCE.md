# Device Stats Container (Light Mode) Reference

This documents the **current** style used by the Dashboard device stats container (`Total Devices / Active Devices / Scenes On`) in light mode.

## Source of Truth

- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/DashboardView.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AppGlassControls.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/LiquidGlassContainer.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AppTheme.swift`

## Component Wiring

`DeviceStatsSection` uses:

- `AppOverviewCard(...)`
- `style: .liquidGlass(tint: nil, clarity: .clear)`
- `cornerRadius: 24`

So in light mode, stats are rendered with `LiquidGlassBackground` in `.clear` clarity and **no color tint**.

## Layout + Typography

From `AppOverviewCard` / metric item:

- Card height: `68`
- Card corner radius: `24`
- Metric row: 3 columns with vertical dividers
- Metric value font: `.title.bold()`
- Metric label font: `.caption.weight(.medium)`
- Value + label spacing: `12`
- Per-metric padding: vertical `12`, horizontal `16`
- Divider width: `1`
- Divider vertical padding: `16`

## Light-Mode Visual Recipe (Current)

From `LiquidGlassBackground` with `clarity = .clear` and normal contrast:

- Base fill: `Color.white.opacity(0.04)`
- Material layer: `.ultraThinMaterial.opacity(0.15)`
- Specular top gradient: white `0.08 -> 0.03 -> clear` (topLeading to center)
- Border stroke (1pt): white gradient `0.20 -> 0.07` (topLeading to bottomTrailing)
- Additional top sheen: white `0.05 -> clear` (topLeading to center)
- Shadow: black opacity `0.10`, radius `10`, y `5`
- Tint layer: **off** (`tint: nil`)

## Text + Divider Colors in Light Mode

From `AppTheme.tokens(for: .light)`:

- `textPrimary`: RGB `(95, 91, 87) / 255`
- `textSecondary`: same base color at `0.78` opacity
- `divider`: `Color.white.opacity(0.16)`

## Why It Looks White-Tinted

Even with `tint: nil`, the container can still read slightly frosted because it stacks:

1. white base fill (`0.04`)
2. white specular gradients
3. `ultraThinMaterial` layer (`0.15`)

That combination creates the frosted white cast.
