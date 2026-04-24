# Automation Delete Status

Last updated: 2026-04-24 (Asia/Hong_Kong)

## Scope
This document tracks what is currently working and not working for **automation delete** (timer + playlist + step presets) in Aesdetic Control.

## Current Delete Flow (as implemented)

1. User taps delete.
2. Delete can be blocked for a short safety window after creation/device prep.
3. Timer cleanup runs first (direct).
4. Playlist and preset cleanup runs WLED-style via `pdel`, queued and one ID at a time.
5. Queue order is timer -> playlist -> preset.
6. After queue drain, app performs readback verification and retries leftovers once.
7. If leftovers still remain, delete fails with explicit `presetStoreDeleteIncomplete`.

Code anchors:
- Delete lock windows: `Aesdetic-Control/Services/AutomationStore.swift:61`, `:62`, `:227`
- Queue WLED-style marker: `Aesdetic-Control/Services/AutomationStore.swift:4519`
- Post-delete readback + leftover retry: `Aesdetic-Control/Services/AutomationStore.swift:4548`, `:4590`, `:4639`
- Manual mimic mode on: `Aesdetic-Control/Services/WLEDAPIService.swift:122`
- Manual pre/post readability gates currently off: `Aesdetic-Control/Services/WLEDAPIService.swift:123`, `:125`
- One command retry on transient pdel failure log (`manual_pdel_retrying`): `Aesdetic-Control/Services/WLEDAPIService.swift:2012`
- Queue pacing/chunking: `Aesdetic-Control/Services/DeviceCleanupManager.swift:17`, `:27`, `:946`, `:955`

## What Is Working

Based on latest run:
- `/Users/ryan/Desktop/Run-Aesdetic-Control-2026.04.23_23-14-36-+0800.xcresult`

Confirmed in logs:
- First taps were blocked by safety lock (`automation.delete.blocked_device_settle`) then delete started normally.
- Timer delete succeeded (`timer.delete.cleared`).
- Playlist delete succeeded (`playlist.delete.manual_pdel_accepted ... attempt=1`).
- Preset deletes succeeded sequentially (`preset.delete.manual_pdel_accepted` for IDs 2..8, all attempt=1).
- Queue drained to zero (`cleanup.queue_drain_pass ... afterEntries=0`).
- Pipeline reached summary and automation removed (`automation.delete.pipeline.summary`, `Deleted automation ...`).

In this run there were:
- No HTTP 503 delete failure.
- No queue retry/defer loop.
- No leftover/readback failure (`leftovers_pass1`, `postcheck_failed`, `presetStoreDeleteIncomplete` not present).

## What Is Not Fully Solved / Open Risks

1. WLED firmware-side preset store fragility is still possible under heavy writes.
- App-side flow is safer, but cannot guarantee "never corrupt presets.json" because firmware writes full preset store file on each mutation.

2. User perception issue: "first delete did nothing" can still happen by design.
- If within the 60s lock window, delete is blocked (`automation.delete.blocked_device_settle`).

3. Large transition automations can still hit device limits.
- WLED can return FS-related errors in state (for example prior observed `error 11` / quota scenarios).

4. `error:12` can appear in state during delete even when delete succeeds.
- Meaning in WLED: preset load attempted on missing preset (`ERR_FS_PLOAD`).
- This is usually transient status reporting, not necessarily a delete failure.

## WLED Error Mapping (relevant)

From firmware source (`/Users/ryan/Downloads/WLED-main 2/wled00/const.h`):
- `11` = `ERR_FS_QUOTA` (filesystem full / max file size reached)
- `12` = `ERR_FS_PLOAD` (attempted to load preset that does not exist)

`json.cpp` emits `error` once in state and then clears it (`errorFlag = ERR_NONE`).

## Pass/Fail Log Checklist

Success signals:
- `automation.delete.pipeline.begin`
- `playlist.delete.manual_pdel_accepted`
- `preset.delete.manual_pdel_accepted` for each target ID
- `cleanup.queue_drain_pass ... afterEntries=0`
- `automation.delete.pipeline.summary`
- `Deleted automation:`

Failure signals:
- `manual_pdel_failed`
- `cleanup.queue_retry_scheduled`
- `automation.delete.pipeline.postcheck_failed`
- `presetStoreDeleteIncomplete`
- repeated defer loops without ID reduction

## Current Overall Status

- **10-minute-class delete flow:** currently good in latest verified run.
- **Automation delete architecture:** now much closer to deterministic WLED-style behavior.
- **Hard guarantee against any firmware-side preset file corruption:** not possible from app side alone.
