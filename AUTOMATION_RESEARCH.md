# Automation Feature Research

## WLED Capabilities

- **Presets & Playlists** – Any state (colors, effects, brightness, transition time, segments) can be stored as a preset and recalled instantly or stitched together as a playlist. Timers in WLED simply recall a preset/playlist at a scheduled time ([WLED repo](https://github.com/wled/WLED)).  
- **Timers/Macros** – Eight simple timers can run at fixed times or sunrise/sunset offsets (requires NTP). Each timer triggers a preset number or macro index. Granularity is limited (no per-day skipping, no multi-device sync).  
- **UDP Sync** – WLED controllers can mirror each other via UDP notifications. Helpful when one controller should broadcast the automation result, but it still needs a “master” to start the sequence.  
- **API hooks** – JSON/HTTP API can update presets and timers, so the iOS app can either push a preset once (fire-and-forget) or continually orchestrate complex gradients on-device.

## App-Orchestrated vs Controller-Managed Automations

| Approach | Advantages | Limitations |
| --- | --- | --- |
| **Controller-managed (push to WLED timer)** | Runs even if phone is offline; zero iOS background work after upload; perfectly aligned with WLED’s NTP clock. | Only 8 timers; each fires a single preset; no dynamic gradients or multi-device coordination; no awareness of user overrides unless controller notifies the app. |
| **App-orchestrated (current AutomationStore)** | Unlimited automations; advanced actions (smooth gradient uploads, real-time transitions); multi-device sync and conflict handling; easy logging & UX (skip, snooze). | Requires iOS background execution and notifications; depends on device connectivity at runtime. |

**Recommendation:** Keep the app-managed scheduler for its flexibility and ability to drive complex transitions. For simple “apply preset at time X” use cases we can later add an opt-in knob that pushes the schedule into WLED, but that requires a preset-based payload and timer slot management.

## Apple Platform Guidelines

- **SwiftUI Patterns** – Use data-driven `@State`/`@ObservedObject` bindings, segmented controls, and `.sheet` presentation for the builder to keep the flow consistent with existing color/preset editors ([SwiftUI docs](https://developer.apple.com/documentation/SwiftUI)).  
- **Human Interface Guidelines** – Automations should reuse the established visual language: rounded rectangles, 8/12/16 spacing grid, and clear affordances (“Run”, “Edit”, “Disable”). Typography and motion should match our device cards for familiarity ([HIG](https://developer.apple.com/design/human-interface-guidelines)).  
- **Permissions & Privacy** – Sunrise/sunset mode requires Location/WeatherKit. Explain the benefit before requesting access, provide fallbacks, and surface status in-line so the user knows when solar automations fall back to manual times.

## Key UX Decisions

1. **Device-detail first** – Automations must be creatable from the device screen where the user already tweaks gradients. The builder is pre-populated with the device’s current state to minimize taps.  
2. **Templates** – Provide sunrise/sunset/focus/bedtime templates that prefill trigger + action, yet open the full editor so the user can rename or fine-tune brightness before saving.  
3. **Dashboard consistency** – Dashboard shortcut chips use the same chip/glass style as device cards. Tapping a chip either runs the automation immediately or opens the editor depending on context, mirroring Apple Home’s scene buttons.  
4. **Multi-device awareness** – Every automation explicitly lists how many devices it targets and lets the user allow/deny partial execution so failures are predictable.  
5. **Logging & retries** – AutomationStore already tracks `lastTriggered`. We’ll expand log messages surfaced via the dashboard so users can retry when a device was offline.  

These findings guide the implementation below: default to app-side scheduling for rich behaviors, keep the UI aligned with Apple’s recommendations, and expose templates plus multi-device cues for a frictionless experience.


