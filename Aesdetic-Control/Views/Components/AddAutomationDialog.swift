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
    }
    
    @Environment(\.dismiss) var dismiss
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
    var onSave: (Automation) -> Void
    
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
    @State private var showLocationSettingsAlert: Bool = false
    
    @State private var actionSelection: ActionSelection = .color
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
    
    private struct TemplateEffectSettings {
        let gradient: LEDGradient?
        let speed: Int
        let intensity: Int
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
        onSave: @escaping (Automation) -> Void
    ) {
        self.device = device
        self.scenes = scenes
        self.effectOptions = effectOptions
        self.availableDevices = availableDevices.isEmpty ? [device] : availableDevices
        self.viewModel = viewModel
        self.defaultName = defaultName
        self.editingAutomation = editingAutomation
        self.allowSceneAction = allowSceneAction
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
        NavigationStack {
            dialogContent
        }
    }

    private var dialogContent: some View {
        ZStack {
            modalBackground
            contentScrollView
        }
        .background(Color.clear)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .presentationBackground(.ultraThinMaterial)
        .toolbar { dialogToolbar }
        .task {
            await loadPresetSlots()
        }
        .task(id: transitionSchedulePreviewInputsKey) {
            await refreshTransitionSchedulePreview()
        }
        .onChange(of: selectedDeviceIds) { _, _ in
            clearOnDeviceScheduleValidationMessage()
            normalizeTriggerSelectionIfNeeded()
            Task { await loadPresetSlots() }
        }
        .onChange(of: activeDevice.id) { _, _ in
            clearOnDeviceScheduleValidationMessage()
            normalizeTriggerSelectionIfNeeded()
            Task { await loadPresetSlots() }
        }
        .onChange(of: validationInputsKey) { _, _ in
            clearOnDeviceScheduleValidationMessage()
        }
        .onChange(of: actionSelection) { _, selection in
            if selection == .scene {
                normalizeSceneSelectionIfNeeded()
            }
            clearOnDeviceScheduleValidationMessage()
            Task { await loadPresetSlots() }
        }
        .onChange(of: selectedSceneId) { _, _ in
            normalizeSceneSelectionIfNeeded()
            clearOnDeviceScheduleValidationMessage()
            Task { await loadPresetSlots() }
        }
        .onChange(of: allowPartialFailure) { _, _ in
            Task { await loadPresetSlots() }
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

    @ToolbarContentBuilder
    private var dialogToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                if isEditingName {
                    TextField("Automation name", text: $automationName)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            isEditingName = false
                            isNameFieldFocused = false
                        }
                        .frame(minWidth: 200)
                } else {
                    Text(automationName.isEmpty ? (isEditing ? "Edit Automation" : "Add Automation") : automationName)
                        .font(AppTypography.style(.headline, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Button {
                    handleNameEditToggle()
                } label: {
                    Image(systemName: isEditingName ? "checkmark" : "pencil")
                        .foregroundColor(.white.opacity(0.7))
                        .font(AppTypography.style(.subheadline, weight: .medium))
                }
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundColor(.white)
        }
    }

    private var contentScrollView: some View {
        ScrollView {
            VStack(spacing: 20) {
                automationDetailsSection
                automationSettingsSection
                repeatScheduleSection
                automationActionSection
                deviceSyncSection
                saveSection
            }
            .padding(20)
            .background(Color.clear)
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

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: saveAndDismiss) {
                Text(isValidatingOnDeviceSchedule ? "Validating..." : primaryButtonTitle)
                    .font(AppTypography.style(.headline))
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background((canSave && !isValidatingOnDeviceSchedule) ? Color.white : Color.white.opacity(0.2))
                    .foregroundColor((canSave && !isValidatingOnDeviceSchedule) ? .black : .white.opacity(0.6))
                    .cornerRadius(16)
            }
            .disabled(!canSave || isValidatingOnDeviceSchedule)

            if let message = onDeviceScheduleValidationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(onDeviceScheduleValidationIsWarning ? .yellow : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = timerSlotLimitPromptMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = dateWindowValidationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = presetCapacityMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(presetCapacitySatisfied ? .white.opacity(0.7) : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = transitionDurationRecommendationMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = sameDayScheduleWarningMessage {
                Text(message)
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if automationStore.hasAnyDeletionInProgress && !isEditing {
                Text("Please wait for automation deletion to finish before creating a new automation.")
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if automationStore.hasAnyOnDeviceSyncInProgress && !isEditing {
                Text("Please wait for the current automation to finish getting ready before creating another on-device automation.")
                    .font(AppTypography.style(.footnote))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var modalBackground: some View {
        LiquidGlassOverlay(
            blurOpacity: 0.65,
            highlightOpacity: 0.18,
            verticalTopOpacity: 0.08,
            verticalBottomOpacity: 0.08,
            vignetteOpacity: 0.12,
            centerSheenOpacity: 0.06
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.01),
                            Color.black.opacity(0.01),
                            Color.white.opacity(0.015),
                            Color.black.opacity(0.005)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Sections
    
    private var automationDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Device selection moved to bottom of dialog
        }
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
    
    // MARK: - Trigger Settings Section
    
    private var automationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Automation Settings")
                .font(AppTypography.style(.callout, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            triggerSelectionCard
            solarParityHint
            if advancedUIEnabled {
                dateWindowSection
            }
        }
    }
    
    private var triggerSelectionCard: some View {
        GeometryReader { geometry in
            triggerSelectionContent(geometry: geometry)
        }
        .frame(height: 240)
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
        let weekdaySpacing: CGFloat = 5
        let weekdayCornerRadius: CGFloat = 10
        let allDaysSelected = selectedWeekdays.allSatisfy { $0 }
        
        return VStack(alignment: .leading, spacing: 8) {
            // Title row with "Every day" toggle
            HStack {
            Text("Repeat Schedule")
                    .font(AppTypography.style(.footnote, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
                Spacer()
                
                // "Every day" toggle chip
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let newValue = !allDaysSelected
                        selectedWeekdays = Array(repeating: newValue, count: 7)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: allDaysSelected ? "checkmark.circle.fill" : "circle")
                            .font(AppTypography.style(.caption2))
                        Text("Every day")
                            .font(AppTypography.style(.caption, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(height: 28)
                    .background(tabButtonBackground(isActive: allDaysSelected))
                    .clipShape(RoundedRectangle(cornerRadius: weekdayCornerRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(allDaysSelected ? 0.15 : 0.08), radius: allDaysSelected ? 6 : 3, x: 0, y: allDaysSelected ? 3 : 2)
                }
                .contentShape(RoundedRectangle(cornerRadius: weekdayCornerRadius, style: .continuous))
                .buttonStyle(.plain)
            }
            
            // Horizontal bar
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            
            // Weekday buttons with swipe-to-select
            GeometryReader { geo in
                HStack(spacing: weekdaySpacing) {
                    ForEach(weekdayNames.indices, id: \.self) { idx in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedWeekdays[idx].toggle()
                            }
                        }) {
                            Text(weekdayNames[idx].uppercased())
                                .font(AppTypography.style(.caption2, weight: .semibold))
                                .tracking(0.3)
                                .foregroundColor(selectedWeekdays[idx] ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(weekdayButtonBackground(isSelected: selectedWeekdays[idx], cornerRadius: weekdayCornerRadius))
                                .clipShape(RoundedRectangle(cornerRadius: weekdayCornerRadius, style: .continuous))
                                .shadow(color: Color.black.opacity(selectedWeekdays[idx] ? 0.15 : 0.08), radius: selectedWeekdays[idx] ? 6 : 3, x: 0, y: selectedWeekdays[idx] ? 3 : 2)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: weekdayCornerRadius, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
                .overlay(
                    // Swipe-to-select gesture overlay
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let width = geo.size.width
                                    let totalSpacing = weekdaySpacing * 6  // 6 gaps between 7 chips
                                    let chipWidth = (width - totalSpacing) / 7
                                    // Calculate index: each chip occupies chipWidth + spacing (except last)
                                    let slotWidth = chipWidth + weekdaySpacing
                                    let idx = min(max(Int(value.location.x / slotWidth), 0), 6)
                                    
                                    // On first call, detect swipe mode based on starting day
                                    if draggingSelects == nil && idx < selectedWeekdays.count {
                                        draggingSelects = !selectedWeekdays[idx]
                                    }
                                    
                                    // Apply swipe mode to current day
                                    if let mode = draggingSelects, idx < selectedWeekdays.count {
                                        if selectedWeekdays[idx] != mode {
                                            withAnimation(.easeInOut(duration: 0.1)) {
                                                selectedWeekdays[idx] = mode
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    // Clear swipe mode when drag ends
                                    draggingSelects = nil
                                }
                        )
                )
            }
            .frame(height: 34)
            .padding(.bottom, weekdaySpacing)
        }
    }
    
    // MARK: - Weekday Button Background Helper
    
    @ViewBuilder
    private func weekdayButtonBackground(isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        if isSelected {
            // Selected: White pill with soft gradient
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
    
    @ViewBuilder
    private func triggerSelectionContent(geometry: GeometryProxy) -> some View {
        let tabHeight: CGFloat = 46
        let cardHeight: CGFloat = 200
        let cornerRadius: CGFloat = 16
        let totalHeight = tabHeight + 12 + cardHeight  // Include spacing
        
        let gradientStops: [Gradient.Stop] = {
            if triggerSelection == .time {
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
            // Tab row aligned with card edges
            HStack(spacing: 8) {
                // Explicit order: Sunrise | Sunset | Time of Day
                ForEach([TriggerSelection.sunrise, .sunset, .time], id: \.self) { option in
                    let isActive = triggerSelection == option
                    let isTimeOfDay = option == .time
                    let isAvailable = isTriggerOptionAvailable(option)
                    
                    Button {
                        guard isAvailable else { return }
                        Task { await handleTriggerSelectionTap(option) }
                    } label: {
                        Text(option == .time ? "Time of Day" : option.rawValue)
                            .font(AppTypography.style(.footnote, weight: .semibold))
                            .foregroundColor(.white.opacity(isAvailable ? 0.9 : 0.45))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .padding(.horizontal, 12)
                            .background(tabButtonBackground(isActive: isActive))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color.black.opacity(isActive ? 0.15 : 0.08), radius: isActive ? 6 : 3, x: 0, y: isActive ? 3 : 2)
                            .opacity(isAvailable ? 1.0 : 0.7)
                    }
                    .frame(minWidth: isTimeOfDay ? 120 : 90, maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(!isAvailable)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .padding(.bottom, 10)  // Reduced gap: 12 - 2 = 10
            
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
                ZStack {
                    if triggerSelection == .time {
                        timeTriggerContent(cardHeight: cardHeight)
                            .padding(.horizontal, 6)
                    } else {
                        SolarOffsetArcSlider(
                            offsetMinutes: $solarOffsetMinutes,
                            eventType: selectedSolarEvent,
                            device: activeDevice,
                            disableClipping: true,
                            useExternalGradient: true
                        )
                        .padding(.horizontal, 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(height: cardHeight)
        }
        .frame(height: totalHeight)
    }
    
    // MARK: - Card Chrome Helper
    
    private func cardChrome(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
    
    // MARK: - Tab Button Background Helper
    
    private func tabButtonBackground(isActive: Bool) -> some View {
                            ZStack {
                                if isActive {
                                    // Active: Ultra-transparent to show gradient through
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial.opacity(0.25))
                                        .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.2),
                                                            Color.white.opacity(0.05)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                        .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.5),
                                                            Color.white.opacity(0.2)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                        )
                                } else {
                // Inactive: Lightened fill/stroke for subtle chrome, text remains at 0.9 opacity
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial.opacity(0.5))
                                        .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                                        )
                                        .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
            }
        }
    }
    
    private func timeTriggerContent(cardHeight: CGFloat) -> some View {
        // Wheel pickers are ~216pt tall; scale & clamp to match the solar card
        let pickerHeight: CGFloat = 216
        
        return DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
            .background(Color.clear)  // Remove default background
            .scaleEffect(y: cardHeight / pickerHeight, anchor: .center)
            .frame(height: cardHeight)  // Enforce final height
            .clipped()
    }
    
    // MARK: - Action Section
    
    private var automationActionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Action")
                .font(AppTypography.style(.callout, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Picker("Action", selection: $actionSelection) {
                ForEach(availableActionSelections) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(lockedAction != nil)
            
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
            selectedEffectPresetId: $selectedEffectPresetId
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
            showFadeControls: advancedUIEnabled
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
            transitionProfile: transitionProfileForActiveDevice,
            automationGuaranteeCount: 5,
            expectedStartDate: transitionSchedulePreviewStart,
            expectedEndDate: transitionSchedulePreviewEnd,
            expectedTimeZone: transitionSchedulePreviewTimeZone
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
        if automationStore.hasAnyDeletionInProgress && !isEditing {
            return false
        }
        if automationStore.hasAnyOnDeviceSyncInProgress && !isEditing {
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
                device: target,
                automationGuaranteeCount: 5
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

    private var transitionBudgetSatisfied: Bool {
        guard transitionPlanningInput != nil else { return true }
        return !transitionProfilesByDevice.isEmpty
            && transitionProfilesByDevice.allSatisfy { $0.profile.fitsBudget }
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

    private var presetCapacityContext: (device: WLEDDevice, status: DeviceControlViewModel.PresetSlotAvailability)? {
        let candidates = targetDevicesForCapacity.compactMap { device -> (WLEDDevice, DeviceControlViewModel.PresetSlotAvailability)? in
            guard let status = viewModel.presetSlotAvailability(for: device) else { return nil }
            return (device, status)
        }
        return candidates.min { $0.1.available < $1.1.available }
    }

    private var presetCapacitySatisfied: Bool {
        guard requiredPresetSlots > 0 else { return true }
        if transitionPlanningInput != nil {
            return transitionBudgetSatisfied
        }
        return targetDevicesForCapacity.allSatisfy { device in
            guard let status = viewModel.presetSlotAvailability(for: device) else { return false }
            return status.available >= requiredPresetSlots
        }
    }

    private var transitionBudgetContext: (device: WLEDDevice, profile: TransitionStepProfile)? {
        transitionProfilesByDevice.min { lhs, rhs in
            let leftMargin = (lhs.profile.perAutomationBudget ?? Int.max) - lhs.profile.slotsRequired
            let rightMargin = (rhs.profile.perAutomationBudget ?? Int.max) - rhs.profile.slotsRequired
            return leftMargin < rightMargin
        }
    }

    private var presetCapacityMessage: String? {
        guard requiredPresetSlots > 0 else { return nil }
        if let context = transitionBudgetContext {
            let profile = context.profile
            let quality = profile.qualityLabel.displayName
            let budget = profile.perAutomationBudget ?? 0
            if !profile.fitsBudget {
                let maxDuration = TransitionDurationPicker.clockString(seconds: profile.maxDurationSecondsAtCurrentQuality ?? 0)
                return "Transition needs \(profile.slotsRequired) slots on \(context.device.name), but \(budget) are budgeted per automation (5-automation guarantee). Max at current quality is about \(maxDuration)."
            }
            let adjusted = profile.wasCoarsened
                ? " Adjusted from \(Int(profile.baseLegSeconds))s to \(Int(profile.legSeconds))s legs for budget fit."
                : ""
            return "Transition estimate on \(context.device.name): \(profile.slotsRequired) slots at \(quality) quality (\(Int(profile.legSeconds))s legs). Budget: \(budget) slots/automation.\(adjusted)"
        }
        guard let context = presetCapacityContext else {
            return "Checking preset storage..."
        }
        let status = context.status
        if status.available < requiredPresetSlots {
            return "Not enough preset slots on \(context.device.name). \(status.remaining) remaining (\(status.reserve) reserved), need \(requiredPresetSlots)."
        }
        return "Preset slots on \(context.device.name): \(status.remaining) remaining (\(status.reserve) reserved). This automation needs \(requiredPresetSlots)."
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
        if isTriggerOptionAvailable(.time) {
            triggerSelection = .time
            return
        }
        if isTriggerOptionAvailable(.sunrise) {
            triggerSelection = .sunrise
            return
        }
        if isTriggerOptionAvailable(.sunset) {
            triggerSelection = .sunset
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

    private var sameDayScheduleWarningMessage: String? {
        guard triggerSelection == .time else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let todayWeekdayIndex = calendar.component(.weekday, from: now) - 1
        guard selectedWeekdays.indices.contains(todayWeekdayIndex),
              selectedWeekdays[todayWeekdayIndex] else {
            return nil
        }
        guard isWithinDateWindow(now, calendar: calendar) else { return nil }

        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        guard let hour = timeComponents.hour, let minute = timeComponents.minute else {
            return nil
        }
        var todayStartComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayStartComponents.hour = hour
        todayStartComponents.minute = minute
        todayStartComponents.second = 0
        guard let todayStart = calendar.date(from: todayStartComponents),
              todayStart <= now else {
            return nil
        }

        if actionSelection == .transition {
            let todayEnd = todayStart.addingTimeInterval(max(0, customTransitionDuration))
            if now < todayEnd {
                return "Today's automation window is already in progress. WLED timers cannot start midway, so the on-device schedule will run at the next selected start unless you run it manually now."
            }
        }

        return "Today's start time has already passed. The on-device schedule will first run on the next selected day."
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

            onSave(automation)
            dismiss()
        }
    }

    private func loadPresetSlots() async {
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
            // Save changes when toggling off
            let trimmed = automationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Restore previous name if empty
                automationName = editingAutomation?.name ?? defaultName ?? "Automation"
            } else {
                automationName = trimmed
            }
            isEditingName = false
            isNameFieldFocused = false
        } else {
            isEditingName = true
            isNameFieldFocused = true
        }
    }
}
