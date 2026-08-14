import Foundation
import Observation

enum DeviceBehaviorTransition: Int, CaseIterable, Identifiable {
    case instant = 0
    case quick = 300
    case smooth = 700
    case slow = 1500

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .instant: return "Instant"
        case .quick: return "Quick"
        case .smooth: return "Smooth"
        case .slow: return "Slow"
        }
    }
}

enum DeviceBehaviorSaveStatus: Equatable {
    case idle
    case loading
    case saving
    case saved
    case restartRequired
    case failed(String)

    var text: String? {
        switch self {
        case .idle: return nil
        case .loading: return "Loading behavior settings..."
        case .saving: return "Saving..."
        case .saved: return "Saved"
        case .restartRequired: return "Restart required"
        case .failed(let message): return message
        }
    }
}

@MainActor
@Observable
final class DeviceBehaviorSettingsStore {
    private(set) var powerOnAfterRestart = true
    private(set) var maximumBrightness = 100
    private(set) var transitionMilliseconds = DeviceBehaviorTransition.smooth.rawValue
    private(set) var status: DeviceBehaviorSaveStatus = .idle

    private let device: WLEDDevice
    private let service: WLEDAdvancedSettingsService
    private var confirmedValues: [String: WLEDSettingValue] = [:]
    private var pendingChanges: [String: WLEDSettingValue] = [:]
    private var saveTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init(
        device: WLEDDevice,
        service: WLEDAdvancedSettingsService = .shared
    ) {
        self.device = device
        self.service = service
    }

    var isLoading: Bool {
        status == .loading
    }

    var isSaving: Bool {
        status == .saving
    }

    var hasCustomBrightness: Bool {
        maximumBrightness > 100
    }

    var selectedTransition: DeviceBehaviorTransition? {
        DeviceBehaviorTransition(rawValue: transitionMilliseconds)
    }

    func load() async {
        guard confirmedValues.isEmpty, status != .loading else { return }
        status = .loading
        do {
            let draft = try await service.fetchDraft(categoryID: "led-hardware", for: device)
            confirmedValues = draft.values
            apply(values: draft.values, excluding: [])
            status = .idle
        } catch is CancellationError {
            return
        } catch {
            status = .failed("Could not load behavior settings.")
        }
    }

    func setPowerOnAfterRestart(_ enabled: Bool) {
        powerOnAfterRestart = enabled
        enqueue(.bool(enabled), for: "BO")
    }

    func previewMaximumBrightness(_ value: Double) {
        maximumBrightness = max(1, min(100, Int(value.rounded())))
    }

    func commitMaximumBrightness() {
        enqueue(.number(Double(maximumBrightness)), for: "BF")
    }

    func setTransition(_ transition: DeviceBehaviorTransition) {
        transitionMilliseconds = transition.rawValue
        enqueue(.number(Double(transition.rawValue) / 100.0), for: "TD")
    }

    func retry() {
        guard case .failed = status else { return }
        Task { await loadFreshValues() }
    }

    private func enqueue(_ value: WLEDSettingValue, for key: String) {
        pendingChanges[key] = value
        statusTask?.cancel()
        status = .saving
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            await self?.flushPendingChanges()
        }
    }

    private func flushPendingChanges() async {
        while !pendingChanges.isEmpty {
            let changes = pendingChanges
            pendingChanges.removeAll()

            do {
                var draft = try await service.fetchDraft(categoryID: "led-hardware", for: device)
                for (key, value) in changes {
                    draft.setValue(value, for: key)
                }
                let result = try await service.saveDraft(draft, for: device)
                let refreshed = try await service.fetchDraft(categoryID: "led-hardware", for: device)
                confirmedValues = refreshed.values
                apply(values: refreshed.values, excluding: Set(pendingChanges.keys))
                status = result.statusText == "Restart Required" ? .restartRequired : .saved
            } catch is CancellationError {
                break
            } catch {
                rollback(keys: Set(changes.keys).subtracting(pendingChanges.keys))
                status = .failed("Could not save. Tap to retry.")
            }
        }

        saveTask = nil
        scheduleStatusResetIfNeeded()
    }

    private func loadFreshValues() async {
        status = .loading
        do {
            let draft = try await service.fetchDraft(categoryID: "led-hardware", for: device)
            confirmedValues = draft.values
            apply(values: draft.values, excluding: Set(pendingChanges.keys))
            status = .idle
        } catch {
            status = .failed("Could not load behavior settings.")
        }
    }

    private func rollback(keys: Set<String>) {
        apply(values: confirmedValues, including: keys)
    }

    private func apply(values: [String: WLEDSettingValue], excluding keys: Set<String>) {
        apply(values: values, including: Set(["BO", "BF", "TD"]).subtracting(keys))
    }

    private func apply(values: [String: WLEDSettingValue], including keys: Set<String>) {
        if keys.contains("BO"), let value = values["BO"] {
            powerOnAfterRestart = value.boolValue
        }
        if keys.contains("BF"), let value = values["BF"] {
            maximumBrightness = max(1, Int(value.numberValue.rounded()))
        }
        if keys.contains("TD"), let value = values["TD"] {
            transitionMilliseconds = max(0, Int((value.numberValue * 100).rounded()))
        }
    }

    private func scheduleStatusResetIfNeeded() {
        guard status == .saved else { return }
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, self?.status == .saved else { return }
            self?.status = .idle
        }
    }
}
