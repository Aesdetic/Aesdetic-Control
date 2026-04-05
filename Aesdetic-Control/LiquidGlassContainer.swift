import SwiftUI

struct LiquidGlassBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil

    enum Clarity {
        case standard
        case clear
    }

    var clarity: Clarity = .standard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        // Opacity tuning based on clarity and contrast
        let baseOpacity: Double
        let materialOpacity: Double
        let strokeTopOpacity: Double
        let strokeBottomOpacity: Double
        let specularTopOpacity: Double
        let specularMidOpacity: Double
        let topSheenOpacity: Double

        if contrast == .increased {
            switch clarity {
            case .standard:
                baseOpacity = 0.18
                materialOpacity = 0.40
                strokeTopOpacity = 0.30
                strokeBottomOpacity = 0.11
                specularTopOpacity = 0.20
                specularMidOpacity = 0.07
                topSheenOpacity = 0.11
            case .clear:
                baseOpacity = 0.09
                materialOpacity = 0.23
                strokeTopOpacity = 0.24
                strokeBottomOpacity = 0.09
                specularTopOpacity = 0.11
                specularMidOpacity = 0.05
                topSheenOpacity = 0.07
            }
        } else {
            switch clarity {
            case .standard:
                baseOpacity = 0.10
                materialOpacity = 0.28
                strokeTopOpacity = 0.28
                strokeBottomOpacity = 0.10
                specularTopOpacity = 0.18
                specularMidOpacity = 0.07
                topSheenOpacity = 0.09
            case .clear:
                baseOpacity = 0.04
                materialOpacity = 0.15
                strokeTopOpacity = 0.20
                strokeBottomOpacity = 0.07
                specularTopOpacity = 0.08
                specularMidOpacity = 0.03
                topSheenOpacity = 0.05
            }
        }

        return shape
            .fill(Color.white.opacity(baseOpacity))
            .overlay(
                shape.fill(.ultraThinMaterial.opacity(materialOpacity))
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(specularTopOpacity), Color.white.opacity(specularMidOpacity), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                ).clipShape(shape)
            )
            .overlay(
                Group {
                    if let tint {
                        LinearGradient(
                            colors: [tint.opacity(clarity == .clear ? 0.14 : 0.20), tint.opacity(clarity == .clear ? 0.06 : 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.overlay)
                        .clipShape(shape)
                    }
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(strokeTopOpacity), Color.white.opacity(strokeBottomOpacity)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(topSheenOpacity), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(shape)
            )
            .clipShape(shape)
            .compositingGroup()
            .shadow(
                color: .black.opacity(contrast == .increased ? (clarity == .clear ? 0.18 : 0.22) : (clarity == .clear ? 0.10 : 0.12)),
                radius: contrast == .increased ? (clarity == .clear ? 14 : 16) : (clarity == .clear ? 10 : 12),
                x: 0,
                y: contrast == .increased ? (clarity == .clear ? 7 : 8) : (clarity == .clear ? 5 : 6)
            )
    }
}
