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
        case .gradient(let payload):
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

struct SolarTrigger: Codable, Equatable {
    enum EventOffset: Codable, Equatable {
        case minutes(Int)
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
    
    init(offset: EventOffset = .minutes(0), location: LocationSource = .followDevice) {
        self.offset = offset
        self.location = location
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
    case gradient(GradientActionPayload)
    case transition(TransitionActionPayload)
    case effect(EffectActionPayload)
    case directState(DirectStatePayload)
}

struct SceneActionPayload: Codable, Equatable {
    var sceneId: UUID
    var sceneName: String?
    var brightnessOverride: Int?
}

struct PresetActionPayload: Codable, Equatable {
    var presetId: Int
    var paletteName: String?
}

struct GradientActionPayload: Codable, Equatable {
    var gradient: LEDGradient
    var brightness: Int
    var durationSeconds: Double
    var shouldLoop: Bool = false
    var presetId: UUID? = nil
    var presetName: String? = nil
}

struct TransitionActionPayload: Codable, Equatable {
    var startGradient: LEDGradient
    var startBrightness: Int
    var endGradient: LEDGradient
    var endBrightness: Int
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
    var temperature: Double?
    var transitionMs: Int
}

struct AutomationMetadata: Codable, Equatable {
    var colorPreviewHex: String?
    var accentColorHex: String?
    var iconName: String?
    var notes: String?
    var templateId: String?
    var pinnedToShortcuts: Bool?
    
    init(
        colorPreviewHex: String? = nil,
        accentColorHex: String? = nil,
        iconName: String? = nil,
        notes: String? = nil,
        templateId: String? = nil,
        pinnedToShortcuts: Bool? = nil
    ) {
        self.colorPreviewHex = colorPreviewHex
        self.accentColorHex = accentColorHex
        self.iconName = iconName
        self.notes = notes
        self.templateId = templateId
        self.pinnedToShortcuts = pinnedToShortcuts
    }
}