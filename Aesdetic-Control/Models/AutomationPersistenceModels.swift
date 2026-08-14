import Foundation

/// Exact device content generation used to prove that a routine was verified
/// against one timer configuration and one preset-store file.
struct DeviceAutomationGeneration: Codable, Equatable, Hashable {
    let timerConfigHash: String
    let presetStoreHash: String
}

/// A short-lived, read-only device snapshot. This is intentionally not
/// persisted because WLED can also be changed by the web UI or another client.
struct DeviceAutomationSnapshot {
    let deviceId: String
    let capturedAt: Date
    let generation: DeviceAutomationGeneration
    let timers: [WLEDTimer]
    let presetIds: Set<Int>
    let playlistIds: Set<Int>
    let presetStoreRecordHashes: [Int: String]
    let presets: [WLEDPreset]
    let playlists: [WLEDPlaylist]
    let deviceTimeZone: TimeZone?
}

enum DeviceAutomationSnapshotError: LocalizedError, Equatable {
    case busy
    case superseded
    case timerConfigurationUnavailable
    case presetStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .busy:
            return "The device is finishing a timer or saved-item change."
        case .superseded:
            return "A newer device change superseded this verification."
        case .timerConfigurationUnavailable:
            return "The device timer configuration could not be verified."
        case .presetStoreUnavailable:
            return "The device preset store could not be verified."
        }
    }
}

struct RoutineDeviceKey: Codable, Equatable, Hashable {
    let automationId: UUID
    let deviceId: String
}

enum AutomationRefreshReason: String, Codable, Equatable {
    case launch
    case foreground
    case reconnect
    case mutationCommitted
    case manualRetry
    case periodic
}

enum AutomationRefreshRetryPolicy {
    static let serviceUnavailableDelays: [UInt64] = [2, 5, 15]

    static func delayForHTTPStatus(_ statusCode: Int, retryIndex: Int) -> UInt64? {
        guard statusCode == 503,
              serviceUnavailableDelays.indices.contains(retryIndex) else {
            return nil
        }
        return serviceUnavailableDelays[retryIndex]
    }
}

struct WLEDTimerClockValue: Equatable {
    let hour: Int
    let minute: Int
    let days: Int
    let dayShift: Int
}

enum WLEDTimerClockConverter {
    static func convert(
        time: String,
        weekdays: [Bool],
        sourceTimeZone: TimeZone,
        deviceTimeZone: TimeZone,
        referenceDate: Date
    ) -> WLEDTimerClockValue? {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        let sourceOffsetMinutes = sourceTimeZone.secondsFromGMT(for: referenceDate) / 60
        let targetOffsetMinutes = deviceTimeZone.secondsFromGMT(for: referenceDate) / 60
        var convertedMinutes = (hour * 60) + minute + targetOffsetMinutes - sourceOffsetMinutes
        var dayShift = 0
        while convertedMinutes < 0 {
            convertedMinutes += 1_440
            dayShift -= 1
        }
        while convertedMinutes >= 1_440 {
            convertedMinutes -= 1_440
            dayShift += 1
        }

        let sourceWeekdays = WeekdayMask.normalizeSunFirst(weekdays)
        var shiftedWeekdays = Array(repeating: false, count: 7)
        for (index, enabled) in sourceWeekdays.enumerated() where enabled {
            shiftedWeekdays[(index + dayShift % 7 + 7) % 7] = true
        }

        return WLEDTimerClockValue(
            hour: convertedMinutes / 60,
            minute: convertedMinutes % 60,
            days: WeekdayMask.wledDow(fromSunFirst: shiftedWeekdays),
            dayShift: dayShift
        )
    }
}

enum RoutineReadinessState: String, Codable, Equatable {
    case checking
    case verified
    case verificationNeeded
    case notReady
}

/// Whether the app has durable evidence that the routine was installed on the
/// device. This is intentionally separate from freshness of the current read.
enum RoutineOperationalState: String, Codable, Equatable {
    case neverConfigured
    case lastKnownReady
    case confirmedNotReady
}

/// Freshness of the read-only device evidence used by the UI. A temporary read
/// failure never changes a last-known-ready routine into confirmed-not-ready.
enum RoutineVerificationState: String, Codable, Equatable {
    case notStarted
    case checking
    case current
    case temporarilyUnavailable
}

