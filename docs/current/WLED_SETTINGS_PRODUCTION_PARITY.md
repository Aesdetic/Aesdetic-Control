# WLED Settings Production Parity Checklist

Source firmware checked: WLED source archive SHA-256 `449309db0cdc8ea5fa0f6979eb093e688e8d767f67bbe54cb650bc54f4e7ab43` (`wled00` firmware settings pages, `cfg.cpp`, and `set.cpp`)

Status legend:
- Native: available directly in Aesdetic Control with app-side validation.
- Guided: available in a simplified app flow for common customer setup.
- Advanced Native: available in the app, but intentionally placed behind advanced/installer UI.
- Web Fallback: reachable from the app through WLED web settings, but not rebuilt natively.
- Planned Native: should become native before production if this app is the primary customer setup tool.
- Defer: not needed for normal customers unless a product SKU requires it.

## Recommended Customer Flow

1. Overview
   - Device identity, IP, firmware, WiFi status, update check, power/reboot.
   - Keep visible because support and customers need it often.

2. WiFi
   - Join/switch networks and show signal health.
   - Native advanced additions: mDNS name, static IP/gateway/subnet/DNS, AP fallback SSID/password/channel/behavior, AP hiding, WiFi sleep, 802.11g compatibility, and TX power.
   - Planned native additions: multi-network credentials, BSSID pinning, Ethernet type/pins, and stronger reconnect/recovery feedback after IP-changing saves.

3. Light Setup
   - Guided native setup for LED type, GPIO, length, color order, current limits, white/CCT, gamma, FPS, and common output behavior.
   - Hide risky wiring and multi-output items behind Advanced Hardware Setup.

4. Segments, Effects, Scenes
   - Keep daily creative controls native.
   - Advanced segment flags can stay advanced until customers need them.

5. Automations
   - App automations and basic WLED timer slots stay native.
   - Time & Schedules is a top-level settings path with app automations, sunrise/sunset rows, native WLED timers, and timed light/night-light behavior.
   - Full WLED time/date/macro parity remains advanced or web fallback where firmware-specific fields are not rebuilt natively.

6. Network & Sync
   - Basic UDP send/receive native.
   - MQTT, Hue, E1.31, Art-Net, DMX, and realtime receiver settings are advanced native or web fallback depending on firmware support and customer need.

7. Smart Home
   - Alexa setup is native when the WLED firmware build supports it.
   - Alexa Favorites can mirror app saves into WLED preset slots for voice discovery.
   - Home Assistant is the bridge path for Apple Home and Google Home.

8. Extensions
   - Usermods are firmware-specific. Keep global bus pins native and generate safe editable controls from the installed module configuration. Keep WLED fallback for unsupported data shapes and firmware-specific help.

9. Advanced
   - Native OTA lock/update safety controls, backup/restore, reset fallback, filesystem fallback, raw WLED config, and risky hardware settings.

## Current Advanced Implementation Notes

Advanced settings are implemented as an in-device editor, not a detached settings modal. The detailed device view owns the top-level settings chrome, while `WLEDAdvancedSettingsView` owns the category list, category detail surface, draft state, save state, and WLED web fallback links.

Current working pattern:

- The simple settings tabs stay customer-friendly and do not expose every firmware field.
- Advanced uses WLED category names, with LED & Hardware implemented first as the pattern-setting category.
- Category detail opens inside the device settings surface and returns to categories with a horizontal swipe transition.
- The detailed-device header becomes the category action surface:
  - `< Controls` exits settings.
  - `< Settings` returns from a focused Advanced category to the Advanced category list.
  - `Advanced Settings` is passive when there are no category changes.
  - `Save` writes the current category draft.
  - `Restart Required` is an action when WLED needs restart/reboot for hardware changes.
- The app keeps "Open ... on WLED" in the category content area for support, parity comparison, and emergency fallback.
- Text and number fields buffer local typing before committing to the draft so field edits do not rebuild the full detailed view on every keystroke.
- Dynamic LED rows and color order override rows use stable IDs and model-level mutation helpers, not raw array index bindings.

LED & Hardware native coverage currently includes:

