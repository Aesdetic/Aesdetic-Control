import SwiftUI
import UIKit

struct AppStatusColors {
    let positive: Color
    let warning: Color
    let negative: Color
    let info: Color
}

enum SettingsGlassTextRole {
    case primary
    case secondary
    case disabled
    case warning
    case error
}

enum SettingsGlassSurfaceRole {
    case card
    case section
    case control
    case row
}

enum DeviceDetailTextRole {
    case primary
    case secondary
    case tertiary
    case disabled
}

enum AppStatusKind {
    case success
    case warning
    case error
    case info
}

struct AppSemanticTheme {
    let surface: Color
    let surfaceElevated: Color
    let surfaceMuted: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let settingsTextPrimary: Color
    let settingsTextSecondary: Color
    let accent: Color
    let divider: Color
    let status: AppStatusColors
    let cardStrokeOuter: Color
    let cardStrokeInner: Color
    let cardShadowKey: GlassShadowStyle
    let cardShadowAmbient: GlassShadowStyle
    let controlShadowKey: GlassShadowStyle
    let controlShadowAmbient: GlassShadowStyle

    func settingsText(_ role: SettingsGlassTextRole) -> Color {
        switch role {
        case .primary:
            return settingsTextPrimary
        case .secondary:
            return settingsTextSecondary
        case .disabled:
            return Color.white.opacity(0.54)
        case .warning:
            return status.warning
        case .error:
            return status.negative
        }
    }
}

private struct SettingsForegroundStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let role: SettingsGlassTextRole

    func body(content: Content) -> some View {
        content.foregroundStyle(AppTheme.tokens(for: colorScheme).settingsText(role))
    }
}

extension View {
    /// Applies the shared settings contrast hierarchy without adding shadows.
    func settingsForegroundStyle(_ role: SettingsGlassTextRole) -> some View {
        modifier(SettingsForegroundStyleModifier(role: role))
    }
}

enum AppTheme {
    static func deviceDetailText(_ role: DeviceDetailTextRole, for scheme: ColorScheme) -> Color {
        switch (role, scheme) {
        case (.primary, .light): return Color.white.opacity(0.98)
        case (.primary, .dark): return Color.white.opacity(0.96)
        case (.secondary, .light): return Color.white.opacity(0.92)
        case (.secondary, .dark): return Color.white.opacity(0.90)
        case (.tertiary, .light): return Color.white.opacity(0.82)
        case (.tertiary, .dark): return Color.white.opacity(0.80)
        case (.disabled, .light): return Color.white.opacity(0.64)
        case (.disabled, .dark): return Color.white.opacity(0.62)
        @unknown default: return Color.white.opacity(0.90)
        }
    }

    static func settingsGlassDarkTint(_ role: SettingsGlassSurfaceRole, for scheme: ColorScheme) -> Double {
        switch (role, scheme) {
        case (.card, .light): return 0.17
        case (.card, .dark): return 0.12
        case (.section, .light): return 0.17
        case (.section, .dark): return 0.11
        case (.control, .light): return 0.15
        case (.control, .dark): return 0.10
        case (.row, .light): return 0.13
        case (.row, .dark): return 0.08
        @unknown default: return 0.14
        }
    }

