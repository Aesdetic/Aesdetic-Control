import SwiftUI

enum AppLiquidGlassRole {
    case card
    case panel
    case control
    case frostedTransition
    case highContrast

    var cornerRadius: CGFloat {
        switch self {
        case .card:
            return 20
        case .panel:
            return 20
        case .control:
            return 16
        case .frostedTransition:
            return 20
        case .highContrast:
            return 20
        }
    }
}

private struct AppLiquidGlassModifier: ViewModifier {
    let role: AppLiquidGlassRole
    var cornerRadiusOverride: CGFloat?
    var showHighContrastEdge: Bool = true
    var highContrastDarkTintOpacity: Double = 0.12

    private var cornerRadius: CGFloat {
        cornerRadiusOverride ?? role.cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var glassBackground: some View {
        if role == .frostedTransition {
            frostedTransitionBackground
        } else if #available(iOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            switch role {
            case .panel:
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .opacity(intensity)
            case .card, .control:
                Color.clear
                    .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            case .highContrast:
                ZStack {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    shape.fill(Color.black.opacity(highContrastDarkTintOpacity))
                    if showHighContrastEdge {
                        shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                    }
                }
                .clipShape(shape)
            case .frostedTransition:
                EmptyView()
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            LiquidGlassBackground(
                cornerRadius: cornerRadius,
                tint: nil,
                clarity: clarity
            )
            .opacity(intensity)
            .overlay {
                if role == .highContrast {
                    shape.fill(Color.black.opacity(highContrastDarkTintOpacity))
                }
            }
            .overlay {
                if role == .highContrast && showHighContrastEdge {
                    shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                }
            }
        }
    }

    @ViewBuilder
    private var frostedTransitionBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .opacity(0.52)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    shape.stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .clipShape(shape)
                )
        } else {
            LiquidGlassBackground(
                cornerRadius: cornerRadius,
                tint: nil,
                clarity: .standard
            )
            .opacity(0.62)
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
        }
    }

    private var clarity: LiquidGlassBackground.Clarity {
        switch role {
        case .panel:
            return .standard
        case .card, .control:
            return .clear
        case .frostedTransition, .highContrast:
            return .standard
        }
    }

    private var intensity: Double {
        switch role {
        case .panel:
            return 0.64
        case .card, .control:
            return 1.0
        case .frostedTransition:
            return 0.62
        case .highContrast:
            return 0.94
        }
    }
}

extension View {
    func appLiquidGlass(
        role: AppLiquidGlassRole = .card,
        cornerRadius: CGFloat? = nil,
        showHighContrastEdge: Bool = true,
        highContrastDarkTintOpacity: Double = 0.12
    ) -> some View {
        modifier(
            AppLiquidGlassModifier(
                role: role,
                cornerRadiusOverride: cornerRadius,
                showHighContrastEdge: showHighContrastEdge,
                highContrastDarkTintOpacity: highContrastDarkTintOpacity
            )
        )
    }
}
