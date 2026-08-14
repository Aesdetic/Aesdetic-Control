import Foundation

/// Versioned, crash-safe persistence for destructive cleanup intent.
///
/// The primary file is replaced atomically and the previously decoded
/// generation is retained as a fallback. UserDefaults is used only as a
/// one-time migration source by callers.
@MainActor
final class CleanupJournalStore {
    static let shared = CleanupJournalStore()

    enum JournalError: Error {
        case applicationSupportUnavailable
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
                .appendingPathComponent("CleanupJournal", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("AesdeticControl", isDirectory: true)
                .appendingPathComponent("CleanupJournal", isDirectory: true)
        self.rootURL = resolvedRoot
        self.primaryURL = resolvedRoot.appendingPathComponent("cleanup-journal-v2.json")
        self.backupURL = resolvedRoot.appendingPathComponent("cleanup-journal-v2.backup.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    func load() throws -> CleanupJournalEnvelope {
        do {
            if let primary = try decodeIfPresent(primaryURL) {
                return primary
            }
        } catch {
            // Continue to the last decoded generation.
        }
        do {
            if let backup = try decodeIfPresent(backupURL) {
                try persist(backup, rotatePrimary: false)
                return backup
            }
        } catch {
            // The explicit error below distinguishes this from an empty journal.
        }
        if fileManager.fileExists(atPath: primaryURL.path)
            || fileManager.fileExists(atPath: backupURL.path) {
            throw JournalError.unreadablePrimaryAndBackup
        }
        return emptyEnvelope()
    }

    func savePendingDeletes(_ pendingDeletes: [PendingDeviceDelete]) throws {
        var envelope = try load()
        envelope.pendingDeletes = pendingDeletes
        envelope.updatedAt = Date()
        try persist(envelope, rotatePrimary: true)
    }

    func savePendingAutomationDeleteIds(_ ids: Set<UUID>) throws {
        var envelope = try load()
        envelope.pendingAutomationDeleteIds = ids.sorted { $0.uuidString < $1.uuidString }
        envelope.updatedAt = Date()
        try persist(envelope, rotatePrimary: true)
    }

    func migrateLegacyPendingDeletes(_ deletes: [PendingDeviceDelete]) throws -> [PendingDeviceDelete] {
        var envelope = try load()
        guard envelope.pendingDeletes.isEmpty else {
            return envelope.pendingDeletes
        }
        envelope.pendingDeletes = deletes
        envelope.updatedAt = Date()
        try persist(envelope, rotatePrimary: true)
        return deletes
    }

    private func emptyEnvelope() -> CleanupJournalEnvelope {
        CleanupJournalEnvelope(
            schemaVersion: CleanupJournalEnvelope.currentSchemaVersion,
            updatedAt: Date(),
            pendingDeletes: [],
            pendingAutomationDeleteIds: []
        )
    }

    private func decodeIfPresent(_ url: URL) throws -> CleanupJournalEnvelope? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let envelope = try decoder.decode(CleanupJournalEnvelope.self, from: data)
        guard envelope.schemaVersion <= CleanupJournalEnvelope.currentSchemaVersion else {
            throw JournalError.unreadablePrimaryAndBackup
        }
        return envelope
    }

    private func persist(
        _ envelope: CleanupJournalEnvelope,
        rotatePrimary: Bool
    ) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if rotatePrimary,
           let current = try? Data(contentsOf: primaryURL),
           (try? decoder.decode(CleanupJournalEnvelope.self, from: current)) != nil {
            try current.write(to: backupURL, options: [.atomic])
        }

        let data = try encoder.encode(envelope)
        try data.write(to: primaryURL, options: [.atomic])
        _ = try decoder.decode(CleanupJournalEnvelope.self, from: Data(contentsOf: primaryURL))
    }
}
