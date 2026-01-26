import Foundation

actor PresetSyncManager {
    static let shared = PresetSyncManager()

    private let apiService = WLEDAPIService.shared
    private var deviceQueues: [String: Task<Void, Never>] = [:]
    private var deviceQueueTokens: [String: Int] = [:]
    private let saveRetryAttempts = 3
    private let verifyRetryAttempts = 4
    private let saveBaseDelayNanos: UInt64 = 400_000_000
    private let verifyBaseDelayNanos: UInt64 = 500_000_000

    private func enqueue<T>(deviceId: String, operation: @escaping () async throws -> T) async throws -> T {
        let previous = deviceQueues[deviceId]
        let token = (deviceQueueTokens[deviceId] ?? 0) + 1
        deviceQueueTokens[deviceId] = token
        let task = Task<T, Error> {
            if let previous {
                _ = await previous.result
            }
            return try await operation()
        }
        deviceQueues[deviceId] = Task { _ = try? await task.value }
        defer {
            if deviceQueueTokens[deviceId] == token {
                deviceQueues.removeValue(forKey: deviceId)
                deviceQueueTokens.removeValue(forKey: deviceId)
            }
        }
        return try await task.value
    }

    func saveColorPreset(_ preset: ColorPreset, to device: WLEDDevice) async throws -> Int {
        try await enqueue(deviceId: device.id) {
            let existingId = preset.wledPresetIds?[device.id] ?? preset.wledPresetId
            let presetId = try await self.resolvePresetId(for: preset, device: device, existingId: existingId)
            #if DEBUG
            print("🔎 Save color preset for \(device.name): id=\(presetId) existing=\(existingId.map(String.init) ?? "nil")")
            #endif
            try await self.performSaveWithRetry {
                _ = try await self.apiService.saveColorPreset(preset, to: device, presetId: presetId)
            }
            try await self.verifyPresetExists(id: presetId, device: device)
            if let existingId, existingId != presetId {
                _ = try? await self.apiService.deletePreset(id: existingId, device: device)
            }
            return presetId
        }
    }

    func saveEffectPreset(_ preset: WLEDEffectPreset, to device: WLEDDevice) async throws -> Int {
        try await enqueue(deviceId: device.id) {
            let existingId = preset.wledPresetId
            let presetId = try await self.resolvePresetId(for: preset, device: device, existingId: existingId)
            #if DEBUG
            print("🔎 Save effect preset for \(device.name): id=\(presetId) existing=\(existingId.map(String.init) ?? "nil")")
            #endif
            try await self.performSaveWithRetry {
                _ = try await self.apiService.saveEffectPreset(preset, to: device, presetId: presetId)
            }
            try await self.verifyPresetExists(id: presetId, device: device)
            if let existingId, existingId != presetId {
                _ = try? await self.apiService.deletePreset(id: existingId, device: device)
            }
            return presetId
        }
    }

    func saveTransitionPreset(_ preset: TransitionPreset, to device: WLEDDevice) async throws -> Int {
        try await enqueue(deviceId: device.id) {
            let existingId = preset.wledPlaylistId
            let playlistId = try await self.resolvePlaylistId(for: preset, device: device, existingId: existingId)
            #if DEBUG
            print("🔎 Save transition preset for \(device.name): id=\(playlistId) existing=\(existingId.map(String.init) ?? "nil")")
            #endif
            try await self.performSaveWithRetry {
                _ = try await self.apiService.saveTransitionPreset(preset, to: device, playlistId: playlistId)
            }
            try await self.verifyPlaylistExists(id: playlistId, device: device)
            if let existingId, existingId != playlistId {
                _ = try? await self.apiService.deletePlaylist(id: existingId, device: device)
            }
            return playlistId
        }
    }

    private func resolvePresetId(for preset: ColorPreset, device: WLEDDevice, existingId: Int?) async throws -> Int {
        let existingPresets = try await apiService.fetchPresets(for: device)
        let used = Set(existingPresets.map { $0.id })
        if existingId != nil, let newId = allocateId(used: used) {
            return newId
        }
        return allocateId(used: used) ?? 1
    }

    private func resolvePresetId(for preset: WLEDEffectPreset, device: WLEDDevice, existingId: Int?) async throws -> Int {
        let existingPresets = try await apiService.fetchPresets(for: device)
        let used = Set(existingPresets.map { $0.id })
        if existingId != nil, let newId = allocateId(used: used) {
            return newId
        }
        return allocateId(used: used) ?? 1
    }

    private func resolvePlaylistId(for preset: TransitionPreset, device: WLEDDevice, existingId: Int?) async throws -> Int {
        let existingPresets = try await apiService.fetchPresets(for: device)
        let used = Set(existingPresets.map { $0.id })
        if existingId != nil, let newId = allocateId(used: used) {
            return newId
        }
        return allocateId(used: used) ?? 1
    }

    private func allocateId(used: Set<Int>) -> Int? {
        for id in 1...250 where !used.contains(id) {
            return id
        }
        return nil
    }

    private func verifyPresetExists(id: Int, device: WLEDDevice) async throws {
        for attempt in 1...verifyRetryAttempts {
            let presets = try await apiService.fetchPresets(for: device)
            #if DEBUG
            print("🔎 Verify preset \(id) on \(device.name): attempt=\(attempt) count=\(presets.count)")
            #endif
            if presets.contains(where: { $0.id == id }) {
                return
            }
            if attempt < verifyRetryAttempts {
                let delay = verifyBaseDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw WLEDAPIError.invalidResponse
    }

    private func verifyPlaylistExists(id: Int, device: WLEDDevice) async throws {
        for attempt in 1...verifyRetryAttempts {
            let playlists = try await apiService.fetchPlaylists(for: device)
            #if DEBUG
            print("🔎 Verify playlist \(id) on \(device.name): attempt=\(attempt) count=\(playlists.count)")
            #endif
            if playlists.contains(where: { $0.id == id }) {
                return
            }
            if attempt < verifyRetryAttempts {
                let delay = verifyBaseDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw WLEDAPIError.invalidResponse
    }

    private func performSaveWithRetry(_ operation: @escaping () async throws -> Void) async throws {
        var lastError: Error?
        for attempt in 1...saveRetryAttempts {
            do {
                try await operation()
                let delay = saveBaseDelayNanos * UInt64(attempt)
                #if DEBUG
                print("✅ Preset save attempt \(attempt) succeeded, delaying \(Double(delay) / 1_000_000_000.0)s")
                #endif
                try? await Task.sleep(nanoseconds: delay)
                return
            } catch {
                lastError = error
                #if DEBUG
                print("⚠️ Preset save attempt \(attempt) failed: \(error.localizedDescription)")
                #endif
                if attempt < saveRetryAttempts {
                    let delay = saveBaseDelayNanos * UInt64(attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError ?? WLEDAPIError.invalidResponse
    }
}
