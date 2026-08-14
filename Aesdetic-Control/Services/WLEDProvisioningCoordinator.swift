import AccessorySetupKit
import Combine
import Foundation
import NetworkExtension
import os.log
import UIKit

struct WLEDHomeWiFiCredentials: Equatable {
    var ssid = ""
    var password = ""
    var isOpenNetwork = false

    var normalizedSSID: String {
        ssid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        (1...32).contains(normalizedSSID.count) &&
            (isOpenNetwork || (8...64).contains(password.count))
    }

    mutating func clearPassword() {
        password = ""
    }

    func matchingNetwork(in networks: [WiFiNetwork]) -> WiFiNetwork? {
        networks.first { $0.ssid == normalizedSSID }
    }
}

struct WLEDProvisioningResult {
    let device: WLEDDevice
    let configuredSSID: String?
    let wifiConfiguredDuringFlow: Bool
    let purpose: WLEDProvisioningPurpose

    var shouldBeginProductSetup: Bool {
        purpose == .addDevice
    }
}

enum WLEDProvisioningPurpose: Equatable {
    case addDevice
    case reconnect(WLEDDevice)

    var existingDevice: WLEDDevice? {
        guard case .reconnect(let device) = self else { return nil }
        return device
    }
}

struct WLEDHomeWiFiCorrection: Equatable {
    let selectedSSID: String?
    let isOpenNetwork: Bool
    let message: String
}

protocol WLEDWiFiConfiguring {
    func scanForNetworks(device: WLEDDevice) async throws -> [WiFiNetwork]
    func connectToNetwork(device: WLEDDevice, ssid: String, password: String?) async throws
}

extension WLEDWiFiService: WLEDWiFiConfiguring {}

protocol WLEDProvisioningDiscovering {
    func startTargetedDiscovery()
    func restartTargetedDiscovery()
}

private struct WLEDProvisioningDiscoveryAdapter: WLEDProvisioningDiscovering {
    let service: WLEDDiscoveryService

    func startTargetedDiscovery() {
        service.startDiscovery()
    }

    func restartTargetedDiscovery() {
        service.stopDiscovery()
        service.startDiscovery()
    }
}

protocol WLEDProvisioningClock {
    var now: Date { get }
    func sleep(for interval: TimeInterval) async throws
}

@MainActor
protocol WLEDProvisioningApplicationStateProviding {
    var isActive: Bool { get }
}

private struct SystemWLEDProvisioningApplicationStateProvider: WLEDProvisioningApplicationStateProviding {
    var isActive: Bool {
        UIApplication.shared.applicationState == .active
    }
}

private struct SystemWLEDProvisioningClock: WLEDProvisioningClock {
    var now: Date { Date() }

    func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

struct WLEDProvisioningFailure: Equatable {
    enum RecoveryFocus: Equatable {
        case wifiDetails
        case deviceFinding
        case either
    }

    let recoveryFocus: RecoveryFocus
    let message: String
}

@MainActor
final class WLEDProvisioningCoordinator: ObservableObject {
    enum AccessoryPickerFailureResolution: Equatable {
        case returnToCredentials
        case retryWhenActive
        case tryDirectSetupConnection
        case fail
    }

    enum PresentationState: Equatable {
        case credentials
        case devicePageNotice
        case connecting
        case finishing
        case takingLonger
        case correction
        case failure
        case candidates
    }

    enum Phase: Equatable {
        case idle
        case discoveringLAN
        case devicesFound
        case collectingHomeWiFi
        case presentingAccessoryPicker
        case preparingDevicePage
        case joiningAccessPoint
        case probingAccessPoint
        case verifyingHomeWiFi
        case correctingHomeWiFi
        case applyingHomeWiFi
        case returningToHomeNetwork
        case rediscovering
        case rediscoveryTakingLonger
        case recoveringSetupConnection
        case failed(WLEDProvisioningFailure)

        var title: String {
            switch self {
            case .idle:
                return "Add Device"
            case .discoveringLAN:
                return "Looking for Devices"
            case .devicesFound:
                return "Device Found"
            case .collectingHomeWiFi:
                return "Choose Home Wi-Fi"
            case .presentingAccessoryPicker:
                return "Finding Your Device"
            case .preparingDevicePage:
                return "Connecting"
            case .joiningAccessPoint:
                return "Connecting to Your Device"
            case .probingAccessPoint:
                return "Checking Connection"
            case .verifyingHomeWiFi:
                return "Checking Home Wi-Fi"
            case .correctingHomeWiFi:
                return "Confirm Home Wi-Fi"
            case .applyingHomeWiFi:
                return "Saving Wi-Fi"
            case .returningToHomeNetwork:
                return "Returning to Home Wi-Fi"
            case .rediscovering:
                return "Finishing Setup"
            case .rediscoveryTakingLonger:
                return "Finishing Setup"
            case .recoveringSetupConnection:
                return "Checking Your Device"
            case .failed:
                return "Setup Needs Attention"
            }
        }

        var subtitle: String {
            switch self {
            case .idle:
                return "Preparing device setup."
            case .discoveringLAN:
                return "Looking for devices already connected to your home Wi-Fi."
            case .devicesFound:
                return "Select a device to continue product setup."
            case .collectingHomeWiFi:
                return "Choose the home Wi-Fi this device should use."
            case .presentingAccessoryPicker:
                return "Choose your nearby device when Apple's setup card appears."
            case .preparingDevicePage:
                return "A device page may appear briefly. You don’t need to do anything there. Setup will continue automatically."
            case .joiningAccessPoint:
                return "Your phone is making a temporary connection for setup."
            case .probingAccessPoint:
                return "Making sure your device is ready."
            case .verifyingHomeWiFi:
                return "Making sure your device can see your home Wi-Fi."
            case .correctingHomeWiFi:
                return "Select a visible network or continue with the entered network if it is hidden."
            case .applyingHomeWiFi:
                return "Connecting your device to your home Wi-Fi."
            case .returningToHomeNetwork:
                return "Your device may restart while it changes networks."
            case .rediscovering:
                return "Waiting for your device to appear on your home Wi-Fi."
            case .rediscoveryTakingLonger:
                return "This is taking longer than usual."
            case .recoveringSetupConnection:
                return "Your device has not appeared yet. Reconnecting to help you finish setup."
            case .failed(let failure):
                return failure.message
            }
        }

