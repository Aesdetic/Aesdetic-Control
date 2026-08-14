import Foundation
import Testing
@testable import Aesdetic_Control

@Suite("Routine readiness generation")
struct RoutineReadinessEvaluatorTests {
    private let generation = DeviceAutomationGeneration(
        timerConfigHash: "timer-generation",
        presetStoreHash: "preset-generation"
    )

    @Test("verified readiness carries the complete device generation")
    func verifiedReadinessCarriesGeneration() throws {
        let automationId = UUID()
        let timer = WLEDTimer(
            id: 2,
            enabled: true,
            hour: 12,
            minute: 0,
            days: 0x7F,
            macroId: 20,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        let key = RoutineDeviceKey(automationId: automationId, deviceId: "lamp")
        let snapshot = DeviceAutomationSnapshot(
            deviceId: "lamp",
            capturedAt: Date(timeIntervalSince1970: 100),
            generation: generation,
            timers: [timer],
            presetIds: [20],
            playlistIds: [],
            presetStoreRecordHashes: [20: "preset-20"],
            presets: [],
            playlists: [],
            deviceTimeZone: TimeZone(secondsFromGMT: 0)
        )
        let expectation = RoutineVerificationExpectation(
            key: key,
            storedTimerSlot: 2,
            allowedTimerSlots: Set(0...7),
            acceptedTimerSignatures: [RoutineReadinessEvaluator.timerSignature(for: timer)],
            macroId: 20,
            targetKind: .preset,
            preflightFailure: nil
        )

        let result = try #require(
            RoutineReadinessEvaluator.evaluate(
                expectations: [expectation],
                snapshot: snapshot
            )[key]
        )

        #expect(result.state == .verified)
        #expect(result.generation == generation)
        #expect(result.reconciledTimerSlot == nil)
    }

    @Test("one matching shifted row reconciles its slot")
    func reconcilesOneShiftedTimerRow() throws {
        let timer = WLEDTimer(
            id: 4,
            enabled: true,
            hour: 7,
            minute: 30,
            days: 0x1F,
            macroId: 21,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        let key = RoutineDeviceKey(automationId: UUID(), deviceId: "lamp")
        let snapshot = DeviceAutomationSnapshot(
            deviceId: "lamp",
            capturedAt: Date(),
            generation: generation,
            timers: [timer],
            presetIds: [],
            playlistIds: [21],
            presetStoreRecordHashes: [21: "playlist-21"],
            presets: [],
            playlists: [],
            deviceTimeZone: nil
        )
        let expectation = RoutineVerificationExpectation(
            key: key,
            storedTimerSlot: 1,
            allowedTimerSlots: Set(0...7),
            acceptedTimerSignatures: [RoutineReadinessEvaluator.timerSignature(for: timer)],
            macroId: 21,
            targetKind: .playlist,
            preflightFailure: nil
        )

        let result = try #require(
            RoutineReadinessEvaluator.evaluate(
                expectations: [expectation],
                snapshot: snapshot
            )[key]
        )

        #expect(result.state == .verified)
        #expect(result.reconciledTimerSlot == 4)
    }

    @Test("missing target never reports ready")
    func missingTargetIsNotReady() throws {
        let timer = WLEDTimer(
            id: 0,
            enabled: true,
            hour: 6,
            minute: 0,
            days: 0x7F,
            macroId: 40,
            startMonth: nil,
            startDay: nil,
            endMonth: nil,
            endDay: nil
        )
        let key = RoutineDeviceKey(automationId: UUID(), deviceId: "lamp")
        let snapshot = DeviceAutomationSnapshot(
            deviceId: "lamp",
            capturedAt: Date(),
            generation: generation,
            timers: [timer],
            presetIds: [],
            playlistIds: [],
            presetStoreRecordHashes: [:],
            presets: [],
            playlists: [],
            deviceTimeZone: nil
        )
        let expectation = RoutineVerificationExpectation(
            key: key,
            storedTimerSlot: 0,
            allowedTimerSlots: Set(0...7),
            acceptedTimerSignatures: [RoutineReadinessEvaluator.timerSignature(for: timer)],
            macroId: 40,
            targetKind: .preset,
            preflightFailure: nil
        )

        let result = try #require(
            RoutineReadinessEvaluator.evaluate(
                expectations: [expectation],
                snapshot: snapshot
            )[key]
        )

