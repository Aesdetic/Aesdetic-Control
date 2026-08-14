#!/usr/bin/env python3
"""Read-only live WLED parity checks for Aesdetic advanced settings."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen


DEFAULT_CATEGORIES = [
    "wifi-network",
    "led-hardware",
    "pin-info",
    "2d-configuration",
    "dmx-output",
    "sync-interfaces",
    "time-macros",
    "usermods",
    "security-updates",
]


def fetch_json(host: str, path: str, timeout: float) -> dict[str, Any]:
    url = f"http://{host}{path}"
    with urlopen(url, timeout=timeout) as response:
        status = getattr(response, "status", 200)
        if status < 200 or status > 299:
            raise RuntimeError(f"{url} returned HTTP {status}")
        return json.loads(response.read().decode("utf-8"))


def fetch_text(host: str, path: str, timeout: float) -> str:
    url = f"http://{host}{path}"
    with urlopen(url, timeout=timeout) as response:
        status = getattr(response, "status", 200)
        if status < 200 or status > 299:
            raise RuntimeError(f"{url} returned HTTP {status}")
        return response.read().decode("utf-8")


def resolved_cfg(raw: dict[str, Any]) -> dict[str, Any]:
    cfg = raw.get("cfg")
    return cfg if isinstance(cfg, dict) else raw


def parse_path(path: str) -> list[str | int]:
    parts: list[str | int] = []
    for piece in path.split("."):
        match = re.fullmatch(r"([^\[]+)(?:\[(\d+)\])?", piece)
        if not match:
            parts.append(piece)
            continue
        parts.append(match.group(1))
        if match.group(2) is not None:
            parts.append(int(match.group(2)))
    return parts


def resolve(path: str | None, root: Any) -> Any:
    if not path or "*" in path:
        return None
    cursor = root
    for part in parse_path(path):
        if isinstance(part, int):
            if not isinstance(cursor, list) or part >= len(cursor):
                return None
            cursor = cursor[part]
        else:
            if not isinstance(cursor, dict) or part not in cursor:
                return None
            cursor = cursor[part]
    return cursor


def secret_configured(field: dict[str, Any], cfg: dict[str, Any]) -> bool:
    path = field.get("configPath")
    if not path:
        return False
    length_path = path.replace(".psk", ".pskl").replace(".pwd", ".pskl")
    value = resolve(length_path, cfg)
    return isinstance(value, (int, float)) and value > 0


def summarize_value(field: dict[str, Any], cfg: dict[str, Any]) -> str:
    if field.get("secret"):
        return "configured" if secret_configured(field, cfg) else "not configured"
    value = resolve(field.get("configPath"), cfg)
    if value is None:
        return "missing"
    if isinstance(value, bool):
        return "on" if value else "off"
    if isinstance(value, (dict, list)):
        encoded = json.dumps(value, separators=(",", ":"))
        return encoded if len(encoded) <= 80 else encoded[:77] + "..."
    return str(value)


def category_by_id(manifest: dict[str, Any], category_id: str) -> dict[str, Any] | None:
    return next((category for category in manifest.get("categories", []) if category.get("id") == category_id), None)


def category_report(category: dict[str, Any], cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    lines: list[str] = []
    issues: list[str] = []
    fields = category.get("fields", [])
    mapped = [field for field in fields if field.get("configPath")]
    writable = [
        field for field in mapped
        if not field.get("localOnly")
        and not field.get("fileUpload")
        and not field.get("secret")
        and "*" not in str(field.get("configPath", ""))
    ]

    lines.append(f"### {category.get('title', category.get('id'))}")
    lines.append(f"- WLED page: `{category.get('webPath', '')}`")
    lines.append(f"- Manifest fields: {len(fields)} total, {len(mapped)} mapped, {len(writable)} generic-writable")

    if category.get("requiresFeature") == "WLED_ENABLE_DMX" and not isinstance(cfg.get("dmx"), dict):
        lines.append("  - Firmware-gated category: this device did not expose `dmx` in `/json/cfg`.")
        lines.append("  - Native UI should keep WLED fallback and avoid assuming DMX Output support.")
        return lines, issues

    if category.get("id") == "2d-configuration":
        lines.append("  - Native read-only check uses `/settings/s.js?p=10`, `/json/info`, and `/json/cfg` panel layout.")
        return lines, issues

    for field in mapped:
        if category.get("id") == "usermods" and field.get("key") == "RBT":
            lines.append("  - `RBT` Reboot after save: action-only form field, not persisted in `/json/cfg`")
            continue
        path = field.get("configPath")
        value = summarize_value(field, cfg)
        missing = value == "missing"
        optional_2d = category.get("id") == "2d-configuration" and path and path.startswith("hw.led.matrix")
        optional_firmware_field = path in {"eth.type"} or "*" in str(path)
        if missing and not optional_2d and not optional_firmware_field:
            issues.append(f"{category.get('title')}: `{field.get('key')}` expected `{path}` but it was missing")
        lines.append(f"  - `{field.get('key')}` {field.get('label')}: `{path}` = {value}")

    if not mapped:
        lines.append("  - No config-mapped fields. Use WLED web fallback or a category-specific endpoint.")
    return lines, issues


def usermods_report(cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    usermods = cfg.get("um")
    if not isinstance(usermods, dict) or not usermods:
        return [
            "  - `/json/cfg.um`: no dynamic usermod config exposed.",
            "  - Native page should still allow Global I2C/SPI pins and keep WLED fallback.",
        ], []

    lines = [f"  - `/json/cfg.um`: {len(usermods)} module(s) exposed."]
    for name in sorted(usermods)[:12]:
        value = usermods.get(name)
        if isinstance(value, dict):
            lines.append(f"  - {name}: {len(value)} top-level value(s)")
        else:
            lines.append(f"  - {name}: {summarize_dynamic_value(value)}")
    if len(usermods) > 12:
        lines.append(f"  - ... {len(usermods) - 12} additional usermod modules")
    return lines, []


def dmx_output_report(cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    dmx = cfg.get("dmx")
    if not isinstance(dmx, dict):
        return [], []
    fixmap = dmx.get("fixmap")
    lines = [
        f"  - DMX fixture map entries: `{len(fixmap) if isinstance(fixmap, list) else 0}`",
        "  - Native saves preserve `fixmap` as CH1...CH15 while stable DMX output fields are edited.",
    ]
    return lines, []


def summarize_dynamic_value(value: Any) -> str:
    if isinstance(value, bool):
        return "on" if value else "off"
    if isinstance(value, (int, float, str)):
        return str(value)
    if isinstance(value, list):
        return f"{len(value)} item(s)"
    if value is None:
        return "not set"
    return type(value).__name__


def parse_js_int_array(script: str, name: str) -> set[int]:
    match = re.search(rf"d\.{re.escape(name)}\s*=\s*\[([^\]]*)\]", script)
    if not match:
        return set()
    return {int(value.strip()) for value in match.group(1).split(",") if value.strip().lstrip("-").isdigit()}


def pin_notes(pin: dict[str, Any], caps: dict[str, set[int]]) -> str:
    gpio = pin.get("p")
    raw_caps = int(pin.get("c") or 0)
    notes: list[str] = []
    if gpio in caps.get("touch", set()):
        notes.append("Touch")
    if gpio in caps.get("ro_gpio", set()):
        notes.append("Input Only")
    if gpio in caps.get("adc", set()) or raw_caps & 0x02:
        notes.append("Analog")
    if raw_caps & 0x08:
        notes.append("Flash Boot")
    if raw_caps & 0x10:
        notes.append("Bootstrap")
    return ", ".join(notes) if notes else "-"


def pin_info_report(pins: dict[str, Any] | None, pin_caps_script: str | None) -> tuple[list[str], list[str]]:
    lines: list[str] = []
    issues: list[str] = []
    rows = pins.get("pins") if isinstance(pins, dict) else None
    if not isinstance(rows, list):
        return ["  - `/json/pins` did not return a pins array."], ["Pin Info: `/json/pins` missing pins array"]

    caps = {
        "touch": parse_js_int_array(pin_caps_script or "", "touch"),
        "ro_gpio": parse_js_int_array(pin_caps_script or "", "ro_gpio"),
        "adc": parse_js_int_array(pin_caps_script or "", "adc"),
    }
    used = [pin for pin in rows if isinstance(pin, dict) and bool(pin.get("a"))]
    available = [pin for pin in rows if isinstance(pin, dict) and not bool(pin.get("a"))]
    lines.append(f"  - `/json/pins`: {len(rows)} pins, {len(used)} used, {len(available)} available")
    for pin in used[:12]:
        gpio = pin.get("p", "?")
        owner = pin.get("n") or ("System" if not pin.get("o") else f"owner {pin.get('o')}")
        state = f", state={pin.get('s')}" if "s" in pin else ""
        lines.append(f"  - GPIO{gpio}: used by {owner}, notes={pin_notes(pin, caps)}{state}")
    if len(used) > 12:
        lines.append(f"  - ... {len(used) - 12} additional used pins")
    return lines, issues


def parse_js_int_assignment(script: str, name: str) -> int | None:
    match = re.search(rf"{re.escape(name)}\s*=\s*(-?\d+)", script)
    return int(match.group(1)) if match else None


def parse_2d_mode(script: str | None) -> int | None:
    if not script:
        return None
    match = re.search(r"Sf\.SOMP\.value\s*=\s*(\d+)", script)
    return int(match.group(1)) if match else None


def matrix_report(cfg: dict[str, Any], info: dict[str, Any], script: str | None) -> tuple[list[str], list[str]]:
    lines: list[str] = []
    issues: list[str] = []
    led = ((cfg.get("hw") or {}).get("led") or {}) if isinstance(cfg.get("hw"), dict) else {}
    matrix = led.get("matrix") if isinstance(led, dict) else None
    info_matrix = (info.get("leds") or {}).get("matrix") if isinstance(info.get("leds"), dict) else None
    mode = parse_2d_mode(script)
    is_matrix = mode == 1 or isinstance(matrix, dict) or isinstance(info_matrix, dict)
    panels = matrix.get("panels", []) if isinstance(matrix, dict) else []
    panel_count = matrix.get("mpc") if isinstance(matrix, dict) else len(panels)
    max_panels = parse_js_int_assignment(script or "", "maxPanels")

    lines.append(f"  - `/settings/s.js?p=10` mode: `{'2D Matrix' if is_matrix else '1D Strip'}`")
    if max_panels is not None:
        lines.append(f"  - Firmware max panels: `{max_panels}`")
    if isinstance(info_matrix, dict):
        width = info_matrix.get("w")
        height = info_matrix.get("h")
        lines.append(f"  - Active matrix dimensions: `{width} x {height}`")
    else:
        lines.append("  - Active matrix dimensions: `not active`")
    lines.append(f"  - Configured panel count: `{panel_count or 0}`")
    if isinstance(panels, list) and panels:
        for index, panel in enumerate(panels[:8]):
            if not isinstance(panel, dict):
                continue
            lines.append(
                "  - Panel "
                f"{index}: {panel.get('w', '?')}x{panel.get('h', '?')} "
                f"offset={panel.get('x', 0)},{panel.get('y', 0)} "
                f"start={'Bottom' if panel.get('b') else 'Top'} {'Right' if panel.get('r') else 'Left'} "
                f"orientation={'Vertical' if panel.get('v') else 'Horizontal'} "
                f"layout={'Serpentine' if panel.get('s') else 'Parallel'}"
            )
    return lines, issues


def capability_report(
    cfg: dict[str, Any],
    info: dict[str, Any],
    state: dict[str, Any],
) -> tuple[list[str], dict[str, bool]]:
    network = cfg.get("nw") if isinstance(cfg.get("nw"), dict) else {}
    interfaces = cfg.get("if") if isinstance(cfg.get("if"), dict) else {}
    sync = interfaces.get("sync") if isinstance(interfaces.get("sync"), dict) else {}
    live = interfaces.get("live") if isinstance(interfaces.get("live"), dict) else {}
    live_dmx = live.get("dmx") if isinstance(live.get("dmx"), dict) else {}
    leds = info.get("leds") if isinstance(info.get("leds"), dict) else {}
    hardware = cfg.get("hw") if isinstance(cfg.get("hw"), dict) else {}
    led_config = hardware.get("led") if isinstance(hardware.get("led"), dict) else {}

    raw_seglc = leds.get("seglc") if isinstance(leds.get("seglc"), list) else []
    info_segment_flags = [value for value in raw_seglc if isinstance(value, int)]
    state_segments = state.get("seg") if isinstance(state.get("seg"), list) else []
    state_segment_flags = [
        segment.get("lc")
        for segment in state_segments
        if isinstance(segment, dict) and isinstance(segment.get("lc"), int)
    ]
    segment_flags = info_segment_flags or state_segment_flags

    capabilities = {
        "espnow": "espnow" in network or "espnow" in sync,
        "dmx_input": any(
            key in live_dmx
            for key in ("inputRxPin", "inputTxPin", "inputEnablePin", "dmxInputPort")
        ),
        "dmx_output": isinstance(cfg.get("dmx"), dict),
        "cct_output": leds.get("cct") is True or any((flag & 0b100) != 0 for flag in segment_flags),
        "white_channel": leds.get("wv") is True or any((flag & 0b010) != 0 for flag in segment_flags),
        "matrix": isinstance(leds.get("matrix"), dict)
        or isinstance(led_config.get("matrix"), dict),
    }

    lines = ["### Runtime Capabilities"]
    labels = {
        "espnow": "ESP-NOW",
        "dmx_input": "DMX input",
        "dmx_output": "DMX output",
        "cct_output": "Tunable CCT output",
        "white_channel": "Dedicated white channel",
        "matrix": "2D matrix",
    }
    for key, label in labels.items():
        lines.append(f"- {label}: `{'supported' if capabilities[key] else 'not reported'}`")
    lines.append("- Capability decisions use live JSON fields, not hidden warning text from WLED HTML pages.")
    return lines, capabilities


def redacted_snapshot_value(value: Any, key: str = "") -> Any:
    normalized_key = key.lower().replace("-", "").replace("_", "")
    secret_key = any(token in normalized_key for token in ("password", "passwd", "passphrase", "psk", "secret"))
    if secret_key and normalized_key not in {"pskl", "passwordlength"}:
        return "<redacted>"
    if isinstance(value, dict):
        return {child_key: redacted_snapshot_value(child_value, child_key) for child_key, child_value in value.items()}
    if isinstance(value, list):
        return [redacted_snapshot_value(item, key) for item in value]
    return value


def wifi_invariants(cfg: dict[str, Any], net: dict[str, Any] | None) -> list[str]:
    issues: list[str] = []
    ap = cfg.get("ap") if isinstance(cfg.get("ap"), dict) else {}
    wifi = cfg.get("wifi") if isinstance(cfg.get("wifi"), dict) else {}
    identity = cfg.get("id") if isinstance(cfg.get("id"), dict) else {}

    mdns = identity.get("mdns", "")
    if isinstance(mdns, str) and (mdns.startswith("http://") or mdns.endswith(".local")):
        issues.append("WiFi & Network: mDNS should be stored as a bare host name without protocol or .local")
    if "pskl" in ap and "psk" in ap:
        issues.append("WiFi & Network: AP password should expose length only, not the password value")
    if not isinstance(ap.get("chan", 1), int):
        issues.append("WiFi & Network: AP channel is not numeric")
    if not isinstance(ap.get("behav", 0), int):
        issues.append("WiFi & Network: AP behavior is not numeric")
    if not isinstance(wifi.get("sleep", True), bool):
        issues.append("WiFi & Network: wifi.sleep is not boolean")
    if net and not any(key in net for key in ("ip", "ssid", "networks")):
        issues.append("WiFi & Network: /json/net responded but did not include expected status or scan fields")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True, help="WLED host or IP, without http://")
    parser.add_argument("--manifest", default="Aesdetic-Control/Resources/WLEDSettingsManifest.json", type=Path)
    parser.add_argument("--category", action="append", help="Category id to check. Defaults to core parity categories.")
    parser.add_argument("--timeout", default=4.0, type=float)
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    parser.add_argument(
        "--snapshot",
        type=Path,
        help="Write a redacted, read-only recovery snapshot of the live JSON responses.",
    )
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text())
    host = args.host.removeprefix("http://").removeprefix("https://").strip("/")
    categories = args.category or DEFAULT_CATEGORIES

    try:
        info = fetch_json(host, "/json/info", args.timeout)
        cfg = resolved_cfg(fetch_json(host, "/json/cfg", args.timeout))
        state = fetch_json(host, "/json/state", args.timeout)
        try:
            net = fetch_json(host, "/json/net", args.timeout)
        except (URLError, TimeoutError, RuntimeError, json.JSONDecodeError):
            net = None
        try:
            pins = fetch_json(host, "/json/pins", args.timeout)
        except (URLError, TimeoutError, RuntimeError, json.JSONDecodeError):
            pins = None
        try:
            with urlopen(f"http://{host}/settings/s.js?p=11", timeout=args.timeout) as response:
                pin_caps_script = response.read().decode("utf-8")
        except (URLError, TimeoutError, RuntimeError, UnicodeDecodeError):
            pin_caps_script = None
        try:
            matrix_script = fetch_text(host, "/settings/s.js?p=10", args.timeout)
        except (URLError, TimeoutError, RuntimeError, UnicodeDecodeError):
            matrix_script = None
    except Exception as error:
        print(f"Could not read WLED device {host}: {error}", file=sys.stderr)
        return 2

    issues: list[str] = []
    report_lines: list[str] = [
        f"# WLED Live Parity Check",
        f"- Checked at: {datetime.now(timezone.utc).isoformat()}",
        f"- Host: `{host}`",
        f"- Firmware: `{info.get('ver', 'unknown')}` (`{info.get('vid', 'unknown')}`)",
        f"- LEDs: `{info.get('leds', {}).get('count', 'unknown')}`",
        "",
    ]

    capability_lines, capabilities = capability_report(cfg, info, state)
    report_lines.extend(capability_lines)
    report_lines.append("")

    if args.snapshot:
        snapshot = redacted_snapshot_value({
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "host": host,
            "capabilities": capabilities,
            "info": info,
            "config": cfg,
            "state": state,
            "network": net,
            "pins": pins,
        })
        args.snapshot.parent.mkdir(parents=True, exist_ok=True)
        args.snapshot.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")
        report_lines.append(f"- Redacted snapshot: `{args.snapshot}`")
        report_lines.append("")

    issues.extend(wifi_invariants(cfg, net))
    for category_id in categories:
        category = category_by_id(manifest, category_id)
        if not category:
            issues.append(f"Manifest missing category `{category_id}`")
            continue
        lines, category_issues = category_report(category, cfg)
        if category_id == "pin-info":
            pin_lines, pin_issues = pin_info_report(pins, pin_caps_script)
            lines.extend(pin_lines)
            category_issues.extend(pin_issues)
        if category_id == "2d-configuration":
            matrix_lines, matrix_issues = matrix_report(cfg, info, matrix_script)
            lines.extend(matrix_lines)
            category_issues.extend(matrix_issues)
        if category_id == "dmx-output":
            dmx_lines, dmx_issues = dmx_output_report(cfg)
            lines.extend(dmx_lines)
            category_issues.extend(dmx_issues)
        if category_id == "usermods":
            usermod_lines, usermod_issues = usermods_report(cfg)
            lines.extend(usermod_lines)
            category_issues.extend(usermod_issues)
        report_lines.extend(lines)
        report_lines.append("")
        issues.extend(category_issues)

    status = "pass" if not issues else "needs-review"
    if args.json:
        print(json.dumps({"status": status, "host": host, "issues": issues, "report": report_lines}, indent=2))
    else:
        print("\n".join(report_lines))
        print("## Result")
        print(f"- Status: `{status}`")
        if issues:
            for issue in issues:
                print(f"- {issue}")
        else:
            print("- No read-only parity issues found.")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
