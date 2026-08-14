import SwiftUI

struct DeviceBehaviorSettingsCard: View {
    let device: WLEDDevice
    let objectName: String
    let glassStyle: SettingsCardGlassStyle
    let openAdvanced: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var store: DeviceBehaviorSettingsStore

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    init(
        device: WLEDDevice,
        objectName: String,
        glassStyle: SettingsCardGlassStyle = .detailControl,
        openAdvanced: @escaping () -> Void
    ) {
        self.device = device
        self.objectName = objectName
        self.glassStyle = glassStyle
        self.openAdvanced = openAdvanced
        _store = State(initialValue: DeviceBehaviorSettingsStore(device: device))
    }

    var body: some View {
        SettingsCard(title: "\(objectName) Behavior", glassStyle: glassStyle) {
            VStack(alignment: .leading, spacing: 16) {
                if store.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading behavior settings...")
                            .font(AppTypography.style(.subheadline))
                            .foregroundStyle(theme.settingsText(.secondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    startupControl
                    Divider().overlay(theme.divider)
                    brightnessControl
                    Divider().overlay(theme.divider)
                    transitionControl
                }

                statusRow

                Button(action: openAdvanced) {
                    SettingsButton(
                        title: "More Light Behavior Settings",
                        icon: "slider.horizontal.3",
                        style: .overviewRow
                    )
                }
            }
        }
        .task(id: device.id) {
            await store.load()
        }
    }

    private var startupControl: some View {
        Toggle(
            "Turn on after power is restored",
            isOn: Binding(
                get: { store.powerOnAfterRestart },
                set: { store.setPowerOnAfterRestart($0) }
            )
        )
        .settingsToggleStyle()
        .accessibilityIdentifier("behavior-power-on")
        .accessibilityHint("Controls the next power-up or restart.")
    }

    @ViewBuilder
    private var brightnessControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Maximum brightness")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundStyle(theme.settingsText(.primary))
                Spacer()
                Text(store.hasCustomBrightness ? "Custom: \(store.maximumBrightness)%" : "\(store.maximumBrightness)%")
                    .font(AppTypography.style(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.settingsText(.secondary))
            }

            if store.hasCustomBrightness {
                SettingsDescriptionText(
                    markdown: "**Custom value:** Above the simple range. It stays unchanged until edited in Advanced."
                )
            } else {
                Slider(
                    value: Binding(
                        get: { Double(store.maximumBrightness) },
                        set: { store.previewMaximumBrightness($0) }
                    ),
                    in: 1...100,
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { store.commitMaximumBrightness() }
                    }
                )
                .tint(theme.settingsText(.primary))
                .accessibilityIdentifier("behavior-maximum-brightness")
                .accessibilityValue("\(store.maximumBrightness) percent")
            }

            SettingsDescriptionText(
                markdown: "**Output limit:** Does not change the brightness selected in Controls."
            )
        }
    }

    private var transitionControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Default transition")
                    .font(AppTypography.style(.subheadline, weight: .medium))
                    .foregroundStyle(theme.settingsText(.primary))
                Spacer()
                if store.selectedTransition == nil {
                    Text("Custom: \(store.transitionMilliseconds) ms")
                        .font(AppTypography.style(.caption, weight: .semibold))
                        .foregroundStyle(theme.settingsText(.secondary))
                }
            }

            Picker(
                "Default transition",
                selection: Binding<DeviceBehaviorTransition?>(
                    get: { store.selectedTransition },
                    set: { selection in
                        if let selection { store.setTransition(selection) }
                    }
                )
            ) {
                ForEach(DeviceBehaviorTransition.allCases) { transition in
                    Text(transition.title).tag(Optional(transition))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("behavior-default-transition")

            SettingsDescriptionText(
                markdown: "**Fade speed:** Used for color, effect, and brightness changes."
            )
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let statusText = store.status.text, !store.isLoading {
            Button {
                store.retry()
            } label: {
                HStack(spacing: 8) {
                    if store.isSaving {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Image(systemName: statusIcon)
                            .font(AppTypography.style(.caption, weight: .semibold))
                    }
                    Text(statusText)
                        .font(AppTypography.style(.caption, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(statusColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isFailure)
        }
    }

    private var isFailure: Bool {
        if case .failed = store.status { return true }
        return false
    }

    private var statusIcon: String {
        switch store.status {
        case .saved: return "checkmark.circle.fill"
        case .restartRequired: return "arrow.clockwise.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .failed: return theme.settingsText(.warning)
        default: return theme.settingsText(.secondary)
        }
    }
}
