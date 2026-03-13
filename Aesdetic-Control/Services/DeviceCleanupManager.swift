import Foundation
import Combine
import os.log

/// Manages pending device-side deletions that need to be processed when devices come online
@MainActor
final class DeviceCleanupManager: ObservableObject {
    static let shared = DeviceCleanupManager()
    
    @Published private(set) var pendingDeletes: [PendingDeviceDelete] = []
    
    private let queueKey = "aesdetic_device_cleanup_queue_v1"
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "DeviceCleanupManager")
    // Note: We'll use WLEDAPIService.shared directly in async contexts since it's an actor
    private let maxAttempts = 12
    private let cleanupEnabled = true
    private let maxDeletesPerPass = 2
    
    private init() {
        load()
        if !cleanupEnabled {
            pendingDeletes.removeAll()
            save()
        }
    }
    
    // MARK: - Public Methods
    
    /// Enqueue a device-side deletion to be processed when the device is online
    func enqueue(
        type: PendingDeviceDelete.DeleteType,
        deviceId: String,
        ids: [Int],
        source: PendingDeviceDelete.DeleteSource = .unknown,
        leaseId: UUID? = nil,
        verificationRequired: Bool = false
    ) {
        guard cleanupEnabled else { return }
        let uniqueIds = Array(Set(ids)).sorted()
        guard !uniqueIds.isEmpty else { return }
        if let index = pendingDeletes.firstIndex(where: {
            $0.type == type
                && $0.deviceId == deviceId
                && $0.source == source
                && $0.leaseId == leaseId
                && $0.deadLetteredAt == nil
        }) {
            let mergedIds = Array(Set(pendingDeletes[index].ids + uniqueIds)).sorted()
            pendingDeletes[index].ids = mergedIds
            pendingDeletes[index].lastAttempt = Date()
            pendingDeletes[index].nextAttemptAt = Date()
            pendingDeletes[index].verificationRequired = pendingDeletes[index].verificationRequired || verificationRequired
            pendingDeletes[index].lastError = nil
            save()
            logger.info("Merged \(type.rawValue) deletion for device \(deviceId): \(mergedIds)")
            return
        }
        let delete = PendingDeviceDelete(
            type: type,
            deviceId: deviceId,
            ids: uniqueIds,
            nextAttemptAt: Date(),
            source: source,
            leaseId: leaseId,
            verificationRequired: verificationRequired
        )
        pendingDeletes.append(delete)
        save()
        logger.info("Enqueued \(type.rawValue) deletion for device \(deviceId): \(uniqueIds)")
    }

    /// Attempt a delete immediately if the device is online, otherwise enqueue
    func requestDelete(
        type: PendingDeviceDelete.DeleteType,
        device: WLEDDevice,
        ids: [Int],
        source: PendingDeviceDelete.DeleteSource = .unknown,
        leaseId: UUID? = nil,
        verificationRequired: Bool = false
    ) async {
        guard cleanupEnabled else { return }
        guard !ids.isEmpty else { return }
        let uniqueIds = Array(Set(ids)).sorted()
        guard !uniqueIds.isEmpty else { return }
        let tempOverlapGuard = PendingDeviceDelete(
            type: type,
            deviceId: device.id,
            ids: uniqueIds,
            source: source,
            leaseId: leaseId,
            verificationRequired: verificationRequired
        )
        if await shouldDeferForActiveTempLeaseOverlap(tempOverlapGuard) {
            enqueue(
                type: type,
                deviceId: device.id,
                ids: uniqueIds,
                source: source,
                leaseId: leaseId,
                verificationRequired: verificationRequired
            )
            return
        }
        if device.isOnline {
            let success = await attemptDelete(type: type, device: device, ids: uniqueIds)
            if success {
                // Remove any queued entries that overlap these ids (across all sources).
                removeIds(type: type, deviceId: device.id, ids: uniqueIds)
                return
            }
        }
        enqueue(
            type: type,
            deviceId: device.id,
            ids: uniqueIds,
            source: source,
            leaseId: leaseId,
            verificationRequired: verificationRequired
        )
    }
    
    /// Process pending deletions for a specific device (called when device comes online)
    func processQueue(for deviceId: String) async {
        guard cleanupEnabled else { return }
        guard let device = await getDevice(id: deviceId) else { return }
        guard device.isOnline else { return }
        let now = Date()
        let pendingForDevice = self.pendingDeletes.filter {
            $0.deviceId == deviceId
                && $0.deadLetteredAt == nil
                && (($0.nextAttemptAt ?? .distantPast) <= now)
        }
        guard !pendingForDevice.isEmpty else { return }
        
        logger.info("Processing \(pendingForDevice.count) pending deletions for device \(deviceId)")
        var processedCount = 0
        for delete in pendingForDevice {
            if processedCount >= maxDeletesPerPass {
                logger.info("cleanup.queue_pass_limited device=\(deviceId, privacy: .public) processed=\(processedCount, privacy: .public) pending=\(pendingForDevice.count, privacy: .public)")
                break
            }
            if await shouldDeferForActiveTempLeaseOverlap(delete) {
                if let index = self.pendingDeletes.firstIndex(where: { $0.id == delete.id }) {
                    self.pendingDeletes[index].lastAttempt = Date()
                    self.pendingDeletes[index].lastError = "Deferred: overlaps active temp lease"
                    let attempts = max(1, self.pendingDeletes[index].retries + 1)
                    self.pendingDeletes[index].nextAttemptAt = Date().addingTimeInterval(self.retryDelay(forAttempt: attempts))
                    self.save()
                }
                logger.info("cleanup.queue_deferred_active_lease_overlap device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public)")
                continue
            }
            let success = await attemptDelete(type: delete.type, device: device, ids: delete.ids)
            if success {
                // Remove from queue on success
                self.pendingDeletes.removeAll { $0.id == delete.id }
                self.save()
                logger.info("Successfully processed \(delete.type.rawValue) deletion for device \(deviceId)")
            } else {
                // Update retry count and schedule next attempt
                if let index = self.pendingDeletes.firstIndex(where: { $0.id == delete.id }) {
                    self.pendingDeletes[index].retries += 1
                    self.pendingDeletes[index].lastAttempt = Date()
                    let attempts = self.pendingDeletes[index].retries
                    self.pendingDeletes[index].nextAttemptAt = Date().addingTimeInterval(self.retryDelay(forAttempt: attempts))

                    if attempts >= self.maxAttempts {
                        if delete.type == .timer {
                            // Timer cleanup controls automation re-import safety; keep retrying instead of dead-lettering.
                            self.pendingDeletes[index].retries = self.maxAttempts - 1
                            self.pendingDeletes[index].nextAttemptAt = Date().addingTimeInterval(self.retryDelay(forAttempt: self.maxAttempts))
                            logger.warning("Max attempts exceeded for timer deletion \(delete.id), keeping queued with capped backoff")
                        } else {
                            logger.warning("Max attempts exceeded for \(delete.type.rawValue) deletion \(delete.id), moving to dead-letter")
                            self.pendingDeletes[index].deadLetteredAt = Date()
                            self.pendingDeletes[index].nextAttemptAt = nil
                        }
                    }
                    self.save()
                }
            }
            processedCount += 1
            if processedCount < maxDeletesPerPass {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    func processEligibleQueue() async {
        let deviceIds = Set(pendingDeletes.compactMap { item -> String? in
            guard item.deadLetteredAt == nil else { return nil }
            return item.deviceId
        })
        for deviceId in deviceIds {
            await processQueue(for: deviceId)
        }
    }
    
    /// Attempt to process a single deletion
    private func attemptDelete(type: PendingDeviceDelete.DeleteType, device: WLEDDevice, ids: [Int]) async -> Bool {
        logger.info("Attempting to delete \(type.rawValue) \(ids) from device \(device.id)")
        
        do {
            switch type {
            case .preset:
                // Delete presets
                for presetId in ids {
                    let success = try await WLEDAPIService.shared.deletePreset(id: presetId, device: device)
                    if !success {
                        logger.error("Failed to delete preset \(presetId) from device \(device.id)")
                        return false
                    }
                }
                return true
                
            case .playlist:
                // Delete playlists
                for playlistId in ids {
                    let success = try await WLEDAPIService.shared.deletePlaylist(id: playlistId, device: device)
                    if !success {
                        logger.error("Failed to delete playlist \(playlistId) from device \(device.id)")
                        return false
                    }
                }
                return true
                
            case .timer:
                // Disable timers
                for timerSlot in ids {
                    let success = try await WLEDAPIService.shared.disableTimer(slot: timerSlot, device: device)
                    if !success {
                        logger.error("Failed to disable timer slot \(timerSlot) on device \(device.id)")
                        return false
                    }
                }
                return true
            }
        } catch {
            logger.error("Error processing deletion for device \(device.id): \(error.localizedDescription)")
            if let index = pendingDeletes.firstIndex(where: { $0.deviceId == device.id && $0.type == type && Set($0.ids) == Set(ids) }) {
                pendingDeletes[index].lastError = error.localizedDescription
            }
            return false
        }
    }

    /// Returns active queued delete IDs for a device/type (dead-lettered entries excluded).
    func activeDeleteIds(
        type: PendingDeviceDelete.DeleteType,
        deviceId: String,
        includeDeadLetter: Bool = false
    ) -> Set<Int> {
        Set(
            pendingDeletes
                .filter {
                    $0.type == type
                        && $0.deviceId == deviceId
                        && (includeDeadLetter || $0.deadLetteredAt == nil)
                }
                .flatMap(\.ids)
        )
    }

    func hasActiveDelete(
        type: PendingDeviceDelete.DeleteType,
        deviceId: String,
        id: Int
    ) -> Bool {
        activeDeleteIds(type: type, deviceId: deviceId).contains(id)
    }

    /// Remove specific IDs from active queue entries.
    /// Used when an ID is re-created and should no longer be eligible for delayed deletion.
    func removeIds(
        type: PendingDeviceDelete.DeleteType,
        deviceId: String,
        ids: [Int]
    ) {
        let toRemove = Set(ids)
        guard !toRemove.isEmpty else { return }

        var changed = false
        for index in pendingDeletes.indices.reversed() {
            guard pendingDeletes[index].type == type,
                  pendingDeletes[index].deviceId == deviceId,
                  pendingDeletes[index].deadLetteredAt == nil else {
                continue
            }
            let remaining = pendingDeletes[index].ids.filter { !toRemove.contains($0) }
            if remaining.count != pendingDeletes[index].ids.count {
                changed = true
                if remaining.isEmpty {
                    pendingDeletes.remove(at: index)
                } else {
                    pendingDeletes[index].ids = remaining
                }
            }
        }

        if changed {
            save()
            logger.info("Pruned queued \(type.rawValue) deletes for device \(deviceId): \(Array(toRemove).sorted())")
        }
    }
    
    /// Remove a specific deletion from the queue (e.g., if manually resolved)
    func remove(_ deleteId: UUID) {
        self.pendingDeletes.removeAll { $0.id == deleteId }
        self.save()
    }
    
    /// Clear all pending deletions (e.g., on app reset)
    func clear() {
        self.pendingDeletes.removeAll()
        self.save()
    }
    
    // MARK: - Private Helpers
    
    private func getDevice(id: String) async -> WLEDDevice? {
        // Get device from DeviceControlViewModel
        let viewModel = DeviceControlViewModel.shared
        return viewModel.devices.first { $0.id == id }
    }

    private func shouldDeferForActiveTempLeaseOverlap(_ delete: PendingDeviceDelete) async -> Bool {
        guard delete.type == .preset || delete.type == .playlist else { return false }
        let touchesReservedTempBand = delete.ids.contains {
            (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0)
        }
        let shouldCheck = delete.source == .temporaryTransition || delete.leaseId != nil || touchesReservedTempBand
        guard shouldCheck else { return false }

        let protected = await TemporaryTransitionCleanupService.shared.activeProtectedTempIds(for: delete.deviceId)
        if protected.playlistIds.isEmpty && protected.presetIds.isEmpty {
            return false
        }
        switch delete.type {
        case .preset:
            return !Set(delete.ids).isDisjoint(with: protected.presetIds)
        case .playlist:
            return !Set(delete.ids).isDisjoint(with: protected.playlistIds)
        case .timer:
            return false
        }
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return }
        if let deletes = try? JSONDecoder().decode([PendingDeviceDelete].self, from: data) {
            self.pendingDeletes = deletes
            logger.info("Loaded \(self.pendingDeletes.count) pending deletions from queue")
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(self.pendingDeletes) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [0.5, 1, 2, 5, 10, 20, 60, 300, 900, 1800]
        guard attempt > 0 else { return 0 }
        let index = min(schedule.count - 1, max(0, attempt - 1))
        return schedule[index]
    }
}
