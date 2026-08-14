import AccessorySetupKit
import Foundation
import SwiftUI
import Testing
@testable import Aesdetic_Control

private final class MockProvisioningURLProtocol: URLProtocol {
    typealias Handler = (URLRequest, Data?) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func reset(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = bodyData(from: request)
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request, body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockProvisioningDiscovery: WLEDProvisioningDiscovering {
    private(set) var startCount = 0
    private(set) var restartCount = 0

    func startTargetedDiscovery() {
        startCount += 1
    }

    func restartTargetedDiscovery() {
        restartCount += 1
    }
}

@Suite(.serialized)
struct WLEDProvisioningWiFiServiceTests {
    @Test func securedNetworkRequestSavesRestartsAndCarriesCredentials() async throws {
        var postedConfig: [String: Any]?
        let service = makeService { request, body in
            let response = try Self.response(for: request)
            if request.httpMethod == "POST" {
                #expect(request.timeoutInterval == WLEDWiFiService.provisioningRestartResponseTimeout)
                postedConfig = try JSONSerialization.jsonObject(with: try #require(body)) as? [String: Any]
                return (response, Data(#"{"success":true}"#.utf8))
            }
            return (response, Self.sampleConfigData())
        }

        try await service.connectToNetwork(device: Self.device(), ssid: "Home WiFi", password: "secret123")

        let config = try #require(postedConfig)
        let nw = try #require(config["nw"] as? [String: Any])
        let stations = try #require(nw["ins"] as? [[String: Any]])
        #expect(stations[0]["ssid"] as? String == "Home WiFi")
        #expect(stations[0]["psk"] as? String == "secret123")
        #expect(stations[0]["pskl"] == nil)
        #expect(config["sv"] as? Bool == true)
        #expect(config["rb"] as? Bool == true)
    }

    @Test func openNetworkFormClearsPrimaryPasswordAndPreservesNetworkSettings() async throws {
        var form: [String: String] = [:]
        let service = makeService { request, body in
            let response = try Self.response(for: request)
            if request.httpMethod == "POST" {
                #expect(request.url?.path == "/settings/wifi")
                #expect(request.timeoutInterval == WLEDWiFiService.provisioningRestartResponseTimeout)
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
                form = Self.decodeForm(try #require(body))
                return (response, Data("WiFi settings saved.".utf8))
            }
            return (response, Self.sampleConfigData())
        }

        try await service.connectToNetwork(device: Self.device(), ssid: "Cafe Open", password: nil)

        #expect(form["CS0"] == "Cafe Open")
        #expect(form["PW0"] == "")
        #expect(form["CS1"] == "Backup")
        #expect(form["PW1"] == String(repeating: "*", count: 12))
        #expect(form["IP00"] == "192")
        #expect(form["SN03"] == "0")
        #expect(form["AS"] == "WLED-AP")
        #expect(form["AP"] == String(repeating: "*", count: 8))
        #expect(form["AC"] == "6")
        #expect(form["AB"] == "1")
        #expect(form["AH"] == "on")
        #expect(form["CM"] == "living-room")
        #expect(form["D0"] == "1")
        #expect(form["WS"] == "on")
        #expect(form["TX"] == "78")
    }

    @Test func safeSecuredChangeKeepsExistingNetworksAndAddsTarget() async throws {
        var postedConfig: [String: Any]?
        let service = makeService { request, body in
            let response = try Self.response(for: request)
            if request.httpMethod == "POST" {
                postedConfig = try JSONSerialization.jsonObject(with: try #require(body)) as? [String: Any]
                return (response, Data(#"{"success":true}"#.utf8))
            }
            return (response, Self.sampleConfigData())
        }

        try await service.connectToNetworkPreservingFallback(
            device: Self.device(),
            ssid: "New Home",
            password: "newpassword"
        )

        let config = try #require(postedConfig)
        let networkConfig = try #require(config["nw"] as? [String: Any])
        let stations = try #require(networkConfig["ins"] as? [[String: Any]])
        #expect(stations.count == 3)
        #expect(stations[0]["ssid"] as? String == "Old Home")
        #expect(stations[0]["pskl"] as? Int == 10)
        #expect(stations[1]["ssid"] as? String == "Backup")
        #expect(stations[2]["ssid"] as? String == "New Home")
        #expect(stations[2]["psk"] as? String == "newpassword")
        #expect(config["sv"] as? Bool == true)
        #expect(config["rb"] as? Bool == true)
    }

    @Test func safeOpenChangeKeepsExistingPasswordsAndAddsOpenTarget() async throws {
        var form: [String: String] = [:]
        let service = makeService { request, body in
            let response = try Self.response(for: request)
            if request.httpMethod == "POST" {
                form = Self.decodeForm(try #require(body))
                return (response, Data("WiFi settings saved.".utf8))
            }
            return (response, Self.sampleConfigData())
        }

        try await service.connectToNetworkPreservingFallback(
            device: Self.device(),
            ssid: "Cafe Open",
            password: nil
        )

        #expect(form["CS0"] == "Old Home")
        #expect(form["PW0"] == String(repeating: "*", count: 10))
        #expect(form["CS1"] == "Backup")
        #expect(form["PW1"] == String(repeating: "*", count: 12))
        #expect(form["CS2"] == "Cafe Open")
        #expect(form["PW2"] == "")
    }

    @Test @MainActor func safeChangeUtilitiesNormalizeBSSIDAndRecognizeRestartLoss() {
        #expect(WLEDSafeWiFiChangeService.normalizeBSSID("AA:bb-CC:dd-EE:ff") == "aabbccddeeff")
        #expect(WLEDSafeWiFiChangeService.isExpectedRestartInterruption(URLError(.networkConnectionLost)))
        #expect(WLEDSafeWiFiChangeService.isExpectedRestartInterruption(URLError(.timedOut)))
        #expect(!WLEDSafeWiFiChangeService.isExpectedRestartInterruption(URLError(.badURL)))
        #expect(WLEDSafeWiFiChangeService.supportsFallback(firmwareVersion: "0.15.0"))
        #expect(WLEDSafeWiFiChangeService.supportsFallback(firmwareVersion: "v0.16.1-b2"))
        #expect(!WLEDSafeWiFiChangeService.supportsFallback(firmwareVersion: "0.14.4"))
        #expect(!WLEDSafeWiFiChangeService.supportsFallback(firmwareVersion: nil))
    }

    @Test func reconnectResultDoesNotLaunchProductSetup() {
        let device = Self.device()
        let reconnect = WLEDProvisioningResult(
            device: device,
            configuredSSID: "New Home",
            wifiConfiguredDuringFlow: true,
            purpose: .reconnect(device)
        )
        let add = WLEDProvisioningResult(
            device: device,
            configuredSSID: "New Home",
            wifiConfiguredDuringFlow: true,
            purpose: .addDevice
        )

        #expect(!reconnect.shouldBeginProductSetup)
        #expect(add.shouldBeginProductSetup)
    }

    @Test func networkScanUsesInjectedSession() async throws {
        let service = makeService { request, _ in
            #expect(request.url?.path == "/json/net")
            let response = try Self.response(for: request)
            return (response, Data(#"{"networks":[{"ssid":"Home","rssi":-42,"enc":3,"channel":11}]}"#.utf8))
        }

        let networks = try await service.scanForNetworks(device: Self.device())

        #expect(networks.count == 1)
        #expect(networks.first?.ssid == "Home")
        #expect(networks.first?.channel == 11)
    }

    @Test func networkScanWaitsForDelayedWLEDResults() async throws {
        var attempts = 0
        let service = makeService(scanMaxAttempts: 4, scanRetryDelay: 0) { request, _ in
            #expect(request.url?.path == "/json/net")
            attempts += 1
            let response = try Self.response(for: request)
            if attempts < 4 {
                return (response, Data(#"{"networks":[]}"#.utf8))
            }
            return (response, Data(#"{"networks":[{"ssid":"Delayed Home","rssi":-51,"enc":3,"channel":6}]}"#.utf8))
        }

        let networks = try await service.scanForNetworks(device: Self.device())

        #expect(attempts == 4)
        #expect(networks.map(\.ssid) == ["Delayed Home"])
    }

    @Test @MainActor func expectedRestartDisconnectsProceedToRediscovery() {
        let accepted: [URLError.Code] = [
            .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut,
            .cannotConnectToHost,
            .resourceUnavailable
        ]
        for code in accepted {
            #expect(WLEDProvisioningCoordinator.shouldVerifyAfterConnectionInterruption(URLError(code)))
        }
        #expect(!WLEDProvisioningCoordinator.shouldVerifyAfterConnectionInterruption(URLError(.badURL)))
    }

    @Test @MainActor func pendingAccessoryConnectionRetriesUntilRequestCanStart() async throws {
        var attempts = 0
        var delays = 0

        try await WLEDProvisioningCoordinator.retryPendingAccessPointConnection(
            expectedSSID: "WLED-AP",
            maxAttempts: 4,
            delay: { delays += 1 },
            currentSSID: { nil },
            connect: {
                attempts += 1
                if attempts < 3 {
                    throw WLEDAccessPointProvisioningError.alreadyPending
                }
            }
        )

        #expect(attempts == 3)
        #expect(delays == 2)
    }

    @Test @MainActor func onlyOneAuthorizedAccessoryOffersExplicitResume() {
        #expect(!WLEDProvisioningCoordinator.shouldOfferSingleAuthorizedAccessoryResume(authorizedCount: 0))
        #expect(WLEDProvisioningCoordinator.shouldOfferSingleAuthorizedAccessoryResume(authorizedCount: 1))
        #expect(!WLEDProvisioningCoordinator.shouldOfferSingleAuthorizedAccessoryResume(authorizedCount: 2))
    }

    @Test @MainActor func factoryResetReusesTheOnlyAuthorizedSetupAccessory() {
        #expect(WLEDProvisioningCoordinator.shouldReuseAuthorizedAccessory(
            authorizedCount: 1,
            restoredSSID: "WLED-AP"
        ))
        #expect(!WLEDProvisioningCoordinator.shouldReuseAuthorizedAccessory(
            authorizedCount: 0,
            restoredSSID: "WLED-AP"
        ))
        #expect(!WLEDProvisioningCoordinator.shouldReuseAuthorizedAccessory(
            authorizedCount: 2,
            restoredSSID: "WLED-AP"
        ))
        #expect(!WLEDProvisioningCoordinator.shouldReuseAuthorizedAccessory(
            authorizedCount: 1,
            restoredSSID: " "
        ))
    }

    @Test @MainActor func pickerFailureFallsBackUnlessTheUserCancelledOrRestrictedSetup() {
        #expect(WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(afterPickerErrorCode: 200))
        #expect(WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(afterPickerErrorCode: 450))
        #expect(!WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(
            afterPickerErrorCode: ASError.Code.userCancelled.rawValue
        ))
        #expect(!WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(
            afterPickerErrorCode: ASError.Code.userRestricted.rawValue
        ))
        #expect(WLEDProvisioningCoordinator.accessoryPickerFailureResolution(
            errorCode: ASError.Code.pickerRestricted.rawValue,
            foregroundRetryCount: 0
        ) == .retryWhenActive)
        #expect(WLEDProvisioningCoordinator.accessoryPickerFailureResolution(
            errorCode: ASError.Code.pickerRestricted.rawValue,
            foregroundRetryCount: 1
        ) == .fail)
        #expect(WLEDProvisioningCoordinator.accessoryPickerFailureResolution(
            errorCode: ASError.Code.userCancelled.rawValue,
            foregroundRetryCount: 0
        ) == .returnToCredentials)
    }

    @Test @MainActor func staleAuthorizedJoinFallsBackToDirectSetupConnection() {
        #expect(WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(
            afterAuthorizedJoinError: WLEDAccessPointProvisioningError.accessoryUnauthorized
        ))
        #expect(WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(
            afterAuthorizedJoinError: WLEDAccessPointProvisioningError.accessoryJoinDenied
        ))
        #expect(!WLEDProvisioningCoordinator.shouldTryDirectSetupConnection(
            afterAuthorizedJoinError: WLEDAccessPointProvisioningError.userDenied
        ))
    }

    @Test @MainActor func accessorySelectionIsAcceptedUntilPickerDismisses() {
        #expect(WLEDProvisioningCoordinator.shouldStartAccessoryJoin(afterAddedIn: .presentingAccessoryPicker))
        #expect(WLEDProvisioningCoordinator.shouldStartAccessoryJoin(afterAddedIn: .collectingHomeWiFi))
        #expect(!WLEDProvisioningCoordinator.shouldStartAccessoryJoin(afterAddedIn: .joiningAccessPoint))
        #expect(!WLEDProvisioningCoordinator.shouldStartAccessoryJoin(afterAddedIn: .probingAccessPoint))
    }

    @Test @MainActor func temporaryHotspotIsRemovedAfterAccessoryProvisioning() {
        #expect(WLEDProvisioningCoordinator.shouldRemoveSetupNetworkConfiguration(joinedWithAccessory: false))
        #expect(WLEDProvisioningCoordinator.shouldRemoveSetupNetworkConfiguration(joinedWithAccessory: true))
        #expect(WLEDWiFiService.provisioningRestartResponseTimeout == 3)
    }

    @Test @MainActor func provisioningPhasesProjectToSimplePresentationStates() {
        #expect(WLEDProvisioningCoordinator.presentationState(for: .preparingDevicePage) == .devicePageNotice)
        #expect(WLEDProvisioningCoordinator.presentationState(for: .joiningAccessPoint) == .connecting)
        #expect(WLEDProvisioningCoordinator.presentationState(for: .applyingHomeWiFi) == .connecting)
        #expect(WLEDProvisioningCoordinator.presentationState(for: .rediscovering) == .finishing)
        #expect(WLEDProvisioningCoordinator.presentationState(for: .rediscoveryTakingLonger) == .takingLonger)
        #expect(WLEDProvisioningCoordinator.presentationState(for: .failed(.init(
            recoveryFocus: .either,
            message: "Try again"
        ))) == .failure)
    }

    @Test @MainActor func explicitFindUsesOnlyInjectedTargetedDiscovery() {
        let discovery = MockProvisioningDiscovery()
        let coordinator = WLEDProvisioningCoordinator(
            viewModel: .shared,
            discovery: discovery
        )

        coordinator.discoverOnCurrentNetwork()

        #expect(discovery.startCount == 1)
        #expect(discovery.restartCount == 0)
        coordinator.cancel()
    }

    @Test @MainActor func captivePageTimeDoesNotConsumeHomeRediscoveryWindow() {
        let credentialsAcceptedAt = Date(timeIntervalSince1970: 1_000)
        let rediscoveryStartedAt = credentialsAcceptedAt.addingTimeInterval(15)
        let deadline = WLEDProvisioningCoordinator.homeRediscoverySoftDeadline(
            startedAt: rediscoveryStartedAt
        )

        #expect(deadline == credentialsAcceptedAt.addingTimeInterval(45))
    }

    @Test @MainActor func provisioningAttemptCanCompleteOnlyOnce() {
        let attemptID = UUID()

        #expect(WLEDProvisioningCoordinator.shouldCompleteProvisioningAttempt(
            attemptID: attemptID,
            completedAttemptID: nil
        ))
        #expect(!WLEDProvisioningCoordinator.shouldCompleteProvisioningAttempt(
            attemptID: attemptID,
            completedAttemptID: attemptID
        ))
        #expect(!WLEDProvisioningCoordinator.shouldCompleteProvisioningAttempt(
            attemptID: nil,
            completedAttemptID: nil
        ))
    }

    @Test @MainActor func correctedWiFiStartsWithAFreshSubmissionWindow() {
        let coordinator = WLEDProvisioningCoordinator(viewModel: .shared)
        coordinator.homeWiFiCredentials = WLEDHomeWiFiCredentials(
            ssid: "Home",
            password: "password123",
            isOpenNetwork: false
        )

        coordinator.showAccessoryPicker()
        #expect(coordinator.requiresCancellationConfirmation)

        coordinator.editHomeWiFiAfterFailure()
        #expect(!coordinator.requiresCancellationConfirmation)
        #expect(coordinator.homeWiFiCredentials.password.isEmpty)
        coordinator.cancel()
    }

    @Test @MainActor func securedRecoveryMatchRequiresPasswordAgain() {
        let credentials = WLEDHomeWiFiCredentials(
            ssid: "Home",
            password: "",
            isOpenNetwork: false
        )
        let correction = WLEDProvisioningCoordinator.homeWiFiCorrection(
            for: credentials,
            networks: [
                WiFiNetwork(ssid: "Home", signalStrength: -42, security: "WPA2", channel: 6, bssid: nil)
            ]
        )

        #expect(correction.selectedSSID == "Home")
        #expect(!correction.isOpenNetwork)
        #expect(correction.message.localizedCaseInsensitiveContains("password"))
    }

    @Test @MainActor func openRecoveryMatchDoesNotRequestPassword() {
        let credentials = WLEDHomeWiFiCredentials(
            ssid: "Guest",
            password: "unused-password",
            isOpenNetwork: false
        )
        let correction = WLEDProvisioningCoordinator.homeWiFiCorrection(
            for: credentials,
            networks: [
                WiFiNetwork(ssid: "Guest", signalStrength: -50, security: "Open", channel: 11, bssid: nil)
            ]
        )

        #expect(correction.selectedSSID == "Guest")
        #expect(correction.isOpenNetwork)
    }

    @Test @MainActor func hiddenRecoveryNetworkKeepsExplicitOpenSetting() {
        let credentials = WLEDHomeWiFiCredentials(
            ssid: "Hidden",
            password: "",
            isOpenNetwork: true
        )
        let correction = WLEDProvisioningCoordinator.homeWiFiCorrection(
            for: credentials,
            networks: [
                WiFiNetwork(ssid: "Other", signalStrength: -55, security: "WPA2", channel: 1, bssid: nil)
            ]
        )

        #expect(correction.selectedSSID == nil)
        #expect(correction.isOpenNetwork)
        #expect(correction.message.localizedCaseInsensitiveContains("hidden"))
    }

    @Test @MainActor func rediscoveryRejectsSetupAddressAndStaleDeviceRecords() {
        let submissionDate = Date()
        var device = Self.device()
        device.isOnline = true
        device.lastSeen = submissionDate.addingTimeInterval(1)

        device.ipAddress = "4.3.2.1"
        #expect(!WLEDProvisioningCoordinator.isValidRediscoveryCandidate(
            device,
            expectedDeviceID: "TEST-DEVICE",
            setupIPAddresses: ["4.3.2.1", "192.168.4.1"],
            seenAfter: submissionDate
        ))

        device.ipAddress = "192.168.1.42"
        device.lastSeen = submissionDate.addingTimeInterval(-1)
        #expect(!WLEDProvisioningCoordinator.isValidRediscoveryCandidate(
            device,
            expectedDeviceID: "test-device",
            setupIPAddresses: ["4.3.2.1", "192.168.4.1"],
            seenAfter: submissionDate
        ))

        device.lastSeen = submissionDate.addingTimeInterval(1)
        #expect(WLEDProvisioningCoordinator.isValidRediscoveryCandidate(
            device,
            expectedDeviceID: "test-device",
            setupIPAddresses: ["4.3.2.1", "192.168.4.1"],
            seenAfter: submissionDate
        ))
    }

    private func makeService(
        scanMaxAttempts: Int = 9,
        scanRetryDelay: TimeInterval = 0.75,
        handler: @escaping MockProvisioningURLProtocol.Handler
    ) -> WLEDWiFiService {
        MockProvisioningURLProtocol.reset(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProvisioningURLProtocol.self]
        return WLEDWiFiService(
            session: URLSession(configuration: configuration),
            restartResponseTimeout: WLEDWiFiService.provisioningRestartResponseTimeout,
            restartSettleDelay: 0,
            scanMaxAttempts: scanMaxAttempts,
            scanRetryDelay: scanRetryDelay
        )
    }

    private static func response(for request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
    }

    private static func sampleConfigData() -> Data {
        Data(#"{"id":{"mdns":"living-room"},"nw":{"ins":[{"ssid":"Old Home","pskl":10,"bssid":"AABBCCDDEEFF","ip":[192,168,1,50],"gw":[192,168,1,1],"sn":[255,255,255,0]},{"ssid":"Backup","pskl":12,"bssid":"","ip":[0,0,0,0],"gw":[0,0,0,0],"sn":[255,255,255,0]}],"dns":[1,1,1,1],"espnow":false},"ap":{"ssid":"WLED-AP","pskl":8,"chan":6,"hide":true,"behav":1},"wifi":{"sleep":false,"phy":false,"txpwr":78}}"#.utf8)
    }

    private static func decodeForm(_ data: Data) -> [String: String] {
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.split(separator: "&", omittingEmptySubsequences: false).reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first else { return }
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            let key = String(rawKey).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(rawKey)
            let value = rawValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawValue
            result[key] = value
        }
    }

    private static func device() -> WLEDDevice {
        WLEDDevice(
            id: "test-device",
            name: "Test Device",
            ipAddress: "192.168.4.1",
            isOnline: true,
            brightness: 128,
            currentColor: .white,
            productType: .generic,
            location: .all,
            lastSeen: Date(),
            state: nil
        )
    }
}