- LED setup: global brightness factor, automatic brightness limiter, maximum PSU current, per-output limiter.
- LED outputs: type, pins, length, start, skip, reverse, refresh when off, color order, white-channel swap, auto white, frequency, current limits, output power limit, driver.
- Color order overrides: add, dedupe exact duplicates, delete, and verify.
- Color & White and General Settings fields exposed from the manifest where `/json/cfg` mapping is verified.
- Hardware setup sections for buttons, IR, and relay are present through the manifest/native shell with WLED page fallback for platform-specific risk.

WiFi & Network native parity foundation now includes:

- Firmware-aligned manifest mappings for mDNS, AP SSID/password/channel/behavior, hidden AP, WiFi sleep, 802.11g compatibility, TX power, DNS, Ethernet, ESP-NOW, and linked remotes.
- Category-specific manifest mappings for reused WLED form names such as `AP`, `AC`, `AB`, `DS`, and `SU`, so one page cannot silently inherit another page's config path.
- Category saves route through WLED's `/settings/wifi` form endpoint when WiFi fields change, instead of relying only on `/json/cfg`.
- Station and AP passwords are treated as write-only. Existing configured passwords are preserved with WLED's asterisk placeholder behavior and are never displayed by the app.
- Existing station networks, static IP rows, DNS, Ethernet, AP fallback, ESP-NOW, and linked remote values are included in the form body so a narrow edit does not clear unrelated WiFi settings.
- `Disable WiFi sleep` uses WLED's inverted form semantics: the UI checkbox means sleep disabled, while `wifi.sleep` in config means sleep enabled.
- WiFi saves are treated as reconnect-required flows because mDNS, static IP, channel, sleep, TX power, or credential changes may temporarily make the device unavailable.
- A read-only live parity checker exists at `scripts/wled_live_parity_check.py` for comparing the checked-in manifest against a reachable WLED device without changing any settings.

Usermods native parity foundation now includes:

- Global I2C and SPI GPIO fields are native Advanced controls with WLED wording: `I2C GPIOs (HW)` and `SPI GPIOs (HW)`.
- Pin selectors use the same `unused` display convention as the rest of Advanced while preserving WLED's underlying `-1` value.
- Dynamic Usermod fields are generated from the installed firmware configuration using WLED's native types: booleans, numbers, text, numeric arrays, and one nested section level, which matches WLED's own generic Usermods page.
- AudioReactive receives native labels, control choices, and practical help for microphone type, I2S pins, gain, AGC, dynamics, and UDP sync. Mic type and pin changes are marked restart-required.
- Each Usermods save posts the complete dynamic Usermods draft together with global pins. This prevents a narrow global-pin save from omitting other module values.
- Unsupported data shapes remain read-only with a direct WLED-page fallback rather than exposing an unsafe generic editor.
- `Reboot after save?` is action-only on WLED's form and is intentionally not treated as a persistent `/json/cfg` field.

DMX Output native parity foundation now includes:

- `/settings/dmx` is treated separately from Sync Interfaces because WLED has both DMX input fields on `/settings/sync` and DMX output fixture fields on `/settings/dmx`.
- Native DMX Output exposes stable WLED fields for proxy universe, channels per fixture, start channel, spacing between fixture start channels, and fixture start LED.
- Saves post through WLED's `/settings/dmx` form endpoint, not generic `/json/cfg`, and preserve the dynamic `CH1...CH15` fixture channel map from `dmx.fixmap`.
- DMX Output is firmware-gated. If `/json/cfg` does not expose `dmx`, the app/checker should keep the WLED fallback and avoid assuming output support is compiled in.

## Lessons From LED & Hardware Parity

1. `/json/cfg` is not always enough, even when the value appears in JSON.
   - WLED LED setup has form semantics that matter.
   - `Enable automatic brightness limiter` (`ABL`) and `Maximum PSU Current` (`MA`) both map to `hw.led.maxpwr`.
   - Saving `ABL` through generic JSON caused the toggle to snap back because enabled/disabled is derived from whether `maxpwr > 0`.
   - Fix: route `ABL` and `MA` saves through `/settings/leds` form POST, include the `ABL` checkbox when enabled, and write a positive default current limit when enabling from `maxpwr = 0`.

