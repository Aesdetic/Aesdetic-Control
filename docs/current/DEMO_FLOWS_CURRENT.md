# Demo Flows

Last updated: 2026-06-04 (Asia/Hong_Kong)

These flows demonstrate the current app behavior without relying on historical implementation notes.

## Demo 1: Basic Device Control

Goal: show that daily light controls work independently of preset/timer mutation work.

1. Open a device detail page.
2. Toggle power.
3. Change brightness.
4. Change color or temperature.
5. Start a preset/automation delete in another tab.
6. Return to Light and confirm power/brightness/color controls remain usable.

Expected result:

- Light responds normally.
- Save/delete/rename/preset mutation controls may be locked or queued while cleanup is active.

## Demo 2: Color Save Create And Delete

Goal: show verified save cleanup.

1. Create a color save.
2. Confirm it appears in Saves.
3. Inspect `presets.json` and confirm the preset ID exists.
4. Delete the color save.
5. Confirm local row stays until device cleanup succeeds.
6. Inspect `presets.json` and confirm the preset ID is gone.

Expected logs:

- `preset_store.full_rewrite_create.success`
- `cleanup.preset_store_delete.enqueued`
- `preset_store.full_rewrite_delete.success`
- `cleanup.device.final_state`

## Demo 3: Transition Save Replay And Delete

Goal: show managed playlist plus step preset behavior.

1. Create a transition save.
2. Confirm WLED `presets.json` has one playlist and managed step presets.
3. Replay the transition save.
4. Delete the transition save.
5. Confirm playlist and step preset IDs are gone from `presets.json`.

Expected result:

- Replay uses the stored playlist when valid.
- Delete removes generated app-managed assets together.

## Demo 4: Automation Create

Goal: show WLED-backed on-device scheduling.

1. Create a time-of-day automation.
2. Wait for ready state.
3. Confirm WLED timer row exists in `/json/cfg`.
4. Confirm the timer points to the generated preset or playlist target.
5. Close the app and let WLED run the schedule.

Expected result:

- WLED runs the timer without the app open after sync completes.
- The automation row reports ready or updated/verified status.

## Demo 5: Automation Delete

Goal: show safe timer-first cleanup.

1. Delete a ready automation.
2. Watch the row show delete progress.
3. Confirm timer cleanup succeeds first.
4. Confirm preset-store cleanup succeeds second.
5. Confirm local automation row disappears after cleanup.

Expected logs:

- `automation.delete.pipeline.begin`
- `timer.rows_delete.success`
- `preset_store.full_rewrite_delete.success`
- `automation.delete.pipeline.summary`
- `cleanup.device.final_state`

## Demo 6: Rapid Delete Stress

Goal: show serialization and coalescing under fast user actions.

1. Create several automations and saves.
2. Rapid-delete multiple automations.
3. Rapid-delete multiple saves.
4. Navigate to another app view while deletes continue.
5. Return and confirm all intended items are removed.

Expected result:

- Automation deletes serialize/queue.
- Save deletes coalesce into fewer preset-store rewrites.
- `presets.json` remains valid.
- WLED timers return to clean state.

Expected logs:

- `automation.delete.queued`
- `cleanup.preset_store_delete.coalesced`
- `timer.rows_delete.success`
- `preset_store.full_rewrite_delete.success`
- `cleanup.device.final_state ... health=healthy`

## Demo 7: Offline Or Force-Quit Resilience

Goal: show local metadata is not removed too early.

1. Create an automation and wait for ready state.
2. Start delete.
3. Force-quit the app or make the device temporarily unreachable.
4. Reopen the app and restore device connectivity.
5. Confirm delete resumes or verifies clean state.

Expected result:

- Pending delete intent survives relaunch.
- Local automation metadata is removed only after cleanup is complete or proven unnecessary.

## Demo 8: Advanced Playlist Editing

Goal: show WLED playlist support is native in advanced paths.

1. Enable advanced UI.
2. Open playlist management.
3. Create or edit playlist steps, durations, transitions, repeat/shuffle/end behavior.
4. Save playlist.
5. Apply playlist.
6. Delete playlist.

Expected result:

- Playlist records are read from WLED preset-store data.
- Save/delete uses verified preset-store paths.
- Apply uses WLED playlist state target.

## Demo 9: Dashboard Scenes And Shortcuts

Goal: show app-level scenes and shortcut surfaces.

1. Open Dashboard.
2. Confirm device cards and shortcut sections reflect current devices.
3. Create or apply a scene/scene group from the scene surfaces.
4. Apply a preset or automation shortcut.
5. Confirm the target device state changes and Dashboard remains in sync.

Expected result:

- Scenes and scene groups are available as app-local quick actions.
- Preset and automation shortcuts use the same underlying device/automation paths as the detail views.

## Demo 10: Device Sync

Goal: show source-to-target sync behavior and native WLED UDP sync controls.

1. Open a device detail page.
2. Go to Sync.
3. Enable target devices for app-side propagation.
4. Use Copy Now from the source device.
5. Change light/effect state and confirm reachable targets update.
6. Enable or disable WLED UDP send/receive in advanced sync settings.

Expected result:

- App-side sync pushes supported state to reachable target devices.
- WLED UDP sync settings write to the device for firmware-level sync behavior.

## Demo 11: Product Setup And Smart Home

Goal: show setup flow, first automation, and integration behavior.

1. Open product setup from device detail/settings.
2. Select a supported product profile or custom WLED device.
3. Review LED recommendations and name/WiFi fields.
4. Enable Alexa if the firmware build supports it.
5. Create the first wake automation using sunrise or specific time.

Expected result:

- Product setup applies guided configuration for supported profiles.
- Alexa setup gives discovery instructions when saved.
- The wake automation uses the normal automation/timer sync path.

## Demo 12: Wellness

Goal: show Wellness is app-side journal/history, with optional HealthKit wake-time import.

1. Open Wellness.
2. Add sleep time, wake time, sleep quality, notes, and sunrise-lamp usage.
3. Allow HealthKit sleep access if prompted.
4. Import latest wake time when available.
5. Open history and confirm summary values update.

Expected result:

- Wellness entries persist locally.
- HealthKit import fills wake time only when permission and sleep samples are available.
