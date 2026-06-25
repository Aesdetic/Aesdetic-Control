# Current Code Anchors

Last updated: 2026-06-04 (Asia/Hong_Kong)

This file ties the current feature docs to the repo. It is not a full code walkthrough; it is the anchor map used to verify that the documented features and caveats are real in the current checkout.

## App Shell

- `Aesdetic-Control/ContentView.swift`: top-level tabs for Dashboard, Devices, Automation, and Wellness.
- `Aesdetic-Control/Aesdetic_ControlApp.swift`: shared stores, local-network prompt, widget listeners, and app lifecycle hooks.
- `Aesdetic-Control/Services/LocalNetworkPrompter.swift`: iOS Local Network permission trigger.

Confirmed caveat:

- Discovery can appear broken when Local Network permission is denied or never prompted.

## Device Discovery And Live Control

- `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`: discovery start, device state, live controls, color/effect/transition handling, sync propagation, and preset-store health.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: WLED `/json`, `/json/cfg`, `/json/effects`, `/json/fxdata`, `/json/palettes`, `/json/palx`, preset-store rewrite, timer, playlist, Alexa, and sync APIs.
- `Aesdetic-Control/Services/WLEDWebSocketManager.swift`: realtime state updates.
- `Aesdetic-Control/Services/WLEDConnectionMonitor.swift`: health checks and automation import on reconnect.

Confirmed caveats:

- WLED does not directly push a reliable "unplugged" event to the app, so offline state is inferred.
- RGBW/RGBCCT output depends on WLED hardware configuration and color order.
- Advanced segment fields exist in models/API paths, but not every advanced flag is a normal customer control.

## Dashboard, Scenes, And Shortcuts

- `Aesdetic-Control/Views/DashboardView.swift`: dashboard device cards, shortcuts, scene-group shortcut handling, and mutation locks.
- `Aesdetic-Control/Views/Scenes/ScenesListView.swift`: scene list UI.
- `Aesdetic-Control/Scenes/ScenesStore.swift`: local scene persistence.
- `Aesdetic-Control/Models/Scene.swift`: scene state model.
- `Aesdetic-Control/Models/SceneGroup.swift`: grouped scene model.

Confirmed caveat:

- Scenes and scene groups are app-local records. They are not WLED timers or WLED playlist schedules unless another flow writes a corresponding WLED asset.

## Saves, Presets, Playlists, And Alexa Favorites

- `Aesdetic-Control/Views/Scenes/PresetsListView.swift`: color/effect/transition saves, advanced playlist UI, Alexa Favorites, and delete locks.
- `Aesdetic-Control/Scenes/PresetsStore.swift`: local save metadata and Alexa favorite mirror state.
- `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`: save/delete/apply flows for color presets, effect presets, transition presets, playlists, and Alexa mirror sync.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: full `presets.json` rewrite helpers, playlist parsing/upsert/apply/delete, and Alexa mirror rewrite.
- `Aesdetic-Control/Services/DeviceCleanupManager.swift`: preset-store cleanup queue, coalescing, wait-for-cleanup, and final-state logs.

Confirmed caveats:

- The app must strict-parse the current preset store before full rewrite. If `presets.json` is unreadable before the operation, cleanup must stop rather than guess.
- Preset-store decode failures during active mutation/settle can be transient, so the app defers readable-degrade health before surfacing recovery-required health.
- Large preset stores and very full WLED filesystems can still fail write operations.

## Effects, Gradients, And Transitions

- `Aesdetic-Control/Views/Components/EffectsPane.swift`: effect/animation UI, save controls, and mutation locks.
- `Aesdetic-Control/Views/Components/TransitionPane.swift`: transition editor, saved transition controls, realtime/app-side transition behavior, and mutation locks.
- `Aesdetic-Control/Views/Components/UnifiedColorPane.swift`: color/gradient controls and save locks.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: effect names, effect metadata, palette names, palette previews, effect state, per-LED chunking, and realtime release behavior.
- `Aesdetic-Control/Services/TemporaryTransitionCleanupService.swift`: temporary transition cleanup.

Confirmed caveats:

- App-side live transitions depend on the app process.
- Saved transition replay is stronger because it uses WLED playlist execution.
- Large gradients can stress device/network throughput.

## Automations And Timers

- `Aesdetic-Control/Models/Automation.swift`: triggers for specific time, sunrise, and sunset; actions for scene, preset, playlist, gradient, transition, effect, and direct state.
- `Aesdetic-Control/Models/AutomationTemplates.swift`: sunrise, sunset, focus, bedtime, and action templates.
- `Aesdetic-Control/Views/AutomationView.swift`: automation list, shortcut menu, mutation locks, and delete UI.
- `Aesdetic-Control/Views/Components/AddAutomationDialog.swift`: create/edit UI and validation for trigger/action types.
- `Aesdetic-Control/Services/AutomationStore.swift`: local persistence, create/update/delete, on-device sync, timer slot selection, timer ownership, import, retry, and delete finalization.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: WLED timer fetch/update/disable and `/json/cfg` schedule writes.

Confirmed caveats:

- WLED-side timers are the production scheduling path. App-side foreground timers are fallback behavior.
- WLED timer rows can compact, so raw stored slot IDs are not trusted as permanent ownership proof.
- Time-of-day automations use logical slots `0...7`; sunrise uses slot `8`; sunset uses slot `9`.
- Sunrise and sunset each have one logical solar slot per device, so conflicting solar automations are blocked.

