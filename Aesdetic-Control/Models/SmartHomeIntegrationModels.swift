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
    case enabled
    case needsSync
    case conflict
    case failed
    case unsupported
    case requiresBridge

    var displayName: String {
        switch self {
        case .notSetUp: return "Not Set Up"
        case .enabled: return "Enabled"
        case .needsSync: return "Needs Sync"
        case .conflict: return "Needs Review"
        case .failed: return "Failed"
        case .unsupported: return "Unsupported"
        case .requiresBridge: return "Requires Bridge"
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

    init(
        deviceId: String,
        kind: SmartHomeIntegrationKind,
        state: SmartHomeIntegrationState,
        message: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.deviceId = deviceId
        self.kind = kind
        self.state = state
        self.message = message
        self.updatedAt = updatedAt
    }
}
