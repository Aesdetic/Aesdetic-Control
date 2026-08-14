import Foundation

enum SettingsExperienceLayer: String, Codable, CaseIterable {
    case simple
    case advanced
    case hidden
    case webFallback
}

enum SettingsExperienceRisk: String, Codable, CaseIterable {
    case safe
    case reconnect
    case restart
    case hardware
    case lockout
}

enum SimpleSettingsDestination: String, Codable, CaseIterable {
    case device
    case timeRoutines
    case wifi
    case smartHome
    case none
}

enum SettingsControlPreference: String, Codable, Equatable {
    case automatic
    case toggle
    case slider
    case segmented
    case menu
    case number
    case text
    case secret
    case action
}

struct SettingsFieldPresentation: Equatable {
    let label: String
    let help: String?
    let unit: String?
    let control: SettingsControlPreference
    let placement: SettingsPlacementDecision
}

struct SettingsPlacementDecision: Equatable {
    let layer: SettingsExperienceLayer
    let destination: SimpleSettingsDestination
    let risk: SettingsExperienceRisk
    let reason: String
}

struct AdvancedSettingsGroupDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let categoryIDs: [String]
}

enum WLEDSettingsExperiencePolicy {
    static let advancedGroups: [AdvancedSettingsGroupDescriptor] = [
        AdvancedSettingsGroupDescriptor(
            id: "hardware",
            title: "Lights & Hardware",
            summary: "**Lights:** Outputs, wiring, pins, and matrix layout.",
            systemImage: "lightbulb",
            categoryIDs: ["led-hardware", "pin-info", "2d-configuration"]
        ),
        AdvancedSettingsGroupDescriptor(
            id: "network-sync",
            title: "Network & Protocols",
            summary: "**Connections:** Network, sync, and lighting protocols.",
            systemImage: "network",
            categoryIDs: ["wifi-network", "sync-interfaces", "dmx-output"]
        ),
        AdvancedSettingsGroupDescriptor(
            id: "automation-extensions",
            title: "Firmware Features",
            summary: "**Firmware tools:** Clock, macros, and installed extensions.",
            systemImage: "puzzlepiece",
            categoryIDs: ["time-macros", "usermods"]
        ),
        AdvancedSettingsGroupDescriptor(
            id: "system",
            title: "System & Recovery",
            summary: "**System tools:** Security, backups, updates, and recovery.",
            systemImage: "lock.shield",
            categoryIDs: ["security-updates"]
        )
    ]

    static let hiddenCategoryIDs: Set<String> = ["user-interface"]

    private static let simpleFieldDestinations: [String: SimpleSettingsDestination] = [
        "user-interface.DS": .device,
        "led-hardware.BO": .device,
        "led-hardware.BF": .device,
        "led-hardware.TD": .device,
        "time-macros.NT": .timeRoutines,
        "time-macros.NS": .timeRoutines,
        "time-macros.CF": .timeRoutines,
        "time-macros.TZ": .timeRoutines,
        "time-macros.UO": .timeRoutines,
        "time-macros.LT": .timeRoutines,
        "time-macros.LN": .timeRoutines
    ]

    private static let categorySummaries: [String: String] = [
        "wifi-network": "**Advanced network:** Static IP, recovery hotspot, radio, Ethernet, and ESP-NOW.",
        "led-hardware": "**LED hardware:** Outputs, power, color, buttons, relay, and startup behavior.",
        "pin-info": "**Pin map:** See available GPIO pins and current assignments.",
        "2d-configuration": "**Matrix layout:** Inspect dimensions, direction, and panel arrangement.",
        "dmx-output": "**DMX output:** Configure wired fixtures when supported by this firmware.",
        "sync-interfaces": "**External control:** WLED sync, realtime input, MQTT, Hue, Alexa, DMX, and serial.",
        "time-macros": "**Firmware time:** Clock, overlays, countdowns, and preset actions.",
        "usermods": "**Installed extensions:** Shared I2C/SPI pins and Usermod controls.",
        "security-updates": "**System protection:** Update access, backups, and recovery.",
        "user-interface": "**WLED browser only:** Hidden because Aesdetic provides its own interface."
    ]

