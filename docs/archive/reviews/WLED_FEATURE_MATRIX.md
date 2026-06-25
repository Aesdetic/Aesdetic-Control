# WLED Feature Matrix (Repo-Grounded)

Legend: Supported | Partial | Missing | Risk

## 1) Discovery + Connectivity
- Bonjour/mDNS discovery: Supported (WLEDDiscoveryService)
- IP scan fallback: Supported (WLEDDiscoveryService)
- Connection health + retry: Supported (WLEDConnectionMonitor)
- WebSocket realtime updates: Supported (WLEDWebSocketManager)
- Network permission prompts: Partial (LocalNetworkPrompter referenced but commented in App)

Gaps / Risks
- If Local Network permission isn’t prompted, discovery can fail silently. Risk

## 2) Core Device State (Power/Brightness/Color)
- Power on/off: Supported (DeviceControlViewModel, WLEDAPIService)
- Brightness: Supported (DeviceControlViewModel, WLEDAPIService)
- RGB color: Supported (DeviceControlViewModel, WLEDAPIModels)
- CCT (temperature): Supported with CCT-only updates (DeviceControlViewModel, WLEDAPIModels)
- White channel (RGBW): Partial (conversion helpers exist; UI support unclear)

Gaps / Risks
- RGBW vs RGB behavior may vary by hardware. Potential mismatch if UI doesn’t expose white channel controls. Risk

## 3) Segments + Advanced Segment Controls
- Segment updates (start/stop/len, effects, palette, etc): Supported at model/API level (SegmentUpdate)
- Segment selection, per-segment color/effects: Partial (limited UI exposure)
- Advanced segment flags (rev/mi/cln/frz/etc): Partial (model exists; UI unclear)

Gaps / Risks
- Missing UI for critical segment controls may lead to incomplete parity with WLED. Missing

## 4) Effects + Palettes
- Effect selection (fx), speed/intensity, palette: Supported (DeviceControlViewModel + WLEDAPIModels)
- Effect metadata parsing: Supported (DeviceControlViewModel)
- Audio-reactive handling: Partial (warns if mode not enabled)

Gaps / Risks
- Audio-reactive enablement may require WLED-side config not surfaced in app. Partial

## 5) Gradients + Transitions
- Per-LED gradients: Supported (ColorEngine, WLEDAPIService chunking)
- Gradient interpolation modes: Supported (Models + UI)
- Transition presets (A→B using playlists): Supported (WLEDAPIService)
- Native transitions (tt/transition): Supported

Gaps / Risks
- Large gradient uploads may stress device or network. Risk
- Long transition behavior can diverge between direct-state and playlist execution paths on unstable networks. Partial
- WLED playlist step timing starts before preset apply completes; app now uses generated playlist boundary compensation (`transition < dur`) to reduce seam color snaps while preserving runtime. Supported (WLED-compatible app behavior)

## 6) Presets + Playlists
- Save/delete/apply presets: Supported (WLEDAPIService)
- Save/apply playlists: Supported (WLEDAPIService, uses preset ID flow)
- Device playlist list/run/stop/edit/copy/delete UI: Supported in Advanced mode (PresetsListView)
- Full playlist editor UI (create/edit steps, durations, transitions, repeat/shuffle/end/manual advance/test/stop): Supported in Advanced mode
- Playlist save validation (100-step cap, ranges, shape normalization): Supported (WLEDAPIService)
- Playlist parser compatibility for top-level + nested preset payload shapes: Supported (WLEDAPIService)
- Preset save flags (ib/sb/sc/ql): Supported for color/effect presets in advanced UI
- Boot preset + custom API-command presets: Partial (supported in advanced save dialogs for color/effect; transition presets still generated from state)
- Device-side rename sync for presets/playlists: Supported with retry queue + delayed reconciliation
- Playlist discoverability in non-advanced mode: Supported (explicit advanced-mode entry card)
- Device-record preset/playlist name snapshots: Supported (`WLEDDevice` + ViewModel maps)

