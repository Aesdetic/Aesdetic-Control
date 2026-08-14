import Foundation
import SwiftUI

final class SetupJourneyActions {
    var beginProductSetup: @MainActor (WLEDDevice, String?) -> Void = { _, _ in }

    init(
        beginProductSetup: @escaping @MainActor (WLEDDevice, String?) -> Void = { _, _ in }
    ) {
        self.beginProductSetup = beginProductSetup
    }
}

private struct SetupJourneyActionsKey: EnvironmentKey {
    static let defaultValue = SetupJourneyActions()
}

extension EnvironmentValues {
    var setupJourneyActions: SetupJourneyActions {
        get { self[SetupJourneyActionsKey.self] }
        set { self[SetupJourneyActionsKey.self] = newValue }
    }
}

struct ProductSetupCompletion {
    let canonicalDeviceID: String
    let device: WLEDDevice
    let productImageName: String
    let deviceName: String
    let roomName: String
    let initialColorHex: String
}

protocol FirstLaunchSetupStoring: AnyObject {
    var isComplete: Bool { get }
    func markComplete()
}

final class UserDefaultsFirstLaunchSetupStore: FirstLaunchSetupStoring {
    static let shared = UserDefaultsFirstLaunchSetupStore()
    static let completionKey = "SetupJourney.firstLaunchCompleted.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isComplete: Bool {
        defaults.bool(forKey: Self.completionKey)
    }

    func markComplete() {
        defaults.set(true, forKey: Self.completionKey)
    }
}

@MainActor
final class SetupJourneyCoordinator: ObservableObject {
    enum EntryContext: Equatable {
        case firstLaunch
        case addDevice
        case reconnect
        case pendingProductSetup
    }

    enum Stage {
        case welcome
        case provisioning(id: UUID, purpose: WLEDProvisioningPurpose)
        case productSetup(id: UUID, result: WLEDProvisioningResult)
        case success(ProductSetupCompletion)
    }

    @Published private(set) var stage: Stage?
    @Published private(set) var entryContext: EntryContext?

    private let firstLaunchStore: any FirstLaunchSetupStoring

    init(firstLaunchStore: any FirstLaunchSetupStoring = UserDefaultsFirstLaunchSetupStore.shared) {
        self.firstLaunchStore = firstLaunchStore
    }

    var isActive: Bool { stage != nil }

    var isProvisioningActive: Bool {
        guard case .provisioning = stage else { return false }
        return true
    }

    func presentFirstLaunchIfNeeded(hasPersistedDevices: Bool) {
        guard stage == nil, !firstLaunchStore.isComplete else { return }
        if hasPersistedDevices {
            firstLaunchStore.markComplete()
            return
        }
        entryContext = .firstLaunch
        stage = .welcome
    }

    func beginFirstDeviceSetup() {
        entryContext = .firstLaunch
        stage = .provisioning(id: UUID(), purpose: .addDevice)
    }

    func skipFirstLaunch() {
        firstLaunchStore.markComplete()
        stage = nil
        entryContext = nil
    }

    func beginAddDevice() {
        entryContext = .addDevice
        stage = .provisioning(id: UUID(), purpose: .addDevice)
    }

    func beginReconnect(_ device: WLEDDevice) {
        entryContext = .reconnect
        stage = .provisioning(id: UUID(), purpose: .reconnect(device))
    }

    func beginProductSetup(device: WLEDDevice, provisionedSSID: String? = nil) {
        entryContext = .pendingProductSetup
        let result = WLEDProvisioningResult(
            device: device,
            configuredSSID: provisionedSSID,
            wifiConfiguredDuringFlow: provisionedSSID != nil,
            purpose: .addDevice
        )
        stage = .productSetup(id: UUID(), result: result)
    }

    func handleProvisioningResult(_ result: WLEDProvisioningResult) {
        if result.shouldBeginProductSetup {
            stage = .productSetup(id: UUID(), result: result)
        } else {
            dismiss()
        }
    }

    func handleProductSetupCompletion(_ completion: ProductSetupCompletion) {
        firstLaunchStore.markComplete()
        stage = .success(completion)
    }

    func cancelCurrentStage() {
        if entryContext == .firstLaunch {
            stage = .welcome
        } else {
            dismiss()
        }
    }

    func dismiss() {
        stage = nil
        entryContext = nil
    }
}