2. LED output changes can save correctly before physical LEDs visibly change.
   - WLED can persist length/output changes while the live LED bus still needs a restart or full power cycle.
   - Addressable LEDs can retain their last color after WLED stops sending data to higher pixels.
   - Reducing length from `120` to `60` may not immediately turn pixels `61-120` off unless they receive black data first or LED power is cycled.
   - UX implication: continue showing `Restart Required` for LED output changes and explain that power cycling may be needed when stale pixels remain lit.

3. WLED form fallback must preserve unrelated settings.
   - Posting `/settings/leds` requires enough existing LED page fields to avoid clearing unrelated settings.
   - The form body must include LED setup, output rows, color overrides, hardware controls, color/white settings, power-up, transitions, random palettes, timed light, and advanced values where applicable.
   - Adding a form fallback for one field must be tested against unrelated LED settings.

4. Verification should compare WLED's reflected behavior, not only the request body.
   - LED output saves re-fetch and retry because WLED may reflect changes after a short reinit delay.
   - Color override deletion needed a WLED form fallback because the firmware accepted JSON but did not clear `hw.com` immediately in all cases.
   - A save is not complete until the app re-fetches and the category draft reflects the expected state.

5. Advanced UI performance depends on commit boundaries.
   - Binding text fields directly into the whole draft made typing laggy.
   - Fix: local text buffers commit after a short pause, on submit, on focus loss, and on disappear.
   - Parent header chrome/status only republishes when the visible header state actually changes.

6. Header actions should be registered, not driven by request counters.
   - The working pattern is a small header action store owned by `DeviceDetailView`.
   - Advanced category views register current back/save/restart closures into that store.
   - This avoids fragile nested request ID wiring and avoids refreshing the parent on every field edit.

7. Navigation should preserve mental model.
   - Returning from an Advanced category should feel like going back one level, not closing settings.
   - The transition should swipe horizontally between category list and category detail; scale/fade felt like a modal replacement and made the return feel laggy.

## LED & Hardware Acceptance Flow

Run this before expanding the same pattern to another WLED category:

1. Open `Settings > Advanced > LED & Hardware`.
2. Change `Global brightness factor`, save, compare against the WLED LED setup page, then restore the original value.
3. Toggle `Enable automatic brightness limiter` on, save, leave/re-enter, confirm it stays on, and compare with WLED.
4. Toggle `Enable automatic brightness limiter` off, save, leave/re-enter, confirm it stays off, and compare with WLED.
5. If safe for the device, change LED output `Length`, save, confirm `Restart Required`, compare WLED page value, restart from the app, re-enter, and confirm persistence.
6. For length reductions, send black/off to the strip or power-cycle LED power before judging whether upper pixels remain actively controlled.
7. Add a color order override, save, compare WLED, delete it, save, restart if requested, and confirm it does not duplicate or reappear.
8. Use `< Settings` to return to categories and confirm the transition is a horizontal swipe with no visible stall.
9. Type quickly in numeric fields and confirm the editor remains responsive and the top-right action becomes `Save` after the buffered commit.

## WiFi & Network Acceptance Flow

Run this on a device that can be recovered through WLED AP mode or physical access before testing risky network fields:

1. Open `Settings > Advanced > WiFi & Network`.
2. Change only the mDNS address/name, save, confirm the app reports a reconnect-required state, then re-enter and compare the WLED WiFi page.
3. Toggle `Disable WiFi sleep`, save, leave/re-enter, and confirm the toggle persists with the WLED page showing the matching value.
4. Change TX power only if safe for the device, save, leave/re-enter, and compare with WLED.
5. Confirm station WiFi passwords and AP password never display real stored values; they should remain configured/write-only unless intentionally replaced.
6. Avoid changing the real home SSID, password, static IP, gateway, subnet, DNS, or Ethernet fields on a primary device until reconnect/recovery UI is hardened.
7. If the device changes IP or temporarily disappears, wait for rediscovery before judging the save as failed.

## Live Read-Only Parity Check

Use this before and after changing WLED settings mappings:

```bash
python3 scripts/wled_live_parity_check.py \
  --host 192.168.0.6
```

Latest read-only live pass:

