import CoreLocation
import SwiftUI
import UIKit

struct AddAutomationDialog: View {
    enum TriggerSelection: String, CaseIterable, Identifiable {
        case time = "Specific Time"
        case sunrise = "Sunrise"
        case sunset = "Sunset"
        var id: String { rawValue }

        var tabIndex: Int {
            switch self {
            case .time: return 0
            case .sunrise: return 1
            case .sunset: return 2
            }
        }
    }

    enum ActionSelection: String, CaseIterable, Identifiable {
        case color = "Colors"
        case transition = "Transitions"
        case effect = "Animations"
        case scene = "Scene"

        var id: String { rawValue }

        var systemImageName: String {
            switch self {
            case .color: return "paintpalette"
            case .transition: return "arrow.triangle.2.circlepath"
            case .effect: return "sparkles"
            case .scene: return "square.stack.3d.up"
            }
        }
    }

    enum PresentationStyle {
        case sheet
        case embedded
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var presetsStore = PresetsStore.shared
    @ObservedObject private var automationStore = AutomationStore.shared
    let device: WLEDDevice
    let scenes: [Scene]
    let effectOptions: [EffectMetadata]
    let availableDevices: [WLEDDevice]
    @ObservedObject var viewModel: DeviceControlViewModel
    let defaultName: String?
    let editingAutomation: Automation?
    let allowSceneAction: Bool
    let presentationStyle: PresentationStyle
    var onCancel: (() -> Void)?
    var onSave: (Automation) -> Bool

    @State private var automationName: String
    @State private var selectedDeviceIds: Set<String>
    @State private var activeDevice: WLEDDevice
    @State private var triggerSelection: TriggerSelection = .time
    @State private var selectedTime: Date = Date()
    @State private var selectedWeekdays: [Bool] = WeekdayMask.allDaysSunFirst
    @State private var draggingSelects: Bool? = nil  // Tracks swipe mode: true = selecting, false = deselecting
    @State private var solarOffsetMinutes: Double = 0
    @State private var useDateWindow: Bool = false
    @State private var startMonth: Int = 1
    @State private var startDay: Int = 1
    @State private var endMonth: Int = 12
    @State private var endDay: Int = 31
    @State private var isValidatingOnDeviceSchedule: Bool = false
    @State private var onDeviceScheduleValidationMessage: String?
    @State private var onDeviceScheduleValidationIsWarning: Bool = false
    @State private var onDeviceScheduleOverlapWarningMessage: String?
    @State private var showLocationSettingsAlert: Bool = false
    @State private var presetSlotLoadingKey: String?

    @State private var actionSelection: ActionSelection = .color
    @State private var actionPreviewEnabled: Bool = false
    @State private var selectedSceneId: UUID?
    @State private var sceneBrightnessOverride: Int? = nil
    @State private var selectedEffectId: Int?
    @State private var effectBrightness: Double
    @State private var effectSpeed: Int = 128
    @State private var effectIntensity: Int = 128
    @State private var effectGradient: LEDGradient?
    @State private var gradientBrightness: Double
    @State private var gradientDuration: Double = 10
    @State private var gradientInterpolation: GradientInterpolation = .linear
    @State private var colorPowerOn: Bool = true
    @State private var selectedColorPresetId: UUID?
    @State private var gradientTemperature: Double?
    @State private var gradientWhiteLevel: Double?
    @State private var selectedTransitionPresetId: UUID?
    @State private var selectedEffectPresetId: UUID?
    @State private var enableColorFade: Bool = false
    @State private var customTransitionDuration: Double = 600
    @State private var allowPartialFailure: Bool = true
    @State private var templateGradient: LEDGradient?
    @State private var templateTransition: TransitionActionPayload?
    // Transition editor state
    @State private var transitionStartGradient: LEDGradient?
    @State private var transitionEndGradient: LEDGradient?
    @State private var transitionStartBrightness: Double = 128
    @State private var transitionEndBrightness: Double = 255
    @State private var transitionStartTemperature: Double?
    @State private var transitionStartWhiteLevel: Double?
    @State private var transitionEndTemperature: Double?
    @State private var transitionEndWhiteLevel: Double?
    @State private var transitionSchedulePreviewStart: Date?
    @State private var transitionSchedulePreviewEnd: Date?
    @State private var transitionSchedulePreviewTimeZone: TimeZone = .current
    @State private var templateEffectSettings: TemplateEffectSettings?
    @State private var templateMetadata: AutomationMetadata?
    @State private var lockedAction: AutomationAction?
    @State private var isEditingName: Bool = false
    @FocusState private var isNameFieldFocused: Bool
    @AppStorage("advancedUIEnabled") private var advancedUIEnabled: Bool = false

    private var isEditing: Bool { editingAutomation != nil }

    private static func defaultTriggerSelection(
        for targetDeviceIds: Set<String>,
        automations: [Automation],
        excludingAutomationId: UUID? = nil
    ) -> TriggerSelection {
        let targets = targetDeviceIds
        let matchingAutomations = automations.filter { automation in
            if automation.id == excludingAutomationId {
                return false
            }
            return !Set(automation.targets.deviceIds).isDisjoint(with: targets)
        }
        let hasSunrise = matchingAutomations.contains { automation in
            if case .sunrise = automation.trigger {
                return true
            }
            return false
        }
        let hasSunset = matchingAutomations.contains { automation in
            if case .sunset = automation.trigger {
                return true
            }
            return false
        }

        if !hasSunrise {
            return .sunrise
        }
        if !hasSunset {
            return .sunset
        }
        return .time
    }

    private struct TemplateEffectSettings {
        let gradient: LEDGradient?
        let speed: Int
        let intensity: Int
    }

    private struct WeekdaySelectionRun: Identifiable {
        let startIndex: Int
        let endIndex: Int

        var id: String { "\(startIndex)-\(endIndex)" }
    }

