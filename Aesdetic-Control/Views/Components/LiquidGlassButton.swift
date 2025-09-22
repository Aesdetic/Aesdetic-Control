import SwiftUI

struct LiquidGlassButtonStyle: ViewModifier {
    var cornerRadius: CGFloat = 20
    var active: Bool = false
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .padding(.horizontal, 0)
            .background(
                Group {
                    if active {
                        // Active: bright white glass, feels elevated
                        shape
                            .fill(Color.white.opacity(0.78))
                            .overlay(shape.fill(.ultraThinMaterial.opacity(0.25)))
                            .overlay(
                                Group {
                                    if let tint = tint {
                                        LinearGradient(
                                            colors: [tint.opacity(0.22), tint.opacity(0.12)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        .blendMode(.overlay)
                                    }
                                }
                            )
                    } else {
                        // Inactive: no material, fully clear fill to avoid any gray block
                        shape
                            .fill(Color.clear)
                    }
                }
            )
            .overlay(
                shape
                    .strokeBorder(
                        active ? Color.clear : Color.white.opacity(0.18),
                        lineWidth: active ? 0 : 1
                    )
                    .blendMode(.overlay)
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(active ? 0.22 : 0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .clipShape(shape)
            )
            // Ensure all backgrounds/materials are clipped strictly to the shape
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .black.opacity(active ? 0.25 : 0.06), radius: active ? 16 : 8, x: 0, y: active ? 8 : 2)
    }
}

extension View {
    func liquidGlassButton(cornerRadius: CGFloat = 20, active: Bool, tint: Color? = nil) -> some View {
        modifier(LiquidGlassButtonStyle(cornerRadius: cornerRadius, active: active, tint: tint))
    }
}


