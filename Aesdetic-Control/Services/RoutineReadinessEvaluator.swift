import Foundation

/// Pure routine readiness evaluation. Network reads, metadata reconciliation,
/// and publication remain owned by AutomationStore.
enum RoutineReadinessEvaluator {
    static func evaluate(
        expectations: [RoutineVerificationExpectation],
        snapshot: DeviceAutomationSnapshot
    ) -> [RoutineDeviceKey: RoutineReadinessRecord] {
        var results: [RoutineDeviceKey: RoutineReadinessRecord] = [:]
        results.reserveCapacity(expectations.count)

        for expectation in expectations {
            if let failure = expectation.preflightFailure {
                results[expectation.key] = .notReady(failure)
                continue
            }
            guard let macroId = expectation.macroId,
                  (1...250).contains(macroId),
                  let storedSlot = expectation.storedTimerSlot,
                  !expectation.acceptedTimerSignatures.isEmpty else {
                results[expectation.key] = .notReady(.invalidMetadata)
                continue
            }

            let targetExists: Bool
            switch expectation.targetKind {
            case .preset:
                targetExists = snapshot.presetIds.contains(macroId)
            case .playlist:
                targetExists = snapshot.playlistIds.contains(macroId)
            }
            guard targetExists else {
                results[expectation.key] = .notReady(.targetMissing)
                continue
            }

            if let storedTimer = snapshot.timers.first(where: { $0.id == storedSlot }),
               expectation.acceptedTimerSignatures.contains(timerSignature(for: storedTimer)) {
                results[expectation.key] = .verified(
                    generation: snapshot.generation,
                    at: snapshot.capturedAt
                )
                continue
            }

            let matchingRows = snapshot.timers
                .filter {
                    expectation.allowedTimerSlots.contains($0.id)
                        && expectation.acceptedTimerSignatures.contains(timerSignature(for: $0))
                }
                .sorted { $0.id < $1.id }

            if matchingRows.count == 1, let match = matchingRows.first {
                results[expectation.key] = .verified(
                    generation: snapshot.generation,
                    at: snapshot.capturedAt,
                    reconciledTimerSlot: match.id
                )
            } else {
                let storedRowExists = snapshot.timers.contains { $0.id == storedSlot }
                results[expectation.key] = .notReady(storedRowExists ? .timerMismatch : .timerMissing)
            }
        }

        return results
    }

    static func timerSignature(for timer: WLEDTimer) -> String {
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

    static func timerSignature(
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
        let window = normalizedTimerDateWindow(
            startMonth: startMonth,
            startDay: startDay,
            endMonth: endMonth,
            endDay: endDay
        )
        return "\(enabled ? 1 : 0)|\(hour)|\(minute)|\(days)|\(macroId)|\(window.startMonth ?? 0)|\(window.startDay ?? 0)|\(window.endMonth ?? 0)|\(window.endDay ?? 0)"
    }

    private static func normalizedTimerDateWindow(
        startMonth: Int?,
        startDay: Int?,
        endMonth: Int?,
        endDay: Int?
    ) -> (startMonth: Int?, startDay: Int?, endMonth: Int?, endDay: Int?) {
        let values = [startMonth, startDay, endMonth, endDay].map { max(0, $0 ?? 0) }
        if values.allSatisfy({ $0 == 0 }) {
            return (nil, nil, nil, nil)
        }
        guard startMonth != nil, startDay != nil, endMonth != nil, endDay != nil else {
            return (nil, nil, nil, nil)
        }
        if startMonth == 1, startDay == 1, endMonth == 12, endDay == 31 {
            return (nil, nil, nil, nil)
        }
        return (startMonth, startDay, endMonth, endDay)
    }
}
