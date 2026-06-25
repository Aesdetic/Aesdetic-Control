# Selected Control Style Recipes

This document captures the selected-control styling used in the automation editor. The current direction is minimal live glass: repeated controls should feel like one coherent system, while Create/Save remains the only primary action.

## Source of Truth

- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AddAutomationDialog.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AutomationColorEditor.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AutomationTransitionEditor.swift`
- `/Users/ryan/Documents/Aesdetic-Control/Aesdetic-Control/Views/Components/AutomationEffectEditor.swift`

## Design Principles

- Use one segmented-control language across automation trigger, repeat days, and Light Action.
- Keep Preview and Power in a smaller secondary-control recipe so they do not compete with primary choices.
- Prefer text labels over decorative icons in dense editor controls.
- Use live liquid glass for low-frequency selected controls where the state should feel tactile.
- Keep rapid repeat-day selection on a stable non-live recipe to avoid visible flash during tap/drag changes.
- Keep tracks low-contrast so controls read as available choices, not separate cards.
- Reserve stronger visual weight for Create/Save and true validation.
- Place validation near the broken control without changing surrounding layout.

## Recipe: Automation Segment Track

Use for the shared background track behind grouped choices.

- Function: `automationSegmentTrackBackground(cornerRadius:)`
- Shape: `RoundedRectangle(..., style: .continuous)`
- Default corner radius: `18`
- Fill: `Color.white.opacity(0.045)`
- Background: `.ultraThinMaterial.opacity(0.64)`
- Stroke: `Color.white.opacity(0.09)`, `1pt`

Current uses:

- Sunrise / Sunset / Time
- Color / Transition / Animation
- Repeat-day row via `weekdayTrackBackground`

## Recipe: Automation Segment Selected Live Glass

Use for selected items inside low-frequency automation segmented controls.

- Function: `automationSegmentBackground(isActive:cornerRadius:)`
- Shape: `RoundedRectangle(..., style: .continuous)`
- Default corner radius: `14`
- Glass: `.appLiquidGlass(role: .card, cornerRadius: cornerRadius)`
- Highlight overlay:
  - topLeading: `Color.white.opacity(0.54)`
  - center: `Color.white.opacity(0.22)`
  - bottomTrailing: `Color.clear`
- Stroke: `Color.white.opacity(0.24)`, `1pt`
- Shadow: black `0.04`, radius `4`, y `2`
- Selected text: black `0.78`
- Unselected text: white `0.64`

Current uses:

- Sunrise / Sunset / Time selected segment
- Light Action selected segment

Current control sizes:

- Sunrise / Sunset / Time tab height: embedded `38`, sheet `40`
- Light Action tab height: embedded `38`, sheet `40`

## Recipe: Automation Secondary Control

Use for compact support controls that should be available but not compete with selected tabs or Create/Save.

- Function: `secondaryControlBackground(isActive:cornerRadius:)`
- Shape: `RoundedRectangle(..., style: .continuous)`
- Default corner radius: `15`
- Active glass: `.appLiquidGlass(role: .control, cornerRadius: cornerRadius)`
- Active fill overlay:
  - topLeading: `Color.white.opacity(0.58)`
  - bottomTrailing: `Color.white.opacity(0.28)`
- Inactive treatment: same quiet material language as non-selected automation segments
  - Fill: `Color.white.opacity(0.045)`
  - Background: `.ultraThinMaterial.opacity(0.64)`
  - Stroke: `Color.white.opacity(0.09)`, `1pt`
- Active stroke: `Color.white.opacity(0.24)`, `1pt`
- Text: black `0.78` active, white `0.64` inactive

Current uses:

- Preview active/inactive state
- Power on/off state

Current control sizes:

- Preview height: `32`
- Power height: `32`, width `58`

## Recipe: Repeat Day Connected Segment

Use for repeat-day chips and any row that toggles rapidly or supports drag selection.

- Function: `repeatDaySelectedRunBackground(cornerRadius:)`
- Relationship: compact connected static variant of Automation Segment Selected Live Glass.
- Merge adjacent selected items into one continuous rounded shape.
- Keep separated selected items aligned to their fixed slots.
- Avoid inserting or removing live material inside selected segments, because the row can flash during rapid tap/drag changes.
- Use the same text contrast as live selected controls so the row still feels related.

Current repeat-day values:

- Embedded height: `32`
- Sheet height: `36`
- Track corner radius: `16`
- Selected corner radius: `11...13`
- Selected text: black `0.78`
- Unselected text: white `0.64`

Layer order:

1. Track background.
2. Selected run shapes.
3. Button labels and hit targets.
4. Transparent drag/tap gesture overlay.

## Recipe: Automation Primary Action

Use only for Create/Save in the inline automation editor header.

- Function: `inlinePrimaryActionBackground(isEnabled:)`
- Shape: `RoundedRectangle(cornerRadius: 15, style: .continuous)`
- Enabled glass: same active family as Automation Secondary Control
- Enabled fill overlay:
  - topLeading: `Color.white.opacity(0.60)`
  - bottomTrailing: `Color.white.opacity(0.30)`
- Disabled treatment: quiet material family, `Color.white.opacity(0.035)` fill
- Enabled stroke: `Color.white.opacity(0.28)`, `1pt`
- Disabled stroke: `Color.white.opacity(0.09)`, `1pt`
- Enabled text: black `0.78`
- Disabled text: white `0.54`
- Font: `.caption`, semibold
- Horizontal padding: `12`
- Height: `32`
- Shadow: black `0.035`, radius `2`, y `1`

Do not reuse this for segmented choices. It is the save/create affordance.

## Recipe: Automation Editor Header

Use for the inline automation create/edit header.

- Back button: use inactive Automation Secondary Control, `.caption` semibold, height `32`, horizontal padding `12`
- Header layout: equal `82pt` left/right action zones, centered title
- Title: `.subheadline`, semibold, white `0.96`
- Rename icon: caption, semibold, white `0.52`, placed close to the title
- Subtitle: omitted in the embedded editor
- Primary action: use the Automation Primary Action recipe

Keep the rename affordance visually secondary. The title row is tappable, but the pencil should not create extra spacing that makes the title block feel chunky.

## Recipe: Automation Detail Rows

Use inside Color, Transition, and Animation detail editors.

- Section labels: `.footnote`, semibold, white `0.78`
- Supporting values: `.caption`, medium, white `0.68`
- Helper or disabled-state text: white `0.62...0.64`
- Inline editor vertical spacing: `12...14`

These rows should feel denser than the trigger and Light Action segmented choices. Do not introduce new button shapes here unless the control needs an explicit state.

## Recipe: Compact Preset Rail

Use for saved colors, saved transitions, and saved animations inside the automation editor.

- Do not show visible section titles or preset names in the editor surface.
- Preserve preset names through accessibility labels.
- Rail spacing: `7pt` between swatches, `2pt` internal horizontal/vertical padding.
- Color and animation rails: `48x18`, corner radius `6`.
- Transition rails: `64x18`, corner radius `6`, split start/end gradients with a subtle center divider.
- Gradient opacity: `0.72`, following the quieter automation-card preview-rail direction.
- Highlight: top-to-bottom white overlay from `0.18` to `0.02`.
- Selected state: white `0.52` ring, `1.5pt`, plus centered white checkmark.
- Unselected state: white `0.12` ring, `1pt`.
- Selected shadow: black `0.08`, radius `4`, y `2`.

These rails should read as quick visual shortcuts, not cards. They take visual reference from `AutomationRow.previewRail(for:)` and should not compete with the active Light Action controls or the main sliders.

## Performance Notes

Live liquid glass has more blur/compositing cost than a static fill. It is acceptable for deliberate controls such as trigger, Light Action, Preview, Power, and Create/Save. Avoid it on drag-heavy or rapidly changing rows such as repeat days.

## Current Coherence Notes

- Trigger and Light Action are both text-only segmented controls using the same quiet selected live glass.
- Repeat days use a stable connected selected run instead of independent live segments.
- Power and Preview use secondary live glass so they remain supportive.
- Create/Save is the only primary action treatment in the automation editor.