struct RoutineReadinessEvidence: Equatable {
    let operationalState: RoutineOperationalState
    let verificationState: RoutineVerificationState
    let lastVerifiedAt: Date?
}

enum RoutineReadinessReason: String, Codable, Equatable {
    case refreshInProgress
    case verified
    case deviceOffline
    case storeBusy
    case timerMissing
    case timerMismatch
    case targetMissing
    case invalidMetadata
    case snapshotSuperseded
    case readFailure
}

enum RoutineRetryAction: Equatable {
    case none
    case verifyReadOnly
    case resync
    case guidedRepair
}

enum RoutineRetryPolicy {
    static func action(
        syncState: AutomationMetadata.WLEDSyncState,
        readinessState: RoutineReadinessState,
        transactionStatus: PresetStoreTransactionStatus
    ) -> RoutineRetryAction {
        if transactionStatus == .needsRepair {
            return .guidedRepair
        }
        if transactionStatus == .saving
            || transactionStatus == .verifying
            || transactionStatus == .recovering {
            return .none
        }
        if readinessState == .checking {
            return .none
        }
        if transactionStatus == .verificationNeeded {
            return syncState == .synced ? .verifyReadOnly : .none
        }
        if readinessState == .verificationNeeded, syncState == .synced {
            return .verifyReadOnly
        }
        if readinessState == .verified, syncState == .synced {
            return .none
        }
        return .resync
    }
}

struct RoutineReadinessRecord: Codable, Equatable {
    let state: RoutineReadinessState
    let reason: RoutineReadinessReason
    let generation: DeviceAutomationGeneration?
    let verifiedAt: Date?
    let reconciledTimerSlot: Int?

    static let checking = RoutineReadinessRecord(
        state: .checking,
        reason: .refreshInProgress,
        generation: nil,
        verifiedAt: nil,
        reconciledTimerSlot: nil
    )

    static func verified(
        generation: DeviceAutomationGeneration,
        at date: Date,
        reconciledTimerSlot: Int? = nil
    ) -> RoutineReadinessRecord {
        RoutineReadinessRecord(
            state: .verified,
            reason: .verified,
            generation: generation,
            verifiedAt: date,
            reconciledTimerSlot: reconciledTimerSlot
        )
    }

    static func verificationNeeded(_ reason: RoutineReadinessReason) -> RoutineReadinessRecord {
        RoutineReadinessRecord(
            state: .verificationNeeded,
            reason: reason,
            generation: nil,
            verifiedAt: nil,
            reconciledTimerSlot: nil
        )
    }

    static func notReady(_ reason: RoutineReadinessReason) -> RoutineReadinessRecord {
        RoutineReadinessRecord(
            state: .notReady,
            reason: reason,
            generation: nil,
            verifiedAt: nil,
            reconciledTimerSlot: nil
        )
    }
}

enum RoutineReadinessEvidenceResolver {
    static func resolve(
        record: RoutineReadinessRecord?,
        receipt: RoutineVerificationReceipt?
    ) -> RoutineReadinessEvidence {
        switch record?.state {
        case .verified:
            return RoutineReadinessEvidence(
                operationalState: .lastKnownReady,
                verificationState: .current,
                lastVerifiedAt: record?.verifiedAt ?? receipt?.verifiedAt
            )
        case .checking:
            return RoutineReadinessEvidence(
                operationalState: receipt == nil ? .neverConfigured : .lastKnownReady,
                verificationState: .checking,
                lastVerifiedAt: receipt?.verifiedAt
            )
        case .verificationNeeded:
            return RoutineReadinessEvidence(
                operationalState: receipt == nil ? .neverConfigured : .lastKnownReady,
                verificationState: .temporarilyUnavailable,
                lastVerifiedAt: receipt?.verifiedAt
            )
        case .notReady:
            return RoutineReadinessEvidence(
                operationalState: .confirmedNotReady,
                verificationState: .current,
                lastVerifiedAt: receipt?.verifiedAt
            )
        case .none:
            return RoutineReadinessEvidence(
                operationalState: receipt == nil ? .neverConfigured : .lastKnownReady,
                verificationState: .notStarted,
                lastVerifiedAt: receipt?.verifiedAt
            )
        }
    }
}

