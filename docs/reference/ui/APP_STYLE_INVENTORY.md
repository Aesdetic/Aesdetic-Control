# App Style Inventory

This inventory captures visual styles that exist in the SwiftUI codebase today. It is not a proposal for the future design system.

## How to use this inventory

- Treat each entry as a current-code recipe. If a value is not obvious from source, it is marked "needs verification" with the file or function to inspect.
- Use `Reuse status` to decide whether a style should be promoted, merged, left local, or retired.
- Check the detailed recipe docs before changing selected controls or dashboard cards:
  - [Selected control style recipes](./SELECTED_CONTROL_STYLE_RECIPES.md)
  - [Mini device card glass reference](./MINI_DEVICE_CARD_GLASS_REFERENCE.md)
  - [Device stats light mode reference](./DEVICE_STATS_LIGHT_MODE_REFERENCE.md)
- Existing detailed docs may be older than the current code. This inventory calls out known mismatches.
- "Approved" means the style is an intentional reusable recipe today. "Experimental" means it is active but likely needs visual review before promotion. "Duplicate candidate" means it overlaps another active style. "Needs unification" means the app has multiple local recipes for the same job. "Do not reuse" means it is legacy, system-specific, or intentionally narrow.

## Style Families

| Family | Main sources | Appears in | Reuse status |
| --- | --- | --- | --- |
| App background and overlays | `AppBackground`, `LiquidGlassOverlay`, `SetupBackdropBlur` | App shell, dashboard, settings, automation sheets, wellness, setup overlays | Approved |
| Semantic theme and typography | `AppTheme`, `GlassTheme`, `AppTypography` | Shared app text, settings, cards, controls | Approved |
| Liquid glass surfaces | `LiquidGlassBackground`, `appLiquidGlass`, `LiquidGlassButton` | Dashboard tiles, detail shell, setup flow, selected controls, older buttons | Duplicate candidate |
| Card shells | `AppCardStyle`, `GlassCardBackground`, `SettingsCard`, local panel backgrounds | Automation, scenes, wellness, settings, editor panes | Duplicate candidate |
| Shared controls | `AppGlassIconButton`, `AppGlassPillButton`, `DockBar`, local icon buttons | Headers, settings category selector, scene actions, navigation dock | Needs unification |
| Dashboard and device cards | `MiniDeviceCard`, `EnhancedDeviceCard`, `DeviceStatsSection` | Dashboard, device list, device tab | Approved |
| Device detail controls | `DeviceDetailView`, `UnifiedColorPane`, `EffectsPane`, `TransitionPane` | Detailed device view | Needs unification |
| Automation cards and editor | `AutomationView`, `AutomationRow`, `AddAutomationDialog`, automation editors | Automation list, create/edit flow, shortcuts | Duplicate candidate |
| Settings surfaces | `ComprehensiveSettingsView`, `WLEDSettingsView`, `RealTimeSettingsView`, `WLEDWebConfigView` | Settings and WLED compatibility screens | Needs unification |
| Saves, scenes, playlists | `ScenesDashboardView`, `PresetsListView`, save dialogs | Saves tab, scenes, presets, playlist editor | Needs unification |
| Wellness | `WellnessView` | Wellness daily, overview, history, date/time sheets | Experimental |
| Widgets | `DeviceWidgetView`, `DeviceControlWidget` | Home Screen, Lock Screen, StandBy widgets | Do not reuse |
| Status and error UI | `ErrorBanner`, local status chips | Global errors, active run chips, setup messages | Needs unification |

## App Background And Overlays

### App Background

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppBackground.swift`, `AppBackground(includePhoto:)`, `AlpinePhotoBackground` |
| Appears | Main dashboard, device control, automation, settings, wellness, likely all top-level app surfaces |
| Shape and radius | Full-screen background, ignores safe area |
| Fill/material/background | Neutral beige/taupe gradient base with radial highlights and vignette; optional alpine photo asset with saturation, contrast, ultra-thin material veil, top black gradient, and radial vignette |
| Stroke/border | None |
| Shadow/lift | None |
| Typography | None |
| Contrast notes | Designed to sit behind white/glass foregrounds. Some screens still force white text, while settings often use `AppTheme` tokens. |
| Interaction states | Static |
| Reuse status | Approved |
| Unification notes | Keep as app shell background. Do not replace card or panel fills with this recipe. |
| Known concerns | Photo opacity and white-text contrast should be checked when new sections are added. `NoiseTexture` appears private/unused and should not be reused without verification. |

### Liquid Glass Overlay

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/LiquidGlassOverlay.swift`, `LiquidGlassOverlay` |
| Appears | Automation creation sheet, `ComprehensiveSettingsView`, modal/photo backdrops |
| Shape and radius | Full-screen overlay, ignores safe area |
| Fill/material/background | Optional `.ultraThinMaterial` at `blurOpacity`; top-left white overlay sheen; vertical soft-light gradient; radial vignette; optional center sheen; increased-contrast mode adds black backdrop |
| Stroke/border | None |
| Shadow/lift | None |
| Typography | None |
| Contrast notes | Increased contrast multiplies highlight, vertical, vignette, and sheen values by 1.6 and increases blur by 0.2. |
| Interaction states | Static and `allowsHitTesting(false)` |
| Reuse status | Approved |
| Unification notes | Reuse for whole-screen glass atmosphere only, not component chrome. |
| Known concerns | Values differ per caller. Inventory of tuned presets should be added if more screens adopt it. |

### Setup Backdrop Blur

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/SetupBackdropBlur.swift`, `SetupBackdropBlur` |
| Appears | Setup/product flow overlays behind mandatory setup |
| Shape and radius | Full-screen rectangles |
| Fill/material/background | `.ultraThinMaterial` opacity default 0.44 plus black dim opacity default 0.03 |
| Stroke/border | None |
| Shadow/lift | None |
| Typography | None |
| Contrast notes | Minimal dimming, intended to keep underlying app recognizable |
| Interaction states | Static |
| Reuse status | Approved |
| Unification notes | Could merge conceptually with `LiquidGlassOverlay`, but current recipe is much simpler and should stay separate unless setup visual language changes. |
| Known concerns | None found in source. |

## Semantic Theme And Typography

### App Semantic Theme

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppTheme.swift`, `AppSemanticTheme`, `AppTheme.tokens(for:)` |
| Appears | Settings, wellness, shared controls, scene cards, overview cards |
| Shape and radius | Token source, no shape |
| Fill/material/background | `surface`, `surfaceElevated`, `surfaceMuted`, card/control fills, pill fills |
| Stroke/border | `divider`, `cardStrokeOuter`, `cardStrokeInner`, `controlStroke` |
| Shadow/lift | Card and control shadows delegated from `GlassTheme` |
| Typography | Used with `AppTypography` |
| Contrast notes | Light mode text primary/secondary use warm dark grays; dark mode uses white opacity tokens. Accent is white in dark and light primary in light. |
| Interaction states | Active/inactive helpers for cards, controls, and pills |
| Reuse status | Approved |
| Unification notes | New reusable styles should consume these tokens first. |
| Known concerns | Some active views bypass tokens and hard-code white text, especially device detail, automation, and preset rows. |