    static func tokens(for scheme: ColorScheme) -> AppSemanticTheme {
        let surface = GlassTheme.surfaces(for: scheme)
        let text = GlassTheme.text(for: scheme)
        return AppSemanticTheme(
            surface: surface.cardFillInactive,
            surfaceElevated: surface.cardFillActive,
            surfaceMuted: surface.panelFill,
            textPrimary: text.pillTextSelected,
            textSecondary: text.pillSubtextSelected,
            textTertiary: text.pillSubtextDefault,
            settingsTextPrimary: Color.white.opacity(0.96),
            settingsTextSecondary: Color.white.opacity(0.88),
            accent: text.pillTextSelected,
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
        let text = GlassTheme.text(for: scheme)
        return isSelected ? text.pillTextSelected : text.pillTextDefault
    }

    static func pillSecondaryText(for scheme: ColorScheme, isSelected: Bool) -> Color {
        let text = GlassTheme.text(for: scheme)
        return isSelected ? text.pillSubtextSelected : text.pillSubtextDefault
    }

    static func cardFill(for scheme: ColorScheme, isActive: Bool = true) -> Color {
        let tokens = tokens(for: scheme)
        return isActive ? tokens.surfaceElevated : tokens.surface
    }

    static func controlForeground(for scheme: ColorScheme, isActive: Bool) -> Color {
        isActive ? text(.selectedControlPrimary, for: scheme) : text(.controlPrimary, for: scheme)
    }

    static func controlFill(for scheme: ColorScheme, isActive: Bool) -> Color {
        isActive ? Color.white.opacity(scheme == .dark ? 0.22 : 0.28) : Color.white.opacity(0.12)
    }

    static func controlFillStyle(for scheme: ColorScheme, isActive: Bool) -> AnyShapeStyle {
        if isActive {
            let gradient = LinearGradient(
                colors: scheme == .dark
                    ? [Color.white.opacity(0.30), Color.white.opacity(0.18)]
                    : [Color.white.opacity(0.34), Color.white.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            return AnyShapeStyle(gradient)
        }

        return AnyShapeStyle(controlFill(for: scheme, isActive: false))
    }

    static func controlStroke(for scheme: ColorScheme, isActive: Bool) -> Color {
        isActive ? Color.white.opacity(0.34) : Color.white.opacity(0.20)
    }

    static func text(_ role: AppTextRole, for scheme: ColorScheme) -> Color {
        let tokens = tokens(for: scheme)
        switch role {
        case .pagePrimary:
            return tokens.textPrimary
        case .pageSecondary:
            return tokens.textSecondary
        case .pageTertiary:
            return tokens.textTertiary
        case .glassPrimary:
            return Color.white.opacity(scheme == .dark ? 0.94 : 1.0)
        case .glassSecondary:
            return Color.white.opacity(scheme == .dark ? 0.78 : 0.82)
        case .glassTertiary:
            return Color.white.opacity(scheme == .dark ? 0.58 : 0.62)
        case .controlPrimary:
            return text(.glassPrimary, for: scheme)
        case .controlSecondary:
            return text(.glassSecondary, for: scheme)
        case .selectedControlPrimary:
            return text(.glassPrimary, for: scheme)
        case .selectedControlSecondary:
            return text(.glassSecondary, for: scheme)
        case .fieldPrimary:
            let text = GlassTheme.text(for: scheme)
            return scheme == .dark ? Color.white.opacity(0.94) : text.pagePrimaryText
        case .fieldSecondary:
            let text = GlassTheme.text(for: scheme)
            return scheme == .dark ? Color.white.opacity(0.70) : text.pageSecondaryText
        case .statusAccent:
            return text(.glassPrimary, for: scheme)
        case .disabled:
            return text(.glassTertiary, for: scheme).opacity(0.68)
        case .success:
            return text(.glassPrimary, for: scheme)
        case .warning:
            return text(.glassPrimary, for: scheme)
        case .error:
            return text(.glassPrimary, for: scheme)
        case .accent:
            return tokens.accent
        }
    }

    static func statusAccent(_ kind: AppStatusKind, for scheme: ColorScheme) -> Color {
        let status = tokens(for: scheme).status
        switch kind {
        case .success:
            return status.positive
        case .warning:
            return status.warning
        case .error:
            return status.negative
        case .info:
            return status.info
        }
    }
}

enum AppTextRole {
    case pagePrimary
    case pageSecondary
    case pageTertiary
    case glassPrimary
    case glassSecondary
    case glassTertiary
    case controlPrimary
    case controlSecondary
    case selectedControlPrimary
    case selectedControlSecondary
    case fieldPrimary
    case fieldSecondary
    case statusAccent
    case disabled
    case success
    case warning
    case error
    case accent
}

enum AppTypographyRole {
    case hero
    case screenTitle
    case sectionTitle
    case cardTitle
    case body
    case bodyStrong
    case caption
    case micro
    case button
    case tabLabel
    case countBadge
    case metricValue
    case metricLabel
}

enum AppTypography {
    enum Family {
        case display
        case text
    }

    static func style(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(textStyle, design: .default).weight(weight)
    }

    static func display(size: CGFloat, weight: Font.Weight = .semibold, relativeTo textStyle: Font.TextStyle = .headline) -> Font {
        customFont(family: .display, size: size, weight: weight, relativeTo: textStyle)
    }

    static func text(size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        customFont(family: .text, size: size, weight: weight, relativeTo: textStyle)
    }

    static func role(_ role: AppTypographyRole) -> Font {
        switch role {
        case .hero:
            return style(.largeTitle, weight: .semibold)
        case .screenTitle:
            return style(.largeTitle, weight: .bold)
        case .sectionTitle:
            return style(.title3, weight: .semibold)
        case .cardTitle:
            return style(.headline, weight: .semibold)
        case .body:
            return style(.body)
        case .bodyStrong:
            return style(.body, weight: .medium)
        case .caption:
            return style(.caption)
        case .micro:
            return style(.caption2)
        case .button:
            return style(.subheadline, weight: .semibold)
        case .tabLabel:
            return style(.caption, weight: .medium)
        case .countBadge:
            return style(.caption, weight: .medium)
        case .metricValue:
            return display(size: 26, weight: .semibold, relativeTo: .title2)
        case .metricLabel:
            return style(.caption2, weight: .medium)
        }
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

enum DeviceDetailTypography {
    static let deviceTitle = AppTypography.style(.headline, weight: .semibold)
    static let sectionTitle = AppTypography.style(.callout, weight: .semibold)
    static let cardTitle = AppTypography.style(.subheadline, weight: .semibold)
    static let body = AppTypography.style(.footnote)
    static let metadata = AppTypography.style(.caption)
    static let micro = AppTypography.style(.caption2)
    static let control = AppTypography.style(.caption, weight: .semibold)
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
