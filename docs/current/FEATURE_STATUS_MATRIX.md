# Feature Status Matrix

Last updated: 2026-06-04 (Asia/Hong_Kong)

Status meanings:

- Production: current behavior is working and has current verification coverage.
- Supported: implemented and usable, but may need broader device/UI testing.
- Partial: implemented only for some paths, advanced UI, or fallback behavior.
- Historical: archived documentation only; do not treat as current source of truth.

| Area | Status | Current behavior |
| --- | --- | --- |
| Device discovery | Supported | mDNS and IP fallback discovery, connection health, WebSocket updates. |
| Dashboard | Supported | Device cards, shortcuts, scene groups, preset shortcuts, and status summaries. |
| Scenes | Supported | App-local scenes and scene groups can be saved and applied through app flows. |
| Power | Supported | Native WLED state writes with local UI update. |
| Brightness | Supported | Device-level brightness writes and UI sync. |
| RGB color | Supported | Native color writes and gradient pipeline integration. |
| CCT/temperature | Supported | Native CCT writes, with hardware/config caveats. |
| Segments | Partial | Model/API support exists; not every advanced segment flag is surfaced. |
| Effects | Supported | Effect names, effect metadata, effect ID, speed, intensity, palette/color slots, conflict handling. |
| Palettes | Supported | Palette names and palette preview pages are fetched through native WLED APIs. |
| Gradients | Supported | Per-LED upload and interpolation; large uploads can stress devices. |
| App-side transitions | Supported | Smooth live transition runner; depends on app process. |
| Saved transitions | Production | Stored as WLED playlist plus managed step presets; replay uses playlist path. |
| Color saves | Production | Full rewrite save/delete and verified cleanup. |
| Effect/animation saves | Production | Full rewrite save/delete and verified cleanup. |
| Playlists | Supported | Fetch, save, apply, edit/copy/delete through native advanced paths. |
| Alexa favorites | Supported | Color, transition, and effect saves can be mirrored into WLED Alexa preset slots when supported. |
| Preset-store full rewrite | Production | Create/delete preflight, local backup, upload, readback, verify. |
| Automation create | Production | Local metadata plus WLED preset-store asset creation plus WLED timer sync. |
| Automation actions | Production | Scene, preset, playlist, gradient, transition, effect, and direct-state actions are modeled and executed. |
| Time-of-day timers | Production | Uses WLED logical slots `0...7`, verifies after write/delete. |
| Sunrise/sunset timers | Production | Sunrise slot `8`, sunset slot `9`, WLED-compatible offset limits. |
| Automation delete | Production | Owned timer first, then managed preset-store assets, then local finalization. |
| Rapid automation delete | Production | Serialized and queued. |
| Rapid save delete | Production | Coalesced into combined preset-store cleanup before rewrite. |
| Offline automation delete | Production | Delete remains pending/retrying and resumes after app relaunch. |
| App-side foreground scheduling | Partial | Exists as fallback; WLED-side timer path is the reliable production path. |
| Device sync | Supported | App-side source-to-target propagation plus manual copy-now; WLED UDP sync settings are native. |
| WLED settings parity | Partial | Native for product-critical paths, web fallback for advanced firmware-specific settings. |
| Product setup | Supported | Guided product profile setup, LED recommendations, name/WiFi, Alexa, and first wake automation. |
| Smart-home setup | Partial | Alexa is native when firmware supports it; Home Assistant is guidance; MQTT/Hue/E1.31/Art-Net/DMX are advanced/native or web fallback by firmware. |
| Wellness | Supported | Sleep/wake journal, sunrise-lamp tracking, history, and HealthKit wake-time import. |
| Diagnostics | Supported | Native diagnostics/settings surfaces exist for support and compatibility checks. |
| Widgets | Supported | Quick actions and setup docs exist; refresh depends on iOS/shared data. |
| Advanced WLED web fallback | Supported | WLED web config remains reachable for settings not rebuilt natively. |

## Current Non-Blocking Watch Items

- Very full WLED filesystems can still fail writes.
- If `presets.json` is unreadable before our operation, full rewrite must abort rather than guess.
- Large automations should be tested near WLED preset-slot limits.
- RGBW/RGBCCT behavior must be tested against the target hardware SKU.
- Local Network permission failure needs clear user recovery.
- App-local scenes, Wellness entries, and app-side sync are not firmware-persistent WLED schedules; use WLED timers/playlists for on-device execution.