        var iconName: String {
            switch self {
            case .idle, .devicesFound:
                return "plus.circle"
            case .discoveringLAN, .rediscovering, .rediscoveryTakingLonger, .recoveringSetupConnection:
                return "dot.radiowaves.left.and.right"
            case .collectingHomeWiFi, .presentingAccessoryPicker, .preparingDevicePage, .joiningAccessPoint:
                return "wifi.router"
            case .probingAccessPoint, .verifyingHomeWiFi, .correctingHomeWiFi:
                return "wifi"
            case .applyingHomeWiFi, .returningToHomeNetwork:
                return "arrow.triangle.2.circlepath"
            case .failed:
                return "exclamationmark.triangle"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle {
        didSet {
            if case .failed = phase {
                homeWiFiCredentials.clearPassword()
                customAPPassword = ""
            }
        }
    }
    @Published private(set) var candidates: [WLEDDevice] = []
    @Published private(set) var availableNetworks: [WiFiNetwork] = []
    @Published private(set) var isLoadingCurrentSSID = false
    @Published private(set) var networkVerificationMessage: String?
    @Published private(set) var completedProvisioningResult: WLEDProvisioningResult?
    @Published var homeWiFiCredentials = WLEDHomeWiFiCredentials()
    @Published var selectedNetwork: WiFiNetwork?
    @Published var customAPSSID = ""
    @Published var customAPPassword = ""

    var presentationState: PresentationState {
        Self.presentationState(for: phase)
    }

    static func presentationState(for phase: Phase) -> PresentationState {
        switch phase {
        case .collectingHomeWiFi:
            return .credentials
        case .preparingDevicePage:
            return .devicePageNotice
        case .rediscovering:
            return .finishing
        case .rediscoveryTakingLonger:
            return .takingLonger
        case .correctingHomeWiFi:
            return .correction
        case .failed:
            return .failure
        case .devicesFound:
            return .candidates
        default:
            return .connecting
        }
    }

    private let viewModel: DeviceControlViewModel
    private let purpose: WLEDProvisioningPurpose
    private let accessPointService: any WLEDAccessPointProvisioning
    private let wifiService: any WLEDWiFiConfiguring
    private let currentWiFiProvider: any CurrentWiFiNetworkProviding
    private let discovery: any WLEDProvisioningDiscovering
    private let clock: any WLEDProvisioningClock
    private let applicationStateProvider: any WLEDProvisioningApplicationStateProviding
    private let apCandidateIPs = ["4.3.2.1", "192.168.4.1"]
    private let homeNetworkAssociationTimeout: TimeInterval = 10
    private let homeRediscoverySoftTimeout: TimeInterval = 30
    private let accessoryPickerForegroundRetryDelay: TimeInterval = 0.4
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "Provisioning")

    private var initialDeviceIDs = Set<String>()
    private var didStart = false
    private var expectedDeviceID: String?
    private var setupTargetDevice: WLEDDevice?
    private var joinedAccessPointSSID: String?
    private var activeTask: Task<Void, Never>?
    private var accessorySession: ASAccessorySession?
    private var isAccessorySessionActive = false
    private var shouldPresentAccessoryPicker = false
    private var pairedAccessory: ASAccessory?
    private var pendingAccessoryAfterPicker: ASAccessory?
    private var restoredAccessory: ASAccessory?
    private var authorizedAccessoryCount = 0
    private var joinedAccessPointWithAccessory = false
    private var configuredHomeSSID: String?
    private var homeWiFiSubmissionStartedAt: Date?
    private var homeRediscoveryStartedAt: Date?
    private var hasSubmittedCredentials = false
    private var isRecoveringAfterSystemWiFiUI = false
    private var provisioningAttemptID: UUID?
    private var completedProvisioningAttemptID: UUID?
    private var accessoryPickerForegroundRetryCount = 0
    private var accessoryPickerRetryTask: Task<Void, Never>?
    private var appBecameActiveObserver: NSObjectProtocol?
    private var appDidEnterBackgroundObserver: NSObjectProtocol?
    private var devicesCancellable: AnyCancellable?
    private var isCancelling = false

    init(
        viewModel: DeviceControlViewModel,
        purpose: WLEDProvisioningPurpose = .addDevice,
        accessPointService: any WLEDAccessPointProvisioning = WLEDAccessPointProvisioningService.shared,
        wifiService: any WLEDWiFiConfiguring = WLEDWiFiService.provisioning,
        currentWiFiProvider: (any CurrentWiFiNetworkProviding)? = nil,
        discovery: (any WLEDProvisioningDiscovering)? = nil,
        clock: (any WLEDProvisioningClock)? = nil,
        applicationStateProvider: (any WLEDProvisioningApplicationStateProviding)? = nil
    ) {
        self.viewModel = viewModel
        self.purpose = purpose
        self.accessPointService = accessPointService
        self.wifiService = wifiService
        self.currentWiFiProvider = currentWiFiProvider ?? CurrentWiFiNetworkProvider.shared
        self.discovery = discovery ?? WLEDProvisioningDiscoveryAdapter(service: viewModel.wledService)
        self.clock = clock ?? SystemWLEDProvisioningClock()
        self.applicationStateProvider = applicationStateProvider ?? SystemWLEDProvisioningApplicationStateProvider()
        observeApplicationLifecycle()
        observeDiscoveredDevices()
    }

    deinit {
        activeTask?.cancel()
        accessoryPickerRetryTask?.cancel()
        accessorySession?.invalidate()
        if let appBecameActiveObserver {
            NotificationCenter.default.removeObserver(appBecameActiveObserver)
        }
        if let appDidEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(appDidEnterBackgroundObserver)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        logger.info("Provisioning flow started")
        initialDeviceIDs = Set(viewModel.devices.map(\.id))
        if let existingDevice = purpose.existingDevice {
            expectedDeviceID = WLEDDeviceIdentity.canonicalID(for: existingDevice.id)
        }
        candidates = pendingSetupCandidates()
        activateAccessorySession()

        if purpose.existingDevice != nil {
            beginNewDeviceSetup()
            return
        }

        if candidates.count == 1, let device = candidates.first {
            completeWithAlreadyConnectedDevice(device)
        } else if candidates.isEmpty {
            beginNewDeviceSetup()
        } else {
            phase = .devicesFound
        }
    }

    func cancel() {
        isCancelling = true
        activeTask?.cancel()
        activeTask = nil
        accessoryPickerRetryTask?.cancel()
        accessoryPickerRetryTask = nil
        homeWiFiCredentials.clearPassword()
        customAPPassword = ""
        accessorySession?.invalidate()
        accessorySession = nil
        removeApplicationLifecycleObserver()
    }

    func discoverOnCurrentNetwork() {
        activeTask?.cancel()
        phase = .discoveringLAN
        candidates = []
        discovery.startTargetedDiscovery()

        activeTask = Task { [weak self] in
            guard let self else { return }
            let deadline = clock.now.addingTimeInterval(3)
            while !Task.isCancelled && clock.now < deadline {
                let found = pendingSetupCandidates()
                if !found.isEmpty {
                    handlePendingCandidates(found)
                    return
                }
                try? await clock.sleep(for: 0.25)
            }
            guard !Task.isCancelled else { return }
            candidates = pendingSetupCandidates()
            if candidates.count == 1, let device = candidates.first {
                completeWithAlreadyConnectedDevice(device)
            } else if candidates.isEmpty {
                beginNewDeviceSetup()
            } else {
                phase = .devicesFound
            }
        }
    }

    func beginNewDeviceSetup() {
        activeTask?.cancel()
        accessoryPickerRetryTask?.cancel()
        accessoryPickerRetryTask = nil
        hasSubmittedCredentials = false
        homeWiFiSubmissionStartedAt = nil
        homeRediscoveryStartedAt = nil
        provisioningAttemptID = nil
        completedProvisioningAttemptID = nil
        accessoryPickerForegroundRetryCount = 0
        phase = .collectingHomeWiFi
        networkVerificationMessage = nil
        loadCurrentSSID()
    }

    func addManualDevice(ipAddress: String) {
        let ipAddress = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ipAddress.isEmpty else { return }

        activeTask?.cancel()
        phase = .discoveringLAN
        viewModel.addDeviceByIP(ipAddress)
        activeTask = Task { [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: 2)
            guard !Task.isCancelled else { return }
            candidates = pendingSetupCandidates()
            phase = candidates.isEmpty
                ? .failed(.init(
                    recoveryFocus: .deviceFinding,
                    message: "No device responded at that address. Check it and try again."
                ))
                : .devicesFound
        }
    }

    func showAccessoryPicker() {
        guard homeWiFiCredentials.isValid else {
            phase = .collectingHomeWiFi
            return
        }
        beginProvisioningAttemptIfNeeded()
        hasSubmittedCredentials = true
        shouldPresentAccessoryPicker = true
        accessoryPickerForegroundRetryCount = 0
        continuePendingAccessorySetupWhenReady()
    }

    private func continuePendingAccessorySetupWhenReady() {
        guard shouldPresentAccessoryPicker else { return }
        guard applicationStateProvider.isActive else {
            phase = .presentingAccessoryPicker
            logger.info("Waiting for the app to become active before presenting the accessory picker")
            return
        }
        if let restoredAccessory,
           let ssid = restoredAccessory.ssid,
           Self.shouldReuseAuthorizedAccessory(
               authorizedCount: authorizedAccessoryCount,
               restoredSSID: ssid
           ) {
            shouldPresentAccessoryPicker = false
            pendingAccessoryAfterPicker = nil
            pairedAccessory = restoredAccessory
            logger.info("Reusing the previously authorized setup accessory with SSID \(ssid, privacy: .public)")
            prepareForDevicePageThenJoin(restoredAccessory, ssid: ssid)
            return
        }
        if authorizedAccessoryCount > 1 {
            logger.info("Multiple authorized setup accessories found; asking Apple to select the nearby device")
        }
        guard isAccessorySessionActive else { return }
        presentAccessoryPicker()
    }

    private func beginProvisioningAttemptIfNeeded() {
        guard provisioningAttemptID == nil else { return }
        let attemptID = UUID()
        provisioningAttemptID = attemptID
        completedProvisioningAttemptID = nil
        homeWiFiSubmissionStartedAt = clock.now
        homeRediscoveryStartedAt = nil
        logger.info("Provisioning attempt \(attemptID.uuidString, privacy: .public) accepted")
    }

    var canReconnectSelectedAccessory: Bool {
        pairedAccessory?.ssid != nil || restoredAccessory?.ssid != nil
    }

    var canResumeAuthorizedAccessory: Bool {
        restoredAccessory?.ssid != nil
    }

    func resumeAuthorizedAccessory() {
        guard homeWiFiCredentials.isValid,
              let restoredAccessory,
              let ssid = restoredAccessory.ssid else {
            phase = .collectingHomeWiFi
            return
        }
        pairedAccessory = restoredAccessory
        logger.info("Explicitly resuming a previously authorized setup accessory with SSID \(ssid, privacy: .public)")
        joinAccessoryAccessPoint(restoredAccessory, ssid: ssid)
    }

    var canBeginAccessorySetup: Bool {
        homeWiFiCredentials.isValid
    }

    var requiresCancellationConfirmation: Bool {
        hasSubmittedCredentials && completedProvisioningResult == nil
    }

    var accessoryPickerMessage: String {
        if authorizedAccessoryCount > 1, pairedAccessory == nil {
            return "More than one of your devices is ready. Apple will ask you to choose the nearby device you want to set up."
        }
        return "Apple may briefly open a device page. Close it using the X to return here. Setup will continue automatically."
    }

    var needsHomeWiFiCorrection: Bool {
        configuredHomeSSID != nil && setupTargetDevice != nil
    }

    func setHomeWiFiOpenNetwork(_ isOpen: Bool) {
        homeWiFiCredentials.isOpenNetwork = isOpen
        if isOpen {
            homeWiFiCredentials.clearPassword()
        }
    }

    var canContinueAccessPointSetup: Bool {
        setupTargetDevice == nil && joinedAccessPointSSID != nil
    }

    func continueAccessPointSetup() {
        guard canContinueAccessPointSetup else { return }
        reconnectAndProbeAccessPoint()
    }

    func joinStandardAccessPoint() {
        guard canBeginAccessorySetup else {
            phase = .collectingHomeWiFi
            return
        }
        joinAccessPoint(ssid: WLEDAccessPointProvisioningRequest.standard.ssid, password: WLEDAccessPointProvisioningRequest.standard.password)
    }

    func joinCustomAccessPoint() {
        let ssid = customAPSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = customAPPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canBeginAccessorySetup, !ssid.isEmpty, password.count >= 8 else {
            phase = .failed(.init(
                recoveryFocus: .wifiDetails,
                message: "Enter a setup network name and an eight-character password."
            ))
            return
        }
        joinAccessPoint(ssid: ssid, password: password)
    }

    func selectHomeNetwork(_ network: WiFiNetwork) {
        selectedNetwork = network
        homeWiFiCredentials.ssid = network.ssid
        homeWiFiCredentials.isOpenNetwork = Self.isOpenNetwork(network)
        homeWiFiCredentials.clearPassword()
        networkVerificationMessage = nil
    }

    func refreshHomeNetworks() {
        guard let setupTargetDevice else { return }
        scanHomeNetworksForCorrection(from: setupTargetDevice)
    }

    func useEnteredHomeNetwork() {
        guard homeWiFiCredentials.isValid else {
            networkVerificationMessage = "Enter a Wi-Fi password or mark this as a network without a password."
            return
        }
        applyHomeWiFi()
    }

    func editHomeWiFiAfterFailure() {
        homeWiFiCredentials.clearPassword()
        beginNewDeviceSetup()
    }

    func findProvisionedDeviceAgain() {
        guard provisioningAttemptID != nil, expectedDeviceID != nil else {
            discoverOnCurrentNetwork()
            return
        }
        logger.info(
            "User requested another exact-device discovery pass for attempt \(self.provisioningAttemptID?.uuidString ?? "unknown", privacy: .public)"
        )
        restartLANDiscovery()
        phase = .rediscoveryTakingLonger
    }

    func provisioningResult(for device: WLEDDevice) -> WLEDProvisioningResult {
        let wasConfigured = configuredHomeSSID != nil &&
            expectedDeviceID?.caseInsensitiveCompare(device.id) == .orderedSame
        return WLEDProvisioningResult(
            device: device,
            configuredSSID: wasConfigured ? configuredHomeSSID : nil,
            wifiConfiguredDuringFlow: wasConfigured,
            purpose: purpose
        )
    }

    private func applyHomeWiFi() {
        guard let setupTargetDevice, homeWiFiCredentials.isValid else { return }
        let ssid = homeWiFiCredentials.normalizedSSID
        let password = homeWiFiCredentials.isOpenNetwork ? nil : homeWiFiCredentials.password
        activeTask?.cancel()
        beginProvisioningAttemptIfNeeded()
        phase = .applyingHomeWiFi
        logger.info("Applying home Wi-Fi SSID \(ssid, privacy: .public) to WLED \(setupTargetDevice.id, privacy: .public)")

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await wifiService.connectToNetwork(
                    device: setupTargetDevice,
                    ssid: ssid,
                    password: password
                )
                guard !Task.isCancelled else { return }
                configuredHomeSSID = ssid
                homeWiFiCredentials.clearPassword()
                await returnToHomeNetworkAndRediscover()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if Self.shouldVerifyAfterConnectionInterruption(error) {
                    configuredHomeSSID = ssid
                    homeWiFiCredentials.clearPassword()
                    await returnToHomeNetworkAndRediscover()
                } else {
                    logger.error("WLED Wi-Fi update failed: \(error.localizedDescription, privacy: .public)")
                    phase = .failed(.init(
                        recoveryFocus: .wifiDetails,
                        message: "Your device could not join the home Wi-Fi. Check the password and try again."
                    ))
                }
            }
        }
    }