### Glass Theme

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/GlassTheme.swift`, `GlassSurfaceStyle`, `GlassTextStyle`, `GlassCardBackground` |
| Appears | App cards, controls, dashboard/device card fallback values |
| Shape and radius | `GlassCardBackground` uses continuous rounded rectangle with caller radius |
| Fill/material/background | Active card fill white 0.13, inactive 0.08, panel 0.10, field 0.16, separator 0.16 |
| Stroke/border | Outer stroke white 0.22, inner stroke white 0.10 |
| Shadow/lift | Card ambient black 0.11 radius 7 y2; card key black 0.20 radius 14 y7; control ambient black 0.07 radius 5 y1; control key black 0.14 radius 10 y5 |
| Typography | Text tokens only; dark text uses white 1.0/0.78/0.58; pills selected black, default white |
| Contrast notes | Light and dark surface styles are currently identical. Light text style exists, but `AppTheme` overrides several light text colors. |
| Interaction states | Active and inactive card/control variants |
| Reuse status | Approved |
| Unification notes | This is the source for glass shadows and strokes. Prefer this over local white-opacity copies. |
| Known concerns | Surface parity between light/dark may be intentional, but should be verified before treating as final design-system behavior. |

### App Typography

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppTheme.swift`, `AppTypography` |
| Appears | Most modern SwiftUI surfaces |
| Shape and radius | Not applicable |
| Fill/material/background | Not applicable |
| Stroke/border | Not applicable |
| Shadow/lift | Not applicable |
| Typography | SF Pro Display for large title/title/headline-like display helpers; SF Pro Text for body/meta; fallback system fonts through `Font.custom(..., relativeTo:)` |
| Contrast notes | Typography is not tied to color. Many screens pair it with local white text. |
| Interaction states | Weight variants per caller |
| Reuse status | Approved |
| Unification notes | Keep as the common type entry point. New local `Font.system` usage should be reviewed. |
| Known concerns | Dashboard has its own `DashboardTypography` scale; widgets use system font APIs for WidgetKit/StandBy. |

## Liquid Glass Surfaces

### Liquid Glass Background

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/LiquidGlassContainer.swift`, `LiquidGlassBackground` |
| Appears | Fallback path for `appLiquidGlass`, overview cards, mini cards, older liquid button recipes |
| Shape and radius | Continuous rounded rectangle, default radius 20 |
| Fill/material/background | Base white fill plus `.ultraThinMaterial`, specular gradient, optional tint blend, top sheen. Clarity `.standard` is denser; `.clear` is lighter. |
| Stroke/border | Gradient white stroke with higher opacity at top-left and lower at bottom-right |
| Shadow/lift | Standard has black shadow around 0.12 radius 12 y6; clear has black 0.10 radius 10 y5; increased contrast raises opacities |
| Typography | None |
| Contrast notes | Increased-contrast mode raises base/material/stroke/specular/top-sheen values. |
| Interaction states | Static; callers supply active/selected overlays |
| Reuse status | Approved |
| Unification notes | Use through `appLiquidGlass` unless a caller needs direct `tint` or `clarity`. |
| Known concerns | Direct use and wrapper use coexist. Prefer wrapper where possible. |

### App Liquid Glass Role Modifier

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppLiquidGlass.swift`, `AppLiquidGlassRole`, `appLiquidGlass(...)` |
| Appears | Device cards, mini cards, detail shell, product setup, settings buttons, dashboard chips, automation selected segments |
| Shape and radius | Roles: card 20, panel 20, control 16, frostedTransition 20, highContrast 20; callers often override to 12, 14, 16, 18, 24, 28, 36 |
| Fill/material/background | On iOS 26: panel/highContrast/frostedTransition use `.glassEffect(.regular)` with opacity/tint overlays; card/control use `.glassEffect(.clear)`. Fallback uses `LiquidGlassBackground` standard or clear. |
| Stroke/border | High-contrast role can add white edge; frostedTransition adds white stroke and top sheen; fallback inherits `LiquidGlassBackground` stroke |
| Shadow/lift | iOS path mostly relies on native glass plus overlays; fallback inherits `LiquidGlassBackground` shadows |
| Typography | None |
| Contrast notes | High-contrast role can add black tint plus optional white edge, helping white text over busy app background. |
| Interaction states | Static. Selection/press/loading are caller-owned. |
| Reuse status | Approved |
| Unification notes | This should be the app-level glass recipe boundary. Local rounded white-opacity panels should migrate here when behavior allows. |
| Known concerns | `.frostedTransition` is specialized and should stay separate from generic cards. |

### Legacy Liquid Glass Button

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/LiquidGlassButton.swift`, `liquidGlassButton` modifier |
| Appears | Needs verification. Current scan found the definition; no confirmed active call site in this pass. |
| Shape and radius | Rounded rectangle, default corner radius 20 |
| Fill/material/background | Active: white 0.66, `.ultraThinMaterial` 0.35, specular gradient, optional tint blend. Inactive is lower opacity. |
| Stroke/border | Gradient white stroke 0.35 to 0.10 |
| Shadow/lift | Active black 0.22 radius 16 y8, inactive black 0.06 radius 8 y2, optional tint glow |
| Typography | Caller-owned |
| Contrast notes | Active white fill can invert text needs; caller must verify foreground. |
| Interaction states | Active/inactive only |
| Reuse status | Duplicate candidate |
| Unification notes | Prefer `AppGlassPillButton`, `AppGlassIconButton`, or `appLiquidGlass(role:.control)` for new controls. |
| Known concerns | May be unused legacy API. Verify with `rg "liquidGlassButton"` before removal. |

## Card Shells

### App Card Background

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppCardStyle.swift`, `AppCardStyles.glass`, `AppCardBackground` |
| Appears | Automation sections, scenes dashboard, wellness sections, settings cards through related `GlassCardBackground` |
| Shape and radius | Caller-selected continuous rounded rectangle, commonly 16, 18, 20, 22, 24 |
| Fill/material/background | Tone active/inactive/muted maps to `AppTheme.cardFill`/surface tokens and `GlassTheme` fills |
| Stroke/border | Outer and inner glass strokes |
| Shadow/lift | `GlassTheme` card ambient and key shadows |
| Typography | Caller-owned, commonly `AppTypography` |
| Contrast notes | Works with both theme text and white local text, but white text is not always checked in light mode. |
| Interaction states | Tone active/inactive/muted only; pressed/selected usually caller-owned |
| Reuse status | Approved |
| Unification notes | Default recipe for reusable cards. |
| Known concerns | Some screens recreate similar white-opacity panels instead of using this. |