Gaps / Risks
- Advanced playlist tooling remains intentionally gated behind `advancedUIEnabled` (per product direction).
- WLED firmware does not auto-clean app-generated temporary presets/playlists; app cleanup remains an app-layer responsibility.
- Transition preset creation flow still does not expose full preset-save option parity (boot/API-command) in one place.
- Rename sync still depends on device availability; queued retries improve reliability but not guaranteed immediacy.
- Playlist/preset tests now cover validation + parser shape handling, but broader persistence/UI regression coverage is still limited.

Comparison (Native iOS WLED + WLED)
- Native iOS WLED app: primarily opens device web UI in a `WKWebView` (`wled/View/DeviceView.swift`, `wled/View/WebView.swift`), so preset/playlist management comes from WLED web UI.
- WLED web/firmware: supports full preset + playlist editing (step add/remove, per-step duration/transition, repeat, shuffle, end preset/restore, quick-load, boot preset, custom API preset).
- Aesdetic Control: now has native advanced playlist editing/operations parity for core flows, while keeping non-advanced UI intentionally simplified.

## 7) Timers / Schedules (WLED-side)
- Timer fetch/update/disable: Supported (WLEDAPIService)
- Native timer editor UI: Partial (`ComprehensiveSettingsView` deep-links to `/settings/time`, but no native CRUD timer list/editor)
- Slot model (0-9): Supported at API level (`WLEDTimer`, `WLEDTimerUpdate`)

Gaps / Risks
- Weekday bitmask mapping now aligns to WLED Monday-first `dow` semantics. Supported
- Specific-time automations are now constrained to slots 0-7; solar remains pinned to 8/9. Supported
- Timer updates now explicitly clear stale date-range (`start`/`end`) constraints when absent. Supported
- Slot conflict visibility is now validated pre-save in Add Automation flow; other scheduling entry points may still need the same preflight UX. Partial

## 8) Automations (App-side)
- Time/sunrise/sunset triggers: Supported (AutomationStore + Models)
- Multi-device targets: Supported
- Automation persistence (automations.json): Supported
- On-device execution path: Supported and default (`runOnDevice = true` in creation/migration)
- Local app timer scheduler: Partial fallback path exists, but currently bypassed for on-device automations

Gaps / Risks
- On-device sync failure handling now clears stale timer-slot metadata and falls back to local execution when no active device timer is confirmed. Supported
- `TimeTrigger.timezoneIdentifier` is now applied when writing on-device timer hour/minute, including weekday day-shift handling. Supported
- Solar UI offset range now matches WLED on-device limits (+/-59). Supported
- Solar weekday selection is now represented in `SolarTrigger` and synced to on-device timer `dow`. Supported
- "Follow device" solar location currently resolves from phone location provider, not device geolocation config. Partial

## 9) Live Mode + Realtime Override
- Live override release (lor): Supported in model/API
- UI controls for live mode: Partial

Gaps / Risks
- Live override can block effects if not released properly. Risk

## 10) Nightlight
- Nightlight payload (nl): Supported in model/API
- UI for nightlight: Missing

Gaps / Risks
- Nightlight exists but not user-accessible. Missing

## 11) UDP Sync
- UDP sync send/recv: Supported (DeviceControlViewModel + WLEDStateUpdate)
- Sync group orchestration UI: Partial

Gaps / Risks
- Limited UI may make multi-device sync confusing. Partial

## 12) Device Configuration (WLED JSON cfg)
- Fetch/update config endpoints: Partial (some cfg handling in timers; full config coverage not present)
- UI for config settings: Partial (WLEDSettingsView exists but coverage unclear)

Gaps / Risks
- Missing config surface limits parity and can cause user confusion. Missing

## 13) Widget
- Home Screen + StandBy widget: Supported (Aesdetic-Control-Widget)
- Widget actions (power/brightness): Supported

