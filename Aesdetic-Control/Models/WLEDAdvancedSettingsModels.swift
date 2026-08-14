import Foundation

struct WLEDSettingsManifest: Codable, Equatable {
    let schemaVersion: Int
    let source: WLEDSettingsManifestSource
    let categories: [WLEDSettingsCategoryDescriptor]

    func category(id: String) -> WLEDSettingsCategoryDescriptor? {
        categories.first { $0.id == id }
    }
}

struct WLEDSettingsManifestSource: Codable, Equatable {
    let archiveSHA256: String
    let firmwareRoot: String
}

struct WLEDSecurityAboutInfo: Equatable {
    let version: String?
    let buildID: String?
    let brand: String?
    let product: String?
    let architecture: String?
    let core: String?
    let freeHeap: Int?
    let uptime: Int?

    var installedVersionText: String {
        let base = version.map { "WLED \($0)" } ?? "WLED"
        if let buildID, !buildID.isEmpty {
            return "\(base) (\(buildID))"
        }
        return base
    }

    var boardText: String? {
        let text = [product, architecture]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}

struct WLEDUsermodsInfo: Equatable {
    let modules: [WLEDUsermodModule]

    var hasModules: Bool {
        !modules.isEmpty
    }
}

struct WLEDUsermodModule: Equatable, Identifiable {
    var id: String { name }

    let name: String
    let rows: [WLEDUsermodConfigRow]
}

struct WLEDUsermodConfigRow: Equatable, Identifiable {
    var id: String { path }

    let path: String
    let label: String
    let value: String
}

enum WLEDUsermodFieldKind: Equatable {
    case boolean
    case number
    case text
    case numberArray
    case unsupported
}

struct WLEDUsermodFieldDraft: Equatable, Identifiable {
    let id: String
    let moduleName: String
    let section: String
    let key: String
    let label: String
    let formName: String
    let kind: WLEDUsermodFieldKind
    var value: String
    var arrayValues: [String]
    let unsupportedValue: String?

    var isEditable: Bool {
        kind != .unsupported
    }

    var boolValue: Bool {
        ["true", "on", "yes", "1", "enabled"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    mutating func setBoolValue(_ enabled: Bool) {
        value = enabled ? "true" : "false"
    }
}

struct WLEDUsermodModuleDraft: Equatable, Identifiable {
    var id: String { name }

    let name: String
    var fields: [WLEDUsermodFieldDraft]
}

struct WLEDUsermodsDraft: Equatable {
    let originalModules: [WLEDUsermodModuleDraft]
    var modules: [WLEDUsermodModuleDraft]

    init(modules: [WLEDUsermodModuleDraft]) {
        self.originalModules = modules
        self.modules = modules
    }

    var isDirty: Bool {
        modules != originalModules
    }

    var changedFields: [WLEDUsermodFieldDraft] {
        let originalFields = Dictionary(
            uniqueKeysWithValues: originalModules.flatMap(\.fields).map { ($0.id, $0) }
        )
        return modules.flatMap(\.fields).filter { originalFields[$0.id] != $0 }
    }

    mutating func reset() {
        modules = originalModules
    }
}

struct WLEDSettingsCategoryDescriptor: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let page: String
    let webPath: String
    let requiresFeature: String?
    let readOnly: Bool
    let sections: [String]
    let fields: [WLEDSettingDescriptor]
    let sourceFieldCount: Int

    var groupedFields: [(section: String, fields: [WLEDSettingDescriptor])] {
        let titles = sections.isEmpty ? ["General"] : sections
        var result: [(String, [WLEDSettingDescriptor])] = titles.map { ($0, []) }

        for field in fields {
            if let index = result.firstIndex(where: { $0.0 == field.section }) {
                result[index].1.append(field)
            } else {
                result.append((field.section, [field]))
            }
        }

        return result.filter { !$0.1.isEmpty || fields.isEmpty }
    }
}

struct WLEDSettingDescriptor: Codable, Equatable, Identifiable {
    var id: String { key }

    let key: String
    let label: String
    let section: String
    let control: WLEDSettingControl
    let htmlTag: String?
    let htmlType: String?
    let min: String?
    let max: String?
    let step: String?
    let placeholder: String?
    let secret: Bool
    let fileUpload: Bool
    let localOnly: Bool
    let configPath: String?
    let sideEffects: [WLEDSettingsSideEffect]
    let options: [WLEDSettingOption]?