### Settings Card

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/ComprehensiveSettingsView.swift`, `SettingsCard<Content>` |
| Appears | Comprehensive settings categories and detail groups |
| Shape and radius | Continuous rounded rectangle radius 16 |
| Fill/material/background | `GlassCardBackground` with active `AppTheme.cardFill`; added diagonal white sheen overlay clipped to radius |
| Stroke/border | App card outer/inner strokes |
| Shadow/lift | App card key and ambient shadows |
| Typography | Title `AppTypography.headline` semibold, content usually subheadline/caption with theme tokens |
| Contrast notes | Uses theme text, better light-mode compatibility than white-only panels. |
| Interaction states | Static card; header content may host buttons/loading |
| Reuse status | Approved |
| Unification notes | Could merge with `AppCardBackground` if the diagonal sheen becomes a card variant. Keep settings-specific until then. |
| Known concerns | Radius 16 differs from many 20/24 app cards. Intentional density should be verified before broad reuse. |

### Local White-Opacity Editor Panels

| Field | Current code |
| --- | --- |
| Source | `AutomationColorEditor`, `AutomationEffectEditor`, `AutomationTransitionEditor`, `EffectsPane`, `TransitionPane`, `DeviceDetailView` local panel backgrounds |
| Appears | Device detail color/effect/transition controls and automation inline editors |
| Shape and radius | Usually radius 18 or 20 for panels; radius 8, 10, 12, 14 for nested controls |
| Fill/material/background | Common recipe is `Color.white.opacity(0.06)` or `backgroundFill` 0.06 / 0.12 in increased contrast |
| Stroke/border | White stroke around 0.12 to 0.26 |
| Shadow/lift | Usually none; selected chips sometimes add local shadows |
| Typography | Mostly `AppTypography` with white text |
| Contrast notes | Designed for dark/glass detail sheets. Light-mode behavior needs visual verification. |
| Interaction states | Disabled opacity 0.45, loading `ProgressView`, selected white fills for chips/segments |
| Reuse status | Needs unification |
| Unification notes | Candidate to merge into `AppCardBackground` or `appLiquidGlass(role:.panel/control)` variants. |
| Known concerns | Many controls use the same white-opacity values but not a shared helper, so future changes are high risk. |

## Shared Controls

### App Glass Icon Button

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppGlassControls.swift`, `AppGlassIconButton` |
| Appears | Top bars, settings header, scenes undo, dashboard/settings action icons |
| Shape and radius | Circle, default size 48 |
| Fill/material/background | `AppTheme.controlFillStyle(active:)`; optional light-mode shine strokes when prominent |
| Stroke/border | `AppTheme.controlStroke(active:)`; extra white shine strokes in light mode |
| Shadow/lift | `GlassTheme` control ambient and key shadows |
| Typography | SF Symbol title3 semibold by default |
| Contrast notes | Foreground from `AppTheme.controlForeground(active:)`; selected/prominent often black on white |
| Interaction states | Press scale 0.93. Loading/disabled are caller-owned, usually opacity 0.35 to 0.55. |
| Reuse status | Approved |
| Unification notes | Use for circular icon actions. Local 32/36/44 icon buttons are duplicate candidates. |
| Known concerns | No intrinsic loading state. |

### App Glass Pill Button

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AppGlassControls.swift`, `AppGlassPillButton` |
| Appears | Settings category selector, scenes create/undo actions, assorted pill actions |
| Shape and radius | Compact radius 14, regular radius 18 |
| Fill/material/background | Default uses `AppTheme.pillFill`; optional `useControlGlassRecipe` wraps `appLiquidGlass(role:.control)` |
| Stroke/border | Default `AppTheme.pillStroke`; optional Apple-selected overlay adds selected white fill and stroke |
| Shadow/lift | Control shadows |
| Typography | Caption or subheadline semibold based on size |
| Contrast notes | Uses `AppTheme.pillText`; selected pill often black-on-white |
| Interaction states | Selected/default, disabled opacity 0.45, press scale 0.97/0.96 |
| Reuse status | Approved |
| Unification notes | Use for reusable text commands and category filters. |
| Known concerns | Some screens still use local capsule buttons with similar states. |

### Dock Bar

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/DockBar.swift`, `DockBar` |
| Appears | Main app bottom navigation dock |
| Shape and radius | Container rounded rectangle radius 36; active pill radius 26, height 58 |
| Fill/material/background | Container and active pill use `appLiquidGlass(role:.highContrast)` |
| Stroke/border | From high-contrast glass role |
| Shadow/lift | From glass role/native effect |
| Typography | Icon display size 18 semibold; active label caption2 semibold |
| Contrast notes | Active foreground white; inactive white 0.70 |
| Interaction states | Active matched-geometry pill, inactive text/icon, plain buttons |
| Reuse status | Approved |
| Unification notes | Keep navigation-specific. Do not reuse for segmented controls. |
| Known concerns | Active state is visual only; ensure labels fit localized strings. |

### Local Icon Buttons

| Field | Current code |
| --- | --- |
| Source | `AutomationRow.neutralIconButton`, `PresetDeleteButton`, `PresetIconButton`, `DeviceDetailView` option/power buttons, dashboard mini-card power buttons |
| Appears | Automation list, saves/presets, detail sheet, dashboard cards |
| Shape and radius | Circles 32, 36, 44; dark device card power uses radius 8 square in some modes |
| Fill/material/background | White opacity 0.08 to 0.16, selected/active sometimes white fill |
| Stroke/border | White 0.16 to 0.24; selected can be white 0.95 |
| Shadow/lift | Some use `GlassTheme` control shadows; others none |
| Typography | SF Symbol caption to headline |
| Contrast notes | Mostly white-on-glass, black-on-white selected |
| Interaction states | Loading `ProgressView`, disabled opacity 0.35 to 0.55, press scale in some cards |
| Reuse status | Duplicate candidate |
| Unification notes | Candidate merge into size variants of `AppGlassIconButton` plus local active/destructive variants. |
| Known concerns | Similar affordances look slightly different across dashboard, detail, automation, and presets. |

## Dashboard And Device Cards

