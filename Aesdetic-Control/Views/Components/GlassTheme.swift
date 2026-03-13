import SwiftUI

struct GlassShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

struct GlassSurfaceStyle {
    let cardFillActive: Color
    let cardFillInactive: Color
    let cardStrokeOuter: Color
    let cardStrokeInner: Color
    let cardShadowKey: GlassShadowStyle
    let cardShadowAmbient: GlassShadowStyle
    let pillFillSelected: Color
    let pillFillDefault: Color
    let pillStroke: Color
    let panelFill: Color
    let fieldFill: Color
    let separator: Color
    let controlShadowKey: GlassShadowStyle
    let controlShadowAmbient: GlassShadowStyle
}

struct GlassTextStyle {
    let pagePrimaryText: Color
    let pageSecondaryText: Color
    let pageTertiaryText: Color
    let pillTextSelected: Color
    let pillTextDefault: Color
    let pillSubtextSelected: Color
    let pillSubtextDefault: Color
}

enum GlassTheme {
    static func surfaces(for scheme: ColorScheme) -> GlassSurfaceStyle {
        scheme == .dark ? darkSurfaceStyle : lightSurfaceStyle
    }

    static func text(for scheme: ColorScheme) -> GlassTextStyle {
        scheme == .dark ? darkTextStyle : lightTextStyle
    }

    private static let lightTextStyle = GlassTextStyle(
        pagePrimaryText: Color(red: 0.227, green: 0.216, blue: 0.200), // softer than #2C2B29
        pageSecondaryText: Color(red: 0.424, green: 0.396, blue: 0.365),
        pageTertiaryText: Color(red: 0.557, green: 0.529, blue: 0.490),
        pillTextSelected: Color(red: 0.227, green: 0.216, blue: 0.200),
        pillTextDefault: Color(red: 0.227, green: 0.216, blue: 0.200),
        pillSubtextSelected: Color(red: 0.424, green: 0.396, blue: 0.365),
        pillSubtextDefault: Color(red: 0.424, green: 0.396, blue: 0.365)
    )

    private static let darkTextStyle = GlassTextStyle(
        pagePrimaryText: .white,
        pageSecondaryText: Color.white.opacity(0.78),
        pageTertiaryText: Color.white.opacity(0.58),
        pillTextSelected: .black,
        pillTextDefault: .white,
        pillSubtextSelected: Color.black.opacity(0.7),
        pillSubtextDefault: Color.white.opacity(0.68)
    )

    private static let lightSurfaceStyle = GlassSurfaceStyle(
        cardFillActive: Color.white.opacity(0.22),
        cardFillInactive: Color.white.opacity(0.16),
        cardStrokeOuter: Color.black.opacity(0.08),
        cardStrokeInner: Color.white.opacity(0.28),
        cardShadowKey: GlassShadowStyle(
            color: Color.black.opacity(0.1),
            radius: 26,
            x: 0,
            y: 14
        ),
        cardShadowAmbient: GlassShadowStyle(
            color: Color.black.opacity(0.035),
            radius: 10,
            x: 0,
            y: 4
        ),
        pillFillSelected: Color.white.opacity(0.6),
        pillFillDefault: Color.white.opacity(0.22),
        pillStroke: Color.black.opacity(0.08),
        panelFill: Color.white.opacity(0.16),
        fieldFill: Color.white.opacity(0.24),
        separator: Color.black.opacity(0.1),
        controlShadowKey: GlassShadowStyle(
            color: Color.black.opacity(0.08),
            radius: 16,
            x: 0,
            y: 8
        ),
        controlShadowAmbient: GlassShadowStyle(
            color: Color.black.opacity(0.025),
            radius: 8,
            x: 0,
            y: 2
        )
    )

    private static let darkSurfaceStyle = GlassSurfaceStyle(
        cardFillActive: Color.white.opacity(0.13),
        cardFillInactive: Color.white.opacity(0.08),
        cardStrokeOuter: Color.white.opacity(0.22),
        cardStrokeInner: Color.white.opacity(0.1),
        cardShadowKey: GlassShadowStyle(
            color: Color.black.opacity(0.2),
            radius: 14,
            x: 0,
            y: 7
        ),
        cardShadowAmbient: GlassShadowStyle(
            color: Color.black.opacity(0.11),
            radius: 7,
            x: 0,
            y: 2
        ),
        pillFillSelected: Color.white,
        pillFillDefault: Color.white.opacity(0.14),
        pillStroke: Color.white.opacity(0.26),
        panelFill: Color.white.opacity(0.1),
        fieldFill: Color.white.opacity(0.16),
        separator: Color.white.opacity(0.16),
        controlShadowKey: GlassShadowStyle(
            color: Color.black.opacity(0.14),
            radius: 10,
            x: 0,
            y: 5
        ),
        controlShadowAmbient: GlassShadowStyle(
            color: Color.black.opacity(0.07),
            radius: 5,
            x: 0,
            y: 1
        )
    )
}

struct GlassCardBackground: View {
    let cornerRadius: CGFloat
    let fill: Color
    let outerStroke: Color
    let innerStroke: Color
    let keyShadow: GlassShadowStyle
    let ambientShadow: GlassShadowStyle

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(outerStroke, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: 1)
                    .stroke(innerStroke, lineWidth: 1)
            )
            .shadow(
                color: ambientShadow.color,
                radius: ambientShadow.radius,
                x: ambientShadow.x,
                y: ambientShadow.y
            )
            .shadow(
                color: keyShadow.color,
                radius: keyShadow.radius,
                x: keyShadow.x,
                y: keyShadow.y
            )
    }
}
