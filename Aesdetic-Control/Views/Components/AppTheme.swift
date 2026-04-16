import SwiftUI
import UIKit

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

enum AppTypography {
    enum Family {
        case display
        case text
    }

    static func style(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let family: Family = usesDisplayFamily(for: textStyle) ? .display : .text
        return customFont(family: family, size: preferredPointSize(for: textStyle), weight: weight, relativeTo: textStyle)
    }

    static func display(size: CGFloat, weight: Font.Weight = .semibold, relativeTo textStyle: Font.TextStyle = .headline) -> Font {
        customFont(family: .display, size: size, weight: weight, relativeTo: textStyle)
    }

    static func text(size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        customFont(family: .text, size: size, weight: weight, relativeTo: textStyle)
    }

    private static func usesDisplayFamily(for textStyle: Font.TextStyle) -> Bool {
        switch textStyle {
        case .largeTitle, .title, .title2, .title3, .headline:
            return true
        default:
            return false
        }
    }

    private static func preferredPointSize(for textStyle: Font.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: uiTextStyle(for: textStyle)).pointSize
    }

    private static func uiTextStyle(for textStyle: Font.TextStyle) -> UIFont.TextStyle {
        switch textStyle {
        case .largeTitle:
            return .largeTitle
        case .title:
            return .title1
        case .title2:
            return .title2
        case .title3:
            return .title3
        case .headline:
            return .headline
        case .subheadline:
            return .subheadline
        case .callout:
            return .callout
        case .caption:
            return .caption1
        case .caption2:
            return .caption2
        case .footnote:
            return .footnote
        default:
            return .body
        }
    }

    private static func customFont(
        family: Family,
        size: CGFloat,
        weight: Font.Weight,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        for name in candidateNames(for: family, weight: weight) where UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: textStyle)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    private static func candidateNames(for family: Family, weight: Font.Weight) -> [String] {
        let compactFamily = family == .display ? "SFProDisplay" : "SFProText"
        let spacedFamily = family == .display ? "SF Pro Display" : "SF Pro Text"
        var names: [String] = []
        for suffix in suffixes(for: weight) {
            names.append("\(compactFamily)-\(suffix)")
            names.append("\(spacedFamily) \(suffix)")
        }
        names.append(compactFamily)
        names.append(spacedFamily)
        return names
    }

    private static func suffixes(for weight: Font.Weight) -> [String] {
        if weight == .ultraLight {
            return ["Ultralight", "UltraLight"]
        }
        if weight == .thin {
            return ["Thin"]
        }
        if weight == .light {
            return ["Light"]
        }
        if weight == .regular {
            return ["Regular"]
        }
        if weight == .medium {
            return ["Medium"]
        }
        if weight == .semibold {
            return ["Semibold", "SemiBold"]
        }
        if weight == .bold {
            return ["Bold"]
        }
        if weight == .heavy {
            return ["Heavy"]
        }
        if weight == .black {
            return ["Black"]
        }
        return ["Regular"]
    }
}

extension View {
    func appFont(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        font(AppTypography.style(textStyle, weight: weight))
    }

    func appDisplayFont(size: CGFloat, weight: Font.Weight = .semibold, relativeTo textStyle: Font.TextStyle = .headline) -> some View {
        font(AppTypography.display(size: size, weight: weight, relativeTo: textStyle))
    }

    func appTextFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> some View {
        font(AppTypography.text(size: size, weight: weight, relativeTo: textStyle))
    }
}