    func retry() {
        switch phase {
        case .failed:
            if setupTargetDevice != nil {
                refreshHomeNetworks()
            } else {
                discoverOnCurrentNetwork()
            }
        default:
            discoverOnCurrentNetwork()
        }
    }

    private func loadCurrentSSID() {
        guard homeWiFiCredentials.normalizedSSID.isEmpty else { return }
        isLoadingCurrentSSID = true
        activeTask = Task { [weak self] in
            guard let self else { return }
            let ssid = await currentWiFiProvider.currentSSID(requestPermissionIfNeeded: true)
            guard !Task.isCancelled else { return }
            if let ssid, homeWiFiCredentials.normalizedSSID.isEmpty {
                homeWiFiCredentials.ssid = ssid
                logger.info("Prefilled current home Wi-Fi SSID \(ssid, privacy: .public)")
            }
            isLoadingCurrentSSID = false
        }
    }

    private func activateAccessorySession() {
        logger.info("Activating Apple accessory session")
        let session = ASAccessorySession()
        accessorySession = session
        session.activate(on: .main) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handleAccessoryEvent(event)
            }
        }
    }

    private func presentAccessoryPicker() {
        guard let accessorySession else {
            phase = .failed(.init(
                recoveryFocus: .deviceFinding,
                message: "The device finder is not available. Open Setup Help and try the standard connection."
            ))
            return
        }
        guard applicationStateProvider.isActive else {
            shouldPresentAccessoryPicker = true
            phase = .presentingAccessoryPicker
            logger.info("Accessory picker presentation deferred because the app is not active")
            return
        }
        shouldPresentAccessoryPicker = false
        phase = .presentingAccessoryPicker
        logger.info(
            "Presenting Apple accessory picker for attempt \(self.provisioningAttemptID?.uuidString ?? "unknown", privacy: .public)"
        )

        let descriptor = ASDiscoveryDescriptor()
        descriptor.ssidPrefix = "WLED-"
        let productImage = UIImage(named: "product_image") ?? UIImage(systemName: "lightbulb.fill")!
        let item = ASPickerDisplayItem(name: "Aesdetic Device", productImage: productImage, descriptor: descriptor)
        item.setupOptions = [.finishInApp]
        accessorySession.showPicker(for: [item]) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, self.phase == .presentingAccessoryPicker else { return }
                let pickerError = error as NSError
                self.logger.error(
                    "Apple accessory picker failed with code \(pickerError.code, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )

                switch Self.accessoryPickerFailureResolution(
                    errorCode: pickerError.code,
                    foregroundRetryCount: self.accessoryPickerForegroundRetryCount
                ) {
                case .returnToCredentials:
                    self.hasSubmittedCredentials = false
                    self.homeWiFiSubmissionStartedAt = nil
                    self.homeRediscoveryStartedAt = nil
                    self.provisioningAttemptID = nil
                    self.phase = .collectingHomeWiFi
                case .retryWhenActive:
                    self.accessoryPickerForegroundRetryCount += 1
                    self.shouldPresentAccessoryPicker = true
                    self.phase = .presentingAccessoryPicker
                    self.scheduleAccessoryPickerForegroundRetry()
                case .tryDirectSetupConnection:
                    self.logger.info("Trying the standard setup connection after accessory picker failure")
                    self.joinStandardAccessPoint()
                case .fail:
                    self.phase = .failed(.init(
                        recoveryFocus: .deviceFinding,
                        message: "Device finding is unavailable. Check Setup Help and try again."
                    ))
                }
            }
        }
    }

    private func handleAccessoryEvent(_ event: ASAccessoryEvent) {
        let eventName = String(describing: event.eventType)
        logger.info("Accessory event: \(eventName, privacy: .public)")
        switch event.eventType {
        case .activated:
            isAccessorySessionActive = true
            restoreAuthorizedAccessory()
            if shouldPresentAccessoryPicker {
                continuePendingAccessorySetupWhenReady()
            }
        case .accessoryAdded:
            guard let accessory = event.accessory, let ssid = accessory.ssid else {
                logger.error("Apple added a setup accessory without a Wi-Fi network")
                return
            }
            pairedAccessory = accessory
            pendingAccessoryAfterPicker = accessory
            logger.info("Apple selected setup accessory with SSID \(ssid, privacy: .public)")
            guard homeWiFiCredentials.isValid,
                  Self.shouldStartAccessoryJoin(afterAddedIn: phase) else {
                return
            }
        case .accessoryChanged:
            guard let accessory = event.accessory else { return }
            if pairedAccessory === accessory {
                pairedAccessory = accessory
            }
            restoreAuthorizedAccessory()
        case .accessoryRemoved:
            if let accessory = event.accessory {
                if pairedAccessory === accessory {
                    pairedAccessory = nil
                }
                if restoredAccessory === accessory {
                    restoredAccessory = nil
                }
            }
            restoreAuthorizedAccessory()
        case .pickerSetupFailed:
            let detail = event.error?.localizedDescription ?? "The device could not be prepared."
            logger.error("Apple accessory setup failed: \(detail, privacy: .public)")
            phase = .failed(.init(
                recoveryFocus: .deviceFinding,
                message: "The device could not be connected. Keep it powered on and try again."
            ))
        case .invalidated:
            isAccessorySessionActive = false
            guard !isCancelling else { return }
            let detail = event.error?.localizedDescription ?? "Accessory session invalidated"
            logger.error("Apple accessory session invalidated: \(detail, privacy: .public)")
            phase = .failed(.init(
                recoveryFocus: .deviceFinding,
                message: "Device finding stopped unexpectedly. Try again."
            ))
        case .pickerDidDismiss:
            accessoryPickerRetryTask?.cancel()
            accessoryPickerRetryTask = nil
            if let accessory = pendingAccessoryAfterPicker,
               let ssid = accessory.ssid,
               homeWiFiCredentials.isValid {
                pendingAccessoryAfterPicker = nil
                prepareForDevicePageThenJoin(accessory, ssid: ssid)
            } else if phase == .presentingAccessoryPicker {
                pendingAccessoryAfterPicker = nil
                hasSubmittedCredentials = false
                homeWiFiSubmissionStartedAt = nil
                homeRediscoveryStartedAt = nil
                provisioningAttemptID = nil
                phase = .collectingHomeWiFi
            } else {
                pendingAccessoryAfterPicker = nil
            }
        default:
            break
        }
    }

    static func shouldStartAccessoryJoin(afterAddedIn phase: Phase) -> Bool {
        phase == .presentingAccessoryPicker || phase == .collectingHomeWiFi
    }

    private func scheduleAccessoryPickerForegroundRetry() {
        accessoryPickerRetryTask?.cancel()
        accessoryPickerRetryTask = Task { [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.accessoryPickerForegroundRetryDelay)
            guard !Task.isCancelled else { return }
            self.continuePendingAccessorySetupWhenReady()
        }
    }

    private func prepareForDevicePageThenJoin(_ accessory: ASAccessory, ssid: String) {
        activeTask?.cancel()
        beginProvisioningAttemptIfNeeded()
        phase = .preparingDevicePage
        activeTask = Task { [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: 1.25)
            guard !Task.isCancelled else { return }
            joinAccessoryAccessPoint(accessory, ssid: ssid)
        }
    }

    private func joinAccessPoint(ssid: String, password: String) {
        activeTask?.cancel()
        hasSubmittedCredentials = true
        beginProvisioningAttemptIfNeeded()
        phase = .joiningAccessPoint
        logger.info("Joining setup network directly with SSID \(ssid, privacy: .public)")
        availableNetworks = []
        selectedNetwork = nil
        joinedAccessPointSSID = ssid
        joinedAccessPointWithAccessory = false

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await accessPointService.joinAccessPoint(
                    WLEDAccessPointProvisioningRequest(ssid: ssid, password: password, useSSIDPrefix: false)
                )
                guard !Task.isCancelled else { return }
                logger.info("Direct setup network join completed")
                beginAccessPointProbe()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Direct setup network join failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(.init(recoveryFocus: .either, message: error.localizedDescription))
            }
        }
    }

    private func joinAccessoryAccessPoint(_ accessory: ASAccessory, ssid: String) {
        activeTask?.cancel()
        hasSubmittedCredentials = true
        beginProvisioningAttemptIfNeeded()
        phase = .joiningAccessPoint
        logger.info("Joining authorized accessory network with SSID \(ssid, privacy: .public)")
        availableNetworks = []
        selectedNetwork = nil
        joinedAccessPointSSID = ssid
        joinedAccessPointWithAccessory = true

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await accessPointService.joinAccessoryAccessPoint(
                    accessory,
                    password: WLEDAccessPointProvisioningRequest.standard.password
                )
                guard !Task.isCancelled else { return }
                logger.info("Authorized accessory network join completed")
                beginAccessPointProbe()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Authorized accessory network join failed: \(error.localizedDescription, privacy: .public)")
                if Self.shouldTryDirectSetupConnection(afterAuthorizedJoinError: error) {
                    logger.info("Authorized setup connection is stale; trying a direct connection to \(ssid, privacy: .public)")
                    joinAccessPoint(
                        ssid: ssid,
                        password: WLEDAccessPointProvisioningRequest.standard.password
                    )
                } else {
                    phase = .failed(.init(recoveryFocus: .either, message: error.localizedDescription))
                }
            }
        }
    }

    private func probeAccessPoint(
        maxProbePasses: Int = 16,
        expectedDeviceID requiredDeviceID: String? = nil
    ) async throws -> WLEDDevice {
        var lastError: Error?
        logger.info("Probing WLED setup network")

        for probePass in 1...maxProbePasses {
            guard !Task.isCancelled else { throw CancellationError() }
            for ipAddress in apCandidateIPs {
                do {
                    let device = try await fetchWLEDDevice(at: ipAddress)
                    if let requiredDeviceID,
                       device.id.caseInsensitiveCompare(requiredDeviceID) != .orderedSame {
                        logger.error(
                            "Ignoring setup device with unexpected MAC \(device.id, privacy: .public); expected \(requiredDeviceID, privacy: .public)"
                        )
                        lastError = ProvisioningError.unexpectedDevice
                        continue
                    }
                    logger.info("Verified WLED setup device \(device.id, privacy: .public) at \(ipAddress, privacy: .public)")
                    return device
                } catch {
                    logger.debug("WLED probe failed at \(ipAddress, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    lastError = error
                }
            }
            guard probePass < maxProbePasses else { break }
            try? await clock.sleep(for: 0.75)
        }

        if Task.isCancelled { throw CancellationError() }
        throw lastError ?? ProvisioningError.wledNotReachable
    }

    private func beginAccessPointProbe() {
        phase = .probingAccessPoint
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let requiredDeviceID = purpose.existingDevice == nil ? nil : expectedDeviceID
                let device = try await probeAccessPoint(expectedDeviceID: requiredDeviceID)
                guard !Task.isCancelled else { return }
                expectedDeviceID = device.id
                setupTargetDevice = device
                logger.info("Using immediate home Wi-Fi submission for WLED \(device.id, privacy: .public)")
                applyHomeWiFi()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(.init(recoveryFocus: .either, message: error.localizedDescription))
            }
        }
    }

    private func observeApplicationLifecycle() {
        appBecameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAfterSystemWiFiUI()
            }
        }
        appDidEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearDraftPasswordIfAppropriate()
            }
        }
    }

    private func removeApplicationLifecycleObserver() {
        if let appBecameActiveObserver {
            NotificationCenter.default.removeObserver(appBecameActiveObserver)
            self.appBecameActiveObserver = nil
        }
        if let appDidEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(appDidEnterBackgroundObserver)
            self.appDidEnterBackgroundObserver = nil
        }
    }

    private func clearDraftPasswordIfAppropriate() {
        // System-owned picker and device pages can also change app activation.
        // Only clear here when the user is still editing the in-app form.
        guard phase == .collectingHomeWiFi else { return }
        homeWiFiCredentials.clearPassword()
        customAPPassword = ""
    }

    private func restoreAuthorizedAccessory() {
        guard let accessorySession else { return }
        let authorizedWLEDDevices = accessorySession.accessories.filter { accessory in
            guard let ssid = accessory.ssid else { return false }
            return ssid.range(of: "WLED-", options: [.anchored, .caseInsensitive]) != nil
        }

        authorizedAccessoryCount = authorizedWLEDDevices.count
        logger.info("Found \(authorizedWLEDDevices.count) previously authorized WLED setup accessories")

        guard Self.shouldOfferSingleAuthorizedAccessoryResume(authorizedCount: authorizedWLEDDevices.count),
              let accessory = authorizedWLEDDevices.first else {
            restoredAccessory = nil
            if authorizedWLEDDevices.count > 1 {
                logger.info("Skipping automatic reuse because more than one setup accessory is authorized")
            }
            return
        }

        restoredAccessory = accessory
        if let ssid = accessory.ssid {
            logger.info("Restored the only authorized setup accessory with SSID \(ssid, privacy: .public)")
        }
    }

    static func shouldOfferSingleAuthorizedAccessoryResume(authorizedCount: Int) -> Bool {
        authorizedCount == 1
    }

    static func shouldReuseAuthorizedAccessory(authorizedCount: Int, restoredSSID: String?) -> Bool {
        authorizedCount == 1 && !(restoredSSID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func accessoryPickerFailureResolution(
        errorCode: Int,
        foregroundRetryCount: Int
    ) -> AccessoryPickerFailureResolution {
        if errorCode == ASError.Code.userCancelled.rawValue {
            return .returnToCredentials
        }
        if errorCode == ASError.Code.pickerRestricted.rawValue {
            return foregroundRetryCount == 0 ? .retryWhenActive : .fail
        }
        if errorCode == ASError.Code.userRestricted.rawValue {
            return .fail
        }
        return .tryDirectSetupConnection
    }

    static func shouldTryDirectSetupConnection(afterPickerErrorCode code: Int) -> Bool {
        accessoryPickerFailureResolution(
            errorCode: code,
            foregroundRetryCount: 0
        ) == .tryDirectSetupConnection
    }

    static func shouldTryDirectSetupConnection(afterAuthorizedJoinError error: Error) -> Bool {
        guard let accessPointError = error as? WLEDAccessPointProvisioningError else {
            return true
        }
        switch accessPointError {
        case .accessoryUnauthorized, .accessoryJoinDenied, .system:
            return true
        case .invalidCredentials, .userDenied, .alreadyPending, .notForeground, .hotspotCapabilityUnavailable:
            return false
        }
    }

    private func resumeAfterSystemWiFiUI() {
        if shouldPresentAccessoryPicker {
            logger.info("App became active with an accessory picker request pending")
            continuePendingAccessorySetupWhenReady()
            return
        }
        guard canContinueAccessPointSetup else { return }
        if phase == .joiningAccessPoint || phase == .probingAccessPoint {
            // Dismissing Apple's picker also activates the app. The existing join/probe
            // must keep running; canceling it here races the connection it just started.
            logger.info("App became active while setup connection was in progress; keeping the current attempt")
        }
    }

    private func reconnectAndProbeAccessPoint() {
        guard let expectedSSID = joinedAccessPointSSID else { return }
        activeTask?.cancel()
        isRecoveringAfterSystemWiFiUI = true
        phase = .joiningAccessPoint
        logger.info("Reconnecting to the authorized setup device")

        activeTask = Task { [weak self] in
            guard let self else { return }
            defer { isRecoveringAfterSystemWiFiUI = false }

            do {
                try await reconnectAccessPoint(expectedSSID: expectedSSID)
                guard !Task.isCancelled else { return }
                logger.info("Setup connection request completed; probing the device directly")
                beginAccessPointProbe()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Setup connection recovery failed: \(error.localizedDescription, privacy: .public)")
                phase = .failed(.init(recoveryFocus: .either, message: error.localizedDescription))
            }
        }
    }

    private func reconnectAccessPoint(expectedSSID: String) async throws {
        try await Self.retryPendingAccessPointConnection(
            expectedSSID: expectedSSID,
            currentSSID: { [currentWiFiProvider] in
                await currentWiFiProvider.currentSSID(requestPermissionIfNeeded: false)
            },
            connect: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.requestAccessPointConnection(expectedSSID: expectedSSID)
            },
            onPending: { [logger] attempt, maxAttempts in
                logger.info("Setup connection is still pending; retry \(attempt + 1) of \(maxAttempts)")
            }
        )
    }

    static func retryPendingAccessPointConnection(
        expectedSSID: String,
        maxAttempts: Int = 11,
        delay: @escaping () async throws -> Void = {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        },
        currentSSID: @escaping () async -> String?,
        connect: @escaping () async throws -> Void,
        onPending: (Int, Int) -> Void = { _, _ in }
    ) async throws {
        precondition(maxAttempts > 0)
        for attempt in 1...maxAttempts {
            do {
                try await connect()
                return
            } catch let error as WLEDAccessPointProvisioningError where error == .alreadyPending {
                if let ssid = await currentSSID(),
                   ssid.caseInsensitiveCompare(expectedSSID) == .orderedSame {
                    return
                }
                guard attempt < maxAttempts else { throw error }
                onPending(attempt, maxAttempts)
                try await delay()
            }
        }
    }

    private func requestAccessPointConnection(expectedSSID: String) async throws {
        if let pairedAccessory,
           pairedAccessory.ssid?.caseInsensitiveCompare(expectedSSID) == .orderedSame {
            try await accessPointService.joinAccessoryAccessPoint(
                pairedAccessory,
                password: WLEDAccessPointProvisioningRequest.standard.password
            )
            return
        }

        let password = expectedSSID.caseInsensitiveCompare(WLEDAccessPointProvisioningRequest.standard.ssid) == .orderedSame
            ? WLEDAccessPointProvisioningRequest.standard.password
            : customAPPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        try await accessPointService.joinAccessPoint(
            WLEDAccessPointProvisioningRequest(
                ssid: expectedSSID,
                password: password,
                useSSIDPrefix: false
            )
        )
    }

    private func scanHomeNetworksForCorrection(from device: WLEDDevice) {
        phase = .verifyingHomeWiFi
        networkVerificationMessage = nil
        activeTask = Task { [weak self] in
            guard let self else { return }
            await loadHomeNetworksForCorrection(from: device)
        }
    }

    private func loadHomeNetworksForCorrection(from device: WLEDDevice) async {
        phase = .verifyingHomeWiFi
        networkVerificationMessage = nil
        do {
            let networks = try await wifiService.scanForNetworks(device: device)
            guard !Task.isCancelled else { return }
            logger.info("WLED returned \(networks.count) nearby Wi-Fi networks during recovery")
            availableNetworks = networks.sorted { $0.signalStrength > $1.signalStrength }
            let correction = Self.homeWiFiCorrection(
                for: homeWiFiCredentials,
                networks: availableNetworks
            )
            selectedNetwork = correction.selectedSSID.flatMap { selectedSSID in
                availableNetworks.first { $0.ssid == selectedSSID }
            }
            homeWiFiCredentials.isOpenNetwork = correction.isOpenNetwork
            homeWiFiCredentials.clearPassword()
            networkVerificationMessage = correction.message
            phase = .correctingHomeWiFi
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("WLED recovery Wi-Fi scan failed: \(error.localizedDescription, privacy: .public)")
            availableNetworks = []
            selectedNetwork = nil
            homeWiFiCredentials.clearPassword()
            networkVerificationMessage = "Re-enter the network password and try again. If the network is hidden, keep its name exactly as shown in Wi-Fi Settings."
            phase = .correctingHomeWiFi
        }
    }

    static func homeWiFiCorrection(
        for credentials: WLEDHomeWiFiCredentials,
        networks: [WiFiNetwork]
    ) -> WLEDHomeWiFiCorrection {
        guard let exactMatch = credentials.matchingNetwork(in: networks) else {
            let message = networks.isEmpty
                ? "No nearby networks were returned. Re-enter the password, or continue if this is a hidden network."
                : "The entered network was not visible. Select one below, or continue if the network is hidden."
            return WLEDHomeWiFiCorrection(
                selectedSSID: nil,
                isOpenNetwork: credentials.isOpenNetwork,
                message: message
            )
        }

        if isOpenNetwork(exactMatch) {
            return WLEDHomeWiFiCorrection(
                selectedSSID: exactMatch.ssid,
                isOpenNetwork: true,
                message: "We found this network. Try connecting your device again."
            )
        }

        return WLEDHomeWiFiCorrection(
            selectedSSID: exactMatch.ssid,
            isOpenNetwork: false,
            message: "We found this network. Re-enter its password to try again."
        )
    }

    static func shouldRetryAutomaticRecovery(after error: Error) -> Bool {
        guard let accessPointError = error as? WLEDAccessPointProvisioningError else {
            return true
        }
        switch accessPointError {
        case .alreadyPending, .notForeground, .accessoryJoinDenied, .system:
            return true
        case .invalidCredentials, .userDenied, .hotspotCapabilityUnavailable, .accessoryUnauthorized:
            return false
        }
    }

    private func returnToHomeNetworkAndRediscover() async {
        phase = .returningToHomeNetwork
        if let joinedAccessPointSSID,
           Self.shouldRemoveSetupNetworkConfiguration(joinedWithAccessory: joinedAccessPointWithAccessory) {
            accessPointService.removeAccessPointConfiguration(ssid: joinedAccessPointSSID)
            logger.info("Removed temporary setup network \(joinedAccessPointSSID, privacy: .public); Apple accessory authorization remains available")
        }
        restartLANDiscovery()

        let associationDeadline = clock.now.addingTimeInterval(homeNetworkAssociationTimeout)
        _ = await waitForHomeNetworkAssociation(until: associationDeadline)
        guard !Task.isCancelled, !hasCompletedCurrentProvisioningAttempt else { return }

        homeRediscoveryStartedAt = clock.now
        phase = .rediscovering
        let softDeadline = Self.homeRediscoverySoftDeadline(
            startedAt: homeRediscoveryStartedAt ?? clock.now,
            timeout: homeRediscoverySoftTimeout
        )
        logger.info(
            "Home-network rediscovery started for attempt \(self.provisioningAttemptID?.uuidString ?? "unknown", privacy: .public)"
        )

        while !Task.isCancelled && clock.now < softDeadline {
            if let device = rediscoveredExpectedDevice() {
                completeProvisioning(with: device)
                return
            }
            try? await clock.sleep(for: 0.75)
        }

        guard !Task.isCancelled, !hasCompletedCurrentProvisioningAttempt else { return }
        logger.info(
            "Exact device has not appeared after the soft rediscovery window for attempt \(self.provisioningAttemptID?.uuidString ?? "unknown", privacy: .public); passive discovery remains active"
        )
        homeWiFiCredentials.clearPassword()
        phase = .rediscoveryTakingLonger
    }

    private func completeProvisioning(with device: WLEDDevice) {
        guard let attemptID = provisioningAttemptID,
              Self.shouldCompleteProvisioningAttempt(
                attemptID: attemptID,
                completedAttemptID: completedProvisioningAttemptID
              ) else {
            return
        }
        completedProvisioningAttemptID = attemptID
        logger.info(
            "Rediscovered provisioned WLED \(device.id, privacy: .public) at \(device.ipAddress, privacy: .public) for attempt \(attemptID.uuidString, privacy: .public)"
        )
        homeWiFiCredentials.clearPassword()
        customAPPassword = ""
        candidates = [device]
        completedProvisioningResult = provisioningResult(for: device)
        phase = .devicesFound
    }

    private var hasCompletedCurrentProvisioningAttempt: Bool {
        guard let provisioningAttemptID else { return false }
        return completedProvisioningAttemptID == provisioningAttemptID
    }

    static func homeRediscoverySoftDeadline(startedAt: Date, timeout: TimeInterval = 30) -> Date {
        startedAt.addingTimeInterval(timeout)
    }

    static func shouldCompleteProvisioningAttempt(
        attemptID: UUID?,
        completedAttemptID: UUID?
    ) -> Bool {
        guard let attemptID else { return false }
        return completedAttemptID != attemptID
    }

    private func waitForHomeNetworkAssociation(until provisioningDeadline: Date) async -> Bool {
        let expectedSSID = configuredHomeSSID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !expectedSSID.isEmpty else {
            try? await clock.sleep(for: 2)
            return !Task.isCancelled
        }

        let deadline = min(provisioningDeadline, clock.now.addingTimeInterval(10))
        let allowUnverifiedReturnAfter = clock.now.addingTimeInterval(4)
        var didReadCurrentSSID = false
        while !Task.isCancelled && clock.now < deadline {
            if let currentSSID = await currentWiFiProvider.currentSSID(requestPermissionIfNeeded: false) {
                didReadCurrentSSID = true
                if currentSSID.caseInsensitiveCompare(expectedSSID) == .orderedSame {
                    logger.info("Phone returned to home Wi-Fi SSID \(currentSSID, privacy: .public)")
                    return true
                }
            } else if !didReadCurrentSSID, clock.now >= allowUnverifiedReturnAfter {
                // The system can withhold the current SSID even while the phone has returned home.
                // Continue with a fresh discovery pass rather than treating unavailable SSID data as a failure.
                return true
            }
            try? await clock.sleep(for: 1)
        }

        return false
    }

    static func shouldRemoveSetupNetworkConfiguration(joinedWithAccessory _: Bool) -> Bool {
        true
    }

    private static func isOpenNetwork(_ network: WiFiNetwork) -> Bool {
        network.security.caseInsensitiveCompare("open") == .orderedSame
    }

    private func pendingSetupCandidates() -> [WLEDDevice] {
        let filtered = viewModel.devices.filter { device in
            !initialDeviceIDs.contains(device.id) || device.setupState == .pendingSelection
        }
        return Dictionary(grouping: filtered, by: { WLEDDeviceIdentity.canonicalID(for: $0.id) })
            .compactMap { $0.value.max(by: { $0.lastSeen < $1.lastSeen }) }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    private func observeDiscoveredDevices() {
        devicesCancellable = viewModel.$devices
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleDeviceListChange()
            }
    }

    private func handleDeviceListChange() {
        if homeWiFiSubmissionStartedAt != nil,
           let device = rediscoveredExpectedDevice() {
            completeProvisioning(with: device)
            return
        }

        guard homeWiFiSubmissionStartedAt == nil else { return }
        switch phase {
        case .idle, .discoveringLAN, .collectingHomeWiFi, .failed:
            handlePendingCandidates(pendingSetupCandidates())
        default:
            break
        }
    }

    private func handlePendingCandidates(_ found: [WLEDDevice]) {
        guard !found.isEmpty else { return }
        candidates = found
        if found.count == 1, let device = found.first {
            completeWithAlreadyConnectedDevice(device)
        } else {
            phase = .devicesFound
        }
    }

    private func completeWithAlreadyConnectedDevice(_ device: WLEDDevice) {
        homeWiFiCredentials.clearPassword()
        customAPPassword = ""
        completedProvisioningResult = provisioningResult(for: device)
        phase = .devicesFound
    }

    private func rediscoveredExpectedDevice() -> WLEDDevice? {
        guard let expectedDeviceID else { return nil }
        return viewModel.devices.first { device in
            Self.isValidRediscoveryCandidate(
                device,
                expectedDeviceID: expectedDeviceID,
                setupIPAddresses: Set(apCandidateIPs),
                seenAfter: homeWiFiSubmissionStartedAt
            )
        }
    }

    static func isValidRediscoveryCandidate(
        _ device: WLEDDevice,
        expectedDeviceID: String,
        setupIPAddresses: Set<String>,
        seenAfter: Date?
    ) -> Bool {
        guard device.id.caseInsensitiveCompare(expectedDeviceID) == .orderedSame,
              device.isOnline,
              !setupIPAddresses.contains(device.ipAddress) else {
            return false
        }
        guard let seenAfter else { return true }
        return device.lastSeen >= seenAfter
    }

    private func restartLANDiscovery() {
        discovery.restartTargetedDiscovery()
    }

    static func shouldVerifyAfterConnectionInterruption(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut,
             .cannotConnectToHost, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private func fetchWLEDDevice(at ipAddress: String) async throws -> WLEDDevice {
        guard let url = URL(string: "http://\(ipAddress)/json/info") else {
            throw ProvisioningError.wledNotReachable
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.allowsCellularAccess = false

        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mac = info["mac"] as? String, !mac.isEmpty else {
            throw ProvisioningError.wledNotReachable
        }

        let brand = (info["brand"] as? String)?.lowercased()
        guard brand == nil || brand == "wled" else {
            throw ProvisioningError.notWLED
        }

        let name = (info["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WLEDDevice(
            id: WLEDDeviceIdentity.canonicalID(for: mac),
            name: name?.isEmpty == false ? name! : "New Device",
            ipAddress: ipAddress,
            isOnline: true,
            setupState: .pendingSelection
        )
    }
}

private enum ProvisioningError: LocalizedError {
    case wledNotReachable
    case notWLED
    case unexpectedDevice

    var errorDescription: String? {
        switch self {
        case .wledNotReachable:
            return "Your phone connected for setup, but the device did not respond. Keep it powered on and try again."
        case .notWLED:
            return "The selected device is not compatible with this setup."
        case .unexpectedDevice:
            return "A different device responded during setup. Keep only the device you are setting up in setup mode, then try again."
        }
    }
}