### Dashboard Header And Counts

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/DashboardView.swift`, dashboard header, `LiquidGlassLogoGlyph` |
| Appears | Dashboard first screen |
| Shape and radius | Logo fallback high-contrast rounded rect radius 14; count badge capsule |
| Fill/material/background | App background. Logo uses image if available, otherwise high-contrast glass. Count badge uses `theme.surfaceMuted`. |
| Stroke/border | Badge has no explicit stroke in header count; logo uses glass role |
| Shadow/lift | Logo from glass role |
| Typography | Local `DashboardTypography`: greeting display 30 semibold, section title 21, body 14, meta 12, micro 11 |
| Contrast notes | Dashboard forces white text palette in many places, including light mode. |
| Interaction states | Static, except action buttons |
| Reuse status | Experimental |
| Unification notes | Dashboard typography should be reconciled with `AppTypography` before design-system promotion. |
| Known concerns | White text over photo/background must be checked in light mode. |

### Dashboard Overview Metrics

| Field | Current code |
| --- | --- |
| Source | `DashboardView.DeviceStatsSection`, `AppGlassControls.AppOverviewCard` |
| Appears | Dashboard summary metrics; automation overview also uses `AppOverviewCard` |
| Shape and radius | Current dashboard code passes corner radius 20 |
| Fill/material/background | Current dashboard code uses `.systemGlass(tint:nil, interactive:false)`. iOS 26 path uses `.glassEffect(.clear)`; fallback uses `LiquidGlassBackground(.clear)`. |
| Stroke/border | Native or fallback clear glass stroke; optional inner shine controlled by `AppOverviewCard` |
| Shadow/lift | Native/fallback glass |
| Typography | Dashboard value font 26 semibold, label 11 semibold; default `AppOverviewCard` value 28 display semibold and label 12 semibold |
| Contrast notes | Dashboard overrides values to white/secondary white; divider uses white 0.24 in dark and tertiary white in light |
| Interaction states | Static, no loading state |
| Reuse status | Approved |
| Unification notes | Keep `AppOverviewCard` as shared metric row/card recipe. |
| Known concerns | [Device stats light mode reference](./DEVICE_STATS_LIGHT_MODE_REFERENCE.md) appears to describe an older recipe/radius. Current code should be verified against that doc before editing. |

### Mini Device Card

| Field | Current code |
| --- | --- |
| Source | `DashboardView.MiniDeviceCard`, `miniCardBackground` |
| Appears | Dashboard device grid |
| Shape and radius | Square card, aspect 1:1, continuous radius 20 |
| Fill/material/background | iOS 26 `.glassEffect(.clear, in:.rect(cornerRadius:20))`; fallback `LiquidGlassBackground(cornerRadius:20, clarity:.clear)` |
| Stroke/border | Native/fallback clear glass stroke |
| Shadow/lift | Native/fallback clear glass |
| Typography | Dashboard card title 17, body strong 14 medium, micro 11 |
| Contrast notes | Light mode uses white 0.92/0.74; dark mode uses white 0.92/0.74. This intentionally does not use dark text. |
| Interaction states | Offline/on affects product opacity; power button has on/off/loading/disabled; tap opens detail |
| Reuse status | Approved |
| Unification notes | Detailed recipe lives in [Mini device card glass reference](./MINI_DEVICE_CARD_GLASS_REFERENCE.md). |
| Known concerns | Existing detailed doc may contain older AppCardBackground wording; current source uses native/clear glass path. |

### Enhanced Device Card

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/DeviceCardComponents.swift`, `EnhancedDeviceCard` |
| Appears | Device tab list through `DeviceListView` |
| Shape and radius | Full-width card height 193, continuous radius 16 |
| Fill/material/background | `appLiquidGlass(role:.card, cornerRadius:16)` with product image as background element |
| Stroke/border | From card glass role |
| Shadow/lift | From card glass/native fallback |
| Typography | Device name headline semibold, brightness caption semibold, percent caption medium |
| Contrast notes | Card primary white 0.96 and secondary white 0.86; offline opacity 0.58 |
| Interaction states | Power on/off/loading/disabled; brightness drag disabled offline/off/setup; product opacity 1.0 on/online and 0.5 otherwise; setup overlay captures tap |
| Reuse status | Approved |
| Unification notes | Device-list-specific. Do not merge with dashboard mini card without preserving height, image placement, and brightness controls. |
| Known concerns | Has local power and brightness recipes that overlap dashboard/detail controls. |

### Device Card Brightness And Image Controls

| Field | Current code |
| --- | --- |
| Source | `EnhancedDeviceCard.brightnessBar`, `subtleControlGlassBackground`, `imageChangeButton` |
| Appears | Device tab list cards |
| Shape and radius | Brightness bar/control height 28, radius 8 |
| Fill/material/background | Track fill white 0.03 dark or 0.045 light; progress fill gradient from current LED color opacity to full; nested control glass background with `appLiquidGlass(role:.control)` opacity 0.62 dark/0.58 light |
| Stroke/border | Track stroke white 0.06 dark or 0.08 light |
| Shadow/lift | Control glass/native fallback only |
| Typography | Caption medium percentage |
| Contrast notes | Percentage text white 0.94 or 1.0 in increased contrast, regardless of gradient luminance |
| Interaction states | Drag gesture, disabled offline/off/setup, local timer throttling |
| Reuse status | Needs unification |
| Unification notes | Candidate for shared compact brightness bar if detail and dashboard adopt same interaction model. |
| Known concerns | Label contrast over bright gradients should be checked. |

## Device Detail

### Device Detail Shell

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/DeviceDetailView.swift`, `DeviceDetailBackgroundStyle`, `detailContainerBackground` |
| Appears | Expanded device detail overlay from dashboard and device tab |
| Shape and radius | Container clipped to `detailCardCornerRadius`; drag handle capsule 42 x 5 |
| Fill/material/background | `.liquidGlass` uses `appLiquidGlass(role:.highContrast)`. `.frosted` uses `.ultraThinMaterial` 0.62, cyan gradient overlay, blurred white circle highlight, stroke and top sheen. |
| Stroke/border | Frosted style has white 0.20 stroke and white top sheen; high-contrast glass uses app recipe |
| Shadow/lift | From glass/native path; frosted has no explicit large shadow in captured source |
| Typography | Header title title2 bold white, location caption white 0.70 or 0.42 |
| Contrast notes | Detail is largely white-on-glass even in light mode. |
| Interaction states | Drag-to-dismiss, reboot/setup overlays disable content, loading overlays blur/dim |
| Reuse status | Approved |
| Unification notes | Keep separate from ordinary cards because it is a modal shell with morphing. |
| Known concerns | Frosted and liquidGlass backgrounds coexist; verify whether both are still reachable. |

### Device Detail Primary Control Panel

| Field | Current code |
| --- | --- |
| Source | `DeviceDetailView.primaryControlSection`, `saveColorPill`, `activeRunStatusChip`, tab/navigation helpers |
| Appears | Expanded detail color/effect/transition controls |
| Shape and radius | Main section radius 20; save/status chips capsule; advanced picker panel radius 12 |
| Fill/material/background | Main section white 0.10; advanced picker white 0.05; chips white 0.12 |
| Stroke/border | Main section white 0.16; chips white 0.16 to 0.18 |
| Shadow/lift | Mostly none |
| Typography | White text, `AppTypography` title/headline/caption variants |
| Contrast notes | White-on-glass; no theme text in most detail controls |
| Interaction states | Save pill loading/success/disabled, active run chip cancellable/armed, tabs selected/locked via opacity/color only |
| Reuse status | Needs unification |
| Unification notes | Candidate for shared detail panel recipe with `EffectsPane` and `TransitionPane`. |
| Known concerns | Tab selected state has no selected background, only icon/text color. Locked tabs rely on low opacity. |

### Device Detail Automation Shortcut Chips

| Field | Current code |
| --- | --- |
| Source | `DeviceDetailView.ShortcutAutomationChip`, `DashboardAutomationShortcutChip`, `AutomationView.AutomationShortcutChip` |
| Appears | Dashboard shortcut strip, automation screen shortcuts, detail quick automation chips |
| Shape and radius | Rounded rectangle radius 16, compact fixed heights in dashboard |
| Fill/material/background | Dashboard/Automation enabled chips use `appLiquidGlass(role:.card, cornerRadius:16)`; detail chip uses local white-opacity fill for enabled/disabled |
| Stroke/border | Local disabled/detail strokes around white 0.14 to 0.24 |
| Shadow/lift | Glass role for dashboard/automation; local detail version has none |
| Typography | Title caption/subheadline semibold, description caption2 medium, white text |
| Contrast notes | White text throughout |
| Interaction states | Enabled, disabled, next badge, long-press edit in detail, tap run |
| Reuse status | Duplicate candidate |
| Unification notes | Consolidate into one shortcut chip recipe with placement-specific sizing. |
| Known concerns | Same concept renders differently across three surfaces. |

## Automation

### Automation Section Cards

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/AutomationView.swift`, `overviewSection`, `shortcutsSection`, `automationsSection` |
| Appears | Automation landing screen |
| Shape and radius | Section cards radius 24; overview metric radius 20; empty shortcut radius 18 |
| Fill/material/background | `AppCardBackground(AppCardStyles.glass tone:.inactive radius:24)`, overview `AppOverviewCard(.systemGlass)` |
| Stroke/border | App card strokes; count badge capsule stroke card outer 0.5 |
| Shadow/lift | App card shadows |
| Typography | Header largeTitle/subheadline theme text; section title headline semibold |
| Contrast notes | Header uses theme text; many chip/card internals use white text |
| Interaction states | Add/create actions, empty states, disabled create opacity 0.45 |
| Reuse status | Approved |
| Unification notes | Good model for section cards in other top-level screens. |
| Known concerns | Mixed theme text and white text in same screen. |

