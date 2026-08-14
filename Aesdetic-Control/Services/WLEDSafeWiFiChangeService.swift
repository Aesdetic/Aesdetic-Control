import Foundation
import os.log

enum WLEDSafeWiFiChangeOutcome: Equatable {
    case verified(WLEDDevice)
    case stayedOnPreviousNetwork
    case deviceDidNotReturn
    case returnedButCouldNotVerify
    case fallbackUnavailable
    case replacementRequired

    var failureMessage: String? {
        switch self {
        case .verified:
            return nil
        case .stayedOnPreviousNetwork:
            return "Your device stayed on its previous Wi-Fi. It may prefer that signal, or the new password may be incorrect. The new network is still saved and can be edited below."
        case .deviceDidNotReturn:
            return "Your device did not return online. Keep it powered on, then use Reconnect Device from the Devices tab."
        case .returnedButCouldNotVerify:
            return "Your device returned online, but the app could not confirm the new Wi-Fi. Check the network shown and try again."
        case .fallbackUnavailable:
            return "This device needs a newer WLED version to change Wi-Fi while keeping the old network as a backup. Update it first, or use Reconnect Device from the Devices tab."
        case .replacementRequired:
            return "This device already has three saved networks. Choose one that is not connected to replace."
        }
    }
}

@MainActor
final class WLEDSafeWiFiChangeService {
    static let shared = WLEDSafeWiFiChangeService()

