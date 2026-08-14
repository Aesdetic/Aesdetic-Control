#!/usr/bin/env python3
"""Generate Aesdetic's WLED advanced settings manifest from WLED firmware files."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from zipfile import ZipFile


PAGES = [
    {
        "id": "wifi-network",
        "title": "WiFi & Network",
        "page": "settings_wifi.htm",
        "webPath": "/settings/wifi",
        "effects": ["wifiReconnect"],
    },
    {
        "id": "led-hardware",
        "title": "LED & Hardware",
        "page": "settings_leds.htm",
        "webPath": "/settings/leds",
        "effects": ["ledReinit", "segmentRebuild"],
    },
    {
        "id": "pin-info",
        "title": "Pin Info",
        "page": "settings_pininfo.htm",
        "webPath": "/settings/pins",
        "readOnly": True,
        "effects": [],
    },
    {
        "id": "2d-configuration",
        "title": "2D Configuration",
        "page": "settings_2D.htm",
        "webPath": "/settings/2D",
        # Native 2D editing is intentionally deferred until matrix form semantics
        # are fully implemented. Keep the app's pin/matrix inspection view read-only.
        "readOnly": True,
        "effects": ["ledReinit", "segmentRebuild"],
    },
    {
        "id": "user-interface",
        "title": "User Interface",
        "page": "settings_ui.htm",
        "webPath": "/settings/ui",
        "effects": [],
    },
    {
        "id": "dmx-output",
        "title": "DMX Output",
        "page": "settings_dmx.htm",
        "webPath": "/settings/dmx",
        "requiresFeature": "WLED_ENABLE_DMX",
        "effects": ["realtimeProtocol"],
    },
    {
        "id": "sync-interfaces",
        "title": "Sync Interfaces",
        "page": "settings_sync.htm",
        "webPath": "/settings/sync",
        "effects": ["realtimeProtocol"],
    },
    {
        "id": "time-macros",
        "title": "Time & Macros",
        "page": "settings_time.htm",
        "webPath": "/settings/time",
        "effects": ["timeSync"],
    },
    {
        "id": "usermods",
        "title": "Usermods",
        "page": "settings_um.htm",
        "webPath": "/settings/um",
        "effects": ["reboot"],
    },
    {
        "id": "security-updates",
        "title": "Security & Updates",
        "page": "settings_sec.htm",
        "webPath": "/settings/sec",
        "effects": ["securityLockout", "reboot"],
    },
]


KNOWN_CONFIG_PATHS = {
    # WiFi & Network
    "ETH": "eth.type",
    "D0": "nw.dns[0]",
    "D1": "nw.dns[1]",
    "D2": "nw.dns[2]",
    "D3": "nw.dns[3]",
    "CM": "id.mdns",
    "AS": "ap.ssid",
    "AH": "ap.hide",
    "AP": "ap.chan",
    "AC": "ap.behav",
    "AB": "ap.ip",
    "WS": "wifi.sleep",
    "TX": "wifi.txpwr",
    "RE": "nw.espnow",
    # LED & Hardware
    "BF": "light.scale-bri",
    "ABL": "hw.led.maxpwr",
    "MA": "hw.led.maxpwr",
    "PPL": "hw.led.ins[*].maxpwr",
    "MS": "light.aseg",
    "GC": "light.gc.col",
    "GB": "light.gc.bri",
    "GV": "light.gc.val",
    "CCT": "hw.led.cct",
    "AW": "hw.led.rgbwm",
    "CR": "hw.led.cr",
    "IC": "hw.led.ic",
    "CB": "hw.led.cb",
    "IP": "hw.btn.pull",
    "TT": "hw.btn.tt",
    "IR": "hw.ir.pin",
    "IT": "hw.ir.type",
    "MSO": "hw.ir.sel",
    "RL": "hw.relay.pin",
    "RM": "hw.relay.rev",
    "RO": "hw.relay.odrain",
    "BO": "def.on",
    "CA": "def.bri",
    "BP": "def.ps",
    "TD": "light.tr.dur",
    "TH": "light.tr.hrp",
    "TP": "light.tr.rpc",
    "TL": "light.nl.dur",
    "TB": "light.nl.tbri",
    "TW": "light.nl.mode",
    "PB": "light.pal-mode",
    "FR": "hw.led.fps",
    # 2D
    "SOMP": "hw.led.matrix.mpc",
    "PW": "hw.led.matrix.panels[0].w",
    "PH": "hw.led.matrix.panels[0].h",
    "MPC": "hw.led.matrix.mpc",
    # UI
    "DS": "id.name",
    # Sync Interfaces
    "UP": "if.sync.port0",
    "U2": "if.sync.port1",
    "EN": "if.sync.espnow",
    "GS": "if.sync.send.grp",
    "GR": "if.sync.recv.grp",
    "RB": "if.sync.recv.bri",
    "RC": "if.sync.recv.col",
    "RX": "if.sync.recv.fx",
    "RP": "if.sync.recv.pal",
    "SO": "if.sync.recv.seg",
    "SG": "if.sync.recv.sb",
    "SS": "if.sync.send.en",
    "SD": "if.sync.send.dir",
    "SB": "if.sync.send.btn",
    "SA": "if.sync.send.va",
    "SH": "if.sync.send.hue",
    "UR": "if.sync.send.ret",
    "NL": "if.nodes.list",
    "NB": "if.nodes.bcast",
    "RD": "if.live.en",
    "MO": "if.live.mso",
    "RLM": "if.live.rlm",
    "EP": "if.live.port",
    "EM": "if.live.mc",
    "EU": "if.live.dmx.uni",
    "ES": "if.live.dmx.seqskip",
    "DA": "if.live.dmx.addr",
    "XX": "if.live.dmx.dss",
    "PY": "if.live.dmx.e131prio",
    "DM": "if.live.dmx.mode",
    "ET": "if.live.timeout",
    "FB": "if.live.maxbri",
    "RG": "if.live.no-gc",
    "WO": "if.live.offset",
    "AL": "if.va.alexa",
    "AI": "id.inv",
    "AP": "if.va.p",
    "MQ": "if.mqtt.en",
    "MQPORT": "if.mqtt.port",
    "MQUSER": "if.mqtt.user",
    "MQPASS": "if.mqtt.psk",
    "MQCID": "if.mqtt.cid",
    "MD": "if.mqtt.topics.device",
    "MG": "if.mqtt.topics.group",
    "BM": "hw.btn.mqtt",
    "RT": "if.mqtt.rtn",
    "HL": "if.hue.id",
    "HI": "if.hue.iv",
    "HP": "if.hue.en",
    "HO": "if.hue.recv.on",
    "HB": "if.hue.recv.bri",
    "HC": "if.hue.recv.col",
    "H0": "if.hue.ip[0]",
    "H1": "if.hue.ip[1]",
    "H2": "if.hue.ip[2]",
    "H3": "if.hue.ip[3]",
    "IDMR": "if.live.dmx.inputRxPin",
    "IDMT": "if.live.dmx.inputTxPin",
    "IDME": "if.live.dmx.inputEnablePin",
    "IDMP": "if.live.dmx.dmxInputPort",
    # Time
    "NT": "if.ntp.en",
    "NS": "if.ntp.host",
    "CF": "if.ntp.ampm",
    "TZ": "if.ntp.tz",
    "UO": "if.ntp.offset",
    "LT": "if.ntp.lt",
    "LN": "if.ntp.ln",
    "OL": "ol.clock",
    "O1": "ol.o12pix",
    "O2": "ol.max",
    "OM": "ol.min",
    "O5": "ol.o5m",
    "OS": "ol.osec",
    "OB": "ol.osb",
    "CE": "ol.cntdwn",
    "CY": "timers.cntdwn.goal[0]",
    "CI": "timers.cntdwn.goal[1]",
    "CD": "timers.cntdwn.goal[2]",
    "CH": "timers.cntdwn.goal[3]",
    "CM": "timers.cntdwn.goal[4]",
    "CS": "timers.cntdwn.goal[5]",
    "MC": "timers.cntdwn.macro",
    "MN": "light.nl.macro",
    "A0": "if.va.macros[0]",
    "A1": "if.va.macros[1]",
    # Usermods
    "SDA": "hw.if.i2c-pin[0]",
    "SCL": "hw.if.i2c-pin[1]",
    "MOSI": "hw.if.spi-pin[0]",
    "MISO": "hw.if.spi-pin[2]",
    "SCLK": "hw.if.spi-pin[1]",
    "RBT": "rb",
    # Security
    "PIN": "sec.pin",
    "NO": "ota.lock",
    "OW": "ota.lock-wifi",
    "AO": "ota.aota",
}

CATEGORY_CONFIG_PATHS = {
    ("wifi-network", "AP"): "ap.psk",
    ("wifi-network", "AC"): "ap.chan",
    ("wifi-network", "AB"): "ap.behav",
    ("wifi-network", "FG"): "wifi.phy",
    ("wifi-network", "CM"): "id.mdns",
    ("wifi-network", "AS"): "ap.ssid",
    ("wifi-network", "SU"): None,
    ("led-hardware", "AS"): None,
    ("2d-configuration", "PB"): None,
    ("user-interface", "DS"): "id.name",
    ("user-interface", "SU"): "id.sui",
    ("sync-interfaces", "AP"): "if.va.p",
    ("sync-interfaces", "MS"): "if.mqtt.broker",
    ("sync-interfaces", "BD"): "hw.baud",
    ("dmx-output", "PU"): "dmx.e131proxy",
    ("dmx-output", "CN"): "dmx.chan",
    ("dmx-output", "CS"): "dmx.start",
    ("dmx-output", "CG"): "dmx.gap",
    ("dmx-output", "SL"): "dmx.start-led",
    ("time-macros", "LTR"): None,
    ("time-macros", "LNR"): None,
    ("security-updates", "SU"): "ota.same-subnet",
}


SECRET_FIELDS = {"MQPASS", "PIN", "OP"}
FILE_FIELDS = {"data", "data2"}
LOCAL_ONLY_FIELDS: set[str] = set()
CATEGORY_LOCAL_ONLY_FIELDS = {
    ("2d-configuration", "SOMP"),
    ("2d-configuration", "PW"),
    ("2d-configuration", "PH"),
    ("2d-configuration", "MPC"),
    # WLED's individual group checkboxes are converted to the GS / GR bitmasks
    # before submission. The native editor owns the bitmasks directly.
    ("sync-interfaces", "G1"),
    ("sync-interfaces", "G2"),
    ("sync-interfaces", "G3"),
    ("sync-interfaces", "G4"),
    ("sync-interfaces", "G5"),
    ("sync-interfaces", "G6"),
    ("sync-interfaces", "G7"),
    ("sync-interfaces", "G8"),
    ("sync-interfaces", "R1"),
    ("sync-interfaces", "R2"),
    ("sync-interfaces", "R3"),
    ("sync-interfaces", "R4"),
    ("sync-interfaces", "R5"),
    ("sync-interfaces", "R6"),
    ("sync-interfaces", "R7"),
    ("sync-interfaces", "R8"),
    # The DMX input type is an HTML-only mode selector. Native controls edit its
    # concrete WLED configuration fields instead.
    ("sync-interfaces", "DI"),
    # Factory reset is intentionally never exposed as a category save field.
    ("security-updates", "RS"),
}


class SettingsHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.sections: list[dict[str, Any]] = []
        self.fields: list[dict[str, Any]] = []
        self._heading_tag: str | None = None
        self._heading_text: list[str] = []
        self._current_section = "General"
        self._pending_select: dict[str, Any] | None = None
        self._pending_option: dict[str, Any] | None = None
        self._option_text: list[str] = []
        self._recent_text = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = {key: value or "" for key, value in attrs}
        if tag in {"h2", "h3", "h4"}:
            self._heading_tag = tag
            self._heading_text = []
            return

        if tag == "input" and attrs_dict.get("name"):
            self.fields.append(self._field_from_attrs("input", attrs_dict))
            return

        if tag == "textarea" and attrs_dict.get("name"):
            self.fields.append(self._field_from_attrs("textarea", attrs_dict))
            return

        if tag == "select" and attrs_dict.get("name"):
            self._pending_select = self._field_from_attrs("select", attrs_dict)
            self._pending_select["options"] = []
            return

        if tag == "option" and self._pending_select is not None:
            self._pending_option = {"value": attrs_dict.get("value", "")}
            self._option_text = []

    def handle_data(self, data: str) -> None:
        clean = re.sub(r"\s+", " ", data).strip()
        if not clean:
            return
        self._recent_text = clean
        if self._heading_tag is not None:
            self._heading_text.append(clean)
        if self._pending_option is not None:
            self._option_text.append(clean)

    def handle_endtag(self, tag: str) -> None:
        if self._heading_tag == tag:
            title = " ".join(self._heading_text).strip()
            if title:
                self._current_section = title
                self.sections.append({"title": title, "level": tag})
            self._heading_tag = None
            self._heading_text = []
            return

        if tag == "option" and self._pending_select is not None and self._pending_option is not None:
            option = dict(self._pending_option)
            option["label"] = " ".join(self._option_text).strip() or option["value"]
            self._pending_select["options"].append(option)
            self._pending_option = None
            self._option_text = []
            return

        if tag == "select" and self._pending_select is not None:
            self.fields.append(self._pending_select)
            self._pending_select = None

    def _field_from_attrs(self, tag: str, attrs: dict[str, str]) -> dict[str, Any]:
        name = attrs["name"]
        input_type = attrs.get("type", "")
        control = "text"
        if tag == "select":
            control = "select"
        elif input_type == "checkbox":
            control = "toggle"
        elif input_type == "number":
            control = "number"
        elif input_type == "file":
            control = "file"
        elif name in SECRET_FIELDS or input_type == "password":
            control = "secret"

        label = self._recent_text.strip(" :")
        if not label or len(label) > 80:
            label = friendly_label(name)

        field: dict[str, Any] = {
            "key": name,
            "label": label,
            "section": self._current_section,
            "control": control,
            "htmlTag": tag,
        }
        if input_type:
            field["htmlType"] = input_type
        for attr in ("min", "max", "step", "placeholder"):
            if attrs.get(attr):
                field[attr] = attrs[attr]
        if name in SECRET_FIELDS or input_type == "password":
            field["secret"] = True
        if name in FILE_FIELDS:
            field["fileUpload"] = True
        if name in LOCAL_ONLY_FIELDS:
            field["localOnly"] = True
        return field


def friendly_label(key: str) -> str:
    labels = {
        "BF": "Global brightness factor",
        "ABL": "Enable automatic brightness limiter",
        "MA": "Maximum PSU Current",
        "PPL": "Use per-output limiter",
        "MS": "Make a segment for each output",
        "GC": "Use Gamma correction for color",
        "GB": "Use Gamma correction for brightness",
        "GV": "Use Gamma value",
        "CCT": "White Balance correction",
        "AW": "Global override for Auto-calculate white",
        "CR": "Calculate CCT from RGB",
        "IC": "CCT IC used",
        "CB": "CCT blending",
        "FR": "Target refresh rate",
        "BO": "Turn LEDs on after power up/reset",
        "CA": "Power-up brightness",
        "BP": "Apply preset at boot",
        "TD": "Default transition time",
        "TL": "Timed light default duration",
        "TB": "Timed light target brightness",
        "TW": "Timed light mode",
        "PB": "Palette wrapping",
        "NT": "Use NTP",
        "NS": "NTP server",
        "TZ": "Timezone",
        "UO": "UTC offset",
        "PIN": "Settings PIN",
    }
    return labels.get(key, key)


def side_effects_for(category: dict[str, Any], field: dict[str, Any]) -> list[str]:
    effects = set(category.get("effects", []))
    key = field["key"]
    if key in {"BF", "GC", "GB", "GV", "CCT", "AW", "CR", "IC", "CB", "BO", "CA", "BP", "TD", "TH", "TP", "TL", "TB", "TW", "PB", "FR"}:
        effects.discard("segmentRebuild")
    if category.get("id") == "security-updates" and key in {"PIN", "NO", "OP", "OW", "RS", "AO", "SU"}:
        effects.add("securityLockout")
    if key == "RBT":
        effects.add("reboot")
    if field.get("secret"):
        effects.add("secret")
    return sorted(effects)


def generate(zip_path: Path) -> dict[str, Any]:
    categories = []
    with ZipFile(zip_path) as archive:
        names = set(archive.namelist())
        for page in PAGES:
            path = f"WLED-main/wled00/data/{page['page']}"
            if path not in names:
                continue
            html = archive.read(path).decode("utf-8", errors="replace")
            parser = SettingsHTMLParser()
            parser.feed(html)

            fields = []
            for field in parser.fields:
                next_field = dict(field)
                override_key = (page["id"], next_field["key"])
                if override_key in CATEGORY_CONFIG_PATHS:
                    path = CATEGORY_CONFIG_PATHS[override_key]
                    if path:
                        next_field["configPath"] = path
                    else:
                        next_field.pop("configPath", None)
                        next_field["localOnly"] = True
                elif next_field["key"] in KNOWN_CONFIG_PATHS:
                    next_field["configPath"] = KNOWN_CONFIG_PATHS[next_field["key"]]
                if override_key in CATEGORY_LOCAL_ONLY_FIELDS:
                    next_field["localOnly"] = True
                next_field["sideEffects"] = side_effects_for(page, next_field)
                fields.append(next_field)

            section_titles = []
            for section in parser.sections:
                if section["title"] not in section_titles:
                    section_titles.append(section["title"])

            categories.append(
                {
                    "id": page["id"],
                    "title": page["title"],
                    "page": page["page"],
                    "webPath": page["webPath"],
                    "requiresFeature": page.get("requiresFeature"),
                    "readOnly": page.get("readOnly", False),
                    "sections": section_titles,
                    "fields": fields,
                    "sourceFieldCount": len(fields),
                }
            )

    return {
        "schemaVersion": 2,
        "source": {
            "archiveSHA256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
            "firmwareRoot": "WLED-main/wled00",
        },
        "categories": categories,
    }


def manifest_diff_lines(current: dict[str, Any] | None, generated: dict[str, Any]) -> list[str]:
    if current is None:
        return ["Manifest does not exist yet."]

    lines: list[str] = []
    current_categories = {category["id"]: category for category in current.get("categories", [])}
    generated_categories = {category["id"]: category for category in generated.get("categories", [])}

    for category_id in sorted(set(current_categories) - set(generated_categories)):
        lines.append(f"Removed category: {current_categories[category_id].get('title', category_id)}")
    for category_id in sorted(set(generated_categories) - set(current_categories)):
        lines.append(f"Added category: {generated_categories[category_id].get('title', category_id)}")

    comparable_attrs = ("label", "control", "min", "max", "step", "configPath", "sideEffects", "options")
    for category_id in sorted(set(current_categories) & set(generated_categories)):
        current_category = current_categories[category_id]
        generated_category = generated_categories[category_id]
        current_fields = {field["key"]: field for field in current_category.get("fields", [])}
        generated_fields = {field["key"]: field for field in generated_category.get("fields", [])}
        category_title = generated_category.get("title", category_id)

        for field_key in sorted(set(current_fields) - set(generated_fields)):
            lines.append(f"{category_title}: removed field {field_key}")
        for field_key in sorted(set(generated_fields) - set(current_fields)):
            lines.append(f"{category_title}: added field {field_key}")

        for field_key in sorted(set(current_fields) & set(generated_fields)):
            current_field = current_fields[field_key]
            generated_field = generated_fields[field_key]
            for attr in comparable_attrs:
                if current_field.get(attr) != generated_field.get(attr):
                    lines.append(f"{category_title}: changed {field_key}.{attr}")

    return lines


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--diff-report", type=Path)
    parser.add_argument("--check", action="store_true", help="Exit non-zero if generated manifest differs from --output.")
    args = parser.parse_args()

    manifest = generate(args.zip)
    current = None
    if args.output.exists():
        current = json.loads(args.output.read_text())

    diff_lines = manifest_diff_lines(current, manifest)
    if args.diff_report:
        args.diff_report.parent.mkdir(parents=True, exist_ok=True)
        args.diff_report.write_text("\n".join(diff_lines) + "\n")

    if args.check:
        if diff_lines:
            print("\n".join(diff_lines), file=sys.stderr)
            sys.exit(1)
        print("WLED settings manifest is current.")
        return

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    total = sum(category["sourceFieldCount"] for category in manifest["categories"])
    print(f"Wrote {args.output} with {len(manifest['categories'])} categories and {total} fields")
    if diff_lines:
        print("Manifest changes:")
        print("\n".join(diff_lines))
    else:
        print("No manifest changes detected.")


if __name__ == "__main__":
    main()