        #expect(result.state == .notReady)
        #expect(result.reason == .targetMissing)
        #expect(result.generation == nil)
    }
}

@Suite("Second-pass routine refresh policy")
struct RoutineRefreshPolicyTests {
    private let receipt = RoutineVerificationReceipt(
        key: RoutineDeviceKey(automationId: UUID(), deviceId: "lamp"),
        automationUpdatedAt: Date(timeIntervalSince1970: 50),
        generation: DeviceAutomationGeneration(
            timerConfigHash: "timer-generation",
            presetStoreHash: "preset-generation"
        ),
        timerSlot: 2,
        timerSignature: "timer-signature",
        targetKind: .playlist,
        targetRecordId: 20,
        targetRecordHash: "target-record",
        verifiedAt: Date(timeIntervalSince1970: 100)
    )

    @Test("checking readiness is explicit and non-retryable")
    func checkingReadinessRecord() {
        #expect(RoutineReadinessRecord.checking.state == .checking)
        #expect(RoutineReadinessRecord.checking.reason == .refreshInProgress)
        #expect(
            RoutineRetryPolicy.action(
                syncState: .synced,
                readinessState: .checking,
                transactionStatus: .idle
            ) == .none
        )
    }

    @Test("synced verification retry is read only")
    func verificationRetryDoesNotResync() {
        #expect(
            RoutineRetryPolicy.action(
                syncState: .synced,
                readinessState: .verificationNeeded,
                transactionStatus: .idle
            ) == .verifyReadOnly
        )
        #expect(
            RoutineRetryPolicy.action(
                syncState: .synced,
                readinessState: .notReady,
                transactionStatus: .idle
            ) == .resync
        )
        #expect(
            RoutineRetryPolicy.action(
                syncState: .notSynced,
                readinessState: .verificationNeeded,
                transactionStatus: .idle
            ) == .resync
        )
        #expect(
            RoutineRetryPolicy.action(
                syncState: .synced,
                readinessState: .verificationNeeded,
                transactionStatus: .needsRepair
            ) == .guidedRepair
        )
        #expect(
            RoutineRetryPolicy.action(
                syncState: .synced,
                readinessState: .notReady,
                transactionStatus: .recovering
            ) == .none
        )
        #expect(
            RoutineRetryPolicy.action(
                syncState: .synced,
                readinessState: .notReady,
                transactionStatus: .verificationNeeded
            ) == .verifyReadOnly
        )
    }

    @Test("only HTTP 503 receives bounded read-only delays")
    func serviceUnavailableRetrySchedule() {
        #expect(AutomationRefreshRetryPolicy.delayForHTTPStatus(503, retryIndex: 0) == 2)
        #expect(AutomationRefreshRetryPolicy.delayForHTTPStatus(503, retryIndex: 1) == 5)
        #expect(AutomationRefreshRetryPolicy.delayForHTTPStatus(503, retryIndex: 2) == 15)
        #expect(AutomationRefreshRetryPolicy.delayForHTTPStatus(503, retryIndex: 3) == nil)
        #expect(AutomationRefreshRetryPolicy.delayForHTTPStatus(500, retryIndex: 0) == nil)
    }

    @Test("last-known ready remains operational while checking or unreachable")
    func lastKnownReadySurvivesRefreshFreshnessChanges() {
        let checking = RoutineReadinessEvidenceResolver.resolve(
            record: .checking,
            receipt: receipt
        )
        #expect(checking.operationalState == .lastKnownReady)
        #expect(checking.verificationState == .checking)

        let unavailable = RoutineReadinessEvidenceResolver.resolve(
            record: .verificationNeeded(.readFailure),
            receipt: receipt
        )
        #expect(unavailable.operationalState == .lastKnownReady)
        #expect(unavailable.verificationState == .temporarilyUnavailable)
    }

    @Test("only confirmed mismatch removes operational readiness")
    func confirmedMismatchIsNotReady() {
        let evidence = RoutineReadinessEvidenceResolver.resolve(
            record: .notReady(.timerMismatch),
            receipt: receipt
        )

        #expect(evidence.operationalState == .confirmedNotReady)
        #expect(evidence.verificationState == .current)
    }

    @Test("never-verified routine reports checking without claiming ready")
    func neverVerifiedRoutineChecksWithoutReadyEvidence() {
        let evidence = RoutineReadinessEvidenceResolver.resolve(
            record: .checking,
            receipt: nil
        )

        #expect(evidence.operationalState == .neverConfigured)
        #expect(evidence.verificationState == .checking)
    }
}

