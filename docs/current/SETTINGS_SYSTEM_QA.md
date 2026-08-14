# Settings System QA and Release Gate

This document defines how Aesdetic settings are organized, verified against WLED, and approved for a firmware release.

## Product Information Architecture

The customer layer is task-based:

- **Lamp** for the Sunrise Lamp profile and **Device** for custom or other products: identity, behavior, product profile, status, software update, restart, and support. Behavior exposes power-restore state, a customer-safe brightness cap, and transition presets with verified automatic saves.
- **Time**: phone time sync, location, sunrise/sunset routines, and compact WLED timer/timed-light status. Editing WLED macros remains in Advanced.
- **WiFi**: current connection, signal, network scanning, password entry, and a single shortcut to technical networking.
- **Smart Home**: Alexa and Home Assistant status and setup. MQTT, Hue polling, DMX, realtime protocols, and physical hardware are not edited here.
- **Advanced**: installer, firmware, and troubleshooting controls.

Advanced settings preserve WLED category names inside four user-oriented groups:

1. Lights & Hardware: LED & Hardware, Pin Info, 2D Configuration.
2. Network & Protocols: WiFi & Network, Sync Interfaces, DMX Output when supported.
3. Firmware Features: Time & Macros, Usermods.
4. System & Recovery: Security & Updates.

Advanced category pages use expandable sections. The first section opens initially, multiple sections can remain open, modified/error badges remain visible while collapsed, and validation reopens the affected section. Leaving a dirty category requires Save Changes, Discard Changes, or Continue Editing.

WLED's User Interface category remains hidden because it changes WLED's browser appearance, not the Aesdetic app. Device Name is the exception and is edited from the customer Device/Lamp page.

## Placement and Risk Policy

`SettingsExperiencePolicy.swift` is the checked-in product policy above the firmware manifest. Every manifest field resolves to:

- simple, advanced, hidden, or WLED web fallback;
- a customer destination when it belongs in the simple layer;
- safe, reconnect, restart, hardware, or lockout risk;
- a customer-facing category summary, section explanation, and improved label where WLED wording is unclear.

Tests fail when a firmware category is not assigned to exactly one Advanced group, when the expected field count drifts, or when a field cannot resolve a placement and risk decision.

## Automated Gate

Run the app build and focused settings tests:

```bash
xcodebuild \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  build

xcodebuild \
  -project Aesdetic-Control.xcodeproj \
  -scheme Aesdetic-Control \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  test \
  -only-testing:Aesdetic-ControlTests/SettingsExperiencePolicyTests \
  -only-testing:Aesdetic-ControlTests/WLEDAdvancedSettingsServiceTests
```

The service suite verifies changed-field-only writes, category-specific form endpoints, secret preservation, inverted booleans, delayed LED verification, stable dynamic-row identity, category-specific decoding, and preservation of custom firmware values outside the customer control ranges.

`SettingsPolishUITests.testRapidSettingsNavigationRemainsResponsive` uses a built-in offline UI-test device to perform a deterministic, read-only five-pass cycle through every customer tab and representative Advanced categories. It does not depend on discovery or saved user data and never presses Save.

## Firmware Drift Gate

Regenerate and compare the manifest whenever the supported WLED source changes:

```bash
python3 scripts/generate_wled_settings_manifest.py \
  --zip /path/to/WLED-main.zip \
  --output Aesdetic-Control/Resources/WLEDSettingsManifest.json \
  --check
```

Any category or field-count change requires an explicit product placement decision, updated mappings where needed, service tests, and a live parity pass before release.

Also confirm that every non-secret, non-upload field in an editable native category has either a WLED config path or an explicit local-only/form-control decision. This guards against controls that render in the app but are never included in WLED's save request. The Sync serial baud rate (`BD` -> `hw.baud`) is covered by this rule and its service test.

## Read-Only Live Check

This command never changes the device. It checks live configuration, Pin Info, matrix state, firmware-gated fields, and runtime capabilities. The optional snapshot is redacted before it is written.

```bash
python3 scripts/wled_live_parity_check.py \
  --host 192.168.0.6 \
  --snapshot /tmp/aesdetic-wled-settings-snapshot.json
```

Capability decisions must come from live JSON fields, not hidden warning text in WLED HTML. The report includes ESP-NOW, DMX input, DMX output, tunable CCT output, white-channel, and matrix support.

## Supervised Device Acceptance

Do not automate destructive or connectivity-changing writes on a primary device. Before testing, create WLED configuration and preset backups and confirm physical access or AP recovery is available.

For each supported category:

1. Record the original value in the app and WLED.
2. Change one harmless field.
3. Save and wait for app verification.
4. Reopen the category and compare the WLED page.
5. Restore the original value and verify it again.
6. For restart-required changes, restart from the app and confirm the waiting state ends after rediscovery.

Risky tests remain manual:

- WiFi credentials, static IP, gateway, subnet, DNS, Ethernet, TX power, and AP behavior.
- LED GPIO, output type, length, current limit, multi-output layout, relay, IR, and buttons.
- Settings PIN, OTA lock, WiFi lock, firmware upload, restore, and reset.
- Usermod bus pins, matrix writes, DMX input/output pins, and fixture mapping.

For a Usermods acceptance test, prefer a non-hardware field while the extension is disabled. On the current AudioReactive build, change `Gain` from `60` to `61`, save, compare it with WLED's `/settings/um` page, then restore `60`. Do not start by changing microphone type or I2S pins: those require a restart and can interrupt connected audio hardware.

## Required Hardware Coverage

Release confidence requires evidence from:

- Aesdetic Sunrise Lamp RGBW hardware.
- A custom RGB-only device.
- A true tunable-CCT or RGBCCT device.
- A multi-output controller if the product supports it.
- Matrix, DMX, Ethernet, and usermod-enabled builds only when those features are part of the supported product promise.
- The current supported WLED firmware and the previous supported release.

## UX Acceptance

- Rapidly switch all simple tabs and Advanced categories without a stall or stale category appearing.
- Type quickly in text and number fields without full-page lag.
- Add and remove every dynamic row type without duplication or an index crash.
- Confirm simple settings contain no JSON paths, manifest keys, native-save labels, protocol editors, or firmware-only browser appearance settings.
- Confirm unsupported categories are absent rather than presented with a misleading warning.
- Verify light and dark appearance, largest Dynamic Type sizes, VoiceOver labels, save/discard behavior, restart recovery, and reconnect messaging.
