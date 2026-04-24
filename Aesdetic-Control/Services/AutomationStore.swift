import Foundation
import Combine
import SwiftUI
import os.log
import CoreLocation

@MainActor
struct AutomationDeletionProgress: Equatable {
    let totalSteps: Int
    let remainingSteps: Int
    let phaseDescription: String

    var completedSteps: Int { max(0, totalSteps - remainingSteps) }

    var fractionCompleted: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completedSteps) / Double(totalSteps)))
    }
}

@MainActor
class AutomationStore: ObservableObject {
    static let shared = AutomationStore()

    enum OnDeviceTriggerKind {
        case specificTime
        case sunrise
        case sunset
    }
    
    @Published var automations: [Automation] = []
    @Published private(set) var upcomingAutomationInfo: (automation: Automation, date: Date)?
    @Published private(set) var deletingAutomationIds: Set<UUID> = []
    @Published private(set) var deletionProgressByAutomationId: [UUID: AutomationDeletionProgress] = [:]
    var hasAnyDeletionInProgress: Bool {
        !deletingAutomationIds.isEmpty
            || DeviceCleanupManager.shared.hasPendingDeletes(source: .automation)
            || DeviceCleanupManager.shared.hasPendingPresetStoreDeletes()
    }
    
    private let fileURL: URL
    private var schedulerTimer: Timer?
    private var solarRefreshTimer: Timer?
    private var onDeviceSyncRetryTimer: Timer?
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "AutomationStore")
    private lazy var scenesStore = ScenesStore.shared
    private lazy var presetsStore = PresetsStore.shared
    private lazy var viewModel = DeviceControlViewModel.shared
    private lazy var apiService = WLEDAPIService.shared
    private let locationProvider = LocationProvider()
    private var solarCache: [SolarCacheKey: Date] = [:]
    private let maxWLEDTransitionSeconds: Double = 6553.5
    private let cleanupThrottleKey = "aesdetic_automation_cleanup_last"
    private let cleanupThrottleInterval: TimeInterval = 6 * 60 * 60
    private let managedAssetDeferredCleanupDelaySeconds: TimeInterval = 120
    private let orphanSweepDeferredCleanupDelaySeconds: TimeInterval = 180
    private let onDeviceSyncRetryInterval: TimeInterval = 30
    private let syncedValidationInterval: TimeInterval = 120
    private let deleteFinalizePollIntervalSeconds: TimeInterval = 2.0
    private let deleteFinalizeTimeoutSeconds: TimeInterval = 180.0
    private let postDevicePreparationDeleteLockoutSeconds: TimeInterval = 60.0
    private let postPresetStoreMutationDeleteSettleSeconds: TimeInterval = 60.0
    private let prePresetStoreDeleteQuiesceSeconds: TimeInterval = 0.7
    private let postTimerDeletePresetStoreSettleSeconds: TimeInterval = 1.5
    private var onDeviceSyncInFlightAutomationIds: Set<UUID> = []
    private var onDeviceSyncReplayAutomationIds: Set<UUID> = []
    private var onDeviceSyncInFlightDeviceIds: Set<String> = []
    private var lastSyncedValidationAt: Date = .distantPast
    private var lastKnownGoodTimerSignatureByAutomationDevice: [String: String] = [:]
    private let importedAutomationTemplatePrefix = "wled.timer."
    private var cancellables: Set<AnyCancellable> = []

    private enum SolarReferenceSource {
        case wledConfig
        case deviceLocation
        case manual
    }

    private struct SolarReference {
        let coordinate: CLLocationCoordinate2D
        let timeZone: TimeZone
        let source: SolarReferenceSource
    }

    private enum TimerSlotResolution {
        case slot(Int)
        case unavailable
        case unresolved(String)
    }

    private enum TimerSlotSelectionReason: String {
        case existing
        case preferred
        case free
        case reclaimable
    }

    private struct TimerSlotSelection {
        let slot: Int
        let reason: TimerSlotSelectionReason
    }
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = documentsPath.appendingPathComponent("automations.json")

        let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isRunningInPreview {
            load()
            return
        }

        load()
        scheduleNext()
        scheduleSolarRefreshIfNeeded()
        scheduleOnDeviceSyncRetryIfNeeded()
        DeviceCleanupManager.shared.$pendingDeletes
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        Task { [weak self] in
            await DeviceCleanupManager.shared.processEligibleQueue()
            await self?.resyncOnDeviceSchedules()
            await self?.importOnDeviceAutomationsFromDevices()
        }
    }
    
    deinit {
        schedulerTimer?.invalidate()
        solarRefreshTimer?.invalidate()
        onDeviceSyncRetryTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func add(_ automation: Automation) {
        guard !hasAnyDeletionInProgress else {
            let queuedDeviceIds = Array(DeviceCleanupManager.shared.pendingDeleteDeviceIds(source: .automation)).sorted()
            logger.warning(
                "automation.add.blocked_deletion_in_progress automation=\(automation.name, privacy: .public) inflightDeletes=\(self.deletingAutomationIds.count, privacy: .public) queuedDevices=\(queuedDeviceIds, privacy: .public)"
            )
            return
        }
        var record = automation
        record.metadata.normalizeWLEDScalarFallbacks(for: record.targets.deviceIds)
        var shouldSyncOnDevice = record.metadata.runOnDevice
        if record.metadata.runOnDevice {
            let localCapacity = validateLocalTimerCapacity(
                triggerKind: triggerKind(for: record.trigger),
                targetDeviceIds: record.targets.deviceIds,
                excludingAutomationId: record.id
            )
            if !localCapacity.isValid {
                record = markOnDeviceNotReady(
                    record,
                    reason: localCapacity.message ?? "No available timer slots on device"
                )
                shouldSyncOnDevice = false
                logger.error("Blocked on-device automation sync due to timer capacity: \(record.name, privacy: .public)")
            }
        }
        record.updatedAt = Date()
        automations.append(record)
        save()
        scheduleNext()
        scheduleSolarRefreshIfNeeded()
        scheduleOnDeviceSyncRetryIfNeeded()
        logger.info("Added automation: \(record.name)")
        if shouldSyncOnDevice {
            Task { [weak self] in
                await self?.syncOnDeviceScheduleIfNeeded(for: record)
            }
        }
    }
    
    func update(_ automation: Automation, syncOnDevice: Bool = true) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        let previous = automations[index]
        var record = automation
        if previous.action.macroAssetKind != record.action.macroAssetKind {
            let impactedIds = Array(Set(previous.targets.deviceIds).union(record.targets.deviceIds))
            record.metadata.clearWLEDMacroMetadata(for: impactedIds, preserveTimerSlots: true)
        }
        let removedTargetIds = Set(previous.targets.deviceIds).subtracting(record.targets.deviceIds)
        if !removedTargetIds.isEmpty {
            record.metadata.clearWLEDMacroMetadata(for: Array(removedTargetIds), preserveTimerSlots: false)
            removeTimerSignatures(for: record.id, deviceIds: removedTargetIds)
        }
        record.metadata.normalizeWLEDScalarFallbacks(for: record.targets.deviceIds)
        var shouldSyncOnDevice = syncOnDevice && record.metadata.runOnDevice
        if record.metadata.runOnDevice {
            let localCapacity = validateLocalTimerCapacity(
                triggerKind: triggerKind(for: record.trigger),
                targetDeviceIds: record.targets.deviceIds,
                excludingAutomationId: record.id
            )
            if !localCapacity.isValid {
                record = markOnDeviceNotReady(
                    record,
                    reason: localCapacity.message ?? "No available timer slots on device"
                )
                shouldSyncOnDevice = false
                logger.error("Blocked on-device automation sync due to timer capacity: \(record.name, privacy: .public)")
            }
        }
        record.updatedAt = Date()
        // Create a new array to trigger @Published change notification
        var updated = automations
        updated[index] = record
        automations = updated
        save()
        scheduleNext()
        scheduleSolarRefreshIfNeeded()
        scheduleOnDeviceSyncRetryIfNeeded()
        logger.info("Updated automation: \(record.name)")
        if shouldSyncOnDevice {
            Task { [weak self] in
                await self?.syncOnDeviceScheduleIfNeeded(for: record)
            }
        }
        if !removedTargetIds.isEmpty {
            Task { [weak self] in
                await self?.cleanupRemovedOnDeviceTargets(previous: previous, removedDeviceIds: removedTargetIds)
            }
        }
    }
    
    func delete(id: UUID) {
        guard let automation = automations.first(where: { $0.id == id }) else { return }
        guard !deletingAutomationIds.contains(id) else { return }
        guard deleteDisabledUntil(for: automation) == nil else {
            logger.info(
                "automation.delete.blocked_device_settle automation=\(automation.id.uuidString, privacy: .public) name=\(automation.name, privacy: .public)"
            )
            return
        }
        deletingAutomationIds.insert(id)
        onDeviceSyncReplayAutomationIds.remove(id)
        updateDeletionProgress(
            automationId: id,
            totalSteps: 1,
            remainingSteps: 1,
            phase: "Preparing delete pipeline..."
        )
        logger.info("automation.delete.requested automation=\(automation.id.uuidString, privacy: .public) name=\(automation.name, privacy: .public)")
        #if DEBUG
        print("automation.delete.requested id=\(automation.id.uuidString) name=\(automation.name)")
        #endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.deleteAutomationAfterDeviceCleanup(automation)
        }
    }

    func deleteDisabledUntil(for automation: Automation) -> Date? {
        let devicePreparationDates = recentDevicePreparationDates(for: automation)
        guard let latestPreparation = devicePreparationDates.max() else {
            if automation.metadata.runOnDevice {
                let createdLockUntil = automation.createdAt.addingTimeInterval(postDevicePreparationDeleteLockoutSeconds)
                return createdLockUntil > Date() ? createdLockUntil : nil
            }
            return nil
        }
        let lockUntil = latestPreparation.addingTimeInterval(postDevicePreparationDeleteLockoutSeconds)
        return lockUntil > Date() ? lockUntil : nil
    }

    private func recentDevicePreparationDates(for automation: Automation) -> [Date] {
        var dates: [Date] = []
        if let syncDates = automation.metadata.wledLastSyncAtByDevice {
            dates.append(contentsOf: syncDates.values)
        }
        if let checkpoints = automation.metadata.wledManagedAssetCheckpointByDevice {
            dates.append(contentsOf: checkpoints.values.map(\.capturedAt))
        }
        return dates
    }

    func isDeletionInProgress(for id: UUID) -> Bool {
        deletingAutomationIds.contains(id)
    }

    func isDeletionInProgress(for deviceId: String) -> Bool {
        if !deletingAutomationIds.isEmpty { return true }
        if DeviceCleanupManager.shared.hasPendingDeletes(
            source: .automation,
            deviceId: deviceId
        ) {
            return true
        }
        if DeviceCleanupManager.shared.hasPendingPresetStoreDeletes(deviceId: deviceId) {
            return true
        }
        return DeviceCleanupManager.shared.isDeleteLeaseActive(deviceId: deviceId)
    }

    func deletionProgress(for id: UUID) -> AutomationDeletionProgress? {
        deletionProgressByAutomationId[id]
    }

    private func pendingCleanupDeviceIds(for automation: Automation) -> [String] {
        automation.targets.deviceIds.filter { deviceId in
            DeviceCleanupManager.shared.hasPendingDeletes(source: .automation, deviceId: deviceId)
                || DeviceCleanupManager.shared.hasPendingPresetStoreDeletes(deviceId: deviceId)
                || DeviceCleanupManager.shared.isDeleteLeaseActive(deviceId: deviceId)
        }.sorted()
    }

    private func pendingTimerCleanupDeviceIds(for automation: Automation) -> [String] {
        automation.targets.deviceIds.filter { deviceId in
            guard let device = viewModel.devices.first(where: { $0.id == deviceId }),
                  device.isOnline else {
                return false
            }
            guard let timerSlot = automation.metadata.wledTimerSlotsByDevice?[deviceId] ?? automation.metadata.wledTimerSlot else {
                return false
            }
            guard !timerSlotClaimedByAnotherAutomation(
                timerSlot,
                deviceId: deviceId,
                excluding: automation.id
            ) else {
                return false
            }
            return DeviceCleanupManager.shared.hasActiveDelete(
                type: .timer,
                deviceId: deviceId,
                id: timerSlot
            )
        }.sorted()
    }

    private func deleteAutomationAfterDeviceCleanup(_ automation: Automation) async {
        let deadline = Date().addingTimeInterval(deleteFinalizeTimeoutSeconds)
        let cleanupComplete = await cleanupDeviceEntries(for: automation)
        guard cleanupComplete else {
            let canFinalize = await canFinalizeAfterCleanupFailure(for: automation)
            if canFinalize {
                logger.warning(
                    "automation.delete.finalize_with_postcheck_warning automation=\(automation.id.uuidString, privacy: .public)"
                )
                finalizeDeletedAutomationLocally(automation)
                deletingAutomationIds.remove(automation.id)
                deletionProgressByAutomationId.removeValue(forKey: automation.id)
                return
            }
            logger.error(
                "automation.delete.finalize_aborted_cleanup_failed automation=\(automation.id.uuidString, privacy: .public)"
            )
            deletingAutomationIds.remove(automation.id)
            deletionProgressByAutomationId.removeValue(forKey: automation.id)
            return
        }
        var attempt = 0
        var lastPendingTimerDeviceIds: [String] = []
        var pendingTimerDeviceIds = pendingTimerCleanupDeviceIds(for: automation)

        while !pendingTimerDeviceIds.isEmpty, Date() < deadline {
            attempt += 1

            let currentProgress = deletionProgressByAutomationId[automation.id]
            let phase: String
            if pendingTimerDeviceIds.count == 1 {
                phase = "Waiting for timer cleanup..."
            } else {
                phase = "Waiting for \(pendingTimerDeviceIds.count) devices to finish timer cleanup..."
            }
            updateDeletionProgress(
                automationId: automation.id,
                totalSteps: max(1, currentProgress?.totalSteps ?? 1),
                remainingSteps: max(1, currentProgress?.remainingSteps ?? 1),
                phase: phase
            )
            if pendingTimerDeviceIds != lastPendingTimerDeviceIds || attempt == 1 || attempt % 5 == 0 {
                logger.warning(
                    "automation.delete.waiting_for_timer_cleanup automation=\(automation.id.uuidString, privacy: .public) attempt=\(attempt, privacy: .public) pendingDevices=\(pendingTimerDeviceIds, privacy: .public)"
                )
                #if DEBUG
                print("automation.delete.waiting_for_timer_cleanup automation=\(automation.id.uuidString) attempt=\(attempt) pendingDevices=\(pendingTimerDeviceIds)")
                #endif
                lastPendingTimerDeviceIds = pendingTimerDeviceIds
            }

            for deviceId in pendingTimerDeviceIds {
                await DeviceCleanupManager.shared.processQueue(for: deviceId)
            }

            let sleepNs = UInt64(deleteFinalizePollIntervalSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNs)
            pendingTimerDeviceIds = pendingTimerCleanupDeviceIds(for: automation)
        }

        guard pendingTimerDeviceIds.isEmpty else {
            logger.error(
                "automation.delete.finalize_aborted_timer_cleanup_incomplete automation=\(automation.id.uuidString, privacy: .public) timeoutSeconds=\(self.deleteFinalizeTimeoutSeconds, privacy: .public) pendingDevices=\(pendingTimerDeviceIds, privacy: .public)"
            )
            #if DEBUG
            print("automation.delete.finalize_aborted_timer_cleanup_incomplete automation=\(automation.id.uuidString) timeoutSeconds=\(self.deleteFinalizeTimeoutSeconds) pendingDevices=\(pendingTimerDeviceIds)")
            #endif
            deletingAutomationIds.remove(automation.id)
            deletionProgressByAutomationId.removeValue(forKey: automation.id)
            return
        }

        finalizeDeletedAutomationLocally(automation)
        deletingAutomationIds.remove(automation.id)
        deletionProgressByAutomationId.removeValue(forKey: automation.id)
    }

    private func finalizeDeletedAutomationLocally(_ automation: Automation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        let removed = automations.remove(at: index)
        removeTimerSignatures(for: removed.id)
        save()
        scheduleNext()
        scheduleSolarRefreshIfNeeded()
        scheduleOnDeviceSyncRetryIfNeeded()
        let pendingBackgroundCleanupDeviceIds = pendingCleanupDeviceIds(for: removed)
        if !pendingBackgroundCleanupDeviceIds.isEmpty {
            logger.info(
                "automation.delete.backgrounded automation=\(removed.id.uuidString, privacy: .public) pendingDevices=\(pendingBackgroundCleanupDeviceIds, privacy: .public)"
            )
            Task { @MainActor in
                for deviceId in pendingBackgroundCleanupDeviceIds {
                    await DeviceCleanupManager.shared.processQueue(for: deviceId)
                }
            }
        }
        logger.info("Deleted automation: \(removed.name)")
    }

    private func canFinalizeAfterCleanupFailure(for automation: Automation) async -> Bool {
        // Never finalize if queue/lease still indicates outstanding cleanup work.
        guard pendingCleanupDeviceIds(for: automation).isEmpty else {
            return false
        }

        for deviceId in automation.targets.deviceIds {
            guard let slot = automation.metadata.wledTimerSlotsByDevice?[deviceId] ?? automation.metadata.wledTimerSlot else {
                continue
            }
            guard !timerSlotClaimedByAnotherAutomation(slot, deviceId: deviceId, excluding: automation.id) else {
                continue
            }
            guard let device = viewModel.devices.first(where: { $0.id == deviceId && $0.isOnline }) else {
                return false
            }
            do {
                let timers = try await apiService.fetchTimers(for: device)
                guard let timer = timers.first(where: { $0.id == slot }) else {
                    continue
                }
                if isTimerActionableForDeletionFinalization(timer, slot: slot) {
                    return false
                }
            } catch {
                return false
            }
        }
        return true
    }

    private func isTimerActionableForDeletionFinalization(_ timer: WLEDTimer, slot: Int) -> Bool {
        let hasDateRange = timer.startMonth != nil || timer.startDay != nil || timer.endMonth != nil || timer.endDay != nil
        let hasClockTime = timer.hour != 0 || timer.minute != 0
        let hasNonDefaultDays = timer.days != 0x7F
        let hasMacro = timer.macroId != 0
        let hasSolarMarker = timer.hour == 255 || timer.hour == 254

        // Firmware can leave a non-actionable solar marker row in slots 8/9 after clear.
        if slot >= 8 && !timer.enabled && !hasMacro && hasSolarMarker && !hasDateRange && !hasNonDefaultDays {
            return false
        }

        return timer.enabled || hasMacro || hasClockTime || hasNonDefaultDays || hasDateRange || hasSolarMarker
    }
    
    func applyAutomation(_ automation: Automation) {
        logger.info("Applying automation: \(automation.name)")
        
        let devices = viewModel.devices.filter { automation.targets.deviceIds.contains($0.id) }
        guard !devices.isEmpty else {
            logger.error("No devices found for automation \(automation.name)")
            return
        }
        
        let allowPartial = automation.targets.allowPartialFailure
        let nameLookup = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0.name) })
        
        Task { @MainActor in
            var failedIds: [String] = []
            let retryAttempts = automation.targets.allowPartialFailure ? 0 : 1
            await withTaskGroup(of: (String, Bool).self) { group in
                for device in devices {
                    group.addTask { [weak self] in
                        guard let self else { return (device.id, false) }
                        let success = await self.runActionWithRetry(
                            automation.action,
                            automation: automation,
                            on: device,
                            retryAttempts: retryAttempts
                        )
                        return (device.id, success)
                    }
                }
                
                for await result in group {
                    if !result.1 {
                        failedIds.append(result.0)
                        if !allowPartial {
                            group.cancelAll()
                        }
                    }
                }
            }
            
            if failedIds.count == devices.count {
                let names = failedIds.compactMap { nameLookup[$0] ?? $0 }
                logger.error("Automation \(automation.name) failed for devices: \(names.joined(separator: ", "))")
                return
            }
            
            var updated = automation
            updated.lastTriggered = Date()
            update(updated, syncOnDevice: false)
            
            if !failedIds.isEmpty {
                let names = failedIds.compactMap { nameLookup[$0] ?? $0 }
                logger.error("Automation \(automation.name) partially failed for devices: \(names.joined(separator: ", "))")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func scheduleNext() {
        schedulerTimer?.invalidate()
        upcomingAutomationInfo = nil
        guard !automations.isEmpty else { return }
        Task { @MainActor in
            guard let (nextAutomation, nextDate) = await resolveNextAutomation(referenceDate: Date()) else { return }
            upcomingAutomationInfo = (nextAutomation, nextDate)
            scheduleTimer(for: nextAutomation, fireDate: nextDate)
        }
    }
    
    private func scheduleTimer(for automation: Automation, fireDate: Date) {
        schedulerTimer?.invalidate()
        let interval = max(1.0, fireDate.timeIntervalSince(Date()))
        logger.info("Scheduling next automation '\(automation.name)' in \(interval) seconds")
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerAutomation(automation)
            }
        }
    }
    
    private func triggerAutomation(_ automation: Automation) {
        logger.info("Triggering automation: \(automation.name)")
        if automation.metadata.runOnDevice {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.syncOnDeviceScheduleIfNeeded(for: automation)
                let latest = self.automations.first(where: { $0.id == automation.id }) ?? automation
                if self.shouldDeferToDeviceTimer(latest) {
                    self.logger.info("On-device automation armed on WLED: \(latest.name, privacy: .public)")
                } else {
                    self.logger.error("On-device automation not synced; local fallback disabled: \(latest.name, privacy: .public)")
                }
                self.scheduleNext()
            }
            return
        }
        applyAutomation(automation)
        scheduleNext()
    }

    private func resyncOnDeviceSchedules() async {
        let candidates = automations.filter { $0.metadata.runOnDevice }
        guard !candidates.isEmpty else { return }
        for automation in candidates {
            await syncOnDeviceScheduleIfNeeded(for: automation)
        }
        // Don't scan/delete presets/playlists on every app launch.
    }

    func resyncOnDeviceSchedules(for device: WLEDDevice) async {
        let candidates = automations.filter {
            $0.metadata.runOnDevice && $0.targets.deviceIds.contains(device.id)
        }
        guard !candidates.isEmpty else { return }
        for automation in candidates {
            await syncOnDeviceScheduleIfNeeded(for: automation, deviceFilter: [device.id])
        }
        // Don't scan/delete presets/playlists on every reconnect.
    }

    func retryOnDeviceSync(for automationId: UUID) {
        guard let automation = automations.first(where: { $0.id == automationId }) else { return }
        guard automation.metadata.runOnDevice else { return }
        Task { [weak self] in
            await self?.syncOnDeviceScheduleIfNeeded(for: automation)
        }
    }

    func validateLocalTimerCapacity(
        triggerKind: OnDeviceTriggerKind,
        targetDeviceIds: [String],
        excludingAutomationId: UUID? = nil
    ) -> OnDeviceScheduleValidation {
        let filteredDeviceIds = Array(Set(targetDeviceIds))
        guard !filteredDeviceIds.isEmpty else {
            return OnDeviceScheduleValidation(isValid: true, message: nil, isWarning: false)
        }

        switch triggerKind {
        case .specificTime:
            let blocked = filteredDeviceIds.filter {
                localSlotUsage(for: $0, excludingAutomationId: excludingAutomationId).specificTimeCount >= 8
            }
            if !blocked.isEmpty {
                let names = deviceNames(for: blocked)
                return OnDeviceScheduleValidation(
                    isValid: false,
                    message: "WLED limit reached on \(names): Specific-time automations use slots 0...7 (max 8 per device).",
                    isWarning: false
                )
            }
            if filteredDeviceIds.count == 1, let deviceId = filteredDeviceIds.first {
                let used = localSlotUsage(for: deviceId, excludingAutomationId: excludingAutomationId).specificTimeCount
                return OnDeviceScheduleValidation(
                    isValid: true,
                    message: "Timer capacity: \(used)/8 specific-time slots used.",
                    isWarning: false
                )
            }
            return OnDeviceScheduleValidation(
                isValid: true,
                message: "Specific-time automations use slots 0...7 (max 8 per device).",
                isWarning: false
            )

        case .sunrise:
            let blocked = filteredDeviceIds.filter {
                localSlotUsage(for: $0, excludingAutomationId: excludingAutomationId).sunriseUsed
            }
            if !blocked.isEmpty {
                let names = deviceNames(for: blocked)
                return OnDeviceScheduleValidation(
                    isValid: false,
                    message: "Sunrise slot already used on \(names). WLED sunrise uses timer slot 8 (one sunrise automation per device).",
                    isWarning: false
                )
            }
            return OnDeviceScheduleValidation(
                isValid: true,
                message: "Sunrise uses timer slot 8 (one sunrise automation per device).",
                isWarning: false
            )

        case .sunset:
            let blocked = filteredDeviceIds.filter {
                localSlotUsage(for: $0, excludingAutomationId: excludingAutomationId).sunsetUsed
            }
            if !blocked.isEmpty {
                let names = deviceNames(for: blocked)
                return OnDeviceScheduleValidation(
                    isValid: false,
                    message: "Sunset slot already used on \(names). WLED sunset uses timer slot 9 (one sunset automation per device).",
                    isWarning: false
                )
            }
            return OnDeviceScheduleValidation(
                isValid: true,
                message: "Sunset uses timer slot 9 (one sunset automation per device).",
                isWarning: false
            )
        }
    }

    private struct LocalSlotUsage {
        let specificTimeCount: Int
        let sunriseUsed: Bool
        let sunsetUsed: Bool
    }

    private func triggerKind(for trigger: AutomationTrigger) -> OnDeviceTriggerKind {
        switch trigger {
        case .specificTime:
            return .specificTime
        case .sunrise:
            return .sunrise
        case .sunset:
            return .sunset
        }
    }

    private func localSlotUsage(for deviceId: String, excludingAutomationId: UUID?) -> LocalSlotUsage {
        var specificTimeCount = 0
        var sunriseUsed = false
        var sunsetUsed = false

        for automation in automations {
            if let excludingAutomationId, automation.id == excludingAutomationId {
                continue
            }
            guard automation.metadata.runOnDevice else { continue }
            guard automation.targets.deviceIds.contains(deviceId) else { continue }

            switch automation.trigger {
            case .specificTime:
                specificTimeCount += 1
            case .sunrise:
                sunriseUsed = true
            case .sunset:
                sunsetUsed = true
            }
        }

        return LocalSlotUsage(
            specificTimeCount: specificTimeCount,
            sunriseUsed: sunriseUsed,
            sunsetUsed: sunsetUsed
        )
    }

    private func deviceNames(for deviceIds: [String]) -> String {
        let uniqueIds = Array(Set(deviceIds))
        let names = uniqueIds.compactMap { id in
            viewModel.devices.first(where: { $0.id == id })?.name
        }.sorted()
        if names.isEmpty {
            return uniqueIds.joined(separator: ", ")
        }
        return names.joined(separator: ", ")
    }

    private func markOnDeviceNotReady(_ automation: Automation, reason: String) -> Automation {
        var updated = automation
        var syncStates = updated.metadata.wledSyncStateByDevice ?? [:]
        var syncErrors = updated.metadata.wledLastSyncErrorByDevice ?? [:]
        var syncAt = updated.metadata.wledLastSyncAtByDevice ?? [:]

        for deviceId in updated.targets.deviceIds {
            syncStates[deviceId] = .notSynced
            syncErrors[deviceId] = reason
            syncAt.removeValue(forKey: deviceId)
        }

        updated.metadata.wledSyncStateByDevice = syncStates.isEmpty ? nil : syncStates
        updated.metadata.wledLastSyncErrorByDevice = syncErrors.isEmpty ? nil : syncErrors
        updated.metadata.wledLastSyncAtByDevice = syncAt.isEmpty ? nil : syncAt
        return updated
    }

    func importOnDeviceAutomationsFromDevices() async {
        let devices = viewModel.devices.filter { !$0.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !devices.isEmpty else { return }
        for device in devices {
            await importOnDeviceAutomations(for: device)
        }
    }

    func importOnDeviceAutomations(for device: WLEDDevice) async {
        let timers: [WLEDTimer]
        do {
            timers = try await apiService.fetchTimers(for: device)
        } catch {
            logger.error("Failed to import WLED timers for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // WLED timer slots without macro targets are not actionable automations.
        let pendingTimerDeletes = DeviceCleanupManager.shared.activeDeleteIds(
            type: .timer,
            deviceId: device.id,
            includeDeadLetter: false
        )
        let pendingAutomationTimerDeletes = Set(
            DeviceCleanupManager.shared.pendingDeletes
                .filter {
                    $0.type == .timer
                        && $0.deviceId == device.id
                        && $0.deadLetteredAt == nil
                        && $0.source == .automation
                }
                .flatMap(\.ids)
        )
        let deadLetterTimerDeletes = DeviceCleanupManager.shared
            .activeDeleteIds(type: .timer, deviceId: device.id, includeDeadLetter: true)
            .subtracting(pendingTimerDeletes)
        let configuredTimers = timers.filter {
            $0.macroId > 0
                && (0...9).contains($0.id)
                && !pendingAutomationTimerDeletes.contains($0.id)
        }
        if !pendingAutomationTimerDeletes.isEmpty {
            logger.info(
                "Suppressing automation-owned pending timer-delete slots during import on \(device.name, privacy: .public): \(Array(pendingAutomationTimerDeletes).sorted())"
            )
        }
        if !pendingTimerDeletes.subtracting(pendingAutomationTimerDeletes).isEmpty {
            logger.info(
                "Pending non-automation timer-delete slots present during import on \(device.name, privacy: .public): \(Array(pendingTimerDeletes.subtracting(pendingAutomationTimerDeletes)).sorted())"
            )
        }
        if !deadLetterTimerDeletes.isEmpty {
            logger.info(
                "Ignoring dead-letter timer-delete slots during import on \(device.name, privacy: .public): \(Array(deadLetterTimerDeletes).sorted())"
            )
        }
        print(
            "automation.import.reported device=\(device.id) configuredTimers=\(configuredTimers.count) pendingTimerDeletes=\(Array(pendingTimerDeletes).sorted()) suppressedPendingAutomationDeletes=\(Array(pendingAutomationTimerDeletes).sorted())"
        )
        let configuredSlots = Set(configuredTimers.map(\.id))

        let playlists: [WLEDPlaylist]
        let presets: [WLEDPreset]
        var playlistCatalogError: Error?
        var presetCatalogError: Error?
        do {
            playlists = try await apiService.fetchPlaylists(for: device)
        } catch {
            playlists = []
            playlistCatalogError = error
            logger.warning("Playlist catalog unavailable during automation import for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        do {
            presets = try await apiService.fetchPresets(for: device)
        } catch {
            presets = []
            presetCatalogError = error
            logger.warning("Preset catalog unavailable during automation import for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        if playlistCatalogError != nil && presetCatalogError != nil {
            logger.warning(
                "Continuing automation import for \(device.name, privacy: .public) with placeholder actions: both WLED catalogs unavailable"
            )
        }
        let playlistById = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        let presetById = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
        let timeZoneId = (await wledSolarReference(for: device)?.timeZone?.identifier) ?? TimeZone.current.identifier
        let now = Date()

        var updatedAutomations = automations
        var changed = false
        var matchedAuthoredAutomationIds: Set<UUID> = []
        var duplicateAuthoredSlotsForCleanup: Set<Int> = []

        for timer in configuredTimers {
            let templateId = importedTemplateId(deviceId: device.id, slot: timer.id)
            let weekdays = WeekdayMask.sunFirst(fromWLEDDow: timer.days)
            let trigger: AutomationTrigger
            if timer.hour == 255 || timer.hour == 254 {
                let offset = SolarTrigger.clampOnDeviceOffset(timer.minute)
                let solar = SolarTrigger(offset: .minutes(offset), location: .followDevice, weekdays: weekdays)
                if timer.hour == 254 {
                    trigger = .sunset(solar)
                } else {
                    // Backward compatibility: older app builds encoded sunset as hour=255 in slot 9.
                    trigger = timer.id == 9 ? .sunset(solar) : .sunrise(solar)
                }
            } else {
                let clampedHour = max(0, min(23, timer.hour))
                let clampedMinute = max(0, min(59, timer.minute))
                let time = String(format: "%02d:%02d", clampedHour, clampedMinute)
                trigger = .specificTime(
                    TimeTrigger(time: time, weekdays: weekdays, timezoneIdentifier: timeZoneId)
                )
            }

            var existingIndex = updatedAutomations.firstIndex { automation in
                if automation.metadata.templateId == templateId {
                    return true
                }
                guard automation.metadata.runOnDevice,
                      automation.targets.deviceIds.contains(device.id) else {
                    return false
                }
                let slot = automation.metadata.wledTimerSlotsByDevice?[device.id] ?? automation.metadata.wledTimerSlot
                return slot == timer.id
            }
            if existingIndex == nil,
               let authoredMatchIndex = await authoredAutomationMatchIndexForImportedTimer(
                timer,
                device: device,
                in: updatedAutomations,
                referenceDate: now
               ) {
                let authoredMatchId = updatedAutomations[authoredMatchIndex].id
                if matchedAuthoredAutomationIds.contains(authoredMatchId) {
                    duplicateAuthoredSlotsForCleanup.insert(timer.id)
                    logger.warning(
                        "automation.import.duplicate_authored_slot device=\(device.id, privacy: .public) slot=\(timer.id, privacy: .public) macro=\(timer.macroId, privacy: .public)"
                    )
                    continue
                }
                existingIndex = authoredMatchIndex
            }
            let existingAutomation = existingIndex.map { updatedAutomations[$0] }

            let action: AutomationAction
            let actionLabel: String
            let importedSyncState: AutomationMetadata.WLEDSyncState
            let importedSyncError: String?
            let importedSyncAt: Date?
            if let playlist = playlistById[timer.macroId] {
                action = .playlist(PlaylistActionPayload(playlistId: playlist.id, playlistName: playlist.name))
                actionLabel = playlist.name
                importedSyncState = .synced
                importedSyncError = nil
                importedSyncAt = now
            } else if let preset = presetById[timer.macroId] {
                action = .preset(PresetActionPayload(presetId: preset.id, paletteName: preset.name, durationSeconds: nil))
                actionLabel = preset.name
                importedSyncState = .synced
                importedSyncError = nil
                importedSyncAt = now
            } else if playlistCatalogError != nil || presetCatalogError != nil {
                if let existingAutomation {
                    action = existingAutomation.action
                    actionLabel = existingAutomation.summary
                    let preservedState = existingAutomation.metadata.syncState(for: device.id)
                    importedSyncState = preservedState
                    importedSyncAt = existingAutomation.metadata.lastSyncAt(for: device.id)
                    if preservedState == .synced {
                        importedSyncError = nil
                    } else {
                        importedSyncError = existingAutomation.metadata.lastSyncError(for: device.id)
                            ?? "WLED catalog unavailable; readiness check deferred"
                    }
                } else {
                    // Catalog fetch failed, but timer macro is still actionable.
                    // Import a placeholder row so users can see/control all device automations.
                    action = .preset(PresetActionPayload(presetId: timer.macroId, paletteName: nil, durationSeconds: nil))
                    actionLabel = "Macro \(timer.macroId)"
                    importedSyncState = .syncing
                    importedSyncError = "WLED preset/playlist catalog unavailable; metadata will refresh when reachable"
                    importedSyncAt = nil
                    logger.warning(
                        "Importing timer with placeholder action for \(device.name, privacy: .public) slot=\(timer.id) macro=\(timer.macroId): catalogs unavailable"
                    )
                }
            } else {
                action = .preset(PresetActionPayload(presetId: timer.macroId, paletteName: nil, durationSeconds: nil))
                actionLabel = "Preset \(timer.macroId)"
                importedSyncState = .notSynced
                importedSyncError = "Macro target missing on WLED (id \(timer.macroId))"
                importedSyncAt = nil
            }
            var signatureAutomationId: UUID?
            let importedWindow = normalizedTimerDateWindow(
                startMonth: timer.startMonth,
                startDay: timer.startDay,
                endMonth: timer.endMonth,
                endDay: timer.endDay
            )
            let importedStartMonth = importedWindow.startMonth
            let importedStartDay = importedWindow.startDay
            let importedEndMonth = importedWindow.endMonth
            let importedEndDay = importedWindow.endDay

            if let index = existingIndex {
                var existing = updatedAutomations[index]
                signatureAutomationId = existing.id
                if !isImportedTemplateId(existing.metadata.templateId) {
                    matchedAuthoredAutomationIds.insert(existing.id)
                }
                let isImportedTemplateRow =
                    isImportedTemplateId(existing.metadata.templateId)
                let preserveAuthoredAction = !isImportedTemplateRow
                let existingPlaylistId = existing.metadata.wledPlaylistIdsByDevice?[device.id] ?? existing.metadata.wledPlaylistId
                let existingPresetId = existing.metadata.wledPresetIdsByDevice?[device.id]
                let previousScalarPlaylistId = updatedAutomations[index].metadata.wledPlaylistId
                let previousScalarTimerSlot = updatedAutomations[index].metadata.wledTimerSlot
                let nextPlaylistId: Int? = {
                    if preserveAuthoredAction {
                        return existingPlaylistId
                    }
                    if case .playlist(let payload) = action { return payload.playlistId }
                    return nil
                }()
                let nextPresetId: Int? = {
                    if preserveAuthoredAction {
                        return existingPresetId
                    }
                    if case .preset(let payload) = action { return payload.presetId }
                    return nil
                }()

                if !preserveAuthoredAction {
                    var playlistMap = existing.metadata.wledPlaylistIdsByDevice ?? [:]
                    var presetMap = existing.metadata.wledPresetIdsByDevice ?? [:]
                    if let nextPlaylistId {
                        playlistMap[device.id] = nextPlaylistId
                        presetMap.removeValue(forKey: device.id)
                        existing.metadata.setManagedPlaylistSignature(nil, for: device.id)
                        existing.metadata.setManagedPresetSignature(nil, for: device.id)
                        existing.metadata.setManagedStepPresetIds(nil, for: device.id)
                        if existing.targets.deviceIds.count == 1 {
                            existing.metadata.wledPlaylistId = nextPlaylistId
                        }
                    } else if let nextPresetId {
                        presetMap[device.id] = nextPresetId
                        playlistMap.removeValue(forKey: device.id)
                        existing.metadata.setManagedPresetSignature(nil, for: device.id)
                        existing.metadata.setManagedPlaylistSignature(nil, for: device.id)
                        existing.metadata.setManagedStepPresetIds(nil, for: device.id)
                        if existing.targets.deviceIds.count == 1 {
                            existing.metadata.wledPlaylistId = nil
                        }
                    }
                    existing.metadata.wledPlaylistIdsByDevice = playlistMap.isEmpty ? nil : playlistMap
                    existing.metadata.wledPresetIdsByDevice = presetMap.isEmpty ? nil : presetMap
                }
                var slotMap = existing.metadata.wledTimerSlotsByDevice ?? [:]
                slotMap[device.id] = timer.id
                existing.metadata.wledTimerSlotsByDevice = slotMap
                if existing.targets.deviceIds.count == 1 {
                    existing.metadata.wledTimerSlot = timer.id
                }
                var syncStateMap = existing.metadata.wledSyncStateByDevice ?? [:]
                syncStateMap[device.id] = importedSyncState
                existing.metadata.wledSyncStateByDevice = syncStateMap
                var syncAtMap = existing.metadata.wledLastSyncAtByDevice ?? [:]
                if let importedSyncAt {
                    syncAtMap[device.id] = importedSyncAt
                } else {
                    syncAtMap.removeValue(forKey: device.id)
                }
                existing.metadata.wledLastSyncAtByDevice = syncAtMap
                var errorMap = existing.metadata.wledLastSyncErrorByDevice ?? [:]
                if let importedSyncError {
                    errorMap[device.id] = importedSyncError
                } else {
                    errorMap.removeValue(forKey: device.id)
                }
                existing.metadata.wledLastSyncErrorByDevice = errorMap.isEmpty ? nil : errorMap
                existing.metadata.onDeviceStartMonth = importedStartMonth
                existing.metadata.onDeviceStartDay = importedStartDay
                existing.metadata.onDeviceEndMonth = importedEndMonth
                existing.metadata.onDeviceEndDay = importedEndDay
                existing.enabled = timer.enabled
                existing.trigger = trigger
                if preserveAuthoredAction {
                    logger.info(
                        "automation.import.preserve_action device=\(device.id, privacy: .public) automation=\(existing.id.uuidString, privacy: .public) slot=\(timer.id) action=\(String(describing: existing.action), privacy: .public)"
                    )
                } else {
                    existing.action = action
                }
                existing.metadata.runOnDevice = true
                if !preserveAuthoredAction && existing.metadata.templateId == nil {
                    existing.metadata.templateId = templateId
                }
                existing.metadata.normalizeWLEDScalarFallbacks(for: existing.targets.deviceIds)

                let didChange =
                    existing.enabled != updatedAutomations[index].enabled ||
                    existing.trigger != updatedAutomations[index].trigger ||
                    existing.action != updatedAutomations[index].action ||
                    existingPlaylistId != nextPlaylistId ||
                    existingPresetId != nextPresetId ||
                    (updatedAutomations[index].metadata.wledTimerSlotsByDevice?[device.id] ?? updatedAutomations[index].metadata.wledTimerSlot) != timer.id ||
                    updatedAutomations[index].metadata.syncState(for: device.id) != importedSyncState ||
                    updatedAutomations[index].metadata.lastSyncError(for: device.id) != importedSyncError ||
                    existing.metadata.wledPlaylistId != previousScalarPlaylistId ||
                    existing.metadata.wledTimerSlot != previousScalarTimerSlot ||
                    updatedAutomations[index].metadata.onDeviceStartMonth != importedStartMonth ||
                    updatedAutomations[index].metadata.onDeviceStartDay != importedStartDay ||
                    updatedAutomations[index].metadata.onDeviceEndMonth != importedEndMonth ||
                    updatedAutomations[index].metadata.onDeviceEndDay != importedEndDay
                if didChange {
                    existing.updatedAt = now
                    updatedAutomations[index] = existing
                    changed = true
                }
            } else {
                let playlistId: Int? = {
                    if case .playlist(let payload) = action { return payload.playlistId }
                    return nil
                }()
                let playlistMap: [String: Int]? = playlistId.map { [device.id: $0] }
                let presetMap: [String: Int]? = {
                    if case .preset(let payload) = action {
                        return [device.id: payload.presetId]
                    }
                    return nil
                }()
                var metadata = AutomationMetadata(
                    notes: "Imported from WLED timer slot \(timer.id)",
                    templateId: templateId,
                    wledPlaylistId: playlistId,
                    wledTimerSlot: timer.id,
                    wledPlaylistIdsByDevice: playlistMap,
                    wledPresetIdsByDevice: presetMap,
                    wledTimerSlotsByDevice: [device.id: timer.id],
                    wledSyncStateByDevice: [device.id: importedSyncState],
                    wledLastSyncErrorByDevice: importedSyncError.map { [device.id: $0] },
                    wledLastSyncAtByDevice: importedSyncAt.map { [device.id: $0] },
                    runOnDevice: true,
                    onDeviceStartMonth: importedStartMonth,
                    onDeviceStartDay: importedStartDay,
                    onDeviceEndMonth: importedEndMonth,
                    onDeviceEndDay: importedEndDay
                )
                metadata.normalizeWLEDScalarFallbacks(for: [device.id])
                let imported = Automation(
                    name: "WLED \(device.name) • \(actionLabel)",
                    enabled: timer.enabled,
                    createdAt: now,
                    updatedAt: now,
                    trigger: trigger,
                    action: action,
                    targets: AutomationTargets(deviceIds: [device.id]),
                    metadata: metadata
                )
                updatedAutomations.append(imported)
                signatureAutomationId = imported.id
                changed = true
            }

            if let signatureAutomationId {
                let key = timerSignatureKey(automationId: signatureAutomationId, deviceId: device.id)
                if importedSyncState == .synced {
                    lastKnownGoodTimerSignatureByAutomationDevice[key] = timerSignature(for: timer)
                } else {
                    lastKnownGoodTimerSignatureByAutomationDevice.removeValue(forKey: key)
                }
            }
        }

        // Remove stale imported rows for this device when a timer is no longer configured.
        let staleImportedIndexes = updatedAutomations.indices.filter { index in
            let automation = updatedAutomations[index]
            guard let templateId = automation.metadata.templateId,
                  templateId.hasPrefix("\(importedAutomationTemplatePrefix)\(device.id).") else {
                return false
            }
            let slot = automation.metadata.wledTimerSlotsByDevice?[device.id] ?? automation.metadata.wledTimerSlot
            guard let slot else { return true }
            return !configuredSlots.contains(slot) || duplicateAuthoredSlotsForCleanup.contains(slot)
        }
        if !staleImportedIndexes.isEmpty {
            for index in staleImportedIndexes.sorted(by: >) {
                updatedAutomations.remove(at: index)
            }
            changed = true
        }

        if !duplicateAuthoredSlotsForCleanup.isEmpty {
            let slots = Array(duplicateAuthoredSlotsForCleanup).sorted()
            await DeviceCleanupManager.shared.requestDelete(
                type: .timer,
                device: device,
                ids: slots,
                source: .automation,
                verificationRequired: true
            )
            logger.warning(
                "automation.import.duplicate_authored_slot_cleanup_requested device=\(device.id, privacy: .public) slots=\(slots, privacy: .public)"
            )
        }

        if changed {
            automations = updatedAutomations
            save()
            scheduleNext()
            scheduleSolarRefreshIfNeeded()
            scheduleOnDeviceSyncRetryIfNeeded()
            logger.info("Imported WLED automations for \(device.name, privacy: .public): timers=\(configuredTimers.count)")
        }
    }

    private func importedTemplateId(deviceId: String, slot: Int) -> String {
        "\(importedAutomationTemplatePrefix)\(deviceId).\(slot)"
    }

    private func isImportedTemplateId(_ templateId: String?) -> Bool {
        guard let templateId else { return false }
        return templateId.hasPrefix(importedAutomationTemplatePrefix)
    }

    private func authoredAutomationMatchIndexForImportedTimer(
        _ timer: WLEDTimer,
        device: WLEDDevice,
        in records: [Automation],
        referenceDate: Date
    ) async -> Int? {
        let importedWindow = normalizedTimerDateWindow(
            startMonth: timer.startMonth,
            startDay: timer.startDay,
            endMonth: timer.endMonth,
            endDay: timer.endDay
        )

        for (index, record) in records.enumerated() {
            guard record.metadata.runOnDevice else { continue }
            guard record.targets.deviceIds.contains(device.id) else { continue }
            guard !isImportedTemplateId(record.metadata.templateId) else { continue }
            guard let macroId = expectedMacroId(for: record, deviceId: device.id),
                  macroId == timer.macroId else {
                continue
            }
            guard let config = await wledTimerConfig(for: record, device: device, referenceDate: referenceDate) else {
                continue
            }
            guard config.hour == timer.hour,
                  config.minute == timer.minute,
                  config.days == timer.days else {
                continue
            }

            let expectedWindow = normalizedTimerDateWindow(
                startMonth: config.startMonth,
                startDay: config.startDay,
                endMonth: config.endMonth,
                endDay: config.endDay
            )
            guard expectedWindow.startMonth == importedWindow.startMonth,
                  expectedWindow.startDay == importedWindow.startDay,
                  expectedWindow.endMonth == importedWindow.endMonth,
                  expectedWindow.endDay == importedWindow.endDay else {
                continue
            }

            return index
        }

        return nil
    }

    private func runCleanupOrphanedPresetsIfNeeded(device: WLEDDevice? = nil) async {
        let lastRun = UserDefaults.standard.object(forKey: cleanupThrottleKey) as? Date ?? .distantPast
        let now = Date()
        guard now.timeIntervalSince(lastRun) >= cleanupThrottleInterval else { return }
        if let device {
            await cleanupOrphanedAutomationPresets(for: device)
        } else {
            await cleanupOrphanedAutomationPresets()
        }
        UserDefaults.standard.set(now, forKey: cleanupThrottleKey)
    }

    private func cleanupOrphanedAutomationPresets() async {
        let devices = viewModel.devices
        guard !devices.isEmpty else { return }
        for device in devices {
            await cleanupOrphanedAutomationPresets(for: device)
        }
    }

    func cleanupOrphanedAutomationPresets(
        for device: WLEDDevice,
        excludingAutomationId: UUID? = nil
    ) async {
        let deviceId = device.id
        if !(await viewModel.shouldAllowPresetStoreMutation(deviceId: deviceId)) {
            logger.warning(
                "automation.cleanup.orphan_sweep.deferred_integrity_guard device=\(deviceId, privacy: .public)"
            )
            return
        }
        var usedPresetIds: Set<Int> = []
        var usedPlaylistIds: Set<Int> = []
        var fallbackTransitionStepPresetIds: Set<Int> = []

        for preset in presetsStore.colorPresets {
            if let ids = preset.wledPresetIds, let id = ids[deviceId] {
                usedPresetIds.insert(id)
            }
            if let legacy = preset.wledPresetId {
                usedPresetIds.insert(legacy)
            }
        }

        for preset in presetsStore.effectPresets(for: deviceId) {
            if let id = preset.wledPresetId {
                usedPresetIds.insert(id)
            }
        }

        for preset in presetsStore.transitionPresets(for: deviceId) {
            if let playlistId = preset.wledPlaylistId {
                usedPlaylistIds.insert(playlistId)
            }
            if let stepIds = preset.wledStepPresetIds {
                fallbackTransitionStepPresetIds.formUnion(stepIds)
            }
        }

        for automation in automations {
            if let excludingAutomationId, automation.id == excludingAutomationId {
                continue
            }
            if let presetMap = automation.metadata.wledPresetIdsByDevice, let id = presetMap[deviceId] {
                usedPresetIds.insert(id)
            }
            if let playlistMap = automation.metadata.wledPlaylistIdsByDevice, let id = playlistMap[deviceId] {
                usedPlaylistIds.insert(id)
            }
            if let managedStepIds = automation.metadata.managedStepPresetIds(for: deviceId) {
                usedPresetIds.formUnion(managedStepIds)
            }
            if let playlistId = automation.metadata.wledPlaylistId {
                usedPlaylistIds.insert(playlistId)
            }
            if case .preset(let payload) = automation.action {
                usedPresetIds.insert(payload.presetId)
            }
            if case .playlist(let payload) = automation.action {
                usedPlaylistIds.insert(payload.playlistId)
            }
        }

        let playlists: [WLEDPlaylist]
        do {
            playlists = try await apiService.fetchPlaylists(for: device)
        } catch {
            logger.warning(
                "automation.cleanup.orphan_sweep.skipped_unreadable_playlists device=\(device.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let usedStepPresetIds = Set(
            playlists.filter { usedPlaylistIds.contains($0.id) }
                .flatMap { $0.presets }
        )
        usedPresetIds.formUnion(usedStepPresetIds)

        let presets: [WLEDPreset]
        do {
            presets = try await apiService.fetchPresets(for: device)
        } catch {
            logger.warning(
                "automation.cleanup.orphan_sweep.skipped_unreadable_presets device=\(device.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let fallbackStepDeletes = fallbackTransitionStepPresetIds.filter { !usedPresetIds.contains($0) }
        let presetDeletes = presets.filter { preset in
            guard !usedPresetIds.contains(preset.id) else { return false }
            return automationManagedPresetName(preset.name) || temporaryTransitionStepName(preset.name)
        }.map { $0.id } + fallbackStepDeletes

        let dedupedPresetDeletes = Array(Set(presetDeletes)).sorted()
        if dedupedPresetDeletes.count <= 20, !dedupedPresetDeletes.isEmpty {
            enqueueDeferredManagedAssetCleanup(
                type: .preset,
                device: device,
                ids: dedupedPresetDeletes,
                delay: orphanSweepDeferredCleanupDelaySeconds,
                reason: "orphan_sweep"
            )
        } else if dedupedPresetDeletes.count > 20 {
            logger.warning(
                "Skipping preset cleanup for \(device.name, privacy: .public): too many candidates (\(dedupedPresetDeletes.count))"
            )
        }

        let playlistDeletes = playlists.filter { playlist in
            guard !usedPlaylistIds.contains(playlist.id) else { return false }
            return automationManagedPresetName(playlist.name) || temporaryTransitionPlaylistName(playlist.name)
        }.map { $0.id }

        if playlistDeletes.count <= 10, !playlistDeletes.isEmpty {
            enqueueDeferredManagedAssetCleanup(
                type: .playlist,
                device: device,
                ids: playlistDeletes,
                delay: orphanSweepDeferredCleanupDelaySeconds,
                reason: "orphan_sweep"
            )
        } else if playlistDeletes.count > 10 {
            logger.warning("Skipping playlist cleanup for \(device.name, privacy: .public): too many candidates (\(playlistDeletes.count))")
        }
    }

    func cleanupOrphanedAutomationPresetsIfNeeded(for device: WLEDDevice) async {
        await runCleanupOrphanedPresetsIfNeeded(device: device)
    }

    private func enqueueDeferredManagedAssetCleanup(
        type: PendingDeviceDelete.DeleteType,
        device: WLEDDevice,
        ids: [Int],
        delay: TimeInterval,
        reason: String
    ) {
        let uniqueIds = Array(Set(ids)).sorted()
        guard !uniqueIds.isEmpty else { return }
        let notBefore = Date().addingTimeInterval(max(0, delay))
        DeviceCleanupManager.shared.enqueue(
            type: type,
            deviceId: device.id,
            ids: uniqueIds,
            source: .automation,
            verificationRequired: true,
            notBefore: notBefore
        )
        logger.info(
            "automation.cleanup.deferred type=\(type.rawValue, privacy: .public) device=\(device.id, privacy: .public) ids=\(uniqueIds, privacy: .public) reason=\(reason, privacy: .public) notBefore=\(notBefore.ISO8601Format(), privacy: .public)"
        )
    }

    private func automationManagedPresetName(_ name: String) -> Bool {
        let prefixes = ["Automation Step ", "Automation Transition ", "Automation "]
        return prefixes.contains { name.hasPrefix($0) }
    }

    private func temporaryTransitionPlaylistName(_ name: String) -> Bool {
        name.hasPrefix("Auto Transition ")
    }

    private func temporaryTransitionStepName(_ name: String) -> Bool {
        name.hasPrefix("Auto Step ")
    }

    private func scheduleSolarRefreshIfNeeded() {
        solarRefreshTimer?.invalidate()
        guard automations.contains(where: { automation in
            guard automation.metadata.runOnDevice else { return false }
            switch automation.trigger {
            case .sunrise, .sunset:
                return true
            default:
                return false
            }
        }) else {
            solarRefreshTimer = nil
            return
        }
        let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 5, second: 0),
            matchingPolicy: .nextTime
        )
        guard let nextMidnight else { return }
        let interval = max(60.0, nextMidnight.timeIntervalSince(Date()))
        solarRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.resyncOnDeviceSchedules()
                self?.scheduleSolarRefreshIfNeeded()
            }
        }
        RunLoop.main.add(solarRefreshTimer!, forMode: .common)
    }

    private func scheduleOnDeviceSyncRetryIfNeeded() {
        let hasOnDeviceAutomations = automations.contains { $0.metadata.runOnDevice }
        if !hasOnDeviceAutomations {
            onDeviceSyncRetryTimer?.invalidate()
            onDeviceSyncRetryTimer = nil
            return
        }
        guard onDeviceSyncRetryTimer == nil else { return }
        onDeviceSyncRetryTimer = Timer.scheduledTimer(withTimeInterval: onDeviceSyncRetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.retryPendingOnDeviceSyncIfNeeded()
            }
        }
        if let timer = onDeviceSyncRetryTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func retryPendingOnDeviceSyncIfNeeded() async {
        await validateSyncedOnDeviceSchedulesIfNeeded()

        let candidates = automations.filter { automation in
            guard automation.metadata.runOnDevice else { return false }
            let targetIds = automation.targets.deviceIds
            guard !targetIds.isEmpty else { return false }
            return targetIds.contains {
                let state = automation.metadata.syncState(for: $0)
                if state == .unknown || state == .syncing {
                    return true
                }
                if state == .notSynced {
                    return shouldAutoRetryNotSyncedState(
                        lastError: automation.metadata.lastSyncError(for: $0)
                    )
                }
                return false
            }
        }
        guard !candidates.isEmpty else { return }

        for automation in candidates {
            if onDeviceSyncInFlightAutomationIds.contains(automation.id) {
                continue
            }
            let targetIds = Set(automation.targets.deviceIds)
            let onlineTargetIds = Set(
                viewModel.devices
                    .filter { targetIds.contains($0.id) && $0.isOnline }
                    .map(\.id)
            )
            guard !onlineTargetIds.isEmpty else { continue }
            await syncOnDeviceScheduleIfNeeded(for: automation, deviceFilter: onlineTargetIds)
        }
    }

    private func shouldAutoRetryNotSyncedState(lastError: String?) -> Bool {
        guard let lastError else { return false }
        let message = lastError.lowercased()
        return message.contains("invalid response")
            || message.contains("verification mismatch")
            || message.contains("device busy")
            || message.contains("temporarily unreachable")
            || message.contains("retrying")
    }

    private func validateSyncedOnDeviceSchedulesIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastSyncedValidationAt) >= syncedValidationInterval else { return }
        lastSyncedValidationAt = now

        let candidates = automations.filter { automation in
            guard automation.metadata.runOnDevice else { return false }
            return automation.targets.deviceIds.contains { automation.metadata.syncState(for: $0) == .synced }
        }
        guard !candidates.isEmpty else { return }

        for automation in candidates {
            for deviceId in automation.targets.deviceIds where automation.metadata.syncState(for: deviceId) == .synced {
                guard let device = viewModel.devices.first(where: { $0.id == deviceId }),
                      device.isOnline else {
                    continue
                }
                if onDeviceSyncInFlightAutomationIds.contains(automation.id) {
                    continue
                }
                let stillValid = await isSyncedScheduleStillValid(for: automation, device: device)
                guard !stillValid else { continue }
                logger.warning("On-device schedule drift detected, resyncing automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public)")
                await syncOnDeviceScheduleIfNeeded(for: automation, deviceFilter: [device.id])
            }
        }
    }

    private func shouldDeferToDeviceTimer(_ automation: Automation) -> Bool {
        guard automation.metadata.runOnDevice else { return false }
        let targetIds = automation.targets.deviceIds
        guard !targetIds.isEmpty else { return false }
        return targetIds.allSatisfy { deviceId in
            let hasSlot = automation.metadata.wledTimerSlotsByDevice?[deviceId] != nil
                || (targetIds.count == 1 && automation.metadata.wledTimerSlot != nil)
            let state = automation.metadata.syncState(for: deviceId)
            return hasSlot && state == .synced
        }
    }
    
    private func resolveNextAutomation(referenceDate: Date) async -> (Automation, Date)? {
        var best: (Automation, Date)?
        for automation in automations where automation.enabled {
            guard !automation.metadata.runOnDevice else { continue }
            if let nextDate = automation.nextTriggerDate(referenceDate: referenceDate) {
                if best == nil || nextDate < best!.1 {
                    best = (automation, nextDate)
                }
                continue
            }
            
            if let solarDate = await resolveSolarTrigger(for: automation, referenceDate: referenceDate) {
                if best == nil || solarDate < best!.1 {
                    best = (automation, solarDate)
                }
            }
        }
        return best
    }
    
    private func resolveSolarTrigger(for automation: Automation, referenceDate: Date) async -> Date? {
        let preferredDevice = preferredSolarDevice(for: automation)
        switch automation.trigger {
        case .sunrise(let solar):
            return await computeSolarDate(
                event: .sunrise,
                trigger: solar,
                referenceDate: referenceDate,
                preferredDevice: preferredDevice
            )
        case .sunset(let solar):
            return await computeSolarDate(
                event: .sunset,
                trigger: solar,
                referenceDate: referenceDate,
                preferredDevice: preferredDevice
            )
        default:
            return nil
        }
    }

    func nextTriggerDate(for automation: Automation, referenceDate: Date = Date()) async -> Date? {
        if let next = automation.nextTriggerDate(referenceDate: referenceDate) {
            return next
        }
        return await resolveSolarTrigger(for: automation, referenceDate: referenceDate)
    }
    
    func computeSolarDate(
        event: SolarEvent,
        trigger: SolarTrigger,
        referenceDate: Date,
        preferredDevice: WLEDDevice? = nil
    ) async -> Date? {
        guard let solarReference = await solarReference(for: trigger.location, preferredDevice: preferredDevice) else {
            logger.error("Missing coordinate for solar automation")
            return nil
        }

        let cacheKey = SolarCacheKey(
            event: event,
            coordinate: solarReference.coordinate,
            timeZoneIdentifier: solarReference.timeZone.identifier,
            date: Calendar.current.startOfDay(for: referenceDate),
            offsetMinutes: trigger.offset
        )
        if let cached = solarCache[cacheKey], cached > referenceDate {
            return cached
        }
        
        let offsetMinutes: Int
        switch trigger.offset {
        case .minutes(let value):
            offsetMinutes = value
        }
        
        guard let eventDate = SunriseSunsetCalculator.nextEventDate(
            event: event,
            coordinate: solarReference.coordinate,
            referenceDate: referenceDate,
            offsetMinutes: offsetMinutes,
            timeZone: solarReference.timeZone
        ) else {
            return nil
        }
        solarCache[cacheKey] = eventDate
        return eventDate
    }
    
    /// Public API to get user's current coordinate
    /// Returns nil if permission denied or location unavailable
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        do {
            return try await locationProvider.currentCoordinate()
        } catch {
            logger.warning("Location unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    /// Preferred solar reference used by sunrise/sunset editors.
    /// Source order: iOS location -> WLED config (if.ntp).
    func currentSolarReference(for device: WLEDDevice) async -> (coordinate: CLLocationCoordinate2D, timeZone: TimeZone)? {
        guard let reference = await solarReference(for: .followDevice, preferredDevice: device) else {
            return nil
        }
        return (reference.coordinate, reference.timeZone)
    }
    
    /// Public API for components to resolve solar trigger dates
    func resolveSolarTriggerDate(
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        date: Date,
        offsetMinutes: Int,
        timeZone: TimeZone = .current
    ) -> Date? {
        let result = SunriseSunsetCalculator.nextEventDate(
            event: event,
            coordinate: coordinate,
            referenceDate: date,
            offsetMinutes: offsetMinutes,
            timeZone: timeZone
        )
        #if DEBUG
        print("🔍 resolveSolarTriggerDate: \(event) at \(coordinate.latitude), \(coordinate.longitude) offset \(offsetMinutes) = \(result?.formatted(date: .omitted, time: .shortened) ?? "nil")")
        #endif
        return result
    }

    private func preferredSolarDevice(for automation: Automation) -> WLEDDevice? {
        let targetIds = Set(automation.targets.deviceIds)
        return viewModel.devices.first(where: { targetIds.contains($0.id) })
    }

    private func solarReference(
        for source: SolarTrigger.LocationSource,
        preferredDevice: WLEDDevice?
    ) async -> SolarReference? {
        switch source {
        case .manual(let lat, let lon):
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if let preferredDevice,
               let wledReference = await wledSolarReference(for: preferredDevice) {
                return SolarReference(
                    coordinate: coordinate,
                    timeZone: wledReference.timeZone ?? .current,
                    source: .manual
                )
            }
            return SolarReference(coordinate: coordinate, timeZone: .current, source: .manual)

        case .followDevice:
            do {
                let coordinate = try await locationProvider.currentCoordinate()
                return SolarReference(
                    coordinate: coordinate,
                    timeZone: .current,
                    source: .deviceLocation
                )
            } catch {
                logger.warning("Failed to fetch iOS location for solar schedule: \(error.localizedDescription)")
                if let preferredDevice,
                   let wledReference = await wledSolarReference(for: preferredDevice),
                   let coordinate = wledReference.coordinate {
                    return SolarReference(
                        coordinate: coordinate,
                        timeZone: wledReference.timeZone ?? .current,
                        source: .wledConfig
                    )
                }
                logger.error("No solar reference available: iOS location unavailable and WLED location missing")
                return nil
            }
        }
    }

    private func wledSolarReference(
        for device: WLEDDevice
    ) async -> (coordinate: CLLocationCoordinate2D?, timeZone: TimeZone?)? {
        do {
            return try await apiService.fetchSolarReference(for: device)
        } catch {
            logger.warning("Failed to fetch WLED solar reference for \(device.name, privacy: .public): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func perform(action: AutomationAction, automation: Automation, on device: WLEDDevice) async -> Bool {
        switch action {
        case .scene(let payload):
            // Set short-lived "Applying" status
            _ = await MainActor.run {
                viewModel.activeRunStatus[device.id] = ActiveRunStatus(
                    deviceId: device.id,
                    kind: .applying,
                    automationId: automation.id,
                    title: automation.name,
                    startDate: Date(),
                    progress: 0.0,
                    isCancellable: false
                )
            }
            
            guard let scene = scenesStore.scenes.first(where: { $0.id == payload.sceneId }) else {
                logger.error("Scene \(payload.sceneId) missing for automation \(automation.name)")
                _ = await MainActor.run {
                    viewModel.activeRunStatus.removeValue(forKey: device.id)
                }
                return false
            }
            var sceneCopy = scene
            sceneCopy.deviceId = device.id
            if let override = payload.brightnessOverride {
                sceneCopy.brightness = override
            }
            await viewModel.applyScene(sceneCopy, to: device, userInitiated: false)
            
            // Clear status after completion
            _ = await MainActor.run {
                viewModel.activeRunStatus.removeValue(forKey: device.id)
            }
            return true
            
        case .preset(let payload):
            // Set short-lived "Applying" status
            _ = await MainActor.run {
                viewModel.activeRunStatus[device.id] = ActiveRunStatus(
                    deviceId: device.id,
                    kind: .applying,
                    automationId: automation.id,
                    title: automation.name,
                    startDate: Date(),
                    progress: 0.0,
                    isCancellable: false
                )
            }
            
            // Use transition time if provided (seconds -> deciseconds)
            let transitionDeciseconds = payload.durationSeconds.map { max(0, Int(($0 * 10.0).rounded())) }
            let applied = await viewModel.applyPresetId(
                payload.presetId,
                to: device,
                transitionDeciseconds: transitionDeciseconds,
                preferWebSocketFirst: true,
                markInteraction: false
            )
            guard applied else {
                logger.error("Failed to apply preset \(payload.presetId) for automation \(automation.name)")
                _ = await MainActor.run {
                    viewModel.activeRunStatus.removeValue(forKey: device.id)
                }
                return false
            }

            // Clear status after completion
            _ = await MainActor.run {
                viewModel.activeRunStatus.removeValue(forKey: device.id)
            }
            return true
            
        case .playlist(let payload):
            let expectedDuration = await playlistDurationSeconds(
                playlistId: payload.playlistId,
                device: device
            )
            let started = await viewModel.startPlaylist(
                device: device,
                playlistId: payload.playlistId,
                runTitle: automation.name,
                expectedDurationSeconds: expectedDuration,
                runKind: .automation,
                runAutomationId: automation.id,
                strictValidation: true,
                preferWebSocketFirst: true
            )
            guard started else {
                logger.error("Failed to apply playlist \(payload.playlistId) for automation \(automation.name)")
                return false
            }
            return true
            
        case .gradient(let payload):
            if !payload.powerOn {
                let transitionDs: Int?
                if payload.durationSeconds > 0 {
                    let clamped = min(payload.durationSeconds, maxWLEDNativeTransitionSeconds)
                    transitionDs = Int((clamped * 10.0).rounded())
                } else {
                    transitionDs = nil
                }
                do {
                    _ = try await apiService.setPower(for: device, isOn: false, transitionDeciseconds: transitionDs)
                    return true
                } catch {
                    logger.error("Failed to power off device for automation \(automation.name): \(error.localizedDescription)")
                    return false
                }
            }
            let gradient = resolveGradientPayload(payload, device: device)
            let ledCount = viewModel.totalLEDCount(for: device)
            let resolvedTemperature = payload.temperature ?? payload.presetId.flatMap { presetsStore.colorPreset(id: $0)?.temperature }
            let resolvedWhiteLevel = payload.whiteLevel ?? payload.presetId.flatMap { presetsStore.colorPreset(id: $0)?.whiteLevel }
            let stopTemperatures = resolvedTemperature.map { temp in
                Dictionary(uniqueKeysWithValues: gradient.stops.map { ($0.id, temp) })
            }
            let stopWhiteLevels = resolvedWhiteLevel.map { white in
                Dictionary(uniqueKeysWithValues: gradient.stops.map { ($0.id, white) })
            }
            var durationSeconds = payload.durationSeconds
            if durationSeconds > maxWLEDNativeTransitionSeconds {
                durationSeconds = maxWLEDNativeTransitionSeconds
            }
            
            // Use native WLED transition for solid colors with duration > 0
            if durationSeconds > 0 && viewModel.shouldUseNativeTransition(stops: gradient.stops, durationSeconds: durationSeconds) {
                logger.info("Automation gradient path=native-tt device=\(device.name, privacy: .public) duration=\(durationSeconds, privacy: .public)s")
                // Solid color with transition - use native WLED tt
                // Extract target color RGB for native transition metadata
                let targetColor = Color(hex: gradient.stops.first?.hexColor ?? "#FFFFFF")
                let targetRGB = targetColor.toRGBArray()
                let targetBrightness = payload.brightness
                
                let startDate = Date()
                let expectedEnd = startDate.addingTimeInterval(durationSeconds)
                let runId = UUID()
                
                // Set active run status with native transition metadata
                _ = await MainActor.run {
                    viewModel.activeRunStatus[device.id] = ActiveRunStatus(
                        id: runId,
                        deviceId: device.id,
                        kind: .automation,
                        automationId: automation.id,
                        title: automation.name,
                        startDate: startDate,
                        progress: 0.0,
                        isCancellable: true,
                        expectedEnd: expectedEnd,
                        nativeTransition: NativeTransitionInfo(
                            targetColorRGB: targetRGB,
                            targetBrightness: targetBrightness,
                            durationSeconds: durationSeconds
                        )
                    )
                }
                
                await apiService.releaseRealtimeOverride(for: device)
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: gradient.stops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperatures,
                    stopWhiteLevels: stopWhiteLevels,
                    disableActiveEffect: true,
                    interpolation: gradient.interpolation,
                    brightness: payload.brightness,
                    on: true,
                    transitionDurationSeconds: durationSeconds,
                    releaseRealtimeOverride: false,
                    userInitiated: false,
                    preferSegmented: true
                )
                
                // Clear status after transition completes (use timer with runId check to prevent race condition)
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
                    _ = await MainActor.run {
                        // Only clear if this run is still active (check runId to prevent clearing newer runs)
                        if let currentStatus = viewModel.activeRunStatus[device.id], currentStatus.id == runId {
                            viewModel.activeRunStatus.removeValue(forKey: device.id)
                        }
                    }
                }
            } else if durationSeconds > 0.5 {
                logger.info("Automation gradient path=segmented-tt device=\(device.name, privacy: .public) duration=\(durationSeconds, privacy: .public)s")
                // Multi-stop gradient with transition - use segmented update with native tt
                await apiService.releaseRealtimeOverride(for: device)
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: gradient.stops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperatures,
                    stopWhiteLevels: stopWhiteLevels,
                    disableActiveEffect: true,
                    interpolation: gradient.interpolation,
                    brightness: payload.brightness,
                    on: true,
                    transitionDurationSeconds: durationSeconds,
                    releaseRealtimeOverride: false,
                    userInitiated: false,
                    preferSegmented: true
                )
            } else {
                logger.info("Automation gradient path=immediate device=\(device.name, privacy: .public)")
                // No transition or very short - apply immediately
                await viewModel.applyGradientStopsAcrossStrip(
                    device,
                    stops: gradient.stops,
                    ledCount: ledCount,
                    stopTemperatures: stopTemperatures,
                    stopWhiteLevels: stopWhiteLevels,
                    disableActiveEffect: true,
                    interpolation: gradient.interpolation,
                    brightness: payload.brightness,
                    on: true,
                    userInitiated: false,
                    preferSegmented: true
                )
            }
            return true
            
        case .transition(let payload):
            let resolved = resolveTransitionPayload(payload, device: device)
            if let managedPlaylist = await ensureAutomationTransitionPlaylist(
                for: automation,
                device: device,
                payload: resolved
            ) {
                if storedPlaylistId(for: automation, deviceId: device.id) == nil {
                    let updated = updateAutomationMetadata(
                        automation,
                        deviceId: device.id,
                        playlistId: managedPlaylist.playlistId,
                        playlistStepPresetIds: managedPlaylist.stepPresetIds
                    )
                    update(updated, syncOnDevice: false)
                }
                let started = await viewModel.startPlaylist(
                    device: device,
                    playlistId: managedPlaylist.playlistId,
                    runTitle: automation.name,
                    expectedDurationSeconds: resolved.durationSeconds,
                    runKind: .automation,
                    runAutomationId: automation.id,
                    strictValidation: true,
                    preferWebSocketFirst: true
                )
                if started {
                    return true
                }
                logger.error("Failed to start stored transition playlist \(managedPlaylist.playlistId) for automation \(automation.name)")
            }
            logger.error("Failed to prepare transition playlist for automation \(automation.name)")
            return false
            
        case .effect(let payload):
            let resolved = resolveEffectPayload(payload, device: device)
            let gradient = resolved.gradient ?? defaultGradient(for: device)
            await viewModel.updateDeviceBrightness(device, brightness: resolved.brightness, userInitiated: false)
            await viewModel.applyColorSafeEffect(
                resolved.effectId,
                with: gradient,
                segmentId: 0,
                device: device,
                userInitiated: false
            )
            return true
            
        case .directState(let payload):
            // Set short-lived "Applying" status if no transition, or track progress if transition exists
            let transitionSeconds = payload.transitionDeciseconds > 0 ? Double(payload.transitionDeciseconds) / 10.0 : nil
            if transitionSeconds == nil {
                // Set short-lived "Applying" status (no watchdog needed - these complete quickly)
                _ = await MainActor.run {
                    viewModel.activeRunStatus[device.id] = ActiveRunStatus(
                        deviceId: device.id,
                        kind: .applying,
                        automationId: automation.id,
                        title: automation.name,
                        startDate: Date(),
                        progress: 0.0,
                        isCancellable: false
                    )
                    // Note: No watchdog for .applying runs - they're expected to complete quickly
                }
            }
            
            // Direct state is always a solid color (single hex color), so use native transition if duration > 0
            let stops = [
                GradientStop(position: 0.0, hexColor: payload.colorHex),
                GradientStop(position: 1.0, hexColor: payload.colorHex)
            ]
            let ledCount = viewModel.totalLEDCount(for: device)
            let stopTemperatures = payload.temperature.map { temp in
                Dictionary(uniqueKeysWithValues: stops.map { ($0.id, temp) })
            }
            let stopWhiteLevels = payload.whiteLevel.map { white in
                Dictionary(uniqueKeysWithValues: stops.map { ($0.id, white) })
            }
            // Use native transition if transition is set (solid color with duration)
            await viewModel.applyGradientStopsAcrossStrip(
                device,
                stops: stops,
                ledCount: ledCount,
                stopTemperatures: stopTemperatures,
                stopWhiteLevels: stopWhiteLevels,
                disableActiveEffect: true,
                brightness: payload.brightness,
                on: true,
                transitionDurationSeconds: transitionSeconds,
                userInitiated: false,
                preferSegmented: true
            )
            
            // Clear status after completion
            _ = await MainActor.run {
                viewModel.activeRunStatus.removeValue(forKey: device.id)
            }
            // Don't call updateDeviceBrightness separately - it's already included in applyGradientStopsAcrossStrip
            return true
        }
    }
    
    private func runActionWithRetry(
        _ action: AutomationAction,
        automation: Automation,
        on device: WLEDDevice,
        retryAttempts: Int
    ) async -> Bool {
        if await perform(action: action, automation: automation, on: device) {
            return true
        }
        guard retryAttempts > 0 else { return false }
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await runActionWithRetry(action, automation: automation, on: device, retryAttempts: retryAttempts - 1)
    }

    private func storedPlaylistId(for automation: Automation, deviceId: String) -> Int? {
        if let map = automation.metadata.wledPlaylistIdsByDevice, let id = map[deviceId] {
            return id
        }
        return automation.metadata.wledPlaylistId
    }

    private func storedManagedTransitionStepPresetIds(for automation: Automation, deviceId: String) -> [Int] {
        automation.metadata.managedStepPresetIds(for: deviceId) ?? []
    }

    private func storedPresetId(for automation: Automation, deviceId: String) -> Int? {
        if let map = automation.metadata.wledPresetIdsByDevice, let id = map[deviceId] {
            return id
        }
        return nil
    }

    private func storedTimerSlot(for automation: Automation, deviceId: String) -> Int? {
        if let map = automation.metadata.wledTimerSlotsByDevice, let slot = map[deviceId] {
            return slot
        }
        return automation.metadata.wledTimerSlot
    }

    private func expectedMacroId(for automation: Automation, deviceId: String) -> Int? {
        switch automation.action {
        case .preset(let payload):
            return payload.presetId
        case .playlist(let payload):
            return payload.playlistId
        case .transition:
            return storedPlaylistId(for: automation, deviceId: deviceId)
        case .gradient, .directState, .effect, .scene:
            return storedPresetId(for: automation, deviceId: deviceId)
        }
    }

    private func expectsPlaylistMacro(for automation: Automation) -> Bool {
        switch automation.action {
        case .playlist, .transition:
            return true
        case .preset, .gradient, .directState, .effect, .scene:
            return false
        }
    }

    private func timerSignatureKey(automationId: UUID, deviceId: String) -> String {
        "\(automationId.uuidString)|\(deviceId)"
    }

    private func timerSignature(
        enabled: Bool,
        hour: Int,
        minute: Int,
        days: Int,
        macroId: Int,
        startMonth: Int?,
        startDay: Int?,
        endMonth: Int?,
        endDay: Int?
    ) -> String {
        let normalizedWindow = normalizedTimerDateWindow(
            startMonth: startMonth,
            startDay: startDay,
            endMonth: endMonth,
            endDay: endDay
        )
        return "\(enabled ? 1 : 0)|\(hour)|\(minute)|\(days)|\(macroId)|\(normalizedWindow.startMonth ?? 0)|\(normalizedWindow.startDay ?? 0)|\(normalizedWindow.endMonth ?? 0)|\(normalizedWindow.endDay ?? 0)"
    }

    private func normalizedTimerDateWindow(
        startMonth: Int?,
        startDay: Int?,
        endMonth: Int?,
        endDay: Int?
    ) -> (startMonth: Int?, startDay: Int?, endMonth: Int?, endDay: Int?) {
        // Treat "all zero" and partial windows as no-window.
        let normalizedValues = [startMonth, startDay, endMonth, endDay].map { max(0, $0 ?? 0) }
        if normalizedValues.allSatisfy({ $0 == 0 }) {
            return (nil, nil, nil, nil)
        }
        guard startMonth != nil, startDay != nil, endMonth != nil, endDay != nil else {
            return (nil, nil, nil, nil)
        }
        // Treat explicit full-year windows as equivalent to "no window".
        if startMonth == 1 && startDay == 1 && endMonth == 12 && endDay == 31 {
            return (nil, nil, nil, nil)
        }
        return (startMonth, startDay, endMonth, endDay)
    }

    private func timerSignature(for timer: WLEDTimer) -> String {
        timerSignature(
            enabled: timer.enabled,
            hour: timer.hour,
            minute: timer.minute,
            days: timer.days,
            macroId: timer.macroId,
            startMonth: timer.startMonth,
            startDay: timer.startDay,
            endMonth: timer.endMonth,
            endDay: timer.endDay
        )
    }

    private enum TimerOwnershipStatus {
        case owned
        case notOwned
        case unknown(String)
    }

    private func timerOwnershipStatusForDeletion(
        automation: Automation,
        device: WLEDDevice,
        slot: Int
    ) async -> TimerOwnershipStatus {
        guard let macroId = expectedMacroId(for: automation, deviceId: device.id),
              (1...maxWLEDPresetSlots).contains(macroId) else {
            return .unknown("missing_expected_macro")
        }
        guard let expectedConfig = await wledTimerConfig(for: automation, device: device, referenceDate: Date()) else {
            return .unknown("missing_expected_timer_config")
        }
        let expectedHours: [Int] = {
            // Backward compatibility: older builds could encode sunset on slot 9 with hour=255.
            if slot == 9 && expectedConfig.hour == 254 {
                return [254, 255]
            }
            return [expectedConfig.hour]
        }()
        var ownedSignatures: Set<String> = []
        for expectedHour in expectedHours {
            ownedSignatures.insert(
                timerSignature(
                    enabled: true,
                    hour: expectedHour,
                    minute: expectedConfig.minute,
                    days: expectedConfig.days,
                    macroId: macroId,
                    startMonth: expectedConfig.startMonth,
                    startDay: expectedConfig.startDay,
                    endMonth: expectedConfig.endMonth,
                    endDay: expectedConfig.endDay
                )
            )
            ownedSignatures.insert(
                timerSignature(
                    enabled: false,
                    hour: expectedHour,
                    minute: expectedConfig.minute,
                    days: expectedConfig.days,
                    macroId: macroId,
                    startMonth: expectedConfig.startMonth,
                    startDay: expectedConfig.startDay,
                    endMonth: expectedConfig.endMonth,
                    endDay: expectedConfig.endDay
                )
            )
        }
        let knownSignature = lastKnownGoodTimerSignatureByAutomationDevice[
            timerSignatureKey(automationId: automation.id, deviceId: device.id)
        ]

        do {
            let timers = try await apiService.fetchTimers(for: device)
            guard let timer = timers.first(where: { $0.id == slot }) else {
                return .notOwned
            }
            let currentSignature = timerSignature(for: timer)
            if ownedSignatures.contains(currentSignature) {
                return .owned
            }
            if let knownSignature, currentSignature == knownSignature {
                return .owned
            }
            return .notOwned
        } catch {
            if isTransientOnDeviceSyncError(error) {
                return .unknown(error.localizedDescription)
            }
            return .notOwned
        }
    }

    private func doesTimerSlotMatchSignature(device: WLEDDevice, slot: Int, expectedSignature: String) async -> Bool {
        do {
            let timers = try await apiService.fetchTimers(for: device)
            guard let timer = timers.first(where: { $0.id == slot }) else {
                return false
            }
            return timerSignature(for: timer) == expectedSignature
        } catch {
            logger.warning("Could not verify timer signature for \(device.name, privacy: .public) slot=\(slot): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func verifyTimerWithRetry(
        _ timerUpdate: WLEDTimerUpdate,
        on device: WLEDDevice,
        attempts: Int = 4,
        initialDelayMs: UInt64 = 180
    ) async throws -> Bool {
        var delayMs = initialDelayMs
        var lastError: Error?
        for attempt in 1...max(1, attempts) {
            do {
                if try await apiService.verifyTimer(timerUpdate, on: device) {
                    return true
                }
            } catch {
                lastError = error
                if !isTransientOnDeviceSyncError(error) {
                    throw error
                }
            }
            if attempt < attempts {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                delayMs = min(delayMs * 2, 1_200)
            }
        }
        if let lastError {
            throw lastError
        }
        return false
    }

    private func isSyncedScheduleStillValid(for automation: Automation, device: WLEDDevice) async -> Bool {
        guard let slot = storedTimerSlot(for: automation, deviceId: device.id),
              let macroId = expectedMacroId(for: automation, deviceId: device.id),
              (1...250).contains(macroId) else {
            return false
        }
        guard let expectedConfig = await wledTimerConfig(for: automation, device: device, referenceDate: Date()) else {
            return false
        }

        let timers: [WLEDTimer]
        do {
            timers = try await apiService.fetchTimers(for: device)
        } catch {
            logger.warning("Skipping synced automation validation (timers unavailable) for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return true
        }

        guard let timer = timers.first(where: { $0.id == slot }) else {
            return false
        }
        guard timer.enabled == automation.enabled,
              timer.hour == expectedConfig.hour,
              timer.minute == expectedConfig.minute,
              timer.days == expectedConfig.days,
              timer.macroId == macroId else {
            return false
        }
        let expectedWindow = normalizedTimerDateWindow(
            startMonth: expectedConfig.startMonth,
            startDay: expectedConfig.startDay,
            endMonth: expectedConfig.endMonth,
            endDay: expectedConfig.endDay
        )
        let actualWindow = normalizedTimerDateWindow(
            startMonth: timer.startMonth,
            startDay: timer.startDay,
            endMonth: timer.endMonth,
            endDay: timer.endDay
        )
        guard expectedWindow.startMonth == actualWindow.startMonth,
              expectedWindow.startDay == actualWindow.startDay,
              expectedWindow.endMonth == actualWindow.endMonth,
              expectedWindow.endDay == actualWindow.endDay else {
            return false
        }

        if expectsPlaylistMacro(for: automation) {
            do {
                let playlists = try await apiService.fetchPlaylists(for: device)
                guard playlists.contains(where: { $0.id == macroId }) else {
                    return false
                }
            } catch {
                logger.warning("Skipping synced automation validation (playlists unavailable) for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            }
        } else {
            do {
                let presets = try await apiService.fetchPresets(for: device)
                guard presets.contains(where: { $0.id == macroId }) else {
                    return false
                }
            } catch {
                logger.warning("Skipping synced automation validation (presets unavailable) for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            }
        }

        let key = timerSignatureKey(automationId: automation.id, deviceId: device.id)
        lastKnownGoodTimerSignatureByAutomationDevice[key] = timerSignature(for: timer)
        return true
    }

    private func removeTimerSignatures(for automationId: UUID) {
        let prefix = "\(automationId.uuidString)|"
        lastKnownGoodTimerSignatureByAutomationDevice.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { lastKnownGoodTimerSignatureByAutomationDevice.removeValue(forKey: $0) }
    }

    private func removeTimerSignatures(for automationId: UUID, deviceIds: Set<String>) {
        guard !deviceIds.isEmpty else { return }
        for deviceId in deviceIds {
            let key = timerSignatureKey(automationId: automationId, deviceId: deviceId)
            lastKnownGoodTimerSignatureByAutomationDevice.removeValue(forKey: key)
        }
    }

    private func cleanupRemovedOnDeviceTargets(
        previous: Automation,
        removedDeviceIds: Set<String>
    ) async {
        guard previous.metadata.runOnDevice else { return }
        guard !removedDeviceIds.isEmpty else { return }
        for deviceId in removedDeviceIds {
            let slot = previous.metadata.wledTimerSlotsByDevice?[deviceId]
                ?? (previous.targets.deviceIds.count == 1 ? previous.metadata.wledTimerSlot : nil)
            guard let slot else { continue }
            if let device = viewModel.devices.first(where: { $0.id == deviceId }) {
                await DeviceCleanupManager.shared.requestDelete(
                    type: .timer,
                    device: device,
                    ids: [slot],
                    source: .automation,
                    verificationRequired: true
                )
            } else {
                DeviceCleanupManager.shared.enqueue(
                    type: .timer,
                    deviceId: deviceId,
                    ids: [slot],
                    source: .automation,
                    verificationRequired: true
                )
            }
        }
    }

    private func updateAutomationMetadata(
        _ automation: Automation,
        deviceId: String,
        playlistId: Int? = nil,
        playlistStepPresetIds: [Int]? = nil,
        presetId: Int? = nil,
        timerSlot: Int? = nil,
        managedPlaylistSignature: String? = nil,
        managedPresetSignature: String? = nil
    ) -> Automation {
        var updated = automation
        var checkpoint = updated.metadata.managedAssetCheckpoint(for: deviceId)
        var checkpointTouched = false
        if let playlistId {
            var map = updated.metadata.wledPlaylistIdsByDevice ?? [:]
            map[deviceId] = playlistId
            updated.metadata.wledPlaylistIdsByDevice = map
            if updated.targets.deviceIds.count == 1 {
                updated.metadata.wledPlaylistId = playlistId
            }
            updated.metadata.setManagedPlaylistSignature(managedPlaylistSignature, for: deviceId)
            updated.metadata.setManagedPresetSignature(nil, for: deviceId)
            if let playlistStepPresetIds {
                updated.metadata.setManagedStepPresetIds(playlistStepPresetIds, for: deviceId)
            } else if managedPlaylistSignature == nil {
                updated.metadata.setManagedStepPresetIds(nil, for: deviceId)
            }
            checkpointTouched = true
            let managedStepIds = playlistStepPresetIds ?? updated.metadata.managedStepPresetIds(for: deviceId) ?? []
            let hasManagedPlaylistContext =
                (managedPlaylistSignature?.isEmpty == false) || !managedStepIds.isEmpty
            if hasManagedPlaylistContext {
                checkpoint = ManagedAutomationAssetCheckpoint(
                    capturedAt: Date(),
                    playlistId: playlistId,
                    presetId: nil,
                    stepPresetIds: managedStepIds,
                    playlistSignature: managedPlaylistSignature,
                    presetSignature: nil
                )
            } else {
                checkpoint = nil
            }
        }
        if let presetId {
            var map = updated.metadata.wledPresetIdsByDevice ?? [:]
            map[deviceId] = presetId
            updated.metadata.wledPresetIdsByDevice = map
            updated.metadata.setManagedPresetSignature(managedPresetSignature, for: deviceId)
            updated.metadata.setManagedPlaylistSignature(nil, for: deviceId)
            updated.metadata.setManagedStepPresetIds(nil, for: deviceId)
            checkpointTouched = true
            if managedPresetSignature?.isEmpty == false {
                checkpoint = ManagedAutomationAssetCheckpoint(
                    capturedAt: Date(),
                    playlistId: nil,
                    presetId: presetId,
                    stepPresetIds: [],
                    playlistSignature: nil,
                    presetSignature: managedPresetSignature
                )
            } else {
                checkpoint = nil
            }
        }
        if let timerSlot {
            var map = updated.metadata.wledTimerSlotsByDevice ?? [:]
            map[deviceId] = timerSlot
            updated.metadata.wledTimerSlotsByDevice = map
            if updated.targets.deviceIds.count == 1 {
                updated.metadata.wledTimerSlot = timerSlot
            }
        }
        if checkpointTouched {
            updated.metadata.setManagedAssetCheckpoint(checkpoint, for: deviceId)
        }
        updated.metadata.normalizeWLEDScalarFallbacks(for: updated.targets.deviceIds)
        return updated
    }

    private func updateAutomationSyncMetadata(
        _ automation: Automation,
        deviceId: String,
        state: AutomationMetadata.WLEDSyncState,
        error: String? = nil,
        syncedAt: Date? = nil
    ) -> Automation {
        var updated = automation
        var stateMap = updated.metadata.wledSyncStateByDevice ?? [:]
        stateMap[deviceId] = state
        updated.metadata.wledSyncStateByDevice = stateMap

        var errorMap = updated.metadata.wledLastSyncErrorByDevice ?? [:]
        if let error, !error.isEmpty {
            errorMap[deviceId] = error
        } else {
            errorMap.removeValue(forKey: deviceId)
        }
        updated.metadata.wledLastSyncErrorByDevice = errorMap.isEmpty ? nil : errorMap

        var syncAtMap = updated.metadata.wledLastSyncAtByDevice ?? [:]
        if let syncedAt {
            syncAtMap[deviceId] = syncedAt
        } else {
            syncAtMap.removeValue(forKey: deviceId)
        }
        updated.metadata.wledLastSyncAtByDevice = syncAtMap.isEmpty ? nil : syncAtMap
        return updated
    }

    private func clearTimerSlotMetadata(
        _ automation: Automation,
        deviceId: String
    ) -> Automation {
        var updated = automation
        if var map = updated.metadata.wledTimerSlotsByDevice {
            map.removeValue(forKey: deviceId)
            updated.metadata.wledTimerSlotsByDevice = map.isEmpty ? nil : map
        }
        if updated.targets.deviceIds.count == 1 {
            updated.metadata.wledTimerSlot = nil
        }
        return updateAutomationSyncMetadata(
            updated,
            deviceId: deviceId,
            state: .notSynced,
            error: "Timer slot missing on device",
            syncedAt: nil
        )
    }

    private struct ManagedTransitionPlaylistAsset {
        let playlistId: Int
        let stepPresetIds: [Int]
    }

    private func fetchPlaylistStepPresetIds(
        playlistId: Int,
        device: WLEDDevice
    ) async -> [Int] {
        do {
            let playlists = try await apiService.fetchPlaylists(for: device)
            guard let playlist = playlists.first(where: { $0.id == playlistId }) else {
                return []
            }
            return Array(Set(playlist.presets.filter { (1...250).contains($0) })).sorted()
        } catch {
            logger.warning("Failed to fetch playlist steps for cleanup: device=\(device.id, privacy: .public) playlist=\(playlistId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func managedPlaylistClaimedByAnotherAutomation(
        _ playlistId: Int,
        deviceId: String,
        excluding automationId: UUID
    ) -> Bool {
        automations.contains { record in
            guard record.id != automationId else { return false }
            let mappedId = record.metadata.wledPlaylistIdsByDevice?[deviceId] ?? record.metadata.wledPlaylistId
            guard mappedId == playlistId else { return false }
            return record.metadata.managedPlaylistSignature(for: deviceId) != nil
        }
    }

    private func managedPresetClaimedByAnotherAutomation(
        _ presetId: Int,
        deviceId: String,
        excluding automationId: UUID
    ) -> Bool {
        automations.contains { record in
            guard record.id != automationId else { return false }
            let mappedId = record.metadata.wledPresetIdsByDevice?[deviceId]
            guard mappedId == presetId else { return false }
            return record.metadata.managedPresetSignature(for: deviceId) != nil
        }
    }

    private func managedStepPresetClaimedByAnotherAutomation(
        _ presetId: Int,
        deviceId: String,
        excluding automationId: UUID
    ) -> Bool {
        automations.contains { record in
            guard record.id != automationId else { return false }
            guard let stepPresetIds = record.metadata.managedStepPresetIds(for: deviceId) else { return false }
            return stepPresetIds.contains(presetId)
        }
    }

    private func ensureAutomationTransitionPlaylist(
        for automation: Automation,
        device: WLEDDevice,
        payload: TransitionActionPayload
    ) async -> ManagedTransitionPlaylistAsset? {
        let desiredSignature = transitionPayloadSignature(payload)
        let storedSignature = automation.metadata.managedPlaylistSignature(for: device.id)
        let previousManagedPlaylistId = storedPlaylistId(for: automation, deviceId: device.id)
        let previousManagedStepPresetIds = Set(storedManagedTransitionStepPresetIds(for: automation, deviceId: device.id))
        if let existing = storedPlaylistId(for: automation, deviceId: device.id) {
            if managedPlaylistClaimedByAnotherAutomation(existing, deviceId: device.id, excluding: automation.id) {
                logger.warning("Automation transition playlist is claimed by another automation, rebuilding: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) playlist=\(existing)")
            } else if isPlaylistQueuedForDelete(existing, deviceId: device.id) {
                logger.warning("Automation transition playlist queued for delete, rebuilding: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) playlist=\(existing)")
            } else if storedSignature == desiredSignature,
                      await playlistExistsOnDevice(existing, device: device) {
                let storedStepIds = storedManagedTransitionStepPresetIds(for: automation, deviceId: device.id)
                if !storedStepIds.isEmpty {
                    return ManagedTransitionPlaylistAsset(
                        playlistId: existing,
                        stepPresetIds: storedStepIds
                    )
                }
                let fetchedStepIds = await fetchPlaylistStepPresetIds(playlistId: existing, device: device)
                return ManagedTransitionPlaylistAsset(
                    playlistId: existing,
                    stepPresetIds: fetchedStepIds
                )
            } else if storedSignature != desiredSignature {
                logger.info("Automation transition playlist signature changed; rebuilding: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public)")
            } else {
                logger.warning("Automation transition playlist missing on device, rebuilding: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) playlist=\(existing)")
            }
        }

        let label = "Automation \(automation.name)"
        if let playlist = await viewModel.createTransitionPlaylist(
            device: device,
            from: payload.startGradient,
            to: payload.endGradient,
            durationSeconds: payload.durationSeconds,
            startBrightness: payload.startBrightness,
            endBrightness: payload.endBrightness,
            persist: true,
            label: label
        ) {
            DeviceCleanupManager.shared.removeIds(type: .playlist, deviceId: device.id, ids: [playlist.playlistId])
            DeviceCleanupManager.shared.removeIds(type: .preset, deviceId: device.id, ids: playlist.stepPresetIds)

            if let previousManagedPlaylistId,
               previousManagedPlaylistId != playlist.playlistId,
               !managedPlaylistClaimedByAnotherAutomation(
                    previousManagedPlaylistId,
                    deviceId: device.id,
                    excluding: automation.id
               ) {
                enqueueDeferredManagedAssetCleanup(
                    type: .playlist,
                    device: device,
                    ids: [previousManagedPlaylistId],
                    delay: managedAssetDeferredCleanupDelaySeconds,
                    reason: "managed_transition_replaced"
                )
            }

            let staleStepPresetIds = previousManagedStepPresetIds
                .subtracting(Set(playlist.stepPresetIds))
                .filter {
                    !managedStepPresetClaimedByAnotherAutomation(
                        $0,
                        deviceId: device.id,
                        excluding: automation.id
                    )
                }
            if !staleStepPresetIds.isEmpty {
                enqueueDeferredManagedAssetCleanup(
                    type: .preset,
                    device: device,
                    ids: Array(staleStepPresetIds).sorted(),
                    delay: managedAssetDeferredCleanupDelaySeconds,
                    reason: "managed_transition_replaced"
                )
            }

            return ManagedTransitionPlaylistAsset(
                playlistId: playlist.playlistId,
                stepPresetIds: playlist.stepPresetIds
            )
        }
        return nil
    }

    private func presetExistsOnDevice(_ presetId: Int, device: WLEDDevice) async -> Bool {
        do {
            let presets = try await apiService.fetchPresets(for: device)
            return presets.contains(where: { $0.id == presetId })
        } catch {
            logger.error("Failed to verify preset \(presetId) on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func playlistExistsOnDevice(_ playlistId: Int, device: WLEDDevice) async -> Bool {
        do {
            let playlists = try await apiService.fetchPlaylists(for: device)
            return playlists.contains(where: { $0.id == playlistId })
        } catch {
            logger.error("Failed to verify playlist \(playlistId) on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func isPresetQueuedForDelete(_ presetId: Int, deviceId: String) -> Bool {
        DeviceCleanupManager.shared.hasActiveDelete(type: .preset, deviceId: deviceId, id: presetId)
    }

    private func isPlaylistQueuedForDelete(_ playlistId: Int, deviceId: String) -> Bool {
        DeviceCleanupManager.shared.hasActiveDelete(type: .playlist, deviceId: deviceId, id: playlistId)
    }

    private func hasAutomationCleanupDebt(deviceId: String) -> Bool {
        DeviceCleanupManager.shared.hasPendingDeletes(
            source: .automation,
            deviceId: deviceId
        )
        || DeviceCleanupManager.shared.hasPendingPresetStoreDeletes(deviceId: deviceId)
        || DeviceCleanupManager.shared.isDeleteLeaseActive(deviceId: deviceId)
    }

    private func canonicalJSONSignature<T: Encodable>(for value: T) -> String? {
        do {
            let encoded = try JSONEncoder().encode(value)
            let object = try JSONSerialization.jsonObject(with: encoded, options: [])
            let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: canonical, encoding: .utf8)
        } catch {
            logger.error("Failed to generate automation payload signature: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func transitionPayloadSignature(_ payload: TransitionActionPayload) -> String? {
        canonicalJSONSignature(for: payload)
    }

    private func presetSnapshotSignature(_ state: WLEDStateUpdate) -> String? {
        canonicalJSONSignature(for: state)
    }

    private enum OnDeviceActionTarget {
        case macro(id: Int, managed: Bool, signature: String?, managedStepPresetIds: [Int]?)
    }

    private struct WLEDTimerConfig {
        let hour: Int
        let minute: Int
        let days: Int
        let startMonth: Int?
        let startDay: Int?
        let endMonth: Int?
        let endDay: Int?
        let preferredSlot: Int?
        let allowedSlots: Set<Int>
    }

    private func availablePresetId(excluding used: Set<Int>) -> Int? {
        for id in stride(from: maxWLEDPresetSlots, through: 1, by: -1) {
            if !used.contains(id) {
                return id
            }
        }
        return nil
    }

    private func isTransientPresetStoreWriteError(_ error: Error) -> Bool {
        guard let apiError = error as? WLEDAPIError else {
            let message = error.localizedDescription.lowercased()
            return message.contains("timed out")
                || message.contains("timeout")
                || message.contains("service unavailable")
                || message.contains("503")
                || message.contains("network")
        }
        switch apiError {
        case .timeout, .networkError, .deviceBusy, .deviceOffline, .deviceUnreachable:
            return true
        case .httpError(let statusCode):
            return statusCode == 429 || statusCode >= 500
        default:
            return false
        }
    }

    private func savePresetWithRetry(_ request: WLEDPresetSaveRequest, device: WLEDDevice) async -> Bool {
        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            do {
                try await apiService.savePreset(request, to: device)
                return true
            } catch {
                logger.error("Automation preset save failed (attempt \(attempt)) for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                guard attempt < maxAttempts, isTransientPresetStoreWriteError(error) else { return false }
                let backoffSeconds = min(2.5, 0.45 * Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            }
        }
        return false
    }

    private func requiresManagedAssetRefresh(
        for automation: Automation,
        device: WLEDDevice
    ) -> Bool {
        switch automation.action {
        case .transition(let payload):
            if let transitionPresetId = payload.presetId,
               let sourcePreset = presetsStore.transitionPreset(id: transitionPresetId),
               sourcePreset.deviceId == device.id,
               sourcePreset.wledSyncState == .synced,
               let playlistId = sourcePreset.wledPlaylistId,
               (1...250).contains(playlistId),
               !isPlaylistQueuedForDelete(playlistId, deviceId: device.id) {
                let hasStaleManagedMarkers =
                    automation.metadata.managedPlaylistSignature(for: device.id) != nil
                    || !(automation.metadata.managedStepPresetIds(for: device.id) ?? []).isEmpty
                return storedPlaylistId(for: automation, deviceId: device.id) != playlistId || hasStaleManagedMarkers
            }
            if payload.presetId != nil {
                return true
            }

            let resolved = resolveTransitionPayload(payload, device: device)
            let desiredSignature = transitionPayloadSignature(resolved)
            guard desiredSignature == automation.metadata.managedPlaylistSignature(for: device.id),
                  let playlistId = storedPlaylistId(for: automation, deviceId: device.id),
                  (1...250).contains(playlistId),
                  !isPlaylistQueuedForDelete(playlistId, deviceId: device.id) else {
                return true
            }
            return false
        case .gradient, .directState, .effect, .scene:
            guard let state = automationPresetState(for: automation, device: device),
                  presetSnapshotSignature(state) == automation.metadata.managedPresetSignature(for: device.id),
                  let presetId = storedPresetId(for: automation, deviceId: device.id),
                  (1...250).contains(presetId),
                  !isPresetQueuedForDelete(presetId, deviceId: device.id) else {
                return true
            }
            return false
        case .preset, .playlist:
            return false
        }
    }

    private func ensureAutomationPresetSnapshot(
        for automation: Automation,
        device: WLEDDevice,
        state: WLEDStateUpdate,
        label: String
    ) async -> Int? {
        let desiredSignature = presetSnapshotSignature(state)
        let storedSignature = automation.metadata.managedPresetSignature(for: device.id)
        let existingStoredId = storedPresetId(for: automation, deviceId: device.id)
        if let existing = existingStoredId {
            if managedPresetClaimedByAnotherAutomation(existing, deviceId: device.id, excluding: automation.id) {
                logger.warning("Automation preset snapshot is claimed by another automation, recreating: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) preset=\(existing)")
            } else if isPresetQueuedForDelete(existing, deviceId: device.id) {
                logger.warning("Automation preset snapshot queued for delete, recreating: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) preset=\(existing)")
            } else if storedSignature == desiredSignature,
                      await presetExistsOnDevice(existing, device: device) {
                return existing
            } else if storedSignature != desiredSignature {
                logger.info("Automation preset snapshot signature changed; recreating: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public)")
            } else {
                logger.warning("Automation preset snapshot missing on device, recreating: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) preset=\(existing)")
            }
        }
        do {
            let existingPresets = try await apiService.fetchPresets(for: device)
            let remaining = max(0, maxWLEDPresetSlots - existingPresets.count)
            guard remaining > presetSlotReserve else {
                logger.error("Automation preset save blocked: remaining slots=\(remaining) for \(device.name, privacy: .public)")
                return nil
            }
            var excludedIds = Set(existingPresets.map { $0.id })
            excludedIds.formUnion(DeviceCleanupManager.shared.activeDeleteIds(type: .preset, deviceId: device.id))
            for record in automations where record.id != automation.id {
                guard let claimedPresetId = record.metadata.wledPresetIdsByDevice?[device.id] else { continue }
                guard record.metadata.managedPresetSignature(for: device.id) != nil else { continue }
                excludedIds.insert(claimedPresetId)
            }
            let presetId: Int
            if let existingStoredId,
               (1...maxWLEDPresetSlots).contains(existingStoredId),
               !excludedIds.contains(existingStoredId),
               !managedPresetClaimedByAnotherAutomation(existingStoredId, deviceId: device.id, excluding: automation.id) {
                presetId = existingStoredId
            } else if let available = availablePresetId(excluding: excludedIds) {
                presetId = available
            } else {
                logger.error("Automation preset save failed: no available preset IDs for \(device.name, privacy: .public)")
                return nil
            }
            let request = WLEDPresetSaveRequest(
                id: presetId,
                name: label,
                quickLoad: nil,
                state: state,
                includeBrightness: true,
                saveSegmentBounds: false,
                selectedSegmentsOnly: false
            )
            guard await savePresetWithRetry(request, device: device) else {
                return nil
            }
            DeviceCleanupManager.shared.removeIds(type: .preset, deviceId: device.id, ids: [presetId])
            return presetId
        } catch {
            logger.error("Automation preset save failed for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func automationPresetState(for automation: Automation, device: WLEDDevice) -> WLEDStateUpdate? {
        switch automation.action {
        case .gradient(let payload):
            if !payload.powerOn || payload.brightness <= 0 {
                return WLEDStateUpdate(on: false, bri: 0)
            }
            let gradient = resolveGradientPayload(payload, device: device)
            return viewModel.presetStateForGradient(
                device: device,
                gradient: gradient,
                brightness: payload.brightness,
                temperature: payload.temperature,
                whiteLevel: payload.whiteLevel,
                includeSegmentBounds: false
            )
        case .directState(let payload):
            if payload.brightness <= 0 {
                return WLEDStateUpdate(on: false, bri: 0)
            }
            let stops = [
                GradientStop(position: 0.0, hexColor: payload.colorHex),
                GradientStop(position: 1.0, hexColor: payload.colorHex)
            ]
            let gradient = LEDGradient(stops: stops)
            return viewModel.presetStateForGradient(
                device: device,
                gradient: gradient,
                brightness: payload.brightness,
                temperature: payload.temperature,
                whiteLevel: payload.whiteLevel,
                includeSegmentBounds: false
            )
        case .effect(let payload):
            let segment = SegmentUpdate(
                id: 0,
                bri: payload.brightness,
                fx: payload.effectId,
                sx: payload.speed,
                ix: payload.intensity,
                pal: payload.paletteId
            )
            return WLEDStateUpdate(
                on: true,
                bri: payload.brightness,
                seg: [segment]
            )
        case .scene(let payload):
            let scenes = scenesStore.scenes
            guard let scene = scenes.first(where: { $0.id == payload.sceneId && $0.deviceId == device.id }) else {
                return nil
            }
            let gradient = LEDGradient(stops: scene.primaryStops)
            var state = viewModel.presetStateForGradient(
                device: device,
                gradient: gradient,
                brightness: scene.brightness,
                temperature: nil,
                whiteLevel: nil,
                includeSegmentBounds: false
            )
            if scene.effectsEnabled, let effectId = scene.effectId, let segments = state.seg {
                let updatedSegments = segments.map { segment in
                    SegmentUpdate(
                        id: segment.id,
                        start: segment.start,
                        stop: segment.stop,
                        len: segment.len,
                        on: segment.on,
                        bri: segment.bri,
                        col: segment.col,
                        fx: effectId,
                        sx: scene.speed,
                        ix: scene.intensity,
                        pal: scene.paletteId
                    )
                }
                state = WLEDStateUpdate(
                    on: state.on,
                    bri: state.bri,
                    seg: updatedSegments
                )
            }
            return state
        case .preset, .playlist, .transition:
            return nil
        }
    }

    private func resolveOnDeviceActionTarget(
        for automation: Automation,
        device: WLEDDevice
    ) async -> OnDeviceActionTarget? {
        switch automation.action {
        case .preset(let payload):
            let targetId = payload.presetId
            guard (1...250).contains(targetId) else { return nil }
            guard !isPresetQueuedForDelete(targetId, deviceId: device.id) else { return nil }
            return .macro(id: targetId, managed: false, signature: nil, managedStepPresetIds: nil)
        case .playlist(let payload):
            let targetId = payload.playlistId
            guard (1...250).contains(targetId) else { return nil }
            guard !isPlaylistQueuedForDelete(targetId, deviceId: device.id) else { return nil }
            return .macro(id: targetId, managed: false, signature: nil, managedStepPresetIds: nil)
        case .transition(let payload):
            if let transitionPresetId = payload.presetId,
               let sourcePreset = presetsStore.transitionPreset(id: transitionPresetId),
               sourcePreset.deviceId == device.id {
                if sourcePreset.wledSyncState == .synced,
                   let playlistId = sourcePreset.wledPlaylistId,
                   (1...250).contains(playlistId),
                   !isPlaylistQueuedForDelete(playlistId, deviceId: device.id) {
                    // Reuse the existing saved transition playlist directly.
                    // This avoids re-generating heavy managed assets during automation sync.
                    return .macro(id: playlistId, managed: false, signature: nil, managedStepPresetIds: nil)
                }
                logger.warning("Automation transition preset is not ready on device yet: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) preset=\(transitionPresetId.uuidString, privacy: .public) state=\(sourcePreset.wledSyncState.rawValue, privacy: .public)")
                return nil
            }
            let resolved = resolveTransitionPayload(payload, device: device)
            if let managedPlaylist = await ensureAutomationTransitionPlaylist(for: automation, device: device, payload: resolved) {
                return .macro(
                    id: managedPlaylist.playlistId,
                    managed: true,
                    signature: transitionPayloadSignature(resolved),
                    managedStepPresetIds: managedPlaylist.stepPresetIds
                )
            }
            return nil
        case .gradient, .directState, .effect, .scene:
            guard let state = automationPresetState(for: automation, device: device) else {
                return nil
            }
            let label = "Automation \(automation.name)"
            if let presetId = await ensureAutomationPresetSnapshot(for: automation, device: device, state: state, label: label) {
                return .macro(
                    id: presetId,
                    managed: true,
                    signature: presetSnapshotSignature(state),
                    managedStepPresetIds: nil
                )
            }
            return nil
        }
    }

    private func syncOnDeviceScheduleIfNeeded(
        for automation: Automation,
        deviceFilter: Set<String>? = nil
    ) async {
        guard automation.metadata.runOnDevice else { return }
        guard automations.contains(where: { $0.id == automation.id }) else { return }
        guard !deletingAutomationIds.contains(automation.id) else {
            logger.info("automation.sync.aborted_delete_in_progress automation=\(automation.id.uuidString, privacy: .public)")
            return
        }
        if onDeviceSyncInFlightAutomationIds.contains(automation.id) {
            onDeviceSyncReplayAutomationIds.insert(automation.id)
            return
        }
        onDeviceSyncInFlightAutomationIds.insert(automation.id)
        defer {
            onDeviceSyncInFlightAutomationIds.remove(automation.id)
            if onDeviceSyncReplayAutomationIds.remove(automation.id) != nil,
               let latest = automations.first(where: { $0.id == automation.id }),
               latest.metadata.runOnDevice {
                Task { @MainActor [weak self] in
                    await self?.syncOnDeviceScheduleIfNeeded(
                        for: latest,
                        deviceFilter: deviceFilter
                    )
                }
            }
        }
        let devices = viewModel.devices.filter {
            automation.targets.deviceIds.contains($0.id)
                && (deviceFilter == nil || deviceFilter?.contains($0.id) == true)
        }
        guard !devices.isEmpty else {
            logger.info("On-device schedule skipped: no target devices for \(automation.name, privacy: .public)")
            return
        }

        var updated = automation
        for device in devices {
            guard let latest = automations.first(where: { $0.id == updated.id }) else {
                logger.info("automation.sync.aborted_deleted automation=\(updated.id.uuidString, privacy: .public)")
                return
            }
            guard !deletingAutomationIds.contains(latest.id) else {
                logger.info(
                    "automation.sync.aborted_delete_in_progress automation=\(latest.id.uuidString, privacy: .public) device=\(device.id, privacy: .public)"
                )
                return
            }
            guard latest.metadata.runOnDevice else {
                logger.info("automation.sync.aborted_not_run_on_device automation=\(updated.id.uuidString, privacy: .public)")
                return
            }
            updated = latest
            await acquireOnDeviceSyncDeviceLock(for: device.id)
            defer { releaseOnDeviceSyncDeviceLock(for: device.id) }
            defer { commitAutomationSyncSnapshot(updated) }

            let previousSyncState = updated.metadata.syncState(for: device.id)
            let previousTimerSlot = storedTimerSlot(for: updated, deviceId: device.id)
            let previousSyncedAt = updated.metadata.lastSyncAt(for: device.id)
            updated = updateAutomationSyncMetadata(
                updated,
                deviceId: device.id,
                state: .syncing,
                error: nil,
                syncedAt: nil
            )
            commitAutomationSyncSnapshot(updated)
            if hasAutomationCleanupDebt(deviceId: device.id) {
                if let preservedSlot = previousTimerSlot {
                    updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                }
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .syncing,
                    error: "Cleanup pending, retrying",
                    syncedAt: nil
                )
                logger.info("automation.sync.defer transient device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=cleanup_pending_delete_queue")
                continue
            }
            if let solarIssue = await validateSolarConfigurationIfNeeded(for: updated.trigger, device: device) {
                updated = clearTimerSlotMetadata(updated, deviceId: device.id)
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .notSynced,
                    error: solarIssue,
                    syncedAt: nil
                )
                logger.warning("automation.sync.not_ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=\(solarIssue, privacy: .public)")
                logger.error("On-device schedule failed: \(solarIssue, privacy: .public) for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                continue
            }
            guard let timeConfig = await wledTimerConfig(for: updated, device: device, referenceDate: Date()) else {
                updated = clearTimerSlotMetadata(updated, deviceId: device.id)
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .notSynced,
                    error: "Could not resolve timer configuration",
                    syncedAt: nil
                )
                logger.warning("automation.sync.not_ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=could_not_resolve_timer_configuration")
                logger.error("On-device schedule failed: time config unavailable for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                continue
            }
            let timerSlotResolution = await ensureTimerSlot(
                for: updated,
                device: device,
                preferredSlot: timeConfig.preferredSlot,
                allowedSlots: timeConfig.allowedSlots
            )
            var timerSlot: Int
            switch timerSlotResolution {
            case .slot(let resolvedSlot):
                timerSlot = resolvedSlot
            case .unavailable:
                await logOccupiedTimerSlots(
                    device: device,
                    allowedSlots: timeConfig.allowedSlots,
                    automationId: automation.id
                )
                if let recoveredSlot = await recoverMatchingTimerSlotWhenUnavailable(
                    automation: updated,
                    device: device,
                    timeConfig: timeConfig
                ) {
                    timerSlot = recoveredSlot
                    logger.info("automation.slot.selected device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot) reason=existing_match_unavailable_recovery")
                    break
                }
                if previousSyncState == .synced, let preservedSlot = previousTimerSlot {
                    updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                    updated = updateAutomationSyncMetadata(
                        updated,
                        deviceId: device.id,
                        state: .synced,
                        error: nil,
                        syncedAt: previousSyncedAt ?? Date()
                    )
                    logger.warning("On-device schedule timer-slot lookup unavailable; preserving ready state for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                    continue
                }
                logger.error("On-device schedule failed: no timer slots for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                updated = clearTimerSlotMetadata(updated, deviceId: device.id)
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .notSynced,
                    error: "No available timer slots on device",
                    syncedAt: nil
                )
                logger.warning("automation.sync.not_ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=no_available_timer_slots")
                continue
            case .unresolved(let reason):
                if previousSyncState == .synced, let preservedSlot = previousTimerSlot {
                    updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                    updated = updateAutomationSyncMetadata(
                        updated,
                        deviceId: device.id,
                        state: .synced,
                        error: nil,
                        syncedAt: previousSyncedAt ?? Date()
                    )
                    logger.warning("On-device schedule timer-slot lookup transiently unavailable; preserving ready state for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(reason, privacy: .public)")
                    continue
                }
                if let preservedSlot = previousTimerSlot {
                    updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                }
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .syncing,
                    error: "Device temporarily unreachable, retrying",
                    syncedAt: nil
                )
                logger.info("automation.sync.defer transient device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=\(reason, privacy: .public)")
                logger.warning("On-device schedule deferred due to transient timer-slot lookup failure for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(reason, privacy: .public)")
                continue
            }
            let timerSlotWasReclaimable = DeviceCleanupManager.shared.hasActiveDelete(
                type: .timer,
                deviceId: device.id,
                id: timerSlot
            )
            if timerSlotWasReclaimable, previousSyncState != .synced {
                await disarmTimerSlotFailClosed(
                    slot: timerSlot,
                    device: device,
                    automation: automation,
                    reason: "reclaimable_slot_pre_disarm"
                )
            }

            let requiresManagedAssetGeneration: Bool
            switch updated.action {
            case .preset, .playlist:
                requiresManagedAssetGeneration = false
            case .transition(let payload):
                requiresManagedAssetGeneration = payload.presetId == nil
            case .gradient, .effect, .scene, .directState:
                requiresManagedAssetGeneration = true
            }

            if requiresManagedAssetGeneration {
                let needsManagedAssetRefresh = requiresManagedAssetRefresh(for: updated, device: device)
                switch await viewModel.waitForHeavyOpQuiescence(deviceId: device.id, timeout: 8.0) {
                case .ready:
                    break
                case .timedOut(let reason):
                    if previousSyncState == .synced,
                       let preservedSlot = previousTimerSlot,
                       !needsManagedAssetRefresh {
                        updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                        updated = updateAutomationSyncMetadata(
                            updated,
                            deviceId: device.id,
                            state: .synced,
                            error: nil,
                            syncedAt: previousSyncedAt ?? Date()
                        )
                        logger.warning("On-device schedule managed-asset wait timed out; preserving ready state for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(reason, privacy: .public)")
                    } else {
                        if let preservedSlot = previousTimerSlot {
                            updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                        }
                        updated = updateAutomationSyncMetadata(
                            updated,
                            deviceId: device.id,
                            state: .syncing,
                            error: "Device busy, retrying",
                            syncedAt: nil
                        )
                        if timerSlotWasReclaimable, previousSyncState != .synced {
                            await disarmTimerSlotFailClosed(
                                slot: timerSlot,
                                device: device,
                                automation: automation,
                                reason: "managed_asset_wait_timeout"
                            )
                        }
                        logger.info("automation.sync.defer transient device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=device_busy_retrying")
                        logger.warning("On-device schedule deferred due to managed-asset wait timeout for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(reason, privacy: .public)")
                    }
                    continue
                }
            }

            var metadataCandidate = updated
            let targetId: Int
            if metadataCandidate.enabled {
                guard let actionTarget = await resolveOnDeviceActionTarget(for: metadataCandidate, device: device) else {
                    let shouldDeferActionTargetFailure: Bool
                    switch metadataCandidate.action {
                    case .transition, .gradient, .directState, .effect, .scene:
                        shouldDeferActionTargetFailure = true
                    case .preset, .playlist:
                        shouldDeferActionTargetFailure = false
                    }

                    if shouldDeferActionTargetFailure {
                        if previousSyncState == .synced,
                           let preservedSlot = previousTimerSlot,
                           !requiresManagedAssetRefresh(for: updated, device: device) {
                            updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                            updated = updateAutomationSyncMetadata(
                                updated,
                                deviceId: device.id,
                                state: .synced,
                                error: nil,
                                syncedAt: previousSyncedAt ?? Date()
                            )
                            logger.warning("On-device schedule action target transiently unavailable; preserving ready state for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                        } else {
                            if let preservedSlot = previousTimerSlot {
                                updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                            }
                            updated = updateAutomationSyncMetadata(
                                updated,
                                deviceId: device.id,
                                state: .syncing,
                                error: "Preparing device assets, retrying",
                                syncedAt: nil
                            )
                            if timerSlotWasReclaimable, previousSyncState != .synced {
                                await disarmTimerSlotFailClosed(
                                    slot: timerSlot,
                                    device: device,
                                    automation: automation,
                                    reason: "action_target_unavailable"
                                )
                            }
                            logger.info("automation.sync.defer transient device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=preparing_device_assets")
                            logger.warning("On-device schedule deferred: action target unavailable for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                        }
                    } else {
                        logger.error("On-device schedule failed: no action target for \(automation.name, privacy: .public) on \(device.name, privacy: .public)")
                        updated = clearTimerSlotMetadata(updated, deviceId: device.id)
                        updated = updateAutomationSyncMetadata(
                            updated,
                            deviceId: device.id,
                            state: .notSynced,
                            error: "Macro target missing on device",
                            syncedAt: nil
                        )
                        logger.warning("automation.sync.not_ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=macro_target_missing")
                    }
                    continue
                }
                switch actionTarget {
                case .macro(let macroId, let managed, let signature, let managedStepPresetIds):
                    targetId = macroId
                    if managed {
                        switch metadataCandidate.action {
                        case .transition, .playlist:
                            metadataCandidate = updateAutomationMetadata(
                                metadataCandidate,
                                deviceId: device.id,
                                playlistId: macroId,
                                playlistStepPresetIds: managedStepPresetIds,
                                managedPlaylistSignature: signature
                            )
                        default:
                            metadataCandidate = updateAutomationMetadata(
                                metadataCandidate,
                                deviceId: device.id,
                                presetId: macroId,
                                managedPresetSignature: signature
                            )
                        }
                    } else if case .transition = metadataCandidate.action {
                        metadataCandidate = updateAutomationMetadata(
                            metadataCandidate,
                            deviceId: device.id,
                            playlistId: macroId,
                            playlistStepPresetIds: nil,
                            managedPlaylistSignature: nil
                        )
                    }
                }
            } else {
                // Disabled schedules should not perform heavy macro asset generation.
                targetId = expectedMacroId(for: metadataCandidate, deviceId: device.id) ?? 0
            }
            updated = metadataCandidate
            let expectedTimerSignature = timerSignature(
                enabled: updated.enabled,
                hour: timeConfig.hour,
                minute: timeConfig.minute,
                days: timeConfig.days,
                macroId: targetId,
                startMonth: timeConfig.startMonth,
                startDay: timeConfig.startDay,
                endMonth: timeConfig.endMonth,
                endDay: timeConfig.endDay
            )
            let allowExistingSlotAdoption: Bool = {
                previousTimerSlot == nil
            }()
            if allowExistingSlotAdoption {
                let reservedSlots = reservedTimerSlots(excluding: automation, deviceId: device.id)
                if let adoptedSlot = await findMatchingTimerSlotOnDevice(
                    device: device,
                    allowedSlots: timeConfig.allowedSlots,
                    reservedSlots: reservedSlots,
                    expectedSignature: expectedTimerSignature
                ), adoptedSlot != timerSlot {
                    timerSlot = adoptedSlot
                    logger.info("automation.slot.selected device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot) reason=existing_match")
                }
            }
            let signatureKey = timerSignatureKey(automationId: updated.id, deviceId: device.id)

            let updatePayload = WLEDTimerUpdate(
                id: timerSlot,
                enabled: updated.enabled,
                hour: timeConfig.hour,
                minute: timeConfig.minute,
                days: timeConfig.days,
                macroId: targetId,
                startMonth: timeConfig.startMonth,
                startDay: timeConfig.startDay,
                endMonth: timeConfig.endMonth,
                endDay: timeConfig.endDay
            )

            do {
                guard automations.contains(where: { $0.id == updated.id }) else {
                    logger.info("automation.sync.aborted_deleted_before_write automation=\(updated.id.uuidString, privacy: .public) device=\(device.id, privacy: .public)")
                    return
                }
                // Reclaim the slot before writing so a queued stale delete cannot disable
                // this freshly assigned automation timer afterwards.
                DeviceCleanupManager.shared.removeIds(type: .timer, deviceId: device.id, ids: [timerSlot])
                // Fail-closed arming path: for new/unsynced schedules, write disabled first
                // and only arm after final verification succeeds.
                if updated.enabled && previousSyncState != .synced {
                    let stagedPayload = WLEDTimerUpdate(
                        id: timerSlot,
                        enabled: false,
                        hour: nil,
                        minute: nil,
                        days: nil,
                        macroId: nil,
                        startMonth: nil,
                        startDay: nil,
                        endMonth: nil,
                        endDay: nil
                    )
                    try await apiService.updateTimer(stagedPayload, on: device)
                    let stagedVerified = try await verifyTimerWithRetry(
                        stagedPayload,
                        on: device,
                        attempts: 3,
                        initialDelayMs: 160
                    )
                    if !stagedVerified {
                        logger.warning(
                            "automation.timer.stage_verify_unconfirmed device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot)"
                        )
                    }
                }
                try await apiService.updateTimer(updatePayload, on: device)
                let verified = try await verifyTimerWithRetry(
                    updatePayload,
                    on: device,
                    attempts: 4,
                    initialDelayMs: 200
                )
                guard verified else {
                    if updated.enabled && previousSyncState != .synced {
                        await disarmTimerSlotFailClosed(
                            slot: timerSlot,
                            device: device,
                            automation: updated,
                            reason: "timer_verification_mismatch"
                        )
                    }
                    lastKnownGoodTimerSignatureByAutomationDevice.removeValue(forKey: signatureKey)
                    // Keep a sticky slot assignment for retries to avoid slot-hopping
                    // when read-after-write verification is transiently unstable.
                    let stickySlot = previousTimerSlot ?? timerSlot
                    updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: stickySlot)
                    updated = updateAutomationSyncMetadata(
                        updated,
                        deviceId: device.id,
                        state: .notSynced,
                        error: "Timer verification mismatch after write",
                        syncedAt: nil
                    )
                    logger.warning("automation.sync.not_ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=timer_verification_mismatch")
                    logger.error("On-device schedule failed verification: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) slot=\(timerSlot)")
                    continue
                }
                updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: timerSlot)
                lastKnownGoodTimerSignatureByAutomationDevice[signatureKey] = expectedTimerSignature
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .synced,
                    error: nil,
                    syncedAt: Date()
                )
                logger.info("automation.sync.ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot)")
                await disableObsoleteTimerSlotIfNeeded(
                    previousSlot: previousTimerSlot,
                    currentSlot: timerSlot,
                    automationId: updated.id,
                    device: device
                )
                await disableDuplicateTimerSlotsIfNeeded(
                    device: device,
                    automationId: updated.id,
                    currentSlot: timerSlot,
                    allowedSlots: timeConfig.allowedSlots,
                    expectedSignature: expectedTimerSignature
                )
                logger.info("On-device schedule updated+verified: automation=\(automation.name, privacy: .public) device=\(device.name, privacy: .public) slot=\(timerSlot)")
            } catch {
                if previousSyncState == .synced && isTransientOnDeviceSyncError(error) {
                    let knownSignature = lastKnownGoodTimerSignatureByAutomationDevice[signatureKey] ?? expectedTimerSignature
                    let slotToVerify = previousTimerSlot ?? timerSlot
                    let proofMatches = await doesTimerSlotMatchSignature(
                        device: device,
                        slot: slotToVerify,
                        expectedSignature: knownSignature
                    )
                    if proofMatches {
                        if let preservedSlot = previousTimerSlot {
                            updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: preservedSlot)
                        }
                        updated = updateAutomationSyncMetadata(
                            updated,
                            deviceId: device.id,
                            state: .synced,
                            error: nil,
                            syncedAt: previousSyncedAt ?? Date()
                        )
                        logger.warning("On-device schedule transient sync error; preserving ready state with signature proof for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        continue
                    }
                    logger.warning("On-device schedule transient sync error without signature proof; marking not ready for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                if isTransientOnDeviceSyncError(error) {
                    if updated.enabled && previousSyncState != .synced {
                        await disarmTimerSlotFailClosed(
                            slot: timerSlot,
                            device: device,
                            automation: updated,
                            reason: "transient_sync_error"
                        )
                    }
                    let stickySlot = previousTimerSlot ?? timerSlot
                    updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: stickySlot)
                    updated = updateAutomationSyncMetadata(
                        updated,
                        deviceId: device.id,
                        state: .syncing,
                        error: "Device temporarily unreachable, retrying",
                        syncedAt: nil
                    )
                    logger.info("automation.sync.defer transient device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=device_temporarily_unreachable")
                    logger.warning("On-device schedule deferred due to transient sync error for \(automation.name, privacy: .public) on \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }
                if updated.enabled && previousSyncState != .synced {
                    await disarmTimerSlotFailClosed(
                        slot: timerSlot,
                        device: device,
                        automation: updated,
                        reason: "non_transient_sync_error"
                    )
                }
                lastKnownGoodTimerSignatureByAutomationDevice.removeValue(forKey: signatureKey)
                let stickySlot = previousTimerSlot ?? timerSlot
                updated = updateAutomationMetadata(updated, deviceId: device.id, timerSlot: stickySlot)
                updated = updateAutomationSyncMetadata(
                    updated,
                    deviceId: device.id,
                    state: .notSynced,
                    error: error.localizedDescription,
                    syncedAt: nil
                )
                logger.warning("automation.sync.not_ready device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) reason=\(error.localizedDescription, privacy: .public)")
                logger.error("On-device schedule failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if updated != automation {
            commitAutomationSyncSnapshot(updated)
        }
    }

    private func disableDuplicateTimerSlotsIfNeeded(
        device: WLEDDevice,
        automationId: UUID,
        currentSlot: Int,
        allowedSlots: Set<Int>,
        expectedSignature: String
    ) async {
        do {
            let timers = try await apiService.fetchTimers(for: device)
            let duplicateSlots = timers
                .filter { timer in
                    timer.id != currentSlot
                        && allowedSlots.contains(timer.id)
                        && timerSignature(for: timer) == expectedSignature
                }
                .map(\.id)
                .sorted()

            guard !duplicateSlots.isEmpty else { return }

            for slot in duplicateSlots {
                guard !timerSlotClaimedByAnotherAutomation(slot, deviceId: device.id, excluding: automationId) else {
                    continue
                }
                do {
                    let disabled = try await apiService.disableTimer(slot: slot, device: device)
                    if disabled {
                        logger.info("automation.slot.duplicate_disabled device=\(device.id, privacy: .public) automation=\(automationId.uuidString, privacy: .public) slot=\(slot) keeper=\(currentSlot)")
                    } else {
                        DeviceCleanupManager.shared.enqueue(
                            type: .timer,
                            deviceId: device.id,
                            ids: [slot],
                            source: .automation
                        )
                        logger.warning("automation.slot.duplicate_queue_cleanup device=\(device.id, privacy: .public) automation=\(automationId.uuidString, privacy: .public) slot=\(slot) keeper=\(currentSlot)")
                    }
                } catch {
                    DeviceCleanupManager.shared.enqueue(
                        type: .timer,
                        deviceId: device.id,
                        ids: [slot],
                        source: .automation
                    )
                    logger.warning("automation.slot.duplicate_disable_failed device=\(device.id, privacy: .public) automation=\(automationId.uuidString, privacy: .public) slot=\(slot) keeper=\(currentSlot) error=\(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.warning("automation.slot.duplicate_scan_failed device=\(device.id, privacy: .public) automation=\(automationId.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func findMatchingTimerSlotOnDevice(
        device: WLEDDevice,
        allowedSlots: Set<Int>,
        reservedSlots: Set<Int>,
        expectedSignature: String
    ) async -> Int? {
        do {
            let timers = try await apiService.fetchTimers(for: device)
            return timers
                .filter {
                    allowedSlots.contains($0.id)
                        && !reservedSlots.contains($0.id)
                        && timerSignature(for: $0) == expectedSignature
                }
                .map(\.id)
                .sorted()
                .first
        } catch {
            logger.warning("Could not adopt existing timer slot for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func recoverMatchingTimerSlotWhenUnavailable(
        automation: Automation,
        device: WLEDDevice,
        timeConfig: WLEDTimerConfig
    ) async -> Int? {
        guard let macroId = expectedMacroId(for: automation, deviceId: device.id) else {
            return nil
        }
        let expectedSignature = timerSignature(
            enabled: automation.enabled,
            hour: timeConfig.hour,
            minute: timeConfig.minute,
            days: timeConfig.days,
            macroId: macroId,
            startMonth: timeConfig.startMonth,
            startDay: timeConfig.startDay,
            endMonth: timeConfig.endMonth,
            endDay: timeConfig.endDay
        )
        let reservedSlots = reservedTimerSlots(excluding: automation, deviceId: device.id)
        return await findMatchingTimerSlotOnDevice(
            device: device,
            allowedSlots: timeConfig.allowedSlots,
            reservedSlots: reservedSlots,
            expectedSignature: expectedSignature
        )
    }

    private func logOccupiedTimerSlots(
        device: WLEDDevice,
        allowedSlots: Set<Int>,
        automationId: UUID
    ) async {
        do {
            let timers = try await apiService.fetchTimers(for: device)
            let occupied = timers
                .filter { allowedSlots.contains($0.id) && $0.macroId > 0 }
                .sorted { $0.id < $1.id }
                .map { timer in
                    "slot=\(timer.id):\(timer.hour):\(timer.minute):macro=\(timer.macroId):en=\(timer.enabled ? 1 : 0)"
                }
                .joined(separator: ",")
            logger.warning(
                "automation.slot.occupied device=\(device.id, privacy: .public) automation=\(automationId.uuidString, privacy: .public) allowed=\(Array(allowedSlots).sorted(), privacy: .public) occupied=\(occupied, privacy: .public)"
            )
        } catch {
            logger.warning(
                "automation.slot.occupied_lookup_failed device=\(device.id, privacy: .public) automation=\(automationId.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func commitAutomationSyncSnapshot(_ automation: Automation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        guard automations[index] != automation else { return }
        var records = automations
        records[index] = automation
        automations = records
        save()
        scheduleOnDeviceSyncRetryIfNeeded()
    }

    private func disarmTimerSlotFailClosed(
        slot: Int,
        device: WLEDDevice,
        automation: Automation,
        reason: String
    ) async {
        func enqueueFallbackCleanup(_ detail: String) {
            DeviceCleanupManager.shared.enqueue(
                type: .timer,
                deviceId: device.id,
                ids: [slot],
                source: .automation,
                verificationRequired: true,
                notBefore: Date().addingTimeInterval(0.8)
            )
            logger.warning(
                "automation.slot.disarm_queue_cleanup device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(slot) reason=\(reason, privacy: .public) detail=\(detail, privacy: .public)"
            )
        }

        do {
            let clearPayload = WLEDTimerUpdate(
                id: slot,
                enabled: false,
                hour: 0,
                minute: 0,
                days: 0x7F,
                macroId: 0,
                startMonth: nil,
                startDay: nil,
                endMonth: nil,
                endDay: nil
            )
            try await apiService.updateTimer(clearPayload, on: device)
            let cleared = try await verifyTimerWithRetry(
                clearPayload,
                on: device,
                attempts: 3,
                initialDelayMs: 120
            )
            if cleared {
                DeviceCleanupManager.shared.removeIds(type: .timer, deviceId: device.id, ids: [slot])
                logger.info("automation.slot.disarmed_cleared device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(slot) reason=\(reason, privacy: .public)")
            } else {
                do {
                    let disabled = try await apiService.disableTimer(slot: slot, device: device)
                    if disabled {
                        DeviceCleanupManager.shared.removeIds(type: .timer, deviceId: device.id, ids: [slot])
                        logger.warning("automation.slot.disarmed_without_clear device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(slot) reason=\(reason, privacy: .public)")
                    } else {
                        enqueueFallbackCleanup("disable_returned_false")
                        logger.warning("automation.slot.disarm_failed device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(slot) reason=\(reason, privacy: .public)")
                    }
                } catch {
                    enqueueFallbackCleanup("disable_error")
                    logger.warning("automation.slot.disarm_error device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(slot) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            enqueueFallbackCleanup("clear_update_or_verify_error")
            logger.warning("automation.slot.disarm_error device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(slot) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func acquireOnDeviceSyncDeviceLock(for deviceId: String) async {
        while onDeviceSyncInFlightDeviceIds.contains(deviceId) {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        onDeviceSyncInFlightDeviceIds.insert(deviceId)
    }

    private func releaseOnDeviceSyncDeviceLock(for deviceId: String) {
        onDeviceSyncInFlightDeviceIds.remove(deviceId)
    }

    private func isTransientOnDeviceSyncError(_ error: Error) -> Bool {
        if let apiError = error as? WLEDAPIError {
            switch apiError {
            case .timeout, .networkError, .deviceOffline, .deviceUnreachable, .deviceBusy, .decodingError:
                return true
            case .httpError(let statusCode):
                return statusCode >= 500 || statusCode == 429
            default:
                break
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .resourceUnavailable:
                return true
            default:
                break
            }
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("decode response")
            || message.contains("isn’t in the correct format")
            || message.contains("isn't in the correct format")
            || message.contains("request timed out")
            || message.contains("network error")
            || message.contains("cancelled") {
            return true
        }
        return false
    }

    private func playlistDurationSeconds(playlistId: Int, device: WLEDDevice) async -> Double? {
        if let cached = viewModel.playlists(for: device).first(where: { $0.id == playlistId }) {
            let total = cached.duration.reduce(0) { $0 + max(0, $1) }
            return total > 0 ? Double(total) / 10.0 : nil
        }
        do {
            let playlists = try await apiService.fetchPlaylists(for: device)
            if let playlist = playlists.first(where: { $0.id == playlistId }) {
                let total = playlist.duration.reduce(0) { $0 + max(0, $1) }
                return total > 0 ? Double(total) / 10.0 : nil
            }
        } catch {
            logger.error("Failed to fetch playlist duration for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func wledTimeAndDays(
        from trigger: AutomationTrigger,
        device: WLEDDevice
    ) async -> (hour: Int, minute: Int, days: Int)? {
        guard case .specificTime(let timeTrigger) = trigger else { return nil }
        let components = timeTrigger.time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else { return nil }

        // Convert schedule intent from trigger timezone into device timezone used by on-device timers.
        let sourceTimeZone = TimeZone(identifier: timeTrigger.timezoneIdentifier) ?? TimeZone.current
        let targetTimeZone = await wledSolarReference(for: device)?.timeZone ?? .current
        let sourceOffsetMinutes = sourceTimeZone.secondsFromGMT(for: Date()) / 60
        let targetOffsetMinutes = targetTimeZone.secondsFromGMT(for: Date()) / 60
        let deltaMinutes = targetOffsetMinutes - sourceOffsetMinutes

        var convertedMinutes = (hour * 60) + minute + deltaMinutes
        var dayShift = 0
        while convertedMinutes < 0 {
            convertedMinutes += 1440
            dayShift -= 1
        }
        while convertedMinutes >= 1440 {
            convertedMinutes -= 1440
            dayShift += 1
        }

        let sourceWeekdays = WeekdayMask.normalizeSunFirst(timeTrigger.weekdays)
        var shiftedWeekdays = Array(repeating: false, count: 7)
        for (index, enabled) in sourceWeekdays.enumerated() where enabled {
            let shifted = (index + dayShift % 7 + 7) % 7
            shiftedWeekdays[shifted] = true
        }

        let days = WeekdayMask.wledDow(fromSunFirst: shiftedWeekdays)
        let convertedHour = convertedMinutes / 60
        let convertedMinute = convertedMinutes % 60
        return (
            hour: max(0, min(23, convertedHour)),
            minute: max(0, min(59, convertedMinute)),
            days: days
        )
    }

    private struct TimerDateRange {
        let startMonth: Int?
        let startDay: Int?
        let endMonth: Int?
        let endDay: Int?
    }

    private func timerDateRange(for automation: Automation) -> TimerDateRange {
        let startMonth = sanitizeMonth(automation.metadata.onDeviceStartMonth)
        let startDay = sanitizeDay(automation.metadata.onDeviceStartDay)
        let endMonth = sanitizeMonth(automation.metadata.onDeviceEndMonth)
        let endDay = sanitizeDay(automation.metadata.onDeviceEndDay)

        // WLED start/end windows are valid only when both month+day are present.
        if startMonth != nil && startDay != nil && endMonth != nil && endDay != nil {
            return TimerDateRange(
                startMonth: startMonth,
                startDay: startDay,
                endMonth: endMonth,
                endDay: endDay
            )
        }
        return TimerDateRange(startMonth: nil, startDay: nil, endMonth: nil, endDay: nil)
    }

    private func sanitizeMonth(_ month: Int?) -> Int? {
        guard let month else { return nil }
        return (1...12).contains(month) ? month : nil
    }

    private func sanitizeDay(_ day: Int?) -> Int? {
        guard let day else { return nil }
        return (1...31).contains(day) ? day : nil
    }

    private func wledTimerConfig(
        for automation: Automation,
        device: WLEDDevice,
        referenceDate: Date
    ) async -> WLEDTimerConfig? {
        let dateRange = timerDateRange(for: automation)
        switch automation.trigger {
        case .specificTime(let timeTrigger):
            guard let config = await wledTimeAndDays(from: .specificTime(timeTrigger), device: device) else { return nil }
            return WLEDTimerConfig(
                hour: config.hour,
                minute: config.minute,
                days: config.days,
                startMonth: dateRange.startMonth,
                startDay: dateRange.startDay,
                endMonth: dateRange.endMonth,
                endDay: dateRange.endDay,
                preferredSlot: nil,
                allowedSlots: Set(0...7)
            )
        case .sunrise(let solar):
            let offsetMinutes: Int
            switch solar.offset {
            case .minutes(let value):
                offsetMinutes = SolarTrigger.clampOnDeviceOffset(value)
            }
            return WLEDTimerConfig(
                hour: 255,
                minute: offsetMinutes,
                days: WeekdayMask.wledDow(fromSunFirst: solar.weekdays),
                startMonth: dateRange.startMonth,
                startDay: dateRange.startDay,
                endMonth: dateRange.endMonth,
                endDay: dateRange.endDay,
                preferredSlot: 8,
                allowedSlots: [8]
            )
        case .sunset(let solar):
            let offsetMinutes: Int
            switch solar.offset {
            case .minutes(let value):
                offsetMinutes = SolarTrigger.clampOnDeviceOffset(value)
            }
            return WLEDTimerConfig(
                hour: 254,
                minute: offsetMinutes,
                days: WeekdayMask.wledDow(fromSunFirst: solar.weekdays),
                startMonth: dateRange.startMonth,
                startDay: dateRange.startDay,
                endMonth: dateRange.endMonth,
                endDay: dateRange.endDay,
                preferredSlot: 9,
                allowedSlots: [9]
            )
        }
    }

    private func validateSolarConfigurationIfNeeded(
        for trigger: AutomationTrigger,
        device: WLEDDevice
    ) async -> String? {
        switch trigger {
        case .sunrise, .sunset:
            guard let reference = await wledSolarReference(for: device) else {
                let configured = await autoConfigureWLEDSolarReference(for: device)
                return configured ? nil : "Could not read WLED solar settings"
            }
            guard reference.coordinate != nil else {
                let configured = await autoConfigureWLEDSolarReference(for: device)
                return configured ? nil : "WLED location not configured for sunrise/sunset"
            }
            return nil
        default:
            return nil
        }
    }

    private func autoConfigureWLEDSolarReference(for device: WLEDDevice) async -> Bool {
        do {
            let coordinate = try await locationProvider.currentCoordinate()
            try await apiService.updateSolarReference(
                for: device,
                coordinate: coordinate,
                timeZone: .current
            )
            if let refreshed = await wledSolarReference(for: device),
               refreshed.coordinate != nil {
                logger.info("Auto-configured WLED solar location for \(device.name, privacy: .public)")
                return true
            }
            logger.warning("WLED solar auto-config attempted but coordinate still missing for \(device.name, privacy: .public)")
            return false
        } catch {
            logger.warning("Failed to auto-configure WLED solar location for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return max(0, min(1439, hour * 60 + minute))
    }

    private func ensureTimerSlot(
        for automation: Automation,
        device: WLEDDevice,
        preferredSlot: Int?,
        allowedSlots: Set<Int>
    ) async -> TimerSlotResolution {
        do {
            let timers = try await apiService.fetchTimers(for: device)
            guard !timers.isEmpty else {
                return .unresolved("Timer list unavailable")
            }
            let reservedSlots = reservedTimerSlots(excluding: automation, deviceId: device.id)
            let existingSlot = storedTimerSlot(for: automation, deviceId: device.id)
            let reclaimableSlots = DeviceCleanupManager.shared.activeDeleteIds(type: .timer, deviceId: device.id)
            if let selection = Self.selectTimerSlot(
                existingSlot: existingSlot,
                preferredSlot: preferredSlot,
                allowedSlots: allowedSlots,
                timers: timers,
                reservedSlots: reservedSlots,
                reclaimableSlots: reclaimableSlots
            ) {
                logger.info(
                    "automation.slot.selected device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(selection.slot) reason=\(selection.reason.rawValue, privacy: .public)"
                )
                return .slot(selection.slot)
            }
            let existingSlotLabel = existingSlot.map(String.init) ?? "nil"
            logger.warning(
                "automation.slot.unavailable device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) allowed=\(Array(allowedSlots).sorted(), privacy: .public) reserved=\(Array(reservedSlots).sorted(), privacy: .public) existing=\(existingSlotLabel, privacy: .public) reclaimable=\(Array(reclaimableSlots).sorted(), privacy: .public)"
            )
            return .unavailable
        } catch {
            logger.error("Failed to fetch timers for \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if isTransientOnDeviceSyncError(error) {
                return .unresolved(error.localizedDescription)
            }
            return .unavailable
        }
    }

    private nonisolated static func selectTimerSlot(
        existingSlot: Int?,
        preferredSlot: Int?,
        allowedSlots: Set<Int>,
        timers: [WLEDTimer],
        reservedSlots: Set<Int>,
        reclaimableSlots: Set<Int>
    ) -> TimerSlotSelection? {
        guard !allowedSlots.isEmpty else { return nil }
        let timerById = Dictionary(uniqueKeysWithValues: timers.map { ($0.id, $0) })
        let availableSlots = Set(timerById.keys)

        if let existingSlot,
           allowedSlots.contains(existingSlot),
           availableSlots.contains(existingSlot),
           !reservedSlots.contains(existingSlot) {
            return TimerSlotSelection(slot: existingSlot, reason: .existing)
        }

        if let preferredSlot,
           allowedSlots.contains(preferredSlot),
           availableSlots.contains(preferredSlot),
           !reservedSlots.contains(preferredSlot) {
            let preferredTimer = timerById[preferredSlot]
            let preferredIsReclaimable = reclaimableSlots.contains(preferredSlot)
            let preferredOccupiedByActionableMacro = (preferredTimer?.macroId ?? 0) > 0
            if !preferredOccupiedByActionableMacro || preferredIsReclaimable {
                return TimerSlotSelection(
                    slot: preferredSlot,
                    reason: preferredIsReclaimable ? .reclaimable : .preferred
                )
            }
        }

        return timers
            .filter {
                allowedSlots.contains($0.id)
                    && !reservedSlots.contains($0.id)
                    && ($0.macroId == 0 || reclaimableSlots.contains($0.id))
            }
            .map(\.id)
            .sorted()
            .first
            .map { slot in
                TimerSlotSelection(
                    slot: slot,
                    reason: reclaimableSlots.contains(slot) ? .reclaimable : .free
                )
            }
    }

#if DEBUG
    nonisolated static func _selectTimerSlotForTesting(
        existingSlot: Int?,
        preferredSlot: Int?,
        allowedSlots: Set<Int>,
        timers: [WLEDTimer],
        reservedSlots: Set<Int>,
        reclaimableSlots: Set<Int>
    ) -> (slot: Int, reason: String)? {
        guard let selection = selectTimerSlot(
            existingSlot: existingSlot,
            preferredSlot: preferredSlot,
            allowedSlots: allowedSlots,
            timers: timers,
            reservedSlots: reservedSlots,
            reclaimableSlots: reclaimableSlots
        ) else {
            return nil
        }
        return (selection.slot, selection.reason.rawValue)
    }
#endif

    private nonisolated static func computeReservedTimerSlots(
        from records: [Automation],
        excludingAutomationId: UUID,
        deviceId: String,
        importedTemplatePrefix: String
    ) -> Set<Int> {
        var reserved = Set<Int>()
        for record in records where record.id != excludingAutomationId {
            guard record.metadata.runOnDevice else { continue }
            guard record.targets.deviceIds.contains(deviceId) else { continue }
            // Imported rows mirror device state and can be stale while cleanup catches up.
            // Do not let them reserve slots for authored automation sync.
            if let templateId = record.metadata.templateId,
               templateId.hasPrefix(importedTemplatePrefix) {
                continue
            }
            if let slot = record.metadata.wledTimerSlotsByDevice?[deviceId] {
                reserved.insert(slot)
            } else if record.targets.deviceIds.count == 1,
                      let slot = record.metadata.wledTimerSlot {
                reserved.insert(slot)
            }
        }
        return reserved
    }

    private func reservedTimerSlots(excluding automation: Automation, deviceId: String) -> Set<Int> {
        Self.computeReservedTimerSlots(
            from: automations,
            excludingAutomationId: automation.id,
            deviceId: deviceId,
            importedTemplatePrefix: importedAutomationTemplatePrefix
        )
    }

#if DEBUG
    nonisolated static func _reservedTimerSlotsForTesting(
        automations: [Automation],
        excludingAutomationId: UUID,
        deviceId: String
    ) -> Set<Int> {
        computeReservedTimerSlots(
            from: automations,
            excludingAutomationId: excludingAutomationId,
            deviceId: deviceId,
            importedTemplatePrefix: "wled.timer."
        )
    }
#endif

    private func timerSlotClaimedByAnotherAutomation(
        _ slot: Int,
        deviceId: String,
        excluding automationId: UUID
    ) -> Bool {
        automations.contains { record in
            guard record.id != automationId else { return false }
            guard record.targets.deviceIds.contains(deviceId) else { return false }
            if let mapped = record.metadata.wledTimerSlotsByDevice?[deviceId] {
                return mapped == slot
            }
            return record.metadata.wledTimerSlot == slot
        }
    }

    private func disableObsoleteTimerSlotIfNeeded(
        previousSlot: Int?,
        currentSlot: Int,
        automationId: UUID,
        device: WLEDDevice
    ) async {
        guard let previousSlot, previousSlot != currentSlot else { return }
        guard !timerSlotClaimedByAnotherAutomation(previousSlot, deviceId: device.id, excluding: automationId) else {
            return
        }
        do {
            let disabled = try await apiService.disableTimer(slot: previousSlot, device: device)
            if disabled {
                logger.info("Disabled obsolete timer slot \(previousSlot) on \(device.name, privacy: .public)")
            } else {
                DeviceCleanupManager.shared.enqueue(type: .timer, deviceId: device.id, ids: [previousSlot], source: .automation)
                logger.warning("Queued obsolete timer slot cleanup for \(device.name, privacy: .public) slot=\(previousSlot)")
            }
        } catch {
            DeviceCleanupManager.shared.enqueue(type: .timer, deviceId: device.id, ids: [previousSlot], source: .automation)
            logger.warning("Failed to disable obsolete timer slot on \(device.name, privacy: .public) slot=\(previousSlot): \(error.localizedDescription, privacy: .public)")
        }
    }

    struct OnDeviceScheduleValidation: Equatable {
        let isValid: Bool
        let message: String?
        let isWarning: Bool
    }

    func validateOnDeviceSchedule(for automation: Automation) async -> OnDeviceScheduleValidation {
        guard automation.metadata.runOnDevice else {
            return OnDeviceScheduleValidation(isValid: true, message: nil, isWarning: false)
        }

        let targetDevices = viewModel.devices.filter { automation.targets.deviceIds.contains($0.id) }
        guard !targetDevices.isEmpty else {
            return OnDeviceScheduleValidation(
                isValid: true,
                message: "Target devices are currently unavailable; schedule will sync when they reconnect.",
                isWarning: true
            )
        }

        var blockedSlotDevices: [String] = []
        var blockedConfigReasons: [String] = []
        var unresolvedDevices: [String] = []
        for device in targetDevices {
            do {
                if let solarIssue = await validateSolarConfigurationIfNeeded(for: automation.trigger, device: device) {
                    blockedConfigReasons.append("\(device.name): \(solarIssue)")
                    continue
                }
                guard let timeConfig = await wledTimerConfig(for: automation, device: device, referenceDate: Date()) else {
                    blockedConfigReasons.append("\(device.name): timer config unavailable")
                    continue
                }
                let timers = try await apiService.fetchTimers(for: device)
                let reserved = reservedTimerSlots(excluding: automation, deviceId: device.id)
                let existingSlot = storedTimerSlot(for: automation, deviceId: device.id)
                let reclaimableSlots = DeviceCleanupManager.shared.activeDeleteIds(type: .timer, deviceId: device.id)
                let selection = Self.selectTimerSlot(
                    existingSlot: existingSlot,
                    preferredSlot: timeConfig.preferredSlot,
                    allowedSlots: timeConfig.allowedSlots,
                    timers: timers,
                    reservedSlots: reserved,
                    reclaimableSlots: reclaimableSlots
                )
                if selection == nil {
                    blockedSlotDevices.append(device.name)
                }
            } catch {
                unresolvedDevices.append(device.name)
            }
        }

        if !blockedConfigReasons.isEmpty {
            return OnDeviceScheduleValidation(
                isValid: false,
                message: blockedConfigReasons.joined(separator: ", "),
                isWarning: false
            )
        }

        if !blockedSlotDevices.isEmpty {
            return OnDeviceScheduleValidation(
                isValid: false,
                message: "No available timer slots for: \(blockedSlotDevices.joined(separator: ", ")).",
                isWarning: false
            )
        }

        if !unresolvedDevices.isEmpty {
            return OnDeviceScheduleValidation(
                isValid: true,
                message: "Could not verify timer slots for: \(unresolvedDevices.joined(separator: ", ")). Will retry when reachable.",
                isWarning: true
            )
        }

        return OnDeviceScheduleValidation(isValid: true, message: nil, isWarning: false)
    }

    private func cleanupDeviceEntries(for automation: Automation) async -> Bool {
        let deviceIds = automation.targets.deviceIds
        var deletionMayFinalize = true
        for deviceId in deviceIds {
            let deleteTraceId = UUID().uuidString
            let playlistId = automation.metadata.wledPlaylistIdsByDevice?[deviceId] ?? automation.metadata.wledPlaylistId
            let presetId = automation.metadata.wledPresetIdsByDevice?[deviceId]
            let timerSlot = automation.metadata.wledTimerSlotsByDevice?[deviceId] ?? automation.metadata.wledTimerSlot
            let shouldDeleteManagedPlaylist = shouldDeleteManagedPlaylistAsset(for: automation, deviceId: deviceId)
            let shouldDeleteManagedPreset = shouldDeleteManagedPresetAsset(for: automation, deviceId: deviceId)
            let shouldDeleteTimerSlot: Bool = {
                guard let timerSlot else { return false }
                return !timerSlotClaimedByAnotherAutomation(
                    timerSlot,
                    deviceId: deviceId,
                    excluding: automation.id
                )
            }()
            let onlineDevice = viewModel.devices.first(where: { $0.id == deviceId && $0.isOnline })
            logger.info(
                "automation.delete.pipeline.begin trace=\(deleteTraceId, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) device=\(deviceId, privacy: .public) timerSlot=\((timerSlot.map(String.init) ?? "nil"), privacy: .public) deleteTimer=\(shouldDeleteTimerSlot, privacy: .public) playlistId=\((playlistId.map(String.init) ?? "nil"), privacy: .public) deletePlaylist=\(shouldDeleteManagedPlaylist, privacy: .public) presetId=\((presetId.map(String.init) ?? "nil"), privacy: .public) deletePreset=\(shouldDeleteManagedPreset, privacy: .public)"
            )
            // Persist deletion intent synchronously so "delete + force quit" does not resurrect
            // imported automations on next launch.
            if onlineDevice == nil {
                if let timerSlot {
                    if shouldDeleteTimerSlot {
                        logger.info("automation.delete.pipeline.queue trace=\(deleteTraceId, privacy: .public) type=timer ids=[\(timerSlot, privacy: .public)]")
                        DeviceCleanupManager.shared.enqueue(
                            type: .timer,
                            deviceId: deviceId,
                            ids: [timerSlot],
                            source: .automation,
                            verificationRequired: true
                        )
                    } else {
                        // Another automation still owns this slot; do not clear it.
                        DeviceCleanupManager.shared.removeIds(type: .timer, deviceId: deviceId, ids: [timerSlot])
                        logger.info(
                            "automation.delete.timer.skip_claimed device=\(deviceId, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot)"
                        )
                    }
                }
                if shouldDeleteManagedPlaylist, let playlistId {
                    logger.info("automation.delete.pipeline.queue trace=\(deleteTraceId, privacy: .public) type=playlist ids=[\(playlistId, privacy: .public)]")
                    DeviceCleanupManager.shared.enqueue(
                        type: .playlist,
                        deviceId: deviceId,
                        ids: [playlistId],
                        source: .automation,
                        verificationRequired: true
                    )
                }
            }

            var presetDeleteIds = Set<Int>()
            if shouldDeleteManagedPreset, let presetId {
                presetDeleteIds.insert(presetId)
            }
            if shouldDeleteManagedPlaylist {
                presetDeleteIds.formUnion(storedManagedTransitionStepPresetIds(for: automation, deviceId: deviceId))
            }
            if !presetDeleteIds.isEmpty, onlineDevice == nil {
                logger.info("automation.delete.pipeline.queue trace=\(deleteTraceId, privacy: .public) type=preset ids=\(Array(presetDeleteIds).sorted(), privacy: .public)")
                DeviceCleanupManager.shared.enqueue(
                    type: .preset,
                    deviceId: deviceId,
                    ids: Array(presetDeleteIds).sorted(),
                    source: .automation,
                    verificationRequired: true
                )
            }

            if onlineDevice == nil {
                let hasTargetedCleanup =
                    ((timerSlot != nil) && shouldDeleteTimerSlot)
                    || ((playlistId != nil) && shouldDeleteManagedPlaylist)
                    || !presetDeleteIds.isEmpty
                if hasTargetedCleanup {
                    logger.info(
                        "automation.delete.pipeline.background_cleanup trace=\(deleteTraceId, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) device=\(deviceId, privacy: .public)"
                    )
                }
            }

            if let device = onlineDevice {
                let deviceCleanupComplete = await cleanupDeviceEntriesOnOnlineDevice(
                    automation: automation,
                    device: device,
                    deviceId: deviceId,
                    deleteTraceId: deleteTraceId,
                    playlistId: playlistId,
                    timerSlot: timerSlot,
                    presetDeleteIds: presetDeleteIds,
                    shouldDeleteManagedPlaylist: shouldDeleteManagedPlaylist,
                    shouldDeleteTimerSlot: shouldDeleteTimerSlot
                )
                deletionMayFinalize = deletionMayFinalize && deviceCleanupComplete
            }
        }
        return deletionMayFinalize
    }

    private func cleanupDeviceEntriesOnOnlineDevice(
        automation: Automation,
        device: WLEDDevice,
        deviceId: String,
        deleteTraceId: String,
        playlistId: Int?,
        timerSlot: Int?,
        presetDeleteIds: Set<Int>,
        shouldDeleteManagedPlaylist: Bool,
        shouldDeleteTimerSlot: Bool
    ) async -> Bool {
        var runtimePresetDeleteIds = presetDeleteIds
        var targetedPlaylistDeleteIds: Set<Int> = []
        if shouldDeleteManagedPlaylist, let playlistId {
            targetedPlaylistDeleteIds.insert(playlistId)
        }
        if shouldDeleteManagedPlaylist,
           let playlistId,
           storedManagedTransitionStepPresetIds(for: automation, deviceId: deviceId).isEmpty {
           let fetchedStepIds = await fetchPlaylistStepPresetIds(playlistId: playlistId, device: device)
            if !fetchedStepIds.isEmpty {
                runtimePresetDeleteIds.formUnion(fetchedStepIds)
            }
        }

        let targetedDeleteCount =
            runtimePresetDeleteIds.count +
            targetedPlaylistDeleteIds.count +
            ((shouldDeleteTimerSlot && timerSlot != nil) ? 1 : 0)
        if targetedDeleteCount > 0 {
            updateDeletionProgress(
                automationId: automation.id,
                totalSteps: targetedDeleteCount,
                remainingSteps: targetedDeleteCount,
                phase: "Deleting timer slot..."
            )
        } else {
            updateDeletionProgress(
                automationId: automation.id,
                totalSteps: 1,
                remainingSteps: 1,
                phase: "No managed IDs found, verifying..."
            )
        }
        if let timerSlot {
            if shouldDeleteTimerSlot {
                let ownership = await timerOwnershipStatusForDeletion(
                    automation: automation,
                    device: device,
                    slot: timerSlot
                )
                switch ownership {
                case .owned:
                    logger.info(
                        "automation.delete.pipeline.direct trace=\(deleteTraceId, privacy: .public) type=timer ids=[\(timerSlot, privacy: .public)] ownership=owned"
                    )
	                    do {
	                        let deleted = try await apiService.disableTimer(slot: timerSlot, device: device)
	                        if !deleted {
	                            logger.error(
	                                "automation.delete.timer.direct_verify_failed device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot)"
	                            )
	                            DeviceCleanupManager.shared.enqueue(
	                                type: .timer,
	                                deviceId: device.id,
	                                ids: [timerSlot],
	                                source: .automation,
	                                verificationRequired: true
	                            )
	                        }
	                    } catch {
	                        logger.error(
	                            "automation.delete.timer.direct_failed device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot) error=\(error.localizedDescription, privacy: .public)"
	                        )
	                        DeviceCleanupManager.shared.enqueue(
	                            type: .timer,
	                            deviceId: device.id,
	                            ids: [timerSlot],
	                            source: .automation,
	                            verificationRequired: true
	                        )
	                    }
                case .notOwned:
                    logger.info(
                        "automation.delete.timer.skip_not_owned device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot)"
                    )
                case .unknown(let reason):
                    logger.error(
                        "automation.delete.timer.defer_unknown device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot) reason=\(reason, privacy: .public)"
                    )
                    if reason.hasPrefix("missing_expected") {
                        return false
                    }
                    DeviceCleanupManager.shared.enqueue(
                        type: .timer,
                        deviceId: device.id,
                        ids: [timerSlot],
                        source: .automation,
                        verificationRequired: true
                    )
                }
            } else {
                logger.info(
                    "automation.delete.timer.skip_claimed device=\(device.id, privacy: .public) automation=\(automation.id.uuidString, privacy: .public) slot=\(timerSlot)"
                )
            }
        }

        let playlistDeleteIds = Array(targetedPlaylistDeleteIds).sorted()
        let presetDeleteIdsSorted = Array(runtimePresetDeleteIds).sorted()

        if !playlistDeleteIds.isEmpty || !presetDeleteIdsSorted.isEmpty {
            do {
                _ = try await apiService.stopPlaylist(on: device)
            } catch {
                logger.warning(
                    "automation.delete.pipeline.stop_playlist_failed trace=\(deleteTraceId, privacy: .public) device=\(device.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
            await apiService.releaseRealtimeOverride(for: device)
            let presetStoreDeleteSettleSeconds =
                ((shouldDeleteTimerSlot && timerSlot != nil)
                 ? postTimerDeletePresetStoreSettleSeconds
                 : prePresetStoreDeleteQuiesceSeconds)
            if presetStoreDeleteSettleSeconds > 0 {
                let settleNs = UInt64(presetStoreDeleteSettleSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: settleNs)
            }
            updateDeletionProgress(
                automationId: automation.id,
                totalSteps: targetedDeleteCount,
                remainingSteps: max(0, playlistDeleteIds.count + presetDeleteIdsSorted.count),
                phase: "Queueing playlist cleanup..."
            )
            logger.info(
                "automation.delete.pipeline.queue_wled_style trace=\(deleteTraceId, privacy: .public) playlistIds=\(playlistDeleteIds, privacy: .public) presetIds=\(presetDeleteIdsSorted, privacy: .public)"
            )
            let notBefore = await presetStoreDeleteSettleNotBefore(deviceId: device.id)
            if !playlistDeleteIds.isEmpty {
                DeviceCleanupManager.shared.enqueue(
                    type: .playlist,
                    deviceId: device.id,
                    ids: playlistDeleteIds,
                    source: .automation,
                    verificationRequired: true,
                    notBefore: notBefore
                )
            }
            if !presetDeleteIdsSorted.isEmpty {
                DeviceCleanupManager.shared.enqueue(
                    type: .preset,
                    deviceId: device.id,
                    ids: presetDeleteIdsSorted,
                    source: .automation,
                    verificationRequired: true,
                    notBefore: notBefore
                )
            }
            let queueDrained = await waitForPresetStoreDeleteQueueDrain(
                deviceId: device.id,
                playlistIds: playlistDeleteIds,
                presetIds: presetDeleteIdsSorted
            )
            guard queueDrained else {
                logger.error(
                    "automation.delete.pipeline.queue_not_drained trace=\(deleteTraceId, privacy: .public) device=\(device.id, privacy: .public) playlistIds=\(playlistDeleteIds, privacy: .public) presetIds=\(presetDeleteIdsSorted, privacy: .public)"
                )
                return false
            }

            do {
                try await verifyPresetStoreDeletionAndRecoverIfNeeded(
                    device: device,
                    deleteTraceId: deleteTraceId,
                    playlistIds: playlistDeleteIds,
                    presetIds: presetDeleteIdsSorted
                )
            } catch {
                logger.error(
                    "automation.delete.pipeline.postcheck_failed trace=\(deleteTraceId, privacy: .public) device=\(device.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }

        if targetedDeleteCount > 0 {
            updateDeletionProgress(
                automationId: automation.id,
                totalSteps: targetedDeleteCount,
                remainingSteps: 0,
                phase: "Verifying cleanup..."
            )
        }

        logger.info(
            "automation.delete.pipeline.summary trace=\(deleteTraceId, privacy: .public) device=\(device.id, privacy: .public) timerDeleted=\(shouldDeleteTimerSlot, privacy: .public) playlistIds=\(playlistDeleteIds, privacy: .public) presetIds=\(presetDeleteIdsSorted, privacy: .public)"
        )
        updateDeletionProgress(
            automationId: automation.id,
            totalSteps: max(1, targetedDeleteCount),
            remainingSteps: 0,
            phase: "Finalizing removal..."
        )
        return true
    }

    private func waitForPresetStoreDeleteQueueDrain(
        deviceId: String,
        playlistIds: [Int],
        presetIds: [Int]
    ) async -> Bool {
        let normalizedPlaylistIds = Array(Set(playlistIds.filter { (1...250).contains($0) })).sorted()
        let normalizedPresetIds = Array(Set(presetIds.filter { (1...250).contains($0) })).sorted()
        guard !normalizedPlaylistIds.isEmpty || !normalizedPresetIds.isEmpty else {
            return true
        }

        let estimatedCadenceSeconds = Double(max(1, normalizedPlaylistIds.count + normalizedPresetIds.count)) * 3.0
        let timeoutSeconds = max(
            postPresetStoreMutationDeleteSettleSeconds + 10.0,
            min(deleteFinalizeTimeoutSeconds, estimatedCadenceSeconds + 20.0)
        )
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var loop = 0

        while Date() < deadline {
            let pendingPlaylistIds = normalizedPlaylistIds.filter {
                DeviceCleanupManager.shared.hasActiveDelete(type: .playlist, deviceId: deviceId, id: $0)
            }
            let pendingPresetIds = normalizedPresetIds.filter {
                DeviceCleanupManager.shared.hasActiveDelete(type: .preset, deviceId: deviceId, id: $0)
            }
            if pendingPlaylistIds.isEmpty && pendingPresetIds.isEmpty {
                return true
            }

            loop += 1
            if loop == 1 || loop % 5 == 0 {
                logger.info(
                    "automation.delete.pipeline.waiting_queue_drain device=\(deviceId, privacy: .public) pendingPlaylists=\(pendingPlaylistIds, privacy: .public) pendingPresets=\(pendingPresetIds, privacy: .public)"
                )
            }

            await DeviceCleanupManager.shared.processQueue(for: deviceId)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return false
    }

    private struct PresetStoreDeleteResiduals {
        let playlistIds: [Int]
        let presetIds: [Int]

        var isEmpty: Bool { playlistIds.isEmpty && presetIds.isEmpty }
    }

    private func verifyPresetStoreDeletionAndRecoverIfNeeded(
        device: WLEDDevice,
        deleteTraceId: String,
        playlistIds: [Int],
        presetIds: [Int]
    ) async throws {
        var residuals = try await fetchPresetStoreDeleteResidualsWithRetry(
            device: device,
            playlistIds: playlistIds,
            presetIds: presetIds,
            traceId: deleteTraceId,
            phase: "pass1"
        )
        guard !residuals.isEmpty else {
            return
        }

        logger.warning(
            "automation.delete.pipeline.leftovers_pass1 trace=\(deleteTraceId, privacy: .public) device=\(device.id, privacy: .public) playlists=\(residuals.playlistIds, privacy: .public) presets=\(residuals.presetIds, privacy: .public)"
        )

        if !residuals.playlistIds.isEmpty {
            DeviceCleanupManager.shared.enqueue(
                type: .playlist,
                deviceId: device.id,
                ids: residuals.playlistIds,
                source: .automation,
                verificationRequired: true
            )
        }
        if !residuals.presetIds.isEmpty {
            DeviceCleanupManager.shared.enqueue(
                type: .preset,
                deviceId: device.id,
                ids: residuals.presetIds,
                source: .automation,
                verificationRequired: true
            )
        }
        let queueDrained = await waitForPresetStoreDeleteQueueDrain(
            deviceId: device.id,
            playlistIds: residuals.playlistIds,
            presetIds: residuals.presetIds
        )
        guard queueDrained else {
            let reason = "queue_not_drained playlists=\(residuals.playlistIds) presets=\(residuals.presetIds)"
            throw WLEDAPIError.presetStoreDeleteIncomplete(reason)
        }

        residuals = try await fetchPresetStoreDeleteResidualsWithRetry(
            device: device,
            playlistIds: residuals.playlistIds,
            presetIds: residuals.presetIds,
            traceId: deleteTraceId,
            phase: "pass2"
        )
        guard residuals.isEmpty else {
            let reason = "leftover playlists=\(residuals.playlistIds) presets=\(residuals.presetIds)"
            throw WLEDAPIError.presetStoreDeleteIncomplete(reason)
        }
    }

    private func fetchPresetStoreDeleteResiduals(
        device: WLEDDevice,
        playlistIds: [Int],
        presetIds: [Int]
    ) async throws -> PresetStoreDeleteResiduals {
        let targetPlaylists = Set(playlistIds.filter { (1...250).contains($0) })
        let targetPresets = Set(presetIds.filter { (1...250).contains($0) })
        let catalog = try await apiService.fetchPresetStoreCatalogIdsStrict(device: device)
        let residualPlaylistIds = targetPlaylists.intersection(catalog.playlistIds).sorted()
        let residualPresetIds = targetPresets.intersection(catalog.presetIds).sorted()

        return PresetStoreDeleteResiduals(
            playlistIds: residualPlaylistIds,
            presetIds: residualPresetIds
        )
    }

    private func fetchPresetStoreDeleteResidualsWithRetry(
        device: WLEDDevice,
        playlistIds: [Int],
        presetIds: [Int],
        traceId: String,
        phase: String
    ) async throws -> PresetStoreDeleteResiduals {
        let attempts = 4
        var delayNanoseconds: UInt64 = 800_000_000
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await fetchPresetStoreDeleteResiduals(
                    device: device,
                    playlistIds: playlistIds,
                    presetIds: presetIds
                )
            } catch {
                lastError = error
                guard attempt < attempts, isPresetStoreCatalogRetryable(error) else {
                    throw error
                }
                logger.warning(
                    "automation.delete.pipeline.postcheck_retry trace=\(traceId, privacy: .public) device=\(device.id, privacy: .public) phase=\(phase, privacy: .public) attempt=\(attempt, privacy: .public)/\(attempts, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                delayNanoseconds = min(delayNanoseconds * 2, 3_200_000_000)
            }
        }

        if let lastError {
            throw lastError
        }
        throw WLEDAPIError.invalidResponse
    }

    private func isPresetStoreCatalogRetryable(_ error: Error) -> Bool {
        guard let apiError = error as? WLEDAPIError else {
            return false
        }
        switch apiError {
        case .httpError(let statusCode):
            return statusCode == 501 || statusCode >= 500
        case .timeout, .networkError, .deviceBusy, .deviceOffline, .deviceUnreachable:
            return true
        case .decodingError, .invalidResponse, .presetStoreUnreadable:
            return true
        default:
            return false
        }
    }

    private func presetStoreDeleteSettleNotBefore(deviceId: String) async -> Date? {
        guard let secondsSinceMutation = await apiService.secondsSinceLastPresetStoreMutationEnd(deviceId: deviceId),
              secondsSinceMutation < postPresetStoreMutationDeleteSettleSeconds else {
            return nil
        }
        let delay = postPresetStoreMutationDeleteSettleSeconds - secondsSinceMutation
        let notBefore = Date().addingTimeInterval(delay)
        logger.info(
            "automation.delete.preset_store_settle_deferred device=\(deviceId, privacy: .public) secondsSinceMutation=\(String(format: "%.1f", secondsSinceMutation), privacy: .public) notBefore=\(notBefore.ISO8601Format(), privacy: .public)"
        )
        return notBefore
    }

    private func updateDeletionProgress(
        automationId: UUID,
        totalSteps: Int,
        remainingSteps: Int,
        phase: String
    ) {
        let clampedTotal = max(1, totalSteps)
        let clampedRemaining = min(clampedTotal, max(0, remainingSteps))
        deletionProgressByAutomationId[automationId] = AutomationDeletionProgress(
            totalSteps: clampedTotal,
            remainingSteps: clampedRemaining,
            phaseDescription: phase
        )
    }

    private func isTimerActionable(_ timer: WLEDTimer) -> Bool {
        let hasDateRange = timer.startMonth != nil || timer.startDay != nil || timer.endMonth != nil || timer.endDay != nil
        let hasClockTime = timer.hour != 0 || timer.minute != 0
        let hasNonDefaultDays = timer.days != 0x7F
        let hasMacro = timer.macroId != 0
        let hasSolarMarker = timer.hour == 255 || timer.hour == 254
        return timer.enabled || hasMacro || hasClockTime || hasNonDefaultDays || hasDateRange || hasSolarMarker
    }

    private func shouldDeleteManagedPlaylistAsset(for automation: Automation, deviceId: String) -> Bool {
        if automation.metadata.managedPlaylistSignature(for: deviceId) != nil {
            return true
        }
        if !(automation.metadata.managedStepPresetIds(for: deviceId) ?? []).isEmpty {
            return true
        }
        if let templateId = automation.metadata.templateId,
           templateId.hasPrefix(importedAutomationTemplatePrefix) {
            return false
        }

        switch automation.action {
        case .transition(let payload):
            return payload.presetId == nil
        case .preset, .playlist, .scene, .gradient, .effect, .directState:
            return false
        }
    }

    private func shouldDeleteManagedPresetAsset(for automation: Automation, deviceId: String) -> Bool {
        if automation.metadata.managedPresetSignature(for: deviceId) != nil {
            return true
        }
        if let templateId = automation.metadata.templateId,
           templateId.hasPrefix(importedAutomationTemplatePrefix) {
            return false
        }

        switch automation.action {
        case .scene, .gradient, .effect, .directState:
            return true
        case .transition(let payload):
            return payload.presetId == nil
        case .preset, .playlist:
            return false
        }
    }
    
    private func resolveGradientPayload(_ payload: GradientActionPayload, device: WLEDDevice) -> LEDGradient {
        if let presetId = payload.presetId,
           let preset = presetsStore.colorPreset(id: presetId) {
            return LEDGradient(
                stops: preset.gradientStops,
                interpolation: payload.gradient.interpolation
            )
        }
        return payload.gradient
    }
    
    private func resolveTransitionPayload(_ payload: TransitionActionPayload, device: WLEDDevice) -> TransitionActionPayload {
        guard let presetId = payload.presetId,
              let preset = presetsStore.transitionPreset(id: presetId) else {
            return payload
        }
        return TransitionActionPayload(
            startGradient: preset.gradientA,
            startBrightness: preset.brightnessA,
            startTemperature: preset.temperatureA,
            startWhiteLevel: preset.whiteLevelA,
            endGradient: preset.gradientB,
            endBrightness: preset.brightnessB,
            endTemperature: preset.temperatureB,
            endWhiteLevel: preset.whiteLevelB,
            durationSeconds: payload.durationSeconds > 0 ? payload.durationSeconds : preset.durationSec,
            shouldLoop: payload.shouldLoop,
            presetId: presetId,
            presetName: preset.name
        )
    }
    
    private func resolveEffectPayload(_ payload: EffectActionPayload, device: WLEDDevice) -> EffectActionPayload {
        guard let presetId = payload.presetId,
              let preset = presetsStore.effectPreset(id: presetId) else {
            return payload
        }
        
        var gradient = payload.gradient
        if let presetStops = preset.gradientStops, !presetStops.isEmpty {
            gradient = LEDGradient(
                stops: presetStops,
                interpolation: preset.gradientInterpolation ?? gradient?.interpolation ?? .linear
            )
        }
        
        return EffectActionPayload(
            effectId: preset.effectId,
            effectName: preset.name,
            gradient: gradient,
            speed: preset.speed ?? payload.speed,
            intensity: preset.intensity ?? payload.intensity,
            paletteId: preset.paletteId ?? payload.paletteId,
            brightness: preset.brightness,
            presetId: presetId,
            presetName: preset.name
        )
    }
    
    private func defaultGradient(for device: WLEDDevice) -> LEDGradient {
        let hex = device.currentColor.toHex()
        return LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ])
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            do {
                automations = try JSONDecoder().decode([Automation].self, from: data)
                var didUpdate = false
                automations = automations.map { automation in
                    var updated = automation
                    if updated.metadata.runOnDevice {
                        let targetIds = updated.targets.deviceIds
                        if !targetIds.isEmpty {
                            var syncMap = updated.metadata.wledSyncStateByDevice ?? [:]
                            for deviceId in targetIds where syncMap[deviceId] == nil {
                                syncMap[deviceId] = .unknown
                                didUpdate = true
                            }
                            updated.metadata.wledSyncStateByDevice = syncMap
                        }
                    }
                    updated.metadata.normalizeWLEDScalarFallbacks(for: updated.targets.deviceIds)
                    return updated
                }
                if didUpdate {
                    save()
                }
                logger.info("Loaded \(self.automations.count) automations")
            } catch {
                logger.error("Failed to decode automations, attempting legacy migration: \(error.localizedDescription)")
                automations = try migrateLegacyAutomations(from: data)
                save()
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 260 {
                logger.debug("No automations file found (first launch) - will create on save")
            } else {
                logger.error("Failed to load automations: \(error.localizedDescription)")
            }
            automations = []
        }
    }
    
    private func migrateLegacyAutomations(from data: Data) throws -> [Automation] {
        let legacyRecords = try JSONDecoder().decode([LegacyAutomation].self, from: data)
        return legacyRecords.map { $0.toModern() }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(automations)
            try data.write(to: fileURL)
            logger.info("Saved \(self.automations.count) automations")
        } catch {
            logger.error("Failed to save automations: \(error.localizedDescription)")
        }
    }
}

// MARK: - Legacy Model Migration

private struct LegacyAutomation: Codable {
    let id: UUID
    var name: String
    var enabled: Bool
    var time: String
    var weekdays: [Bool]
    var sceneId: UUID
    var deviceId: String
    var createdAt: Date
    var lastTriggered: Date?
    
    func toModern() -> Automation {
        let trigger = AutomationTrigger.specificTime(
            TimeTrigger(
                time: time,
                weekdays: weekdays,
                timezoneIdentifier: TimeZone.current.identifier
            )
        )
        let action = AutomationAction.scene(
            SceneActionPayload(
                sceneId: sceneId,
                sceneName: nil,
                brightnessOverride: nil
            )
        )
        let targets = AutomationTargets(deviceIds: [deviceId])
        return Automation(
            id: id,
            name: name,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastTriggered: lastTriggered,
            trigger: trigger,
            action: action,
            targets: targets,
            metadata: AutomationMetadata()
        )
    }
}

// MARK: - Location Provider & Solar Calculations

@MainActor
private final class LocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pendingContinuations: [CheckedContinuation<CLLocationCoordinate2D, Error>] = []
    private var pendingAuthorizationContinuations: [CheckedContinuation<Void, Error>] = []
    private var isLocationRequestInFlight = false
    private var isAuthorizationRequestInFlight = false
    private var locationTimeoutTask: Task<Void, Never>?
    private var authorizationTimeoutTask: Task<Void, Never>?
    private var cachedCoordinate: CLLocationCoordinate2D?
    private var lastUpdate: Date?
    
    // UserDefaults keys for persistent location storage
    private let latitudeKey = "com.aesdetic.cachedLatitude"
    private let longitudeKey = "com.aesdetic.cachedLongitude"
    private let lastUpdateKey = "com.aesdetic.lastLocationUpdate"
    private let timeZoneKey = "com.aesdetic.cachedTimeZoneIdentifier"
    private var cachedTimeZoneIdentifier: String?
    
    override init() {
        super.init()
        manager.delegate = self
        // Use reduced accuracy for city-level location (~10km radius)
        // Perfect for sunrise/sunset, more privacy-friendly
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        
        // Load cached location from UserDefaults (survives app restarts)
        loadCachedLocation()
    }

    deinit {
        locationTimeoutTask?.cancel()
        authorizationTimeoutTask?.cancel()
    }
    
    private func loadCachedLocation() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latitudeKey) != nil,
              defaults.object(forKey: longitudeKey) != nil else {
            return
        }
        
        let latitude = defaults.double(forKey: latitudeKey)
        let longitude = defaults.double(forKey: longitudeKey)
        cachedTimeZoneIdentifier = defaults.string(forKey: timeZoneKey)
        
        if let timestamp = defaults.object(forKey: lastUpdateKey) as? Date {
            cachedCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            lastUpdate = timestamp
        }
    }
    
    private func saveCachedLocation() {
        guard let coordinate = cachedCoordinate, let update = lastUpdate else { return }
        
        let defaults = UserDefaults.standard
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        defaults.set(update, forKey: lastUpdateKey)
        defaults.set(cachedTimeZoneIdentifier, forKey: timeZoneKey)
    }
    
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        let currentTimeZoneIdentifier = TimeZone.current.identifier

        // Cache location for 30 days since lamps don't move
        // Only re-check if cache is stale or app restarts in new location
        if let coordinate = cachedCoordinate,
           let lastUpdate,
           Date().timeIntervalSince(lastUpdate) < 2_592_000, // 30 days
           cachedTimeZoneIdentifier == currentTimeZoneIdentifier {
            #if DEBUG
            print("📍 Using cached location: \(coordinate.latitude), \(coordinate.longitude)")
            #endif
            return coordinate
        }

        try await ensureAuthorized()

        // Now request location
        #if DEBUG
        print("📍 Requesting location...")
        #endif
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuations.append(continuation)
            guard !self.isLocationRequestInFlight else { return }
            self.isLocationRequestInFlight = true
            self.manager.requestLocation()
            self.scheduleLocationRequestTimeout()
        }
    }

    private func ensureAuthorized() async throws {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied, .restricted:
            #if DEBUG
            print("❌ Location permission denied")
            #endif
            throw NSError(domain: kCLErrorDomain, code: CLError.denied.rawValue)
        case .notDetermined:
            #if DEBUG
            print("❓ Location permission not determined - requesting...")
            #endif
            return try await withCheckedThrowingContinuation { continuation in
                pendingAuthorizationContinuations.append(continuation)
                guard !isAuthorizationRequestInFlight else { return }
                isAuthorizationRequestInFlight = true
                manager.requestWhenInUseAuthorization()
                scheduleAuthorizationRequestTimeout()
            }
        @unknown default:
            throw NSError(domain: kCLErrorDomain, code: CLError.denied.rawValue)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if DEBUG
        print("🔐 Location authorization changed: \(manager.authorizationStatus.rawValue)")
        #endif
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorizationRequestInFlight = false
            resumeAllAuthorizationContinuations(with: .success(()))
        case .denied, .restricted:
            isAuthorizationRequestInFlight = false
            let error = NSError(domain: kCLErrorDomain, code: CLError.denied.rawValue)
            resumeAllAuthorizationContinuations(with: .failure(error))
            if !pendingContinuations.isEmpty {
                resumeAllContinuations(with: .failure(error))
            }
        @unknown default:
            isAuthorizationRequestInFlight = false
            let error = NSError(domain: kCLErrorDomain, code: CLError.denied.rawValue)
            resumeAllAuthorizationContinuations(with: .failure(error))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            #if DEBUG
            print("❌ No location in update")
            #endif
            return
        }
        #if DEBUG
        print("✅ Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif
        cachedCoordinate = location.coordinate
        lastUpdate = Date()
        cachedTimeZoneIdentifier = TimeZone.current.identifier
        saveCachedLocation() // Persist to UserDefaults
        resumeAllContinuations(with: .success(location.coordinate))
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("❌ Location error: \(error.localizedDescription)")
        #endif
        resumeAllContinuations(with: .failure(error))
    }

    private func resumeAllContinuations(with result: Result<CLLocationCoordinate2D, Error>) {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        isLocationRequestInFlight = false
        for continuation in continuations {
            switch result {
            case .success(let coordinate):
                continuation.resume(returning: coordinate)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private func resumeAllAuthorizationContinuations(with result: Result<Void, Error>) {
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil
        let continuations = pendingAuthorizationContinuations
        pendingAuthorizationContinuations.removeAll()
        for continuation in continuations {
            switch result {
            case .success:
                continuation.resume(returning: ())
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private func scheduleLocationRequestTimeout(seconds: TimeInterval = 12) {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard isLocationRequestInFlight, !pendingContinuations.isEmpty else { return }
            let timeout = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
            resumeAllContinuations(with: .failure(timeout))
        }
    }

    private func scheduleAuthorizationRequestTimeout(seconds: TimeInterval = 12) {
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard isAuthorizationRequestInFlight, !pendingAuthorizationContinuations.isEmpty else { return }
            isAuthorizationRequestInFlight = false
            let timeout = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
            resumeAllAuthorizationContinuations(with: .failure(timeout))
            if !pendingContinuations.isEmpty {
                resumeAllContinuations(with: .failure(timeout))
            }
        }
    }
}

public enum SolarEvent: Hashable {
    case sunrise
    case sunset
}

public enum SunriseSunsetCalculator {
    public static func nextEventDate(
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        referenceDate: Date,
        offsetMinutes: Int,
        timeZone: TimeZone
    ) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        for offset in 0...1 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: referenceDate),
                  let baseEvent = eventDate(on: date, event: event, coordinate: coordinate, timeZone: timeZone) else {
                continue
            }
            let adjusted = baseEvent.addingTimeInterval(Double(offsetMinutes) * 60)
            if adjusted > referenceDate {
                return adjusted
            }
        }
        return nil
    }
    
    private static func eventDate(
        on date: Date,
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        timeZone: TimeZone
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else {
            return nil
        }
        
        let zenith = 90.833
        let longitudeHour = coordinate.longitude / 15.0
        let N = Double(dayOfYear)
        let base = (event == .sunrise ? 6.0 : 18.0)
        let t = N + ((base - longitudeHour) / 24.0)
        let M = (0.9856 * t) - 3.289
        var L = M + (1.916 * sinDeg(M)) + (0.02 * sinDeg(2 * M)) + 282.634
        L = normalizeDegrees(L)
        var RA = atan(0.91764 * tanDeg(L)) * 180 / .pi
        RA = normalizeDegrees(RA)
        let Lquadrant = floor(L / 90.0) * 90.0
        let RAquadrant = floor(RA / 90.0) * 90.0
        RA = RA + (Lquadrant - RAquadrant)
        RA /= 15.0
        
        let sinDec = 0.39782 * sinDeg(L)
        let cosDec = cos(asin(sinDec))
        let cosH = (cosDeg(zenith) - (sinDec * sinDeg(coordinate.latitude))) / (cosDec * cosDeg(coordinate.latitude))
        if cosH > 1 || cosH < -1 {
            return nil
        }
        
        var H = event == .sunrise ? 360.0 - acosDeg(cosH) : acosDeg(cosH)
        H /= 15.0
        let T = H + RA - (0.06571 * t) - 6.622
        var UT = T - longitudeHour
        UT = normalizeHours(UT)
        
        // UT is in UTC time - convert to hours, minutes, seconds
        let utcHour = Int(UT)
        let minute = Int((UT - Double(utcHour)) * 60.0)
        let second = Int((((UT - Double(utcHour)) * 60.0) - Double(minute)) * 60.0)
        
        // Convert UTC time to local time by adding timezone offset
        let localOffsetSeconds = timeZone.secondsFromGMT(for: date)
        let localOffsetHours = Double(localOffsetSeconds) / 3600.0
        
        // Add offset to convert UTC to local time
        var localHours = Double(utcHour) + localOffsetHours
        
        // Handle day overflow
        var dayOffset = 0
        if localHours < 0 {
            localHours += 24
            dayOffset = -1
        } else if localHours >= 24 {
            localHours -= 24
            dayOffset = 1
        }
        
        let hour = Int(localHours)
        
        // Get year/month/day from the input date and apply day offset
        var adjustedDate = date
        if dayOffset != 0 {
            adjustedDate = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }
        
        var components = calendar.dateComponents([.year, .month, .day], from: adjustedDate)
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = 0
        
        return calendar.date(from: components)
    }
    
    private static func sinDeg(_ degrees: Double) -> Double {
        sin(degrees * .pi / 180.0)
    }
    
    private static func cosDeg(_ degrees: Double) -> Double {
        cos(degrees * .pi / 180.0)
    }
    
    private static func tanDeg(_ degrees: Double) -> Double {
        tan(degrees * .pi / 180.0)
    }
    
    private static func acosDeg(_ value: Double) -> Double {
        acos(value) * 180.0 / .pi
    }
    
    private static func normalizeDegrees(_ value: Double) -> Double {
        var angle = value.truncatingRemainder(dividingBy: 360.0)
        if angle < 0 { angle += 360.0 }
        return angle
    }
    
    private static func normalizeHours(_ value: Double) -> Double {
        var hourValue = value.truncatingRemainder(dividingBy: 24.0)
        if hourValue < 0 { hourValue += 24.0 }
        return hourValue
    }
}

private struct SolarCacheKey: Hashable {
    let event: SolarEvent
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String
    let date: Date
    let offsetMinutes: SolarTrigger.EventOffset
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(event)
        hasher.combine(Int(coordinate.latitude * 1000))
        hasher.combine(Int(coordinate.longitude * 1000))
        hasher.combine(timeZoneIdentifier)
        hasher.combine(date.timeIntervalSince1970)
        switch offsetMinutes {
        case .minutes(let value):
            hasher.combine(value)
        }
    }
    
    static func == (lhs: SolarCacheKey, rhs: SolarCacheKey) -> Bool {
        lhs.event == rhs.event &&
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.0005 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.0005 &&
        lhs.timeZoneIdentifier == rhs.timeZoneIdentifier &&
        lhs.date == rhs.date &&
        lhs.offsetMinutes == rhs.offsetMinutes
    }
}