    private static let sectionDescriptions: [String: String] = [
        "wifi-network.Wireless network": "**Saved networks and IP:** Use the WiFi tab for normal connection changes.",
        "wifi-network.Ethernet Type": "**Ethernet hardware:** Select only the board physically installed.",
        "wifi-network.DNS & mDNS": "**Device address:** Set DNS and the local `.local` name.",
        "wifi-network.Configure Access Point": "**Recovery hotspot:** Available when normal WiFi cannot connect.",
        "wifi-network.WiFi Power": "**Radio behavior:** Incorrect values can reduce reliability or range.",
        "wifi-network.ESP-NOW Wireless": "**Direct device link:** Communicate with compatible ESP devices without normal WiFi data.",
        "led-hardware.LED setup": "**Power protection:** Limit brightness and current for the LEDs and power supply.",
        "led-hardware.LED outputs": "**Connected strips:** Set type, pins, length, color order, and current estimate.",
        "led-hardware.LED outputs:": "**Connected strips:** Match WLED to the physical strip and wiring.",
        "led-hardware.LED diagnostics": "**Read only:** LED count, memory estimate, and hardware-channel use.",
        "led-hardware.Color Order Override": "**Mixed wiring:** Change channel order for only part of a strip.",
        "led-hardware.Physical button rows": "**Button wiring:** Use WLED for its live pin-conflict checks.",
        "led-hardware.Config template": "**Template import:** Choose and validate the file on the WLED page.",
        "led-hardware.Color & White": "**Color calibration:** White channel, gamma, and color temperature.",
        "led-hardware.Buttons": "**Physical controls:** Buttons or touch inputs connected to GPIO pins.",
        "led-hardware.IR Remote": "**IR control:** Receiver pin and remote profile.",
        "led-hardware.Relay": "**External power:** Switch LED power through a connected relay.",
        "led-hardware.Power up": "**After restart:** Choose whether and how the LEDs turn on.",
        "led-hardware.Transitions": "**Default fade:** Duration used when WLED changes state.",
        "led-hardware.Random Palettes": "**Generated colors:** Control palette harmony and cycle timing.",
        "led-hardware.Timed light": "**Timed fade:** Default duration, target brightness, and mode.",
        "led-hardware.Advanced": "**Rendering:** Palette motion and LED refresh rate.",
        "pin-info.GPIO pins": "**Read only:** Live pin assignments and hardware notes.",
        "2d-configuration.2D setup": "**Read only:** Matrix mode and dimensions reported by WLED.",
        "2d-configuration.LED panel layout": "**Read only:** Panel order, orientation, offsets, and wiring direction.",
        "sync-interfaces.WLED Broadcast": "**Controller communication:** Ports used for WLED discovery and sync.",
        "sync-interfaces.ESP-NOW": "**Direct sync:** Requires ESP-NOW in Network settings.",
        "sync-interfaces.Sync groups": "**Group routing:** Choose which groups send or receive changes.",
        "sync-interfaces.Receive": "**Incoming sync:** Choose which state this device accepts.",
        "sync-interfaces.Send": "**Outgoing sync:** Choose when this device broadcasts changes.",
        "sync-interfaces.Instance List": "**Discovery:** Let other WLED devices find this controller.",
        "sync-interfaces.Realtime": "**Live streaming:** Let external software temporarily control LED data.",
        "sync-interfaces.Network DMX input": "**Network lighting:** Map E1.31, Art-Net, or another stream onto the LEDs.",
        "sync-interfaces.Wired DMX Input": "**DMX receiver:** Assign GPIO pins for the physical circuit.",
        "sync-interfaces.Alexa Voice Assistant": "**Direct Alexa:** Expose power, brightness, and color.",
        "sync-interfaces.MQTT": "**MQTT broker:** Use credentials created only for this device.",
        "sync-interfaces.Philips Hue": "**Hue mirror:** Follow power, brightness, or color from one Hue light.",
        "sync-interfaces.Serial": "**Serial link:** Set communication speed for connected equipment.",
        "sync-interfaces.MQTT and Hue": "**Performance:** Enabling both external services can reduce responsiveness.",
        "time-macros.Time setup": "**Device clock:** Network time, timezone, and solar location.",
        "time-macros.Clock": "**LED overlay:** Display a clock or countdown on the strip.",
        "time-macros.Timer & Alexa Presets": "**Completion actions:** Presets for timers, timed light, and Alexa.",
        "time-macros.Button Action Presets": "**Physical buttons:** Map gestures to WLED presets, separate from Aesdetic automations.",
        "time-macros.Time-Controlled Presets": "**Firmware schedules:** Separate from Aesdetic routines.",
        "usermods.Global I 2 C & SPI": "**Shared buses:** Assign pins used by installed firmware extensions.",
        "usermods.Global I2C & SPI": "**Shared buses:** Assign pins used by installed firmware extensions.",
        "usermods.Installed Extensions": "**Firmware-specific:** Controls exposed by installed Usermods.",
        "security-updates.Security & Update Setup": "**Access control:** Protect settings and firmware updates.",
        "security-updates.Software Update": "**Update access:** Limit firmware updates to the local network.",
        "security-updates.Backup & Restore": "**Replaces current data:** Back up before restoring configuration or presets.",
        "security-updates.About": "**Device information:** WLED version, board, memory, and uptime.",
        "dmx-output.DMX Output": "**Requires support:** Configure physical DMX output only when available.",
        "dmx-output.Fixture Layout": "**Address layout:** Channels, start address, spacing, and first LED.",
        "dmx-output.Channel Functions": "**Channel map:** Assign brightness, color, or another function."
    ]

