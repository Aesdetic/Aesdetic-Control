import CryptoKit
import Foundation
import Security

/// Native, local-network firmware updates for WLED. The service intentionally
/// refuses to guess a board image: an asset must be selected by the approved
/// compatibility catalog before it can be uploaded.
final class WLEDFirmwareUpdateService {
    static let shared = WLEDFirmwareUpdateService()

    /// WLED's official 16.0 release is reported by `/json/info` as `16.0.0`.
    static let approvedBaselineVersion = "16.0.0"

    /// Native uploads stay fail-closed until the production OTA acceptance
    /// gates (hardware authorization, durable recovery, and physical-device
    /// validation) have been completed. Builds must opt in explicitly.
    static var nativeInstallationEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "WLEDFirmwareNativeInstallationEnabled") as? Bool ?? false
    }

    private let urlSession: URLSession
    private let backupStore: WLEDFirmwareBackupStore

    init(urlSession: URLSession? = nil, backupStore: WLEDFirmwareBackupStore = .shared) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 180
            self.urlSession = URLSession(configuration: configuration)
        }
        self.backupStore = backupStore
    }

    func recommendedAssessment(for device: WLEDDevice, isAesdeticProduct: Bool) async throws -> WLEDFirmwareUpdateAssessment {
        let identity = try await fetchIdentity(for: device)
        guard isAesdeticProduct else {
            return .manualUpdateRequired("This device uses a custom setup. Use Advanced update options if you need to update WLED.")
        }
        guard Self.nativeInstallationEnabled else {
            return .unavailable("Automatic software installation is not enabled in this build.")
        }
        guard VersionComparator.compare(identity.version, Self.approvedBaselineVersion) == .orderedAscending else {
            return .upToDate(current: identity.version, target: Self.approvedBaselineVersion)
        }

        let catalog = try await loadCatalog()
        guard !catalog.isDisabled else {
            return .unavailable("Software updates are temporarily unavailable.")
        }
        guard let profile = catalog.profile(for: identity) else {
            return .manualUpdateRequired("This lamp needs a manual software update.")
        }
        return .available(current: identity.version, target: catalog.approvedRelease.version, profile: profile)
    }

    func latestOfficialAssessment(for device: WLEDDevice) async throws -> WLEDFirmwareUpdateAssessment {
        let identity = try await fetchIdentity(for: device)
        guard Self.nativeInstallationEnabled else {
            return .unavailable("Native WLED installation is not enabled in this build. Use the manual updater if needed.")
        }
        let catalog = try await loadCatalog()
        guard !catalog.isDisabled else {
            return .unavailable("Software updates are temporarily unavailable.")
        }
        guard let profile = catalog.profile(for: identity) else {
            return .manualUpdateRequired("A safe firmware match could not be identified for this WLED device.")
        }
        let release = try await fetchLatestRelease()
        guard VersionComparator.compare(identity.version, release.version) == .orderedAscending else {
            return .upToDate(current: identity.version, target: release.version)
        }
        guard release.asset(named: profile.assetName(for: release.version)) != nil else {
            return .manualUpdateRequired("The latest WLED release does not include a safe firmware match for this device.")
        }
        return .available(current: identity.version, target: release.version, profile: profile)
    }

    func installRecommendedUpdate(
        for device: WLEDDevice,
        progress: @escaping @MainActor (WLEDFirmwareUpdatePhase) -> Void
    ) async throws -> String {
        guard Self.nativeInstallationEnabled else {
            throw WLEDFirmwareUpdateError.nativeInstallationDisabled
        }
        let identity = try await fetchIdentity(for: device)
        guard VersionComparator.compare(identity.version, Self.approvedBaselineVersion) == .orderedAscending else {
            return identity.version
        }
        let catalog = try await loadCatalog()
        guard !catalog.isDisabled, let profile = catalog.profile(for: identity) else {
            throw WLEDFirmwareUpdateError.manualUpdateRequired
        }
        return try await install(
            device: device,
            identity: identity,
            release: catalog.approvedRelease,
            assetName: profile.assetName(for: catalog.approvedRelease.version),
            progress: progress
        )
    }

    func installLatestOfficialUpdate(
        for device: WLEDDevice,
        progress: @escaping @MainActor (WLEDFirmwareUpdatePhase) -> Void
    ) async throws -> String {
        guard Self.nativeInstallationEnabled else {
            throw WLEDFirmwareUpdateError.nativeInstallationDisabled
        }
        let identity = try await fetchIdentity(for: device)
        let catalog = try await loadCatalog()
        guard !catalog.isDisabled, let profile = catalog.profile(for: identity) else {
            throw WLEDFirmwareUpdateError.manualUpdateRequired
        }
        let release = try await fetchLatestRelease()
        guard VersionComparator.compare(identity.version, release.version) == .orderedAscending else {
            return identity.version
        }
        return try await install(
            device: device,
            identity: identity,
            release: release,
            assetName: profile.assetName(for: release.version),
            progress: progress
        )
    }

    func fetchIdentity(for device: WLEDDevice) async throws -> WLEDFirmwareIdentity {
        guard let url = URL(string: "http://\(device.ipAddress)/json/info") else {
            throw WLEDFirmwareUpdateError.invalidDeviceAddress
        }
        let (data, response) = try await urlSession.data(from: url)
        try validate(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = string(object["ver"]), !version.isEmpty else {
            throw WLEDFirmwareUpdateError.invalidDeviceResponse
        }
        return WLEDFirmwareIdentity(
            version: VersionComparator.normalize(version),
            architecture: string(object["arch"]),
            brand: string(object["brand"]),
            product: string(object["product"]),
            repository: string(object["repo"]),
            buildID: string(object["vid"])
        )
    }

    private func install(
        device: WLEDDevice,
        identity: WLEDFirmwareIdentity,
        release: WLEDFirmwareRelease,
        assetName: String,
        progress: @escaping @MainActor (WLEDFirmwareUpdatePhase) -> Void
    ) async throws -> String {
        guard let asset = release.asset(named: assetName) else {
            throw WLEDFirmwareUpdateError.manualUpdateRequired
        }
        await publish(.preflight, to: progress)
        try await verifyOTAPermissions(for: device)

        await publish(.creatingBackup, to: progress)
        await backupStore.removeExpiredBackups()
        let backupID = try await backupStore.capture(for: device, session: urlSession)

        do {
            await publish(.downloading, to: progress)
            var request = URLRequest(url: asset.downloadURL)
            request.setValue("Aesdetic-Control", forHTTPHeaderField: "User-Agent")
            let (firmware, response) = try await urlSession.data(for: request)
            try validate(response)

            await publish(.verifying, to: progress)
            guard sha256(firmware) == asset.sha256.lowercased() else {
                throw WLEDFirmwareUpdateError.checksumMismatch
            }

            await publish(.installing, to: progress)
            try await upload(firmware: firmware, named: asset.name, to: device)

            await publish(.restarting, to: progress)
            let installedVersion = try await waitForReboot(of: device, expectedVersion: release.version, progress: progress)
            await backupStore.remove(id: backupID)
            return installedVersion
        } catch {
            // Preserve the encrypted snapshot for recovery when confirmation does not complete.
            throw error
        }
    }

    private func verifyOTAPermissions(for device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/json/cfg") else {
            throw WLEDFirmwareUpdateError.invalidDeviceAddress
        }
        let (data, response) = try await urlSession.data(from: url)
        try validate(response)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WLEDFirmwareUpdateError.invalidDeviceResponse
        }
        let config = root["cfg"] as? [String: Any] ?? root
        let ota = config["ota"] as? [String: Any]
        if bool(ota?["lock"]) == true {
            throw WLEDFirmwareUpdateError.otaLocked
        }
    }

    private func upload(firmware: Data, named filename: String, to device: WLEDDevice) async throws {
        guard let url = URL(string: "http://\(device.ipAddress)/update") else {
            throw WLEDFirmwareUpdateError.invalidDeviceAddress
        }
        let boundary = "AesdeticFirmware-\(UUID().uuidString)"
        var body = Data()
        body.appendFirmwareUTF8("--\(boundary)\r\n")
        body.appendFirmwareUTF8("Content-Disposition: form-data; name=\"update\"; filename=\"\(filename)\"\r\n")
        body.appendFirmwareUTF8("Content-Type: application/octet-stream\r\n\r\n")
        body.append(firmware)
        body.appendFirmwareUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = body
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        let message = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        if message.contains("update failed") || message.contains("access denied") || message.contains("ota lock") {
            throw WLEDFirmwareUpdateError.deviceRejectedUpdate
        }
    }

    private func waitForReboot(
        of device: WLEDDevice,
        expectedVersion: String,
        progress: @escaping @MainActor (WLEDFirmwareUpdatePhase) -> Void
    ) async throws -> String {
        try await Task.sleep(nanoseconds: 3_000_000_000)
        await publish(.checking, to: progress)
        let deadline = Date().addingTimeInterval(100)
        while Date() < deadline {
            if let identity = try? await fetchIdentity(for: device),
               VersionComparator.compare(identity.version, expectedVersion) != .orderedAscending {
                return identity.version
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw WLEDFirmwareUpdateError.rebootTimedOut
    }

    private func loadCatalog() async throws -> WLEDFirmwareCatalog {
        // Production builds can supply both keys through Info.plist. A missing or
        // invalid remote catalog intentionally falls back to the bundled baseline.
        guard let endpoint = Bundle.main.object(forInfoDictionaryKey: "WLEDFirmwareCatalogRemoteURL") as? String,
              let url = URL(string: endpoint),
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "WLEDFirmwareCatalogSigningPublicKey") as? String,
              !publicKey.isEmpty else {
            return .bundled
        }
        do {
            let (data, response) = try await urlSession.data(from: url)
            try validate(response)
            let envelope = try JSONDecoder().decode(WLEDFirmwareCatalogEnvelope.self, from: data)
            guard let signature = Data(base64Encoded: envelope.signature),
                  let keyData = Data(base64Encoded: publicKey),
                  let payload = envelope.payload.data(using: .utf8) else {
                return .bundled
            }
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
            guard key.isValidSignature(signature, for: payload) else { return .bundled }
            let catalog = try JSONDecoder().decode(WLEDFirmwareCatalog.self, from: payload)
            return catalog.isExpired ? .bundled : catalog
        } catch {
            return .bundled
        }
    }

    private func fetchLatestRelease() async throws -> WLEDFirmwareRelease {
        guard let url = URL(string: "https://api.github.com/repos/wled/WLED/releases/latest") else {
            throw WLEDFirmwareUpdateError.releaseUnavailable
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Aesdetic-Control", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        try validate(response)
        let githubRelease = try JSONDecoder().decode(GitHubFirmwareRelease.self, from: data)
        let assets = githubRelease.assets.compactMap { asset -> WLEDFirmwareAsset? in
            guard let digest = asset.digest?.lowercased(), digest.hasPrefix("sha256:") else { return nil }
            return WLEDFirmwareAsset(
                name: asset.name,
                downloadURL: asset.downloadURL,
                sha256: String(digest.dropFirst("sha256:".count))
            )
        }
        return WLEDFirmwareRelease(version: VersionComparator.normalize(githubRelease.tagName), assets: assets)
    }

    private func publish(
        _ phase: WLEDFirmwareUpdatePhase,
        to progress: @escaping @MainActor (WLEDFirmwareUpdatePhase) -> Void
    ) async {
        await progress(phase)
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw WLEDFirmwareUpdateError.networkFailure
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["1", "true", "yes", "on"].contains(text.lowercased()) }
        return nil
    }
}

