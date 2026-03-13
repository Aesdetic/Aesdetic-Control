import Foundation

actor DeviceSyncManager {
    enum DispatchOutcome {
        case applied
        case downgraded
        case skipped
    }

    static let shared = DeviceSyncManager()

    private let userDefaults: UserDefaults
    private let profilesKey = "device.sync.profiles.v2"
    private var profilesBySource: [String: DeviceSyncProfile] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        profilesBySource = Self.decodeProfiles(
            from: userDefaults.data(forKey: profilesKey)
        )
    }

    func loadProfiles() -> [String: DeviceSyncProfile] {
        profilesBySource
    }

    func profile(for sourceId: String) -> DeviceSyncProfile {
        if let existing = profilesBySource[sourceId] {
            return existing
        }
        return DeviceSyncProfile(sourceDeviceId: sourceId)
    }

    @discardableResult
    func toggleTarget(sourceId: String, targetId: String) -> DeviceSyncProfile {
        var profile = profile(for: sourceId)
        profile.toggle(targetDeviceId: targetId)
        profilesBySource[sourceId] = profile
        persistProfiles()
        return profile
    }

    @discardableResult
    func clearTargets(sourceId: String) -> DeviceSyncProfile {
        var profile = profile(for: sourceId)
        profile.clearTargets()
        profilesBySource[sourceId] = profile
        persistProfiles()
        return profile
    }

    func setTargets(sourceId: String, targetIds: [String]) -> DeviceSyncProfile {
        var profile = DeviceSyncProfile(sourceDeviceId: sourceId, targetDeviceIds: targetIds)
        profile.updatedAt = Date()
        profilesBySource[sourceId] = profile
        persistProfiles()
        return profile
    }

    func dispatch(
        from sourceId: String,
        availableDevicesById: [String: WLEDDevice],
        apply: @Sendable (WLEDDevice) async -> DispatchOutcome
    ) async -> SyncDispatchSummary {
        let profile = profile(for: sourceId)
        guard !profile.targetDeviceIds.isEmpty else {
            return .idle
        }

        var applied = 0
        var downgraded = 0
        var skipped = 0

        for targetId in profile.targetDeviceIds {
            guard let target = availableDevicesById[targetId] else {
                skipped += 1
                continue
            }
            switch await apply(target) {
            case .applied:
                applied += 1
            case .downgraded:
                downgraded += 1
            case .skipped:
                skipped += 1
            }
        }

        return SyncDispatchSummary(applied: applied, downgraded: downgraded, skipped: skipped)
    }

    private static func decodeProfiles(from data: Data?) -> [String: DeviceSyncProfile] {
        guard let data else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: DeviceSyncProfile].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profilesBySource) else { return }
        userDefaults.set(data, forKey: profilesKey)
    }
}
