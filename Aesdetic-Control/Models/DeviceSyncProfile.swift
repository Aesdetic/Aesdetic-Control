import Foundation

struct DeviceSyncProfile: Codable, Equatable {
    let sourceDeviceId: String
    var targetDeviceIds: [String]
    var updatedAt: Date

    init(sourceDeviceId: String, targetDeviceIds: [String] = [], updatedAt: Date = Date()) {
        self.sourceDeviceId = sourceDeviceId
        self.targetDeviceIds = Array(Set(targetDeviceIds)).sorted()
        self.updatedAt = updatedAt
    }

    var isActive: Bool {
        !targetDeviceIds.isEmpty
    }

    mutating func toggle(targetDeviceId: String) {
        if let index = targetDeviceIds.firstIndex(of: targetDeviceId) {
            targetDeviceIds.remove(at: index)
        } else {
            targetDeviceIds.append(targetDeviceId)
        }
        targetDeviceIds = Array(Set(targetDeviceIds)).sorted()
        updatedAt = Date()
    }

    mutating func clearTargets() {
        targetDeviceIds.removeAll()
        updatedAt = Date()
    }
}