    private static let friendlyLabels: [String: String] = [
        "wifi-network.D0": "DNS server",
        "wifi-network.D1": "DNS server",
        "wifi-network.D2": "DNS server",
        "wifi-network.D3": "DNS server",
        "wifi-network.CM": "Local web address",
        "wifi-network.AS": "Recovery hotspot name",
        "wifi-network.AH": "Hide recovery hotspot name",
        "wifi-network.AP": "Recovery hotspot password",
        "wifi-network.AC": "Recovery hotspot channel",
        "wifi-network.AB": "When the recovery hotspot opens",
        "wifi-network.FG": "Use legacy 802.11g WiFi",
        "wifi-network.WS": "Disable WiFi sleep",
        "wifi-network.TX": "WiFi transmit power",
        "wifi-network.RE": "Enable ESP-NOW",
        "led-hardware.BF": "Maximum brightness",
        "led-hardware.MA": "Power supply current limit",
        "led-hardware.PPL": "Use a separate limit for each output",
        "led-hardware.GC": "Correct colors with gamma",
        "led-hardware.GB": "Correct brightness with gamma",
        "led-hardware.GV": "Gamma value",
        "led-hardware.CCT": "Correct white balance",
        "led-hardware.AW": "Automatic white-channel mode",
        "led-hardware.CR": "Calculate color temperature from RGB",
        "led-hardware.IC": "Use the Athom 15W CCT driver",
        "led-hardware.CB": "Warm/cool white blending",
        "led-hardware.IP": "Disable internal button pull-up/down",
        "led-hardware.TT": "Touch sensitivity threshold",
        "led-hardware.MSO": "Apply IR changes to the main segment only",
        "led-hardware.BO": "Turn LEDs on after restart",
        "led-hardware.CA": "Startup brightness",
        "led-hardware.BP": "Startup preset",
        "led-hardware.TD": "Default transition time",
        "led-hardware.TH": "Use coordinated colors in random palettes",
        "led-hardware.TP": "Random palette cycle time",
        "led-hardware.TL": "Timed-light duration",
        "led-hardware.TB": "Timed-light target brightness",
        "led-hardware.TW": "Timed-light mode",
        "led-hardware.PB": "Palette wrapping",
        "led-hardware.FR": "Target refresh rate",
        "time-macros.NT": "Set time automatically",
        "time-macros.NS": "Time server",
        "time-macros.CF": "Use 24-hour time",
        "time-macros.TZ": "Timezone",
        "time-macros.UO": "Additional UTC offset",
        "time-macros.LT": "Latitude",
        "time-macros.LN": "Longitude",
        "security-updates.NO": "Lock wireless firmware updates",
        "security-updates.OW": "Hide WiFi settings while locked",
        "security-updates.AO": "Enable Arduino OTA updates",
        "security-updates.SU": "Allow updates only from this local network"
    ]

    private static let fieldHelp: [String: String] = [
        "led-hardware.BO": "**Power recovery:** Turns the light on after power returns or WLED restarts.",
        "led-hardware.BF": "**Output cap:** Limits brightness without changing the level in Controls.",
        "led-hardware.TD": "**Fade speed:** Used for color, effect, and brightness changes.",
        "led-hardware.MA": "**Power protection:** Limits the total current WLED may use.",
        "led-hardware.GV": "**Gamma curve:** Higher values make dim colors appear darker.",
        "led-hardware.FR": "**Refresh target:** Higher rates use more controller processing time.",
        "wifi-network.CM": "**Local address:** WLED adds `.local` automatically.",
        "wifi-network.AP": "**Recovery password:** Used only by the fallback hotspot.",
        "wifi-network.TX": "**Radio power:** Changing it can reduce range or make the device unreachable.",
        "wifi-network.RE": "**Direct link:** Lets compatible ESP devices and remotes communicate.",
        "sync-interfaces.BD": "**Serial speed:** Keep 115200 unless connected equipment requires another rate.",
        "security-updates.NO": "**OTA lock:** Requires the passphrase for wireless firmware changes.",
        "security-updates.SU": "**Local only:** Blocks firmware updates from outside the local network."
    ]