    private enum CodingKeys: String, CodingKey {
        case key
        case label
        case section
        case control
        case htmlTag
        case htmlType
        case min
        case max
        case step
        case placeholder
        case secret
        case fileUpload
        case localOnly
        case configPath
        case sideEffects
        case options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        section = try container.decode(String.self, forKey: .section)
        control = try container.decode(WLEDSettingControl.self, forKey: .control)
        htmlTag = try container.decodeIfPresent(String.self, forKey: .htmlTag)
        htmlType = try container.decodeIfPresent(String.self, forKey: .htmlType)
        min = try container.decodeIfPresent(String.self, forKey: .min)
        max = try container.decodeIfPresent(String.self, forKey: .max)
        step = try container.decodeIfPresent(String.self, forKey: .step)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        secret = try container.decodeIfPresent(Bool.self, forKey: .secret) ?? false
        fileUpload = try container.decodeIfPresent(Bool.self, forKey: .fileUpload) ?? false
        localOnly = try container.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
        configPath = try container.decodeIfPresent(String.self, forKey: .configPath)
        sideEffects = try container.decodeIfPresent([WLEDSettingsSideEffect].self, forKey: .sideEffects) ?? []
        options = try container.decodeIfPresent([WLEDSettingOption].self, forKey: .options)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(label, forKey: .label)
        try container.encode(section, forKey: .section)
        try container.encode(control, forKey: .control)
        try container.encodeIfPresent(htmlTag, forKey: .htmlTag)
        try container.encodeIfPresent(htmlType, forKey: .htmlType)
        try container.encodeIfPresent(min, forKey: .min)
        try container.encodeIfPresent(max, forKey: .max)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        if secret { try container.encode(secret, forKey: .secret) }
        if fileUpload { try container.encode(fileUpload, forKey: .fileUpload) }
        if localOnly { try container.encode(localOnly, forKey: .localOnly) }
        try container.encodeIfPresent(configPath, forKey: .configPath)
        try container.encode(sideEffects, forKey: .sideEffects)
        try container.encodeIfPresent(options, forKey: .options)
    }

    var isWritableByGenericConfig: Bool {
        guard let configPath, !configPath.contains("*") else { return false }
        return !localOnly && !fileUpload && !secret && !configPath.hasPrefix("sec.")
    }

    func validatedNumber(from value: Double) -> Double {
        switch key {
        case "HI", "ET":
            return value * 100
        case "LT", "LN":
            return abs(value)
        default:
            return value
        }
    }
}

enum WLEDSettingControl: String, Codable, Equatable {
    case toggle
    case number
    case select
    case text
    case secret
    case file
}

struct WLEDSettingOption: Codable, Equatable, Identifiable {
    var id: String { value }
    let label: String
    let value: String
}

enum WLEDSettingsSideEffect: String, Codable, Equatable, CaseIterable {
    case ledReinit
    case segmentRebuild
    case wifiReconnect
    case reboot
    case securityLockout
    case realtimeProtocol
    case timeSync
    case secret

    var displayName: String {
        switch self {
        case .ledReinit: return "LED output restarts"
        case .segmentRebuild: return "Segments may rebuild"
        case .wifiReconnect: return "WiFi may reconnect"
        case .reboot: return "Reboot may be required"
        case .securityLockout: return "Security setting"
        case .realtimeProtocol: return "Realtime sync may change"
        case .timeSync: return "Clock behavior may change"
        case .secret: return "Write-only secret"
        }
    }
}

enum WLEDSettingValue: Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([WLEDSettingValue])
    case object([String: WLEDSettingValue])
    case null

    var boolValue: Bool {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            return ["true", "1", "yes", "on"].contains(value.lowercased())
        case .array, .object, .null:
            return false
        }
    }

    var numberValue: Double {
        switch self {
        case .number(let value):
            return value
        case .bool(let value):
            return value ? 1 : 0
        case .string(let value):
            return Double(value) ?? 0
        case .array, .object, .null:
            return 0
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return values.map(\.stringValue).joined(separator: ", ")
        case .object:
            return "Configured"
        case .null:
            return ""
        }
    }