    init(
        device: WLEDDevice,
        scenes: [Scene],
        effectOptions: [EffectMetadata],
        availableDevices: [WLEDDevice],
        viewModel: DeviceControlViewModel,
        defaultName: String? = nil,
        editingAutomation: Automation? = nil,
        templatePrefill: AutomationTemplate.Prefill? = nil,
        allowSceneAction: Bool = true,
        presentationStyle: PresentationStyle = .sheet,
        onCancel: (() -> Void)? = nil,
        onSave: @escaping (Automation) -> Bool
    ) {
        self.device = device
        self.scenes = scenes
        self.effectOptions = effectOptions
        self.availableDevices = availableDevices.isEmpty ? [device] : availableDevices
        self.viewModel = viewModel
        self.defaultName = defaultName
        self.editingAutomation = editingAutomation
        self.allowSceneAction = allowSceneAction
        self.presentationStyle = presentationStyle
        self.onCancel = onCancel
        self.onSave = onSave

        var initialActiveDevice = self.availableDevices.first(where: { $0.id == device.id }) ?? self.availableDevices.first ?? device

        var initialName = defaultName ?? "\(device.name) Automation"
        var initialDeviceIds = Set([initialActiveDevice.id])
        var initialTriggerSelection: TriggerSelection = .time
        var initialTime = Date()
        var initialWeekdays = WeekdayMask.allDaysSunFirst
        var initialSolarOffset: Double = 0
        var initialUseDateWindow = false
        var initialStartMonth = 1
        var initialStartDay = 1
        var initialEndMonth = 12
        var initialEndDay = 31
        var initialActionSelection: ActionSelection = .color
        var initialSelectedSceneId: UUID?
        var initialSceneBrightnessOverride: Int?
        var initialEffectId: Int? = effectOptions.first?.id
        var initialEffectBrightness = Double(device.brightness)
        var initialEffectSpeed: Int = 128
        var initialEffectIntensity: Int = 128
        var initialEffectGradient: LEDGradient?
        var initialGradientBrightness = Double(device.brightness)
        var initialGradientDuration: Double = 10
        var initialEnableColorFade = false
        var initialColorPowerOn = true
        var initialTransitionDuration: Double = 600
        var initialTemplateGradient: LEDGradient?
        var initialGradientTemperature: Double?
        var initialGradientWhiteLevel: Double?
        var initialTemplateTransition: TransitionActionPayload?
        var initialTemplateEffect: TemplateEffectSettings?
        var initialMetadata: AutomationMetadata?
        var initialAllowPartial = true
        var initialTransitionStartGradient: LEDGradient?
        var initialTransitionEndGradient: LEDGradient?
        var initialTransitionStartBrightness: Double = 128
        var initialTransitionEndBrightness: Double = 255
        var initialTransitionStartTemperature: Double?
        var initialTransitionStartWhiteLevel: Double?
        var initialTransitionEndTemperature: Double?
        var initialTransitionEndWhiteLevel: Double?
        var initialSelectedColorPresetId: UUID?
        var initialSelectedTransitionPresetId: UUID?
        var initialSelectedEffectPresetId: UUID?
        var initialLockedAction: AutomationAction? = nil

        if let editing = editingAutomation {
            initialName = editing.name
            initialDeviceIds = Set(editing.targets.deviceIds)
            initialAllowPartial = editing.targets.allowPartialFailure
            if let firstId = editing.targets.deviceIds.first,
               let resolved = self.availableDevices.first(where: { $0.id == firstId }) {
                initialActiveDevice = resolved
            }
            switch editing.trigger {
            case .specificTime(let trigger):
                initialTriggerSelection = .time
                if let date = Self.dateFrom(timeString: trigger.time) {
                    initialTime = date
                }
                if trigger.weekdays.count == 7 {
                    initialWeekdays = trigger.weekdays
                }
            case .sunrise(let solar):
                initialTriggerSelection = .sunrise
                initialSolarOffset = Double(SolarTrigger.clampOnDeviceOffset(Int(Self.minutes(from: solar.offset).rounded())))
                initialWeekdays = WeekdayMask.normalizeSunFirst(solar.weekdays)
            case .sunset(let solar):
                initialTriggerSelection = .sunset
                initialSolarOffset = Double(SolarTrigger.clampOnDeviceOffset(Int(Self.minutes(from: solar.offset).rounded())))
                initialWeekdays = WeekdayMask.normalizeSunFirst(solar.weekdays)
            }
            switch editing.action {
            case .scene(let payload):
                initialActionSelection = .scene
                initialSelectedSceneId = payload.sceneId
                initialSceneBrightnessOverride = payload.brightnessOverride
            case .playlist:
                // Playlist actions are not yet supported in the UI editor
                // Fall through to default gradient behavior
                initialActionSelection = .color
                initialLockedAction = editing.action
            case .gradient(let payload):
                initialActionSelection = .color
                initialTemplateGradient = payload.gradient
                initialGradientBrightness = Double(payload.brightness)
                initialEnableColorFade = payload.durationSeconds > 0
                initialGradientDuration = payload.durationSeconds  // Preserve actual duration, don't clamp
                initialColorPowerOn = payload.powerOn
                initialSelectedColorPresetId = payload.presetId
                initialGradientTemperature = payload.temperature
                initialGradientWhiteLevel = payload.whiteLevel
                // Note: interpolation is stored in the gradient itself
            case .transition(let payload):
                initialActionSelection = .transition
                initialTemplateTransition = payload
                initialGradientBrightness = Double(payload.endBrightness)
                initialTransitionDuration = payload.durationSeconds  // Preserve actual duration
                initialSelectedTransitionPresetId = payload.presetId
                // Extract transition gradients for editor
                initialTransitionStartGradient = payload.startGradient
                initialTransitionEndGradient = payload.endGradient
                initialTransitionStartBrightness = Double(payload.startBrightness)
                initialTransitionEndBrightness = Double(payload.endBrightness)
                initialTransitionStartTemperature = payload.startTemperature
                initialTransitionStartWhiteLevel = payload.startWhiteLevel
                initialTransitionEndTemperature = payload.endTemperature
                initialTransitionEndWhiteLevel = payload.endWhiteLevel
            case .effect(let payload):
                initialActionSelection = .effect
                initialEffectId = payload.effectId
                initialEffectBrightness = Double(payload.brightness)
                initialEffectSpeed = payload.speed
                initialEffectIntensity = payload.intensity
                initialEffectGradient = payload.gradient
                initialTemplateGradient = payload.gradient
                initialTemplateEffect = TemplateEffectSettings(gradient: payload.gradient, speed: payload.speed, intensity: payload.intensity)
                initialSelectedEffectPresetId = payload.presetId
            case .preset:
                initialActionSelection = .color
                initialLockedAction = editing.action
            case .directState(let payload):
                initialActionSelection = .color
                initialTemplateGradient = LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: payload.colorHex),
                    GradientStop(position: 1.0, hexColor: payload.colorHex)
                ], interpolation: .linear)
                initialGradientBrightness = Double(payload.brightness)
                initialEnableColorFade = payload.transitionDeciseconds > 0
                initialGradientDuration = Double(payload.transitionDeciseconds) / 10.0
                initialColorPowerOn = payload.brightness > 0
                initialGradientTemperature = payload.temperature
                initialGradientWhiteLevel = payload.whiteLevel
            }
            initialMetadata = editing.metadata
            if let sm = editing.metadata.onDeviceStartMonth,
               let sd = editing.metadata.onDeviceStartDay,
               let em = editing.metadata.onDeviceEndMonth,
               let ed = editing.metadata.onDeviceEndDay {
                initialUseDateWindow = true
                initialStartMonth = min(12, max(1, sm))
                initialStartDay = min(31, max(1, sd))
                initialEndMonth = min(12, max(1, em))
                initialEndDay = min(31, max(1, ed))
            }
        } else if let prefill = templatePrefill {
            initialName = prefill.name ?? initialName
            if let ids = prefill.targetDeviceIds, !ids.isEmpty {
                initialDeviceIds = Set(ids)
            }
            initialAllowPartial = prefill.allowPartialFailure ?? true
            initialMetadata = prefill.metadata

            switch prefill.trigger {
            case .time(let hour, let minute, let weekdays):
                initialTriggerSelection = .time
                initialTime = Self.dateFrom(hour: hour, minute: minute) ?? Date()
                if let weekdays, weekdays.count == 7 {
                    initialWeekdays = weekdays
                }
            case .sunrise(let offset):
                initialTriggerSelection = .sunrise
                initialSolarOffset = Double(SolarTrigger.clampOnDeviceOffset(offset))
            case .sunset(let offset):
                initialTriggerSelection = .sunset
                initialSolarOffset = Double(SolarTrigger.clampOnDeviceOffset(offset))
            }

            switch prefill.action {
            case .gradient(let gradient, let brightness, let fadeDuration):
                initialActionSelection = .color
                initialTemplateGradient = gradient
                initialGradientBrightness = Double(brightness)
                initialEnableColorFade = fadeDuration > 0
                initialGradientDuration = max(10, fadeDuration)
            case .transition(let payload, let durationSeconds, let endBrightness):
                initialActionSelection = .transition
                initialTemplateTransition = payload
                if let durationSeconds {
                    initialTransitionDuration = min(3600, max(0, durationSeconds))
                }
                if let endBrightness {
                    initialGradientBrightness = Double(endBrightness)
                }
                initialTransitionStartTemperature = payload.startTemperature
                initialTransitionStartWhiteLevel = payload.startWhiteLevel
                initialTransitionEndTemperature = payload.endTemperature
                initialTransitionEndWhiteLevel = payload.endWhiteLevel
            case .effect(let effectId, let brightness, let gradient, let speed, let intensity):
                initialActionSelection = .effect
                initialEffectId = effectId
                initialEffectBrightness = Double(brightness)
                initialTemplateEffect = TemplateEffectSettings(gradient: gradient, speed: speed, intensity: intensity)
                initialTemplateGradient = gradient
            }
        } else {
            initialAllowPartial = true
            initialTriggerSelection = Self.defaultTriggerSelection(
                for: initialDeviceIds,
                automations: AutomationStore.shared.automations
            )
        }

        _automationName = State(initialValue: initialName)
        _selectedEffectId = State(initialValue: initialEffectId)
        _selectedSceneId = State(initialValue: initialSelectedSceneId)
        _sceneBrightnessOverride = State(initialValue: initialSceneBrightnessOverride)
        _effectBrightness = State(initialValue: initialEffectBrightness)
        _effectSpeed = State(initialValue: initialEffectSpeed)
        _effectIntensity = State(initialValue: initialEffectIntensity)
        _effectGradient = State(initialValue: initialEffectGradient ?? viewModel.automationGradient(for: initialActiveDevice))
        _gradientBrightness = State(initialValue: initialGradientBrightness)
        _selectedDeviceIds = State(initialValue: initialDeviceIds)
        _activeDevice = State(initialValue: initialActiveDevice)
        _selectedColorPresetId = State(initialValue: initialSelectedColorPresetId)
        _gradientTemperature = State(initialValue: initialGradientTemperature)
        _gradientWhiteLevel = State(initialValue: initialGradientWhiteLevel)
        _selectedTransitionPresetId = State(initialValue: initialSelectedTransitionPresetId)
        _selectedEffectPresetId = State(initialValue: initialSelectedEffectPresetId)
        _customTransitionDuration = State(initialValue: initialTransitionDuration)
        _allowPartialFailure = State(initialValue: initialAllowPartial)
        _triggerSelection = State(initialValue: initialTriggerSelection)
        _selectedTime = State(initialValue: initialTime)
        _selectedWeekdays = State(initialValue: initialWeekdays)
        _solarOffsetMinutes = State(initialValue: initialSolarOffset)
        _useDateWindow = State(initialValue: initialUseDateWindow)
        _startMonth = State(initialValue: initialStartMonth)
        _startDay = State(initialValue: initialStartDay)
        _endMonth = State(initialValue: initialEndMonth)
        _endDay = State(initialValue: initialEndDay)
        _actionSelection = State(initialValue: initialActionSelection)
        _enableColorFade = State(initialValue: initialEnableColorFade)
        _colorPowerOn = State(initialValue: initialColorPowerOn)
        _gradientDuration = State(initialValue: initialGradientDuration)
        _gradientInterpolation = State(initialValue: initialTemplateGradient?.interpolation ?? .linear)
        _templateGradient = State(initialValue: initialTemplateGradient ?? viewModel.automationGradient(for: initialActiveDevice))
        _templateTransition = State(initialValue: initialTemplateTransition)
        _templateEffectSettings = State(initialValue: initialTemplateEffect)
        _templateMetadata = State(initialValue: initialMetadata)
        _lockedAction = State(initialValue: initialLockedAction)
        // Initialize transition editor state
        let defaultStartGradient = LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFFFFF")
        ])
        let defaultEndGradient = LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFFFFF"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ])
        _transitionStartGradient = State(initialValue: initialTransitionStartGradient ?? defaultStartGradient)
        _transitionEndGradient = State(initialValue: initialTransitionEndGradient ?? defaultEndGradient)
        _transitionStartBrightness = State(initialValue: initialTransitionStartBrightness)
        _transitionEndBrightness = State(initialValue: initialTransitionEndBrightness)
        _transitionStartTemperature = State(initialValue: initialTransitionStartTemperature)
        _transitionStartWhiteLevel = State(initialValue: initialTransitionStartWhiteLevel)
        _transitionEndTemperature = State(initialValue: initialTransitionEndTemperature)
        _transitionEndWhiteLevel = State(initialValue: initialTransitionEndWhiteLevel)
    }

    private var weekdayNames: [String] { ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"] }
    private var primaryButtonTitle: String { isEditing ? "Save Changes" : "Save Automation" }
    private var availableActionSelections: [ActionSelection] {
        if allowSceneAction {
            return ActionSelection.allCases
        }
        if case .scene = editingAutomation?.action {
            return ActionSelection.allCases
        }
        return ActionSelection.allCases.filter { $0 != .scene }
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    private static func dateFrom(timeString: String) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return dateFrom(hour: hour, minute: minute)
    }

    private static func minutes(from offset: SolarTrigger.EventOffset) -> Double {
        switch offset {
        case .minutes(let value):
            return Double(value)
        }
    }

    var body: some View {
        Group {
            if presentationStyle == .sheet {
                NavigationStack {
                    dialogContent
                }
            } else {
                dialogContent
            }
        }
    }

    private var dialogContent: some View {
        Group {
            if presentationStyle == .embedded {
                embeddedDialogContent
            } else {
                sheetDialogContent
            }
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .presentationBackground(.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if presentationStyle == .sheet {
                dialogToolbar
            }
        }
        .task(id: presetSlotLoadKey) {
            await loadPresetSlots(for: presetSlotLoadKey)
        }
        .task(id: transitionSchedulePreviewInputsKey) {
            await refreshTransitionSchedulePreview()
        }
        .task(id: scheduleValidationInputsKey) {
            await refreshOnDeviceScheduleOverlapWarning()
        }
        .onChange(of: selectedDeviceIds) { _, _ in
            clearOnDeviceScheduleValidationMessage()
            onDeviceScheduleOverlapWarningMessage = nil
            normalizeTriggerSelectionIfNeeded()
        }
        .onChange(of: activeDevice.id) { _, _ in
            clearOnDeviceScheduleValidationMessage()
            onDeviceScheduleOverlapWarningMessage = nil
            normalizeTriggerSelectionIfNeeded()
        }
        .onChange(of: validationInputsKey) { _, _ in
            clearOnDeviceScheduleValidationMessage()
            onDeviceScheduleOverlapWarningMessage = nil
        }
        .onChange(of: actionSelection) { _, selection in
            if selection == .scene {
                normalizeSceneSelectionIfNeeded()
            }
            clearOnDeviceScheduleValidationMessage()
            onDeviceScheduleOverlapWarningMessage = nil
        }
        .onChange(of: selectedSceneId) { _, _ in
            normalizeSceneSelectionIfNeeded()
            clearOnDeviceScheduleValidationMessage()
            onDeviceScheduleOverlapWarningMessage = nil
        }
        .onAppear {
            if !availableActionSelections.contains(actionSelection) {
                actionSelection = .color
            }
            normalizeTriggerSelectionIfNeeded()
            normalizeSceneSelectionIfNeeded()
        }
        .alert("Location Access Needed", isPresented: $showLocationSettingsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text("Sunrise and sunset automations need location access. Enable Location for Aesdetic in iOS Settings.")
        }
    }

    private var sheetDialogContent: some View {
        ZStack {
            modalBackground
            contentScrollView
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stickySaveBar
        }
    }

    private var embeddedDialogContent: some View {
        VStack(spacing: 0) {
            inlineEditorHeader
                .padding(.top, 2)
                .padding(.bottom, 8)
                .zIndex(2)

            contentScrollView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            AppCardBackground(
                style: AppCardStyles.glass(
                    for: colorScheme,
                    tone: .muted,
                    cornerRadius: 28
                            )
                        )
                )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ToolbarContentBuilder
    private var dialogToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            editableAutomationTitle
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") { closeEditor() }
                .foregroundColor(.white)
        }
    }

    private var editorTitleText: String {
        automationName.isEmpty ? (isEditing ? "Edit Automation" : "Add Automation") : automationName
    }

    private var editableAutomationTitle: some View {
        Group {
            if isEditingName {
                HStack(spacing: 6) {
                    TextField("Automation name", text: $automationName)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white.opacity(0.96))
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            commitNameEdit()
                        }
                        .submitLabel(.done)
                        .frame(maxWidth: .infinity)

                    Button {
                        commitNameEdit()
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white.opacity(0.82))
                            .font(AppTypography.style(.caption, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
                .onAppear {
                    DispatchQueue.main.async {
                        isNameFieldFocused = true
                    }
                }
            } else {
                Button {
                    handleNameEditToggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(editorTitleText)
                            .font(AppTypography.style(.subheadline, weight: .semibold))
                            .foregroundColor(.white.opacity(0.96))
                            .lineLimit(1)

                        Image(systemName: "pencil")
                            .foregroundColor(.white.opacity(0.52))
                            .font(AppTypography.style(.caption, weight: .semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename automation")
                .frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var inlineEditorHeader: some View {
        let headerActionWidth: CGFloat = 82

        return HStack(spacing: 8) {
            HStack {
                Button {
                    closeEditor()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(AppTypography.style(.caption2, weight: .bold))
                        Text("Back")
                            .font(AppTypography.style(.caption, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.64))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(secondaryControlBackground(isActive: false, cornerRadius: 15))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .frame(width: headerActionWidth, alignment: .leading)

            editableAutomationTitle
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                if presentationStyle == .embedded {
                    inlinePrimaryActionButton
                }
            }
            .frame(width: headerActionWidth, alignment: .trailing)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlinePrimaryActionButton: some View {
        Button(action: saveAndDismiss) {
            HStack(spacing: 6) {
                if isValidatingOnDeviceSchedule {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white.opacity(0.72))
                }
                Text(isValidatingOnDeviceSchedule ? "Checking" : (isEditing ? "Save" : "Create"))
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(canSave && !isValidatingOnDeviceSchedule ? .black.opacity(0.78) : .white.opacity(0.54))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(inlinePrimaryActionBackground(isEnabled: canSave && !isValidatingOnDeviceSchedule))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave || isValidatingOnDeviceSchedule)
    }

    @ViewBuilder
    private func inlinePrimaryActionBackground(isEnabled: Bool) -> some View {
        ZStack {
            if isEnabled {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.clear)
                    .appLiquidGlass(role: .control, cornerRadius: 15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.60),
                                        Color.white.opacity(0.30)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.035), radius: 2, x: 0, y: 1)
            } else {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .background(.ultraThinMaterial.opacity(0.64), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            }
        }
    }

    private var contentScrollView: some View {
        ScrollView {
            LazyVStack(spacing: presentationStyle == .embedded ? 12 : 18) {
                if presentationStyle == .sheet {
                    dialogSection(automationDetailsSection)
                }
                dialogSection(editorCard {
                    automationSettingsSection
                })
                dialogSection(editorCard {
                    automationActionSection
                })
                if allowDeviceSelection {
                    dialogSection(editorCard {
                        deviceSyncSection
                    })
                }
                if presentationStyle == .sheet {
                    dialogSection(storageEstimateCard)
                }
                dialogSection(saveSection)
            }
            .padding(presentationStyle == .embedded ? 0 : 20)
            .padding(.top, presentationStyle == .embedded ? 6 : 0)
            .padding(.bottom, presentationStyle == .embedded ? 10 : 18)
            .background(Color.clear)
        }
        .scrollIndicators(.hidden)
    }

    private func dialogSection<Content: View>(_ content: Content) -> AnyView {
        AnyView(content)
    }

    @ViewBuilder
    private func editorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if presentationStyle == .embedded {
            content()
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(colorScheme == .dark ? 0.38 : 0.18),
                                    Color.white.opacity(colorScheme == .dark ? 0.075 : 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.26),
                                            Color.white.opacity(0.08)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16),
                    radius: 22,
                    x: 0,
                    y: 14
                )
        }
    }

    private var validationInputsKey: String {
        let selectedMinute = Int(selectedTime.timeIntervalSinceReferenceDate / 60.0)
        let weekdays = selectedWeekdays.map { $0 ? "1" : "0" }.joined()
        return [
            triggerSelection.rawValue,
            String(selectedMinute),
            weekdays,
            String(Int(solarOffsetMinutes.rounded())),
            useDateWindow ? "1" : "0",
            String(startMonth),
            String(startDay),
            String(endMonth),
            String(endDay),
            actionSelection.rawValue,
            selectedSceneId?.uuidString ?? "nil",
            selectedEffectId.map(String.init) ?? "nil",
            automationName
        ].joined(separator: "|")
    }

    private var transitionSchedulePreviewInputsKey: String {
        let selectedMinute = Int(selectedTime.timeIntervalSinceReferenceDate / 60.0)
        let weekdays = selectedWeekdays.map { $0 ? "1" : "0" }.joined()
        return [
            triggerSelection.rawValue,
            String(selectedMinute),
            weekdays,
            String(Int(solarOffsetMinutes.rounded())),
            activeDevice.id,
            String(Int(customTransitionDuration.rounded())),
            useDateWindow ? "1" : "0",
            String(startMonth),
            String(startDay),
            String(endMonth),
            String(endDay)
        ].joined(separator: "|")
    }

    private var scheduleValidationInputsKey: String {
        [
            validationInputsKey,
            selectedDeviceIds.sorted().joined(separator: ","),
            activeDevice.id,
            actionSelection.rawValue,
            String(Int(gradientDuration.rounded())),
            enableColorFade ? "1" : "0",
            String(Int(customTransitionDuration.rounded())),
            selectedColorPresetId?.uuidString ?? "nil",
            selectedTransitionPresetId?.uuidString ?? "nil",
            selectedEffectPresetId?.uuidString ?? "nil"
        ].joined(separator: "|")
    }

    private var presetSlotLoadKey: String {
        let targetIds = targetDevicesForCapacity.map(\.id).sorted().joined(separator: ",")
        return [
            targetIds,
            actionSelection.rawValue,
            selectedSceneId?.uuidString ?? "nil",
            allowPartialFailure ? "partial" : "strict"
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var saveSection: some View {
        if presentationStyle == .sheet, hasSaveGuidanceMessages {
            editorCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Needs attention", systemImage: "exclamationmark.circle")
                        .font(AppTypography.style(.footnote, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                    saveGuidanceMessages
                }
            }
        }
    }

    @ViewBuilder
    private var saveGuidanceMessages: some View {
        Group {
            if let message = onDeviceScheduleValidationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(onDeviceScheduleValidationIsWarning ? 0.86 : 0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = onDeviceScheduleOverlapWarningMessage,
               message != onDeviceScheduleValidationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = timerSlotLimitPromptMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = dateWindowValidationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = presetCapacityMessage, !presetCapacitySatisfied {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if presentationStyle == .sheet, let message = transitionDurationRecommendationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if automationStore.hasAnyDeletionInProgress {
                Text("Please wait for automation deletion to finish before saving automation changes.")
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if automationStore.hasOnDeviceSyncInProgress(for: selectedDeviceIds) {
                Text("Please wait for the current automation to finish preparing before saving automation changes.")
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hasSaveGuidanceMessages: Bool {
        onDeviceScheduleValidationMessage != nil
            || onDeviceScheduleOverlapWarningMessage != nil
            || timerSlotLimitPromptMessage != nil
            || dateWindowValidationMessage != nil
            || (presetCapacityMessage != nil && !presetCapacitySatisfied)
            || (presentationStyle == .sheet && transitionDurationRecommendationMessage != nil)
            || automationStore.hasAnyDeletionInProgress
            || automationStore.hasOnDeviceSyncInProgress(for: selectedDeviceIds)
    }

    private var stickySaveBar: some View {
        VStack(spacing: presentationStyle == .embedded ? 6 : 10) {
            HStack(alignment: .center, spacing: presentationStyle == .embedded ? 10 : 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEditing ? "Update automation" : "Create automation")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundColor(.white.opacity(presentationStyle == .embedded ? 0.92 : 0.76))
                    Text(primarySaveStatusText)
                        .font(AppTypography.style(.footnote, weight: .medium))
                        .foregroundColor(primarySaveStatusTint)
                        .lineLimit(presentationStyle == .embedded ? 1 : 2)
                        .minimumScaleFactor(presentationStyle == .embedded ? 0.86 : 1)
                        .fixedSize(horizontal: false, vertical: true)

                }

                Spacer(minLength: 8)

                Button(action: saveAndDismiss) {
                    let isButtonEnabled = canSave && !isValidatingOnDeviceSchedule
                    HStack(spacing: 8) {
                        if isValidatingOnDeviceSchedule {
                            ProgressView()
                                .scaleEffect(0.72)
                                .tint(isButtonEnabled && presentationStyle != .embedded ? .black : .white.opacity(0.72))
                        }
                        Text(isValidatingOnDeviceSchedule ? "Checking" : primaryButtonTitle)
                            .font(AppTypography.style(.subheadline, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundColor(saveButtonTextColor(isEnabled: isButtonEnabled))
                    .padding(.horizontal, presentationStyle == .embedded ? 12 : 18)
                    .padding(.vertical, presentationStyle == .embedded ? 8 : 13)
                    .frame(minWidth: presentationStyle == .embedded ? 122 : 148)
                    .background(saveButtonBackground(isEnabled: isButtonEnabled))
                    .opacity(isButtonEnabled || isValidatingOnDeviceSchedule ? 1 : 0.72)
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isValidatingOnDeviceSchedule)
            }
            .padding(.horizontal, presentationStyle == .embedded ? 10 : 18)
            .padding(.top, presentationStyle == .embedded ? 8 : 14)
            .padding(.bottom, presentationStyle == .embedded ? 8 : 12)
        }
        .padding(.horizontal, presentationStyle == .embedded ? 0 : 0)
        .padding(.top, 0)
        .padding(.bottom, presentationStyle == .embedded ? 0 : 0)
        .background(stickySaveBarBackground)
    }

    private func saveButtonTextColor(isEnabled: Bool) -> Color {
        if presentationStyle == .embedded {
            return isEnabled ? .black.opacity(0.92) : .white.opacity(0.62)
        }
        return isEnabled ? .black : .white.opacity(0.62)
    }

    @ViewBuilder
    private func saveButtonBackground(isEnabled: Bool) -> some View {
        if presentationStyle == .embedded {
            if isEnabled {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color.white.opacity(0.84)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .appLiquidGlass(role: .control, cornerRadius: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            }
        } else {
            Capsule(style: .continuous)
                .fill(
                    isEnabled
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.84)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.white.opacity(0.14))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isEnabled ? 0.34 : 0.12), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var stickySaveBarBackground: some View {
        if presentationStyle == .embedded {
            Color.clear
                .allowsHitTesting(false)
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.72),
                            Color.black.opacity(0.52)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var primarySaveStatusText: String {
        if presentationStyle == .embedded {
            return compactPrimarySaveStatusText
        }
        if isValidatingOnDeviceSchedule {
            return "Checking this automation before saving..."
        }
        if automationStore.hasAnyDeletionInProgress {
            return "Wait for the current automation delete to finish."
        }
        if automationStore.hasOnDeviceSyncInProgress(for: selectedDeviceIds) {
            return "Wait for the current automation to finish preparing."
        }
        if automationName.trimmed().isEmpty {
            return "Add a name before saving."
        }
        if selectedDeviceIds.isEmpty {
            return "Select at least one device."
        }
        if !selectedWeekdays.contains(true) {
            return "Choose at least one day."
        }
        if !isDateWindowValid {
            return dateWindowValidationMessage ?? "Check the date range."
        }
        if let message = onDeviceScheduleValidationMessage {
            return message
        }
        if let message = onDeviceScheduleOverlapWarningMessage {
            return message
        }
        if !timerSlotCapacitySatisfied {
            return timerSlotLimitPromptMessage ?? "There is no available schedule slot for this automation."
        }
        if actionSelection == .scene && selectedScene == nil {
            return "Choose a scene to continue."
        }
        if requiredPresetSlots > 0 && !presetCapacitySatisfied {
            return presetCapacityMessage ?? "Free saved-entry space before saving."
        }
        if presentationStyle == .sheet, let warning = transitionDurationRecommendationMessage {
            return warning
        }
        return "Ready to save."
    }

    private var compactPrimarySaveStatusText: String {
        if isValidatingOnDeviceSchedule {
            return "Checking..."
        }
        if automationStore.hasAnyDeletionInProgress {
            return "Delete in progress."
        }
        if automationStore.hasOnDeviceSyncInProgress(for: selectedDeviceIds) {
            return "Preparing current automation."
        }
        if automationName.trimmed().isEmpty {
            return "Name required."
        }
        if selectedDeviceIds.isEmpty {
            return "Select a device."
        }
        if !selectedWeekdays.contains(true) {
            return "Choose a repeat day."
        }
        if !isDateWindowValid {
            return "Check date range."
        }
        if onDeviceScheduleValidationMessage != nil {
            return onDeviceScheduleValidationIsWarning ? "Review schedule warning." : "Schedule issue."
        }
        if onDeviceScheduleOverlapWarningMessage != nil {
            return "Schedule overlap."
        }
        if !timerSlotCapacitySatisfied {
            return "No schedule slot available."
        }
        if actionSelection == .scene && selectedScene == nil {
            return "Choose a scene."
        }
        if requiredPresetSlots > 0 && !presetCapacitySatisfied {
            return "Free saved-entry space."
        }
        return "Ready to save."
    }

    private var primarySaveStatusTint: Color {
        if canSave && !isValidatingOnDeviceSchedule {
            if onDeviceScheduleValidationMessage != nil {
                if presentationStyle == .embedded { return .white.opacity(0.9) }
                return onDeviceScheduleValidationIsWarning ? .yellow.opacity(0.94) : .orange.opacity(0.94)
            }
            if onDeviceScheduleOverlapWarningMessage != nil {
                if presentationStyle == .embedded { return .white.opacity(0.9) }
                return .yellow.opacity(0.94)
            }
            if transitionDurationRecommendationMessage != nil {
                if presentationStyle == .embedded { return .white.opacity(0.9) }
                return .yellow.opacity(0.94)
            }
            return .white.opacity(presentationStyle == .embedded ? 0.9 : 0.78)
        }
        return presentationStyle == .embedded ? .white.opacity(0.78) : .orange.opacity(0.94)
    }

    private var storageEstimateCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: storageEstimateIconName)
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(storageEstimateTint)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage")
                            .font(AppTypography.style(.callout, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                        Text(storageUsageSummary)
                            .font(AppTypography.style(.footnote))
                            .foregroundColor(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if let context = presetCapacityContext, context.status.total > 0 {
                    storageUsageBar(status: context.status)

                    HStack(spacing: 8) {
                        storageMetricPill(
                            title: "Used now",
                            value: storagePercentText(count: context.status.used, total: context.status.total)
                        )
                        storageMetricPill(
                            title: "This automation",
                            value: "+\(storagePercentText(count: requiredPresetSlots, total: context.status.total, minimumOneWhenNonZero: true))"
                        )
                        storageMetricPill(
                            title: "After save",
                            value: storagePercentText(
                                count: min(context.status.total, context.status.used + requiredPresetSlots),
                                total: context.status.total
                            )
                        )
                    }

                    Text("Safest device: \(context.device.name). \(storageEntrySummary)")
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.58))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Checking storage...")
                        .font(AppTypography.style(.footnote, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var storageEstimateIconName: String {
        presetCapacitySatisfied ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var storageEstimateTint: Color {
        presetCapacitySatisfied ? Color.green.opacity(0.9) : .orange
    }

    private var storageUsageSummary: String {
        guard let context = presetCapacityContext, context.status.total > 0 else {
            return "Checking how much saved-entry space is available."
        }
        let used = storagePercentText(count: context.status.used, total: context.status.total)
        let added = storagePercentText(count: requiredPresetSlots, total: context.status.total, minimumOneWhenNonZero: true)
        return "\(used) occupied now. This automation adds \(added)."
    }

    private var storageEntrySummary: String {
        guard requiredPresetSlots > 0 else {
            return "This automation reuses saved content and adds no new storage."
        }
        return "This automation adds \(savedEntryCountText(requiredPresetSlots))."
    }

    private func storageUsageBar(status: DeviceControlViewModel.PresetSlotAvailability) -> some View {
        let total = max(1, status.total)
        let usedFraction = min(1, max(0, Double(status.used) / Double(total)))
        let automationFraction = min(1 - usedFraction, max(0, Double(requiredPresetSlots) / Double(total)))

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))

                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: proxy.size.width * usedFraction)

                Capsule()
                    .fill(storageEstimateTint)
                    .frame(width: proxy.size.width * automationFraction)
                    .offset(x: proxy.size.width * usedFraction)
            }
        }
        .frame(height: 9)
        .clipShape(Capsule())
        .accessibilityLabel("Automation storage")
        .accessibilityValue("\(storagePercentText(count: status.used, total: status.total)) used, plus \(storagePercentText(count: requiredPresetSlots, total: status.total, minimumOneWhenNonZero: true)) for this automation")
    }

    private func storagePercentText(
        count: Int,
        total: Int,
        minimumOneWhenNonZero: Bool = false
    ) -> String {
        guard total > 0 else { return "0%" }
        if count <= 0 { return "0%" }
        let raw = (Double(count) / Double(total)) * 100.0
        let value = minimumOneWhenNonZero ? max(1, Int(ceil(raw))) : Int(round(raw))
        return "\(min(100, max(0, value)))%"
    }

    private func storageMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(AppTypography.style(.caption2, weight: .bold))
                .foregroundColor(.white.opacity(0.48))
            Text(value)
                .font(AppTypography.style(.caption, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func savedEntryCountText(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    @ViewBuilder
    private var modalBackground: some View {
        if presentationStyle == .sheet {
            modalBackgroundLayers
                .ignoresSafeArea()
        } else {
            Color.clear
        }
    }

    private var modalBackgroundLayers: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.030, blue: 0.040),
                    Color(red: 0.055, green: 0.050, blue: 0.046),
                    Color(red: 0.018, green: 0.022, blue: 0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.94, green: 0.56, blue: 0.30).opacity(0.22),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 460
            )

            RadialGradient(
                colors: [
                    Color(red: 0.36, green: 0.58, blue: 0.78).opacity(0.16),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 520
            )

            LiquidGlassOverlay(
                blurOpacity: 0.82,
                highlightOpacity: 0.20,
                verticalTopOpacity: 0.09,
                verticalBottomOpacity: 0.16,
                vignetteOpacity: 0.22,
                centerSheenOpacity: 0.06
            )

            Rectangle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.30 : 0.18))

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            .clear,
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        }
    }

    // MARK: - Sections

    private var automationDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: isEditing ? "slider.horizontal.3" : "plus")
                        .font(AppTypography.style(.title3, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(isEditing ? "Edit automation" : "New automation")
                        .font(AppTypography.style(.title2, weight: .bold))
                        .foregroundColor(.white)
                    Text(isEditing ? "Update the schedule, colors, and device setup without starting over." : "Choose when it runs, what it does, and where it saves.")
                        .font(AppTypography.style(.subheadline))
                        .foregroundColor(.white.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                summaryPill(icon: "clock", text: triggerSummaryText)
                summaryPill(icon: actionSelection.systemImageName, text: actionSelection.rawValue)
            }
            summaryPill(icon: "lightbulb.2", text: deviceSyncSummary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.055)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var deviceSyncSection: some View {
            if allowDeviceSelection {
            deviceSelectionCard
        }
    }

    private var deviceSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with summary on the right
            HStack {
                Text("Sync to devices")
                    .font(AppTypography.style(.callout, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text(deviceSyncSummary)
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.6))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(availableDevices) { device in
                    deviceChip(device: device)
                }
            }
        }
    }

    private func deviceChip(device: WLEDDevice) -> some View {
        let isSelected = selectedDeviceIds.contains(device.id)
        let isOnline = device.isOnline

        return Button {
            if isSelected && selectedDeviceIds.count == 1 {
                return // Prevent deselecting the last device
            }
            if isSelected {
                selectedDeviceIds.remove(device.id)
            } else {
                selectedDeviceIds.insert(device.id)
                activeDevice = device
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(isSelected ? .black : .white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(isOnline ? "Online" : "Offline")
                        .font(AppTypography.style(.caption2))
                        .foregroundColor(isSelected ? .black.opacity(0.7) : .white.opacity(0.5))

                    // Status dot on the right
                    Circle()
                        .fill(isOnline ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44) // Accessibility: minimum 44pt hit area
            .background(deviceChipBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: Color.black.opacity(isSelected ? 0.15 : 0.08),
                radius: isSelected ? 6 : 3,
                x: 0,
                y: isSelected ? 3 : 2
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
        .accessibilityLabel("Sync to device: \(device.name), \(isOnline ? "Online" : "Offline")")
        .accessibilityHint(isSelected ? "Tap to deselect this device" : "Tap to select this device")
    }

    @ViewBuilder
    private func deviceChipBackground(isSelected: Bool) -> some View {
        if isSelected {
            // Selected: White pill with soft gradient (matching tab style)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        } else {
            // Inactive: Transparent fill matching tab style
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
    }

    private var deviceSyncSummary: String {
        let selectedCount = selectedDeviceIds.count
        let totalCount = availableDevices.count

        if selectedCount == totalCount {
            return "All devices selected"
        } else {
            return "Syncing to \(selectedCount) of \(totalCount) devices"
        }
    }

    private var triggerSummaryText: String {
        switch triggerSelection {
        case .time:
            return selectedTime.formatted(date: .omitted, time: .shortened)
        case .sunrise:
            return solarOffsetSummary(event: "Sunrise")
        case .sunset:
            return solarOffsetSummary(event: "Sunset")
        }
    }

    private func solarOffsetSummary(event: String) -> String {
        let minutes = Int(solarOffsetMinutes.rounded())
        if minutes == 0 { return event }
        return "\(event) \(minutes > 0 ? "+" : "")\(minutes)m"
    }

    private func summaryPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppTypography.style(.caption2, weight: .semibold))
            Text(text)
                .font(AppTypography.style(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundColor(.white.opacity(0.86))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    // MARK: - Trigger Settings Section

    private var automationSettingsSection: some View {
        VStack(alignment: .leading, spacing: presentationStyle == .embedded ? 12 : 16) {
            if presentationStyle == .sheet {
                sectionHeader(
                    title: "Automation Settings",
                    subtitle: "Choose when it runs and which days repeat."
                )
            }

            scheduleSelectionSection
            if presentationStyle == .sheet {
                solarParityHint
            }
            if advancedUIEnabled {
                dateWindowSection
            }
        }
    }

    @ViewBuilder
    private var scheduleSelectionSection: some View {
        if presentationStyle == .embedded {
            triggerSelectionCard
        } else {
            triggerSelectionCard
            repeatScheduleSection
        }
    }

    private func sectionHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.style(.callout, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.style(.caption, weight: .medium))
                    .foregroundColor(.white.opacity(0.52))
            }
        }
    }

    private var triggerSelectionCard: some View {
        GeometryReader { geometry in
            triggerSelectionContent(geometry: geometry)
        }
        .frame(height: triggerSelectionHeight)
    }

    private var triggerSelectionHeight: CGFloat {
        if presentationStyle == .embedded {
            return 260
        }
        return 248
    }

    @ViewBuilder
    private var solarParityHint: some View {
        if triggerSelection == .sunrise || triggerSelection == .sunset {
            Text("WLED solar parity: Sunrise uses timer slot 8, Sunset uses slot 9. Offset range is -120...+120 minutes and uses device timezone/location.")
                .font(AppTypography.style(.caption))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var dateWindowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Limit To Date Range (WLED timer start/end)", isOn: $useDateWindow)
                .tint(.white)
                .foregroundColor(.white)
            if useDateWindow {
                HStack(spacing: 12) {
                    dateWindowStepper(title: "Start Mon", value: $startMonth, range: 1...12)
                    dateWindowStepper(title: "Start Day", value: $startDay, range: 1...31)
                }
                HStack(spacing: 12) {
                    dateWindowStepper(title: "End Mon", value: $endMonth, range: 1...12)
                    dateWindowStepper(title: "End Day", value: $endDay, range: 1...31)
                }
                Text("When enabled, WLED will only run this timer between the selected start/end dates each year.")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.7))
                if let validationMessage = dateWindowValidationMessage {
                    Text(validationMessage)
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func dateWindowStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.style(.caption2, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
            HStack(spacing: 10) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 24)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(AppTypography.style(.caption, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Repeat Schedule Section

    private var repeatScheduleSection: some View {
        let weekdaySpacing: CGFloat = presentationStyle == .embedded ? 1 : 4
        let weekdayCornerRadius: CGFloat = presentationStyle == .embedded ? 11 : 13
        let weekdayHeight: CGFloat = presentationStyle == .embedded ? 32 : 36
        let trackPadding: CGFloat = 4

        return VStack(alignment: .leading, spacing: presentationStyle == .embedded ? 8 : 10) {
            if presentationStyle != .embedded {
                Text("Repeat on")
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .foregroundColor(.white.opacity(0.76))
            }

            // Weekday buttons with swipe-to-select
            weekdaySelectionBar(
                weekdaySpacing: weekdaySpacing,
                weekdayCornerRadius: weekdayCornerRadius,
                weekdayHeight: weekdayHeight,
                trackPadding: trackPadding
            )

            if !selectedWeekdays.contains(true) {
                repeatDayValidationBubble
            }
        }
    }

    private var repeatDayValidationBubble: some View {
        Text("Choose at least one repeat day.")
            .font(AppTypography.style(.caption, weight: .medium))
            .foregroundColor(.white.opacity(0.84))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .background(.ultraThinMaterial.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 7, x: 0, y: 3)
    }

    private func weekdaySelectionBar(
        weekdaySpacing: CGFloat,
        weekdayCornerRadius: CGFloat,
        weekdayHeight: CGFloat,
        trackPadding: CGFloat
    ) -> some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width - (trackPadding * 2))
            let slotWidth = max(1, width / 7)
            let selectedInset = max(0, weekdaySpacing / 2)
            let selectedHeight = weekdayHeight

            ZStack(alignment: .topLeading) {
                weekdayTrackBackground

                ForEach(selectedWeekdayRuns) { run in
                    let runLength = run.endIndex - run.startIndex + 1
                    let runX = trackPadding + (CGFloat(run.startIndex) * slotWidth) + selectedInset
                    let runWidth = max(1, (CGFloat(runLength) * slotWidth) - (selectedInset * 2))
                    repeatDaySelectedRunBackground(cornerRadius: weekdayCornerRadius)
                        .frame(width: runWidth, height: selectedHeight)
                        .offset(x: runX, y: trackPadding)
                        .allowsHitTesting(false)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }

                HStack(spacing: 0) {
                    ForEach(weekdayNames.indices, id: \.self) { idx in
                        Button(action: {
                            toggleWeekday(idx)
                        }) {
                            Text(weekdayNames[idx].uppercased())
                                .font(AppTypography.style(.caption2, weight: .semibold))
                                .tracking(0.3)
                                .foregroundColor(selectedWeekdays[idx] ? .black.opacity(0.78) : .white.opacity(0.64))
                                .frame(width: slotWidth)
                                .frame(height: weekdayHeight)
                                .clipShape(RoundedRectangle(cornerRadius: weekdayCornerRadius, style: .continuous))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: weekdayCornerRadius, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
                .padding(trackPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                // Swipe-to-select gesture overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let adjustedX = min(max(value.location.x - trackPadding, 0), max(width - 1, 0))
                                let idx = min(max(Int(adjustedX / slotWidth), 0), 6)

                                // On first call, detect swipe mode based on starting day
                                if draggingSelects == nil && idx < selectedWeekdays.count {
                                    draggingSelects = !selectedWeekdays[idx]
                                }

                                // Apply swipe mode to current day
                                if let mode = draggingSelects, idx < selectedWeekdays.count {
                                    setWeekday(idx, selected: mode)
                                }
                            }
                            .onEnded { _ in
                                // Clear swipe mode when drag ends
                                draggingSelects = nil
                            }
                    )
            )
        }
        .frame(height: weekdayHeight + (trackPadding * 2))
    }

    private var embeddedRepeatScheduleBar: some View {
        weekdaySelectionBar(
            weekdaySpacing: 1,
            weekdayCornerRadius: 11,
            weekdayHeight: 32,
            trackPadding: 4
        )
    }

    private var selectedWeekdayRuns: [WeekdaySelectionRun] {
        var runs: [WeekdaySelectionRun] = []
        var start: Int?

        for index in selectedWeekdays.indices {
            if selectedWeekdays[index] {
                if start == nil {
                    start = index
                }
            } else if let currentStart = start {
                runs.append(WeekdaySelectionRun(startIndex: currentStart, endIndex: index - 1))
                start = nil
            }
        }

        if let currentStart = start {
            runs.append(WeekdaySelectionRun(startIndex: currentStart, endIndex: selectedWeekdays.count - 1))
        }

        return runs
    }

    private func toggleWeekday(_ index: Int) {
        guard selectedWeekdays.indices.contains(index) else { return }
        setWeekday(index, selected: !selectedWeekdays[index])
    }

    private func setWeekday(_ index: Int, selected: Bool) {
        guard selectedWeekdays.indices.contains(index),
              selectedWeekdays[index] != selected else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            selectedWeekdays[index] = selected
        }
    }

    // MARK: - Repeat Day Selection Background

    private func repeatDaySelectedRunBackground(cornerRadius: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.56),
                        Color.white.opacity(0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.03),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private var weekdayTrackBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .background(.ultraThinMaterial.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func triggerSelectionContent(geometry: GeometryProxy) -> some View {
        let isEmbedded = presentationStyle == .embedded
        let tabHeight: CGFloat = isEmbedded ? 38 : 40
        let tabGap: CGFloat = isEmbedded ? 8 : 10
        let cardHeight: CGFloat = {
            if isEmbedded {
                return 214
            }
            return 198
        }()
        let embeddedRepeatHeight: CGFloat = isEmbedded ? 40 : 0
        let embeddedRepeatTopGap: CGFloat = isEmbedded ? 7 : 0
        let embeddedRepeatBottomPadding: CGFloat = isEmbedded ? 8 : 0
        let triggerContentHeight = max(
            120,
            cardHeight - embeddedRepeatHeight - embeddedRepeatTopGap - embeddedRepeatBottomPadding
        )
        let cornerRadius: CGFloat = isEmbedded ? 18 : 16
        let totalHeight = tabHeight + tabGap + cardHeight
        let contentWidth = max(0, geometry.size.width)
        let cardContentInset: CGFloat = isEmbedded ? 4 : 6
        let cardContentWidth = max(0, contentWidth - (cardContentInset * 2))

        let gradientStops: [Gradient.Stop] = {
            if triggerSelection == .time {
                if isEmbedded {
                    return [
                        .init(color: Color.white.opacity(0.18), location: 0.0),
                        .init(color: Color.white.opacity(0.08), location: 1.0)
                    ]
                }
                return [
                    .init(color: Color.black.opacity(0.4), location: 0.0),
                    .init(color: Color.black.opacity(0.25), location: 1.0)
                ]
            } else {
                return SolarOffsetArcSlider.gradientStops(for: selectedSolarEvent)
            }
        }()

        // PERFORMANCE FIX: Reduced gradient height from 30x to 6x
        let scrollOffset: CGFloat = {
            guard triggerSelection != .time else { return 0 }
            let gradientHeight = cardHeight * 6  // Reduced for better performance
            let range: ClosedRange<Double> = Double(SolarTrigger.minOnDeviceOffsetMinutes)...Double(SolarTrigger.maxOnDeviceOffsetMinutes)
            let normalized = max(0, min(1, (solarOffsetMinutes - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let scrollableHeight = gradientHeight - cardHeight
            return normalized * scrollableHeight
        }()

        let gradient = LinearGradient(
            gradient: Gradient(stops: gradientStops),
            startPoint: .top,
            endPoint: .bottom
        )

        VStack(spacing: 0) {
            // Trigger row aligned with card edges
            HStack(spacing: 4) {
                // Explicit order: Sunrise | Sunset | Time of Day
                ForEach([TriggerSelection.sunrise, .sunset, .time], id: \.self) { option in
                    let isActive = triggerSelection == option
                    let isAvailable = isTriggerOptionAvailable(option)

                    Button {
                        guard isAvailable else { return }
                        Task { await handleTriggerSelectionTap(option) }
                    } label: {
                        Text(triggerSelectionLabel(for: option))
                            .font(AppTypography.style(isEmbedded ? .caption : .footnote, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                            .foregroundColor(isActive ? .black.opacity(0.78) : .white.opacity(isAvailable ? 0.64 : 0.34))
                            .frame(maxWidth: .infinity, minHeight: max(0, tabHeight - 8))
                            .padding(.horizontal, isEmbedded ? 4 : 8)
                            .background(triggerSelectionSegmentBackground(isActive: isActive))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(isAvailable ? 1.0 : 0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(!isAvailable)
                }
            }
            .padding(4)
            .frame(width: contentWidth, height: tabHeight)
            .background(triggerSelectionTrackBackground)
            .padding(.bottom, tabGap)
            .zIndex(2)

            // Card with gradient background (masked to rounded shape)
            ZStack {
                // Gradient background masked to card shape
                GeometryReader { geo in
                    Group {
                        if triggerSelection == .time {
                            gradient
                                .frame(width: geo.size.width, height: cardHeight)
                        } else {
                            gradient
                                .frame(width: geo.size.width, height: cardHeight * 6)
                                .offset(y: -scrollOffset)
                        }
                    }
                }
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .frame(height: cardHeight)
                )
                .allowsHitTesting(false)

                // Glass layer on top of gradient (shared chrome)
                cardChrome(cornerRadius: cornerRadius)

                // Content layer - unified structure
                Group {
                    if isEmbedded {
                        VStack(spacing: embeddedRepeatTopGap) {
                            triggerControlContent(
                                cardHeight: triggerContentHeight,
                                cardWidth: cardContentWidth,
                                cardContentInset: cardContentInset
                            )
                            .frame(width: contentWidth, height: triggerContentHeight)

                            embeddedRepeatScheduleBar
                                .padding(.horizontal, cardContentInset + 6)
                                .frame(width: contentWidth, height: embeddedRepeatHeight)
                                .overlay(alignment: .topLeading) {
                                    if !selectedWeekdays.contains(true) {
                                        repeatDayValidationBubble
                                            .offset(x: cardContentInset + 6, y: -34)
                                            .zIndex(4)
                                    }
                                }
                        }
                        .padding(.bottom, embeddedRepeatBottomPadding)
                        .frame(width: contentWidth, height: cardHeight, alignment: .top)
                    } else {
                        triggerControlContent(
                            cardHeight: cardHeight,
                            cardWidth: cardContentWidth,
                            cardContentInset: cardContentInset
                        )
                        .frame(width: contentWidth, height: cardHeight)
                    }
                }
                .frame(width: contentWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(width: contentWidth, height: cardHeight)
            .zIndex(0)
        }
        .frame(width: contentWidth, height: totalHeight)
    }

    @ViewBuilder
    private func triggerControlContent(
        cardHeight: CGFloat,
        cardWidth: CGFloat,
        cardContentInset: CGFloat
    ) -> some View {
        if triggerSelection == .time {
            timeTriggerContent(cardHeight: cardHeight, cardWidth: cardWidth)
                .padding(.horizontal, cardContentInset)
        } else {
            SolarOffsetArcSlider(
                offsetMinutes: $solarOffsetMinutes,
                eventType: selectedSolarEvent,
                device: activeDevice,
                disableClipping: true,
                useExternalGradient: true
            )
            .padding(.horizontal, cardContentInset)
        }
    }

    // MARK: - Card Chrome Helper

    private func cardChrome(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(presentationStyle == .embedded ? 0.09 : 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(presentationStyle == .embedded ? 0.14 : 0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(presentationStyle == .embedded ? 0.08 : 0.2), radius: presentationStyle == .embedded ? 4 : 8, x: 0, y: presentationStyle == .embedded ? 2 : 4)
    }

    // MARK: - Trigger Selection Styling

    private func triggerSelectionLabel(for option: TriggerSelection) -> String {
        option == .time ? "Time" : option.rawValue
    }

    private var triggerSelectionTrackBackground: some View {
        automationSegmentTrackBackground(cornerRadius: 18)
    }

    private func triggerSelectionSegmentBackground(isActive: Bool) -> some View {
        automationSegmentBackground(isActive: isActive, cornerRadius: 14)
    }

    private func timeTriggerContent(cardHeight: CGFloat, cardWidth: CGFloat) -> some View {
        // Wheel pickers are ~216pt tall; crop instead of vertically scaling so numerals stay legible.
        let pickerHeight: CGFloat = 216
        let pickerWidth = min(max(cardWidth, 260), 340)
        let horizontalScale = min(1, max(0.88, (cardWidth - 6) / max(pickerWidth, 1)))

        return HStack(spacing: 0) {
            Picker("", selection: selectedTimeHourBinding) {
                ForEach(1...12, id: \.self) { hour in
                    Text("\(hour)")
                        .font(AppTypography.style(.title2, weight: .regular))
                        .foregroundColor(.white)
                        .tag(hour)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: pickerWidth * 0.28)
            .clipped()

            Picker("", selection: selectedTimeMinuteBinding) {
                ForEach(0...59, id: \.self) { minute in
                    Text(String(format: "%02d", minute))
                        .font(AppTypography.style(.title2, weight: .regular))
                        .foregroundColor(.white)
                        .tag(minute)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: pickerWidth * 0.34)
            .clipped()

            Picker("", selection: selectedTimePeriodBinding) {
                Text("AM")
                    .font(AppTypography.style(.title2, weight: .regular))
                    .foregroundColor(.white)
                    .tag(false)
                Text("PM")
                    .font(AppTypography.style(.title2, weight: .regular))
                    .foregroundColor(.white)
                    .tag(true)
            }
            .pickerStyle(.wheel)
            .frame(width: pickerWidth * 0.28)
            .clipped()
        }
            .frame(width: pickerWidth, height: pickerHeight)
            .environment(\.colorScheme, .dark)
            .background(Color.clear)  // Remove default background
            .scaleEffect(x: horizontalScale, y: 1, anchor: .center)
            .frame(width: cardWidth, alignment: .center)
            .frame(height: cardHeight)  // Enforce final height
            .contentShape(Rectangle())
            .clipped()
    }

    private var selectedTimeHourBinding: Binding<Int> {
        Binding(
            get: { selectedTimeHour12 },
            set: { hour in
                updateSelectedTime(hour12: hour, minute: selectedTimeMinute, isPM: selectedTimeIsPM)
            }
        )
    }

    private var selectedTimeMinuteBinding: Binding<Int> {
        Binding(
            get: { selectedTimeMinute },
            set: { minute in
                updateSelectedTime(hour12: selectedTimeHour12, minute: minute, isPM: selectedTimeIsPM)
            }
        )
    }

    private var selectedTimePeriodBinding: Binding<Bool> {
        Binding(
            get: { selectedTimeIsPM },
            set: { isPM in
                updateSelectedTime(hour12: selectedTimeHour12, minute: selectedTimeMinute, isPM: isPM)
            }
        )
    }

    private var selectedTimeHour12: Int {
        let hour = Calendar.current.component(.hour, from: selectedTime)
        let normalized = hour % 12
        return normalized == 0 ? 12 : normalized
    }

    private var selectedTimeMinute: Int {
        Calendar.current.component(.minute, from: selectedTime)
    }

    private var selectedTimeIsPM: Bool {
        Calendar.current.component(.hour, from: selectedTime) >= 12
    }

    private func updateSelectedTime(hour12: Int, minute: Int, isPM: Bool) {
        var calendar = Calendar.current
        calendar.locale = Locale.current
        var components = calendar.dateComponents([.year, .month, .day], from: selectedTime)
        components.hour = (hour12 % 12) + (isPM ? 12 : 0)
        components.minute = minute
        components.second = 0
        if let date = calendar.date(from: components) {
            selectedTime = date
        }
    }

    // MARK: - Action Section

    private var automationActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                sectionHeader(
                    title: "Light Action",
                    subtitle: actionSectionSubtitle
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                if actionSelectionSupportsPreview {
                    actionPreviewToggle
                        .padding(.top, actionSectionSubtitle == nil ? 0 : 1)
                }
            }

            actionSelectionButtons

            switch actionSelection {
            case .color:
                colorActionControls
            case .scene:
                sceneActionControls
            case .transition:
                transitionActionControls
            case .effect:
                effectActionControls
            }
        }
    }

    private var actionSelectionSupportsPreview: Bool {
        switch actionSelection {
        case .color, .transition, .effect:
            return true
        case .scene:
            return false
        }
    }

    private var actionPreviewToggle: some View {
        Button {
            actionPreviewEnabled.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: actionPreviewEnabled ? "eye.fill" : "eye")
                    .font(AppTypography.style(.caption2, weight: .semibold))
                Text("Preview")
                    .font(AppTypography.style(.caption, weight: .semibold))
            }
            .foregroundColor(actionPreviewEnabled ? .black.opacity(0.78) : .white.opacity(0.64))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                actionPreviewBackground
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionPreviewBackground: some View {
        if actionPreviewEnabled {
            secondaryControlBackground(isActive: true, cornerRadius: 15)
        } else {
            secondaryControlBackground(isActive: false, cornerRadius: 15)
        }
    }

    private var actionSectionSubtitle: String? {
        isFirstAutomationForSelectedTargets ? "What the lamp does when this runs." : nil
    }

    private var isFirstAutomationForSelectedTargets: Bool {
        let targets = selectedDeviceIds.isEmpty ? Set([activeDevice.id]) : selectedDeviceIds
        return !automationStore.automations.contains { automation in
            if automation.id == editingAutomation?.id {
                return false
            }
            return !Set(automation.targets.deviceIds).isDisjoint(with: targets)
        }
    }

    private var actionSelectionButtons: some View {
        let segmentHeight: CGFloat = presentationStyle == .embedded ? 38 : 40
        let segmentLabelHeight = max(0, segmentHeight - 8)

        return HStack(spacing: 4) {
            ForEach(availableActionSelections) { option in
                let isActive = actionSelection == option
                Button {
                    guard lockedAction == nil else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        actionPreviewEnabled = false
                        actionSelection = option
                    }
                } label: {
                    Text(actionSelectionLabel(for: option))
                        .font(AppTypography.style(presentationStyle == .embedded ? .caption : .footnote, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .foregroundColor(isActive ? .black.opacity(0.78) : .white.opacity(0.64))
                        .frame(maxWidth: .infinity, minHeight: segmentLabelHeight)
                        .padding(.horizontal, presentationStyle == .embedded ? 4 : 8)
                        .background(automationSegmentBackground(isActive: isActive))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(lockedAction == nil || isActive ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(lockedAction != nil)
            }
        }
        .padding(4)
        .frame(height: segmentHeight)
        .background(
            automationSegmentTrackBackground(cornerRadius: 18)
        )
    }

    private func automationSegmentTrackBackground(cornerRadius: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .background(.ultraThinMaterial.opacity(0.64), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }

    private func automationSegmentBackground(isActive: Bool, cornerRadius: CGFloat = 14) -> some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .appLiquidGlass(role: .card, cornerRadius: cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.54),
                                        Color.white.opacity(0.22),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.015))
            }
        }
    }

    private func secondaryControlBackground(isActive: Bool, cornerRadius: CGFloat = 15) -> some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .appLiquidGlass(role: .control, cornerRadius: cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.58),
                                        Color.white.opacity(0.28)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .background(.ultraThinMaterial.opacity(0.64), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
            }
        }
    }

    private func actionSelectionLabel(for option: ActionSelection) -> String {
        switch option {
        case .color:
            return "Color"
        case .transition:
            return "Transition"
        case .effect:
            return "Animation"
        case .scene:
            return "Scene"
        }
    }

    private var effectActionControls: some View {
        AutomationEffectEditor(
            viewModel: viewModel,
            device: activeDevice,
            effectOptions: effectOptions,
            effectId: Binding(
                get: { selectedEffectId ?? effectOptions.first?.id ?? 0 },
                set: { newId in
                    selectedEffectId = newId
                    selectedEffectPresetId = nil
                    // Update gradient for new slot count
                    if let metadata = effectOptions.first(where: { $0.id == newId }) {
                        let slotCount = max(metadata.colorSlotCount, 1)
                        if slotCount <= 1 {
                            // Single color mode
                            let currentHex = effectGradient?.stops.first?.hexColor ?? "FFFFFF"
                            effectGradient = LEDGradient(stops: [GradientStop(position: 0.0, hexColor: currentHex)])
                        } else {
                            // Multi-color mode - prepare gradient for slot count
                            let currentGrad = effectGradient ?? viewModel.automationGradient(for: activeDevice)
                            effectGradient = preparedGradientForSlotCount(currentGrad, slotCount: slotCount)
                        }
                    }
                }
            ),
            brightness: $effectBrightness,
            speed: $effectSpeed,
            intensity: $effectIntensity,
            gradient: Binding(
                get: { effectGradient ?? viewModel.automationGradient(for: activeDevice) },
                set: { newGradient in
                    effectGradient = newGradient
                        selectedEffectPresetId = nil
                }
            ),
            selectedEffectPresetId: $selectedEffectPresetId,
            isInline: presentationStyle == .embedded,
            externalPreviewEnabled: $actionPreviewEnabled
        )
    }

    @ViewBuilder
    private var sceneActionControls: some View {
        let choices = sortedScenes

        if choices.isEmpty {
            Text("No saved scenes for this device yet. Save a scene first, then schedule it.")
                .font(AppTypography.style(.footnote))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            VStack(spacing: 8) {
                ForEach(choices) { scene in
                    sceneSelectionRow(scene)
                }
            }

            if let scene = selectedScene {
                Text("Runs on \(deviceName(for: scene.deviceId)) at the scheduled time.")
                    .font(AppTypography.style(.caption))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sceneSelectionRow(_ scene: Scene) -> some View {
        let selected = selectedSceneId == scene.id
        return Button {
            selectedSceneId = scene.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? .white : .white.opacity(0.45))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.name)
                        .font(AppTypography.style(.subheadline, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                    Text(deviceName(for: scene.deviceId))
                        .font(AppTypography.style(.caption))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                Text(sceneTypeLabel(for: scene))
                    .font(AppTypography.style(.caption2, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0.32 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func preparedGradientForSlotCount(_ gradient: LEDGradient, slotCount: Int) -> LEDGradient {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        if slotCount <= 1 {
            let hex = sortedStops.first?.hexColor ?? "FFFFFF"
            return LEDGradient(stops: [GradientStop(position: 0.0, hexColor: hex)], interpolation: gradient.interpolation)
                    }
        let clampedCount = max(2, slotCount)
        let positions: [Double]
        if clampedCount == 2 {
            positions = [0.0, 1.0]
        } else {
            positions = (0..<clampedCount).map { Double($0) / Double(clampedCount - 1) }
        }
        let generatedStops = positions.map { t -> GradientStop in
            let sourceStops = sortedStops.isEmpty ? gradient.stops : sortedStops
            let color = GradientSampler.sampleColor(at: t, stops: sourceStops, interpolation: gradient.interpolation)
            return GradientStop(position: t, hexColor: color.toHex())
        }
        return LEDGradient(stops: generatedStops, interpolation: gradient.interpolation)
    }

    private var colorActionControls: some View {
                gradientCreationControls
            .onChange(of: templateGradient) { _, newGradient in
                // Sync interpolation when gradient changes
                if let newGradient = newGradient {
                    gradientInterpolation = newGradient.interpolation
            }
        }
    }

    private var gradientCreationControls: some View {
        AutomationColorEditor(
            viewModel: viewModel,
            device: activeDevice,
            gradient: Binding(
                get: { templateGradient ?? viewModel.automationGradient(for: activeDevice) },
                set: { newGradient in
                    templateGradient = newGradient
                    gradientInterpolation = newGradient.interpolation
                }
            ),
            brightness: $gradientBrightness,
            interpolation: $gradientInterpolation,
            fadeDuration: $gradientDuration,
            enableFade: $enableColorFade,
            powerOn: $colorPowerOn,
            selectedPresetId: $selectedColorPresetId,
            temperature: $gradientTemperature,
            whiteLevel: $gradientWhiteLevel,
            showFadeControls: advancedUIEnabled,
            isInline: presentationStyle == .embedded,
            externalPreviewEnabled: $actionPreviewEnabled
        )
    }
    private var transitionActionControls: some View {
        AutomationTransitionEditor(
            viewModel: viewModel,
            device: activeDevice,
            startGradient: Binding(
                get: { transitionStartGradient ?? LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: "FFA000"),
                    GradientStop(position: 1.0, hexColor: "FFFFFF")
                ]) },
                set: { newGradient in
                    transitionStartGradient = newGradient
                    selectedTransitionPresetId = nil  // Clear preset selection when manually editing
                }
            ),
            endGradient: Binding(
                get: { transitionEndGradient ?? LEDGradient(stops: [
                    GradientStop(position: 0.0, hexColor: "FFFFFF"),
                    GradientStop(position: 1.0, hexColor: "FFA000")
                ]) },
                set: { newGradient in
                    transitionEndGradient = newGradient
                    selectedTransitionPresetId = nil  // Clear preset selection when manually editing
                }
            ),
            startBrightness: $transitionStartBrightness,
            endBrightness: $transitionEndBrightness,
            durationSeconds: $customTransitionDuration,
            startTemperature: $transitionStartTemperature,
            startWhiteLevel: $transitionStartWhiteLevel,
            endTemperature: $transitionEndTemperature,
            endWhiteLevel: $transitionEndWhiteLevel,
            selectedTransitionPresetId: $selectedTransitionPresetId,
            transitionProfile: transitionProfileForActiveDevice,
            showsDurationRecommendationGuide: presentationStyle != .embedded,
            expectedStartDate: transitionSchedulePreviewStart,
            expectedEndDate: transitionSchedulePreviewEnd,
            expectedTimeZone: transitionSchedulePreviewTimeZone,
            isInline: presentationStyle == .embedded,
            externalPreviewEnabled: $actionPreviewEnabled
        )
    }

    // MARK: - Computed Properties

    private var sortedScenes: [Scene] {
        scenes.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var selectedScene: Scene? {
        guard let id = selectedSceneId else { return nil }
        return scenes.first(where: { $0.id == id })
    }

    private func deviceName(for deviceId: String) -> String {
        availableDevices.first(where: { $0.id == deviceId })?.name ?? "Device"
    }

    private func sceneTypeLabel(for scene: Scene) -> String {
        if scene.transitionEnabled {
            return "Transition"
        }
        if scene.effectsEnabled {
            return "Animation"
        }
        return "Color"
    }

    private var canSave: Bool {
        if automationStore.hasAnyDeletionInProgress {
            return false
        }
        if automationStore.hasOnDeviceSyncInProgress(for: selectedDeviceIds) {
            return false
        }
        guard !automationName.trimmed().isEmpty else { return false }
        guard !selectedDeviceIds.isEmpty else { return false }
        if !selectedWeekdays.contains(true) {
            return false
        }
        if !isDateWindowValid {
            return false
        }
        if !timerSlotCapacitySatisfied {
            return false
        }
        if actionSelection == .scene && selectedScene == nil {
            return false
        }
        if actionSelection == .effect {
            return selectedEffectId != nil
        }
        if requiredPresetSlots > 0 {
            return presetCapacitySatisfied
        }
        return true
    }

    private var selectedSolarEvent: SolarEvent {
        triggerSelection == .sunrise ? .sunrise : .sunset
    }

    private var targetDevicesForCapacity: [WLEDDevice] {
        let targetIds = selectedDeviceIds.isEmpty ? [activeDevice.id] : Array(selectedDeviceIds)
        let targets = availableDevices.filter { targetIds.contains($0.id) }
        return targets.isEmpty ? [activeDevice] : targets
    }

    private struct TransitionPlanningInput {
        let startGradient: LEDGradient
        let endGradient: LEDGradient
        let startBrightness: Int
        let endBrightness: Int
        let durationSeconds: Double
    }

    private var transitionPlanningInput: TransitionPlanningInput? {
        if let lockedAction {
            guard case .transition(let payload) = lockedAction else { return nil }
            return TransitionPlanningInput(
                startGradient: payload.startGradient,
                endGradient: payload.endGradient,
                startBrightness: payload.startBrightness,
                endBrightness: payload.endBrightness,
                durationSeconds: payload.durationSeconds
            )
        }

        guard actionSelection == .transition else { return nil }
        if let preset = selectedTransitionPreset {
            return TransitionPlanningInput(
                startGradient: preset.gradientA,
                endGradient: preset.gradientB,
                startBrightness: preset.brightnessA,
                endBrightness: preset.brightnessB,
                durationSeconds: preset.durationSec
            )
        }

        let startGradient = transitionStartGradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFFFFF")
        ])
        let endGradient = transitionEndGradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFFFFF"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ])
        return TransitionPlanningInput(
            startGradient: startGradient,
            endGradient: endGradient,
            startBrightness: Int(transitionStartBrightness),
            endBrightness: Int(transitionEndBrightness),
            durationSeconds: customTransitionDuration
        )
    }

    private var transitionProfilesByDevice: [(device: WLEDDevice, profile: TransitionStepProfile)] {
        guard let input = transitionPlanningInput else { return [] }
        return targetDevicesForCapacity.map { target in
            let profile = viewModel.planTransitionPlaylist(
                durationSec: input.durationSeconds,
                startGradient: input.startGradient,
                endGradient: input.endGradient,
                startBrightness: input.startBrightness,
                endBrightness: input.endBrightness,
                context: .persistentAutomation,
                device: target
            )
            return (target, profile)
        }
    }

    private var transitionProfileForActiveDevice: TransitionStepProfile? {
        if let profile = transitionProfilesByDevice.first(where: { $0.device.id == activeDevice.id })?.profile {
            return profile
        }
        return transitionProfilesByDevice.first?.profile
    }

    private var transitionStorageSatisfied: Bool {
        guard transitionPlanningInput != nil else { return true }
        return !transitionProfilesByDevice.isEmpty
            && transitionProfilesByDevice.allSatisfy { $0.profile.fitsStorage }
    }

    private var requiredPresetSlots: Int {
        if let lockedAction {
            switch lockedAction {
            case .preset, .playlist:
                return 0
            case .transition:
                return transitionProfilesByDevice.map(\.profile.slotsRequired).max() ?? 0
            case .gradient, .effect, .directState, .scene:
                return 1
            }
        }

        switch actionSelection {
        case .transition:
            return transitionProfilesByDevice.map(\.profile.slotsRequired).max() ?? 0
        case .color:
            return 1
        case .scene:
            return 1
        case .effect:
            return 1
        }
    }

    private var storageCapacityRange: ClosedRange<Int> {
        if let lockedAction {
            if case .transition = lockedAction {
                return persistentAutomationPresetRange
            }
            return appManagedPresetRange
        }
        return actionSelection == .transition ? persistentAutomationPresetRange : appManagedPresetRange
    }

    private var presetCapacityContext: (device: WLEDDevice, status: DeviceControlViewModel.PresetSlotAvailability)? {
        let candidates = targetDevicesForCapacity.compactMap { device -> (WLEDDevice, DeviceControlViewModel.PresetSlotAvailability)? in
            guard let status = viewModel.presetSlotAvailability(for: device, range: storageCapacityRange) else { return nil }
            return (device, status)
        }
        return candidates.min { $0.1.available < $1.1.available }
    }

    private var presetCapacitySatisfied: Bool {
        guard requiredPresetSlots > 0 else { return true }
        if transitionPlanningInput != nil {
            let storageLoaded = targetDevicesForCapacity.allSatisfy {
                viewModel.presetSlotAvailability(for: $0, range: storageCapacityRange) != nil
            }
            return storageLoaded && transitionStorageSatisfied
        }
        return targetDevicesForCapacity.allSatisfy { device in
            guard let status = viewModel.presetSlotAvailability(for: device, range: storageCapacityRange) else { return false }
            return status.available >= requiredPresetSlots
        }
    }

    private var transitionStorageContext: (device: WLEDDevice, profile: TransitionStepProfile)? {
        transitionProfilesByDevice.min { lhs, rhs in
            let leftMargin = (lhs.profile.availableSlots ?? Int.max) - lhs.profile.slotsRequired
            let rightMargin = (rhs.profile.availableSlots ?? Int.max) - rhs.profile.slotsRequired
            return leftMargin < rightMargin
        }
    }

    private var presetCapacityMessage: String? {
        guard requiredPresetSlots > 0 else { return nil }
        if transitionPlanningInput != nil && presetCapacityContext == nil {
            return "Checking saved-entry space..."
        }
        if let context = transitionStorageContext {
            let profile = context.profile
            if !profile.fitsStorage {
                let maxDuration = TransitionDurationPicker.clockString(seconds: profile.maxDurationSecondsAtCurrentQuality ?? 0)
                let available = profile.availableSlots ?? 0
                return "This transition needs \(profile.slotsRequired) saved entries on \(context.device.name), but only \(available) are available after reserve. Try a shorter duration or free saved presets. About \(maxDuration) fits with the current storage."
            }
            let adjusted = profile.wasCoarsened
                ? " The step spacing was adjusted so it fits safely."
                : ""
            let available = profile.availableSlots ?? 0
            return "Storage looks good on \(context.device.name): this transition needs \(profile.slotsRequired) saved entries, with \(available) available after reserve.\(adjusted)"
        }
        guard let context = presetCapacityContext else {
            return "Checking preset storage..."
        }
        let status = context.status
        if status.available < requiredPresetSlots {
            return "Not enough saved-entry space on \(context.device.name). \(status.available) available after reserve, need \(requiredPresetSlots)."
        }
        return "Storage looks good on \(context.device.name): this automation needs \(savedEntryCountText(requiredPresetSlots)), with \(status.available) available after reserve."
    }

    private var transitionDurationForGuidance: Double? {
        transitionPlanningInput?.durationSeconds
    }

    private var transitionDurationRecommendationMessage: String? {
        guard let duration = transitionDurationForGuidance else { return nil }
        guard TransitionDurationPicker.exceedsRecommendedMax(duration) else { return nil }
        let recommended = TransitionDurationPicker.clockString(seconds: Double(TransitionDurationPicker.recommendedMaxSeconds))
        return "Selected transition is above the recommended \(recommended). Keeping transitions at or below this helps preserve reliability and preset headroom across multiple automations."
    }

    private var selectedTriggerKindForCapacity: AutomationStore.OnDeviceTriggerKind {
        switch triggerSelection {
        case .time:
            return .specificTime
        case .sunrise:
            return .sunrise
        case .sunset:
            return .sunset
        }
    }

    private var timerSlotCapacityValidation: AutomationStore.OnDeviceScheduleValidation {
        let targetIds = selectedDeviceIds.isEmpty ? [activeDevice.id] : Array(selectedDeviceIds)
        return automationStore.validateLocalTimerCapacity(
            triggerKind: selectedTriggerKindForCapacity,
            targetDeviceIds: targetIds,
            excludingAutomationId: editingAutomation?.id
        )
    }

    private var timerSlotCapacitySatisfied: Bool {
        timerSlotCapacityValidation.isValid
    }

    private var timerSlotCapacityMessage: String? {
        timerSlotCapacityValidation.message
    }

    private var timerSlotLimitPromptMessage: String? {
        guard !timerSlotCapacitySatisfied else { return nil }
        guard selectedTriggerKindForCapacity == .specificTime else { return timerSlotCapacityMessage }
        let targetIds = selectedDeviceIds.isEmpty ? [activeDevice.id] : Array(selectedDeviceIds)
        return "Maximum reached on \(targetDeviceNames(for: targetIds)): 8/8 time-of-day automations are already set. Delete an existing time-of-day automation to make room for a new one."
    }

    private func targetDeviceNames(for deviceIds: [String]) -> String {
        let names = availableDevices
            .filter { deviceIds.contains($0.id) }
            .map(\.name)
            .sorted()
        if names.isEmpty {
            return deviceIds.joined(separator: ", ")
        }
        return names.joined(separator: ", ")
    }

    private func triggerKind(for selection: TriggerSelection) -> AutomationStore.OnDeviceTriggerKind {
        switch selection {
        case .time:
            return .specificTime
        case .sunrise:
            return .sunrise
        case .sunset:
            return .sunset
        }
    }

    private func isTriggerOptionAvailable(_ selection: TriggerSelection) -> Bool {
        let targetIds = selectedDeviceIds.isEmpty ? [activeDevice.id] : Array(selectedDeviceIds)
        let validation = automationStore.validateLocalTimerCapacity(
            triggerKind: triggerKind(for: selection),
            targetDeviceIds: targetIds,
            excludingAutomationId: editingAutomation?.id
        )
        return validation.isValid
    }

    private func normalizeTriggerSelectionIfNeeded() {
        guard !isTriggerOptionAvailable(triggerSelection) else { return }
        if isTriggerOptionAvailable(.sunrise) {
            triggerSelection = .sunrise
            return
        }
        if isTriggerOptionAvailable(.sunset) {
            triggerSelection = .sunset
            return
        }
        if isTriggerOptionAvailable(.time) {
            triggerSelection = .time
        }
    }

    private func normalizeSceneSelectionIfNeeded() {
        guard actionSelection == .scene else { return }

        guard !sortedScenes.isEmpty else {
            selectedSceneId = nil
            return
        }

        if selectedScene == nil {
            selectedSceneId = sortedScenes.first?.id
        }

        guard let scene = selectedScene else { return }
        let desiredDeviceIds: Set<String> = [scene.deviceId]
        if selectedDeviceIds != desiredDeviceIds {
            selectedDeviceIds = desiredDeviceIds
        }
        if activeDevice.id != scene.deviceId,
           let resolved = availableDevices.first(where: { $0.id == scene.deviceId }) {
            activeDevice = resolved
        }
    }

    private var isDateWindowValid: Bool {
        dateWindowValidationMessage == nil
    }

    @MainActor
    private func refreshTransitionSchedulePreview() async {
        let schedule = await computeNextTransitionSchedulePreview(referenceDate: Date())
        transitionSchedulePreviewStart = schedule.start
        transitionSchedulePreviewEnd = schedule.start?.addingTimeInterval(max(0, customTransitionDuration))
        transitionSchedulePreviewTimeZone = schedule.timeZone
    }

    @MainActor
    private func refreshOnDeviceScheduleOverlapWarning() async {
        guard let automation = buildAutomation(), automation.metadata.runOnDevice else {
            onDeviceScheduleOverlapWarningMessage = nil
            return
        }
        onDeviceScheduleOverlapWarningMessage = await automationStore.previewOnDeviceScheduleOverlapWarning(for: automation)
    }

    @MainActor
    private func computeNextTransitionSchedulePreview(referenceDate: Date) async -> (start: Date?, timeZone: TimeZone) {
        let normalizedWeekdays = WeekdayMask.normalizeSunFirst(selectedWeekdays)

        switch triggerSelection {
        case .time:
            let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
            guard let hour = components.hour, let minute = components.minute else {
                return (nil, .current)
            }
            let timeZone = TimeZone.current
            let next = nextSpecificTimeTriggerDate(
                hour: hour,
                minute: minute,
                weekdays: normalizedWeekdays,
                referenceDate: referenceDate,
                timeZone: timeZone
            )
            return (next, timeZone)

        case .sunrise, .sunset:
            guard let reference = await automationStore.currentSolarReference(for: activeDevice) else {
                return (nil, .current)
            }
            let event: SolarEvent = triggerSelection == .sunrise ? .sunrise : .sunset
            let clampedOffset = SolarTrigger.clampOnDeviceOffset(Int(solarOffsetMinutes.rounded()))
            let next = nextSolarTriggerDate(
                event: event,
                coordinate: reference.coordinate,
                offsetMinutes: clampedOffset,
                weekdays: normalizedWeekdays,
                referenceDate: referenceDate,
                timeZone: reference.timeZone
            )
            return (next, reference.timeZone)
        }
    }

    private func nextSpecificTimeTriggerDate(
        hour: Int,
        minute: Int,
        weekdays: [Bool],
        referenceDate: Date,
        timeZone: TimeZone
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let normalizedWeekdays = WeekdayMask.normalizeSunFirst(weekdays)
        let dayStart = calendar.startOfDay(for: referenceDate)

        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let triggerDate = calendar.date(from: components), triggerDate > referenceDate else { continue }
            let weekdayIndex = calendar.component(.weekday, from: triggerDate) - 1
            guard weekdayIndex >= 0, weekdayIndex < normalizedWeekdays.count, normalizedWeekdays[weekdayIndex] else {
                continue
            }
            guard isWithinDateWindow(triggerDate, calendar: calendar) else { continue }
            return triggerDate
        }

        return nil
    }

    private func nextSolarTriggerDate(
        event: SolarEvent,
        coordinate: CLLocationCoordinate2D,
        offsetMinutes: Int,
        weekdays: [Bool],
        referenceDate: Date,
        timeZone: TimeZone
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let normalizedWeekdays = WeekdayMask.normalizeSunFirst(weekdays)
        let dayStart = calendar.startOfDay(for: referenceDate)

        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) else { continue }
            guard let triggerDate = automationStore.resolveSolarTriggerDate(
                event: event,
                coordinate: coordinate,
                date: day,
                offsetMinutes: offsetMinutes,
                timeZone: timeZone
            ) else {
                continue
            }
            guard triggerDate > referenceDate else { continue }
            let weekdayIndex = calendar.component(.weekday, from: triggerDate) - 1
            guard weekdayIndex >= 0, weekdayIndex < normalizedWeekdays.count, normalizedWeekdays[weekdayIndex] else {
                continue
            }
            guard isWithinDateWindow(triggerDate, calendar: calendar) else { continue }
            return triggerDate
        }

        return nil
    }

    private func isWithinDateWindow(_ date: Date, calendar: Calendar) -> Bool {
        guard useDateWindow else { return true }
        guard isValidCalendarDay(month: startMonth, day: startDay),
              isValidCalendarDay(month: endMonth, day: endDay) else {
            return false
        }

        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return false }

        let value = month * 100 + day
        let startValue = startMonth * 100 + startDay
        let endValue = endMonth * 100 + endDay

        if startValue <= endValue {
            return (startValue...endValue).contains(value)
        }
        return value >= startValue || value <= endValue
    }

    @MainActor
    private func handleTriggerSelectionTap(_ option: TriggerSelection) async {
        if option == .sunrise || option == .sunset {
            switch CLLocationManager().authorizationStatus {
            case .denied, .restricted:
                onDeviceScheduleValidationMessage = "Location permission is off. Sunrise/sunset requires location access."
                onDeviceScheduleValidationIsWarning = false
                showLocationSettingsAlert = true
                return
            case .notDetermined:
                let coordinate = await AutomationStore.shared.currentCoordinate()
                if coordinate == nil {
                    switch CLLocationManager().authorizationStatus {
                    case .denied, .restricted:
                        onDeviceScheduleValidationMessage = "Location permission is required for sunrise/sunset."
                        onDeviceScheduleValidationIsWarning = false
                        showLocationSettingsAlert = true
                    default:
                        break
                    }
                    return
                }
            default:
                break
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            triggerSelection = option
        }
    }

    private var dateWindowValidationMessage: String? {
        guard useDateWindow else { return nil }
        guard isValidCalendarDay(month: startMonth, day: startDay) else {
            return "Invalid start date for selected month."
        }
        guard isValidCalendarDay(month: endMonth, day: endDay) else {
            return "Invalid end date for selected month."
        }
        return nil
    }

    private func isValidCalendarDay(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), (1...31).contains(day) else { return false }
        let maxDayByMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= maxDayByMonth[month - 1]
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        guard canSave, !isValidatingOnDeviceSchedule else { return }
        guard let automation = buildAutomation() else { return }
        onDeviceScheduleValidationMessage = nil
        onDeviceScheduleValidationIsWarning = false
        isValidatingOnDeviceSchedule = true

        Task { @MainActor in
            let validation = await AutomationStore.shared.validateOnDeviceSchedule(for: automation)
            isValidatingOnDeviceSchedule = false

            guard validation.isValid else {
                onDeviceScheduleValidationMessage = validation.message ?? "No available on-device timer slots for this schedule."
                onDeviceScheduleValidationIsWarning = validation.isWarning
                return
            }

            guard canSave else {
                onDeviceScheduleValidationMessage = "Automation could not be saved because the selected device is busy. Please try again."
                onDeviceScheduleValidationIsWarning = false
                return
            }

            guard onSave(automation) else {
                onDeviceScheduleValidationMessage = "Automation could not be saved because the selected device is busy. Please try again."
                onDeviceScheduleValidationIsWarning = false
                return
            }
            closeEditor()
        }
    }

    private func closeEditor() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func loadPresetSlots(for key: String) async {
        guard presetSlotLoadingKey != key else { return }
        presetSlotLoadingKey = key
        defer {
            if presetSlotLoadingKey == key {
                presetSlotLoadingKey = nil
            }
        }
        for device in targetDevicesForCapacity {
            await viewModel.loadPresets(for: device)
        }
    }

    private func buildAutomation() -> Automation? {
        guard let trigger = buildTrigger() else { return nil }
        guard let action = buildAction() else { return nil }

        // Preserve existing metadata and only update action-coupled sync fields as needed.
        var metadata = editingAutomation?.metadata ?? templateMetadata ?? AutomationMetadata()
        metadata.colorPreviewHex = previewHex(for: action)
        metadata.runOnDevice = true
        if useDateWindow {
            metadata.onDeviceStartMonth = startMonth
            metadata.onDeviceStartDay = startDay
            metadata.onDeviceEndMonth = endMonth
            metadata.onDeviceEndDay = endDay
        } else {
            metadata.onDeviceStartMonth = nil
            metadata.onDeviceStartDay = nil
            metadata.onDeviceEndMonth = nil
            metadata.onDeviceEndDay = nil
        }
        let defaultTargetIds = selectedDeviceIds.isEmpty ? [activeDevice.id] : Array(selectedDeviceIds)
        let targetIds: [String]
        if case .scene(let payload) = action,
           let scene = scenes.first(where: { $0.id == payload.sceneId }) {
            targetIds = [scene.deviceId]
        } else {
            targetIds = defaultTargetIds
        }
        if let existing = editingAutomation,
           existing.action.macroAssetKind != action.macroAssetKind {
            let impactedIds = Array(Set(existing.targets.deviceIds).union(targetIds))
            metadata.clearWLEDMacroMetadata(for: impactedIds, preserveTimerSlots: true)
        }

        metadata.wledPlaylistIdsByDevice = metadata.wledPlaylistIdsByDevice?.filter { targetIds.contains($0.key) }
        metadata.wledPresetIdsByDevice = metadata.wledPresetIdsByDevice?.filter { targetIds.contains($0.key) }
        metadata.wledTimerSlotsByDevice = metadata.wledTimerSlotsByDevice?.filter { targetIds.contains($0.key) }
        metadata.wledManagedPlaylistSignatureByDevice = metadata.wledManagedPlaylistSignatureByDevice?.filter { targetIds.contains($0.key) }
        metadata.wledManagedPresetSignatureByDevice = metadata.wledManagedPresetSignatureByDevice?.filter { targetIds.contains($0.key) }

        var syncMap = metadata.wledSyncStateByDevice ?? [:]
        var errorMap = metadata.wledLastSyncErrorByDevice ?? [:]
        var syncedAtMap = metadata.wledLastSyncAtByDevice ?? [:]
        for deviceId in targetIds where syncMap[deviceId] == nil {
            syncMap[deviceId] = .unknown
        }
        syncMap = syncMap.filter { targetIds.contains($0.key) }
        errorMap = errorMap.filter { targetIds.contains($0.key) }
        syncedAtMap = syncedAtMap.filter { targetIds.contains($0.key) }
        metadata.wledSyncStateByDevice = syncMap.isEmpty ? nil : syncMap
        metadata.wledLastSyncErrorByDevice = errorMap.isEmpty ? nil : errorMap
        metadata.wledLastSyncAtByDevice = syncedAtMap.isEmpty ? nil : syncedAtMap
        metadata.normalizeWLEDScalarFallbacks(for: targetIds)
        let freshMetadata = metadata

        // Preserve the original automation's ID and timestamps when editing
        if let existing = editingAutomation {
            var updated = existing
            updated.name = automationName.trimmed()
            updated.trigger = trigger
            updated.action = action
            updated.targets = AutomationTargets(deviceIds: targetIds, syncGroupName: nil, allowPartialFailure: allowPartialFailure)
            updated.metadata = freshMetadata // Use fresh metadata for edited automations
            updated.updatedAt = Date()
            return updated
        }

        // Create new automation
        return Automation(
            name: automationName.trimmed(),
            trigger: trigger,
            action: action,
            targets: AutomationTargets(deviceIds: targetIds, syncGroupName: nil, allowPartialFailure: allowPartialFailure),
            metadata: freshMetadata // Use fresh metadata for new automations
        )
    }

    private func clearOnDeviceScheduleValidationMessage() {
        onDeviceScheduleValidationMessage = nil
        onDeviceScheduleValidationIsWarning = false
    }

    private func buildTrigger() -> AutomationTrigger? {
        let normalizedWeekdays = WeekdayMask.normalizeSunFirst(selectedWeekdays)
        guard normalizedWeekdays.contains(true) else { return nil }

        switch triggerSelection {
        case .time:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return .specificTime(
                TimeTrigger(
                    time: formatter.string(from: selectedTime),
                    weekdays: normalizedWeekdays,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            )
        case .sunrise, .sunset:
            let clampedOffset = SolarTrigger.clampOnDeviceOffset(Int(solarOffsetMinutes.rounded()))
            let offset = SolarTrigger.EventOffset.minutes(clampedOffset)
            // Always use device location for sunrise/sunset triggers
            let trigger = SolarTrigger(offset: offset, location: .followDevice, weekdays: normalizedWeekdays)
            return triggerSelection == .sunrise ? .sunrise(trigger) : .sunset(trigger)
        }
    }

    private func buildAction() -> AutomationAction? {
        // If action is locked (playlist/preset/directState), return it directly
        if let lockedAction { return lockedAction }
        switch actionSelection {
        case .color:
            let gradient = currentColorGradient()
            let duration = enableColorFade ? gradientDuration : 0
            return .gradient(
                GradientActionPayload(
                    gradient: gradient,
                    brightness: Int(gradientBrightness),
                    durationSeconds: duration,
                    temperature: gradientTemperature,
                    whiteLevel: gradientWhiteLevel,
                    shouldLoop: false,
                    presetId: selectedColorPresetId,
                    presetName: selectedColorPreset?.name,
                    powerOn: colorPowerOn
                )
            )
        case .scene:
            guard let scene = selectedScene else { return nil }
            return .scene(
                SceneActionPayload(
                    sceneId: scene.id,
                    sceneName: scene.name,
                    brightnessOverride: sceneBrightnessOverride
                )
            )
        case .transition:
            return buildTransitionAction()
        case .effect:
            return buildEffectAction()
        }
    }

    private func previewHex(for action: AutomationAction) -> String? {
        switch action {
        case .scene(let payload):
            if let scene = scenes.first(where: { $0.id == payload.sceneId }), let lastColor = scene.primaryStops.last {
                return lastColor.hexColor
            }
            return nil
        case .gradient(let payload):
            if !payload.powerOn {
                return "000000"
            }
            return payload.gradient.stops.last?.hexColor
        case .transition(let payload):
            return payload.endGradient.stops.last?.hexColor
        case .effect(let payload):
            return payload.gradient?.stops.last?.hexColor
        case .preset, .playlist, .directState:
            return nil
        }
    }

    // MARK: - Device Selection

    private var allowDeviceSelection: Bool {
        availableDevices.count > 1 && actionSelection != .scene
    }

}

// MARK: - Action Builders & Helpers

private extension AddAutomationDialog {
    var selectedColorPreset: ColorPreset? {
        guard let id = selectedColorPresetId else { return nil }
        return presetsStore.colorPreset(id: id)
    }

    var selectedTransitionPreset: TransitionPreset? {
        guard let id = selectedTransitionPresetId else { return nil }
        return presetsStore.transitionPreset(id: id)
    }

    var selectedEffectPreset: WLEDEffectPreset? {
        guard let id = selectedEffectPresetId else { return nil }
        return presetsStore.effectPreset(id: id)
    }

    func currentColorGradient() -> LEDGradient {
        let baseGradient: LEDGradient
        if let preset = selectedColorPreset {
            baseGradient = LEDGradient(stops: preset.gradientStops)
        } else if let templateGradient {
            baseGradient = templateGradient
        } else {
            baseGradient = viewModel.automationGradient(for: activeDevice)
        }

        // Ensure interpolation mode is synced from state
        var result = baseGradient
        result.interpolation = gradientInterpolation
        return result
    }

    func buildTransitionAction() -> AutomationAction? {
        // Use preset if selected, otherwise use editor values
        if let preset = selectedTransitionPreset {
            return .transition(
                TransitionActionPayload(
                    startGradient: preset.gradientA,
                    startBrightness: preset.brightnessA,
                    startTemperature: preset.temperatureA,
                    startWhiteLevel: preset.whiteLevelA,
                    endGradient: preset.gradientB,
                    endBrightness: preset.brightnessB,
                    endTemperature: preset.temperatureB,
                    endWhiteLevel: preset.whiteLevelB,
                    durationSeconds: preset.durationSec,
                    shouldLoop: false,
                    presetId: preset.id,
                    presetName: preset.name
                )
            )
        }

        // Use editor values (from AutomationTransitionEditor bindings)
        let startGrad = transitionStartGradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFFFFF")
        ])
        let endGrad = transitionEndGradient ?? LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFFFFF"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ])

        return .transition(
            TransitionActionPayload(
                startGradient: startGrad,
                startBrightness: Int(transitionStartBrightness),
                startTemperature: transitionStartTemperature,
                startWhiteLevel: transitionStartWhiteLevel,
                endGradient: endGrad,
                endBrightness: Int(transitionEndBrightness),
                endTemperature: transitionEndTemperature,
                endWhiteLevel: transitionEndWhiteLevel,
                durationSeconds: customTransitionDuration,
                shouldLoop: false,
                presetId: nil,
                presetName: nil
            )
        )
    }

    func buildEffectAction() -> AutomationAction? {
        guard let effectId = selectedEffectId ?? effectOptions.first?.id else { return nil }

        // Use preset if selected, otherwise use editor values
        if let preset = selectedEffectPreset {
            let gradient: LEDGradient?
            if let presetStops = preset.gradientStops, !presetStops.isEmpty {
                gradient = LEDGradient(
                    stops: presetStops,
                    interpolation: preset.gradientInterpolation ?? .linear
                )
            } else {
                gradient = viewModel.automationGradient(for: activeDevice)
            }
            return .effect(
                EffectActionPayload(
                    effectId: effectId,
                    effectName: preset.name,
                    gradient: gradient,
                    speed: preset.speed ?? 128,
                    intensity: preset.intensity ?? 128,
                    paletteId: preset.paletteId,
                    brightness: preset.brightness,
                    presetId: preset.id,
                    presetName: preset.name
                )
            )
        }

        // Use editor values (from AutomationEffectEditor bindings)
            let effectName = effectOptions.first(where: { $0.id == effectId })?.name
        let gradient = effectGradient ?? viewModel.automationGradient(for: activeDevice)
            return .effect(
                EffectActionPayload(
                    effectId: effectId,
                    effectName: effectName,
                    gradient: gradient,
                speed: effectSpeed,
                intensity: effectIntensity,
                paletteId: nil,
                brightness: Int(effectBrightness),
                presetId: nil,
                presetName: nil
            )
        )
    }

}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Focus State Helper
extension AddAutomationDialog {
    func handleNameEditToggle() {
        if isEditingName {
            commitNameEdit()
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isEditingName = true
            }
        }
    }

    func commitNameEdit() {
        let trimmed = automationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            automationName = editingAutomation?.name ?? defaultName ?? "Automation"
        } else {
            automationName = trimmed
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isNameFieldFocused = false
            isEditingName = false
        }
    }
}