    private static let fieldUnits: [String: String] = [
        "led-hardware.BF": "%",
        "led-hardware.MA": "mA",
        "led-hardware.CB": "%",
        "led-hardware.TD": "ms",
        "led-hardware.TP": "s",
        "led-hardware.TL": "min",
        "led-hardware.FR": "FPS",
        "sync-interfaces.HI": "ms",
        "sync-interfaces.ET": "ms",
        "time-macros.UO": "s"
    ]

    private static let preferredControls: [String: SettingsControlPreference] = [
        "led-hardware.BO": .toggle,
        "led-hardware.BF": .slider,
        "led-hardware.TD": .segmented
    ]

    static func categorySummary(_ categoryID: String) -> String {
        categorySummaries[categoryID] ?? "**Advanced WLED:** Configuration for experienced users and installers."
    }

    static func sectionDescription(categoryID: String, section: String) -> String? {
        sectionDescriptions["\(categoryID).\(section)"]
    }

    static func friendlyLabel(categoryID: String, field: WLEDSettingDescriptor) -> String {
        friendlyLabels["\(categoryID).\(field.key)"] ?? field.label
    }

    static func presentation(categoryID: String, field: WLEDSettingDescriptor) -> SettingsFieldPresentation {
        let key = "\(categoryID).\(field.key)"
        return SettingsFieldPresentation(
            label: friendlyLabel(categoryID: categoryID, field: field),
            help: fieldHelp[key],
            unit: fieldUnits[key],
            control: preferredControls[key] ?? defaultControlPreference(for: field),
            placement: placement(categoryID: categoryID, field: field)
        )
    }

    private static func defaultControlPreference(for field: WLEDSettingDescriptor) -> SettingsControlPreference {
        switch field.control {
        case .toggle: return .toggle
        case .number: return .number
        case .select: return .menu
        case .text: return .text
        case .secret: return .secret
        case .file: return .action
        }
    }

    static func placement(categoryID: String, field: WLEDSettingDescriptor) -> SettingsPlacementDecision {
        let compositeKey = "\(categoryID).\(field.key)"
        if let destination = simpleFieldDestinations[compositeKey] {
            return SettingsPlacementDecision(
                layer: .simple,
                destination: destination,
                risk: risk(for: field),
                reason: "Used by the guided customer settings experience."
            )
        }

        if hiddenCategoryIDs.contains(categoryID) {
            return SettingsPlacementDecision(
                layer: .hidden,
                destination: .none,
                risk: .safe,
                reason: "Only affects WLED's browser interface."
            )
        }

        if field.fileUpload || field.localOnly || (field.configPath == nil && !field.secret) {
            return SettingsPlacementDecision(
                layer: .webFallback,
                destination: .none,
                risk: risk(for: field),
                reason: "Requires firmware-specific form behavior or a file workflow."
            )
        }

        return SettingsPlacementDecision(
            layer: .advanced,
            destination: .none,
            risk: risk(for: field),
            reason: "Useful for advanced setup, installation, or troubleshooting."
        )
    }

    static func risk(for field: WLEDSettingDescriptor) -> SettingsExperienceRisk {
        if field.sideEffects.contains(.securityLockout) { return .lockout }
        if field.sideEffects.contains(.ledReinit) || field.sideEffects.contains(.segmentRebuild) { return .hardware }
        if field.sideEffects.contains(.wifiReconnect) { return .reconnect }
        if field.sideEffects.contains(.reboot) { return .restart }
        return .safe
    }

    static func group(containing categoryID: String) -> AdvancedSettingsGroupDescriptor? {
        advancedGroups.first { $0.categoryIDs.contains(categoryID) }
    }
}

extension ProductType {
    var settingsObjectName: String {
        self == .sunriseLamp ? "Lamp" : "Device"
    }

    var settingsObjectNameLowercased: String {
        settingsObjectName.lowercased()
    }
}