@Suite("Routine verification receipt persistence")
@MainActor
struct RoutineVerificationReceiptStoreTests {
    @Test("verified receipt round-trips atomically")
    func verifiedReceiptRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineVerificationReceiptStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RoutineVerificationReceiptStore(rootURL: root)
        let receipt = makeReceipt(recordId: 20, verifiedAt: 100)

        try store.save([receipt.key: receipt])
        let loaded = try RoutineVerificationReceiptStore(rootURL: root).load()

        #expect(loaded == [receipt.key: receipt])
    }

    @Test("corrupt primary falls back to the previous verified receipt generation")
    func corruptPrimaryFallsBackToBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineVerificationReceiptStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RoutineVerificationReceiptStore(rootURL: root)
        let first = makeReceipt(recordId: 20, verifiedAt: 100)
        let second = makeReceipt(recordId: 21, verifiedAt: 200)

        try store.save([first.key: first])
        try store.save([second.key: second])
        let primaryURL = root.appendingPathComponent("routine-verification-v1.json")
        try Data("{".utf8).write(to: primaryURL, options: [.atomic])

        let loaded = try RoutineVerificationReceiptStore(rootURL: root).load()

        #expect(loaded == [first.key: first])
    }

    private func makeReceipt(
        recordId: Int,
        verifiedAt: TimeInterval
    ) -> RoutineVerificationReceipt {
        RoutineVerificationReceipt(
            key: RoutineDeviceKey(
                automationId: UUID(uuidString: "53E72943-2353-4D5D-B7B6-32BFB334AE62")!,
                deviceId: "lamp"
            ),
            automationUpdatedAt: Date(timeIntervalSince1970: 50),
            generation: DeviceAutomationGeneration(
                timerConfigHash: "timer-\(recordId)",
                presetStoreHash: "preset-\(recordId)"
            ),
            timerSlot: 2,
            timerSignature: "timer-signature-\(recordId)",
            targetKind: .playlist,
            targetRecordId: recordId,
            targetRecordHash: "record-\(recordId)",
            verifiedAt: Date(timeIntervalSince1970: verifiedAt)
        )
    }
}

@Suite("Per-device automation refresh coalescing")
@MainActor
struct AutomationRefreshSingleFlightCoordinatorTests {
    @Test("concurrent triggers share one complete device refresh")
    func concurrentTriggersCoalesce() async {
        let coordinator = AutomationRefreshSingleFlightCoordinator()
        var operationCount = 0

        let first = Task { @MainActor in
            await coordinator.run(deviceId: "lamp") {
                operationCount += 1
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let second = Task { @MainActor in
            await coordinator.run(deviceId: "lamp") {
                operationCount += 1
            }
        }

        await first.value
        await second.value
        #expect(operationCount == 1)
        #expect(!coordinator.isInFlight(deviceId: "lamp"))
    }

    @Test("different devices keep independent refresh transactions")
    func differentDevicesRunIndependently() async {
        let coordinator = AutomationRefreshSingleFlightCoordinator()
        var refreshedDevices: Set<String> = []

        async let lampA: Void = coordinator.run(deviceId: "lamp-a") {
            refreshedDevices.insert("lamp-a")
        }
        async let lampB: Void = coordinator.run(deviceId: "lamp-b") {
            refreshedDevices.insert("lamp-b")
        }
        _ = await (lampA, lampB)

        #expect(refreshedDevices == ["lamp-a", "lamp-b"])
    }
}

@Suite("WLED timer clock conversion")
struct WLEDTimerClockConverterTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_768_435_200)