- Date: July 10, 2026
- Device: `192.168.0.6`
- Firmware: WLED `16.0.0` / vid `2605030`
- LED count: `120`
- Result: pass, no read-only parity issues found.
- Observed WiFi values: mDNS `aesdetic.test`, AP SSID `WLED-AP`, AP password configured/write-only, AP channel `1`, AP behavior `0`, WiFi sleep disabled, TX power `78`.
- Observed User Interface values: WLED device name `Aesdetic Sunrise Lamp`, simplified UI off.
- Observed Pin Info values are read from WLED's live `/json/pins` endpoint, not `/json/cfg`; the native screen is read-only and keeps `/settings/pins` as comparison fallback.
- Ethernet was absent from this firmware/config and is treated as optional.
- `2D Configuration` is native read-only. It reads strip/matrix mode from `/settings/s.js?p=10`, active dimensions from `/json/info`, and panel layout from `/json/cfg`; saves remain disabled until `/settings/2D` form semantics are implemented and tested on matrix hardware.
- `Sync Interfaces` is cross-checked against WLED 16 screenshots and firmware source. Native layout follows WLED's Broadcast, ESP-NOW, Sync groups, Receive, Send, Instance List, Realtime/DMX, Alexa, MQTT, Hue, and Serial order. Saves use WLED's `/settings/sync` form semantics for bitmask groups, MQTT secret preservation, Hue interval, realtime timeout, DMX input pins, and Serial baud (`BD` -> `hw.baud`).
- `Usermods` found one live module, `AudioReactive`. Global usermod pins were all `unused`/`-1`; the editable native draft reads: disabled, gain `60`, I2S pins `32/15/14/-1`, and AudioReactive sync port `11988`. A write acceptance pass should change and restore gain while the module remains disabled.
- `DMX Output` was not exposed in this device's `/json/cfg`, so it is treated as firmware-gated on this firmware build. Native DMX Output should be verified on a DMX-enabled spare before using write controls in production.

Firmware update workflow check:

```bash
python3 scripts/generate_wled_settings_manifest.py \
  --zip /path/to/WLED-main.zip \
  --output Aesdetic-Control/Resources/WLEDSettingsManifest.json \
  --check
```

Latest result: pass, checked-in manifest matches the WLED source zip.

## Page-by-Page WLED Parity

| WLED page | App grouping | Current status | Production recommendation |
| --- | --- | --- | --- |
| `/settings/wifi` | Overview + WiFi | Native + Advanced Native + Web Fallback | Network join, mDNS, static IP, AP fallback, and WiFi power are native. Keep web fallback for multi-network credentials, BSSID, enterprise WiFi, ESP-NOW, and Ethernet. |
| `/settings/leds` | Light Setup + Advanced LED & Hardware | Guided + Advanced Native + Web Fallback | LED & Hardware is the pattern-setting native Advanced category. Keep WLED fallback for support and platform-specific pin/driver warnings. Continue hardening multi-output, RGBW/RGBCCT, and hardware-control testing before production. |
| `/settings/pins` | Advanced Pin Info | Advanced Read-Only + Web Fallback | Native Pin Info reads `/json/pins`, shows used/available GPIO rows, owner names, state/raw readings where provided, and simple pin notes. No native save controls. |
| `/settings/2D` | 2D Layout + Advanced Hardware Setup | Advanced Read-Only + Web Fallback | Native detection exists, but native saves are disabled until `/settings/2D` form semantics are implemented and tested on matrix hardware. |
| `/settings/ui` | Hidden from native Advanced | Hidden + Web Fallback | Do not expose WLED web UI settings in Aesdetic. The app owns the customer UI, and WLED simplified UI/CSS/background settings only affect WLED's browser UI. Keep manifest coverage for drift checks only. |
| `/settings/sync` | Network & Sync + Integrations | Advanced Native + Web Fallback | Native Sync Interfaces now follows WLED's section order and uses WLED form-save semantics for UDP, sync groups, receive/send, instance list, realtime, DMX input, Alexa, MQTT, Hue, and Serial baud. Keep WLED fallback for firmware-conditional support states, protocol help links, and device-specific recovery. |
| `/settings/dmx` | Advanced DMX Output | Advanced Native + Web Fallback | Native stable fields save through WLED's DMX form endpoint and preserve dynamic channel mapping. Keep WLED fallback for fixture channel map editing and firmware builds without DMX output support. |
| `/settings/time` | Time & Schedules + Automations | Advanced Native + Web Fallback | App automations, sunrise/sunset rows, native WLED timers, and timed light/night light are native. Planned/native-watch items: full timezone/NTP/geolocation/date range/macro parity for every firmware field. |
| `/settings/um` | Extensions | Advanced Native + Dynamic Editable + Web Fallback | Global I2C/SPI pins and safe dynamic module fields are native. Unsupported nested shapes remain read-only with a direct WLED fallback. |
| `/settings/sec` | Advanced | Native + Web Fallback | OTA lock, WiFi settings lock, ArduinoOTA, same-subnet update restriction, backup links, and JSON restore/import are native. Settings PIN, factory reset, and firmware-specific guarded flows remain WLED fallback. |
| `/update` | Overview + Advanced | Planned Native + Web Fallback | Update check is native; manual firmware upload stays WLED fallback until the app can verify board/build compatibility and track reboot recovery. |
| `/reset` | Advanced | Web Fallback | Keep deeply hidden with warnings. Native reset only with a confirmation flow and backup prompt. |

