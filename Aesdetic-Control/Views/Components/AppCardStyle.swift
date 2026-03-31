import SwiftUI

enum AppCardTone {
    case active
    case inactive
    case muted
}

struct AppCardStyle {
    let cornerRadius: CGFloat
    let fill: Color
    let outerStroke: Color
    let innerStroke: Color
    let keyShadow: GlassShadowStyle
    let ambientShadow: GlassShadowStyle
}

enum AppCardStyles {
    static func glass(
        for scheme: ColorScheme,
        tone: AppCardTone,
        cornerRadius: CGFloat
    ) -> AppCardStyle {
        let theme = AppTheme.tokens(for: scheme)
        let fill: Color

        switch tone {
        case .active:
            fill = theme.surfaceElevated
        case .inactive:
            fill = theme.surface
        case .muted:
            fill = theme.surfaceMuted
        }

        return AppCardStyle(
            cornerRadius: cornerRadius,
            fill: fill,
            outerStroke: theme.cardStrokeOuter,
            innerStroke: theme.cardStrokeInner,
            keyShadow: theme.cardShadowKey,
            ambientShadow: theme.cardShadowAmbient
        )
    }
}

struct AppCardBackground: View {
    let style: AppCardStyle

    var body: some View {
        GlassCardBackground(
            cornerRadius: style.cornerRadius,
            fill: style.fill,
            outerStroke: style.outerStroke,
            innerStroke: style.innerStroke,
            keyShadow: style.keyShadow,
            ambientShadow: style.ambientShadow
        )
    }
}