    var jsonCompatibleValue: Any {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return Int(value)
            }
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.jsonCompatibleValue)
        case .object(let values):
            return values.mapValues(\.jsonCompatibleValue)
        case .null:
            return NSNull()
        }
    }

    static func fromJSON(_ value: Any?) -> WLEDSettingValue {
        guard let value, !(value is NSNull) else { return .null }
        if let bool = value as? Bool { return .bool(bool) }
        if let int = value as? Int { return .number(Double(int)) }
        if let double = value as? Double { return .number(double) }
        if let float = value as? Float { return .number(Double(float)) }
        if let string = value as? String { return .string(string) }
        if let array = value as? [Any] { return .array(array.map { .fromJSON($0) }) }
        if let object = value as? [String: Any] { return .object(object.mapValues { .fromJSON($0) }) }
        return .string(String(describing: value))
    }
}

enum WLEDSecretDraftState: Equatable {
    case preserve(configured: Bool)
    case replace(String)
    case clear
}

struct WLEDSettingsDraft: Equatable {
    let category: WLEDSettingsCategoryDescriptor
    let originalValues: [String: WLEDSettingValue]
    var values: [String: WLEDSettingValue]
    var secretStates: [String: WLEDSecretDraftState]

    var dirtyKeys: Set<String> {
        let valueChanges = values.reduce(into: Set<String>()) { result, pair in
            if originalValues[pair.key] != pair.value {
                result.insert(pair.key)
            }
        }
        let secretChanges = secretStates.reduce(into: Set<String>()) { result, pair in
            if case .preserve = pair.value {
                return
            }
            result.insert(pair.key)
        }
        return valueChanges.union(secretChanges)
    }

    var isDirty: Bool { !dirtyKeys.isEmpty }

    var changedFields: [WLEDSettingDescriptor] {
        category.fields.filter { dirtyKeys.contains($0.key) }
    }

    var sideEffects: [WLEDSettingsSideEffect] {
        var ordered: [WLEDSettingsSideEffect] = []
        for field in changedFields {
            for effect in field.sideEffects where !ordered.contains(effect) {
                ordered.append(effect)
            }
        }
        return ordered
    }

    mutating func setValue(_ value: WLEDSettingValue, for key: String) {
        values[key] = value
    }

    mutating func setSecretState(_ state: WLEDSecretDraftState, for key: String) {
        secretStates[key] = state
    }

    mutating func reset() {
        values = originalValues
        for key in secretStates.keys {
            if case .preserve(let configured) = secretStates[key] {
                secretStates[key] = .preserve(configured: configured)
            } else {
                secretStates[key] = .preserve(configured: false)
            }
        }
    }

    func validationErrors() -> [String: String] {
        var errors: [String: String] = [:]
        for field in category.fields {
            guard dirtyKeys.contains(field.key), let value = values[field.key] else { continue }
            if field.control == .number || field.control == .select {
                let number = field.validatedNumber(from: value.numberValue)
                if let min = field.min.flatMap(Double.init), number < min {
                    errors[field.key] = "\(field.label) must be at least \(field.min ?? "")."
                }
                if let max = field.max.flatMap(Double.init), number > max {
                    errors[field.key] = "\(field.label) must be at most \(field.max ?? "")."
                }
            }
            if field.secret, case .replace(let replacement) = secretStates[field.key] {
                if replacement.isEmpty {
                    continue
                }
                if field.key == "PIN" {
                    if replacement.count != 4 || replacement.contains(where: { !$0.isNumber }) {
                        errors[field.key] = "\(field.label) must be a 4 digit number."
                    }
                } else if field.key == "OP" {
                    if replacement.count > 32 {
                        errors[field.key] = "\(field.label) must be 32 characters or fewer."
                    }
                } else if replacement.count < 8 || replacement.count > 63 {
                    errors[field.key] = "\(field.label) must be empty or 8-63 characters."
                }
            }
        }
        return errors
    }
}

struct WLEDSettingsSaveResult: Equatable {
    let savedKeys: Set<String>
    let sideEffects: [WLEDSettingsSideEffect]
    let requiresRefresh: Bool

