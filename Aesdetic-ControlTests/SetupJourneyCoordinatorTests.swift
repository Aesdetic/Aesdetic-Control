import Foundation
import Testing
@testable import Aesdetic_Control

private final class FirstLaunchSetupStoreSpy: FirstLaunchSetupStoring {
    var isComplete: Bool
    private(set) var markCompleteCalls = 0

    init(isComplete: Bool = false) {
        self.isComplete = isComplete
    }

    func markComplete() {
        isComplete = true
        markCompleteCalls += 1
    }
}

@Suite
@MainActor
struct SetupJourneyCoordinatorTests {
    @Test func freshInstallOffersSkippableFirstDeviceSetup() {
        let store = FirstLaunchSetupStoreSpy()
        let coordinator = SetupJourneyCoordinator(firstLaunchStore: store)

        coordinator.presentFirstLaunchIfNeeded(hasPersistedDevices: false)

        guard case .welcome = coordinator.stage else {
            Issue.record("Expected the welcome stage")
            return
        }
        #expect(coordinator.entryContext == .firstLaunch)

        coordinator.skipFirstLaunch()
        #expect(!coordinator.isActive)
        #expect(store.markCompleteCalls == 1)
    }

    @Test func existingUsersAreMigratedWithoutSeeingFirstLaunch() {
        let store = FirstLaunchSetupStoreSpy()
        let coordinator = SetupJourneyCoordinator(firstLaunchStore: store)

        coordinator.presentFirstLaunchIfNeeded(hasPersistedDevices: true)

        #expect(!coordinator.isActive)
        #expect(store.markCompleteCalls == 1)
    }

    @Test func cancellingFirstLaunchSetupReturnsToWelcome() {
        let coordinator = SetupJourneyCoordinator(firstLaunchStore: FirstLaunchSetupStoreSpy())
        coordinator.presentFirstLaunchIfNeeded(hasPersistedDevices: false)
        coordinator.beginFirstDeviceSetup()

        guard case .provisioning = coordinator.stage else {
            Issue.record("Expected provisioning")
            return
        }
        #expect(coordinator.isProvisioningActive)

        coordinator.cancelCurrentStage()
        guard case .welcome = coordinator.stage else {
            Issue.record("Expected cancellation to return to welcome")
            return
        }
        #expect(!coordinator.isProvisioningActive)
    }

    @Test func completedFirstLaunchDoesNotPresentAgain() {
        let coordinator = SetupJourneyCoordinator(
            firstLaunchStore: FirstLaunchSetupStoreSpy(isComplete: true)
        )

        coordinator.presentFirstLaunchIfNeeded(hasPersistedDevices: false)

        #expect(!coordinator.isActive)
    }
}
