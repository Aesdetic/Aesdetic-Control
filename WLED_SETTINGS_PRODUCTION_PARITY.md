# WLED Settings Production Parity Checklist

Source firmware checked: `/Users/ryan/Downloads/WLED-main 2/wled00`

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
   - Full WLED time/macros page remains advanced until time/date/macro parity is completed.

6. Network & Sync
   - Basic UDP send/receive native.
   - DMX, E1.31, Art-Net, DDP, MQTT, Hue, and realtime receiver settings remain advanced/web fallback.

7. Extensions
   - Usermods are firmware-specific. Keep web fallback unless a shipped product depends on one.

8. Advanced
   - Native OTA lock/update safety controls, backup/restore, reset fallback, filesystem fallback, raw WLED config, and risky hardware settings.

## Page-by-Page WLED Parity

| WLED page | App grouping | Current status | Production recommendation |
| --- | --- | --- | --- |
| `/settings/wifi` | Overview + WiFi | Native + Advanced Native + Web Fallback | Network join, mDNS, static IP, AP fallback, and WiFi power are native. Keep web fallback for multi-network credentials, BSSID, enterprise WiFi, ESP-NOW, and Ethernet. |
| `/settings/leds` | Light Setup | Guided + Advanced Native + Web Fallback | Core single-output setup is native. Add native multi-output editor before production if products can ship with multiple outputs. Keep buttons/IR/relay advanced. |
| `/settings/2D` | 2D Layout + Advanced Hardware Setup | Web Fallback | Native detection exists. Add native matrix/panel editor only if product line includes matrix devices. |
| `/settings/ui` | Controls | Web Fallback | Defer most WLED UI theme/server-page settings. App UI owns the customer experience. |
| `/settings/sync` | Network & Sync | Advanced Native + Web Fallback | Keep UDP native. Add only the protocols your customers actually use: DDP/E1.31/DMX/MQTT/Hue. |
| `/settings/time` | Automations | Advanced Native + Web Fallback | Basic timers/macros/night light are native. Planned native: timezone/NTP/geolocation/date range/macro parity. |
| `/settings/um` | Extensions | Web Fallback | Keep dynamic web fallback. Native only for product-required usermods. |
| `/settings/sec` | Advanced | Native + Web Fallback | OTA lock, WiFi settings lock, ArduinoOTA, same-subnet update restriction, backup links, and JSON restore/import are native. Settings PIN, factory reset, and firmware-specific guarded flows remain WLED fallback. |
| `/update` | Overview + Advanced | Planned Native + Web Fallback | Update check is native; manual firmware upload stays WLED fallback until the app can verify board/build compatibility and track reboot recovery. |
| `/reset` | Advanced | Web Fallback | Keep deeply hidden with warnings. Native reset only with a confirmation flow and backup prompt. |

## Native Before Production

- WiFi production setup: reconnect feedback after IP-changing saves, multi-network credentials if needed, Ethernet if hardware ships with it, and clearer failure recovery when a bad static IP is saved.
- Firmware update: current/latest version, compatibility warning, upload progress, reboot wait, recovery instructions.
- Security and backup: add native settings PIN flow only if we can preserve WLED's PIN gate correctly; add safer factory reset confirmation with backup prompt.
- Firmware update: board/build compatibility detection, upload progress, reboot recovery, and support guidance after failed update.
- Light setup validation: device capability warnings, GPIO conflict warnings, RGB/RGBW/RGBCCT test workflow, multi-output safety.
- WLED settings audit view: show which sections are Native, Advanced Native, Web Fallback, or Planned Native.

## Acceptable Web Fallback for First Production Build

- WLED UI customization page.
- Usermods not tied to a shipped product.
- DMX/E1.31/Art-Net/Hue/MQTT unless those are part of the product promise.
- Full 2D panel editor if the launch product is not a matrix product.
- Buttons, IR, relay, and color-order overrides if installers configure them.

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