    private let wifiService: WLEDWiFiService
    private let savedNetworkService: WLEDSavedNetworkServicing
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "WiFiChange")

    init(
        wifiService: WLEDWiFiService = .shared,
        savedNetworkService: WLEDSavedNetworkServicing = WLEDSavedNetworkService.shared
    ) {
        self.wifiService = wifiService
        self.savedNetworkService = savedNetworkService
    }

    func changeNetwork(
        device: WLEDDevice,
        network: WiFiNetwork,
        password: String?,
        viewModel: DeviceControlViewModel,
        replacingSlot: Int? = nil,
        timeout: TimeInterval = 60
    ) async -> WLEDSafeWiFiChangeOutcome {
        let expectedDeviceID = WLEDDeviceIdentity.canonicalID(for: device.id)
        let snapshot = try? await savedNetworkService.loadSnapshot(for: device)
        let previousInfo = try? await wifiService.getCurrentWiFiInfo(device: device)
        let previousBSSID = Self.normalizeBSSID(snapshot?.connectedBSSID ?? previousInfo?.bssid)
        let previousSSID = snapshot?.connectedSSID ?? ""

        if previousSSID.caseInsensitiveCompare(network.ssid) == .orderedSame,
           !previousSSID.isEmpty {
            logger.info("Wi-Fi change skipped because the device is already on SSID \(network.ssid, privacy: .public)")
            return .verified(device)
        }

        let firmwareVersion = snapshot?.firmwareVersion ?? previousInfo?.firmwareVersion
        guard Self.supportsFallback(firmwareVersion: firmwareVersion) else {
            logger.info("Safe Wi-Fi change unavailable for WLED version \(firmwareVersion ?? "unknown", privacy: .public)")
            return .fallbackUnavailable
        }

        if let snapshot,
           snapshot.networks.count >= snapshot.capacity,
           !snapshot.networks.contains(where: { $0.ssid.caseInsensitiveCompare(network.ssid) == .orderedSame }),
           replacingSlot == nil {
            return .replacementRequired
        }

        let scannedNetworks = (try? await wifiService.scanForNetworks(device: device)) ?? [network]
        let targetBSSIDs = Set(
            scannedNetworks
                .filter { $0.ssid.caseInsensitiveCompare(network.ssid) == .orderedSame }
                .compactMap { Self.normalizeBSSID($0.bssid) }
                .filter { !$0.isEmpty }
        )
        let submittedAt = Date()

        logger.info(
            "Submitting safe Wi-Fi change for WLED \(expectedDeviceID, privacy: .public) to SSID \(network.ssid, privacy: .public); target access points=\(targetBSSIDs.count)"
        )

        do {
            let draft = WLEDSavedNetworkDraft(
                ssid: network.ssid,
                password: password ?? "",
                isOpenNetwork: password == nil
            )
            _ = try await savedNetworkService.save(
                draft,
                for: device,
                replacingSlot: replacingSlot,
                restartAfterSave: true
            )
        } catch {
            if error as? WLEDSavedNetworkError == .replacementRequired {
                return .replacementRequired
            }
            guard Self.isExpectedRestartInterruption(error) else {
                logger.error("Safe Wi-Fi submission failed: \(error.localizedDescription, privacy: .public)")
                return .deviceDidNotReturn
            }
            logger.info("Connection ended while WLED restarted; continuing exact-device verification")
        }

        viewModel.startPassiveDiscovery()
        viewModel.wledService.startDiscovery()

        let deadline = Date().addingTimeInterval(timeout)
        var lastReachableBSSID: String?
        var lastReachableDevice: WLEDDevice?

        while !Task.isCancelled && Date() < deadline {
            if let candidate = viewModel.devices.first(where: { candidate in
                WLEDDeviceIdentity.canonicalID(for: candidate.id) == expectedDeviceID &&
                    candidate.isOnline && candidate.lastSeen >= submittedAt
            }) {
                lastReachableDevice = candidate
                if let currentSnapshot = try? await savedNetworkService.loadSnapshot(for: candidate) {
                    let connectedBSSID = Self.normalizeBSSID(currentSnapshot.connectedBSSID)
                    if !connectedBSSID.isEmpty {
                        lastReachableBSSID = connectedBSSID
                    }

                    if let connectedSSID = currentSnapshot.connectedSSID,
                       connectedSSID.caseInsensitiveCompare(network.ssid) == .orderedSame {
                        logger.info("Verified WLED \(expectedDeviceID, privacy: .public) on the requested Wi-Fi")
                        return .verified(candidate)
                    }

                    let matchedScannedAccessPoint = targetBSSIDs.contains(connectedBSSID)
                    let changedFromPreviousAccessPoint = targetBSSIDs.isEmpty &&
                        !connectedBSSID.isEmpty &&
                        !previousBSSID.isEmpty &&
                        connectedBSSID != previousBSSID
                    if matchedScannedAccessPoint || changedFromPreviousAccessPoint {
                        logger.info("Verified WLED \(expectedDeviceID, privacy: .public) on the requested Wi-Fi")
                        return .verified(candidate)
                    }
                } else if let info = try? await wifiService.getCurrentWiFiInfo(device: candidate) {
                    let connectedBSSID = Self.normalizeBSSID(info.bssid)
                    if !connectedBSSID.isEmpty {
                        lastReachableBSSID = connectedBSSID
                    }
                    if targetBSSIDs.contains(connectedBSSID) {
                        logger.info("Verified WLED \(expectedDeviceID, privacy: .public) on the requested Wi-Fi")
                        return .verified(candidate)
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard !Task.isCancelled else { return .deviceDidNotReturn }
        if let lastReachableBSSID,
           !previousBSSID.isEmpty,
           lastReachableBSSID == previousBSSID {
            logger.info("WLED returned on its previous Wi-Fi fallback")
            return .stayedOnPreviousNetwork
        }
        if lastReachableDevice != nil {
            return .returnedButCouldNotVerify
        }
        return .deviceDidNotReturn
    }

    nonisolated static func normalizeBSSID(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    nonisolated static func isExpectedRestartInterruption(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut,
             .cannotConnectToHost, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    nonisolated static func supportsFallback(firmwareVersion: String?) -> Bool {
        guard let firmwareVersion else { return false }
        let release = firmwareVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: ".")
            .prefix(3)
            .map { Int($0) ?? 0 } ?? []
        guard release.count >= 2 else { return false }
        let major = release[0]
        let minor = release[1]
        return major > 0 || minor >= 15
    }
}