## Native Before Production

- WiFi production setup: reconnect feedback after IP-changing saves, multi-network credentials if needed, Ethernet if hardware ships with it, and clearer failure recovery when a bad static IP is saved.
- Firmware update: current/latest version, compatibility warning, upload progress, reboot wait, recovery instructions.
- Security and backup: add native settings PIN flow only if we can preserve WLED's PIN gate correctly; add safer factory reset confirmation with backup prompt.
- Light setup validation: device capability warnings, GPIO conflict warnings, RGB/RGBW/RGBCCT test workflow, multi-output safety.
- WLED settings audit view: show which sections are Native, Advanced Native, Web Fallback, or Planned Native.

## Next Phase Recommendation

Next phase should focus on production hardening rather than adding another broad category:

1. Reconnect and recovery
   - Make IP-changing WiFi saves, reboot-required saves, and post-restart rediscovery more explicit and less ambiguous.
   - Add clearer states for "saved but reconnecting", "device moved IP", "waiting for reboot", and "manual recovery needed".

2. Risky advanced gating
   - Keep write controls for LED hardware, network, security, usermod pins, and DMX behind warnings that explain likely side effects.
   - Prefer read-only summaries plus WLED fallback for firmware-conditional or module-specific fields.

3. Matrix and DMX hardware validation
   - Test `/settings/2D` writes only on real matrix hardware.
   - Test `/settings/dmx` writes only on a DMX-output-enabled firmware build, especially fixture channel mapping and E1.31 proxy behavior.

4. Firmware update workflow
   - Keep the manifest check in the normal firmware-refresh process.
   - Fail or flag parity work whenever a WLED firmware update adds/removes settings without an explicit native/web/defer decision.

## Acceptable Web Fallback for First Production Build

- WLED UI customization page.
- Usermods with unsupported nested data shapes or product-specific setup instructions not represented by the native editor.
- DMX/E1.31/Art-Net/Hue/MQTT unless those are part of the product promise.
- Full 2D panel editor if the launch product is not a matrix product.
- Buttons, IR, relay, and color-order overrides if installers configure them.
- Home Assistant/Apple Home/Google Home setup beyond guidance and bridge instructions.

## 2D vs 3D Matrix Decision

WLED exposes a native 2D matrix settings page and 2D matrix info in the JSON API. The checked firmware tree does not expose a native 3D matrix configuration page.

For a 3D cube or volumetric product, treat it as a custom product workflow: custom LED map, firmware/usermod support, or an app-specific mapping tool. Do not present 3D as a normal WLED customer setting unless the hardware SKU ships with that exact layout.

## QA Required Before Calling This Production Ready

- Test on RGB, RGBW, and RGBCCT strips.
- Test at least one 2D matrix device if the UI remains visible.
- Test a multi-output controller if multiple outputs are supported in the product.
- Test WiFi switching, bad password, device reboot, and device IP change.
- Test firmware update success, failed upload, and reconnect after reboot once native firmware upload exists.
- Test backup/export and restore/import before reset.
- Test WLED versions expected in the field, not just one firmware build.
