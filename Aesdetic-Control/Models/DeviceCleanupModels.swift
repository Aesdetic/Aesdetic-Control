import Foundation

/// Represents a pending device-side deletion that needs to be processed
struct PendingDeviceDelete: Codable, Identifiable, Equatable {
    let id: UUID
    let type: DeleteType
    let deviceId: String
    let ids: [Int]  // Preset IDs, playlist IDs, or timer slot IDs
    var retries: Int
    var lastAttempt: Date?
    let createdAt: Date
    
    enum DeleteType: String, Codable {
        case preset
        case playlist
        case timer
    }
    
    init(
        id: UUID = UUID(),
        type: DeleteType,
        deviceId: String,
        ids: [Int],
        retries: Int = 0,
        lastAttempt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.deviceId = deviceId
        self.ids = ids
        self.retries = retries
        self.lastAttempt = lastAttempt
        self.createdAt = createdAt
    }
}
