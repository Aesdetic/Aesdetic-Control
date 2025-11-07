import Foundation

@MainActor
final class PresetsStore: ObservableObject {
    static let shared = PresetsStore()
    
    @Published private(set) var colorPresets: [ColorPreset] = []
    @Published private(set) var transitionPresets: [TransitionPreset] = []
    @Published private(set) var effectPresets: [WLEDEffectPreset] = []
    
    private let colorPresetsKey = "aesdetic_color_presets_v1"
    private let transitionPresetsKey = "aesdetic_transition_presets_v1"
    private let effectPresetsKey = "aesdetic_effect_presets_v1"
    
    private init() {
        load()
    }
    
    // MARK: - Color Presets (Shared across devices)
    
    func addColorPreset(_ preset: ColorPreset) {
        colorPresets.append(preset)
        saveColorPresets()
    }
    
    func removeColorPreset(_ id: UUID) {
        colorPresets.removeAll { $0.id == id }
        saveColorPresets()
    }
    
    func updateColorPreset(_ preset: ColorPreset) {
        if let index = colorPresets.firstIndex(where: { $0.id == preset.id }) {
            colorPresets[index] = preset
            saveColorPresets()
        }
    }
    
    func updateTransitionPreset(_ preset: TransitionPreset) {
        if let index = transitionPresets.firstIndex(where: { $0.id == preset.id }) {
            transitionPresets[index] = preset
            saveTransitionPresets()
        }
    }
    
    func updateEffectPreset(_ preset: WLEDEffectPreset) {
        if let index = effectPresets.firstIndex(where: { $0.id == preset.id }) {
            effectPresets[index] = preset
            saveEffectPresets()
        }
    }
    
    // MARK: - Transition Presets (Per-device)
    
    func addTransitionPreset(_ preset: TransitionPreset) {
        transitionPresets.append(preset)
        saveTransitionPresets()
    }
    
    func removeTransitionPreset(_ id: UUID) {
        transitionPresets.removeAll { $0.id == id }
        saveTransitionPresets()
    }
    
    func transitionPresets(for deviceId: String) -> [TransitionPreset] {
        transitionPresets.filter { $0.deviceId == deviceId }
    }
    
    // MARK: - Effect Presets (Per-device)
    
    func addEffectPreset(_ preset: WLEDEffectPreset) {
        effectPresets.append(preset)
        saveEffectPresets()
    }
    
    func removeEffectPreset(_ id: UUID) {
        effectPresets.removeAll { $0.id == id }
        saveEffectPresets()
    }
    
    func effectPresets(for deviceId: String) -> [WLEDEffectPreset] {
        effectPresets.filter { $0.deviceId == deviceId }
    }
    
    // MARK: - Persistence
    
    private func load() {
        loadColorPresets()
        loadTransitionPresets()
        loadEffectPresets()
    }
    
    private func loadColorPresets() {
        guard let data = UserDefaults.standard.data(forKey: colorPresetsKey) else { return }
        if let presets = try? JSONDecoder().decode([ColorPreset].self, from: data) {
            colorPresets = presets
        }
    }
    
    private func loadTransitionPresets() {
        guard let data = UserDefaults.standard.data(forKey: transitionPresetsKey) else { return }
        if let presets = try? JSONDecoder().decode([TransitionPreset].self, from: data) {
            transitionPresets = presets
        }
    }
    
    private func loadEffectPresets() {
        guard let data = UserDefaults.standard.data(forKey: effectPresetsKey) else { return }
        if let presets = try? JSONDecoder().decode([WLEDEffectPreset].self, from: data) {
            effectPresets = presets
        }
    }
    
    private func saveColorPresets() {
        if let data = try? JSONEncoder().encode(colorPresets) {
            UserDefaults.standard.set(data, forKey: colorPresetsKey)
        }
    }
    
    private func saveTransitionPresets() {
        if let data = try? JSONEncoder().encode(transitionPresets) {
            UserDefaults.standard.set(data, forKey: transitionPresetsKey)
        }
    }
    
    private func saveEffectPresets() {
        if let data = try? JSONEncoder().encode(effectPresets) {
            UserDefaults.standard.set(data, forKey: effectPresetsKey)
        }
    }
}

