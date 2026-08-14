import SwiftUI

private struct AppGlassSnappyTapStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct AppGlassIconButton: View {
    let systemName: String
    var isProminent: Bool = true
    var size: CGFloat = 48
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var fillColor: Color { AppTheme.controlFill(for: colorScheme, isActive: isProminent) }
    private var strokeColor: Color { AppTheme.controlStroke(for: colorScheme, isActive: isProminent) }
    private var foregroundColor: Color { AppTheme.controlForeground(for: colorScheme, isActive: isProminent) }
    private var fillStyle: AnyShapeStyle { AppTheme.controlFillStyle(for: colorScheme, isActive: isProminent) }
    private var isLightMode: Bool { colorScheme == .light }
    private var shineLineWidth: CGFloat { isProminent ? 2.4 : 1.8 }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(fillStyle)
                )
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 1)
                )
                .overlay {
                    if isLightMode {
                        Circle()
                            .inset(by: 1.2)
                            .stroke(
                                Color.white.opacity(isProminent ? 0.78 : 0.58),
                                style: StrokeStyle(lineWidth: shineLineWidth, lineCap: .round)
                            )
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.9), location: 0.42),
                                        .init(color: .clear, location: 0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Circle()
                            .inset(by: 1.5)
                            .stroke(
                                Color.white.opacity(isProminent ? 0.52 : 0.38),
                                style: StrokeStyle(lineWidth: shineLineWidth - 0.6, lineCap: .round)
                            )
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.65), location: 0.32),
                                        .init(color: .clear, location: 0.7)
                                    ],
                                    startPoint: .bottomTrailing,
                                    endPoint: .topLeading
                                )
                            )
                        Circle()
                            .inset(by: 1.6)
                            .stroke(
                                Color.white.opacity(isProminent ? 0.3 : 0.22),
                                style: StrokeStyle(lineWidth: shineLineWidth - 0.6, lineCap: .round)
                            )
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.55), location: 0.28),
                                        .init(color: .clear, location: 0.68)
                                    ],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading
                                )
                            )
                        Circle()
                            .inset(by: 1.6)
                            .stroke(
                                Color.white.opacity(isProminent ? 0.26 : 0.18),
                                style: StrokeStyle(lineWidth: shineLineWidth - 0.8, lineCap: .round)
                            )
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.5), location: 0.24),
                                        .init(color: .clear, location: 0.65)
                                    ],
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            )
                    }
                }
                .shadow(
                    color: theme.controlShadowAmbient.color,
                    radius: theme.controlShadowAmbient.radius,
                    x: theme.controlShadowAmbient.x,
                    y: theme.controlShadowAmbient.y
                )
                .shadow(
                    color: theme.controlShadowKey.color,
                    radius: theme.controlShadowKey.radius,
                    x: theme.controlShadowKey.x,
                    y: theme.controlShadowKey.y
                )
        }
        .buttonStyle(AppGlassSnappyTapStyle(pressedScale: 0.93))
    }
}

struct AppGlassPillButton: View {
    enum Size {
        case regular
        case compact
    }

