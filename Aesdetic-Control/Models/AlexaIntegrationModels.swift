import Foundation

enum AlexaFavoriteSourceType: String, Codable, CaseIterable {
    case color
    case effect
    case transition
    case wledPreset
    case wledPlaylist

    var displayName: String {
        switch self {
        case .color: return "Color"
        case .effect: return "Animation"
        case .transition: return "Transition"
        case .wledPreset: return "WLED Preset"
        case .wledPlaylist: return "WLED Playlist"
        }
    }
}

enum AlexaFavoriteSyncState: String, Codable {
    case synced
    case pending
    case conflict
    case failed

    var displayName: String {
        switch self {
        case .synced: return "Synced"
        case .pending: return "Pending"
        case .conflict: return "Conflict"
        case .failed: return "Failed"
        }
    }
}

struct AlexaFavorite: Identifiable, Codable, Equatable {
    let id: UUID
    var deviceId: String
    var sourceType: AlexaFavoriteSourceType
    var sourceId: UUID?
    var sourceWLEDPresetId: Int
    var displayName: String
    var slot: Int
    var syncState: AlexaFavoriteSyncState
    var lastSyncError: String?
    var isManuallyRemovedFromAutoFill: Bool

    init(
        id: UUID = UUID(),
        deviceId: String,
        sourceType: AlexaFavoriteSourceType,
        sourceId: UUID?,
        sourceWLEDPresetId: Int,
        displayName: String,
        slot: Int,
        syncState: AlexaFavoriteSyncState = .pending,
        lastSyncError: String? = nil,
        isManuallyRemovedFromAutoFill: Bool = false
    ) {
        self.id = id
        self.deviceId = deviceId
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.sourceWLEDPresetId = sourceWLEDPresetId
        self.displayName = displayName
        self.slot = slot
        self.syncState = syncState
        self.lastSyncError = lastSyncError
        self.isManuallyRemovedFromAutoFill = isManuallyRemovedFromAutoFill
    }
}

struct AlexaFavoriteCandidate: Identifiable, Equatable {
    let sourceType: AlexaFavoriteSourceType
    let sourceId: UUID?
    let sourceWLEDPresetId: Int
    let displayName: String

    var id: String {
        "\(sourceType.rawValue)-\(sourceId?.uuidString ?? String(sourceWLEDPresetId))-\(sourceWLEDPresetId)"
    }
}

struct WLEDAlexaMirrorFavorite: Equatable {
    let slot: Int
    let sourcePresetId: Int
    let displayName: String
}

struct WLEDAlexaMirrorSyncResult: Equatable {
    let mirroredSlots: [Int]
    let deletedSlots: [Int]
    let conflictSlots: [Int]
    let missingSourceIds: [Int]

    var succeeded: Bool {
        conflictSlots.isEmpty && missingSourceIds.isEmpty
    }
}
