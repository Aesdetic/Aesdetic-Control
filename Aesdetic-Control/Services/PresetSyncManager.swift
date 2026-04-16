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

    enum PresetSyncManagerError: LocalizedError {
        case blockedByAutomationDeletion

        var errorDescription: String? {
            switch self {
            case .blockedByAutomationDeletion:
                return "Please wait for automation deletion to finish before saving a new preset."
            }
        }
    }

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

    private func assertPresetCreationAllowed() async throws {
        let deletionInProgress = await MainActor.run {
            AutomationStore.shared.hasAnyDeletionInProgress
        }
        if deletionInProgress {
            throw PresetSyncManagerError.blockedByAutomationDeletion
        }
    }

    func saveColorPreset(_ preset: ColorPreset, to device: WLEDDevice) async throws -> Int {
        try await assertPresetCreationAllowed()
        return try await enqueue(deviceId: device.id) {
            try await self.assertPresetCreationAllowed()
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
        try await assertPresetCreationAllowed()
        return try await enqueue(deviceId: device.id) {
            try await self.assertPresetCreationAllowed()
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

    @available(*, deprecated, message: "Transition UI saves must use DeviceControlViewModel.createTransitionPlaylist(... persist: true)")
    func saveTransitionPreset(_ preset: TransitionPreset, to device: WLEDDevice) async throws -> Int {
        #if DEBUG
        print("transition_preset.legacy_save_path_blocked device=\(device.id)")
        assertionFailure("Use DeviceControlViewModel.saveTransitionPresetToDevice/createTransitionPlaylist for transition presets")
        #endif
        try await assertPresetCreationAllowed()
        return try await enqueue(deviceId: device.id) {
            try await self.assertPresetCreationAllowed()
            let existingId = preset.wledPlaylistId
            let existingStepIds = preset.wledStepPresetIds ?? []
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
            if !existingStepIds.isEmpty,
               let playlists = try? await self.apiService.fetchPlaylists(for: device),
               let playlist = playlists.first(where: { $0.id == playlistId }) {
                let newStepIds = Set(playlist.presets)
                let staleStepIds = existingStepIds.filter { !newStepIds.contains($0) }
                for presetId in staleStepIds {
                    _ = try? await self.apiService.deletePreset(id: presetId, device: device)
                }
            }
            return playlistId
        }
    }

    private func resolvePresetId(for preset: ColorPreset, device: WLEDDevice, existingId: Int?) async throws -> Int {
        let existingPresets = try await apiService.fetchPresets(for: device)
        let used = Set(existingPresets.map { $0.id })
        if let existingId, (1...250).contains(existingId) {
            return existingId
        }
        return allocateId(used: used) ?? 1
    }

    private func resolvePresetId(for preset: WLEDEffectPreset, device: WLEDDevice, existingId: Int?) async throws -> Int {
        let existingPresets = try await apiService.fetchPresets(for: device)
        let used = Set(existingPresets.map { $0.id })
        if let existingId, (1...250).contains(existingId) {
            return existingId
        }
        return allocateId(used: used) ?? 1
    }

    private func resolvePlaylistId(for preset: TransitionPreset, device: WLEDDevice, existingId: Int?) async throws -> Int {
        let existingPresets = try await apiService.fetchPresets(for: device)
        let used = Set(existingPresets.map { $0.id })
        if let existingId, (1...250).contains(existingId) {
            return existingId
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
            do {
                let presets = try await apiService.fetchPresets(for: device)
                #if DEBUG
                print("🔎 Verify preset \(id) on \(device.name): attempt=\(attempt) count=\(presets.count)")
                #endif
                if presets.contains(where: { $0.id == id }) {
                    return
                }
            } catch {
                #if DEBUG
                print("⚠️ Verify preset \(id) failed to fetch presets on \(device.name): \(error.localizedDescription)")
                #endif
                // If we can't read presets.json, don't block saves.
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
            do {
                let playlists = try await apiService.fetchPlaylists(for: device)
                #if DEBUG
                print("🔎 Verify playlist \(id) on \(device.name): attempt=\(attempt) count=\(playlists.count)")
                #endif
                if playlists.contains(where: { $0.id == id }) {
                    return
                }
            } catch {
                #if DEBUG
                print("⚠️ Verify playlist \(id) failed to fetch playlists on \(device.name): \(error.localizedDescription)")
                #endif
                // If we can't read presets.json, don't block saves.
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
