import Foundation

/// Atomic app-local persistence for last-known verified routine evidence.
/// This store never writes to WLED and is not used as current-generation proof.
@MainActor
final class RoutineVerificationReceiptStore {
    static let shared = RoutineVerificationReceiptStore()

    enum StoreError: Error {
        case unreadablePrimaryAndBackup
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let primaryURL: URL
    private let backupURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let resolvedRoot = rootURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("AesdeticControl", isDirectory: true)
                .appendingPathComponent("RoutineVerification", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("AesdeticControl", isDirectory: true)
                .appendingPathComponent("RoutineVerification", isDirectory: true)
        self.rootURL = resolvedRoot
        self.primaryURL = resolvedRoot.appendingPathComponent("routine-verification-v1.json")
        self.backupURL = resolvedRoot.appendingPathComponent("routine-verification-v1.backup.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    func load() throws -> [RoutineDeviceKey: RoutineVerificationReceipt] {
        if let primary = try? decodeIfPresent(primaryURL) {
            return dictionary(from: primary)
        }
        if let backup = try? decodeIfPresent(backupURL) {
            try persist(backup, rotatePrimary: false)
            return dictionary(from: backup)
        }
        if fileManager.fileExists(atPath: primaryURL.path)
            || fileManager.fileExists(atPath: backupURL.path) {
            throw StoreError.unreadablePrimaryAndBackup
        }
        return [:]
    }

    func save(_ receipts: [RoutineDeviceKey: RoutineVerificationReceipt]) throws {
        let envelope = RoutineVerificationReceiptEnvelope(
            schemaVersion: RoutineVerificationReceiptEnvelope.currentSchemaVersion,
            updatedAt: Date(),
            receipts: receipts.values.sorted {
                if $0.key.deviceId != $1.key.deviceId {
                    return $0.key.deviceId < $1.key.deviceId
                }
                return $0.key.automationId.uuidString < $1.key.automationId.uuidString
            }
        )
        try persist(envelope, rotatePrimary: true)
    }

    private func decodeIfPresent(_ url: URL) throws -> RoutineVerificationReceiptEnvelope? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let envelope = try decoder.decode(
            RoutineVerificationReceiptEnvelope.self,
            from: Data(contentsOf: url)
        )
        guard envelope.schemaVersion <= RoutineVerificationReceiptEnvelope.currentSchemaVersion else {
            throw StoreError.unreadablePrimaryAndBackup
        }
        return envelope
    }

    private func dictionary(
        from envelope: RoutineVerificationReceiptEnvelope
    ) -> [RoutineDeviceKey: RoutineVerificationReceipt] {
        Dictionary(envelope.receipts.map { ($0.key, $0) }, uniquingKeysWith: { _, newest in newest })
    }

    private func persist(
        _ envelope: RoutineVerificationReceiptEnvelope,
        rotatePrimary: Bool
    ) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        if rotatePrimary,
           let current = try? Data(contentsOf: primaryURL),
           (try? decoder.decode(RoutineVerificationReceiptEnvelope.self, from: current)) != nil {
            try current.write(to: backupURL, options: [.atomic])
        }
        let encoded = try encoder.encode(envelope)
        try encoded.write(to: primaryURL, options: [.atomic])
        _ = try decoder.decode(
            RoutineVerificationReceiptEnvelope.self,
            from: Data(contentsOf: primaryURL)
        )
    }
}
