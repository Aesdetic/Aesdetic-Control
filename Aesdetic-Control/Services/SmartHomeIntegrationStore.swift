import Foundation
import Combine

@MainActor
final class SmartHomeIntegrationStore: ObservableObject {
    static let shared = SmartHomeIntegrationStore()

    @Published private(set) var statuses: [String: SmartHomeIntegrationStatus] = [:]
    @Published private(set) var homeAssistantSetupStates: [String: HomeAssistantSetupState] = [:]

    private let storageKey = "aesdetic_smart_home_integration_statuses_v1"
    private let homeAssistantStorageKey = "aesdetic_home_assistant_setup_states_v1"

    private init() {
        load()
        loadHomeAssistantSetupStates()
    }

    func status(for kind: SmartHomeIntegrationKind, deviceId: String) -> SmartHomeIntegrationStatus {
        if kind == .homeAssistant {
            let setup = homeAssistantSetup(for: deviceId)
            return SmartHomeIntegrationStatus(
                deviceId: deviceId,
                kind: kind,
                state: setup.integrationState,
                message: setup.integrationMessage,
                updatedAt: setup.updatedAt,
                verificationSource: setup.hasStartedSetup ? .savedInApp : .notVerified
            )
        }

        return statuses[key(deviceId: deviceId, kind: kind)] ?? SmartHomeIntegrationStatus(
            deviceId: deviceId,
            kind: kind,
            state: defaultState(for: kind),
            message: defaultMessage(for: kind),
            verificationSource: .notVerified
        )
    }

    func setStatus(
        _ state: SmartHomeIntegrationState,
        for kind: SmartHomeIntegrationKind,
        deviceId: String,
        message: String? = nil,
        verificationSource: SmartHomeVerificationSource = .savedInApp
    ) {
        let status = SmartHomeIntegrationStatus(
            deviceId: deviceId,
            kind: kind,
            state: state,
            message: message ?? defaultMessage(for: kind, state: state),
            verificationSource: verificationSource
        )
        statuses[key(deviceId: deviceId, kind: kind)] = status
        save()
    }

    func homeAssistantSetup(for deviceId: String) -> HomeAssistantSetupState {
        homeAssistantSetupStates[deviceId] ?? HomeAssistantSetupState(deviceId: deviceId)
    }

    func setHomeAssistantSetup(_ setup: HomeAssistantSetupState) {
        var updated = setup
        updated.updatedAt = Date()
        homeAssistantSetupStates[updated.deviceId] = updated
        saveHomeAssistantSetupStates()
    }

    func updateHomeAssistantSetup(
        for deviceId: String,
        _ update: (inout HomeAssistantSetupState) -> Void
    ) {
        var setup = homeAssistantSetup(for: deviceId)
        update(&setup)
        setHomeAssistantSetup(setup)
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
        case (.homeAssistant, .enabled):
            return "Home Assistant bridge setup is marked complete."
        case (.homeAssistant, .inProgress):
            return "Finish the Home Assistant checklist, then expose only the main light to Apple Home, Alexa, or Google."
        case (.alexa, .notSetUp):
            return "Set up Alexa to control power, brightness, color, and favorite presets."
        case (.alexa, .needsSync):
            return "Alexa favorites changed. Save Alexa setup to sync WLED."
        case (.alexa, .conflict):
            return "WLED Alexa preset slots already contain presets."
        case (.alexa, .unsupported):
            return "This WLED firmware build does not include Alexa support."
        case (.homeAssistant, .notSetUp):
            return "Use Home Assistant's native WLED integration; Aesdetic will guide segment cleanup."
        case (.homeAssistant, .conflict):
            return "Segment entities still need review. Hide them in Home Assistant and keep the main light."
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

    private func loadHomeAssistantSetupStates() {
        guard let data = UserDefaults.standard.data(forKey: homeAssistantStorageKey),
              let decoded = try? JSONDecoder().decode([String: HomeAssistantSetupState].self, from: data) else {
            return
        }
        homeAssistantSetupStates = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func saveHomeAssistantSetupStates() {
        guard let data = try? JSONEncoder().encode(homeAssistantSetupStates) else { return }
        UserDefaults.standard.set(data, forKey: homeAssistantStorageKey)
    }
}