struct WLEDFirmwareIdentity: Equatable {
    let version: String
    let architecture: String?
    let brand: String?
    let product: String?
    let repository: String?
    let buildID: String?
}

struct WLEDFirmwareAsset: Codable, Equatable {
    let name: String
    let downloadURL: URL
    let sha256: String
}

struct WLEDFirmwareRelease: Codable, Equatable {
    let version: String
    let assets: [WLEDFirmwareAsset]

    func asset(named name: String) -> WLEDFirmwareAsset? {
        assets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

struct WLEDFirmwareCompatibilityProfile: Codable, Equatable, Identifiable {
    let id: String
    let architecture: String
    let requiredRepository: String?
    let assetSuffix: String

    func matches(_ identity: WLEDFirmwareIdentity) -> Bool {
        guard let deviceArchitecture = identity.architecture,
              deviceArchitecture.caseInsensitiveCompare(architecture) == .orderedSame else { return false }
        guard let requiredRepository else { return true }
        return identity.repository?.caseInsensitiveCompare(requiredRepository) == .orderedSame
            // WLED versions prior to 0.16 did not report `repo`; supported
            // Aesdetic hardware is still allowed through the baseline profile.
            || identity.repository == nil
    }

    func assetName(for version: String) -> String {
        "WLED_\(version)_\(assetSuffix).bin"
    }
}

struct WLEDFirmwareCatalog: Codable, Equatable {
    let issuedAt: Date
    let expiresAt: Date
    let isDisabled: Bool
    let approvedRelease: WLEDFirmwareRelease
    let profiles: [WLEDFirmwareCompatibilityProfile]

    var isExpired: Bool { expiresAt < Date() }

    func profile(for identity: WLEDFirmwareIdentity) -> WLEDFirmwareCompatibilityProfile? {
        profiles.first { $0.matches(identity) }
    }

    static let bundled = WLEDFirmwareCatalog(
        issuedAt: Date(timeIntervalSince1970: 1_778_000_000),
        expiresAt: Date(timeIntervalSince1970: 1_840_000_000),
        isDisabled: false,
        approvedRelease: WLEDFirmwareRelease(
            version: "16.0.0",
            assets: [
                WLEDFirmwareAsset(
                    name: "WLED_16.0.0_ESP32.bin",
                    downloadURL: URL(string: "https://github.com/wled/WLED/releases/download/v16.0.0/WLED_16.0.0_ESP32.bin")!,
                    sha256: "0e0c63dcc350b4c1a69d55fe592ce30228eb4abb0ce937ac0863d000b794558d"
                )
            ]
        ),
        profiles: [
            WLEDFirmwareCompatibilityProfile(
                id: "official-esp32",
                architecture: "esp32",
                requiredRepository: "wled/WLED",
                assetSuffix: "ESP32"
            )
        ]
    )
}

struct WLEDFirmwareCatalogEnvelope: Codable {
    let payload: String
    let signature: String
}

enum WLEDFirmwareUpdateAssessment: Equatable {
    case upToDate(current: String, target: String)
    case available(current: String, target: String, profile: WLEDFirmwareCompatibilityProfile)
    case manualUpdateRequired(String)
    case unavailable(String)
}

enum WLEDFirmwareUpdatePhase: Equatable {
    case preflight
    case creatingBackup
    case downloading
    case verifying
    case installing
    case restarting
    case checking

    var customerMessage: String {
        switch self {
        case .preflight: return "Preparing your lamp"
        case .creatingBackup: return "Saving your settings"
        case .downloading: return "Downloading supported software"
        case .verifying: return "Checking the update"
        case .installing: return "Installing supported software"
        case .restarting: return "Restarting your lamp"
        case .checking: return "Checking everything is ready"
        }
    }
}

enum WLEDFirmwareUpdateError: LocalizedError, Equatable {
    case nativeInstallationDisabled
    case invalidDeviceAddress
    case invalidDeviceResponse
    case networkFailure
    case releaseUnavailable
    case manualUpdateRequired
    case otaLocked
    case checksumMismatch
    case deviceRejectedUpdate
    case rebootTimedOut

    var errorDescription: String? {
        switch self {
        case .nativeInstallationDisabled: return "Automatic software installation is not enabled in this build."
        case .invalidDeviceAddress: return "This lamp’s address is invalid."
        case .invalidDeviceResponse: return "The lamp did not provide the information needed for an update."
        case .networkFailure: return "The software update could not connect to the lamp or update service."
        case .releaseUnavailable: return "The latest official WLED release is unavailable right now."
        case .manualUpdateRequired: return "A safe firmware match could not be identified. Use the manual WLED updater."
        case .otaLocked: return "Updates are locked in WLED security settings. Unlock OTA and try again."
        case .checksumMismatch: return "The downloaded software could not be verified."
        case .deviceRejectedUpdate: return "The lamp rejected this software update."
        case .rebootTimedOut: return "The lamp did not reconnect after the update."
        }
    }
}

private struct GitHubFirmwareRelease: Decodable {
    let tagName: String
    let assets: [GitHubFirmwareAsset]

    enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }
}

private struct GitHubFirmwareAsset: Decodable {
    let name: String
    let downloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey { case name, downloadURL = "browser_download_url", digest }
}

final class WLEDFirmwareBackupStore {
    static let shared = WLEDFirmwareBackupStore()

