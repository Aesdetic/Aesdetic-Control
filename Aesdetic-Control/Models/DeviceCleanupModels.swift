import Foundation

/// Represents a pending device-side deletion that needs to be processed
struct PendingDeviceDelete: Codable, Identifiable, Equatable {
    enum DeleteSource: String, Codable {
        case temporaryTransition
        case presetRenameSync
        case playlistRenameSync
        case automation
        case unknown
    }

    let id: UUID
    let type: DeleteType
    let deviceId: String
    var ids: [Int]  // Preset IDs, playlist IDs, or timer slot IDs
    var retries: Int
    var lastAttempt: Date?
    var nextAttemptAt: Date?
    var lastError: String?
    var source: DeleteSource
    var leaseId: UUID?
    var verificationRequired: Bool
    var deadLetteredAt: Date?
    let createdAt: Date
    
    enum DeleteType: String, Codable {
        case preset
        case playlist
        case timer
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case deviceId
        case ids
        case retries
        case lastAttempt
        case nextAttemptAt
        case lastError
        case source
        case leaseId
        case verificationRequired
        case deadLetteredAt
        case createdAt
    }
    
    init(
        id: UUID = UUID(),
        type: DeleteType,
        deviceId: String,
        ids: [Int],
        retries: Int = 0,
        lastAttempt: Date? = nil,
        nextAttemptAt: Date? = nil,
        lastError: String? = nil,
        source: DeleteSource = .unknown,
        leaseId: UUID? = nil,
        verificationRequired: Bool = false,
        deadLetteredAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.deviceId = deviceId
        self.ids = ids
        self.retries = retries
        self.lastAttempt = lastAttempt
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
        self.source = source
        self.leaseId = leaseId
        self.verificationRequired = verificationRequired
        self.deadLetteredAt = deadLetteredAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(DeleteType.self, forKey: .type)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.ids = try container.decode([Int].self, forKey: .ids)
        self.retries = try container.decodeIfPresent(Int.self, forKey: .retries) ?? 0
        self.lastAttempt = try container.decodeIfPresent(Date.self, forKey: .lastAttempt)
        self.nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        self.source = try container.decodeIfPresent(DeleteSource.self, forKey: .source) ?? .unknown
        self.leaseId = try container.decodeIfPresent(UUID.self, forKey: .leaseId)
        self.verificationRequired = try container.decodeIfPresent(Bool.self, forKey: .verificationRequired) ?? false
        self.deadLetteredAt = try container.decodeIfPresent(Date.self, forKey: .deadLetteredAt)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

enum TemporaryTransitionLeaseState: String, Codable {
    case allocating
    case ready
    case running
    case cancelRequested
    case cleanupPending
    case cleaned
    case failed
    case deadLetter
}

enum TemporaryTransitionEndReason: String, Codable {
    case completed
    case cancelledByUser
    case cancelledByWatchdog
    case cancelledByManualInput
    case cancelledByPresetSave
    case creationFailed
    case appRestartRecovery
}

enum PresetStoreHealthState: String, Codable {
    case healthy
    case degradedReadable
    case unsafeWritesPaused
}

struct PendingPresetStoreSyncItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case transitionPresetSave
        case presetSave
        case playlistSave
        case rename
    }

    let id: UUID
    let deviceId: String
    var kind: Kind
    var transitionPresetSnapshot: TransitionPreset?
    let createdAt: Date
    var retryCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        deviceId: String,
        kind: Kind,
        transitionPresetSnapshot: TransitionPreset? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.kind = kind
        self.transitionPresetSnapshot = transitionPresetSnapshot
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
    }
}

struct TemporaryTransitionLease: Codable, Identifiable, Equatable {
    let leaseId: UUID
    var id: UUID { leaseId }
    let deviceId: String
    var runId: UUID?
    var playlistId: Int?
    var stepPresetIds: [Int]
    let createdAt: Date
    var expectedEndAt: Date?
    var cleanupNotBefore: Date?
    var state: TemporaryTransitionLeaseState
    var isPersistentTransition: Bool
    var lastError: String?
    var cleanupAttemptCount: Int
    var endReason: TemporaryTransitionEndReason?

    init(
        leaseId: UUID = UUID(),
        deviceId: String,
        runId: UUID? = nil,
        playlistId: Int? = nil,
        stepPresetIds: [Int] = [],
        createdAt: Date = Date(),
        expectedEndAt: Date? = nil,
        cleanupNotBefore: Date? = nil,
        state: TemporaryTransitionLeaseState = .allocating,
        isPersistentTransition: Bool = false,
        lastError: String? = nil,
        cleanupAttemptCount: Int = 0,
        endReason: TemporaryTransitionEndReason? = nil
    ) {
        self.leaseId = leaseId
        self.deviceId = deviceId
        self.runId = runId
        self.playlistId = playlistId
        self.stepPresetIds = stepPresetIds
        self.createdAt = createdAt
        self.expectedEndAt = expectedEndAt
        self.cleanupNotBefore = cleanupNotBefore
        self.state = state
        self.isPersistentTransition = isPersistentTransition
        self.lastError = lastError
        self.cleanupAttemptCount = cleanupAttemptCount
        self.endReason = endReason
    }
}
