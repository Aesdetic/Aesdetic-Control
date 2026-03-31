import SwiftUI

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
                .font(.title3.weight(.semibold))
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
        .buttonStyle(.plain)
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
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppSemanticTheme { AppTheme.tokens(for: colorScheme) }
    private var fillColor: Color { AppTheme.pillFill(for: colorScheme, isSelected: isSelected) }
    private var strokeColor: Color { AppTheme.pillStroke(for: colorScheme, isSelected: isSelected) }
    private var textColor: Color { AppTheme.pillText(for: colorScheme, isSelected: isSelected) }
    private var secondaryTextColor: Color { AppTheme.pillSecondaryText(for: colorScheme, isSelected: isSelected) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .compact ? 6 : 8) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(size == .compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundColor(textColor)
                }

                Text(title)
                    .font(size == .compact ? .caption.weight(.semibold) : .subheadline.weight(.medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)

                if let trailingText {
                    Text(trailingText)
                        .font(size == .compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(.horizontal, size == .compact ? 12 : 16)
            .padding(.vertical, size == .compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: size == .compact ? 14 : 18, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size == .compact ? 14 : 18, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
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
        .buttonStyle(.plain)
    }
}

struct AppOverviewMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

struct AppOverviewCard: View {
    let metrics: [AppOverviewMetric]
    var cornerRadius: CGFloat = 20
    var enableInnerShine: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                AppOverviewMetricItem(metric: metric)

                if index < metrics.count - 1 {
                    AppOverviewDivider()
                }
            }
        }
        .frame(height: 68)
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
    }
}

private struct AppOverviewMetricItem: View {
    let metric: AppOverviewMetric

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(metric.value)
                .font(.title.bold())
                .foregroundColor(AppTheme.tokens(for: colorScheme).textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(metric.label)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.tokens(for: colorScheme).textSecondary)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AppTheme.tokens(for: colorScheme).divider)
            .frame(width: 1)
            .padding(.vertical, 16)
    }
}
