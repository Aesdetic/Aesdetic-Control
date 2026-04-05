import SwiftUI

enum AppLiquidGlassRole {
    case card
    case panel
    case control

    var cornerRadius: CGFloat {
        switch self {
        case .card:
            return 20
        case .panel:
            return 20
        case .control:
            return 16
        }
    }
}

private struct AppLiquidGlassModifier: ViewModifier {
    let role: AppLiquidGlassRole
    var cornerRadiusOverride: CGFloat?

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
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            LiquidGlassBackground(
                cornerRadius: cornerRadius,
                tint: nil,
                clarity: .clear
            )
        }
    }
}

extension View {
    func appLiquidGlass(role: AppLiquidGlassRole = .card, cornerRadius: CGFloat? = nil) -> some View {
        modifier(AppLiquidGlassModifier(role: role, cornerRadiusOverride: cornerRadius))
    }
}
