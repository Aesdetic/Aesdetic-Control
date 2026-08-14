import AccessorySetupKit
import Foundation
import NetworkExtension

struct WLEDAccessPointProvisioningRequest {
    var ssid: String
    var password: String
    var useSSIDPrefix: Bool

    static let standard = WLEDAccessPointProvisioningRequest(
        ssid: "WLED-AP",
        password: "wled1234",
        useSSIDPrefix: false
    )

    static let standardPrefix = WLEDAccessPointProvisioningRequest(
        ssid: "WLED-",
        password: "wled1234",
        useSSIDPrefix: true
    )
}

protocol WLEDAccessPointProvisioning {
    func joinAccessPoint(_ request: WLEDAccessPointProvisioningRequest) async throws
    func joinAccessoryAccessPoint(_ accessory: ASAccessory, password: String) async throws
    func removeAccessPointConfiguration(ssid: String)
}

enum WLEDAccessPointProvisioningError: LocalizedError, Equatable {
    case invalidCredentials
    case userDenied
    case alreadyPending
    case notForeground
    case hotspotCapabilityUnavailable
    case accessoryUnauthorized
    case accessoryJoinDenied
    case system(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "The setup connection name or password is invalid."
        case .userDenied:
            return "The connection was cancelled. Approve Apple's setup prompt to continue."
        case .alreadyPending:
            return "A connection is already in progress."
        case .notForeground:
            return "Keep Aesdetic Control open while connecting to your device."
        case .hotspotCapabilityUnavailable:
            return "This build cannot start the setup connection."
        case .accessoryUnauthorized:
            return "This device needs approval again. Find it and repeat Apple's setup step."
        case .accessoryJoinDenied:
            return "Your phone could not connect to the device. Find it and try again."
        case .system(let message):
            return message
        }
    }
}

final class WLEDAccessPointProvisioningService: WLEDAccessPointProvisioning {
    static let shared = WLEDAccessPointProvisioningService()

    private init() {}

    func joinDefaultWLEDAccessPoint() async throws {
        try await joinAccessPoint(.standard)
    }

    func removeAccessPointConfiguration(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    func joinAccessoryAccessPoint(_ accessory: ASAccessory, password: String) async throws {
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedPassword.count >= 8 else {
            throw WLEDAccessPointProvisioningError.invalidCredentials
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NEHotspotConfigurationManager.shared.joinAccessoryHotspot(
                accessory,
                passphrase: normalizedPassword
            ) { error in
                if let error, !Self.isAlreadyAssociated(error) {
                    continuation.resume(throwing: Self.mapHotspotError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func joinAccessPoint(_ request: WLEDAccessPointProvisioningRequest) async throws {
        let normalizedSSID = request.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = request.password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSSID.isEmpty, normalizedPassword.count >= 8 else {
            throw WLEDAccessPointProvisioningError.invalidCredentials
        }

        let configuration: NEHotspotConfiguration
        if request.useSSIDPrefix {
            configuration = NEHotspotConfiguration(
                ssidPrefix: normalizedSSID,
                passphrase: normalizedPassword,
                isWEP: false
            )
        } else {
            configuration = NEHotspotConfiguration(
                ssid: normalizedSSID,
                passphrase: normalizedPassword,
                isWEP: false
            )
        }
        configuration.joinOnce = true

        try await withCheckedThrowingContinuation { continuation in
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                if let error {
                    let mappedError = Self.mapHotspotError(error)
                    if case .system(let message) = mappedError,
                       message.localizedCaseInsensitiveContains("already associated") {
                        continuation.resume()
                        return
                    }
                    if Self.isAlreadyAssociated(error) {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: mappedError)
                    }
                    return
                }
                continuation.resume()
            }
        }
    }

    private static func isAlreadyAssociated(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NEHotspotConfigurationErrorDomain
            && nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
    }

    private static func mapHotspotError(_ error: Error) -> WLEDAccessPointProvisioningError {
        let nsError = error as NSError
        guard nsError.domain == NEHotspotConfigurationErrorDomain else {
            return .system(nsError.localizedDescription)
        }

        switch nsError.code {
        case NEHotspotConfigurationError.invalid.rawValue,
             NEHotspotConfigurationError.invalidSSID.rawValue,
             NEHotspotConfigurationError.invalidSSIDPrefix.rawValue,
             NEHotspotConfigurationError.invalidWPAPassphrase.rawValue,
             NEHotspotConfigurationError.invalidWEPPassphrase.rawValue:
            return .invalidCredentials
        case NEHotspotConfigurationError.userDenied.rawValue:
            return .userDenied
        case NEHotspotConfigurationError.pending.rawValue:
            return .alreadyPending
        case NEHotspotConfigurationError.applicationIsNotInForeground.rawValue:
            return .notForeground
        case NEHotspotConfigurationError.userUnauthorized.rawValue:
            return .accessoryUnauthorized
        case NEHotspotConfigurationError.systemDenied.rawValue:
            return .accessoryJoinDenied
        case NEHotspotConfigurationError.internal.rawValue,
             NEHotspotConfigurationError.systemConfiguration.rawValue:
            return .hotspotCapabilityUnavailable
        default:
            return .system(nsError.localizedDescription)
        }
    }
}
