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
                        // Active: premium liquid glass with layered materials and gentle tint
                        shape
                            .fill(Color.white.opacity(0.66))
                            .overlay(shape.fill(.ultraThinMaterial.opacity(0.35)))
                            // Subtle specular highlight from top-left
                            .overlay(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), Color.white.opacity(0.10), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                                .clipShape(shape)
                            )
                            // Optional tint bloom to inherit device/section color
                            .overlay(
                                Group {
                                    if let tint = tint {
                                        LinearGradient(
                                            colors: [tint.opacity(0.22), tint.opacity(0.12)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        .blendMode(.overlay)
                                        .clipShape(shape)
                                    }
                                }
                            )
                    } else {
                        // Inactive: faint glassy presence without heavy material
                        shape
                            .fill(Color.white.opacity(0.06))
                    }
                }
            )
            .overlay(
                // Outer edge light or outline depending on state
                Group {
                    if active {
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    } else {
                        shape
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            .blendMode(.overlay)
                    }
                }
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
            // Soft drop shadow for elevation
            .shadow(color: .black.opacity(active ? 0.22 : 0.06), radius: active ? 16 : 8, x: 0, y: active ? 8 : 2)
            // Optional tint glow for vivid feel (very subtle)
            .shadow(color: (tint ?? .clear).opacity(active ? 0.18 : 0.06), radius: active ? 10 : 6, x: 0, y: 0)
    }
}

extension View {
    func liquidGlassButton(cornerRadius: CGFloat = 20, active: Bool, tint: Color? = nil) -> some View {
        modifier(LiquidGlassButtonStyle(cornerRadius: cornerRadius, active: active, tint: tint))
    }
}