### Automation Row

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AutomationRow.swift` |
| Appears | Automation list |
| Shape and radius | Main card radius 20; power toggle capsule min 70 x 38; icon buttons circle 32; preview rail radius 5 |
| Fill/material/background | Main card `AppCardBackground` active/inactive by enabled; local chips/buttons white 0.08 to 0.16; loading overlay theme surface opacity 0.58 dark/0.74 light |
| Stroke/border | Local controls white around 0.18 to 0.20; preview rail white 0.10 |
| Shadow/lift | Main card app shadows; local controls mostly no extra shadow |
| Typography | Name headline semibold white; action caption medium white 0.72; subtitle white 0.62 |
| Contrast notes | Hard-coded white card text may need light-mode review. Loading overlay switches to theme text. |
| Interaction states | Enabled/off toggle, active/deleting/loading blur overlay, disabled hit testing, retry buttons, status chips |
| Reuse status | Duplicate candidate |
| Unification notes | Card shell is reusable. Icon buttons/chips overlap preset and detail controls. |
| Known concerns | Device timer status computes colors but neutral chip styling may not expose that color, which can reduce status clarity. |

### Add Automation Sheet Background

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/AddAutomationDialog.swift`, `sheetBackground`, `editorCard`, `stickySaveBar` |
| Appears | Automation create/edit sheet |
| Shape and radius | Sheet editor card radius 24; embedded outer card radius 28; save bar full-width |
| Fill/material/background | Dark linear gradient with orange/blue radial gradients, `LiquidGlassOverlay`, black overlays; editor card black/white gradient plus `.ultraThinMaterial`; embedded uses muted `AppCardBackground` |
| Stroke/border | Editor card gradient stroke white 0.26 to 0.08 |
| Shadow/lift | Editor card black shadow 0.28 dark/0.16 light radius 22 y14 |
| Typography | White text, AppTypography, black text on enabled save buttons |
| Contrast notes | Designed as dark modal chrome even in light mode |
| Interaction states | Save disabled/enabled/loading, validation messages, embedded versus sheet presentation |
| Reuse status | Approved |
| Unification notes | Keep separate from ordinary settings cards due modal complexity. |
| Known concerns | Dense local recipes make visual drift likely. |

### Automation Selected Control Recipes

| Field | Current code |
| --- | --- |
| Source | `AddAutomationDialog.repeatDaySelectedRunBackground`, `weekdayTrackBackground`, `lightActionSelectionBackground` |
| Appears | Repeat day chips, light action segmented control |
| Shape and radius | Repeat selected run radius 11 to 13; track radius 16; light action segment radius 14/18 |
| Fill/material/background | Selected run gradient white 0.78 to 0.46 plus highlight; track white 0.07 and `.ultraThinMaterial`; light selected glass gradient white 0.72 to 0.34 |
| Stroke/border | Selected white stroke around 0.42; track white 0.12 |
| Shadow/lift | Selected shadow black 0.08 radius 8 y4 |
| Typography | Selected black 0.82, unselected white 0.72 |
| Contrast notes | Selected controls intentionally invert to dark text. |
| Interaction states | Default, selected, drag-selected, disabled/locked, validation bubble |
| Reuse status | Approved |
| Unification notes | Detailed recipe lives in [Selected control style recipes](./SELECTED_CONTROL_STYLE_RECIPES.md). |
| Known concerns | Use only for selection controls with similar density and motion, not generic buttons. |

### Automation Trigger And Action Cards

| Field | Current code |
| --- | --- |
| Source | `AddAutomationDialog.triggerSelectionContent`, trigger tab helpers, scene/action selectors |
| Appears | Automation create/edit trigger and action steps |
| Shape and radius | Trigger tabs radius 12; trigger content card radius 16/18; scene rows radius 12; empty message radius 10 |
| Fill/material/background | Active trigger tab white 0.94 plus white gradient; inactive white 0.075 plus overlay; content uses time/solar gradient plus `cardChrome` white 0.09/0.12 |
| Stroke/border | Active gradient stroke 0.65 to 0.32 line 1.5; inactive white 0.12; scene selected white 0.32 |
| Shadow/lift | Active trigger tab black 0.15 radius 6 y3; cardChrome black 0.08 to 0.20 depending presentation |
| Typography | Active tab black, inactive white 0.82, unavailable white 0.42 |
| Contrast notes | Trigger tabs invert selected state; solar/time gradients need visual verification with white labels |
| Interaction states | Active/inactive, unavailable/disabled, selected scene, loading/checking |
| Reuse status | Experimental |
| Unification notes | Could become a shared segmented-card recipe if other flows use large choice cards. |
| Known concerns | Exact presentation differs between sheet and embedded mode. |

### Automation Inline Editors

| Field | Current code |
| --- | --- |
| Source | `AutomationColorEditor`, `AutomationEffectEditor`, `AutomationTransitionEditor` |
| Appears | Automation action configuration |
| Shape and radius | Container radius 18; preset chips radius 12; gradient preview chips radius 4 to 8; power segment radius 9; blend/interpolation radius 8 |
| Fill/material/background | Container white 0.06; selected chips white 0.20, unselected white 0.08; power on white, off white 0.12; blend selected white, unselected white 0.10 |
| Stroke/border | Container white 0.12; power off white 0.20; some previews white 0.25 |
| Shadow/lift | Minimal, mostly none |
| Typography | White and black-on-white selected text, AppTypography caption/subheadline |
| Contrast notes | Dark-modal local recipe; light mode needs verification |
| Interaction states | Selected preset, loading/saving preset, disabled opacity, selected/off power |
| Reuse status | Needs unification |
| Unification notes | Shares many values with detail panes. Candidate for shared editor panel/chip recipes. |
| Known concerns | Several near-identical preset chip implementations exist across automation and detail panes. |

## Settings

