import XCTest
import SwiftUI
@testable import Aesdetic_Control

final class AutomationModelTests: XCTestCase {
    @MainActor
    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        _ condition: @MainActor @escaping () -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return condition()
    }
    
    func testSunriseTemplatePrefillBuildsTransition() {
        let device = WLEDDevice(
            id: "demo-device",
            name: "Aurora",
            ipAddress: "192.168.1.20",
            isOnline: true,
            brightness: 42,
            currentColor: .orange
        )
        let context = AutomationTemplate.Context(
            device: device,
            availableDevices: [device],
            defaultGradient: LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "#FFD8A8"),
                GradientStop(position: 1.0, hexColor: "#FFFFFF")
            ])
        )
        
        let prefill = AutomationTemplate.sunrise.prefill(for: context)
        
        switch prefill.trigger {
        case .sunrise(let offsetMinutes):
            XCTAssertEqual(offsetMinutes, -15)
        default:
            XCTFail("Expected sunrise trigger")
        }
        
        switch prefill.action {
        case .transition(let payload, let duration, let endBrightness):
            XCTAssertEqual(Int(duration ?? 0), 1800)
            XCTAssertEqual(endBrightness, 255)
            XCTAssertEqual(payload.presetName, "Sunrise Glow")
            XCTAssertEqual(payload.startBrightness, 6)
            XCTAssertEqual(payload.endGradient.stops.count, 2)
        default:
            XCTFail("Expected transition payload")
        }
        
        XCTAssertEqual(prefill.metadata?.templateId, "sunrise")
    }
    
    func testTimeTriggerNextDateAdvancesToNextValidDay() {
        var trigger = TimeTrigger(time: "06:30", weekdays: [false, true, true, true, true, true, false])
        let calendar = Calendar(identifier: .gregorian)
        let mondayComponents = DateComponents(calendar: calendar, year: 2025, month: 1, day: 6, hour: 7, minute: 0) // Monday
        let reference = calendar.date(from: mondayComponents)!
        guard let nextDate = trigger.nextTriggerDate(referenceDate: reference, calendar: calendar) else {
            return XCTFail("Expected next trigger date")
        }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: nextDate)
        XCTAssertEqual(components.weekday, 3) // Tuesday
        XCTAssertEqual(components.hour, 6)
        XCTAssertEqual(components.minute, 30)
    }

    func testAutomationMetadataSyncStateDefaultsToUnknown() {
        let metadata = AutomationMetadata()
        XCTAssertEqual(metadata.syncState(for: "device-1"), .unknown)
        XCTAssertNil(metadata.lastSyncError(for: "device-1"))
        XCTAssertNil(metadata.lastSyncAt(for: "device-1"))
    }

    func testAutomationMetadataPerDeviceSyncStateHelpers() {
        let now = Date()
        let metadata = AutomationMetadata(
            wledSyncStateByDevice: ["a": .synced, "b": .notSynced],
            wledLastSyncErrorByDevice: ["b": "Timer mismatch"],
            wledLastSyncAtByDevice: ["a": now]
        )
        XCTAssertEqual(metadata.syncState(for: "a"), .synced)
        XCTAssertEqual(metadata.syncState(for: "b"), .notSynced)
        XCTAssertEqual(metadata.syncState(for: "missing"), .unknown)
        XCTAssertEqual(metadata.lastSyncError(for: "b"), "Timer mismatch")
        XCTAssertNil(metadata.lastSyncError(for: "a"))
        XCTAssertEqual(metadata.lastSyncAt(for: "a"), now)
    }

    func testAutomationMetadataSyncStateRoundTripCodable() throws {
        let original = AutomationMetadata(
            wledSyncStateByDevice: ["d1": .syncing, "d2": .synced]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutomationMetadata.self, from: data)
        XCTAssertEqual(decoded.wledSyncStateByDevice?["d1"], .syncing)
        XCTAssertEqual(decoded.wledSyncStateByDevice?["d2"], .synced)
    }

    func testAutomationMacroAssetKindMapping() {
        XCTAssertEqual(
            AutomationAction.playlist(PlaylistActionPayload(playlistId: 1, playlistName: nil)).macroAssetKind,
            .playlist
        )
        XCTAssertEqual(
            AutomationAction.transition(
                TransitionActionPayload(
                    startGradient: LEDGradient(stops: [GradientStop(position: 0, hexColor: "FFA000"), GradientStop(position: 1, hexColor: "FFFFFF")]),
                    startBrightness: 100,
                    endGradient: LEDGradient(stops: [GradientStop(position: 0, hexColor: "FFFFFF"), GradientStop(position: 1, hexColor: "FFA000")]),
                    endBrightness: 120,
                    durationSeconds: 60
                )
            ).macroAssetKind,
            .playlist
        )
        XCTAssertEqual(
            AutomationAction.preset(PresetActionPayload(presetId: 8, paletteName: nil, durationSeconds: nil)).macroAssetKind,
            .preset
        )
        XCTAssertEqual(
            AutomationAction.gradient(
                GradientActionPayload(
                    gradient: LEDGradient(stops: [GradientStop(position: 0, hexColor: "FFFFFF"), GradientStop(position: 1, hexColor: "FFFFFF")]),
                    brightness: 128,
                    durationSeconds: 0
                )
            ).macroAssetKind,
            .preset
        )
    }

    func testAutomationMetadataManagedSignaturesRoundTripCodable() throws {
        let original = AutomationMetadata(
            wledManagedPlaylistSignatureByDevice: ["d1": "playlist-signature"],
            wledManagedPresetSignatureByDevice: ["d1": "preset-signature"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutomationMetadata.self, from: data)
        XCTAssertEqual(decoded.managedPlaylistSignature(for: "d1"), "playlist-signature")
        XCTAssertEqual(decoded.managedPresetSignature(for: "d1"), "preset-signature")
    }

    func testClearWLEDMacroMetadataResetsTargetedDeviceState() {
        var metadata = AutomationMetadata(
            wledPlaylistId: 42,
            wledPlaylistIdsByDevice: ["d1": 42, "d2": 43],
            wledPresetIdsByDevice: ["d1": 11, "d2": 12],
            wledManagedPlaylistSignatureByDevice: ["d1": "playlist", "d2": "other"],
            wledManagedPresetSignatureByDevice: ["d1": "preset", "d2": "other"],
            wledSyncStateByDevice: ["d1": .synced, "d2": .synced],
            wledLastSyncErrorByDevice: ["d1": "error"],
            wledLastSyncAtByDevice: ["d1": Date()]
        )

        metadata.clearWLEDMacroMetadata(for: ["d1"], preserveTimerSlots: true)

        XCTAssertNil(metadata.wledPlaylistIdsByDevice?["d1"])
        XCTAssertEqual(metadata.wledPlaylistIdsByDevice?["d2"], 43)
        XCTAssertNil(metadata.wledPresetIdsByDevice?["d1"])
        XCTAssertEqual(metadata.wledPresetIdsByDevice?["d2"], 12)
        XCTAssertEqual(metadata.syncState(for: "d1"), .unknown)
        XCTAssertNil(metadata.lastSyncError(for: "d1"))
        XCTAssertNil(metadata.lastSyncAt(for: "d1"))
        XCTAssertNil(metadata.managedPlaylistSignature(for: "d1"))
        XCTAssertNil(metadata.managedPresetSignature(for: "d1"))
    }

    func testNormalizeWLEDScalarFallbacksClearsMultiTargetScalars() {
        var metadata = AutomationMetadata(
            wledPlaylistId: 99,
            wledTimerSlot: 7,
            wledPlaylistIdsByDevice: ["d1": 10, "d2": 20],
            wledTimerSlotsByDevice: ["d1": 3, "d2": 4]
        )

        metadata.normalizeWLEDScalarFallbacks(for: ["d1", "d2"])

        XCTAssertNil(metadata.wledPlaylistId)
        XCTAssertNil(metadata.wledTimerSlot)
        XCTAssertEqual(metadata.wledPlaylistIdsByDevice?["d1"], 10)
        XCTAssertEqual(metadata.wledTimerSlotsByDevice?["d2"], 4)
    }

    func testNormalizeWLEDScalarFallbacksUsesSingleTargetMaps() {
        var metadata = AutomationMetadata(
            wledPlaylistId: 88,
            wledTimerSlot: 2,
            wledPlaylistIdsByDevice: ["target": 11, "stale": 44],
            wledTimerSlotsByDevice: ["target": 6, "stale": 9]
        )

        metadata.normalizeWLEDScalarFallbacks(for: ["target"])

        XCTAssertEqual(metadata.wledPlaylistId, 11)
        XCTAssertEqual(metadata.wledTimerSlot, 6)
        XCTAssertEqual(metadata.wledPlaylistIdsByDevice?["target"], 11)
        XCTAssertNil(metadata.wledPlaylistIdsByDevice?["stale"])
        XCTAssertEqual(metadata.wledTimerSlotsByDevice?["target"], 6)
        XCTAssertNil(metadata.wledTimerSlotsByDevice?["stale"])
    }

    @MainActor
    func testLocalTimerCapacityBlocksNinthSpecificTimeAutomation() {
        let store = AutomationStore.shared
        let original = store.automations
        defer { store.automations = original }

        let deviceId = "device-capacity"
        store.automations = (0..<8).map { idx in
            makeOnDeviceAutomation(
                name: "Time \(idx)",
                trigger: .specificTime(
                    TimeTrigger(
                        time: String(format: "%02d:00", idx),
                        weekdays: WeekdayMask.allDaysSunFirst,
                        timezoneIdentifier: TimeZone.current.identifier
                    )
                ),
                deviceId: deviceId
            )
        }

        let validation = store.validateLocalTimerCapacity(
            triggerKind: .specificTime,
            targetDeviceIds: [deviceId]
        )

        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.message?.contains("max 8") == true)
    }

    @MainActor
    func testLocalTimerCapacitySunriseAndSunsetExclusivity() {
        let store = AutomationStore.shared
        let original = store.automations
        defer { store.automations = original }

        let deviceId = "device-solar"
        store.automations = [
            makeOnDeviceAutomation(
                name: "Sunrise Existing",
                trigger: .sunrise(
                    SolarTrigger(
                        offset: .minutes(0),
                        location: .followDevice,
                        weekdays: WeekdayMask.allDaysSunFirst
                    )
                ),
                deviceId: deviceId
            )
        ]

        let sunriseValidation = store.validateLocalTimerCapacity(
            triggerKind: .sunrise,
            targetDeviceIds: [deviceId]
        )
        XCTAssertFalse(sunriseValidation.isValid)
        XCTAssertTrue(sunriseValidation.message?.contains("slot 8") == true)

        let sunsetValidation = store.validateLocalTimerCapacity(
            triggerKind: .sunset,
            targetDeviceIds: [deviceId]
        )
        XCTAssertTrue(sunsetValidation.isValid)
    }

    @MainActor
    func testUpdateClearsMacroMetadataWhenActionKindChanges() {
        let store = AutomationStore.shared
        let original = store.automations
        defer { store.automations = original }

        let deviceId = "device-macro-reset"
        var automation = makeOnDeviceAutomation(
            name: "Macro Reset",
            trigger: .specificTime(
                TimeTrigger(
                    time: "12:00",
                    weekdays: WeekdayMask.allDaysSunFirst,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            ),
            deviceId: deviceId
        )
        automation.action = .playlist(PlaylistActionPayload(playlistId: 12, playlistName: "Demo"))
        automation.metadata.wledPlaylistId = 12
        automation.metadata.wledPlaylistIdsByDevice = [deviceId: 12]
        automation.metadata.wledSyncStateByDevice = [deviceId: .synced]
        store.automations = [automation]

        var edited = automation
        edited.action = .preset(PresetActionPayload(presetId: 5, paletteName: "Warm", durationSeconds: nil))
        store.update(edited, syncOnDevice: false)

        guard let updated = store.automations.first else {
            return XCTFail("Expected updated automation")
        }
        XCTAssertNil(updated.metadata.wledPlaylistIdsByDevice?[deviceId])
        XCTAssertEqual(updated.metadata.syncState(for: deviceId), .unknown)
    }

    @MainActor
    func testDeleteManagedTransitionAutomationEnqueuesPlaylistAndStepPresetCleanup() async {
        let store = AutomationStore.shared
        let cleanup = DeviceCleanupManager.shared
        let originalAutomations = store.automations
        defer {
            store.automations = originalAutomations
        }

        let deviceId = "cleanup-test-\(UUID().uuidString)"
        let timerSlot = 2
        let playlistId = 211
        let stepPresetIds = [212, 213, 214]

        defer {
            cleanup.removeIds(type: .timer, deviceId: deviceId, ids: [timerSlot])
            cleanup.removeIds(type: .playlist, deviceId: deviceId, ids: [playlistId])
            cleanup.removeIds(type: .preset, deviceId: deviceId, ids: stepPresetIds)
        }

        let transition = TransitionActionPayload(
            startGradient: LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "FFA000"),
                GradientStop(position: 1.0, hexColor: "FFFFFF")
            ]),
            startBrightness: 128,
            endGradient: LEDGradient(stops: [
                GradientStop(position: 0.0, hexColor: "FFFFFF"),
                GradientStop(position: 1.0, hexColor: "59A4FF")
            ]),
            endBrightness: 128,
            durationSeconds: 180
        )

        var automation = Automation(
            name: "Managed Transition Cleanup",
            trigger: .specificTime(TimeTrigger(time: "08:00", weekdays: WeekdayMask.allDaysSunFirst)),
            action: .transition(transition),
            targets: AutomationTargets(deviceIds: [deviceId])
        )
        automation.metadata.wledPlaylistIdsByDevice = [deviceId: playlistId]
        automation.metadata.wledTimerSlotsByDevice = [deviceId: timerSlot]
        automation.metadata.wledManagedPlaylistSignatureByDevice = [deviceId: "sig-transition"]
        automation.metadata.wledManagedStepPresetIdsByDevice = [deviceId: stepPresetIds]

        store.automations = [automation]
        store.delete(id: automation.id)
        let deleteFinished = await waitForCondition {
            !store.isDeletionInProgress(for: automation.id)
        }
        XCTAssertTrue(deleteFinished, "Expected managed transition delete to finish")

        XCTAssertTrue(cleanup.hasActiveDelete(type: .timer, deviceId: deviceId, id: timerSlot))
        XCTAssertTrue(cleanup.hasActiveDelete(type: .playlist, deviceId: deviceId, id: playlistId))
        for stepId in stepPresetIds {
            XCTAssertTrue(cleanup.hasActiveDelete(type: .preset, deviceId: deviceId, id: stepId))
        }
    }

    @MainActor
    func testDeleteUserSelectedPresetAndPlaylistActionsPreserveUnderlyingAssets() async {
        let store = AutomationStore.shared
        let cleanup = DeviceCleanupManager.shared
        let originalAutomations = store.automations
        defer {
            store.automations = originalAutomations
        }

        let deviceId = "cleanup-test-user-assets-\(UUID().uuidString)"
        let timerSlot = 4
        let userPresetId = 77
        let userPlaylistId = 78

        defer {
            cleanup.removeIds(type: .timer, deviceId: deviceId, ids: [timerSlot])
            cleanup.removeIds(type: .preset, deviceId: deviceId, ids: [userPresetId])
            cleanup.removeIds(type: .playlist, deviceId: deviceId, ids: [userPlaylistId])
        }

        var presetAutomation = Automation(
            name: "User Preset Action",
            trigger: .specificTime(TimeTrigger(time: "09:00", weekdays: WeekdayMask.allDaysSunFirst)),
            action: .preset(PresetActionPayload(presetId: userPresetId, paletteName: "User preset", durationSeconds: nil)),
            targets: AutomationTargets(deviceIds: [deviceId])
        )
        presetAutomation.metadata.wledTimerSlotsByDevice = [deviceId: timerSlot]

        var playlistAutomation = Automation(
            name: "User Playlist Action",
            trigger: .specificTime(TimeTrigger(time: "10:00", weekdays: WeekdayMask.allDaysSunFirst)),
            action: .playlist(PlaylistActionPayload(playlistId: userPlaylistId, playlistName: "User playlist")),
            targets: AutomationTargets(deviceIds: [deviceId])
        )
        playlistAutomation.metadata.wledTimerSlotsByDevice = [deviceId: timerSlot]

        store.automations = [presetAutomation, playlistAutomation]

        store.delete(id: presetAutomation.id)
        let presetDeleteFinished = await waitForCondition {
            !store.isDeletionInProgress(for: presetAutomation.id)
        }
        XCTAssertTrue(presetDeleteFinished, "Expected preset automation delete to finish")
        XCTAssertFalse(cleanup.hasActiveDelete(type: .timer, deviceId: deviceId, id: timerSlot))
        XCTAssertFalse(cleanup.hasActiveDelete(type: .preset, deviceId: deviceId, id: userPresetId))

        store.delete(id: playlistAutomation.id)
        let playlistDeleteFinished = await waitForCondition {
            !store.isDeletionInProgress(for: playlistAutomation.id)
        }
        XCTAssertTrue(playlistDeleteFinished, "Expected playlist automation delete to finish")
        XCTAssertTrue(cleanup.hasActiveDelete(type: .timer, deviceId: deviceId, id: timerSlot))
        XCTAssertFalse(cleanup.hasActiveDelete(type: .playlist, deviceId: deviceId, id: userPlaylistId))
    }

    func testSelectTimerSlotDoesNotReuseActionableMacroWhenDisabled() {
        let timers = [
            WLEDTimer(id: 0, enabled: false, hour: 8, minute: 30, days: 0x7F, macroId: 99, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil),
            WLEDTimer(id: 1, enabled: false, hour: 0, minute: 0, days: 0x7F, macroId: 0, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil),
            WLEDTimer(id: 2, enabled: false, hour: 0, minute: 0, days: 0x7F, macroId: 0, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil)
        ]

        let selection = AutomationStore._selectTimerSlotForTesting(
            existingSlot: nil,
            preferredSlot: 0,
            allowedSlots: Set([0, 1, 2]),
            timers: timers,
            reservedSlots: Set<Int>(),
            reclaimableSlots: Set<Int>()
        )

        XCTAssertEqual(selection?.slot, 1)
        XCTAssertEqual(selection?.reason, "free")
    }

    func testSelectTimerSlotAllowsReclaimableOccupiedSlot() {
        let timers = [
            WLEDTimer(id: 0, enabled: true, hour: 6, minute: 0, days: 0x7F, macroId: 88, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil),
            WLEDTimer(id: 1, enabled: false, hour: 0, minute: 0, days: 0x7F, macroId: 0, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil)
        ]

        let selection = AutomationStore._selectTimerSlotForTesting(
            existingSlot: nil,
            preferredSlot: 0,
            allowedSlots: Set([0, 1]),
            timers: timers,
            reservedSlots: Set<Int>(),
            reclaimableSlots: Set([0])
        )

        XCTAssertEqual(selection?.slot, 0)
        XCTAssertEqual(selection?.reason, "reclaimable")
    }

    func testSelectTimerSlotAlwaysReusesExistingSlotFirst() {
        let timers = [
            WLEDTimer(id: 0, enabled: true, hour: 7, minute: 0, days: 0x7F, macroId: 77, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil),
            WLEDTimer(id: 1, enabled: false, hour: 0, minute: 0, days: 0x7F, macroId: 0, startMonth: nil, startDay: nil, endMonth: nil, endDay: nil)
        ]

        let selection = AutomationStore._selectTimerSlotForTesting(
            existingSlot: 0,
            preferredSlot: 1,
            allowedSlots: Set([0, 1]),
            timers: timers,
            reservedSlots: Set<Int>(),
            reclaimableSlots: Set<Int>()
        )

        XCTAssertEqual(selection?.slot, 0)
        XCTAssertEqual(selection?.reason, "existing")
    }

    private func makeOnDeviceAutomation(
        name: String,
        trigger: AutomationTrigger,
        deviceId: String
    ) -> Automation {
        Automation(
            name: name,
            trigger: trigger,
            action: .preset(PresetActionPayload(presetId: 1, paletteName: "Test", durationSeconds: nil)),
            targets: AutomationTargets(deviceIds: [deviceId], syncGroupName: nil, allowPartialFailure: false),
            metadata: AutomationMetadata(runOnDevice: true)
        )
    }
}
