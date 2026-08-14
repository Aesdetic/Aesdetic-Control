import Foundation

enum PresetStoreMutationOutcome: String, Codable, Equatable {
    case committed
    case recoveredWithoutCommit
    case recoveryPending
    case needsRepair

    var isCommitted: Bool {
        self == .committed
    }
}

enum PresetStoreTransactionStatus: String, Codable, Equatable {
    case idle
    case saving
    case verifying
    case recovering
    case verificationNeeded
    case needsRepair

    var blocksPersistentEdits: Bool {
        switch self {
        case .idle:
            return false
        case .saving, .verifying, .recovering, .verificationNeeded, .needsRepair:
            return true
        }
    }
}

struct PresetStoreTransactionJournal: Codable, Equatable, Identifiable {
    enum OperationKind: String, Codable {
        case presetSave
        case playlistSave
        case batchUpsert
        case delete
        case rename
        case alexaMirror
        case recovery
    }

    enum Phase: String, Codable {
        case prepared
        case uploadingCandidate
        case outcomeUnknown
        case verifyingCandidate
        case restoringBackup
        case replayingCandidate
        case verifyingRestore
        case recoveredWithoutCommit
        case needsRepair
    }

    let id: UUID
    let deviceId: String
    let deviceIPAddress: String
    let deviceName: String
    let operation: OperationKind
    let playlistIds: [Int]
    let presetIds: [Int]
    let originalHash: String
    let candidateHash: String
    let originalByteCount: Int
    let candidateByteCount: Int
    let originalSnapshotName: String
    let candidateSnapshotName: String
    let createdAt: Date
    var updatedAt: Date
    var phase: Phase
    var replayCount: Int
    var recoveryAttemptCount: Int
    var lastError: String?
}
