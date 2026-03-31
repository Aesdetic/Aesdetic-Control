import Foundation
import CoreLocation

// MARK: - Automation Model

struct Automation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastTriggered: Date?
    
    var trigger: AutomationTrigger
    var action: AutomationAction
    var targets: AutomationTargets
    var metadata: AutomationMetadata
    
    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastTriggered: Date? = nil,
        trigger: AutomationTrigger,
        action: AutomationAction,
        targets: AutomationTargets,
        metadata: AutomationMetadata = .init()
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastTriggered = lastTriggered
        self.trigger = trigger
        self.action = action
        self.targets = targets
        self.metadata = metadata
    }
    
    /// Returns a short summary suitable for cards or dashboard chips.
    var summary: String {
        switch action {
        case .scene(let payload):
            return payload.sceneName ?? "Scene"
        case .preset(let payload):
            return "Preset \(payload.presetId)"
        case .playlist(let payload):
            return payload.playlistName ?? "Playlist \(payload.playlistId)"
        case .gradient(let payload):
            if !payload.powerOn {
                return "Power off"
            }
            return payload.gradient.name ?? "Gradient"
        case .transition(let payload):
            if let presetName = payload.presetName {
                return presetName
            }
            return "Transition"
        case .effect(let payload):
            return payload.effectName ?? "Effect \(payload.effectId)"
        case .directState:
            return "Custom State"
        }
    }
    
    /// Helper used by schedulers that rely on simple time-based triggers.
    /// Solar triggers return nil and must be resolved by the scheduling engine.
    func nextTriggerDate(referenceDate: Date = .init(), calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        return trigger.nextTriggerDate(referenceDate: referenceDate, calendar: calendar)
    }
}

// MARK: - Trigger Definitions

enum AutomationTrigger: Codable, Equatable {
    case specificTime(TimeTrigger)
    case sunrise(SolarTrigger)
    case sunset(SolarTrigger)
    
    var displayName: String {
        switch self {
        case .specificTime(let time):
            return time.displayString
        case .sunrise(let solar):
            return solar.displayString(eventName: "Sunrise")
        case .sunset(let solar):
            return solar.displayString(eventName: "Sunset")
        }
    }
    
    func nextTriggerDate(referenceDate: Date, calendar: Calendar) -> Date? {
        switch self {
        case .specificTime(let trigger):
            return trigger.nextTriggerDate(referenceDate: referenceDate, calendar: calendar)
        case .sunrise, .sunset:
            return nil // Solar triggers resolved by scheduling engine
        }
    }
}

struct TimeTrigger: Codable, Equatable {
    var time: String // "HH:mm"
    var weekdays: [Bool] // Sunday...Saturday
    var timezoneIdentifier: String
    
    init(time: String, weekdays: [Bool], timezoneIdentifier: String = TimeZone.current.identifier) {
        self.time = time
        self.weekdays = weekdays.count == 7 ? weekdays : Array(repeating: true, count: 7)
        self.timezoneIdentifier = timezoneIdentifier
    }
    
    var displayString: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let selectedDays = weekdays.enumerated().compactMap { idx, flag in flag ? dayNames[idx] : nil }
        let days = selectedDays.isEmpty ? "No days" : selectedDays.joined(separator: ", ")
        return "\(time) · \(days)"
    }
    
    func nextTriggerDate(referenceDate: Date, calendar: Calendar = .current) -> Date? {
        let calendar = calendar
        let tz = TimeZone(identifier: timezoneIdentifier) ?? calendar.timeZone
        var calendarWithTZ = calendar
        calendarWithTZ.timeZone = tz
        
        let now = referenceDate
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }
        
        for offset in 0..<7 {
            guard let candidate = calendarWithTZ.date(byAdding: .day, value: offset, to: now) else { continue }
            let weekday = calendarWithTZ.component(.weekday, from: candidate) - 1
            guard weekday >= 0, weekday < weekdays.count, weekdays[weekday] else { continue }
            
            var dateComponents = calendarWithTZ.dateComponents([.year, .month, .day], from: candidate)
            dateComponents.hour = hour
            dateComponents.minute = minute
            dateComponents.second = 0
            
            if let triggerDate = calendarWithTZ.date(from: dateComponents), triggerDate > now {
                return triggerDate
            }
        }
        return nil
    }
}

