import Foundation

struct SceneGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var deviceScenes: [Scene]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        deviceScenes: [Scene]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.deviceScenes = deviceScenes
    }
}
