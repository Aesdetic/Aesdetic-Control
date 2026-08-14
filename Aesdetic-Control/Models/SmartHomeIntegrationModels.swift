import Foundation

enum SmartHomeIntegrationKind: String, Codable, CaseIterable, Identifiable {
    case alexa
    case homeAssistant
    case appleHome
    case googleHome
    case mqtt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alexa: return "Alexa"
        case .homeAssistant: return "Home Assistant"
        case .appleHome: return "Apple Home"
        case .googleHome: return "Google Home"
        case .mqtt: return "MQTT"
        }
    }

    var iconName: String {
        switch self {
        case .alexa: return "waveform.circle"
        case .homeAssistant: return "house.circle"
        case .appleHome: return "homekit"
        case .googleHome: return "g.circle"
        case .mqtt: return "antenna.radiowaves.left.and.right"
        }
    }
}

enum SmartHomeIntegrationState: String, Codable {
    case notSetUp
    case inProgress
    case enabled
    case needsSync
    case conflict
    case failed
    case unsupported
    case requiresBridge

    var displayName: String {
        switch self {
        case .notSetUp: return "Not Set Up"
        case .inProgress: return "In Progress"
        case .enabled: return "Enabled"
        case .needsSync: return "Needs Sync"
        case .conflict: return "Needs Review"
        case .failed: return "Failed"
        case .unsupported: return "Unsupported"
        case .requiresBridge: return "Requires Bridge"
        }
    }
}

enum SmartHomeVerificationSource: String, Codable {
    case reportedByDevice
    case savedInApp
    case notVerified

    var displayName: String {
        switch self {
        case .reportedByDevice: return "Reported by Device"
        case .savedInApp: return "Saved in App"
        case .notVerified: return "Not Verified"
        }
    }
}

struct HomeAssistantSetupState: Codable, Equatable {
    var deviceId: String
    var isWLEDAdded: Bool
    var isMainLightKept: Bool
    var areSegmentsDisabled: Bool
    var isHomeKitBridgeConfigured: Bool
    var homeAssistantURL: String?
    var mainEntityName: String?
    var updatedAt: Date

    init(
        deviceId: String,
        isWLEDAdded: Bool = false,
        isMainLightKept: Bool = false,
        areSegmentsDisabled: Bool = false,
        isHomeKitBridgeConfigured: Bool = false,
        homeAssistantURL: String? = nil,
        mainEntityName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.deviceId = deviceId
        self.isWLEDAdded = isWLEDAdded
        self.isMainLightKept = isMainLightKept
        self.areSegmentsDisabled = areSegmentsDisabled
        self.isHomeKitBridgeConfigured = isHomeKitBridgeConfigured
        self.homeAssistantURL = homeAssistantURL
        self.mainEntityName = mainEntityName
        self.updatedAt = updatedAt
    }

    var hasStartedSetup: Bool {
        isWLEDAdded
            || isMainLightKept
            || areSegmentsDisabled
            || isHomeKitBridgeConfigured
            || !(homeAssistantURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(mainEntityName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var isReadyForBridge: Bool {
        isWLEDAdded && isMainLightKept && areSegmentsDisabled
    }

    var isFullySetUp: Bool {
        isReadyForBridge && isHomeKitBridgeConfigured
    }

    var integrationState: SmartHomeIntegrationState {
        if isFullySetUp {
            return .enabled
        }
        if isWLEDAdded && isMainLightKept && !areSegmentsDisabled {
            return .conflict
        }
        if hasStartedSetup {
            return .inProgress
        }
        return .notSetUp
    }

    var integrationMessage: String {
        switch integrationState {
        case .enabled:
            return "Home Assistant bridge setup is marked complete."
        case .conflict:
            return "Segment entities still need review. Hide them in Home Assistant and keep the main light."
        case .inProgress:
            return "Finish the Home Assistant checklist, then expose only the main light to Apple Home, Alexa, or Google."
        case .notSetUp:
            return "Use Home Assistant's native WLED integration; Aesdetic will guide segment cleanup."
        default:
            return "Home Assistant setup uses the native WLED integration."
        }
    }
}

struct SmartHomeIntegrationStatus: Codable, Equatable, Identifiable {
    var id: String { "\(deviceId)-\(kind.rawValue)" }
    let deviceId: String
    let kind: SmartHomeIntegrationKind
    var state: SmartHomeIntegrationState
    var message: String?
    var updatedAt: Date
    var verificationSource: SmartHomeVerificationSource?

    var resolvedVerificationSource: SmartHomeVerificationSource {
        verificationSource ?? .savedInApp
    }

    init(
        deviceId: String,
        kind: SmartHomeIntegrationKind,
        state: SmartHomeIntegrationState,
        message: String? = nil,
        updatedAt: Date = Date(),
        verificationSource: SmartHomeVerificationSource = .savedInApp
    ) {
        self.deviceId = deviceId
        self.kind = kind
        self.state = state
        self.message = message
        self.updatedAt = updatedAt
        self.verificationSource = verificationSource
    }
}