/// Durable proof promoted only after one immutable live snapshot verifies the
/// owned timer row and target record together.
struct RoutineVerificationReceipt: Codable, Equatable {
    let key: RoutineDeviceKey
    let automationUpdatedAt: Date
    let generation: DeviceAutomationGeneration
    let timerSlot: Int
    let timerSignature: String
    let targetKind: RoutineTargetKind
    let targetRecordId: Int
    let targetRecordHash: String
    let verifiedAt: Date
}

struct RoutineVerificationReceiptEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var updatedAt: Date
    var receipts: [RoutineVerificationReceipt]
}

enum RoutineTargetKind: String, Codable, Equatable {
    case preset
    case playlist
}

struct RoutineVerificationExpectation: Equatable {
    let key: RoutineDeviceKey
    let storedTimerSlot: Int?
    let allowedTimerSlots: Set<Int>
    let acceptedTimerSignatures: Set<String>
    let macroId: Int?
    let targetKind: RoutineTargetKind
    let preflightFailure: RoutineReadinessReason?
}

enum PresetStoreContentState: String, Codable, Equatable {
    case unknown
    case verifiedHealthy
    case confirmedMalformed
    case recoveryExhausted
}

struct PresetStoreContentHealth: Codable, Equatable {
    let state: PresetStoreContentState
    let verifiedHash: String?
    let observedAt: Date?
    let message: String?

    static let unknown = PresetStoreContentHealth(
        state: .unknown,
        verifiedHash: nil,
        observedAt: nil,
        message: nil
    )

    static func healthy(hash: String?, at date: Date = Date()) -> PresetStoreContentHealth {
        PresetStoreContentHealth(
            state: .verifiedHealthy,
            verifiedHash: hash,
            observedAt: date,
            message: nil
        )
    }
}

enum TimerMutationOutcome: String, Codable, Equatable {
    case committed
    case notCommitted
    case verificationNeeded
}

enum CleanupResourceType: String, Codable, Hashable {
    case preset
    case playlist
    case timer
}

struct CleanupOwnershipEvidence: Codable, Equatable, Hashable {
    let recordHash: String?
    let semanticSignature: String?
    let markerKind: AesdeticWLEDPresetMarkerKind?
    let expectedTimerSignature: String?
    let ownerAutomationId: UUID?
    let ownerToken: String?

    init(
        recordHash: String?,
        semanticSignature: String?,
        markerKind: AesdeticWLEDPresetMarkerKind?,
        expectedTimerSignature: String?,
        ownerAutomationId: UUID?,
        ownerToken: String? = nil
    ) {
        self.recordHash = recordHash
        self.semanticSignature = semanticSignature
        self.markerKind = markerKind
        self.expectedTimerSignature = expectedTimerSignature
        self.ownerAutomationId = ownerAutomationId
        self.ownerToken = ownerToken
    }

    static let legacyUnverified = CleanupOwnershipEvidence(
        recordHash: nil,
        semanticSignature: nil,
        markerKind: nil,
        expectedTimerSignature: nil,
        ownerAutomationId: nil
    )

    var canAutomaticallyDeletePresetStoreRecord: Bool {
        recordHash != nil
            || semanticSignature != nil
            || (
                markerKind?.isInternalAsset == true
                    && resolvedOwnerToken != nil
            )
    }

    var canAutomaticallyDeleteTimer: Bool {
        expectedTimerSignature != nil
    }

    var resolvedOwnerToken: String? {
        ownerToken
            ?? ownerAutomationId.map(AesdeticWLEDPresetNameMarker.ownershipToken)
    }
}

struct CleanupDeleteTarget: Codable, Equatable, Hashable {
    let resourceType: CleanupResourceType
    let id: Int
    let ownership: CleanupOwnershipEvidence
}

enum CleanupTargetDisposition: String, Codable, Equatable {
    case deleted
    case alreadyAbsent
    case superseded
    case needsReview
}

struct ConditionalDeleteReport: Equatable {
    let outcome: PresetStoreMutationOutcome
    let deleted: Set<CleanupDeleteTarget>
    let alreadyAbsent: Set<CleanupDeleteTarget>
    let superseded: Set<CleanupDeleteTarget>
    let needsReview: Set<CleanupDeleteTarget>
}

enum CleanupJournalEntryState: String, Codable, Equatable {
    case active
    case needsReview
    case deadLetter
    case completed
}

struct CleanupJournalEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var updatedAt: Date
    var pendingDeletes: [PendingDeviceDelete]
    var pendingAutomationDeleteIds: [UUID]
}
