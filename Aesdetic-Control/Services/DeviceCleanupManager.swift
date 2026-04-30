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
    private let maxPresetStoreDeleteAttempts = 3
    private let cleanupEnabled = true
    private let maxDeletesPerPass = 1
    // Keep a single fixed cadence for WLED-style one-by-one preset-store deletes.
    private let interPresetStoreDeleteDelayNanoseconds: UInt64 = 1_200_000_000
    private let interTimerDeleteDelayNanoseconds: UInt64 = 180_000_000
    private var lastDeleteAttemptAtByCadenceKey: [String: Date] = [:]
    private var activeDeleteLeaseByDeviceId: Set<String> = []

    private struct DeleteAttemptOutcome {
        let succeededIds: [Int]
        let failedIds: [Int]
        let lastError: String?
        let terminalAPIError: WLEDAPIError?

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
        if type == .timer && source == .automation {
            logger.warning(
                "cleanup.timer.raw_queue_rejected device=\(deviceId, privacy: .public) ids=\(ids, privacy: .public) reason=automation_timer_slots_require_live_ownership_proof"
            )
            return
        }
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
            pendingDeletes[index].nextAttemptAt = min(existingNextAttemptAt, requestedNextAttemptAt)
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
            nextAttemptAt: requestedNextAttemptAt,
            source: source,
            leaseId: leaseId,
            verificationRequired: verificationRequired
        )
        pendingDeletes.append(delete)
        save()
        logger.info("Enqueued \(type.rawValue) deletion for device \(deviceId): \(uniqueIds)")
    }

    func enqueuePresetStoreDelete(
        deviceId: String,
        playlistIds: [Int],
        presetIds: [Int],
        source: PendingDeviceDelete.DeleteSource = .unknown,
        leaseId: UUID? = nil,
        verificationRequired: Bool = false,
        notBefore: Date? = nil
    ) {
        guard cleanupEnabled else { return }
        let normalizedPlaylistIds = Array(Set(playlistIds.filter { (1...250).contains($0) })).sorted()
        let normalizedPresetIds = Array(Set(presetIds.filter { (1...250).contains($0) })).sorted()
        let combinedIds = Array(Set(normalizedPlaylistIds + normalizedPresetIds)).sorted()
        guard !combinedIds.isEmpty else { return }
        let requestedNextAttemptAt = notBefore ?? Date()

        if let index = pendingDeletes.firstIndex(where: {
            $0.type == .presetStore
                && $0.deviceId == deviceId
                && $0.source == source
                && $0.leaseId == leaseId
                && $0.deadLetteredAt == nil
        }) {
            let mergedPlaylistIds = Array(Set((pendingDeletes[index].playlistIds ?? []) + normalizedPlaylistIds)).sorted()
            let mergedPresetIds = Array(Set((pendingDeletes[index].presetIds ?? []) + normalizedPresetIds)).sorted()
            pendingDeletes[index].playlistIds = mergedPlaylistIds
            pendingDeletes[index].presetIds = mergedPresetIds
            pendingDeletes[index].ids = Array(Set(mergedPlaylistIds + mergedPresetIds)).sorted()
            pendingDeletes[index].lastAttempt = Date()
            let existingNextAttemptAt = pendingDeletes[index].nextAttemptAt ?? requestedNextAttemptAt
            pendingDeletes[index].nextAttemptAt = min(existingNextAttemptAt, requestedNextAttemptAt)
            pendingDeletes[index].verificationRequired = pendingDeletes[index].verificationRequired || verificationRequired
            pendingDeletes[index].lastError = nil
            save()
            logger.info(
                "Merged preset-store deletion for device \(deviceId): playlists=\(mergedPlaylistIds) presets=\(mergedPresetIds)"
            )
            return
        }

        let delete = PendingDeviceDelete(
            type: .presetStore,
            deviceId: deviceId,
            ids: combinedIds,
            nextAttemptAt: requestedNextAttemptAt,
            source: source,
            leaseId: leaseId,
            verificationRequired: verificationRequired,
            playlistIds: normalizedPlaylistIds,
            presetIds: normalizedPresetIds
        )
        pendingDeletes.append(delete)
        save()
        logger.info(
            "Enqueued preset-store deletion for device \(deviceId): playlists=\(normalizedPlaylistIds) presets=\(normalizedPresetIds)"
        )
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
        if type == .timer && source == .automation {
            logger.warning(
                "cleanup.timer.raw_request_rejected device=\(device.id, privacy: .public) ids=\(uniqueIds, privacy: .public) reason=automation_timer_slots_require_live_ownership_proof"
            )
            return
        }
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
            logger.info(
                "cleanup.queue_attempt device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) ids=\(delete.ids, privacy: .public) retries=\(delete.retries, privacy: .public) lastError=\((delete.lastError ?? "none"), privacy: .public)"
            )
            let idsToAttempt = delete.type == .presetStore
                ? delete.ids
                : Array(delete.ids.prefix(maxIdsPerAttempt(for: delete.type)))
            if idsToAttempt.count < delete.ids.count {
                logger.info(
                    "cleanup.queue_chunked device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) attempting=\(idsToAttempt, privacy: .public) remaining=\(delete.ids.count - idsToAttempt.count, privacy: .public)"
                )
            }
            let outcome: DeleteAttemptOutcome
            if delete.type == .presetStore {
                outcome = await attemptPresetStoreRewriteDelete(
                    playlistIds: delete.playlistIds ?? [],
                    presetIds: delete.presetIds ?? [],
                    device: device,
                    context: "queue:\(delete.id.uuidString)"
                )
            } else {
                outcome = await attemptDelete(
                    type: delete.type,
                    device: device,
                    ids: idsToAttempt,
                    context: "queue:\(delete.id.uuidString)"
                )
            }
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
                    entry.nextAttemptAt = Date()
                    self.pendingDeletes[index] = entry
                    self.save()
                } else {
                    if let unreadableReason = presetStoreUnreadableHardStopReason(
                        for: outcome,
                        type: delete.type
                    ) {
                        let reason = "Preset-store unreadable hard-stop: \(unreadableReason)"
                        let presetIds: Set<Int> = {
                            if delete.type == .preset { return Set(entry.ids) }
                            if delete.type == .presetStore { return Set(entry.presetIds ?? []) }
                            return []
                        }()
                        let playlistIds: Set<Int> = {
                            if delete.type == .playlist { return Set(entry.ids) }
                            if delete.type == .presetStore { return Set(entry.playlistIds ?? []) }
                            return []
                        }()
                        _ = deadLetterPresetStoreDeletes(
                            deviceId: deviceId,
                            source: delete.source,
                            presetIds: presetIds,
                            playlistIds: playlistIds,
                            reason: reason
                        )
                        logger.warning(
                            "cleanup.queue_hard_stop_unreadable device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
                        )
                        processedCount += 1
                        continue
                    }
                    entry.lastError = outcome.lastError ?? "Delete failed"
                    if !outcome.madeProgress && !outcome.failedIds.isEmpty {
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
                    if !outcome.madeProgress {
                        entry.retries += 1
                    }
                    let retryAttempt: Int
                    if outcome.madeProgress {
                        retryAttempt = 1
                    } else {
                        retryAttempt = max(1, entry.retries)
                    }
                    let retryDelaySeconds = self.retryDelay(forAttempt: retryAttempt)
                    let nextAttemptAt = Date().addingTimeInterval(retryDelaySeconds)
                    entry.nextAttemptAt = nextAttemptAt
                    logger.warning(
                        "cleanup.queue_retry_scheduled device=\(deviceId, privacy: .public) delete=\(delete.id.uuidString, privacy: .public) type=\(delete.type.rawValue, privacy: .public) retries=\(entry.retries, privacy: .public) madeProgress=\(outcome.madeProgress, privacy: .public) failedIds=\(outcome.failedIds, privacy: .public) nextAttemptAt=\(nextAttemptAt.ISO8601Format(), privacy: .public) reason=\((entry.lastError ?? "Delete failed"), privacy: .public)"
                    )

                    let maxAttemptsForType = self.maxAttempts(for: delete.type)
                    if !outcome.madeProgress && entry.retries >= maxAttemptsForType {
                        if delete.type == .timer {
                            // Timer cleanup controls automation re-import safety.
                            entry.retries = maxAttemptsForType - 1
                            entry.nextAttemptAt = Date().addingTimeInterval(self.retryDelay(forAttempt: maxAttemptsForType))
                            logger.warning(
                                "Max attempts exceeded for \(delete.type.rawValue) deletion \(delete.id), keeping queued with capped backoff"
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
    private func attemptDelete(
        type: PendingDeviceDelete.DeleteType,
        device: WLEDDevice,
        ids: [Int],
        context: String
    ) async -> DeleteAttemptOutcome {
        logger.info("cleanup.delete.begin device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) ids=\(ids, privacy: .public) context=\(context, privacy: .public)")
        if type == .preset || type == .playlist {
            return await attemptPresetStoreRewriteDelete(
                type: type,
                device: device,
                ids: ids,
                context: context
            )
        }

        var succeeded: [Int] = []
        var failed: [Int] = []
        var lastError: String?
        var terminalAPIError: WLEDAPIError?

        for id in ids {
            do {
                await enforceDeleteCadence(for: type, deviceId: device.id)
                let success: Bool
                switch type {
                case .preset, .playlist, .presetStore:
                    assertionFailure("Preset-store deletes must use full rewrite path")
                    success = false
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
                    logger.info("cleanup.delete.item_ok device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public)")
                } else {
                    failed.append(id)
                    lastError = "delete returned unsuccessful status for id \(id)"
                    logger.error("cleanup.delete.item_failed device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public)")
                    break
                }
            } catch let apiError as WLEDAPIError {
                failed.append(id)
                lastError = apiError.localizedDescription
                terminalAPIError = apiError
                logger.error("cleanup.delete.error device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public) error=\(apiError.localizedDescription, privacy: .public)")
                break
            } catch {
                failed.append(id)
                lastError = error.localizedDescription
                logger.error("cleanup.delete.error device=\(device.id, privacy: .public) type=\(type.rawValue, privacy: .public) id=\(id, privacy: .public) context=\(context, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                break
            }

        }

        return DeleteAttemptOutcome(
            succeededIds: succeeded,
            failedIds: failed,
            lastError: lastError,
            terminalAPIError: terminalAPIError
        )
    }

    private func attemptPresetStoreRewriteDelete(
        type: PendingDeviceDelete.DeleteType,
        device: WLEDDevice,
        ids: [Int],
        context: String
    ) async -> DeleteAttemptOutcome {
        let normalizedIds = Array(Set(ids.filter { (1...250).contains($0) })).sorted()
        guard !normalizedIds.isEmpty else {
            return DeleteAttemptOutcome(succeededIds: ids, failedIds: [], lastError: nil, terminalAPIError: nil)
        }

        let playlistIds: [Int]
        let presetIds: [Int]
        switch type {
        case .preset:
            playlistIds = []
            presetIds = normalizedIds
        case .playlist:
            playlistIds = normalizedIds
            presetIds = []
        case .presetStore, .timer:
            playlistIds = []
            presetIds = []
        }

        return await attemptPresetStoreRewriteDelete(
            playlistIds: playlistIds,
            presetIds: presetIds,
            device: device,
            context: context
        )
    }

    private func attemptPresetStoreRewriteDelete(
        playlistIds: [Int],
        presetIds: [Int],
        device: WLEDDevice,
        context: String
    ) async -> DeleteAttemptOutcome {
        let normalizedPlaylistIds = Array(Set(playlistIds.filter { (1...250).contains($0) })).sorted()
        let normalizedPresetIds = Array(Set(presetIds.filter { (1...250).contains($0) })).sorted()
        let normalizedIds = Array(Set(normalizedPlaylistIds + normalizedPresetIds)).sorted()
        guard !normalizedIds.isEmpty else {
            return DeleteAttemptOutcome(succeededIds: [], failedIds: [], lastError: nil, terminalAPIError: nil)
        }

        do {
            await enforceDeleteCadence(for: .presetStore, deviceId: device.id)
            let success = try await WLEDAPIService.shared.rewritePresetStoreDeletingRecords(
                playlistIds: normalizedPlaylistIds,
                presetIds: normalizedPresetIds,
                device: device
            )

            guard success else {
                logger.error(
                    "cleanup.delete.rewrite_failed device=\(device.id, privacy: .public) playlists=\(normalizedPlaylistIds, privacy: .public) presets=\(normalizedPresetIds, privacy: .public) context=\(context, privacy: .public)"
                )
                return DeleteAttemptOutcome(
                    succeededIds: [],
                    failedIds: normalizedIds,
                    lastError: "full rewrite delete returned unsuccessful status",
                    terminalAPIError: nil
                )
            }

            logger.info(
                "cleanup.delete.rewrite_ok device=\(device.id, privacy: .public) playlists=\(normalizedPlaylistIds, privacy: .public) presets=\(normalizedPresetIds, privacy: .public) context=\(context, privacy: .public)"
            )
            return DeleteAttemptOutcome(
                succeededIds: normalizedIds,
                failedIds: [],
                lastError: nil,
                terminalAPIError: nil
            )
        } catch let apiError as WLEDAPIError {
            logger.error(
                "cleanup.delete.rewrite_error device=\(device.id, privacy: .public) playlists=\(normalizedPlaylistIds, privacy: .public) presets=\(normalizedPresetIds, privacy: .public) context=\(context, privacy: .public) error=\(apiError.localizedDescription, privacy: .public)"
            )
            return DeleteAttemptOutcome(
                succeededIds: [],
                failedIds: normalizedIds,
                lastError: apiError.localizedDescription,
                terminalAPIError: apiError
            )
        } catch {
            logger.error(
                "cleanup.delete.rewrite_error device=\(device.id, privacy: .public) playlists=\(normalizedPlaylistIds, privacy: .public) presets=\(normalizedPresetIds, privacy: .public) context=\(context, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return DeleteAttemptOutcome(
                succeededIds: [],
                failedIds: normalizedIds,
                lastError: error.localizedDescription,
                terminalAPIError: nil
            )
        }
    }

    private func presetStoreUnreadableHardStopReason(
        for outcome: DeleteAttemptOutcome,
        type: PendingDeviceDelete.DeleteType
    ) -> String? {
        guard type == .preset || type == .playlist || type == .presetStore else { return nil }
        guard let apiError = outcome.terminalAPIError else { return nil }
        switch apiError {
        case .presetStoreUnreadable(let reason):
            return reason
        case .httpError(let statusCode) where statusCode == 501:
            return "WLED reported HTTP 501 during preset-store delete"
        default:
            return nil
        }
    }

    private func cadenceKey(for type: PendingDeviceDelete.DeleteType, deviceId: String) -> String {
        switch type {
        case .preset, .playlist, .presetStore:
            // Preset + playlist share the same underlying presets-store write path.
            return "preset-store:\(deviceId)"
        case .timer:
            return "timer:\(deviceId)"
        }
    }

    private func cadenceIntervalSeconds(for type: PendingDeviceDelete.DeleteType) -> TimeInterval {
        switch type {
        case .preset, .playlist, .presetStore:
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
        var ids: Set<Int> = []
        for item in pendingDeletes {
            guard item.deviceId == deviceId else { continue }
            guard includeDeadLetter || item.deadLetteredAt == nil else { continue }

            switch (type, item.type) {
            case (.preset, .preset):
                ids.formUnion(item.ids)
            case (.playlist, .playlist):
                ids.formUnion(item.ids)
            case (.presetStore, .presetStore):
                ids.formUnion(item.ids)
            case (.preset, .presetStore):
                ids.formUnion(item.presetIds ?? [])
            case (.playlist, .presetStore):
                ids.formUnion(item.playlistIds ?? [])
            case (.timer, .timer):
                ids.formUnion(item.ids)
            default:
                continue
            }
        }
        return ids
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
            guard item.type == .preset || item.type == .playlist || item.type == .presetStore else { return false }
            return !item.ids.isEmpty
        }
    }

    func isDeleteLeaseActive(deviceId: String) -> Bool {
        activeDeleteLeaseByDeviceId.contains(deviceId)
    }

    var hasActiveDeleteLease: Bool {
        !activeDeleteLeaseByDeviceId.isEmpty
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
            guard pendingDeletes[index].deviceId == deviceId,
                  pendingDeletes[index].deadLetteredAt == nil else {
                continue
            }

            if pendingDeletes[index].type == .presetStore {
                let originalPlaylistIds = pendingDeletes[index].playlistIds ?? []
                let originalPresetIds = pendingDeletes[index].presetIds ?? []
                var playlistIds = originalPlaylistIds
                var presetIds = originalPresetIds
                switch type {
                case .playlist:
                    playlistIds.removeAll { toRemove.contains($0) }
                case .preset:
                    presetIds.removeAll { toRemove.contains($0) }
                case .presetStore:
                    playlistIds.removeAll { toRemove.contains($0) }
                    presetIds.removeAll { toRemove.contains($0) }
                case .timer:
                    continue
                }

                if playlistIds != originalPlaylistIds || presetIds != originalPresetIds {
                    changed = true
                    let remainingCombined = Array(Set(playlistIds + presetIds)).sorted()
                    if remainingCombined.isEmpty {
                        pendingDeletes.remove(at: index)
                    } else {
                        pendingDeletes[index].playlistIds = playlistIds.sorted()
                        pendingDeletes[index].presetIds = presetIds.sorted()
                        pendingDeletes[index].ids = remainingCombined
                    }
                }
                continue
            }

            guard pendingDeletes[index].type == type else { continue }
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
            guard entry.type == .preset || entry.type == .playlist || entry.type == .presetStore else { continue }

            let scopedIds: Set<Int> = {
                switch entry.type {
                case .preset:
                    return presetIds
                case .playlist:
                    return playlistIds
                case .presetStore:
                    return Set(entry.ids).intersection(presetIds.union(playlistIds))
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
            } else if entry.type == .presetStore {
                unmatchedPresetIds.subtract(Set(entry.presetIds ?? []).intersection(matchedIds))
                unmatchedPlaylistIds.subtract(Set(entry.playlistIds ?? []).intersection(matchedIds))
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
                if entry.type == .presetStore {
                    let remainingSet = Set(remaining)
                    pendingDeletes[index].playlistIds = (entry.playlistIds ?? []).filter { remainingSet.contains($0) }
                    pendingDeletes[index].presetIds = (entry.presetIds ?? []).filter { remainingSet.contains($0) }
                }
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
                    createdAt: entry.createdAt,
                    playlistIds: entry.type == .presetStore
                        ? (entry.playlistIds ?? []).filter { matchedIds.contains($0) }
                        : nil,
                    presetIds: entry.type == .presetStore
                        ? (entry.presetIds ?? []).filter { matchedIds.contains($0) }
                        : nil
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

    // MARK: - Persistence
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return }
        if let deletes = try? JSONDecoder().decode([PendingDeviceDelete].self, from: data) {
            let filtered = deletes.filter {
                !($0.type == .timer && $0.source == .automation && $0.deadLetteredAt == nil)
            }
            self.pendingDeletes = filtered
            if filtered.count != deletes.count {
                save()
                logger.warning(
                    "Dropped \(deletes.count - filtered.count) legacy automation timer deletes because WLED timer slots require live ownership proof"
                )
            }
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

    private func maxAttempts(for type: PendingDeviceDelete.DeleteType) -> Int {
        switch type {
        case .preset, .playlist, .presetStore:
            return maxPresetStoreDeleteAttempts
        case .timer:
            return maxAttempts
        }
    }

    private func maxIdsPerAttempt(for type: PendingDeviceDelete.DeleteType) -> Int {
        switch type {
        case .preset, .playlist, .presetStore:
            return 250
        case .timer:
            return 1
        }
    }

    private func deleteTypePriority(_ delete: PendingDeviceDelete) -> Int {
        switch delete.type {
        case .timer:
            return 0
        case .presetStore:
            return 1
        case .playlist:
            return 2
        case .preset:
            return 3
        }
    }

}