    let title: String
    let isSelected: Bool
    var iconName: String? = nil
    var trailingText: String? = nil
    var size: Size = .regular
    var useControlGlassRecipe: Bool = false
    var useAppleSelectedStyle: Bool = false
    var selectedGlassRole: AppLiquidGlassRole = .panel
    var selectedFrostUsesMaterial: Bool = true
    var foregroundColorOverride: Color? = nil
    var secondaryForegroundColorOverride: Color? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var fillColor: Color { AppTheme.pillFill(for: colorScheme, isSelected: isSelected) }
    private var strokeColor: Color { AppTheme.pillStroke(for: colorScheme, isSelected: isSelected) }
    private var textColor: Color {
        foregroundColorOverride ?? AppTheme.pillText(for: colorScheme, isSelected: isSelected)
    }
    private var secondaryTextColor: Color {
        secondaryForegroundColorOverride ?? AppTheme.pillSecondaryText(for: colorScheme, isSelected: isSelected)
    }
    private var cornerRadius: CGFloat { size == .compact ? 14 : 18 }
    private var glassRole: AppLiquidGlassRole {
        useAppleSelectedStyle && isSelected ? selectedGlassRole : .control
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .compact ? 6 : 8) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(
                            size == .compact
                                ? .system(size: 12, weight: .regular)
                                : .system(size: 15, weight: .regular)
                        )
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(textColor)
                }

                Text(title)
                    .font(
                        size == .compact
                            ? AppTypography.style(.caption, weight: .semibold)
                            : AppTypography.style(.subheadline, weight: .medium)
                    )
                    .foregroundColor(textColor)
                    .lineLimit(1)

                if let trailingText {
                    Text(trailingText)
                        .font(
                            size == .compact
                                ? AppTypography.style(.caption2, weight: .semibold)
                                : AppTypography.style(.caption, weight: .semibold)
                        )
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(.horizontal, size == .compact ? 12 : 16)
            .padding(.vertical, size == .compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(useControlGlassRecipe ? Color.clear : fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(useControlGlassRecipe ? .clear : strokeColor, lineWidth: 1)
            )
            .overlay(
                Group {
                    if useControlGlassRecipe && useAppleSelectedStyle {
                        AppLiquidGlassFrostOverlay(
                            isActive: isSelected,
                            cornerRadius: cornerRadius,
                            usesMaterial: selectedFrostUsesMaterial
                        )
                    }
                }
            )
            .shadow(
                color: theme.controlShadowAmbient.color,
                radius: theme.controlShadowAmbient.radius,
                x: theme.controlShadowAmbient.x,
                y: theme.controlShadowAmbient.y
            )
            .shadow(
                color: theme.controlShadowKey.color,
                radius: theme.controlShadowKey.radius,
                x: theme.controlShadowKey.x,
                y: theme.controlShadowKey.y
            )
        }
        .if(useControlGlassRecipe) { view in
            view.appLiquidGlass(role: glassRole, cornerRadius: cornerRadius)
        }
        .buttonStyle(AppGlassSnappyTapStyle(pressedScale: size == .compact ? 0.97 : 0.96))
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

struct PresetSavePillButton: View {
    let title: String
    let isSaving: Bool
    let isSuccess: Bool
    var isDisabled: Bool = false
    var minWidth: CGFloat = 112
    var normalForegroundColor: Color = .white.opacity(0.9)
    var disabledForegroundColor: Color = .white.opacity(0.45)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.68)
                            .tint(currentForegroundColor)
                    } else {
                        Image(systemName: isSuccess ? "checkmark" : "plus.circle")
                            .font(.system(size: 12, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .symbolEffect(.bounce, value: isSuccess)
                    }
                }
                .frame(width: 15, height: 15)

                Text(title)
                    .font(AppTypography.style(.caption, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(currentForegroundColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(minWidth: minWidth)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSuccess ? 0.16 : 0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                Color.white.opacity(isSuccess ? 0.26 : 0.16),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: isSuccess ? Color.white.opacity(0.08) : Color.clear, radius: 6, x: 0, y: 2)
            .scaleEffect(isSuccess ? 1.018 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isSuccess)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
        .accessibilityLabel(title)
        .accessibilityValue(isSaving ? "Saving" : (isSuccess ? "Saved" : "Ready"))
    }

    private var currentForegroundColor: Color {
        if isDisabled {
            return disabledForegroundColor
        }
        return normalForegroundColor
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct AppOverviewMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

struct AppOverviewCard: View {
    let metrics: [AppOverviewMetric]

    enum Style {
        case standard
        case liquidGlass(tint: Color? = nil, clarity: LiquidGlassBackground.Clarity = .standard)
        case systemGlass(tint: Color? = nil, interactive: Bool = false)
    }

    var style: Style = .systemGlass(tint: nil, interactive: false)
    var cornerRadius: CGFloat = 20
    var enableInnerShine: Bool = false
    var valueColorOverride: Color? = nil
    var labelColorOverride: Color? = nil
    var dividerColorOverride: Color? = nil
    var valueFontOverride: Font? = nil
    var labelFontOverride: Font? = nil
    var height: CGFloat = 68

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let cardContent = HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                AppOverviewMetricItem(
                    metric: metric,
                    valueColorOverride: valueColorOverride,
                    labelColorOverride: labelColorOverride,
                    valueFontOverride: valueFontOverride,
                    labelFontOverride: labelFontOverride
                )

                if index < metrics.count - 1 {
                    AppOverviewDivider(colorOverride: dividerColorOverride)
                }
            }
        }
        .frame(height: height)

        switch style {
        case .systemGlass(let tint, let interactive):
            Group {
                if #available(iOS 26.0, *) {
                    cardContent
                        .glassEffect({
                            var g: Glass = .clear
                            if let tint { g = g.tint(tint) }
                            if interactive { g = g.interactive() }
                            return g
                        }(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    // Fallback for earlier OS versions: keep a transparent liquid-glass look
                    cardContent
                        .background(
                            LiquidGlassBackground(
                                cornerRadius: cornerRadius,
                                tint: tint,
                                clarity: .clear
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }

        case .standard:
            cardContent
                .background(
                    AppCardBackground(
                        style: AppCardStyles.glass(
                            for: colorScheme,
                            tone: .active,
                            cornerRadius: cornerRadius
                        )
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if enableInnerShine && colorScheme == .light {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.0)
                            .stroke(Color.white.opacity(0.7), lineWidth: 2.0)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.9), location: 0.42),
                                        .init(color: .clear, location: 0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.2)
                            .stroke(Color.white.opacity(0.42), lineWidth: 1.2)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.62), location: 0.3),
                                        .init(color: .clear, location: 0.68)
                                    ],
                                    startPoint: .bottomTrailing,
                                    endPoint: .topLeading
                                )
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.4)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1.0)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.5), location: 0.24),
                                        .init(color: .clear, location: 0.65)
                                    ],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading
                                )
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.4)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1.0)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.46), location: 0.24),
                                        .init(color: .clear, location: 0.65)
                                    ],
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            )
                    }
                }

        case .liquidGlass(let tint, let clarity):
            cardContent
                .background(
                    LiquidGlassBackground(cornerRadius: cornerRadius, tint: tint, clarity: clarity)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if enableInnerShine && colorScheme == .light {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.0)
                            .stroke(Color.white.opacity(0.7), lineWidth: 2.0)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.9), location: 0.42),
                                        .init(color: .clear, location: 0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.2)
                            .stroke(Color.white.opacity(0.42), lineWidth: 1.2)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.62), location: 0.3),
                                        .init(color: .clear, location: 0.68)
                                    ],
                                    startPoint: .bottomTrailing,
                                    endPoint: .topLeading
                                )
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.4)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1.0)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.5), location: 0.24),
                                        .init(color: .clear, location: 0.65)
                                    ],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading
                                )
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 1.4)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1.0)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.46), location: 0.24),
                                        .init(color: .clear, location: 0.65)
                                    ],
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            )
                    }
                }
        }
    }
}

private struct AppOverviewMetricItem: View {
    let metric: AppOverviewMetric
    let valueColorOverride: Color?
    let labelColorOverride: Color?
    let valueFontOverride: Font?
    let labelFontOverride: Font?
    @Environment(\.colorScheme) private var colorScheme
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            Text(metric.value)
                .font(valueFontOverride ?? AppTypography.display(size: 28, weight: .semibold, relativeTo: .title2))
                .foregroundColor((valueColorOverride ?? theme.textPrimary).opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(metric.label)
                .font(labelFontOverride ?? AppTypography.text(size: 12, weight: .semibold, relativeTo: .caption))
                .foregroundColor((labelColorOverride ?? theme.textSecondary).opacity(0.94))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct AppOverviewDivider: View {
    let colorOverride: Color?
    @Environment(\.colorScheme) private var colorScheme
    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }

    var body: some View {
        Rectangle()
            .fill((colorOverride ?? theme.divider).opacity(0.72))
            .frame(width: 1)
            .padding(.vertical, 16)
    }
}