    @Test("exact midnight stays midnight in the same timezone")
    func exactMidnightSameTimeZone() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
        let result = try #require(
            WLEDTimerClockConverter.convert(
                time: "00:00",
                weekdays: WeekdayMask.allDaysSunFirst,
                sourceTimeZone: timeZone,
                deviceTimeZone: timeZone,
                referenceDate: referenceDate
            )
        )

        #expect(result.hour == 0)
        #expect(result.minute == 0)
        #expect(result.dayShift == 0)
        #expect(result.days == 0x7F)
    }

    @Test("midnight shifts to the prior WLED weekday across timezone boundary")
    func midnightPriorDayBoundary() throws {
        let hongKong = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let mondayOnly = [false, true, false, false, false, false, false]
        let result = try #require(
            WLEDTimerClockConverter.convert(
                time: "00:00",
                weekdays: mondayOnly,
                sourceTimeZone: hongKong,
                deviceTimeZone: utc,
                referenceDate: referenceDate
            )
        )

        #expect(result.hour == 16)
        #expect(result.minute == 0)
        #expect(result.dayShift == -1)
        #expect(result.days == 1 << 6)
    }

    @Test("late time shifts to the next WLED weekday across timezone boundary")
    func lateTimeNextDayBoundary() throws {
        let hongKong = try #require(TimeZone(identifier: "Asia/Hong_Kong"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let mondayOnly = [false, true, false, false, false, false, false]
        let result = try #require(
            WLEDTimerClockConverter.convert(
                time: "23:30",
                weekdays: mondayOnly,
                sourceTimeZone: utc,
                deviceTimeZone: hongKong,
                referenceDate: referenceDate
            )
        )

        #expect(result.hour == 7)
        #expect(result.minute == 30)
        #expect(result.dayShift == 1)
        #expect(result.days == 1 << 1)
    }
}

@Suite("Brightness interaction policy")
struct BrightnessInteractionPolicyTests {
    @Test("interactive preview cadence is bounded")
    func cadenceAndAtomicBoundaries() {
        #expect(BrightnessInteractionPolicy.previewCadence == 0.14)
        #expect(
            BrightnessInteractionPolicy.permitsPreview(
                isOn: true,
                currentBrightness: 128,
                requestedBrightness: 180
            )
        )
        #expect(
            !BrightnessInteractionPolicy.permitsPreview(
                isOn: false,
                currentBrightness: 128,
                requestedBrightness: 180
            )
        )
        #expect(
            !BrightnessInteractionPolicy.permitsPreview(
                isOn: true,
                currentBrightness: 128,
                requestedBrightness: 0
            )
        )
    }
}

@Suite("Cleanup journal")
@MainActor
struct CleanupJournalStoreTests {
    @Test("corrupt primary recovers the previous atomic generation")
    func corruptPrimaryFallsBackToBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanupJournalStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CleanupJournalStore(rootURL: root)
        let first = PendingDeviceDelete(
            type: .presetStore,
            deviceId: "lamp",
            ids: [10],
            playlistIds: [],
            presetIds: [10]
        )
        let second = PendingDeviceDelete(
            type: .presetStore,
            deviceId: "lamp",
            ids: [11],
            playlistIds: [11],
            presetIds: []
        )

        try store.savePendingDeletes([first])
        try store.savePendingDeletes([second])
        let primaryURL = root.appendingPathComponent("cleanup-journal-v2.json")
        try Data("{".utf8).write(to: primaryURL, options: [.atomic])

        let recovered = try CleanupJournalStore(rootURL: root).load()

        #expect(recovered.pendingDeletes == [first])
    }
}
