import SwiftUI

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
        
        var id: String { rawValue }
    }
    
    enum ColorActionMode: String, CaseIterable, Identifiable {
        case scenes = "Scenes"
        case gradient = "Create New"
        
        var id: String { rawValue }
    }
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var presetsStore = PresetsStore.shared
    let device: WLEDDevice
    let scenes: [Scene]
    let effectOptions: [EffectMetadata]
    let availableDevices: [WLEDDevice]
    @ObservedObject var viewModel: DeviceControlViewModel
    let defaultName: String?
    let editingAutomation: Automation?
    var onSave: (Automation) -> Void
    
    @State private var automationName: String
    @State private var selectedDeviceIds: Set<String>
    @State private var activeDevice: WLEDDevice
    @State private var triggerSelection: TriggerSelection = .time
    @State private var selectedTime: Date = Date()
    @State private var selectedWeekdays: [Bool] = Array(repeating: false, count: 7)
    @State private var solarOffsetMinutes: Double = 0
    
    @State private var actionSelection: ActionSelection = .color
    @State private var selectedSceneId: UUID?
    @State private var selectedEffectId: Int?
    @State private var effectBrightness: Double
    @State private var gradientBrightness: Double
    @State private var gradientDuration: Double = 10
    @State private var selectedColorPresetId: UUID?
    @State private var selectedTransitionPresetId: UUID?
    @State private var selectedEffectPresetId: UUID?
    @State private var enableColorFade: Bool = false
    @State private var customTransitionDuration: Double = 600
    @State private var allowPartialFailure: Bool = true
    @State private var templateGradient: LEDGradient?
    @State private var templateTransition: TransitionActionPayload?
    @State private var templateEffectSettings: TemplateEffectSettings?
    @State private var templateMetadata: AutomationMetadata?
    @State private var colorActionMode: ColorActionMode
    @State private var isEditingName: Bool = false
    @FocusState private var isNameFieldFocused: Bool
    
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
        onSave: @escaping (Automation) -> Void
    ) {
        self.device = device
        self.scenes = scenes
        self.effectOptions = effectOptions
        self.availableDevices = availableDevices.isEmpty ? [device] : availableDevices
        self.viewModel = viewModel
        self.defaultName = defaultName
        self.editingAutomation = editingAutomation
        self.onSave = onSave
        
        var initialActiveDevice = self.availableDevices.first(where: { $0.id == device.id }) ?? self.availableDevices.first ?? device
        
        var initialName = defaultName ?? "\(device.name) Automation"
        var initialDeviceIds = Set([initialActiveDevice.id])
        var initialTriggerSelection: TriggerSelection = .time
        var initialTime = Date()
        var initialWeekdays = Array(repeating: false, count: 7)
        var initialSolarOffset: Double = 0
        var initialActionSelection: ActionSelection = .color
        var initialColorMode: ColorActionMode = scenes.isEmpty ? .gradient : .scenes
        var initialSceneId: UUID? = scenes.first?.id
        var initialEffectId: Int? = effectOptions.first?.id
        var initialEffectBrightness = Double(device.brightness)
        var initialGradientBrightness = Double(device.brightness)
        var initialGradientDuration: Double = 10
        var initialEnableColorFade = false
        var initialTransitionDuration: Double = 600
        var initialTemplateGradient: LEDGradient?
        var initialTemplateTransition: TransitionActionPayload?
        var initialTemplateEffect: TemplateEffectSettings?
        var initialMetadata: AutomationMetadata?
        var initialAllowPartial = true
        
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
                initialSolarOffset = Self.minutes(from: solar.offset)
            case .sunset(let solar):
                initialTriggerSelection = .sunset
                initialSolarOffset = Self.minutes(from: solar.offset)
            }
            switch editing.action {
            case .scene(let payload):
                initialActionSelection = .color
                initialColorMode = .scenes
                initialSceneId = payload.sceneId
            case .gradient(let payload):
                initialActionSelection = .color
                initialColorMode = .gradient
                initialTemplateGradient = payload.gradient
                initialGradientBrightness = Double(payload.brightness)
                initialEnableColorFade = payload.durationSeconds > 0
                initialGradientDuration = max(10, payload.durationSeconds)
            case .transition(let payload):
                initialActionSelection = .transition
                initialTemplateTransition = payload
                initialGradientBrightness = Double(payload.endBrightness)
                initialTransitionDuration = payload.durationSeconds
            case .effect(let payload):
                initialActionSelection = .effect
                initialEffectId = payload.effectId
                initialEffectBrightness = Double(payload.brightness)
                initialTemplateGradient = payload.gradient
                initialTemplateEffect = TemplateEffectSettings(gradient: payload.gradient, speed: payload.speed, intensity: payload.intensity)
            case .preset, .directState:
                initialActionSelection = .color
                initialColorMode = .gradient
            }
            initialMetadata = editing.metadata
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
                initialSolarOffset = Double(offset)
            case .sunset(let offset):
                initialTriggerSelection = .sunset
                initialSolarOffset = Double(offset)
            }
            
            switch prefill.action {
            case .gradient(let gradient, let brightness, let fadeDuration):
                initialActionSelection = .color
                initialColorMode = .gradient
                initialTemplateGradient = gradient
                initialGradientBrightness = Double(brightness)
                initialEnableColorFade = fadeDuration > 0
                initialGradientDuration = max(10, fadeDuration)
            case .transition(let payload, let durationSeconds, let endBrightness):
                initialActionSelection = .transition
                initialTemplateTransition = payload
                if let durationSeconds {
                    initialTransitionDuration = max(60, durationSeconds)
                }
                if let endBrightness {
                    initialGradientBrightness = Double(endBrightness)
                }
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
        _selectedSceneId = State(initialValue: initialSceneId)
        _selectedEffectId = State(initialValue: initialEffectId)
        _effectBrightness = State(initialValue: initialEffectBrightness)
        _gradientBrightness = State(initialValue: initialGradientBrightness)
        _selectedDeviceIds = State(initialValue: initialDeviceIds)
        _activeDevice = State(initialValue: initialActiveDevice)
        _selectedColorPresetId = State(initialValue: nil)
        _selectedTransitionPresetId = State(initialValue: nil)
        _selectedEffectPresetId = State(initialValue: nil)
        _customTransitionDuration = State(initialValue: initialTransitionDuration)
        _allowPartialFailure = State(initialValue: initialAllowPartial)
        _triggerSelection = State(initialValue: initialTriggerSelection)
        _selectedTime = State(initialValue: initialTime)
        _selectedWeekdays = State(initialValue: initialWeekdays)
        _solarOffsetMinutes = State(initialValue: initialSolarOffset)
        _actionSelection = State(initialValue: initialActionSelection)
        _enableColorFade = State(initialValue: initialEnableColorFade)
        _gradientDuration = State(initialValue: initialGradientDuration)
        _templateGradient = State(initialValue: initialTemplateGradient)
        _templateTransition = State(initialValue: initialTemplateTransition)
        _templateEffectSettings = State(initialValue: initialTemplateEffect)
        _templateMetadata = State(initialValue: initialMetadata)
        _colorActionMode = State(initialValue: initialColorMode)
    }
    
    private var weekdayNames: [String] { ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"] }
    private var primaryButtonTitle: String { isEditing ? "Save Changes" : "Save Automation" }
    
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
            ScrollView {
                VStack(spacing: 20) {
                    automationDetailsSection
                    automationSettingsSection
                    repeatScheduleSection
                    automationActionSection
                    
                    Button(action: saveAndDismiss) {
                        Text(primaryButtonTitle)
                            .font(.headline)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(canSave ? Color.white : Color.white.opacity(0.2))
                            .foregroundColor(canSave ? .black : .white.opacity(0.6))
                            .cornerRadius(16)
                    }
                    .disabled(!canSave)
                }
                .padding(20)
                .background(Color.black.opacity(0.95))
            }
            .background(Color.black.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        if isEditingName {
                            TextField("Automation name", text: $automationName)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .font(.headline.weight(.semibold))
                                .focused($isNameFieldFocused)
                                .onSubmit {
                                    isEditingName = false
                                    isNameFieldFocused = false
                                }
                                .frame(minWidth: 200)
                        } else {
                            Text(automationName.isEmpty ? (isEditing ? "Edit Automation" : "Add Automation") : automationName)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        
                        Button {
                            handleNameEditToggle()
                        } label: {
                            Image(systemName: isEditingName ? "checkmark" : "pencil")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Sections
    
    private var automationDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allowDeviceSelection {
                deviceSelectionSection
                
                Toggle(isOn: $allowPartialFailure) {
                    Text("Allow partial run if a device is offline")
                        .foregroundColor(.white.opacity(0.85))
                }
                .toggleStyle(SwitchToggleStyle(tint: .white))
            }
        }
    }
    
    // MARK: - Trigger Settings Section
    
    private var automationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Automation Settings")
                .font(.callout.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
            
            triggerSelectionCard
        }
    }
    
    private var triggerSelectionCard: some View {
        GeometryReader { geometry in
            triggerSelectionContent(geometry: geometry)
        }
        .frame(height: 240)
    }
    
    // MARK: - Repeat Schedule Section
    
    private var repeatScheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repeat Schedule")
                .font(.callout.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
            
            HStack(spacing: 8) {
                ForEach(weekdayNames.indices, id: \.self) { idx in
                    Button(action: { selectedWeekdays[idx].toggle() }) {
                        Text(weekdayNames[idx])
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selectedWeekdays[idx] ? Color.white : Color.white.opacity(0.15))
                            )
                            .foregroundColor(selectedWeekdays[idx] ? .black : .white.opacity(0.8))
                    }
                }
            }
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
            let range: ClosedRange<Double> = -120...120
            let normalized = max(0, min(1, (solarOffsetMinutes - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let scrollableHeight = gradientHeight - cardHeight
            return normalized * scrollableHeight
        }()
        
        let gradient = LinearGradient(
            gradient: Gradient(stops: gradientStops),
            startPoint: .top,
            endPoint: .bottom
        )
        
        VStack(spacing: 12) {
            // Tab row with neutral background
            HStack(spacing: 8) {
                ForEach(TriggerSelection.allCases) { option in
                    let isActive = triggerSelection == option
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            triggerSelection = option
                        }
                    } label: {
                        Text(option == .time ? "Time of Day" : option.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .background(
                        ZStack {
                            // Liquid glass effect
                            if isActive {
                                // Active: Ultra-transparent neutral background
                                Capsule()
                                    .fill(.ultraThinMaterial.opacity(0.25))
                                    .overlay(
                                        Capsule()
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
                                        Capsule()
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
                                // Inactive: More opaque frosted glass
                                Capsule()
                                    .fill(.ultraThinMaterial.opacity(0.5))
                                    .overlay(
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        }
                    )
                    .shadow(color: Color.black.opacity(isActive ? 0.15 : 0.08), radius: isActive ? 6 : 3, x: 0, y: isActive ? 3 : 2)
                    .buttonStyle(.plain)
                }
            }
            
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
                
                // Glass layer on top of gradient
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // Content layer
                if triggerSelection == .time {
                    timeTriggerContent
                        .padding(.horizontal, 20)
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
            .frame(height: cardHeight)
        }
        .frame(height: totalHeight)
    }
    
    private var timeTriggerContent: some View {
        DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
    }
    
    // MARK: - Action Section
    
    private var automationActionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colors")
                .font(.callout.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Picker("Action", selection: $actionSelection) {
                ForEach(ActionSelection.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            
            switch actionSelection {
            case .color:
                colorActionControls
            case .transition:
                transitionActionControls
            case .effect:
                effectActionControls
            }
        }
    }
    
    private var effectActionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            let presets = presetsStore.effectPresets(for: activeDevice.id)
            if !presets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Effect presets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presets) { preset in
                                Button {
                                    selectedEffectPresetId = preset.id
                                    selectedEffectId = preset.effectId
                                    effectBrightness = Double(preset.brightness)
                                    templateEffectSettings = nil
                                    templateGradient = nil
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white)
                                        Text("Effect \(preset.effectId)")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(10)
                                    .frame(width: 140, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selectedEffectPresetId == preset.id ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            if effectOptions.isEmpty {
                Text("No gradient-friendly animations available for this device.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Picker("Animation", selection: Binding(
                    get: { selectedEffectId ?? effectOptions.first!.id },
                    set: {
                        selectedEffectId = $0
                        selectedEffectPresetId = nil
                        templateEffectSettings = nil
                        templateGradient = nil
                    }
                )) {
                    ForEach(effectOptions, id: \.id) { effect in
                        Text(effect.name).tag(effect.id)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .colorMultiply(.white)
                
                VStack(alignment: .leading) {
                    Text("Brightness \(Int(effectBrightness))%")
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: $effectBrightness, in: 1...255, step: 1)
                        .tint(.white)
                }
            }
        }
    }
    
    private var colorActionControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Color Mode", selection: $colorActionMode) {
                ForEach(ColorActionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
            if colorActionMode == .scenes {
                sceneSelectionControls
            } else {
                gradientCreationControls
            }
        }
        .onChange(of: colorActionMode) { _, mode in
            if mode == .scenes {
                selectedColorPresetId = nil
                templateGradient = nil
            } else {
                selectedSceneId = nil
                if templateGradient == nil {
                    templateGradient = viewModel.automationGradient(for: activeDevice)
                }
            }
        }
    }
    
    private var sceneSelectionControls: some View {
        Group {
            if scenes.isEmpty {
                Text("Save a scene from the Colors tab to reuse it here.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(scenes) { scene in
                            let isSelected = selectedSceneId == scene.id
                            Button {
                                selectedSceneId = scene.id
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(scene.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(isSelected ? .black : .white)
                                    Text("\(scene.primaryStops.count) colors")
                                        .font(.caption)
                                        .foregroundColor(isSelected ? .black.opacity(0.7) : .white.opacity(0.7))
                                }
                                .padding(12)
                                .frame(width: 150, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isSelected ? Color.white : Color.white.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private var gradientCreationControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            gradientEditorSection
            
            gradientPresetButtons
            
            Button {
                setTemplateGradient(viewModel.automationGradient(for: activeDevice))
            } label: {
                Label("Use current colors", systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Brightness")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(gradientBrightness))%")
                        .foregroundColor(.white)
                }
                
                Slider(value: $gradientBrightness, in: 1...255, step: 1)
                    .tint(.white)
            }
            
            Toggle(isOn: $enableColorFade.animation()) {
                Text("Fade over time")
                    .foregroundColor(.white.opacity(0.9))
            }
            .toggleStyle(SwitchToggleStyle(tint: .white))
            
            if enableColorFade {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Fade duration")
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(gradientDuration)) sec")
                            .foregroundColor(.white)
                    }
                    Slider(value: $gradientDuration, in: 5...300, step: 5)
                        .tint(.white)
                }
            }
        }
    }
    
    private var gradientEditorSection: some View {
        let gradient = editingGradient
        return VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: gradient.stops.map { Color(hex: $0.hexColor) }),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            ForEach(gradient.stops) { stop in
                gradientStopEditorRow(stop: stop, totalCount: gradient.stops.count)
            }
            
        Button(action: addGradientStop) {
                Label("Add Color", systemImage: "plus.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var gradientPresetButtons: some View {
        Group {
            if presetsStore.colorPresets.isEmpty {
                Text("Capture your current gradient or save a preset to reuse it here.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.75))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presetsStore.colorPresets) { preset in
                                let isSelected = selectedColorPresetId == preset.id
                                Button {
                                    let gradient = LEDGradient(stops: preset.gradientStops)
                                    setTemplateGradient(gradient, presetId: preset.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        LinearGradient(
                                            gradient: Gradient(colors: preset.gradientStops.map { Color(hex: $0.hexColor) }),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        
                                        Text(preset.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white)
                                    }
                                    .padding(10)
                                    .frame(width: 135, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private func gradientStopEditorRow(stop: GradientStop, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stop \(stopLabel(for: stop))")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                if totalCount > 1 {
                    Button(role: .destructive) {
                        removeGradientStop(stop.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            ColorPicker("Color", selection: colorBinding(for: stop), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Text("Position")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.0f%%", stop.position * 100))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Slider(value: positionBinding(for: stop), in: 0...1)
                .tint(.white)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
    
    private var transitionActionControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            let presets = presetsStore.transitionPresets(for: activeDevice.id)
            if presets.isEmpty {
                Text("Create a transition preset from the Transitions tab to enable sunrise/sunset routines.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick a transition")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                    ForEach(presets) { preset in
                        Button {
                            selectedTransitionPresetId = preset.id
                            templateTransition = nil
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("\(Int(preset.durationSec)) sec · \(Int(preset.brightnessA))% → \(Int(preset.brightnessB))%")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                if selectedTransitionPresetId == preset.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selectedTransitionPresetId == preset.id ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button {
                selectedTransitionPresetId = nil
                templateTransition = nil
            } label: {
                Label("Use quick sunrise", systemImage: "sunrise.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            if selectedTransitionPresetId == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration \(Int(customTransitionDuration / 60)) min")
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: $customTransitionDuration, in: 120...2400, step: 60)
                        .tint(.white)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Final brightness \(Int(gradientBrightness))%")
                        .foregroundColor(.white.opacity(0.8))
                    Slider(value: $gradientBrightness, in: 1...255, step: 1)
                        .tint(.white)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSave: Bool {
        guard !automationName.trimmed().isEmpty else { return false }
        guard !selectedDeviceIds.isEmpty else { return false }
        if triggerSelection == .time && !selectedWeekdays.contains(true) {
            return false
        }
        if actionSelection == .color && colorActionMode == .scenes {
            return selectedSceneId != nil
        }
        if actionSelection == .effect {
            return selectedEffectId != nil
        }
        return true
    }
    
    private var selectedSolarEvent: SolarEvent {
        triggerSelection == .sunrise ? .sunrise : .sunset
    }
    
    // MARK: - Actions
    
    private func saveAndDismiss() {
        guard canSave else { return }
        guard let automation = buildAutomation() else { return }
        onSave(automation)
        dismiss()
    }
    
    private func buildAutomation() -> Automation? {
        guard let trigger = buildTrigger() else { return nil }
        guard let action = buildAction() else { return nil }
        let metadata = templateMetadata ?? AutomationMetadata(colorPreviewHex: previewHex(for: action))
        let targetIds = selectedDeviceIds.isEmpty ? [activeDevice.id] : Array(selectedDeviceIds)
        
        // Preserve the original automation's ID and timestamps when editing
        if let existing = editingAutomation {
            var updated = existing
            updated.name = automationName.trimmed()
            updated.trigger = trigger
            updated.action = action
            updated.targets = AutomationTargets(deviceIds: targetIds, syncGroupName: nil, allowPartialFailure: allowPartialFailure)
            updated.metadata = metadata
            updated.updatedAt = Date()
            return updated
        }
        
        // Create new automation
        return Automation(
            name: automationName.trimmed(),
            trigger: trigger,
            action: action,
            targets: AutomationTargets(deviceIds: targetIds, syncGroupName: nil, allowPartialFailure: allowPartialFailure),
            metadata: metadata
        )
    }
    
    private func buildTrigger() -> AutomationTrigger? {
        switch triggerSelection {
        case .time:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return .specificTime(
                TimeTrigger(
                    time: formatter.string(from: selectedTime),
                    weekdays: selectedWeekdays,
                    timezoneIdentifier: TimeZone.current.identifier
                )
            )
        case .sunrise, .sunset:
            let offset = SolarTrigger.EventOffset.minutes(Int(solarOffsetMinutes))
            // Always use device location for sunrise/sunset triggers
            let trigger = SolarTrigger(offset: offset, location: .followDevice)
            return triggerSelection == .sunrise ? .sunrise(trigger) : .sunset(trigger)
        }
    }
    
    private func buildAction() -> AutomationAction? {
        switch actionSelection {
        case .color:
            if colorActionMode == .scenes {
                guard let sceneId = selectedSceneId ?? scenes.first?.id else { return nil }
                let sceneName = scenes.first(where: { $0.id == sceneId })?.name
                    ?? "Scene"
                return .scene(
                    SceneActionPayload(
                        sceneId: sceneId,
                        sceneName: sceneName,
                        brightnessOverride: nil
                    )
                )
            } else {
                let gradient = currentColorGradient()
                let duration = enableColorFade ? gradientDuration : 0
                return .gradient(
                    GradientActionPayload(
                        gradient: gradient,
                        brightness: Int(gradientBrightness),
                        durationSeconds: duration,
                        shouldLoop: false,
                        presetId: selectedColorPresetId,
                        presetName: selectedColorPreset?.name
                    )
                )
            }
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
            return payload.gradient.stops.last?.hexColor
        case .transition(let payload):
            return payload.endGradient.stops.last?.hexColor
        case .effect(let payload):
            return payload.gradient?.stops.last?.hexColor
        case .preset, .directState:
            return nil
        }
    }
    
    // MARK: - Device Selection
    
    private var allowDeviceSelection: Bool {
        availableDevices.count > 1
    }
    
    private var deviceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices to control")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(availableDevices) { device in
                    let isSelected = selectedDeviceIds.contains(device.id)
                    Button {
                        if isSelected && selectedDeviceIds.count == 1 {
                            return
                        }
                        if isSelected {
                            selectedDeviceIds.remove(device.id)
                        } else {
                            selectedDeviceIds.insert(device.id)
                            activeDevice = device
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.caption)
                                .foregroundColor(isSelected ? .black : .white.opacity(0.9))
                                .lineLimit(1)
                            Text(device.isOnline ? "Online" : "Offline")
                                .font(.caption2)
                                .foregroundColor(isSelected ? .black.opacity(0.7) : (device.isOnline ? .green : .orange))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.white : Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }
                }
            }
        }
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
        if let preset = selectedColorPreset {
            return LEDGradient(stops: preset.gradientStops)
        }
        if let templateGradient {
            return templateGradient
        }
        return viewModel.automationGradient(for: activeDevice)
    }
    
    func buildTransitionAction() -> AutomationAction? {
        if let preset = selectedTransitionPreset {
            return .transition(
                TransitionActionPayload(
                    startGradient: preset.gradientA,
                    startBrightness: preset.brightnessA,
                    endGradient: preset.gradientB,
                    endBrightness: preset.brightnessB,
                    durationSeconds: preset.durationSec,
                    shouldLoop: false,
                    presetId: preset.id,
                    presetName: preset.name
                )
            )
        }
        if let templateTransition = templateTransition {
            var payload = templateTransition
            payload.durationSeconds = customTransitionDuration
            payload.endBrightness = Int(gradientBrightness)
            return .transition(payload)
        }
        return .transition(quickSunrisePayload())
    }
    
    func quickSunrisePayload() -> TransitionActionPayload {
        let startGradient = LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "#120700"),
            GradientStop(position: 1.0, hexColor: "#371401")
        ])
        let endGradient = currentColorGradient()
        return TransitionActionPayload(
            startGradient: startGradient,
            startBrightness: 6,
            endGradient: endGradient,
            endBrightness: Int(gradientBrightness),
            durationSeconds: customTransitionDuration,
            shouldLoop: false,
            presetId: nil,
            presetName: "Quick Sunrise"
        )
    }
    
    func buildEffectAction() -> AutomationAction? {
        guard let effectId = selectedEffectId ?? effectOptions.first?.id else { return nil }
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
        
        if let templateEffectSettings {
            let effectName = effectOptions.first(where: { $0.id == effectId })?.name
            let gradient = templateEffectSettings.gradient ?? templateGradient ?? viewModel.automationGradient(for: activeDevice)
            return .effect(
                EffectActionPayload(
                    effectId: effectId,
                    effectName: effectName,
                    gradient: gradient,
                    speed: templateEffectSettings.speed,
                    intensity: templateEffectSettings.intensity,
                    paletteId: nil,
                    brightness: Int(effectBrightness),
                    presetId: nil,
                    presetName: nil
                )
            )
        }
        
        let effectName = effectOptions.first(where: { $0.id == effectId })?.name
        let gradient = viewModel.automationGradient(for: activeDevice)
        return .effect(
            EffectActionPayload(
                effectId: effectId,
                effectName: effectName,
                gradient: gradient,
                speed: 128,
                intensity: 128,
                paletteId: nil,
                brightness: Int(effectBrightness),
                presetId: nil,
                presetName: nil
            )
        )
    }
    
    var editingGradient: LEDGradient {
        templateGradient ?? viewModel.automationGradient(for: activeDevice)
    }
    
    func setTemplateGradient(_ gradient: LEDGradient, presetId: UUID? = nil) {
        templateGradient = LEDGradient(
            stops: gradient.stops,
            name: gradient.name,
            interpolation: gradient.interpolation
        )
        if let presetId {
            selectedColorPresetId = presetId
        } else {
            selectedColorPresetId = nil
        }
    }
    
    func updateGradientStop(_ stopId: UUID, mutation: (inout GradientStop) -> Void) {
        var gradient = editingGradient
        guard let idx = gradient.stops.firstIndex(where: { $0.id == stopId }) else { return }
        mutation(&gradient.stops[idx])
        gradient.stops.sort { $0.position < $1.position }
        setTemplateGradient(gradient)
    }
    
    func removeGradientStop(_ stopId: UUID) {
        var gradient = editingGradient
        guard gradient.stops.count > 1 else { return }
        gradient.stops.removeAll { $0.id == stopId }
        setTemplateGradient(gradient)
    }
    
    func addGradientStop() {
        var gradient = editingGradient
        let positions = gradient.stops.map { $0.position }
        let newPosition = positions.adjacentMid() ?? 0.5
        let sampledColor = GradientSampler.sampleColor(at: newPosition, stops: gradient.stops, interpolation: gradient.interpolation)
        gradient.stops.append(GradientStop(position: newPosition, hexColor: sampledColor.toHex()))
        gradient.stops.sort { $0.position < $1.position }
        setTemplateGradient(gradient)
    }
    
    func stopLabel(for stop: GradientStop) -> String {
        if let idx = editingGradient.stops.firstIndex(where: { $0.id == stop.id }) {
            return "\(idx + 1)"
        }
        return "#"
    }
    
    func colorBinding(for stop: GradientStop) -> Binding<Color> {
        Binding(
            get: { Color(hex: stop.hexColor) },
            set: { newColor in
                updateGradientStop(stop.id) { $0.hexColor = newColor.toHex() }
            }
        )
    }
    
    func positionBinding(for stop: GradientStop) -> Binding<Double> {
        Binding(
            get: { stop.position },
            set: { newValue in
                updateGradientStop(stop.id) { $0.position = newValue }
            }
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