    var statusText: String {
        if sideEffects.contains(.wifiReconnect) {
            return "Reconnect Required"
        }
        if sideEffects.contains(.reboot) {
            return "Restart Required"
        }
        return "Saved"
    }
}

struct WLEDLEDOutputDraft: Equatable {
    let originalOutputs: [WLEDLEDOutput]
    let originalColorOverrides: [WLEDColorOrderOverride]
    let diagnostics: WLEDLEDDiagnostics
    var outputs: [WLEDLEDOutput]
    var colorOverrides: [WLEDColorOrderOverride]

    var isDirty: Bool {
        outputs != originalOutputs || colorOverrides != originalColorOverrides
    }

    var sideEffects: [WLEDSettingsSideEffect] {
        isDirty ? [.ledReinit, .segmentRebuild, .reboot] : []
    }

    mutating func reset() {
        outputs = originalOutputs
        colorOverrides = originalColorOverrides
    }

    mutating func addOutput() {
        let nextStart = outputs.map { $0.start + $0.length }.max() ?? 0
        outputs.append(
            WLEDLEDOutput(
                type: outputs.last?.type ?? 22,
                pins: "",
                length: 1,
                start: nextStart,
                skip: 0,
                reverse: false,
                refreshWhenOff: false,
                colorOrder: outputs.last?.colorOrder ?? 0,
                whiteChannelSwap: outputs.last?.whiteChannelSwap ?? 0,
                autoWhiteMode: outputs.last?.autoWhiteMode ?? 0,
                frequency: 0,
                currentMilliamps: outputs.last?.currentMilliamps ?? 55,
                maxPowerMilliamps: 0,
                driverType: 0,
                perOutputLimiter: false
            )
        )
    }

    mutating func removeOutput(at index: Int) {
        guard outputs.indices.contains(index), outputs.count > 1 else { return }
        outputs.remove(at: index)
    }

    mutating func updateOutput(id: WLEDLEDOutput.ID, with output: WLEDLEDOutput) {
        guard let index = outputs.firstIndex(where: { $0.id == id }) else { return }
        outputs[index] = output
    }

    mutating func removeOutput(id: WLEDLEDOutput.ID) {
        guard let index = outputs.firstIndex(where: { $0.id == id }) else { return }
        removeOutput(at: index)
    }

    mutating func addColorOverride() {
        colorOverrides.append(
            WLEDColorOrderOverride(
                start: outputs.map { $0.start + $0.length }.max() ?? 0,
                length: 1,
                colorOrder: outputs.first?.colorOrder ?? 0,
                whiteChannelSwap: 0
            )
        )
    }

    mutating func removeColorOverride(at index: Int) {
        guard colorOverrides.indices.contains(index) else { return }
        colorOverrides.remove(at: index)
    }

    mutating func updateColorOverride(id: WLEDColorOrderOverride.ID, with override: WLEDColorOrderOverride) {
        guard let index = colorOverrides.firstIndex(where: { $0.id == id }) else { return }
        colorOverrides[index] = override
    }

    mutating func removeColorOverride(id: WLEDColorOrderOverride.ID) {
        guard let index = colorOverrides.firstIndex(where: { $0.id == id }) else { return }
        removeColorOverride(at: index)
    }

    var normalizedColorOverrides: [WLEDColorOrderOverride] {
        var seen: Set<String> = []
        return colorOverrides.filter { override in
            let key = override.normalizedSignature
            return seen.insert(key).inserted
        }
    }

    func validationErrors() -> [String: String] {
        var errors: [String: String] = [:]
        for index in outputs.indices {
            let output = outputs[index]
            if output.type < 0 {
                errors["output-\(index)-type"] = "Type must be 0 or higher."
            }
            if output.parsedPins == nil {
                errors["output-\(index)-pins"] = "Pins must be comma-separated numbers."
            }
            if output.length < 0 {
                errors["output-\(index)-length"] = "Length must be 0 or higher."
            }
            if output.start < 0 {
                errors["output-\(index)-start"] = "Start must be 0 or higher."
            }
            if output.skip < 0 {
                errors["output-\(index)-skip"] = "Skip must be 0 or higher."
            }
            if output.currentMilliamps < 0 {
                errors["output-\(index)-current"] = "LED current must be 0 or higher."
            }
            if output.maxPowerMilliamps < 0 {
                errors["output-\(index)-maxpwr"] = "Power limit must be 0 or higher."
            }
        }
        for index in colorOverrides.indices {
            let mapping = colorOverrides[index]
            if mapping.start < 0 {
                errors["override-\(index)-start"] = "Start must be 0 or higher."
            }
            if mapping.length <= 0 {
                errors["override-\(index)-length"] = "Length must be at least 1."
            }
        }
        return errors
    }
}