### Comprehensive Settings Shell

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/ComprehensiveSettingsView.swift` |
| Appears | Main settings experience |
| Shape and radius | Top-level scroll content over full-screen app background |
| Fill/material/background | `AppBackground()` plus `LiquidGlassOverlay(blurOpacity:.34, highlight:.14, verticalTop:.04, verticalBottom:.06, vignette:.08, centerSheen:.04)`, presentation background `.ultraThinMaterial` |
| Stroke/border | Section/card strokes through child components |
| Shadow/lift | Child components |
| Typography | Header title and section text use `AppTypography` and theme tokens |
| Contrast notes | More theme-aware than device/automation detail flows |
| Interaction states | Loading/reboot/product setup overlays, category selection, disclosure expansion |
| Reuse status | Approved |
| Unification notes | Good reference for settings IA and light-mode-compatible text. |
| Known concerns | Some local toggles still force white foreground. |

### Settings Buttons And Fields

| Field | Current code |
| --- | --- |
| Source | `SettingsButton`, `SettingsInlineButton`, `DangerSettingsButton`, `settingsTextFieldChrome`, `settingsToggleStyle`, `SettingsDisclosureSection` |
| Appears | Comprehensive settings forms and actions |
| Shape and radius | Buttons/fields radius 12; disclosure radius 16; mini steppers radius 10; group buttons circle 30 |
| Fill/material/background | Settings button uses theme surfaceMuted plus `appLiquidGlass(role:.control)`; inline uses active control fill; danger overlays tint 0.10; text fields use theme surfaceMuted |
| Stroke/border | Theme divider/control stroke; danger tint 0.35; warning disclosure can use orange 0.28 |
| Shadow/lift | From glass control role for button-like rows |
| Typography | Subheadline/headline semibold, caption subtitles, theme text |
| Contrast notes | Mostly theme-aware. `settingsToggleStyle` uses white tint/foreground and may be less light-mode-friendly. |
| Interaction states | Default, loading for sync button, destructive, disclosure expanded/collapsed, disabled via caller |
| Reuse status | Approved |
| Unification notes | Could provide shared form-row primitives after control recipes settle. |
| Known concerns | Button rows combine theme fill and glass modifier; verify whether double background is intentional. |

### Settings Status Rows

| Field | Current code |
| --- | --- |
| Source | `SolarTimerStatusRow`, `FirmwareCoverageRow`, `SmartHomeIntegrationStatusRow`, `AlexaDiscoveryInstructionsView`, `TimerSlotEditorCard` |
| Appears | Time schedules, firmware parity/status, smart home, timers |
| Shape and radius | Status row radius 10 or 12; instructions radius 14; timer card radius 12; day chips radius 8 |
| Fill/material/background | Solar row white 0.08; smart home white 0.06; Alexa green 0.12; timer card theme surfaceMuted plus control glass |
| Stroke/border | Smart home status color 0.32; Alexa green 0.35; timer card theme divider |
| Shadow/lift | Timer card gets control glass; most status rows flat |
| Typography | Theme text and AppTypography |
| Contrast notes | Firmware coverage web fallback pill uses white 0.12 with white 0.82; other colored pills may use black text. |
| Interaction states | Sync loading, timer enabled/disabled, day selected/unselected |
| Reuse status | Needs unification |
| Unification notes | Candidate for shared status/instruction row styles. |
| Known concerns | Status colors and contrast should be visually checked in light mode. |

### Legacy WLED Settings Panels

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/WLEDSettingsView.swift`, `Aesdetic-Control/Views/RealTimeSettingsView.swift`, `Aesdetic-Control/Views/WLEDWebConfigView.swift` |
| Appears | WLED compatibility/fallback settings, realtime settings utility, web config |
| Shape and radius | WLED panels radius 12; web toolbar minimal; realtime uses system `List`/`Section` |
| Fill/material/background | WLED sections white 0.08; realtime system list; web view clear/toolbar |
| Stroke/border | WLED sections white 0.15; web icons no container |
| Shadow/lift | None |
| Typography | WLED mostly white; realtime system secondary/blue/green/red; web toolbar SF Symbols |
| Contrast notes | Legacy dark glass assumptions and system-list styling do not match modern settings cards |
| Interaction states | Basic buttons, disabled toolbar opacity 0.4, progress bar tint white |
| Reuse status | Do not reuse |
| Unification notes | Keep only as compatibility/utility surfaces unless modernized. |
| Known concerns | Visual mismatch with `ComprehensiveSettingsView`. |

## Saves, Scenes, Playlists

### Scenes Dashboard Cards

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Scenes/ScenesDashboardView.swift`, `SceneGroupCard`, `EmptyScenesCard`, `SceneUndoBanner`, `SceneDeviceCard`, `SceneEditorSheet` |
| Appears | Saves/Scenes tab |
| Shape and radius | Section cards radius 24; group cards radius 20; undo banner radius 18; device cards need verification in `SceneDeviceCard` |
| Fill/material/background | `AppCardBackground` active/inactive/muted; scene chips use theme surfaceMuted |
| Stroke/border | App card strokes |
| Shadow/lift | App card shadows |
| Typography | AppTypography, mostly theme text with some white text in chips/actions |
| Contrast notes | More theme-aware than preset rows but still mixed |
| Interaction states | Empty/create, undo, play, edit, selected devices in editor |
| Reuse status | Approved |
| Unification notes | Good model for saves section cards. Scene editor specifics need runtime verification. |
| Known concerns | Needs visual pass for `SceneEditorSheet` because it has several local form controls. |

### Preset Glass Rows

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Scenes/PresetsListView.swift`, `PresetGlassCardModifier`, `ColorPresetRow`, `TransitionPresetRow`, `EffectPresetRow`, device record rows |
| Appears | Saves/presets, device presets/effects/playlists |
| Shape and radius | Rows radius 18; Alexa favorite radius 16; preview bars radius 8; action buttons circle 32 |
| Fill/material/background | `AppCardBackground(AppCardStyles.glass tone:.muted)` via `.presetGlassCard`; preview rows use gradients and local white overlays |
| Stroke/border | App card strokes; recent-save highlight green stroke 0.92 line 2 |
| Shadow/lift | App card shadows; recent-save green shadow 0.32 radius 14 y7 |
| Typography | Subheadline semibold white titles, caption white metadata 0.50 to 0.70 |
| Contrast notes | White text is forced on muted glass. Gradient preview labels switch to gray if trailing luminance is high. |
| Interaction states | Tap apply, delete loading, favorite disabled, recent-save highlight, interaction locked |
| Reuse status | Duplicate candidate |
| Unification notes | Row shell is reusable for presets; icon buttons should merge with shared icon button variants. |
| Known concerns | White text on app-card muted fill should be checked in light mode. |

### Save Dialogs And Playlist Editor

| Field | Current code |
| --- | --- |
| Source | `SaveSceneDialog`, `SaveColorPresetDialog`, `SaveEffectPresetDialog`, `SaveTransitionPresetDialog`, `EditPresetNameDialog`, `PlaylistEditorSheet`, `EditPresetNamePopup` |
| Appears | Save flows, edit preset name, playlist editing |
| Shape and radius | Form panels radius 10 to 12; popup radius 18; bottom bar full-width; primary/secondary buttons radius 12 |
| Fill/material/background | Black modal backgrounds, white 0.06/0.10 panels and fields; popup white 0.12 with white 0.20 stroke; playlist editor uses system fields plus bottom `.ultraThinMaterial` |
| Stroke/border | White 0.20 to 0.30 in popup/checkboxes; delete button red 0.15 fill; primary button blue |
| Shadow/lift | Popup black 0.5 radius 30 y15 |
| Typography | Mostly white text; primary button white on system blue, secondary blue on blue 0.20, delete red |
| Contrast notes | Legacy/system blue styling diverges from current glass controls |
| Interaction states | Save disabled/loading, delete destructive, form validation |
| Reuse status | Needs unification |
| Unification notes | Candidate to migrate to automation/settings modal button recipes. |
| Known concerns | Several separate save dialogs repeat panel/button recipes. |

