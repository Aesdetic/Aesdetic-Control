# Current App Features

Last updated: 2026-06-04 (Asia/Hong_Kong)

This is the current source-of-truth feature overview for Aesdetic Control. Historical docs in `docs/archive` may be stale.

## Product Model

The app controls WLED-backed devices through native iOS UI while keeping WLED as the on-device execution engine for reliable schedules.

Main runtime components:

- `DeviceControlViewModel`: live device state, light controls, saves, transitions, effect state, and device refresh.
- `WLEDAPIService`: WLED HTTP/file/config/timer/preset-store APIs.
- `AutomationStore`: automation persistence, WLED timer sync, schedule metadata, delete/retry pipeline, and import.
- `DeviceCleanupManager`: persisted cleanup queue for timers, presets, playlists, and combined preset-store deletes.
- `PresetSyncManager`: device preset/playlist reconciliation.
- `ScenesStore`: local scene capture and scene group persistence.
- `PresetsStore`: local save metadata plus Alexa favorite mirror state.
- `WellnessIntegrationService`: HealthKit-backed sleep/wake import for the Wellness tab.

Top-level app areas:

- Dashboard: device overview, shortcuts, scenes, and quick actions.
- Devices: discovery, device list, detail controls, saves, automations, sync, and settings.
- Automation: schedule list, shortcut menu, create/edit/delete flows.
- Wellness: sleep/wake journal, sunrise-lamp tracking, history, and HealthKit wake-time import.

## Discovery And Connectivity

What works:

- mDNS/Bonjour discovery and IP fallback discovery find WLED devices.
- Device state is fetched through WLED JSON APIs.
- WebSocket state updates keep UI responsive when connected.
- Connection failures mark devices offline or unreachable and feed retry paths.
- Device identity and metadata are persisted locally.

Current caveats:

- If iOS Local Network permission is denied or not prompted, discovery can appear broken.
- WLED cannot tell the app instantly when unplugged; the app infers offline from WebSocket, HTTP, mDNS, and health-check failures.

## Dashboard And Device Detail

What works:

- Dashboard shows devices, status summaries, shortcuts, scenes, scene groups, and quick actions.
- Device detail provides native light, saves, automations, and sync tabs.
- Device detail exposes product setup, advanced UI, diagnostics, scenes, preset management, and WLED settings entry points.
- Live light controls remain usable during preset/timer mutation work.
- Mutation controls such as save, delete, rename, and preset-store edits are blocked or queued when conflicting cleanup is active.

Current caveats:

- Scenes and scene groups are app-local records. They can apply WLED state/preset data through app flows, but they are not the same as WLED on-device playlists or timer schedules.

## Light Controls

What works:

- Power on/off.
- Device brightness.
- RGB color.
- CCT/temperature controls.
- Segment-aware model/API support.
- Optimistic UI state plus WLED readback/refresh.
- WebSocket updates are ignored or delayed where needed during active user control to prevent UI jumping.

Current caveats:

- Advanced segment flags exist at model/API level but are not all exposed as daily customer controls.
- RGBW/RGBCCT behavior depends on hardware configuration and WLED color-order setup.

## Gradients, Effects, And Transitions

What works:

- Per-LED gradients are uploaded through the color pipeline.
- Gradient interpolation and transition runner work for app-side live transitions.
- WLED effects can be applied with speed, intensity, palette, and color slots.
- WLED effect names, effect metadata, palette names, and palette preview pages are fetched through native WLED APIs.
- Realtime override is released before effects or transitions when needed.
- Effects and transitions cancel or disable conflicting runtime states.
- Saved transitions are stored as WLED playlist plus managed step presets.
- Saved transition replay starts the stored playlist when valid.

Current caveats:

- Very large gradients can stress device/network throughput.
- App-side live transitions depend on the app process. Saved/on-device playlist execution is the stronger persisted path.

## Saves And Presets

What works:

- Color presets save and apply.
- Effect/animation presets save and apply.
- Transition presets save as playlist plus step presets.
- Playlists can be fetched, saved, applied, edited, copied, and deleted through native advanced UI paths.
- Preset and playlist names are reconciled from device records.
- Save deletes use verified full `presets.json` rewrite cleanup instead of WLED `pdel`.
- Local save rows are removed only after device cleanup verifies the target IDs are gone or no longer queued.

Preset-store safety:

- Create and delete use full `presets.json` rewrite helpers.
- Rewrites strict-parse current records, mutate in memory, preflight, save a local backup, upload, read back, and verify.
- WLED-side backup files are not left on `/edit`; backups are local app files only.
- Preset/playlist validation pauses during active mutation and a short settle window.
- Transient decode failures during mutation/settle are treated as busy/read-unstable before becoming user-facing degraded health.

## Automations And Timers

What works:

- Time-of-day automations.
- Sunrise and sunset automations.
- Automation actions for scenes, presets, playlists, gradients, transitions, effects, and direct WLED state.
- Multi-device targets.
- Local automation persistence in `automations.json`.
- On-device WLED timer sync is the production path.
- WLED timers run without the app open after sync is complete.
- Time-of-day automations use WLED logical slots `0...7`.
- Sunrise uses WLED logical slot `8`.
- Sunset uses WLED logical slot `9`.
- Timer writes go through `/json/cfg`.
- Timer delete is ownership-checked, written, and verified by readback.
- Timer verification retries handle non-final transient mismatch/decode failures.