struct WLEDLEDDiagnostics: Equatable {
    let totalLEDs: Int
    let brightestWhiteAmps: Double?
    let typicalEffectsAmps: Double?
    let estimatedMemoryUsedBytes: Int?
    let estimatedMemoryAvailableBytes: Int?
    let hardwareChannelsSummary: String?
}

struct WLEDPinInfo: Equatable {
    let pins: [WLEDPinInfoPin]

    var availableCount: Int {
        pins.filter { !$0.isAllocated }.count
    }

    var allocatedCount: Int {
        pins.filter(\.isAllocated).count
    }
}

struct WLEDPinInfoPin: Equatable, Identifiable {
    var id: Int { gpio }

    let gpio: Int
    let capabilities: Int
    let isAllocated: Bool
    let owner: Int?
    let name: String?
    let mode: Int?
    let type: Int?
    let state: Int?
    let rawValue: Int?
    let isTouch: Bool
    let isInputOnly: Bool
    let isAnalog: Bool

    var displayOwner: String {
        if let name, !name.isEmpty {
            return name
        }
        if !isAllocated {
            return "Available"
        }
        if owner == 0x85, let type {
            return "Button \(buttonTypeName(type))"
        }
        guard let owner, owner != 0 else {
            return "System"
        }
        return "Usermod \(owner)"
    }

    var statusText: String {
        isAllocated ? "Used" : "Available"
    }

    var noteText: String {
        let notes = capabilityNotes
        return notes.isEmpty ? "-" : notes.joined(separator: ", ")
    }

    var stateText: String? {
        guard let state else { return nil }
        return state == 0 ? "Off" : "On"
    }

    var capabilityNotes: [String] {
        var notes: [String] = []
        if isTouch {
            notes.append("Touch")
        }
        if isInputOnly {
            notes.append("Input Only")
        }
        if isAnalog || capabilities & 0x02 != 0 {
            notes.append("Analog")
        }
        if capabilities & 0x08 != 0 {
            notes.append("Flash Boot")
        }
        if capabilities & 0x10 != 0 {
            notes.append("Bootstrap")
        }
        return notes
    }

    private func buttonTypeName(_ type: Int) -> String {
        switch type {
        case 0: return "None"
        case 1: return "Reserved"
        case 2: return "Push"
        case 3: return "Push Inverted"
        case 4: return "Switch"
        case 5: return "PIR"
        case 6: return "Touch"
        case 7: return "Analog"
        case 8: return "Analog Inverted"
        case 9: return "Touch Switch"
        default: return "Unknown"
        }
    }
}

struct WLEDPinCapabilities: Equatable {
    var touch: Set<Int> = []
    var inputOnly: Set<Int> = []
    var analog: Set<Int> = []

    static let empty = WLEDPinCapabilities()
}

struct WLEDPinInfoResponse: Codable {
    let pins: [WLEDPinInfoPinResponse]

    func model(capabilities: WLEDPinCapabilities = .empty) -> WLEDPinInfo {
        WLEDPinInfo(
            pins: pins
                .map { $0.model(capabilities: capabilities) }
                .sorted { $0.gpio < $1.gpio }
        )
    }
}

struct WLEDPinInfoPinResponse: Codable {
    let p: Int
    let c: Int?
    let a: Bool?
    let o: Int?
    let n: String?
    let m: Int?
    let t: Int?
    let s: Int?
    let r: Int?

    func model(capabilities: WLEDPinCapabilities = .empty) -> WLEDPinInfoPin {
        WLEDPinInfoPin(
            gpio: p,
            capabilities: c ?? 0,
            isAllocated: a ?? false,
            owner: o,
            name: n,
            mode: m,
            type: t,
            state: s,
            rawValue: r,
            isTouch: capabilities.touch.contains(p),
            isInputOnly: capabilities.inputOnly.contains(p),
            isAnalog: capabilities.analog.contains(p)
        )
    }
}