## Device Detail Color, Effect, And Transition Controls

### Unified Color Pane

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/UnifiedColorPane.swift`, `ColorWheelInline`, `GradientBar` |
| Appears | Device detail color tab and automation color editor internals |
| Shape and radius | Blend/interpolation buttons radius 8; color previews vary by helper |
| Fill/material/background | Local white-opacity selectors; selected mode white, unselected white 0.10; sliders use SwiftUI tint |
| Stroke/border | Needs verification in `UnifiedColorPane.savePresetButton`, `ColorWheelInline`, and gradient stop helpers |
| Shadow/lift | Needs verification |
| Typography | White/black selected text, AppTypography |
| Contrast notes | Color surfaces need contrast checks over bright gradients |
| Interaction states | Selected blend/interpolation, dragging gradient stops, saving preset/loading/success |
| Reuse status | Needs unification |
| Unification notes | Should align selector chips with automation inline editors and detail pane chips. |
| Known concerns | Exact visual states need a focused source and screenshot review. |

### Effects Pane

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/EffectsPane.swift` |
| Appears | Device detail effects tab |
| Shape and radius | Main card radius 20; control chips radius 10 to 12; preset chips capsule |
| Fill/material/background | Main card `backgroundFill` white 0.06 or 0.12 increased contrast; selected tiles white 0.12, unselected 0.06; save button white 0.12 or success white 0.92 |
| Stroke/border | Main card white 0.16 or 0.26; save stroke white 0.16 or success green 0.95; preset chip stroke selected white 0.82, unselected 0.28 |
| Shadow/lift | Save success green shadow 0.38 radius 10 y4; selected preset may add local shadow |
| Typography | White text, black on success save state |
| Contrast notes | Success state inverts to black text; normal state white-on-glass |
| Interaction states | Applying, saving, save success, disabled opacity 0.45, selected presets/effects |
| Reuse status | Needs unification |
| Unification notes | Shares card/preset chip values with `TransitionPane`. Promote together if reused. |
| Known concerns | Many local white-opacity controls duplicate automation editor chips. |

### Transition Pane

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/TransitionPane.swift` |
| Appears | Device detail transitions tab |
| Shape and radius | Main card radius 20; selected controls radius 8, 14; preset chips capsule |
| Fill/material/background | Main card `backgroundFill` white 0.06 or 0.12 increased contrast; power capsule white 0.14/0.08; save button white 0.12 or success white 0.92 |
| Stroke/border | Main card white 0.16/0.26; power capsule white 0.14; save stroke white 0.16 or green 0.95 |
| Shadow/lift | Save success green shadow; other lift minimal |
| Typography | White text, black on selected/success controls |
| Contrast notes | Dark detail style; light mode needs verification |
| Interaction states | Expanded/collapsed, active transition, saving, canceling, disabled opacity 0.45, preset selected |
| Reuse status | Needs unification |
| Unification notes | Merge with `EffectsPane` where possible. |
| Known concerns | Transition-specific busy states and cleanup locks are visualized only by disabled opacity/loading text. |

## Wellness

### Wellness Shell And Day Strip

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/WellnessView.swift`, `WellnessTheme`, header/day strip |
| Appears | Wellness tab |
| Shape and radius | Header glass background radius 0; day capsules 34 x 32; calendar button circle 44 |
| Fill/material/background | `AppBackground`; pinned header uses `AppCardBackground(AppCardStyles.glass tone:.inactive radius:0)` opacity 0.92; day selected uses active control fill |
| Stroke/border | Day selected uses control stroke; unselected uses card outer stroke 0.45 |
| Shadow/lift | Header card style; controls use theme shadows when applicable |
| Typography | Large title 38 bold, eyebrow caption semibold uppercase tracking 0.8, day labels caption |
| Contrast notes | Mixes `AppTheme` and `WellnessTheme` text. |
| Interaction states | Selected day/week/month, locked historical entries, calendar sheet |
| Reuse status | Experimental |
| Unification notes | Wellness has a distinct journal/planner language. Do not merge until product direction is clear. |
| Known concerns | Uses custom palette and text names; visual relationship to main app is loose. |

### Wellness Stacked Sections

| Field | Current code |
| --- | --- |
| Source | `WellnessView.stackedSection`, `overviewContent` |
| Appears | Morning setup, identity, priorities, evening, tomorrow, weekly/monthly overview |
| Shape and radius | Continuous radius 22 |
| Fill/material/background | `AppCardBackground(AppCardStyles.glass tone:.active/.inactive radius:22)` despite passing per-section background colors in function signature |
| Stroke/border | App card strokes |
| Shadow/lift | App card shadows |
| Typography | Headline semibold title, footnote subtitle |
| Contrast notes | Uses `appTheme.textPrimary` and `appTheme.textSecondary` in section headers, `WellnessTheme` in content |
| Interaction states | Expanded/collapsed with chevron, animated opacity/move transition |
| Reuse status | Experimental |
| Unification notes | Potentially reusable as an accordion card, but background parameter appears unused in captured source and should be verified. |
| Known concerns | `background` argument to `stackedSection` is accepted but not used in the visible background recipe. |

### Wellness Inputs And Pickers

| Field | Current code |
| --- | --- |
| Source | `RatingDots`, `CheckDot`, `CapsulePicker`, `WellnessTextEditor`, `WellnessLineTextField`, `TaskRow`, `PlanTaskRow`, `DurationMenu` |
| Appears | Wellness check-in forms and planning rows |
| Shape and radius | Rating dots circles 12; check dot circle 16; text editor rectangle; history row radius 14 |
| Fill/material/background | Text editor `WellnessTheme.surface` 0.55; line fields use underline only; check dot selected `WellnessTheme.sectionBlue`, off `WellnessTheme.surface` |
| Stroke/border | Rating/check off stroke `WellnessTheme.textSecondary` 0.35 to 0.40; line fields underline 0.40 |
| Shadow/lift | None |
| Typography | Footnote/caption medium or semibold |
| Contrast notes | Uses wellness palette, not glass tokens |
| Interaction states | Rating drag/tap, selected/unchecked, locked disabled, duration menu arrow fade |
| Reuse status | Experimental |
| Unification notes | Keep local unless wellness becomes a broader form style. |
| Known concerns | Text editor uses rectangular fill with no radius, unlike the rest of the app. |

### Wellness Date And Time Sheets

| Field | Current code |
| --- | --- |
| Source | `WellnessDatePickerSheet`, `WellnessTimePickerSheet`, `WellnessHistoryView`, `HistoryRow` |
| Appears | Wellness modal date/time selection and history |
| Shape and radius | Action button capsule; history row radius 14 |
| Fill/material/background | Sheet background `WellnessTheme.background`; action button `WellnessTheme.surfaceStrong`; history row `WellnessTheme.surface` |
| Stroke/border | None on action/history; rating dots in history use fills |
| Shadow/lift | None |
| Typography | System DatePicker styles with AppTypography for button/history |
| Contrast notes | Custom wellness palette, not main glass |
| Interaction states | Modal close, selected date/time, history loading task |
| Reuse status | Do not reuse |
| Unification notes | Widget/system picker constraints make this intentionally local. |
| Known concerns | Modal sheets visually diverge from app glass sheets. |