Current caveats:

- App-side foreground timers are fallback behavior and are not the sold-product reliability path.
- A non-final timer verify error is acceptable only if followed by `timer.rows_delete.success`.
- WLED timer rows can compact, so stored slot numbers are not trusted as permanent ownership IDs.
- Sunrise and sunset each map to one WLED logical solar slot per device, so the app prevents conflicting solar automations on the same device.

## Automation Delete And Cleanup

What works:

- Automation delete clears owned WLED timer rows first.
- Managed playlist and preset assets are removed after timer cleanup.
- Local automation metadata is removed only after device cleanup succeeds.
- Rapid automation delete taps are serialized and queued.
- Pending automation delete IDs persist across force-quit and resume on next launch.
- Offline deletes remain visible and retry instead of disappearing locally.
- Rapid save/preset deletes are coalesced for a short window before the full rewrite.
- Final all-clear logs report clean per-device queue state.

Key success logs:

- `automation.delete.pipeline.summary`
- `timer.rows_delete.success`
- `preset_store.full_rewrite_delete.success`
- `cleanup.preset_store_delete.coalesced`
- `cleanup.device.final_state ... pendingDeletes=0 pendingPresetStore=0 pendingTimers=0 ... health=healthy`

## Settings And WLED Parity

What works natively:

- Core device overview and identity.
- WiFi/setup flows for the product path.
- Product setup flow for supported Aesdetic products and custom WLED devices.
- Light setup, LED configuration, current limits, white/CCT behavior, gamma, and common output behavior.
- Time & Schedules as a top-level settings category, including app automations, solar rows, native WLED timers, and timed light/night-light behavior.
- Advanced network settings such as mDNS, static IP fields, AP fallback fields, WiFi sleep, compatibility, and transmit power.
- Native Alexa setup when the WLED firmware build supports it, including Alexa favorites mirrored into WLED preset slots.
- Home Assistant guidance for Apple Home and Google Home bridging.
- Advanced protocol controls for UDP sync, MQTT, Hue, E1.31, Art-Net, DMX, and related WLED integration settings where firmware supports them.
- Diagnostics, compatibility information, maintenance/safety entry points, backup/reset/update guidance, and WLED web settings fallback.
- Advanced WLED web fallback remains available for firmware-specific settings.
- Security/update/reset/settings areas are partially native and partially web fallback depending on risk.

Current caveats:

- Full WLED settings parity is intentionally split between native customer flows, advanced native controls, and WLED web fallback.
- Product-critical settings should stay native; firmware-specific or risky settings can stay web fallback.
- Some native integration controls depend on WLED compile-time feature support. The UI reports unsupported firmware builds instead of pretending the feature is available.

## Device Sync And Multi-Device Behavior

What works:

- Device sync profiles can propagate selected state from a source device to target devices.
- Manual "copy now" sync can push the current source state to selected targets.
- Light/color/effect/transition changes can propagate through app-side sync payloads.
- Native WLED UDP sync send/receive settings are available for firmware-level sync behavior.
- Preset-store mutations, cleanup queues, and health state are tracked per device.

Current caveats:

- App-side sync requires the app process and reachable devices. WLED UDP sync is the stronger firmware-level path for device-to-device realtime behavior.
- Multi-device automation success depends on each target completing its own timer/preset-store sync.

## Product Setup

What works:

- Guided setup supports known Aesdetic product profiles and custom WLED devices.
- Setup can apply safe LED recommendations, name/WiFi choices, Alexa setup, and a first wake automation.
- Sunrise wake setup can use a solar trigger or a specific time trigger.
- Product profile data exists for sunrise-lamp style devices and safe defaults.

Current caveats:

- Product setup recommendations are only production assumptions for the supported product profiles. Custom WLED hardware still needs installer/user validation.
- Sunrise setup needs location permission or a specific-time fallback.

## Wellness

What works:

- Wellness tab records sleep time, wake time, sleep quality, notes, sunrise-lamp usage, and whether sunrise helped.
- History and simple summary stats are available in the app.
- HealthKit sleep-analysis permission can import the latest wake time when available.

Current caveats:

- Wellness entries are app-side wellness records, not WLED device state.
- HealthKit import depends on user permission and whether iOS has sleep-analysis samples.

## Widgets

What works:

- Widget setup docs exist.
- Widget control paths support quick device actions.

Current caveats:

- Widget freshness depends on shared app data and iOS scheduling.

## Production Definition For This Area

For automations, timers, saves, and preset-store cleanup, production-ready means:

- No repeated `pdel` delete path for app-managed saves or automation assets.
- No local finalization until WLED cleanup is verified or proven unnecessary.
- No raw automation timer slot delete without ownership proof.
- Preset-store validation pauses during mutation and settle windows.
- Rapid deletes are serialized or coalesced.
- Light controls stay usable while mutation controls are guarded.
- Logs clearly show pass, retry, and failure states.
