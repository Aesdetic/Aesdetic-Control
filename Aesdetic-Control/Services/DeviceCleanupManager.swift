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
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 5.0 // 5 seconds between retries
    
    private init() {
        load()
    }
    
    // MARK: - Public Methods
    
    /// Enqueue a device-side deletion to be processed when the device is online
    func enqueue(type: PendingDeviceDelete.DeleteType, deviceId: String, ids: [Int]) {
        let delete = PendingDeviceDelete(
            type: type,
            deviceId: deviceId,
            ids: ids
        )
        self.pendingDeletes.append(delete)
        self.save()
        logger.info("Enqueued \(type.rawValue) deletion for device \(deviceId): \(ids)")
    }

    /// Attempt a delete immediately if the device is online, otherwise enqueue
    func requestDelete(type: PendingDeviceDelete.DeleteType, device: WLEDDevice, ids: [Int]) async {
        guard !ids.isEmpty else { return }
        if device.isOnline {
            let success = await attemptDelete(type: type, device: device, ids: ids)
            if success {
                return
            }
        }
        enqueue(type: type, deviceId: device.id, ids: ids)
    }
    
    /// Process pending deletions for a specific device (called when device comes online)
    func processQueue(for deviceId: String) async {
        guard let device = await getDevice(id: deviceId) else { return }
        guard device.isOnline else { return }
        let pendingForDevice = self.pendingDeletes.filter { $0.deviceId == deviceId }
        guard !pendingForDevice.isEmpty else { return }
        
        logger.info("Processing \(pendingForDevice.count) pending deletions for device \(deviceId)")
        
        for delete in pendingForDevice {
            let success = await attemptDelete(type: delete.type, device: device, ids: delete.ids)
            if success {
                // Remove from queue on success
                self.pendingDeletes.removeAll { $0.id == delete.id }
                self.save()
                logger.info("Successfully processed \(delete.type.rawValue) deletion for device \(deviceId)")
            } else {
                // Update retry count and last attempt
                if let index = self.pendingDeletes.firstIndex(where: { $0.id == delete.id }) {
                    self.pendingDeletes[index].retries += 1
                    self.pendingDeletes[index].lastAttempt = Date()
                    
                    // Remove if max retries exceeded
                    if self.pendingDeletes[index].retries >= self.maxRetries {
                        logger.warning("Max retries exceeded for \(delete.type.rawValue) deletion \(delete.id), removing from queue")
                        self.pendingDeletes.remove(at: index)
                    }
                    self.save()
                }
            }
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
            return false
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
}