## Product Setup

### Product Setup Shell

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/ProductSetupFlowView.swift`, main body, `headerSection`, `footerSection` |
| Appears | Mandatory/optional product setup flow |
| Shape and radius | Main shell high-contrast radius 28; header/footer panel radius 18; product cards radius 16; compact custom card radius 14 |
| Fill/material/background | Main shell `appLiquidGlass(role:.highContrast)`, header/footer `appLiquidGlass(role:.panel)`, product selected highContrast and unselected panel |
| Stroke/border | From glass roles; internal small cards use white-opacity strokes |
| Shadow/lift | From glass roles/native fallback |
| Typography | AppTypography display 22 semibold, subheadline/caption |
| Contrast notes | Uses `AppTheme` text tokens in header and many body controls |
| Interaction states | Step progress, selected product, disabled next/apply, scanning/loading Wi-Fi, setup errors |
| Reuse status | Experimental |
| Unification notes | Good candidate for future onboarding modal patterns, but currently setup-specific. |
| Known concerns | Source includes many local radius 10/12 controls; detailed visual verification needed before promotion. |

### Product Setup Choice Controls

| Field | Current code |
| --- | --- |
| Source | `ProductSetupFlowView.productCard`, `compactCustomCard`, weekday/action helpers |
| Appears | Product selection, LED preferences, first automation setup |
| Shape and radius | Product image radius 14; option/control rows radius 10/12; weekday buttons radius 10 |
| Fill/material/background | Selected product highContrast glass, unselected panel glass; smaller controls use white opacity around 0.10 to 0.20 |
| Stroke/border | White-opacity strokes and glass strokes |
| Shadow/lift | Mostly glass-role lift |
| Typography | AppTypography caption/subheadline |
| Contrast notes | Mixed theme tokens and white text depending section |
| Interaction states | Selected, all-days shortcut, weekday selected/unselected, loading, validation error |
| Reuse status | Experimental |
| Unification notes | Could reuse automation repeat-day recipe for weekday controls if interaction matches. |
| Known concerns | Several local duplicate selection styles around setup automation. |

## Status And Errors

### Error Banner

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control/Views/Components/ErrorBanner.swift`, `ErrorBanner` |
| Appears | Error presentation where imported |
| Shape and radius | Continuous rounded rectangle radius 16; close button circle |
| Fill/material/background | Red base `Color(red:0.73, green:0.16, blue:0.2)` opacity 0.85 or 0.95 increased contrast |
| Stroke/border | None |
| Shadow/lift | Black shadow 0.35 or 0.45 increased contrast, radius 16 y12 |
| Typography | Icon headline, message subheadline medium, close footnote semibold |
| Contrast notes | White foreground throughout; action uses borderedProminent with white-opacity tint |
| Interaction states | Optional action, dismiss, increased contrast, close icon opacity 0.8/1.0 |
| Reuse status | Approved |
| Unification notes | Keep as global error banner; do not use for non-error warnings. |
| Known concerns | Action button uses system bordered prominent rather than glass button. |

### Active Run And Status Chips

| Field | Current code |
| --- | --- |
| Source | `EnhancedDeviceCard.runStatusChip`, `DeviceDetailView.activeRunStatusChip`, `AutomationRow.neutralChip`, settings status rows |
| Appears | Device cards, detail, automation rows, settings status |
| Shape and radius | Mostly capsules; some status rows radius 10/12 |
| Fill/material/background | White opacity 0.10 to 0.16 or colored semantic fills |
| Stroke/border | White 0.14 to 0.20, or semantic status color strokes |
| Shadow/lift | Mostly none |
| Typography | Caption/caption2 medium or semibold |
| Contrast notes | White chips can hide semantic severity; colored rows vary by surface |
| Interaction states | Running/loading/cancellable/armed/disabled/error/success |
| Reuse status | Needs unification |
| Unification notes | Create shared status chip recipes after deciding which statuses need color versus neutral glass. |
| Known concerns | Status semantics are inconsistently visible across surfaces. |

## Widgets

### Device Widgets

| Field | Current code |
| --- | --- |
| Source | `Aesdetic-Control-Widget/DeviceWidgetView.swift`, `DeviceControlWidget.swift` |
| Appears | Home Screen small/medium widgets, accessory circular/rectangular, StandBy |
| Shape and radius | Widget family controls layout; medium power button circle 44 or 56 in StandBy; accessory layouts have no explicit card shell |
| Fill/material/background | `containerBackground(.fill.tertiary, for:.widget)` from widget configuration; internal backgrounds are `Color.clear`; medium power button uses blue/gray 0.10 circle outside StandBy |
| Stroke/border | None |
| Shadow/lift | None |
| Typography | System WidgetKit fonts, StandBy enlarged sizes, rounded monospaced digits for brightness |
| Contrast notes | StandBy luminance-reduced mode uses red 0.9 in dark or white in light; normal widgets use `.primary`, `.secondary`, blue/gray/green/red |
| Interaction states | Device present/empty, online/offline, on/off, StandBy/night mode, interactive medium power button |
| Reuse status | Do not reuse |
| Unification notes | Widget styling follows WidgetKit and StandBy constraints. Keep separate from app glass system. |
| Known concerns | Widgets do not currently reflect the app's glass visual language, likely intentionally due platform constraints. |

## Duplicate Candidates And Unification Queue

| Candidate | Existing recipes | Suggested future review |
| --- | --- | --- |
| Shortcut automation chips | Dashboard `DashboardAutomationShortcutChip`, automation `AutomationShortcutChip`, detail `ShortcutAutomationChip` | Merge into one component with placement size variants. |
| Circular icon buttons | `AppGlassIconButton`, automation neutral icon, preset icon/delete buttons, detail option/power buttons | Add shared size/state variants, then retire local copies. |
| Editor panel cards | Automation inline editors, `EffectsPane`, `TransitionPane`, detail primary section | Create one detail/editor panel recipe or map to `appLiquidGlass(role:.panel)`. |
| Preset chips | Automation color/effect/transition chips, detail color preset chips, effects/transition pane chips | Create one selected/unselected preset chip with preview slots. |
| Save/action buttons | Automation sticky save, save dialogs blue buttons, settings inline buttons, setup footer buttons | Decide whether primary action is white glass, theme control, or system blue. |
| Status chips | Active run chips, automation neutral chips, timer/status rows | Define neutral, success, warning, error, running variants. |
| Legacy settings panels | `WLEDSettingsView`, `RealTimeSettingsView`, `WLEDWebConfigView` | Modernize only if those screens become first-class; otherwise keep marked do-not-reuse. |

## Known Visual Risks

- Light mode still contains many hard-coded white-on-glass surfaces: dashboard, device detail, automation rows, preset rows, and editor panes.
- Several detailed recipe docs are useful but may lag current source, especially the device stats card radius/style and mini-card fallback wording.
- Product setup and wellness are active but stylistically distinct. They should not be used as general design-system source without product review.
- Selection controls intentionally invert to black text on white; applying that recipe to small/bright gradient previews could reduce contrast.
- Many loading/disabled states are implemented as local opacity and `ProgressView` overlays. A future system should normalize these states without changing busy/locked behavior.
