import Foundation
import Combine

@MainActor
final class SmartHomeIntegrationStore: ObservableObject {
    static let shared = SmartHomeIntegrationStore()

    @Published private(set) var statuses: [String: SmartHomeIntegrationStatus] = [:]

    private let storageKey = "aesdetic_smart_home_integration_statuses_v1"

    private init() {
        load()
    }

    func status(for kind: SmartHomeIntegrationKind, deviceId: String) -> SmartHomeIntegrationStatus {
        statuses[key(deviceId: deviceId, kind: kind)] ?? SmartHomeIntegrationStatus(
            deviceId: deviceId,
            kind: kind,
            state: defaultState(for: kind),
            message: defaultMessage(for: kind)
        )
    }

    func setStatus(
        _ state: SmartHomeIntegrationState,
        for kind: SmartHomeIntegrationKind,
        deviceId: String,
        message: String? = nil
    ) {
        let status = SmartHomeIntegrationStatus(
            deviceId: deviceId,
            kind: kind,
            state: state,
            message: message ?? defaultMessage(for: kind, state: state)
        )
        statuses[key(deviceId: deviceId, kind: kind)] = status
        save()
    }

    private func key(deviceId: String, kind: SmartHomeIntegrationKind) -> String {
        "\(deviceId)|\(kind.rawValue)"
    }

    private func defaultState(for kind: SmartHomeIntegrationKind) -> SmartHomeIntegrationState {
        switch kind {
        case .alexa, .homeAssistant, .mqtt:
            return .notSetUp
        case .appleHome, .googleHome:
            return .requiresBridge
        }
    }

    private func defaultMessage(for kind: SmartHomeIntegrationKind) -> String? {
        defaultMessage(for: kind, state: defaultState(for: kind))
    }

    private func defaultMessage(for kind: SmartHomeIntegrationKind, state: SmartHomeIntegrationState) -> String? {
        switch (kind, state) {
        case (.alexa, .enabled):
            return "Alexa setup saved. Open the Alexa app and run Discover Devices."
        case (.alexa, .notSetUp):
            return "Set up Alexa to control power, brightness, color, and favorite presets."
        case (.alexa, .needsSync):
            return "Alexa favorites changed. Save Alexa setup to sync WLED."
        case (.alexa, .conflict):
            return "WLED Alexa preset slots already contain presets."
        case (.homeAssistant, .notSetUp):
            return "Home Assistant support will use WLED discovery first."
        case (.appleHome, .requiresBridge):
            return "Apple Home will require a Home Assistant or Homebridge bridge."
        case (.googleHome, .requiresBridge):
            return "Google Home will require a Home Assistant bridge."
        case (.mqtt, .notSetUp):
            return "MQTT is planned for advanced local automation."
        default:
            return nil
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SmartHomeIntegrationStatus].self, from: data) else {
            return
        }
        statuses = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