enum WeekdayMask {
    static let allDaysSunFirst = Array(repeating: true, count: 7)

    /// Convert Sunday-first booleans (Sun...Sat) to WLED `dow` bitmask (Mon bit0 ... Sun bit6).
    static func wledDow(fromSunFirst weekdays: [Bool]) -> Int {
        let normalized = normalizeSunFirst(weekdays)
        var dow = 0
        // WLED bit positions: 0=Mon, 1=Tue, ... 5=Sat, 6=Sun
        for index in 0..<7 where normalized[index] {
            let bit: Int
            if index == 0 {
                bit = 6 // Sunday
            } else {
                bit = index - 1
            }
            dow |= (1 << bit)
        }
        return dow == 0 ? 0x7F : dow
    }

    /// Convert WLED `dow` bitmask (Mon bit0 ... Sun bit6) to Sunday-first booleans (Sun...Sat).
    static func sunFirst(fromWLEDDow dow: Int) -> [Bool] {
        let normalized = dow == 0 ? 0x7F : dow
        var weekdays = Array(repeating: false, count: 7)
        for index in 0..<7 {
            let bit: Int
            if index == 0 {
                bit = 6 // Sunday
            } else {
                bit = index - 1
            }
            weekdays[index] = ((normalized >> bit) & 0x01) == 1
        }
        return weekdays
    }

    static func normalizeSunFirst(_ weekdays: [Bool]) -> [Bool] {
        weekdays.count == 7 ? weekdays : allDaysSunFirst
    }
}

struct SolarTrigger: Codable, Equatable {
    enum EventOffset: Codable, Equatable {
        case minutes(Int)

        private enum CodingKeys: String, CodingKey {
            case minutes
            case legacyValue = "_0"
        }

