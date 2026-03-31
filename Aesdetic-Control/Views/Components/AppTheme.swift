import SwiftUI

struct AppStatusColors {
    let positive: Color
    let warning: Color
    let negative: Color
    let info: Color
}

struct AppSemanticTheme {
    let surface: Color
    let surfaceElevated: Color
    let surfaceMuted: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let divider: Color
    let status: AppStatusColors
    let cardStrokeOuter: Color
    let cardStrokeInner: Color
    let cardShadowKey: GlassShadowStyle
    let cardShadowAmbient: GlassShadowStyle
    let controlShadowKey: GlassShadowStyle
    let controlShadowAmbient: GlassShadowStyle
}

enum AppTheme {
    static func tokens(for scheme: ColorScheme) -> AppSemanticTheme {
        let surface = GlassTheme.surfaces(for: scheme)
        let text = GlassTheme.text(for: scheme)
        let lightPrimary = Color(red: 95.0 / 255.0, green: 91.0 / 255.0, blue: 87.0 / 255.0)
        let lightSecondary = Color(red: 95.0 / 255.0, green: 91.0 / 255.0, blue: 87.0 / 255.0).opacity(0.78)

        return AppSemanticTheme(
            surface: surface.cardFillInactive,
            surfaceElevated: surface.cardFillActive,
            surfaceMuted: surface.panelFill,
            textPrimary: scheme == .dark ? text.pagePrimaryText : lightPrimary,
            textSecondary: scheme == .dark ? text.pageSecondaryText : lightSecondary,
            textTertiary: scheme == .dark ? text.pageTertiaryText : lightSecondary.opacity(0.82),
            accent: scheme == .dark ? .white : lightPrimary,
            divider: surface.separator,
            status: AppStatusColors(
                positive: .green,
                warning: .orange,
                negative: .red,
                info: .blue
            ),
            cardStrokeOuter: surface.cardStrokeOuter,
            cardStrokeInner: surface.cardStrokeInner,
            cardShadowKey: surface.cardShadowKey,
            cardShadowAmbient: surface.cardShadowAmbient,
            controlShadowKey: surface.controlShadowKey,
            controlShadowAmbient: surface.controlShadowAmbient
        )
    }

    static func pillFill(for scheme: ColorScheme, isSelected: Bool) -> Color {
        let surface = GlassTheme.surfaces(for: scheme)
        return isSelected ? surface.pillFillSelected : surface.pillFillDefault
    }

    static func pillStroke(for scheme: ColorScheme, isSelected: Bool) -> Color {
        let surface = GlassTheme.surfaces(for: scheme)
        return scheme == .dark && isSelected ? .clear : surface.pillStroke
    }

    static func pillText(for scheme: ColorScheme, isSelected: Bool) -> Color {
        let tokens = tokens(for: scheme)
        if scheme == .dark {
            let text = GlassTheme.text(for: scheme)
            return isSelected ? text.pillTextSelected : text.pillTextDefault
        }
        return tokens.textPrimary
    }

    static func pillSecondaryText(for scheme: ColorScheme, isSelected: Bool) -> Color {
        let tokens = tokens(for: scheme)
        if scheme == .dark {
            let text = GlassTheme.text(for: scheme)
            return isSelected ? text.pillSubtextSelected : text.pillSubtextDefault
        }
        return tokens.textSecondary
    }

    static func cardFill(for scheme: ColorScheme, isActive: Bool = true) -> Color {
        let tokens = tokens(for: scheme)
        return isActive ? tokens.surfaceElevated : tokens.surface
    }

    static func controlForeground(for scheme: ColorScheme, isActive: Bool) -> Color {
        if scheme == .dark {
            return isActive ? .black : .white
        }
        return tokens(for: scheme).textPrimary
    }

    static func controlFill(for scheme: ColorScheme, isActive: Bool) -> Color {
        if scheme == .dark {
            return isActive ? .white : .clear
        }
        // Keep "on" white in light mode, but avoid a fully solid tile.
        return isActive ? Color.white.opacity(0.8) : Color.white.opacity(0.12)
    }

    static func controlFillStyle(for scheme: ColorScheme, isActive: Bool) -> AnyShapeStyle {
        if isActive {
            let gradient = LinearGradient(
                colors: scheme == .dark
                    ? [Color.white.opacity(1.0), Color.white.opacity(0.86)]
                    : [Color.white.opacity(0.94), Color.white.opacity(0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            return AnyShapeStyle(gradient)
        }

        return AnyShapeStyle(controlFill(for: scheme, isActive: false))
    }

    static func controlStroke(for scheme: ColorScheme, isActive: Bool) -> Color {
        if scheme == .dark {
            return isActive ? .clear : .white
        }
        return isActive ? Color.white.opacity(0.34) : Color.white.opacity(0.2)
    }
}
