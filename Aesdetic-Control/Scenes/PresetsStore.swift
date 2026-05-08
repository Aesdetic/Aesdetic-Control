import Foundation

@MainActor
final class PresetsStore: ObservableObject {
    static let shared = PresetsStore()
    
    @Published private(set) var colorPresets: [ColorPreset] = []
    @Published private(set) var transitionPresets: [TransitionPreset] = []
    @Published private(set) var effectPresets: [WLEDEffectPreset] = []
    @Published private(set) var alexaFavorites: [AlexaFavorite] = []
    @Published private(set) var alexaAutoFillEnabledByDeviceId: [String: Bool] = [:]
    
    private let colorPresetsKey = "aesdetic_color_presets_v1"
    private let transitionPresetsKey = "aesdetic_transition_presets_v1"
    private let effectPresetsKey = "aesdetic_effect_presets_v1"
    private let alexaFavoritesKey = "aesdetic_alexa_favorites_v1"
    private let alexaAutoFillKey = "aesdetic_alexa_autofill_v1"
    
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
    
    func colorPreset(id: UUID) -> ColorPreset? {
        colorPresets.first(where: { $0.id == id })
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
    
    func transitionPreset(id: UUID) -> TransitionPreset? {
        transitionPresets.first(where: { $0.id == id })
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
    
    func effectPreset(id: UUID) -> WLEDEffectPreset? {
        effectPresets.first(where: { $0.id == id })
    }

    // MARK: - Alexa Favorites

    func alexaFavorites(for deviceId: String, includeRemoved: Bool = false) -> [AlexaFavorite] {
        alexaFavorites
            .filter { $0.deviceId == deviceId && (includeRemoved || !$0.isManuallyRemovedFromAutoFill) }
            .sorted { lhs, rhs in
                if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func alexaAutoFillEnabled(for deviceId: String) -> Bool {
        alexaAutoFillEnabledByDeviceId[deviceId] ?? true
    }

    func setAlexaAutoFillEnabled(_ enabled: Bool, for deviceId: String) {
        alexaAutoFillEnabledByDeviceId[deviceId] = enabled
        saveAlexaAutoFill()
    }

    @discardableResult
    func addAlexaFavorite(_ candidate: AlexaFavoriteCandidate, for deviceId: String) -> Bool {
        guard appManagedPresetRange.contains(candidate.sourceWLEDPresetId) else { return false }
        let key = alexaFavoriteKey(
            deviceId: deviceId,
            sourceType: candidate.sourceType,
            sourceId: candidate.sourceId,
            sourceWLEDPresetId: candidate.sourceWLEDPresetId
        )
        if let existingIndex = alexaFavorites.firstIndex(where: { alexaFavoriteKey($0) == key }) {
            if alexaFavorites[existingIndex].isManuallyRemovedFromAutoFill {
                alexaFavorites[existingIndex].isManuallyRemovedFromAutoFill = false
                alexaFavorites[existingIndex].displayName = candidate.displayName
                alexaFavorites[existingIndex].syncState = .pending
                alexaFavorites[existingIndex].lastSyncError = nil
                compactAlexaFavorites(for: deviceId, saveAfterCompaction: false)
                saveAlexaFavorites()
            }
            return true
        }

        guard alexaFavorites(for: deviceId).count < alexaReservedPresetRange.count else { return false }
        let nextSlot = nextAlexaSlot(for: deviceId)
        let favorite = AlexaFavorite(
            deviceId: deviceId,
            sourceType: candidate.sourceType,
            sourceId: candidate.sourceId,
            sourceWLEDPresetId: candidate.sourceWLEDPresetId,
            displayName: candidate.displayName,
            slot: nextSlot
        )
        alexaFavorites.append(favorite)
        compactAlexaFavorites(for: deviceId, saveAfterCompaction: false)
        saveAlexaFavorites()
        return true
    }

    func removeAlexaFavorite(_ favoriteId: UUID, for deviceId: String) {
        guard let index = alexaFavorites.firstIndex(where: { $0.id == favoriteId && $0.deviceId == deviceId }) else { return }
        alexaFavorites[index].isManuallyRemovedFromAutoFill = true
        alexaFavorites[index].slot = 0
        alexaFavorites[index].syncState = .pending
        alexaFavorites[index].lastSyncError = nil
        compactAlexaFavorites(for: deviceId, saveAfterCompaction: false)
        saveAlexaFavorites()
    }

    func clearAlexaFavorites(for deviceId: String) {
        alexaFavorites.removeAll { $0.deviceId == deviceId }
        saveAlexaFavorites()
    }

    @discardableResult
    func autoFillAlexaFavorites(for deviceId: String, candidates: [AlexaFavoriteCandidate]) -> [AlexaFavorite] {
        var active = alexaFavorites(for: deviceId)
        var activeKeys = Set(active.map(alexaFavoriteKey))
        let removedKeys = Set(
            alexaFavorites(for: deviceId, includeRemoved: true)
                .filter(\.isManuallyRemovedFromAutoFill)
                .map(alexaFavoriteKey)
        )

        for candidate in candidates {
            guard active.count < alexaReservedPresetRange.count else { break }
            guard appManagedPresetRange.contains(candidate.sourceWLEDPresetId) else { continue }
            let candidateKey = alexaFavoriteKey(
                deviceId: deviceId,
                sourceType: candidate.sourceType,
                sourceId: candidate.sourceId,
                sourceWLEDPresetId: candidate.sourceWLEDPresetId
            )
            guard !activeKeys.contains(candidateKey), !removedKeys.contains(candidateKey) else { continue }
            let favorite = AlexaFavorite(
                deviceId: deviceId,
                sourceType: candidate.sourceType,
                sourceId: candidate.sourceId,
                sourceWLEDPresetId: candidate.sourceWLEDPresetId,
                displayName: candidate.displayName,
                slot: active.count + 1
            )
            alexaFavorites.append(favorite)
            active.append(favorite)
            activeKeys.insert(candidateKey)
        }

        compactAlexaFavorites(for: deviceId, saveAfterCompaction: false)
        saveAlexaFavorites()
        return alexaFavorites(for: deviceId)
    }

    func markAlexaFavorites(_ favorites: [AlexaFavorite], state: AlexaFavoriteSyncState, error: String? = nil) {
        let ids = Set(favorites.map(\.id))
        for index in alexaFavorites.indices where ids.contains(alexaFavorites[index].id) {
            alexaFavorites[index].syncState = state
            alexaFavorites[index].lastSyncError = error
        }
        saveAlexaFavorites()
    }

    func markAlexaFavoritesForDevice(_ deviceId: String, state: AlexaFavoriteSyncState, error: String? = nil) {
        for index in alexaFavorites.indices where alexaFavorites[index].deviceId == deviceId && !alexaFavorites[index].isManuallyRemovedFromAutoFill {
            alexaFavorites[index].syncState = state
            alexaFavorites[index].lastSyncError = error
        }
        saveAlexaFavorites()
    }

    func isAlexaFavorite(_ candidate: AlexaFavoriteCandidate, for deviceId: String) -> Bool {
        let key = alexaFavoriteKey(
            deviceId: deviceId,
            sourceType: candidate.sourceType,
            sourceId: candidate.sourceId,
            sourceWLEDPresetId: candidate.sourceWLEDPresetId
        )
        return alexaFavorites(for: deviceId).contains { alexaFavoriteKey($0) == key }
    }
    
    // MARK: - Persistence
    
    private func load() {
        loadColorPresets()
        loadTransitionPresets()
        loadEffectPresets()
        loadAlexaFavorites()
        loadAlexaAutoFill()
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

    private func loadAlexaFavorites() {
        guard let data = UserDefaults.standard.data(forKey: alexaFavoritesKey) else { return }
        if let favorites = try? JSONDecoder().decode([AlexaFavorite].self, from: data) {
            alexaFavorites = favorites
        }
    }

    private func loadAlexaAutoFill() {
        guard let data = UserDefaults.standard.data(forKey: alexaAutoFillKey) else { return }
        if let settings = try? JSONDecoder().decode([String: Bool].self, from: data) {
            alexaAutoFillEnabledByDeviceId = settings
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

    private func saveAlexaFavorites() {
        if let data = try? JSONEncoder().encode(alexaFavorites) {
            UserDefaults.standard.set(data, forKey: alexaFavoritesKey)
        }
    }

    private func saveAlexaAutoFill() {
        if let data = try? JSONEncoder().encode(alexaAutoFillEnabledByDeviceId) {
            UserDefaults.standard.set(data, forKey: alexaAutoFillKey)
        }
    }

    private func nextAlexaSlot(for deviceId: String) -> Int {
        let usedSlots = Set(alexaFavorites(for: deviceId).map(\.slot))
        return alexaReservedPresetRange.first(where: { !usedSlots.contains($0) }) ?? alexaReservedPresetRange.upperBound
    }

    private func compactAlexaFavorites(for deviceId: String, saveAfterCompaction: Bool = true) {
        let activeIds = alexaFavorites(for: deviceId).map(\.id)
        for (offset, favoriteId) in activeIds.enumerated() {
            guard let index = alexaFavorites.firstIndex(where: { $0.id == favoriteId }) else { continue }
            alexaFavorites[index].slot = alexaReservedPresetRange.lowerBound + offset
        }
        if saveAfterCompaction {
            saveAlexaFavorites()
        }
    }

    private func alexaFavoriteKey(_ favorite: AlexaFavorite) -> String {
        alexaFavoriteKey(
            deviceId: favorite.deviceId,
            sourceType: favorite.sourceType,
            sourceId: favorite.sourceId,
            sourceWLEDPresetId: favorite.sourceWLEDPresetId
        )
    }

    private func alexaFavoriteKey(_ candidate: AlexaFavoriteCandidate) -> String {
        "\(candidate.sourceType.rawValue)|\(candidate.sourceId?.uuidString ?? "wled")|\(candidate.sourceWLEDPresetId)"
    }

    private func alexaFavoriteKey(
        deviceId: String,
        sourceType: AlexaFavoriteSourceType,
        sourceId: UUID?,
        sourceWLEDPresetId: Int
    ) -> String {
        "\(deviceId)|\(sourceType.rawValue)|\(sourceId?.uuidString ?? "wled")|\(sourceWLEDPresetId)"
    }

    func debugResetAlexaFavoritesForTests(deviceId: String) {
        alexaFavorites.removeAll { $0.deviceId == deviceId }
        alexaAutoFillEnabledByDeviceId.removeValue(forKey: deviceId)
        saveAlexaFavorites()
        saveAlexaAutoFill()
    }
}
