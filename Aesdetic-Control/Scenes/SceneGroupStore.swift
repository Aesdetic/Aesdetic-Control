import Foundation

final class SceneGroupStore: ObservableObject {
    static let shared = SceneGroupStore()
    @Published private(set) var scenes: [SceneGroup] = []

    private let key = "aesdetic_scene_groups_v1"

    private init() {
        load()
    }

    func add(_ scene: SceneGroup) {
        scenes.append(scene)
        save()
    }

    func upsert(_ scene: SceneGroup) {
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[index] = scene
        } else {
            scenes.append(scene)
        }
        save()
    }

    func remove(_ id: UUID) {
        scenes.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let list = try? JSONDecoder().decode([SceneGroup].self, from: data) {
            scenes = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
