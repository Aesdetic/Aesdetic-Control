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
    private let maxDeletesPerPass = 1
    // Emulate WLED UI-like manual deletion cadence: one preset-store mutation, then wait.
    private let userPacedPresetStoreDeleteIntervalSeconds: TimeInterval = 2.0
    private let largePresetStoreDeleteIntervalSeconds: TimeInterval = 3.5
    private let veryLargePresetStoreDeleteIntervalSeconds: TimeInterval = 6.0
    private let largePresetStoreByteThreshold = 300_000
    private let veryLargePresetStoreByteThreshold = 800_000
    private let presetStoreSizePressureCacheTTL: TimeInterval = 10 * 60
    // Preset/playlist filesystem mutations are heavier than timer mutations.
    // Use a slightly slower cadence to reduce presets-store write pressure.
    private let interPresetStoreDeleteDelayNanoseconds: UInt64 = 2_000_000_000
    private let interTimerDeleteDelayNanoseconds: UInt64 = 180_000_000
    private let unreadablePresetStoreBaseBackoffSeconds: TimeInterval = 20.0
    private let unreadablePresetStoreMaxBackoffSeconds: TimeInterval = 180.0
    private var lastDeleteAttemptAtByCadenceKey: [String: Date] = [:]
    private var activeDeleteLeaseByDeviceId: Set<String> = []
    private var presetStoreUnreadableBackoffUntilByDeviceId: [String: Date] = [:]
    private var presetStoreUnreadableStreakByDeviceId: [String: Int] = [:]
    private var presetStoreSizePressureByDeviceId: [String: (bytes: Int, checkedAt: Date)] = [:]

    private struct DeleteAttemptOutcome {
        let succeededIds: [Int]
        let failedIds: [Int]
        let lastError: String?
        let wasDeferred: Bool

        var isSuccess: Bool { failedIds.isEmpty }
        var madeProgress: Bool { !succeededIds.isEmpty }
    }

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
        verificationRequired: Bool = false,
        notBefore: Date? = nil
    ) {
        guard cleanupEnabled else { return }
        let uniqueIds = Array(Set(ids)).sorted()
        guard !uniqueIds.isEmpty else { return }
        let requestedNextAttemptAt = notBefore ?? Date()
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
            let existingNextAttemptAt = pendingDeletes[index].nextAttemptAt ?? requestedNextAttemptAt
            let hasDeferredCooldown =
                pendingDeletes[index].lastError?.hasPrefix("Deferred:") == true
                && existingNextAttemptAt > Date()
            pendingDeletes[index].nextAttemptAt = hasDeferredCooldown
                ? existingNextAttemptAt
                : min(existingNextAttemptAt, requestedNextAttemptAt)
            pendingDeletes[index].verificationRequired = pendingDeletes[index].verificationRequired || verificationRequired
            if !hasDeferredCooldown {
                pendingDeletes[index].lastError = nil
            }
            save()
            logger.info("Merged \(type.rawValue) deletion for device \(deviceId): \(mergedIds)")
            return
        }
        let delete = PendingDeviceDelete(
            type: type,
            deviceId: deviceId,
            ids: uniqueIds,
            nextAttemptAt: requestedNextAttemptAt,
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
        // Preset/playlist mutations are the riskiest operations for presets.json integrity.
        // Always route them through the queue so they run one-at-a-time with pacing.
        if type == .preset || type == .playlist {
            enqueue(
                type: type,
                deviceId: device.id,
                ids: uniqueIds,
                source: source,
                leaseId: leaseId,
                verificationRequired: verificationRequired
            )
            if device.isOnline {
                await processQueue(for: device.id)
            }
            return
        }
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
            // Serialize immediate deletes with queued deletes for the same device.
            // Without this lease, re-entrant MainActor execution can run queue + immediate
            // attempts at the same time and double-hit the same IDs.
            guard tryAcquireDeleteLease(deviceId: device.id, context: "requestDelete_immediate") else {
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
            defer { releaseDeleteLease(deviceId: device.id, context: "requestDelete_immediate") }

            let outcome = await attemptDelete(
                type: type,
                device: device,
                ids: uniqueIds,
                context: "requestDelete_immediate"
            )
            if outcome.isSuccess {
                // Remove any queued entries that overlap these ids (across all sources).
                removeIds(type: type, deviceId: device.id, ids: uniqueIds)
                return
            }
            if outcome.madeProgress {
                removeIds(type: type, deviceId: device.id, ids: outcome.succeededIds)
                let remaining = uniqueIds.filter { !Set(outcome.succeededIds).contains($0) }
                if !remaining.isEmpty {
                    enqueue(
                        type: type,
                        deviceId: device.id,
                        ids: remaining,
                        source: source,
                        leaseId: leaseId,
                        verificationRequired: verificationRequired
                    )
                    return
                }
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
        guard tryAcquireDeleteLease(deviceId: deviceId, context: "processQueue") else {
            return
        }
        defer { releaseDeleteLease(deviceId: deviceId, context: "processQueue") }
        guard let device = await getDevice(id: deviceId) else { return }
        guard device.isOnline else { return }
        let now = Date()
        let pendingForDevice = self.pendingDeletes
            .filter {
                $0.deviceId == deviceId
                    && $0.deadLetteredAt == nil
                    && (($0.nextAttemptAt ?? .distantPast) <= now)
            }
            .sorted { lhs, rhs in
                let leftPriority = deleteTypePriority(lhs)
                let rightPriority = deleteTypePriority(rhs)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return lhs.createdAt < rhs.createdAt
            }
        guard !pendingForDevice.isEmpty else { return }
        
        logger.info("Processing \(pendingForDevice.count) pending deletions for device \(deviceId)")
        var processedCount = 0
        for delete in pendingForDevice {
            if processedCount >= maxDeletesPerPass {
                logger.info("cleanup.queue_pass_limited device=\(deviceId, privacy: .public) processed=\(processedCount, privacy: .public) pending=\(pendingForDevice.count, privacy: .public)")
                break
            }
            if let unreadableBackoffUntil = unreadablePresetStoreBackoffUntil(for: delete),
               unreadableBackoffUntil > Date() {
                if let index = self.pendingDeletes.firstIndex(where: { $0.id == delete.id }) {
                    self.pendingDeletes[index].lastAttempt = Date()
                    self.pendingDeletes[index].lastError = "Deferred: preset-store unreadable backoff is active"
                    self.pendingDeletes[index].nextAttemptAt = unreadableBackoffUntil
                    self.save()
                }
                logger.warning(
                    "cleanup.queue_deferred_unreadable_backoff device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) nextAttemptAt=\(unreadableBackoffUntil.ISO8601Format(), privacy: .public)"
                )
                continue
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
            logger.info(
                "cleanup.queue_attempt device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) ids=\(delete.ids, privacy: .public) retries=\(delete.retries, privacy: .public) lastError=\((delete.lastError ?? "none"), privacy: .public)"
            )
            let idsToAttempt = Array(delete.ids.prefix(maxIdsPerAttempt(for: delete.type)))
            if idsToAttempt.count < delete.ids.count {
                logger.info(
                    "cleanup.queue_chunked device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) attempting=\(idsToAttempt, privacy: .public) remaining=\(delete.ids.count - idsToAttempt.count, privacy: .public)"
                )
            }
            let outcome = await attemptDelete(
                type: delete.type,
                device: device,
                ids: idsToAttempt,
                context: "queue:\(delete.id.uuidString)"
            )
            if let index = self.pendingDeletes.firstIndex(where: { $0.id == delete.id }) {
                var entry = self.pendingDeletes[index]
                let succeeded = Set(outcome.succeededIds)
                if !succeeded.isEmpty {
                    entry.ids = entry.ids.filter { !succeeded.contains($0) }
                }
                entry.lastAttempt = Date()

                if entry.ids.isEmpty {
                    self.pendingDeletes.remove(at: index)
                    self.save()
                    logger.info("Successfully processed \(delete.type.rawValue) deletion for device \(deviceId)")
                } else if outcome.isSuccess {
                    // Chunk succeeded but entry still has IDs; continue in staged passes.
                    entry.lastError = nil
                    if entry.type == .preset || entry.type == .playlist {
                        let delay = await presetStoreDeleteCadenceSeconds(for: device)
                        entry.nextAttemptAt = Date().addingTimeInterval(delay)
                    } else {
                        entry.nextAttemptAt = Date()
                    }
                    self.pendingDeletes[index] = entry
                    self.save()
                } else {
                    entry.lastError = outcome.lastError ?? "Delete failed"
                    if !outcome.madeProgress && !outcome.wasDeferred && !outcome.failedIds.isEmpty {
                        let failedSet = Set(outcome.failedIds)
                        let nonFailed = entry.ids.filter { !failedSet.contains($0) }
                        let failedInOrder = entry.ids.filter { failedSet.contains($0) }
                        if !nonFailed.isEmpty && !failedInOrder.isEmpty {
                            entry.ids = nonFailed + failedInOrder
                            logger.warning(
                                "cleanup.queue_rotate_failed_tail device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) failed=\(failedInOrder, privacy: .public)"
                            )
                        }
                    }
                    if !outcome.madeProgress && !outcome.wasDeferred {
                        entry.retries += 1
                    }
                    let retryAttempt: Int
                    if outcome.madeProgress || outcome.wasDeferred {
                        retryAttempt = 1
                    } else {
                        retryAttempt = max(1, entry.retries)
                    }
                    let deferredRetryDelaySeconds: TimeInterval = {
                        let message = outcome.lastError?.lowercased() ?? ""
                        if message.contains("preset-store unreadable") {
                            return min(60.0, max(20.0, self.retryDelay(forAttempt: entry.retries + 2)))
                        }
                        if message.contains("mutation guard is active") {
                            return min(24.0, max(10.0, self.retryDelay(forAttempt: entry.retries + 1)))
                        }
                        return min(20.0, max(8.0, self.retryDelay(forAttempt: entry.retries + 1)))
                    }()
                    let retryDelaySeconds: TimeInterval = outcome.wasDeferred
                        ? deferredRetryDelaySeconds
                        : self.retryDelay(forAttempt: retryAttempt)
                    var nextAttemptAt = Date().addingTimeInterval(retryDelaySeconds)
                    if let unreadableBackoffUntil = unreadablePresetStoreBackoffUntil(for: delete),
                       unreadableBackoffUntil > nextAttemptAt {
                        nextAttemptAt = unreadableBackoffUntil
                    }
                    entry.nextAttemptAt = nextAttemptAt
                    logger.warning(
                        "cleanup.queue_retry_scheduled device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) retries=\(entry.retries, privacy: .public) wasDeferred=\(outcome.wasDeferred, privacy: .public) madeProgress=\(outcome.madeProgress, privacy: .public) failedIds=\(outcome.failedIds, privacy: .public) nextAttemptAt=\(nextAttemptAt.ISO8601Format(), privacy: .public) reason=\((entry.lastError ?? "Delete failed"), privacy: .public)"
                    )

                    if !outcome.madeProgress && !outcome.wasDeferred && entry.retries >= self.maxAttempts {
                        if delete.type == .timer || delete.source == .automation {
                            // Timer cleanup controls automation re-import safety. Automation-sourced
                            // asset cleanup should also keep retrying so managed resources are not
                            // permanently stranded in dead-letter.
                            entry.retries = self.maxAttempts - 1
                            entry.nextAttemptAt = Date().addingTimeInterval(self.retryDelay(forAttempt: self.maxAttempts))
                            logger.warning(
                                "Max attempts exceeded for \(delete.type.rawValue) deletion \(delete.id), source=\(delete.source.rawValue, privacy: .public), keeping queued with capped backoff"
                            )
                        } else {
                            logger.warning("Max attempts exceeded for \(delete.type.rawValue) deletion \(delete.id), moving to dead-letter")
                            entry.deadLetteredAt = Date()
                            entry.nextAttemptAt = nil
                        }
                    }
                    self.pendingDeletes[index] = entry
                    self.save()
                }
            }
            processedCount += 1
            if processedCount < maxDeletesPerPass {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func presetStoreDeleteCadenceSeconds(for device: WLEDDevice) async -> TimeInterval {
        let now = Date()
        if let cached = presetStoreSizePressureByDeviceId[device.id],
           now.timeIntervalSince(cached.checkedAt) < presetStoreSizePressureCacheTTL {
            return presetStoreDeleteCadenceSeconds(forPresetStoreBytes: cached.bytes)
        }

        guard let byteCount = await WLEDAPIService.shared.fetchPresetStoreByteCount(device: device) else {
            return userPacedPresetStoreDeleteIntervalSeconds
        }

        presetStoreSizePressureByDeviceId[device.id] = (bytes: byteCount, checkedAt: now)
        let cadence = presetStoreDeleteCadenceSeconds(forPresetStoreBytes: byteCount)
        if cadence > userPacedPresetStoreDeleteIntervalSeconds {
            logger.info(
                "cleanup.queue_large_preset_store_cadence device=\(device.id, privacy: .public) bytes=\(byteCount, privacy: .public) cadence=\(cadence, privacy: .public)"
            )
        }
        return cadence
    }

    private func presetStoreDeleteCadenceSeconds(forPresetStoreBytes byteCount: Int) -> TimeInterval {
        if byteCount >= veryLargePresetStoreByteThreshold {
            return veryLargePresetStoreDeleteIntervalSeconds
        }
        if byteCount >= largePresetStoreByteThreshold {
            return largePresetStoreDeleteIntervalSeconds
        }
        return userPacedPresetStoreDeleteIntervalSeconds
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

    /// Drain queued deletes for a device in the current online session.
    /// Useful after automation delete so step-preset cleanup does not get stranded
    /// behind maxDeletesPerPass throttling.
    func processQueueUntilIdle(for deviceId: String, maxPasses: Int = 4) async {
        guard cleanupEnabled else { return }
        let passLimit = max(1, maxPasses)
        for pass in 1...passLimit {
            let beforeEntries = pendingDeletes.filter {
                $0.deviceId == deviceId && $0.deadLetteredAt == nil
            }.count
            let beforeIds = activeDeleteIdCount(deviceId: deviceId)
            guard beforeEntries > 0, beforeIds > 0 else {
                logger.info("cleanup.queue_drain_complete device=\(deviceId, privacy: .public) pass=\(pass, privacy: .public) remaining=0")
                return
            }

            await processQueue(for: deviceId)

            let afterEntries = pendingDeletes.filter {
                $0.deviceId == deviceId && $0.deadLetteredAt == nil
            }.count
            let afterIds = activeDeleteIdCount(deviceId: deviceId)
            logger.info(
                "cleanup.queue_drain_pass device=\(deviceId, privacy: .public) pass=\(pass, privacy: .public) beforeEntries=\(beforeEntries, privacy: .public) afterEntries=\(afterEntries, privacy: .public) beforeIds=\(beforeIds, privacy: .public) afterIds=\(afterIds, privacy: .public)"
            )
            if afterEntries == 0 || afterIds == 0 {
                return
            }

            if let nextAttemptAt = earliestNextAttemptAt(deviceId: deviceId), nextAttemptAt > Date() {
                let remaining = nextAttemptAt.timeIntervalSinceNow
                if remaining > 30.0 {
                    logger.info(
                        "cleanup.queue_drain_waiting_future_retry device=\(deviceId, privacy: .public) pass=\(pass, privacy: .public) nextAttemptAt=\(nextAttemptAt.ISO8601Format(), privacy: .public)"
                    )
                    return
                }
                logger.info(
                    "cleanup.queue_drain_waiting_short_retry device=\(deviceId, privacy: .public) pass=\(pass, privacy: .public) seconds=\(remaining, privacy: .public) nextAttemptAt=\(nextAttemptAt.ISO8601Format(), privacy: .public)"
                )
                let waitSeconds = max(0.15, remaining)
                let waitNs = UInt64(waitSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: waitNs)
                continue
            }

            let delayNs: UInt64 = afterIds < beforeIds ? 250_000_000 : 500_000_000
            try? await Task.sleep(nanoseconds: delayNs)
        }
    }
    
    /// Attempt to process a single deletion
    private func attemptDelete(
        type: PendingDeviceDelete.DeleteType,
        device: WLEDDevice,
        ids: [Int],
        context: String
    ) async -> DeleteAttemptOutcome {
        logger.info("cleanup.delete.begin device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) ids=\(ids, privacy: .public) context=\(context, privacy: .public)")
        var succeeded: [Int] = []
        var failed: [Int] = []
        var lastError: String?

        for id in ids {
            do {
                await enforceDeleteCadence(for: type, deviceId: device.id)
                let success: Bool
                switch type {
                case .preset:
                    success = try await WLEDAPIService.shared.deletePreset(id: id, device: device)
                case .playlist:
                    success = try await WLEDAPIService.shared.deletePlaylist(id: id, device: device)
                case .timer:
                    #if DEBUG
                    if let before = try? await WLEDAPIService.shared.fetchTimers(for: device).first(where: { $0.id == id }) {
                        print("cleanup.timer.delete.before device=\(device.id) slot=\(id) en=\(before.enabled) hour=\(before.hour) min=\(before.minute) dow=\(before.days) macro=\(before.macroId)")
                    }
                    #endif
                    success = try await WLEDAPIService.shared.disableTimer(slot: id, device: device)
                    #if DEBUG
                    if let after = try? await WLEDAPIService.shared.fetchTimers(for: device).first(where: { $0.id == id }) {
                        print("cleanup.timer.delete.after device=\(device.id) slot=\(id) en=\(after.enabled) hour=\(after.hour) min=\(after.minute) dow=\(after.days) macro=\(after.macroId)")
                    }
                    #endif
                }
                if success {
                    succeeded.append(id)
                    if type == .preset || type == .playlist {
                        clearPresetStoreUnreadableBackoffIfNeeded(deviceId: device.id)
                    }
                    logger.info("cleanup.delete.item_ok device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public)")
                } else {
                    failed.append(id)
                    lastError = "delete returned unsuccessful status for id \(id)"
                    logger.error("cleanup.delete.item_failed device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public)")
                    break
                }
            } catch let apiError as WLEDAPIError {
                failed.append(id)
                if case .presetStoreUnreadable(let reason) = apiError {
                    let backoffUntil = registerPresetStoreUnreadableBackoff(deviceId: device.id)
                    lastError = "Deferred: preset-store unreadable (\(reason)); backoff_until=\(backoffUntil.ISO8601Format())"
                    logger.warning(
                        "cleanup.delete.deferred_unreadable_store device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public) backoffUntil=\(backoffUntil.ISO8601Format(), privacy: .public) reason=\(reason, privacy: .public)"
                    )
                } else {
                    lastError = apiError.localizedDescription
                    logger.error("cleanup.delete.error device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public) error=\(apiError.localizedDescription, privacy: .public)")
                }
                break
            } catch {
                failed.append(id)
                lastError = error.localizedDescription
                logger.error("cleanup.delete.error device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                break
            }

            if id != ids.last {
                let interDeleteDelayNanoseconds: UInt64
                switch type {
                case .preset, .playlist:
                    interDeleteDelayNanoseconds = interPresetStoreDeleteDelayNanoseconds
                case .timer:
                    interDeleteDelayNanoseconds = interTimerDeleteDelayNanoseconds
                }
                try? await Task.sleep(nanoseconds: interDeleteDelayNanoseconds)
            }
        }

        return DeleteAttemptOutcome(
            succeededIds: succeeded,
            failedIds: failed,
            lastError: lastError,
            wasDeferred: lastError?.hasPrefix("Deferred:") == true
        )
    }

    private func cadenceKey(for type: PendingDeviceDelete.DeleteType, deviceId: String) -> String {
        switch type {
        case .preset, .playlist:
            // Preset + playlist share the same underlying presets-store write path.
            return "preset-store:\(deviceId)"
        case .timer:
            return "timer:\(deviceId)"
        }
    }

    private func unreadablePresetStoreBackoffUntil(for delete: PendingDeviceDelete) -> Date? {
        guard delete.type == .preset || delete.type == .playlist else { return nil }
        guard let until = presetStoreUnreadableBackoffUntilByDeviceId[delete.deviceId] else { return nil }
        if until <= Date() {
            presetStoreUnreadableBackoffUntilByDeviceId.removeValue(forKey: delete.deviceId)
            presetStoreUnreadableStreakByDeviceId.removeValue(forKey: delete.deviceId)
            return nil
        }
        return until
    }

    private func registerPresetStoreUnreadableBackoff(deviceId: String) -> Date {
        let streak = (presetStoreUnreadableStreakByDeviceId[deviceId] ?? 0) + 1
        presetStoreUnreadableStreakByDeviceId[deviceId] = streak
        let exponent = max(0, min(4, streak - 1))
        let delay = min(
            unreadablePresetStoreMaxBackoffSeconds,
            unreadablePresetStoreBaseBackoffSeconds * pow(2.0, Double(exponent))
        )
        let backoffUntil = Date().addingTimeInterval(delay)
        presetStoreUnreadableBackoffUntilByDeviceId[deviceId] = backoffUntil
        return backoffUntil
    }

    private func clearPresetStoreUnreadableBackoffIfNeeded(deviceId: String) {
        presetStoreUnreadableBackoffUntilByDeviceId.removeValue(forKey: deviceId)
        presetStoreUnreadableStreakByDeviceId.removeValue(forKey: deviceId)
    }

    private func cadenceIntervalSeconds(for type: PendingDeviceDelete.DeleteType) -> TimeInterval {
        switch type {
        case .preset, .playlist:
            return TimeInterval(interPresetStoreDeleteDelayNanoseconds) / 1_000_000_000.0
        case .timer:
            return TimeInterval(interTimerDeleteDelayNanoseconds) / 1_000_000_000.0
        }
    }

    private func enforceDeleteCadence(
        for type: PendingDeviceDelete.DeleteType,
        deviceId: String
    ) async {
        let key = cadenceKey(for: type, deviceId: deviceId)
        let minimumInterval = cadenceIntervalSeconds(for: type)
        if let previous = lastDeleteAttemptAtByCadenceKey[key] {
            let elapsed = Date().timeIntervalSince(previous)
            if elapsed < minimumInterval {
                let remaining = minimumInterval - elapsed
                let sleepNanoseconds = UInt64((remaining * 1_000_000_000.0).rounded())
                if sleepNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: sleepNanoseconds)
                }
            }
        }
        lastDeleteAttemptAtByCadenceKey[key] = Date()
    }

    private func tryAcquireDeleteLease(deviceId: String, context: String) -> Bool {
        guard !activeDeleteLeaseByDeviceId.contains(deviceId) else {
            logger.info(
                "cleanup.delete.lease_busy device=\(deviceId, privacy: .public) context=\(context, privacy: .public)"
            )
            return false
        }
        activeDeleteLeaseByDeviceId.insert(deviceId)
        logger.debug(
            "cleanup.delete.lease_acquired device=\(deviceId, privacy: .public) context=\(context, privacy: .public)"
        )
        return true
    }

    private func releaseDeleteLease(deviceId: String, context: String) {
        activeDeleteLeaseByDeviceId.remove(deviceId)
        logger.debug(
            "cleanup.delete.lease_released device=\(deviceId, privacy: .public) context=\(context, privacy: .public)"
        )
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

    func hasPendingDeletes(
        source: PendingDeviceDelete.DeleteSource? = nil,
        deviceId: String? = nil,
        includeDeadLetter: Bool = false
    ) -> Bool {
        pendingDeletes.contains { item in
            guard includeDeadLetter || item.deadLetteredAt == nil else { return false }
            guard deviceId == nil || item.deviceId == deviceId else { return false }
            guard source == nil || item.source == source else { return false }
            return !item.ids.isEmpty
        }
    }

    func hasPendingPresetStoreDeletes(
        deviceId: String? = nil,
        includeDeadLetter: Bool = false
    ) -> Bool {
        pendingDeletes.contains { item in
            guard includeDeadLetter || item.deadLetteredAt == nil else { return false }
            guard deviceId == nil || item.deviceId == deviceId else { return false }
            guard item.type == .preset || item.type == .playlist else { return false }
            return !item.ids.isEmpty
        }
    }

    func isDeleteLeaseActive(deviceId: String) -> Bool {
        activeDeleteLeaseByDeviceId.contains(deviceId)
    }

    func pendingDeleteDeviceIds(
        source: PendingDeviceDelete.DeleteSource? = nil,
        includeDeadLetter: Bool = false
    ) -> Set<String> {
        Set(
            pendingDeletes.compactMap { item -> String? in
                guard includeDeadLetter || item.deadLetteredAt == nil else { return nil }
                guard source == nil || item.source == source else { return nil }
                guard !item.ids.isEmpty else { return nil }
                return item.deviceId
            }
        )
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

    /// Move scoped preset/playlist cleanup IDs into dead-letter state.
    /// This is used for unreadable preset-store hard-stops to prevent repeated write attempts.
    @discardableResult
    func deadLetterPresetStoreDeletes(
        deviceId: String,
        source: PendingDeviceDelete.DeleteSource? = nil,
        presetIds: Set<Int> = [],
        playlistIds: Set<Int> = [],
        reason: String
    ) -> Int {
        let now = Date()
        var changed = false
        var deadLetteredCount = 0
        var spawnedDeadLetters: [PendingDeviceDelete] = []
        var unmatchedPresetIds = presetIds
        var unmatchedPlaylistIds = playlistIds

        for index in pendingDeletes.indices.reversed() {
            let entry = pendingDeletes[index]
            guard entry.deviceId == deviceId else { continue }
            guard entry.deadLetteredAt == nil else { continue }
            if let source, entry.source != source { continue }
            guard entry.type == .preset || entry.type == .playlist else { continue }

            let scopedIds: Set<Int> = {
                switch entry.type {
                case .preset:
                    return presetIds
                case .playlist:
                    return playlistIds
                case .timer:
                    return []
                }
            }()

            let entryIdSet = Set(entry.ids)
            let matchedIds = scopedIds.isEmpty
                ? entryIdSet
                : entryIdSet.intersection(scopedIds)
            guard !matchedIds.isEmpty else { continue }
            if entry.type == .preset {
                unmatchedPresetIds.subtract(matchedIds)
            } else if entry.type == .playlist {
                unmatchedPlaylistIds.subtract(matchedIds)
            }

            changed = true
            let matchedInEntryOrder = entry.ids.filter { matchedIds.contains($0) }
            let remaining = entry.ids.filter { !matchedIds.contains($0) }

            if remaining.isEmpty {
                pendingDeletes[index].deadLetteredAt = now
                pendingDeletes[index].lastAttempt = now
                pendingDeletes[index].nextAttemptAt = nil
                pendingDeletes[index].lastError = reason
            } else {
                pendingDeletes[index].ids = remaining
                pendingDeletes[index].lastAttempt = now
                pendingDeletes[index].lastError = "Scoped IDs moved to dead-letter: \(reason)"

                let deadLetter = PendingDeviceDelete(
                    type: entry.type,
                    deviceId: entry.deviceId,
                    ids: matchedInEntryOrder,
                    retries: entry.retries,
                    lastAttempt: now,
                    nextAttemptAt: nil,
                    lastError: reason,
                    source: entry.source,
                    leaseId: entry.leaseId,
                    verificationRequired: entry.verificationRequired,
                    deadLetteredAt: now,
                    createdAt: entry.createdAt
                )
                spawnedDeadLetters.append(deadLetter)
            }

            deadLetteredCount += matchedInEntryOrder.count
        }

        if !presetIds.isEmpty && !unmatchedPresetIds.isEmpty {
            spawnedDeadLetters.append(
                PendingDeviceDelete(
                    type: .preset,
                    deviceId: deviceId,
                    ids: Array(unmatchedPresetIds).sorted(),
                    retries: 0,
                    lastAttempt: now,
                    nextAttemptAt: nil,
                    lastError: reason,
                    source: source ?? .unknown,
                    leaseId: nil,
                    verificationRequired: true,
                    deadLetteredAt: now,
                    createdAt: now
                )
            )
            deadLetteredCount += unmatchedPresetIds.count
            changed = true
        }

        if !playlistIds.isEmpty && !unmatchedPlaylistIds.isEmpty {
            spawnedDeadLetters.append(
                PendingDeviceDelete(
                    type: .playlist,
                    deviceId: deviceId,
                    ids: Array(unmatchedPlaylistIds).sorted(),
                    retries: 0,
                    lastAttempt: now,
                    nextAttemptAt: nil,
                    lastError: reason,
                    source: source ?? .unknown,
                    leaseId: nil,
                    verificationRequired: true,
                    deadLetteredAt: now,
                    createdAt: now
                )
            )
            deadLetteredCount += unmatchedPlaylistIds.count
            changed = true
        }

        if !spawnedDeadLetters.isEmpty {
            pendingDeletes.append(contentsOf: spawnedDeadLetters)
        }
        if changed {
            save()
            logger.warning(
                "cleanup.dead_lettered_preset_store device=\(deviceId, privacy: .public) count=\(deadLetteredCount, privacy: .public) reason=\(reason, privacy: .public)"
            )
        }
        return deadLetteredCount
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

    private func maxIdsPerAttempt(for type: PendingDeviceDelete.DeleteType) -> Int {
        switch type {
        case .preset:
            return 1
        case .playlist, .timer:
            return 1
        }
    }

    private func deleteTypePriority(_ delete: PendingDeviceDelete) -> Int {
        switch delete.type {
        case .timer:
            return 0
        case .playlist:
            return 1
        case .preset:
            return 2
        }
    }

    private func activeDeleteIdCount(deviceId: String) -> Int {
        pendingDeletes
            .filter { $0.deviceId == deviceId && $0.deadLetteredAt == nil }
            .reduce(0) { $0 + $1.ids.count }
    }

    private func earliestNextAttemptAt(deviceId: String) -> Date? {
        pendingDeletes
            .filter { $0.deviceId == deviceId && $0.deadLetteredAt == nil }
            .compactMap(\.nextAttemptAt)
            .min()
    }
}