struct WLEDMatrixInfo: Equatable {
    let mode: WLEDMatrixMode
    let maxPanels: Int?
    let totalLEDs: Int?
    let matrixWidth: Int?
    let matrixHeight: Int?
    let configuredPanelCount: Int
    let panels: [WLEDMatrixPanel]

    var dimensionsText: String {
        guard let matrixWidth, let matrixHeight else {
            return "Not active"
        }
        return "\(matrixWidth) x \(matrixHeight) = \(matrixWidth * matrixHeight)"
    }

    var panelCountText: String {
        if mode == .strip {
            return "0"
        }
        if panels.isEmpty {
            return "\(configuredPanelCount)"
        }
        return "\(panels.count)"
    }
}

enum WLEDMatrixMode: Equatable {
    case strip
    case matrix

    var displayName: String {
        switch self {
        case .strip: return "1D Strip"
        case .matrix: return "2D Matrix"
        }
    }
}

struct WLEDMatrixPanel: Equatable, Identifiable {
    let index: Int
    let bottomStart: Bool
    let rightStart: Bool
    let vertical: Bool
    let serpentine: Bool
    let xOffset: Int
    let yOffset: Int
    let width: Int
    let height: Int

    var id: Int { index }

    var firstLEDText: String {
        "\(bottomStart ? "Bottom" : "Top") \(rightStart ? "Right" : "Left")"
    }

    var orientationText: String {
        vertical ? "Vertical" : "Horizontal"
    }

    var layoutText: String {
        serpentine ? "Serpentine" : "Parallel"
    }

    var dimensionsText: String {
        "\(width) x \(height)"
    }

    var offsetText: String {
        "\(xOffset), \(yOffset)"
    }
}

struct WLEDLEDOutput: Equatable, Identifiable {
    let id = UUID()
    var type: Int
    var pins: String
    var length: Int
    var start: Int
    var skip: Int
    var reverse: Bool
    var refreshWhenOff: Bool
    var colorOrder: Int
    var whiteChannelSwap: Int
    var autoWhiteMode: Int
    var frequency: Int
    var currentMilliamps: Int
    var maxPowerMilliamps: Int
    var driverType: Int
    var perOutputLimiter: Bool

    var parsedPins: [Int]? {
        let trimmed = pins.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var result: [Int] = []
        for part in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            let clean = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(clean) else { return nil }
            result.append(value)
        }
        return result
    }

    static func == (lhs: WLEDLEDOutput, rhs: WLEDLEDOutput) -> Bool {
        lhs.type == rhs.type
            && lhs.pins == rhs.pins
            && lhs.length == rhs.length
            && lhs.start == rhs.start
            && lhs.skip == rhs.skip
            && lhs.reverse == rhs.reverse
            && lhs.refreshWhenOff == rhs.refreshWhenOff
            && lhs.colorOrder == rhs.colorOrder
            && lhs.whiteChannelSwap == rhs.whiteChannelSwap
            && lhs.autoWhiteMode == rhs.autoWhiteMode
            && lhs.frequency == rhs.frequency
            && lhs.currentMilliamps == rhs.currentMilliamps
            && lhs.maxPowerMilliamps == rhs.maxPowerMilliamps
            && lhs.driverType == rhs.driverType
            && lhs.perOutputLimiter == rhs.perOutputLimiter
    }
}

struct WLEDColorOrderOverride: Equatable, Identifiable {
    let id = UUID()
    var start: Int
    var length: Int
    var colorOrder: Int
    var whiteChannelSwap: Int

    var normalizedSignature: String {
        "\(start):\(length):\(colorOrder):\(whiteChannelSwap)"
    }

    static func == (lhs: WLEDColorOrderOverride, rhs: WLEDColorOrderOverride) -> Bool {
        lhs.start == rhs.start
            && lhs.length == rhs.length
            && lhs.colorOrder == rhs.colorOrder
            && lhs.whiteChannelSwap == rhs.whiteChannelSwap
    }
}