Gaps / Risks
- Widget data updates rely on shared file; no background refresh strategy. Risk

## 14) Testing
- WLED API request tests: Supported
- Coverage for new WLED config/timer/playlists UI: Missing

Gaps / Risks
- High change surface without tests increases regression risk. Risk

## 15) Automation Time + Scheduling Alignment (Aesdetic vs Native iOS WLED vs WLED)
- WLED firmware: supports 8 standard timer slots plus sunrise/sunset timer behavior, weekday masks, date ranges, and timer macros/presets (`cfg.cpp`, `ntp.cpp`).
- Native iOS WLED app: primarily wraps device web UI (`WKWebView`), so scheduling behavior follows WLED web/firmware directly.
- Aesdetic Control: strong automation abstraction and on-device sync pipeline, but has several semantic mismatches with WLED timer internals.

High-confidence alignment checks
- Sunrise/sunset on-device slot targeting (8/9): implemented.
- Timer CRUD via `/json/cfg` (`timers.ins`): implemented.
- Preset/playlist targets as timer macros: implemented.

Priority gaps to fix (automation time/scheduling)
1. Add test coverage for weekday mask mapping, slot allocation constraints, solar offset clamping, and timer range clearing.
2. Extend slot-conflict preflight UX to all automation creation/edit entry points (not only Add Automation dialog).
3. Consider device-geolocation-based solar scheduling for true "follow device" semantics.

---

# High-Risk Gaps (Impacting Correctness or Reliability)
- Local Network permission prompt appears to be commented out.
- WLED timers have no native editor UI (only deep-links to WLED web settings), and playlists lack full editor parity (only list/run/delete in advanced mode).
- Advanced segment controls are model-only and may create inconsistent state if not exposed.
- Nightlight exists in API but has no UI or workflow.

# Active Focus (Per Your Request)
1. Discovery + connectivity reliability (start here)
2. WLED timers + playlists UI
3. Background-safe scheduling (BGTaskScheduler or on-device timers)
4. Config surface coverage (critical WLED settings + capability-driven UI)

# Step-by-Step Implementation Plan
## Phase 0: Capability Baseline (done)
- Capability matrix and gaps (this file).

## Phase 1: Discovery + Connectivity Reliability (active)
- Fix local network permission prompting and user feedback.
- Harden discovery fallbacks and error handling.
- Add diagnostics for connection state and failures.

## Phase 2: On-Device Scheduling (Timers + Playlists)
- Expose WLED timers UI (CRUD).
- Expose playlist management UI.
- Add sync to AutomationStore if desired.

## Phase 3: Background-Safe Automation
- Add BGTaskScheduler support.
- Add missed-automation catch-up logic on foreground.
- Prefer on-device timers where possible.

## Phase 4: Config + Advanced Controls
- Expand config models + endpoints.
- Add capability-gated UI for advanced segment controls, nightlight, live override.

## Phase 5: Tests + Docs
- Add tests for new endpoints and parsing.
- Add README for setup/run + capability coverage.

# Scoped Checklist (Active)
## Discovery + Connectivity
- [ ] Confirm Local Network prompt is triggered on first launch (uncomment and verify LocalNetworkPrompter usage in `Aesdetic_ControlApp.swift`).
- [ ] Add UI feedback when permission is denied or pending (surface a banner/action).
- [ ] Add a manual “Re-scan” action that clears the banlist and restarts discovery.
- [ ] Verify Bonjour browse and IP scan concurrency doesn’t block UI or overrun retries.
- [ ] Add a “last seen” and “last error” diagnostic per device for easier debugging.
- [ ] Add a minimal connectivity diagnostics view (device IP, port, last WS ping time).
- [ ] Add tests for discovery parsing and state transitions (online/offline, reconnect).

### Discovery + Connectivity: Gaps That Can Break Functionality
- Local network permission not prompted (discovery fails silently).
- If WS reconnect is paused in background, device state may appear stale on return.
