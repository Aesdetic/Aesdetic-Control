import Foundation

final class ScenesStore: ObservableObject {
    static let shared = ScenesStore()
    @Published private(set) var scenes: [Scene] = []

    private let key = "aesdetic_scenes_v1"

    private init() {
        load()
    }

    func add(_ scene: Scene) {
        scenes.append(scene)
        save()
    }

    func remove(_ id: UUID) {
        scenes.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let list = try? JSONDecoder().decode([Scene].self, from: data) {
            scenes = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}


