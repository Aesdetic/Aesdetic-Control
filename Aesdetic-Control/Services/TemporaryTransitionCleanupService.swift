import Foundation
import os.log

actor TemporaryTransitionCleanupService {
    static let shared = TemporaryTransitionCleanupService()
    nonisolated static let isEnabled: Bool = false

    private let logger = Logger(subsystem: "com.aesdetic.control", category: "TempTransitionCleanup")
    private let leasesKey = "aesdetic_temp_transition_leases_v2"
    private let localRetrySchedule: [TimeInterval] = [0.5, 1, 2, 5, 10, 20]
    private let degradedVerificationRetrySchedule: [TimeInterval] = [5, 10, 20, 60, 120, 300]
    private let degradedVerificationMaxAttemptsBeforeParking = 3
    private let maxAttemptsBeforeQueueFallback = 12

    private var leasesById: [UUID: TemporaryTransitionLease] = [:]
    private var activeLeaseByDevice: [String: UUID] = [:]
    private var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var cleanupTaskTokens: [UUID: UUID] = [:]
    private var activeCleanupAttemptLeaseIds: Set<UUID> = []
    private var completedDeletePhaseLeaseIds: Set<UUID> = []
    private var interactiveDeferralUntilByDevice: [String: Date] = [:]
    private var lastOrphanScanAtByDevice: [String: Date] = [:]
    private let orphanScanMinInterval: TimeInterval = 180
    private let cleanupNotBeforePollInterval: TimeInterval = 0.25

    private init() {
        leasesById = Self.loadLeases(leasesKey: leasesKey, logger: logger)
        let candidates = leasesById.values.sorted { $0.createdAt < $1.createdAt }
        for lease in candidates where lease.state != .cleaned && lease.state != .deadLetter {
            activeLeaseByDevice[lease.deviceId] = lease.leaseId
        }
    }

    func registerLease(
        deviceId: String,
        runId: UUID? = nil,
        playlistId: Int? = nil,
        stepPresetIds: [Int] = []
    ) -> TemporaryTransitionLease {
        let lease = TemporaryTransitionLease(
            deviceId: deviceId,
            runId: runId,
            playlistId: playlistId,
            stepPresetIds: Array(Set(stepPresetIds)).sorted(),
            state: .allocating,
            isPersistentTransition: false
        )
        leasesById[lease.leaseId] = lease
        activeLeaseByDevice[deviceId] = lease.leaseId
        save()
        logger.info("cleanup.lease_created device=\(deviceId, privacy: .public) lease=\(lease.leaseId.uuidString, privacy: .public)")
        return lease
    }

    func updateAllocatingLease(
        leaseId: UUID,
        playlistId: Int? = nil,
        appendStepPresetId: Int? = nil
    ) -> TemporaryTransitionLease? {
        guard var lease = leasesById[leaseId] else { return nil }
        if let playlistId {
            lease.playlistId = playlistId
        }
        if let appendStepPresetId {
            lease.stepPresetIds = Array(Set(lease.stepPresetIds + [appendStepPresetId])).sorted()
        }
        leasesById[leaseId] = lease
        if activeLeaseByDevice[lease.deviceId] == nil {
            activeLeaseByDevice[lease.deviceId] = leaseId
        }
        save()
        return lease
    }

    func markReady(leaseId: UUID, playlistId: Int, stepPresetIds: [Int]) -> TemporaryTransitionLease? {
        guard var lease = leasesById[leaseId] else { return nil }
        lease.playlistId = playlistId
        lease.stepPresetIds = Array(Set(stepPresetIds)).sorted()
        lease.state = .ready
        leasesById[leaseId] = lease
        activeLeaseByDevice[lease.deviceId] = leaseId
        save()
        return lease
    }

    func markRunning(leaseId: UUID, runId: UUID?, expectedEndAt: Date?) -> TemporaryTransitionLease? {
        guard var lease = leasesById[leaseId] else { return nil }
        lease.runId = runId ?? lease.runId
        lease.expectedEndAt = expectedEndAt
        lease.cleanupNotBefore = expectedEndAt
        lease.state = .running
        leasesById[leaseId] = lease
        activeLeaseByDevice[lease.deviceId] = leaseId
        save()
        return lease
    }

    func requestCleanup(
        device: WLEDDevice,
        endReason: TemporaryTransitionEndReason,
        runId: UUID?,
        playlistIdHint: Int? = nil,
        stepPresetIdsHint: [Int]? = nil
    ) async {
        guard Self.isEnabled else { return }
        if endReason == .appRestartRecovery,
           await WLEDAPIService.shared.isPresetStoreMutationInFlight(deviceId: device.id) {
            logger.info("cleanup.recovery_skipped_mutation_in_flight device=\(device.id, privacy: .public)")
            return
        }
        let leaseId = upsertLeaseForCleanup(
            device: device,
            runId: runId,
            endReason: endReason,
            playlistIdHint: playlistIdHint,
            stepPresetIdsHint: stepPresetIdsHint
        )
        guard let leaseId else { return }
        await scheduleCleanup(leaseId: leaseId, device: device)
    }

    func cleanupNow(leaseId: UUID, device: WLEDDevice) async {
        guard Self.isEnabled else { return }
        cleanupTasks[leaseId]?.cancel()
        let token = UUID()
        cleanupTaskTokens[leaseId] = token
        await runCleanupLoop(leaseId: leaseId, device: device, token: token)
        cleanupTaskDidFinish(leaseId: leaseId, token: token)
    }

    func resumePending(for device: WLEDDevice) async {
        guard Self.isEnabled else { return }
        let now = Date()
        let leases = leasesById.values
            .filter { $0.deviceId == device.id }
            .sorted { $0.createdAt < $1.createdAt }
        for lease in leases {
            switch lease.state {
            case .running:
                if let expectedEndAt = lease.expectedEndAt, now >= expectedEndAt.addingTimeInterval(temporaryTransitionCleanupGraceMinutes * 60) {
                    await requestCleanup(device: device, endReason: .appRestartRecovery, runId: lease.runId)
                } else if let expectedEndAt = lease.expectedEndAt, now >= expectedEndAt {
                    await requestCleanup(device: device, endReason: .completed, runId: lease.runId)
                }
            case .cancelRequested, .cleanupPending, .failed:
                await scheduleCleanup(leaseId: lease.leaseId, device: device)
            default:
                break
            }
        }
    }

    func scanAndCleanOrphans(for device: WLEDDevice) async {
        guard Self.isEnabled else { return }
        guard device.isOnline else { return }
        let now = Date()
        if let lastScan = lastOrphanScanAtByDevice[device.id],
           now.timeIntervalSince(lastScan) < orphanScanMinInterval {
            return
        }
        if let activeLeaseId = activeLeaseByDevice[device.id],
           let lease = leasesById[activeLeaseId] {
            switch lease.state {
            case .allocating, .ready, .running, .cancelRequested, .cleanupPending:
                return
            default:
                break
            }
        }
        lastOrphanScanAtByDevice[device.id] = now
        let protectedIds = Set(
            leasesById.values
                .filter { $0.deviceId == device.id && $0.state != .cleaned }
                .flatMap { [$0.playlistId].compactMap { $0 } + $0.stepPresetIds }
        )
        let presets = (try? await WLEDAPIService.shared.fetchPresets(for: device)) ?? []
        let playlists = (try? await WLEDAPIService.shared.fetchPlaylists(for: device)) ?? []

        let orphanStepIds = presets
            .filter { (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0.id) }
            .filter { $0.name.hasPrefix("Auto Step ") }
            .map(\.id)
            .filter { !protectedIds.contains($0) }

        let orphanPlaylistIds = playlists
            .filter { (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0.id) }
            .filter { $0.name.hasPrefix("Auto Transition ") }
            .map(\.id)
            .filter { !protectedIds.contains($0) }

        guard !orphanStepIds.isEmpty || !orphanPlaylistIds.isEmpty else { return }
        await requestCleanup(
            device: device,
            endReason: .appRestartRecovery,
            runId: nil,
            playlistIdHint: orphanPlaylistIds.sorted().last,
            stepPresetIdsHint: orphanStepIds
        )
    }

    func activeLease(for deviceId: String) -> TemporaryTransitionLease? {
        guard let leaseId = activeLeaseByDevice[deviceId] else { return nil }
        return leasesById[leaseId]
    }

    func activeLeaseId(for deviceId: String) -> UUID? {
        guard let leaseId = activeLeaseByDevice[deviceId],
              let lease = leasesById[leaseId],
              lease.state != .cleaned,
              lease.state != .deadLetter else {
            return nil
        }
        return leaseId
    }

    func activeProtectedTempIds(for deviceId: String) -> (playlistIds: Set<Int>, presetIds: Set<Int>) {
        guard Self.isEnabled else { return ([], []) }
        guard let leaseId = activeLeaseByDevice[deviceId],
              let lease = leasesById[leaseId],
              lease.state != .cleaned,
              lease.state != .deadLetter else {
            return ([], [])
        }
        let playlistIds = Set([lease.playlistId].compactMap { $0 })
        let presetIds = Set(lease.stepPresetIds)
        return (playlistIds, presetIds)
    }

    func pendingCleanupCount(for deviceId: String) -> Int {
        guard Self.isEnabled else { return 0 }
        return cleanupCounts(for: deviceId).blocking
    }

    func cleanupCounts(for deviceId: String) -> (blocking: Int, backlog: Int) {
        guard Self.isEnabled else { return (0, 0) }
        let now = Date()
        var blocking = 0
        var backlog = 0
        for lease in cleanupTasks.keys.compactMap({ leaseId in
            leasesById[leaseId]
        }) {
            guard lease.deviceId == deviceId else { continue }
            guard lease.state != .cleaned, lease.state != .deadLetter else { continue }
            // A scheduled completion cleanup for a still-running transition should not block
            // new heavy ops until the cleanup is actually due.
            if lease.state == .running,
               let notBefore = lease.cleanupNotBefore,
               notBefore > now {
                continue
            }

            let deferralUntil = interactiveDeferralUntilByDevice[deviceId]
            let isInteractiveDeferred = deferralUntil.map { $0 > now } ?? false
            let cleanupDueNow = (lease.cleanupNotBefore == nil) || ((lease.cleanupNotBefore ?? now) <= now)
            let activeAttempt = activeCleanupAttemptLeaseIds.contains(lease.leaseId)
            let shouldBlockNow = activeAttempt || (
                cleanupDueNow &&
                !isInteractiveDeferred &&
                (lease.state == .cancelRequested || lease.state == .cleanupPending)
            )

            if shouldBlockNow {
                blocking += 1
            } else {
                backlog += 1
            }
        }
        return (blocking, backlog)
    }

    func deferInteractiveConflictingCleanup(for deviceId: String, until: Date) {
        guard Self.isEnabled else { return }
        if let existing = interactiveDeferralUntilByDevice[deviceId], existing >= until {
            return
        }
        interactiveDeferralUntilByDevice[deviceId] = until
    }

    func markCreationFailed(leaseId: UUID, device: WLEDDevice) async {
        guard Self.isEnabled else { return }
        guard var lease = leasesById[leaseId] else { return }
        lease.state = .cancelRequested
        lease.endReason = .creationFailed
        lease.cleanupNotBefore = Date()
        leasesById[leaseId] = lease
        save()
        await scheduleCleanup(leaseId: leaseId, device: device)
    }

    private func upsertLeaseForCleanup(
        device: WLEDDevice,
        runId: UUID?,
        endReason: TemporaryTransitionEndReason,
        playlistIdHint: Int?,
        stepPresetIdsHint: [Int]?
    ) -> UUID? {
        if let matched = findLeaseId(deviceId: device.id, runId: runId) {
            guard var lease = leasesById[matched] else { return matched }
            if lease.state != .cleaned && lease.state != .deadLetter {
                let now = Date()
                if endReason == .appRestartRecovery,
                   shouldIgnoreRecoveryCleanupRequest(
                        lease: lease,
                        now: now,
                        playlistIdHint: playlistIdHint,
                        stepPresetIdsHint: stepPresetIdsHint
                   ) {
                    logger.info("cleanup.recovery_ignored_active_lease device=\(device.id, privacy: .public) lease=\(matched.uuidString, privacy: .public)")
                    return nil
                }
                let notBefore: Date
                if endReason == .completed, let expectedEndAt = lease.expectedEndAt {
                    notBefore = expectedEndAt
                } else {
                    notBefore = now
                }
                lease.state = (endReason == .completed && notBefore > now) ? .running : .cancelRequested
                lease.endReason = endReason
                lease.cleanupNotBefore = notBefore
                if let playlistIdHint, lease.playlistId == nil { lease.playlistId = playlistIdHint }
                if let stepPresetIdsHint, !stepPresetIdsHint.isEmpty {
                    lease.stepPresetIds = Array(Set(lease.stepPresetIds + stepPresetIdsHint)).sorted()
                }
                leasesById[matched] = lease
                activeLeaseByDevice[device.id] = matched
                save()
                logger.info("cleanup.cancel_requested device=\(device.id, privacy: .public) lease=\(matched.uuidString, privacy: .public) reason=\(endReason.rawValue, privacy: .public)")
            }
            return matched
        }

        let synthetic = TemporaryTransitionLease(
            deviceId: device.id,
            runId: runId,
            playlistId: playlistIdHint,
            stepPresetIds: Array(Set(stepPresetIdsHint ?? [])).sorted(),
            expectedEndAt: nil,
            cleanupNotBefore: Date(),
            state: .cancelRequested,
            isPersistentTransition: false,
            endReason: endReason
        )
        leasesById[synthetic.leaseId] = synthetic
        activeLeaseByDevice[device.id] = synthetic.leaseId
        save()
        logger.warning("cleanup.lease_created_synthetic device=\(device.id, privacy: .public) lease=\(synthetic.leaseId.uuidString, privacy: .public)")
        return synthetic.leaseId
    }

    private func findLeaseId(deviceId: String, runId: UUID?) -> UUID? {
        if let runId,
           let match = leasesById.values.first(where: {
               $0.deviceId == deviceId && $0.runId == runId && $0.state != .cleaned && $0.state != .deadLetter
           }) {
            return match.leaseId
        }
        if let active = activeLeaseByDevice[deviceId],
           let lease = leasesById[active],
           lease.state != .cleaned,
           lease.state != .deadLetter {
            return active
        }
        return leasesById.values
            .filter { $0.deviceId == deviceId && $0.state != .cleaned && $0.state != .deadLetter }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .leaseId
    }

    private func scheduleCleanup(leaseId: UUID, device: WLEDDevice) async {
        guard let lease = leasesById[leaseId] else { return }
        if lease.state == .cleaned || lease.state == .deadLetter { return }
        if activeCleanupAttemptLeaseIds.contains(leaseId) {
            logger.info("cleanup.schedule.skip_active_attempt device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public)")
            return
        }
        if cleanupTasks[leaseId]?.isCancelled == false {
            // Keep a single cleanup loop per lease. The loop polls cleanupNotBefore, so
            // updated urgency can be picked up without cancel/restart churn.
            logger.info("cleanup.schedule.skip_existing_task device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public)")
            return
        }
        let token = UUID()
        cleanupTaskTokens[leaseId] = token
        let task = Task { [leaseId, device, token] in
            await TemporaryTransitionCleanupService.shared.runCleanupLoop(leaseId: leaseId, device: device, token: token)
            await TemporaryTransitionCleanupService.shared.cleanupTaskDidFinish(leaseId: leaseId, token: token)
        }
        cleanupTasks[leaseId] = task
    }

    private func runCleanupLoop(leaseId: UUID, device: WLEDDevice, token: UUID) async {
        for attemptIndex in 0..<maxAttemptsBeforeQueueFallback {
            guard cleanupTaskTokens[leaseId] == token else {
                logger.info("cleanup.task_stale_exit device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) stage=loop_begin")
                return
            }
            guard await waitUntilCleanupDue(leaseId: leaseId, token: token) else { return }
            guard var lease = leasesById[leaseId] else { return }
            if lease.state == .cleaned || lease.state == .deadLetter { return }
            guard cleanupTaskTokens[leaseId] == token else {
                logger.info("cleanup.task_stale_exit device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) stage=after_wait_due")
                return
            }
            let deferralNow = Date()
            if let deferredUntil = interactiveDeferralUntilByDevice[device.id] {
                if deferralNow < deferredUntil {
                    let delay = deferredUntil.timeIntervalSince(deferralNow)
                    logger.info("cleanup.retry_deferred_interactive device=\(device.id, privacy: .public) until=\(deferredUntil.ISO8601Format(), privacy: .public)")
                    try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                    if Task.isCancelled { return }
                } else {
                    interactiveDeferralUntilByDevice.removeValue(forKey: device.id)
                }
            }
            guard cleanupTaskTokens[leaseId] == token else {
                logger.info("cleanup.task_stale_exit device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) stage=after_interactive_deferral")
                return
            }
            lease.state = .cleanupPending
            lease.cleanupAttemptCount += 1
            lease.lastError = nil
            leasesById[leaseId] = lease
            save()
            logger.info("cleanup.begin device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) attempt=\(lease.cleanupAttemptCount)")

            guard cleanupTaskTokens[leaseId] == token else {
                logger.info("cleanup.task_stale_exit device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) stage=before_attempt")
                return
            }
            activeCleanupAttemptLeaseIds.insert(leaseId)
            let result = await performCleanupAttempt(lease: lease, device: device)
            activeCleanupAttemptLeaseIds.remove(leaseId)
            switch result {
            case .success:
                completedDeletePhaseLeaseIds.remove(leaseId)
                var updated = lease
                updated.state = .cleaned
                updated.lastError = nil
                leasesById[leaseId] = updated
                if activeLeaseByDevice[device.id] == leaseId {
                    activeLeaseByDevice.removeValue(forKey: device.id)
                }
                save()
                logger.info("cleanup.verify_ok device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public)")
                return
            case .failure(let message):
                // A hard verification failure means another delete pass may still be needed.
                completedDeletePhaseLeaseIds.remove(leaseId)
                lease.lastError = message
                lease.state = .failed
                leasesById[leaseId] = lease
                save()
                logger.warning("cleanup.verify_fail device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) error=\(message, privacy: .public)")
                if Task.isCancelled { return }
                if attemptIndex < localRetrySchedule.count {
                    let delay = localRetrySchedule[attemptIndex]
                    logger.info("cleanup.retry device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) delay=\(delay)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                await enqueueQueueFallback(for: leaseId, device: device, lease: lease, error: message)
                return
            case .degradedVerification(let message):
                // Keep delete phase as completed; degraded read retries should avoid re-delete storms.
                let delay = degradedVerificationRetryDelay(forAttemptIndex: attemptIndex)
                lease.lastError = message
                let degradedAttempts = attemptIndex + 1
                if degradedAttempts >= degradedVerificationMaxAttemptsBeforeParking {
                    lease.state = .deadLetter
                    lease.cleanupNotBefore = nil
                    leasesById[leaseId] = lease
                    if activeLeaseByDevice[device.id] == leaseId {
                        activeLeaseByDevice.removeValue(forKey: device.id)
                    }
                    save()
                    logger.error("cleanup.verify_degraded_parked device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) attempts=\(degradedAttempts, privacy: .public) error=\(message, privacy: .public)")
                    return
                }
                lease.state = .failed
                lease.cleanupNotBefore = Date().addingTimeInterval(delay)
                leasesById[leaseId] = lease
                save()
                logger.warning("cleanup.verify_degraded device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public) delay=\(delay, privacy: .public) error=\(message, privacy: .public)")
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
        }
    }

    private func waitUntilCleanupDue(leaseId: UUID, token: UUID) async -> Bool {
        while true {
            guard cleanupTaskTokens[leaseId] == token else {
                logger.info("cleanup.task_stale_exit lease=\(leaseId.uuidString, privacy: .public) stage=wait_due_poll")
                return false
            }
            guard let lease = leasesById[leaseId] else { return false }
            if lease.state == .cleaned || lease.state == .deadLetter {
                return false
            }
            let now = Date()
            if let notBefore = lease.cleanupNotBefore, now < notBefore {
                let delay = min(cleanupNotBeforePollInterval, notBefore.timeIntervalSince(now))
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                if Task.isCancelled {
                    return false
                }
                continue
            }
            return true
        }
    }

    private func cleanupTaskDidFinish(leaseId: UUID, token: UUID) {
        guard cleanupTaskTokens[leaseId] == token else { return }
        cleanupTasks.removeValue(forKey: leaseId)
        cleanupTaskTokens.removeValue(forKey: leaseId)
        completedDeletePhaseLeaseIds.remove(leaseId)
    }

    private enum CleanupAttemptResult {
        case success
        case failure(String)
        case degradedVerification(String)
    }

    private func performCleanupAttempt(lease: TemporaryTransitionLease, device: WLEDDevice) async -> CleanupAttemptResult {
        let activeLeaseId = activeLeaseByDevice[device.id]
        let activeLease = activeLeaseId.flatMap { leasesById[$0] }
        let protectActiveLeaseIds = activeLeaseId != nil && activeLeaseId != lease.leaseId
        let protectedPlaylistIds = protectActiveLeaseIds ? Set([activeLease?.playlistId].compactMap { $0 }) : Set<Int>()
        let protectedPresetIds = protectActiveLeaseIds ? Set(activeLease?.stepPresetIds ?? []) : Set<Int>()

        var playlistId = lease.playlistId
        if let candidatePlaylistId = playlistId, protectedPlaylistIds.contains(candidatePlaylistId) {
            playlistId = nil
        }
        let presetIds = lease.stepPresetIds
            .sorted(by: >)
            .filter { !protectedPresetIds.contains($0) }

        if protectActiveLeaseIds {
            let skippedPresetIds = Set(lease.stepPresetIds).subtracting(presetIds)
            let skippedPlaylist = (lease.playlistId != nil && playlistId == nil)
            if skippedPlaylist || !skippedPresetIds.isEmpty {
                let skippedPresetText = Array(skippedPresetIds).sorted().map(String.init).joined(separator: ",")
                logger.info(
                    "cleanup.skip_protected_ids device=\(device.id, privacy: .public) lease=\(lease.leaseId.uuidString, privacy: .public) skippedPlaylist=\(String(skippedPlaylist), privacy: .public) skippedPresets=\(skippedPresetText, privacy: .public)"
                )
            }
        }

        if playlistId == nil && presetIds.isEmpty {
            return .success
        }

        let skipDeletePhase = completedDeletePhaseLeaseIds.contains(lease.leaseId)
        do {
            if !skipDeletePhase {
                if let playlistId {
                    logger.info("cleanup.delete_playlist device=\(device.id, privacy: .public) id=\(playlistId)")
                    _ = try await WLEDAPIService.shared.deletePlaylist(id: playlistId, device: device)
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
                for (index, presetId) in presetIds.enumerated() {
                    logger.info("cleanup.delete_preset device=\(device.id, privacy: .public) id=\(presetId)")
                    _ = try await WLEDAPIService.shared.deletePreset(id: presetId, device: device)
                    if index < presetIds.count - 1 {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                }
                completedDeletePhaseLeaseIds.insert(lease.leaseId)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            let presets: [WLEDPreset]
            do {
                presets = try await WLEDAPIService.shared.fetchPresets(for: device)
            } catch {
                if isDegradedVerificationReadError(error) {
                    return .degradedVerification("Preset verification unreadable: \(error.localizedDescription)")
                }
                return .failure(error.localizedDescription)
            }
            let playlists: [WLEDPlaylist]
            do {
                playlists = try await WLEDAPIService.shared.fetchPlaylists(for: device)
            } catch {
                if isDegradedVerificationReadError(error) {
                    return .degradedVerification("Playlist verification unreadable: \(error.localizedDescription)")
                }
                return .failure(error.localizedDescription)
            }
            let presetSet = Set(presets.map(\.id))
            let playlistSet = Set(playlists.map(\.id))
            if let playlistId, playlistSet.contains(playlistId) {
                return .failure("Playlist \(playlistId) still present after delete")
            }
            let remainingSteps = presetIds.filter { presetSet.contains($0) }
            if !remainingSteps.isEmpty {
                return .failure("Preset IDs still present: \(remainingSteps)")
            }
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func degradedVerificationRetryDelay(forAttemptIndex attemptIndex: Int) -> TimeInterval {
        if attemptIndex < degradedVerificationRetrySchedule.count {
            return degradedVerificationRetrySchedule[attemptIndex]
        }
        return degradedVerificationRetrySchedule.last ?? 300
    }

    private func isDegradedVerificationReadError(_ error: Error) -> Bool {
        if let apiError = error as? WLEDAPIError {
            switch apiError {
            case .decodingError, .invalidResponse, .deviceBusy, .timeout, .networkError:
                return true
            case .httpError(let status):
                return status >= 500
            case .deviceOffline, .deviceUnreachable:
                return true
            default:
                return false
            }
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("http 5") || message.contains("server error") || message.contains("service unavailable") {
            return true
        }
        if message.contains("decode") || message.contains("invalid response") || message.contains("error:4") {
            return true
        }
        if message.contains("timed out") || message.contains("network error") || message.contains("cancelled") {
            return true
        }
        return false
    }

    private func shouldIgnoreRecoveryCleanupRequest(
        lease: TemporaryTransitionLease,
        now: Date,
        playlistIdHint: Int?,
        stepPresetIdsHint: [Int]?
    ) -> Bool {
        // Recovery/orphan cleanup must not commandeer an active/in-flight lease.
        switch lease.state {
        case .allocating, .ready:
            return true
        case .running:
            guard let expectedEndAt = lease.expectedEndAt else {
                return true
            }
            if now < expectedEndAt.addingTimeInterval(temporaryTransitionCleanupGraceMinutes * 60) {
                return true
            }
        default:
            break
        }

        let hintedIds = Set(([playlistIdHint].compactMap { $0 }) + (stepPresetIdsHint ?? []))
        if !hintedIds.isEmpty {
            let leaseIds = Set(([lease.playlistId].compactMap { $0 }) + lease.stepPresetIds)
            if !hintedIds.isDisjoint(with: leaseIds),
               lease.state != .failed,
               lease.state != .cancelRequested,
               lease.state != .cleanupPending {
                return true
            }
        }
        return false
    }

    private func enqueueQueueFallback(
        for leaseId: UUID,
        device: WLEDDevice,
        lease: TemporaryTransitionLease,
        error: String
    ) async {
        if let playlistId = lease.playlistId {
            await DeviceCleanupManager.shared.requestDelete(
                type: .playlist,
                device: device,
                ids: [playlistId],
                source: .temporaryTransition,
                leaseId: leaseId,
                verificationRequired: true
            )
        }
        if !lease.stepPresetIds.isEmpty {
            await DeviceCleanupManager.shared.requestDelete(
                type: .preset,
                device: device,
                ids: lease.stepPresetIds,
                source: .temporaryTransition,
                leaseId: leaseId,
                verificationRequired: true
            )
        }
        var updated = lease
        updated.state = .failed
        updated.lastError = error
        leasesById[leaseId] = updated
        save()
        logger.warning("cleanup.queue_enqueued device=\(device.id, privacy: .public) lease=\(leaseId.uuidString, privacy: .public)")
    }

    private static func loadLeases(leasesKey: String, logger: Logger) -> [UUID: TemporaryTransitionLease] {
        guard let data = UserDefaults.standard.data(forKey: leasesKey) else { return [:] }
        do {
            let leases = try JSONDecoder().decode([TemporaryTransitionLease].self, from: data)
            return Dictionary(uniqueKeysWithValues: leases.map { ($0.leaseId, $0) })
        } catch {
            logger.error("Failed to load temporary transition leases: \(error.localizedDescription)")
            return [:]
        }
    }

    private func save() {
        let leases = leasesById.values.sorted { $0.createdAt < $1.createdAt }
        if let data = try? JSONEncoder().encode(leases) {
            UserDefaults.standard.set(data, forKey: leasesKey)
        }
    }
}