    private let fileManager = FileManager.default
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    func capture(for device: WLEDDevice, session: URLSession) async throws -> String {
        guard let configURL = URL(string: "http://\(device.ipAddress)/json/cfg"),
              let presetsURL = URL(string: "http://\(device.ipAddress)/presets.json") else {
            throw WLEDFirmwareUpdateError.invalidDeviceAddress
        }
        async let configResult = session.data(from: configURL)
        async let presetsResult = session.data(from: presetsURL)
        let (configData, configResponse) = try await configResult
        let (presetsData, presetsResponse) = try await presetsResult
        guard let configHTTP = configResponse as? HTTPURLResponse, (200...299).contains(configHTTP.statusCode),
              let presetsHTTP = presetsResponse as? HTTPURLResponse, (200...299).contains(presetsHTTP.statusCode) else {
            throw WLEDFirmwareUpdateError.networkFailure
        }
        let snapshot = WLEDFirmwareBackupSnapshot(
            deviceID: device.id,
            createdAt: Date(),
            configuration: sanitizedConfiguration(configData),
            presets: presetsData
        )
        let id = UUID().uuidString
        let data = try JSONEncoder().encode(snapshot)
        let encrypted = try AES.GCM.seal(data, using: try encryptionKey()).combined!
        let url = try directory().appendingPathComponent("\(id).backup")
        try encrypted.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return id
    }