        init(from decoder: Decoder) throws {
            // Legacy shape: "offset": 10
            if let singleValue = try? decoder.singleValueContainer(),
               let directMinutes = try? singleValue.decode(Int.self) {
                self = .minutes(directMinutes)
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Common shape: "offset": { "minutes": 10 }
            if let directMinutes = try? container.decode(Int.self, forKey: .minutes) {
                self = .minutes(directMinutes)
                return
            }

            // Swift synthesized enum payload shape: { "minutes": { "_0": 10 } }
            if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .minutes),
               let nestedMinutes = try? nested.decode(Int.self, forKey: .legacyValue) {
                self = .minutes(nestedMinutes)
                return
            }

            throw DecodingError.typeMismatch(
                EventOffset.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported SolarTrigger.EventOffset payload."
                )
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .minutes(let value):
                try container.encode(value, forKey: .minutes)
            }
        }
    }
    
    enum LocationSource: Codable, Equatable {
        case followDevice
        case manual(latitude: Double, longitude: Double)
        
        var manualCoordinate: CLLocationCoordinate2D? {
            switch self {
            case .followDevice: return nil
            case .manual(let lat, let lon): return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
    }
    
    var offset: EventOffset
    var location: LocationSource
    var weekdays: [Bool]

    static let minOnDeviceOffsetMinutes = -59
    static let maxOnDeviceOffsetMinutes = 59
    
    init(
        offset: EventOffset = .minutes(0),
        location: LocationSource = .followDevice,
        weekdays: [Bool] = WeekdayMask.allDaysSunFirst
    ) {
        self.offset = offset
        self.location = location
        self.weekdays = WeekdayMask.normalizeSunFirst(weekdays)
    }

    enum CodingKeys: String, CodingKey {
        case offset
        case location
        case weekdays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offset = try container.decode(EventOffset.self, forKey: .offset)
        location = try container.decode(LocationSource.self, forKey: .location)
        weekdays = WeekdayMask.normalizeSunFirst(
            try container.decodeIfPresent([Bool].self, forKey: .weekdays) ?? WeekdayMask.allDaysSunFirst
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(offset, forKey: .offset)
        try container.encode(location, forKey: .location)
        try container.encode(WeekdayMask.normalizeSunFirst(weekdays), forKey: .weekdays)
    }

    static func clampOnDeviceOffset(_ minutes: Int) -> Int {
        min(maxOnDeviceOffsetMinutes, max(minOnDeviceOffsetMinutes, minutes))
    }
    
    func displayString(eventName: String) -> String {
        let offsetString: String
        switch offset {
        case .minutes(let minutes):
            if minutes == 0 {
                offsetString = ""
            } else if minutes > 0 {
                offsetString = " (+\(minutes)m)"
            } else {
                offsetString = " (\(minutes)m)"
            }
        }
        return "\(eventName)\(offsetString)"
    }
}

// MARK: - Targets

struct AutomationTargets: Codable, Equatable {
    var deviceIds: [String]
    var syncGroupName: String?
    var allowPartialFailure: Bool
    
    init(
        deviceIds: [String],
        syncGroupName: String? = nil,
        allowPartialFailure: Bool = true
    ) {
        self.deviceIds = deviceIds
        self.syncGroupName = syncGroupName
        self.allowPartialFailure = allowPartialFailure
    }
}

// MARK: - Action Definitions

enum AutomationAction: Codable, Equatable {
    case scene(SceneActionPayload)
    case preset(PresetActionPayload)
    case playlist(PlaylistActionPayload)
    case gradient(GradientActionPayload)
    case transition(TransitionActionPayload)
    case effect(EffectActionPayload)
    case directState(DirectStatePayload)
}

enum AutomationMacroAssetKind {
    case playlist
    case preset
}

extension AutomationAction {
    var macroAssetKind: AutomationMacroAssetKind {
        switch self {
        case .playlist, .transition:
            return .playlist
        case .preset, .gradient, .effect, .directState, .scene:
            return .preset
        }
    }
}

struct SceneActionPayload: Codable, Equatable {
    var sceneId: UUID
    var sceneName: String?
    var brightnessOverride: Int?
}

struct PresetActionPayload: Codable, Equatable {
    var presetId: Int
    var paletteName: String?
    var durationSeconds: Double? = nil  // Optional duration for preset transitions
}

struct PlaylistActionPayload: Codable, Equatable {
    var playlistId: Int  // WLED playlist ID (1-250)
    var playlistName: String?
}

struct GradientActionPayload: Codable, Equatable {
    var gradient: LEDGradient
    var brightness: Int
    var durationSeconds: Double
    var temperature: Double? = nil
    var whiteLevel: Double? = nil
    var shouldLoop: Bool = false
    var presetId: UUID? = nil
    var presetName: String? = nil
    var powerOn: Bool = true

    enum CodingKeys: String, CodingKey {
        case gradient
        case brightness
        case durationSeconds
        case temperature
        case whiteLevel
        case shouldLoop
        case presetId
        case presetName
        case powerOn
    }

    init(
        gradient: LEDGradient,
        brightness: Int,
        durationSeconds: Double,
        temperature: Double? = nil,
        whiteLevel: Double? = nil,
        shouldLoop: Bool = false,
        presetId: UUID? = nil,
        presetName: String? = nil,
        powerOn: Bool = true
    ) {
        self.gradient = gradient
        self.brightness = brightness
        self.durationSeconds = durationSeconds
        self.temperature = temperature
        self.whiteLevel = whiteLevel
        self.shouldLoop = shouldLoop
        self.presetId = presetId
        self.presetName = presetName
        self.powerOn = powerOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gradient = try container.decode(LEDGradient.self, forKey: .gradient)
        brightness = try container.decode(Int.self, forKey: .brightness)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        whiteLevel = try container.decodeIfPresent(Double.self, forKey: .whiteLevel)
        shouldLoop = try container.decodeIfPresent(Bool.self, forKey: .shouldLoop) ?? false
        presetId = try container.decodeIfPresent(UUID.self, forKey: .presetId)
        presetName = try container.decodeIfPresent(String.self, forKey: .presetName)
        powerOn = try container.decodeIfPresent(Bool.self, forKey: .powerOn) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gradient, forKey: .gradient)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(whiteLevel, forKey: .whiteLevel)
        try container.encode(shouldLoop, forKey: .shouldLoop)
        try container.encodeIfPresent(presetId, forKey: .presetId)
        try container.encodeIfPresent(presetName, forKey: .presetName)
        try container.encode(powerOn, forKey: .powerOn)
    }
}

struct TransitionActionPayload: Codable, Equatable {
    var startGradient: LEDGradient
    var startBrightness: Int
    var startTemperature: Double? = nil
    var startWhiteLevel: Double? = nil
    var endGradient: LEDGradient
    var endBrightness: Int
    var endTemperature: Double? = nil
    var endWhiteLevel: Double? = nil
    var durationSeconds: Double
    var shouldLoop: Bool = false
    var presetId: UUID? = nil
    var presetName: String? = nil
    
    var isLoopingTransition: Bool {
        shouldLoop
    }
}

struct EffectActionPayload: Codable, Equatable {
    var effectId: Int
    var effectName: String?
    var gradient: LEDGradient?
    var speed: Int
    var intensity: Int
    var paletteId: Int?
    var brightness: Int
    var presetId: UUID? = nil
    var presetName: String? = nil
}

struct DirectStatePayload: Codable, Equatable {
    var colorHex: String
    var brightness: Int
    var temperature: Double? = nil
    var whiteLevel: Double? = nil
    var transitionDeciseconds: Int

    enum CodingKeys: String, CodingKey {
        case colorHex
        case brightness
        case temperature
        case whiteLevel
        case transitionDeciseconds
        case transitionMs
    }

    init(
        colorHex: String,
        brightness: Int,
        temperature: Double? = nil,
        whiteLevel: Double? = nil,
        transitionDeciseconds: Int
    ) {
        self.colorHex = colorHex
        self.brightness = brightness
        self.temperature = temperature
        self.whiteLevel = whiteLevel
        self.transitionDeciseconds = transitionDeciseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        brightness = try container.decode(Int.self, forKey: .brightness)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        whiteLevel = try container.decodeIfPresent(Double.self, forKey: .whiteLevel)
        if let deciseconds = try container.decodeIfPresent(Int.self, forKey: .transitionDeciseconds) {
            transitionDeciseconds = max(0, deciseconds)
        } else if let ms = try container.decodeIfPresent(Int.self, forKey: .transitionMs) {
            transitionDeciseconds = max(0, Int((Double(ms) / 100.0).rounded()))
        } else {
            transitionDeciseconds = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(brightness, forKey: .brightness)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(whiteLevel, forKey: .whiteLevel)
        try container.encode(transitionDeciseconds, forKey: .transitionDeciseconds)
    }
}

struct AutomationMetadata: Codable, Equatable {
    enum WLEDSyncState: String, Codable, Equatable {
        case unknown
        case syncing
        case synced
        case notSynced

        var displayLabel: String {
            switch self {
            case .unknown:
                return "Not ready"
            case .syncing:
                return "Getting ready"
            case .synced:
                return "Ready"
            case .notSynced:
                return "Not ready"
            }
        }
    }

    var colorPreviewHex: String?
    var accentColorHex: String?
    var iconName: String?
    var notes: String?
    var templateId: String?
    var pinnedToShortcuts: Bool?
    // WLED device-side execution metadata (optional, backwards compatible)
    var wledPlaylistId: Int? = nil  // WLED playlist ID if this automation uses a playlist
    var wledTimerSlot: Int? = nil   // WLED timer slot ID if this automation runs on-device
    var wledPlaylistIdsByDevice: [String: Int]? = nil  // Per-device playlist IDs
    var wledPresetIdsByDevice: [String: Int]? = nil    // Per-device preset IDs (snapshots)
    var wledTimerSlotsByDevice: [String: Int]? = nil   // Per-device timer slots
    var wledManagedPlaylistSignatureByDevice: [String: String]? = nil
    var wledManagedStepPresetIdsByDevice: [String: [Int]]? = nil
    var wledManagedPresetSignatureByDevice: [String: String]? = nil
    var wledSyncStateByDevice: [String: WLEDSyncState]? = nil
    var wledLastSyncErrorByDevice: [String: String]? = nil
    var wledLastSyncAtByDevice: [String: Date]? = nil
    var runOnDevice: Bool = false   // Whether this automation should run on WLED device (timer-based)
    // Optional WLED timer date window (applies to timer.start/end month/day)
    var onDeviceStartMonth: Int? = nil
    var onDeviceStartDay: Int? = nil
    var onDeviceEndMonth: Int? = nil
    var onDeviceEndDay: Int? = nil
    
    init(
        colorPreviewHex: String? = nil,
        accentColorHex: String? = nil,
        iconName: String? = nil,
        notes: String? = nil,
        templateId: String? = nil,
        pinnedToShortcuts: Bool? = nil,
        wledPlaylistId: Int? = nil,
        wledTimerSlot: Int? = nil,
        wledPlaylistIdsByDevice: [String: Int]? = nil,
        wledPresetIdsByDevice: [String: Int]? = nil,
        wledTimerSlotsByDevice: [String: Int]? = nil,
        wledManagedPlaylistSignatureByDevice: [String: String]? = nil,
        wledManagedStepPresetIdsByDevice: [String: [Int]]? = nil,
        wledManagedPresetSignatureByDevice: [String: String]? = nil,
        wledSyncStateByDevice: [String: WLEDSyncState]? = nil,
        wledLastSyncErrorByDevice: [String: String]? = nil,
        wledLastSyncAtByDevice: [String: Date]? = nil,
        runOnDevice: Bool = false,
        onDeviceStartMonth: Int? = nil,
        onDeviceStartDay: Int? = nil,
        onDeviceEndMonth: Int? = nil,
        onDeviceEndDay: Int? = nil
    ) {
        self.colorPreviewHex = colorPreviewHex
        self.accentColorHex = accentColorHex
        self.iconName = iconName
        self.notes = notes
        self.templateId = templateId
        self.pinnedToShortcuts = pinnedToShortcuts
        self.wledPlaylistId = wledPlaylistId
        self.wledTimerSlot = wledTimerSlot
        self.wledPlaylistIdsByDevice = wledPlaylistIdsByDevice
        self.wledPresetIdsByDevice = wledPresetIdsByDevice
        self.wledTimerSlotsByDevice = wledTimerSlotsByDevice
        self.wledManagedPlaylistSignatureByDevice = wledManagedPlaylistSignatureByDevice
        self.wledManagedStepPresetIdsByDevice = wledManagedStepPresetIdsByDevice
        self.wledManagedPresetSignatureByDevice = wledManagedPresetSignatureByDevice
        self.wledSyncStateByDevice = wledSyncStateByDevice
        self.wledLastSyncErrorByDevice = wledLastSyncErrorByDevice
        self.wledLastSyncAtByDevice = wledLastSyncAtByDevice
        self.runOnDevice = runOnDevice
        self.onDeviceStartMonth = onDeviceStartMonth
        self.onDeviceStartDay = onDeviceStartDay
        self.onDeviceEndMonth = onDeviceEndMonth
        self.onDeviceEndDay = onDeviceEndDay
    }

    func syncState(for deviceId: String) -> WLEDSyncState {
        wledSyncStateByDevice?[deviceId] ?? .unknown
    }

    func lastSyncError(for deviceId: String) -> String? {
        wledLastSyncErrorByDevice?[deviceId]
    }

    func lastSyncAt(for deviceId: String) -> Date? {
        wledLastSyncAtByDevice?[deviceId]
    }

    func managedPlaylistSignature(for deviceId: String) -> String? {
        wledManagedPlaylistSignatureByDevice?[deviceId]
    }

    func managedPresetSignature(for deviceId: String) -> String? {
        wledManagedPresetSignatureByDevice?[deviceId]
    }

    func managedStepPresetIds(for deviceId: String) -> [Int]? {
        wledManagedStepPresetIdsByDevice?[deviceId]
    }

    mutating func setManagedPlaylistSignature(_ signature: String?, for deviceId: String) {
        var map = wledManagedPlaylistSignatureByDevice ?? [:]
        if let signature, !signature.isEmpty {
            map[deviceId] = signature
        } else {
            map.removeValue(forKey: deviceId)
        }
        wledManagedPlaylistSignatureByDevice = map.isEmpty ? nil : map
    }

    mutating func setManagedStepPresetIds(_ presetIds: [Int]?, for deviceId: String) {
        var map = wledManagedStepPresetIdsByDevice ?? [:]
        if let presetIds {
            let unique = Array(Set(presetIds.filter { (1...250).contains($0) })).sorted()
            if unique.isEmpty {
                map.removeValue(forKey: deviceId)
            } else {
                map[deviceId] = unique
            }
        } else {
            map.removeValue(forKey: deviceId)
        }
        wledManagedStepPresetIdsByDevice = map.isEmpty ? nil : map
    }

    mutating func setManagedPresetSignature(_ signature: String?, for deviceId: String) {
        var map = wledManagedPresetSignatureByDevice ?? [:]
        if let signature, !signature.isEmpty {
            map[deviceId] = signature
        } else {
            map.removeValue(forKey: deviceId)
        }
        wledManagedPresetSignatureByDevice = map.isEmpty ? nil : map
    }

    mutating func clearWLEDMacroMetadata(for deviceIds: [String], preserveTimerSlots: Bool = true) {
        let targetIds = Set(deviceIds)
        if var playlistMap = wledPlaylistIdsByDevice {
            playlistMap = playlistMap.filter { !targetIds.contains($0.key) }
            wledPlaylistIdsByDevice = playlistMap.isEmpty ? nil : playlistMap
        }
        if var presetMap = wledPresetIdsByDevice {
            presetMap = presetMap.filter { !targetIds.contains($0.key) }
            wledPresetIdsByDevice = presetMap.isEmpty ? nil : presetMap
        }
        if var playlistSignatures = wledManagedPlaylistSignatureByDevice {
            playlistSignatures = playlistSignatures.filter { !targetIds.contains($0.key) }
            wledManagedPlaylistSignatureByDevice = playlistSignatures.isEmpty ? nil : playlistSignatures
        }
        if var managedStepIds = wledManagedStepPresetIdsByDevice {
            managedStepIds = managedStepIds.filter { !targetIds.contains($0.key) }
            wledManagedStepPresetIdsByDevice = managedStepIds.isEmpty ? nil : managedStepIds
        }
        if var presetSignatures = wledManagedPresetSignatureByDevice {
            presetSignatures = presetSignatures.filter { !targetIds.contains($0.key) }
            wledManagedPresetSignatureByDevice = presetSignatures.isEmpty ? nil : presetSignatures
        }
        if var syncMap = wledSyncStateByDevice {
            for deviceId in targetIds {
                syncMap[deviceId] = .unknown
            }
            wledSyncStateByDevice = syncMap.isEmpty ? nil : syncMap
        }
        if var errorMap = wledLastSyncErrorByDevice {
            for deviceId in targetIds {
                errorMap.removeValue(forKey: deviceId)
            }
            wledLastSyncErrorByDevice = errorMap.isEmpty ? nil : errorMap
        }
        if var syncAtMap = wledLastSyncAtByDevice {
            for deviceId in targetIds {
                syncAtMap.removeValue(forKey: deviceId)
            }
            wledLastSyncAtByDevice = syncAtMap.isEmpty ? nil : syncAtMap
        }
        if !preserveTimerSlots {
            if var slotMap = wledTimerSlotsByDevice {
                slotMap = slotMap.filter { !targetIds.contains($0.key) }
                wledTimerSlotsByDevice = slotMap.isEmpty ? nil : slotMap
            }
            if targetIds.count <= 1 {
                wledTimerSlot = nil
            }
        }
        if targetIds.count <= 1 {
            wledPlaylistId = nil
        }
    }

    mutating func normalizeWLEDScalarFallbacks(for targetDeviceIds: [String]) {
        let targetIds = Set(targetDeviceIds)
        wledPlaylistIdsByDevice = wledPlaylistIdsByDevice?.filter { targetIds.contains($0.key) }
        wledPresetIdsByDevice = wledPresetIdsByDevice?.filter { targetIds.contains($0.key) }
        wledTimerSlotsByDevice = wledTimerSlotsByDevice?.filter { targetIds.contains($0.key) }
        wledManagedPlaylistSignatureByDevice = wledManagedPlaylistSignatureByDevice?.filter { targetIds.contains($0.key) }
        wledManagedStepPresetIdsByDevice = wledManagedStepPresetIdsByDevice?.filter { targetIds.contains($0.key) }
        wledManagedPresetSignatureByDevice = wledManagedPresetSignatureByDevice?.filter { targetIds.contains($0.key) }
        wledSyncStateByDevice = wledSyncStateByDevice?.filter { targetIds.contains($0.key) }
        wledLastSyncErrorByDevice = wledLastSyncErrorByDevice?.filter { targetIds.contains($0.key) }
        wledLastSyncAtByDevice = wledLastSyncAtByDevice?.filter { targetIds.contains($0.key) }

        guard targetIds.count == 1, let onlyDeviceId = targetIds.first else {
            wledPlaylistId = nil
            wledTimerSlot = nil
            return
        }

        if let playlistMap = wledPlaylistIdsByDevice {
            wledPlaylistId = playlistMap[onlyDeviceId]
        }
        if let slotMap = wledTimerSlotsByDevice {
            wledTimerSlot = slotMap[onlyDeviceId]
        }
    }
}