## Automation Delete And Cleanup

- `Aesdetic-Control/Services/AutomationStore.swift`: delete request queue, pending delete persistence, ownership-checked timer cleanup, preset-store cleanup, offline retry, and local finalization.
- `Aesdetic-Control/Services/DeviceCleanupManager.swift`: per-device queue, delete leases, coalesced preset-store deletes, dead letters, wait-for-completion, and `cleanup.device.final_state`.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: timer delete verification retries and verified full preset-store delete rewrites.
- `Aesdetic-Control/Views/Components/SaveColorPresetDialog.swift`, `SaveEffectPresetDialog.swift`, `SaveTransitionPresetDialog.swift`: create controls blocked during conflicting delete work.

Confirmed caveats:

- If the app is killed mid-upload, the in-flight HTTP request cannot be guaranteed to finish. Persisted delete intent and cleanup queue state resume on next launch.
- A non-final timer verify mismatch/error is acceptable only when followed by `timer.rows_delete.success`.
- Light controls remain usable during cleanup, while save/delete/rename/preset mutation controls are blocked or queued.

## Device Sync

- `Aesdetic-Control/ViewModels/DeviceControlViewModel.swift`: `copyNowFromSource`, `propagateIfNeeded`, sync profiles, target toggles, dispatch summaries, and WLED UDP sync writes.
- `Aesdetic-Control/Models/ColorsSyncPayload.swift`: sync payload types for gradient, effect state, effect parameters, transition start, and effect disable.
- `Aesdetic-Control/Views/DeviceDetailView.swift`: Sync tab, advanced sync UI, Copy Now, and WLED UDP send/receive toggles.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: `setUDPSync` and UDP sync config.

Confirmed caveat:

- App-side sync requires the app process and reachable devices. WLED UDP sync is the firmware-level realtime sync path.

## Product Setup And Settings

- `Aesdetic-Control/Views/Components/ProductSetupFlowView.swift`: product selection, LED recommendations, name/WiFi, Alexa setup, and first wake automation.
- `Aesdetic-Control/Services/DeviceProfileCatalog.swift`: product profile defaults for supported device types.
- `Aesdetic-Control/Views/Components/ComprehensiveSettingsView.swift`: Time & Schedules, WiFi, LED setup, advanced network, integrations, protocols, diagnostics, maintenance, and WLED web fallback.
- `Aesdetic-Control/Views/WLEDWebConfigView.swift`: WLED web fallback.
- `Aesdetic-Control/Views/RealTimeSettingsView.swift`: realtime settings surface.
- `Aesdetic-Control/Views/Components/DiagnosticsView.swift`: diagnostics surface.
- `Aesdetic-Control/Views/Components/WiFiSetupView.swift`: product WiFi setup.

Confirmed caveats:

- Full WLED settings parity is intentionally split between native customer flows, advanced native controls, and WLED web fallback.
- Some integration controls depend on WLED compile-time support.
- Product setup recommendations are valid for supported product profiles; custom WLED hardware still needs validation.
- Sunrise setup needs location permission or a specific-time fallback.

## Smart Home

- `Aesdetic-Control/Models/SmartHomeIntegrationModels.swift`: smart-home integration status model.
- `Aesdetic-Control/Services/SmartHomeIntegrationStore.swift`: integration status messages.
- `Aesdetic-Control/Models/AlexaIntegrationModels.swift`: Alexa favorite mirror models.
- `Aesdetic-Control/Services/WLEDAPIService.swift`: native WLED Alexa settings and Alexa preset mirror rewrite.
- `Aesdetic-Control/Views/Components/ComprehensiveSettingsView.swift`: Alexa setup, Home Assistant guidance, MQTT, Hue, E1.31, Art-Net, DMX, and sync integration controls.
- `Aesdetic-Control/Views/Components/ProductSetupFlowView.swift`: setup-time Alexa flow.
- `Aesdetic-Control/Views/Scenes/PresetsListView.swift`: add/remove saves as Alexa favorites.

Confirmed caveats:

- Alexa is native only on WLED firmware builds that include Alexa support.
- Home Assistant is a bridge/guidance path, not a direct app-managed Home Assistant integration.
- Apple Home and Google Home require a Home Assistant/Homebridge-style bridge.

## Wellness

- `Aesdetic-Control/Views/WellnessView.swift`: Wellness tab, entry editing, stats, history, and HealthKit wake import UI.
- `Aesdetic-Control/Services/WellnessIntegrationService.swift`: HealthKit authorization and latest wake-time fetch.
- `Aesdetic-Control/Models/WellnessEntry.swift`: wellness entry snapshots and summaries.
- `Aesdetic-Control/Models/CoreDataEntities.swift`: Core Data persistence for wellness entries.

Confirmed caveats:

- Wellness entries are app-side records, not WLED device state.
- HealthKit import depends on permission and available sleep-analysis samples.

## Widgets

- `docs/reference/widgets/WIDGET_SETUP.md`: widget setup reference.
- `docs/reference/widgets/WIDGET_TROUBLESHOOTING.md`: widget troubleshooting reference.
- `docs/reference/widgets/QUICK_WIDGET_FIX.md`: historical widget fix note.

Confirmed caveat:

- Widget freshness depends on shared app data and iOS widget scheduling.