    func remove(id: String) async {
        guard let url = try? directory().appendingPathComponent("\(id).backup") else { return }
        try? fileManager.removeItem(at: url)
    }

    func removeExpiredBackups() async {
        guard let directory = try? directory(),
              let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-retention)
        for url in urls {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? fileManager.removeItem(at: url) }
        }
    }

    private func directory() throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = root.appendingPathComponent("WLEDFirmwareBackups", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func encryptionKey() throws -> SymmetricKey {
        let service = "com.aesdetic.control.wled-firmware-backups"
        let account = "encryption-key"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw WLEDFirmwareUpdateError.networkFailure }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw WLEDFirmwareUpdateError.networkFailure }
        return SymmetricKey(data: data)
    }

    private func sanitizedConfiguration(_ data: Data) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        redactSecrets(in: &root)
        return (try? JSONSerialization.data(withJSONObject: root, options: [])) ?? data
    }

    private func redactSecrets(in value: inout [String: Any]) {
        let secretKeys: Set<String> = ["psk", "pass", "password", "pwd", "ssid", "mqtt", "token", "apikey"]
        for key in value.keys {
            if secretKeys.contains(key.lowercased()) {
                value[key] = "[redacted]"
            } else if var nested = value[key] as? [String: Any] {
                redactSecrets(in: &nested)
                value[key] = nested
            } else if var array = value[key] as? [[String: Any]] {
                for index in array.indices { redactSecrets(in: &array[index]) }
                value[key] = array
            }
        }
    }
}

private struct WLEDFirmwareBackupSnapshot: Codable {
    let deviceID: String
    let createdAt: Date
    let configuration: Data
    let presets: Data
}

private extension Data {
    mutating func appendFirmwareUTF8(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}
