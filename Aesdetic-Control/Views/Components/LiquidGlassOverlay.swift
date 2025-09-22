import SwiftUI

/// Full-screen liquid glass overlay approximating Apple's modern iOS glass style.
/// Blur is optional; when disabled, the overlay provides sheen, soft-light depth,
/// and vignette without applying a material blur.
struct LiquidGlassOverlay: View {
    /// 0.0 disables blur entirely; values 0.3–0.9 apply system blur at given opacity
    var blurOpacity: Double = 0.0
    var highlightOpacity: Double = 0.14
    var verticalTopOpacity: Double = 0.06
    var verticalBottomOpacity: Double = 0.06
    var vignetteOpacity: Double = 0.06
    var centerSheenOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Optional native blur/material
            if blurOpacity > 0.0 {
                Color.clear
                    .background(.ultraThinMaterial)
                    .opacity(blurOpacity)
                    .ignoresSafeArea()
            }

            // Soft top-left highlight sheen
            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.white.opacity(highlightOpacity * 0.45),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .blendMode(.overlay)
            .ignoresSafeArea()

            // Gentle vertical soft-light to add depth without darkening too much
            LinearGradient(
                colors: [
                    Color.white.opacity(verticalTopOpacity),
                    .clear,
                    Color.black.opacity(verticalBottomOpacity)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)
            .ignoresSafeArea()

            // Very subtle edge vignette to keep text contrast near borders
            RadialGradient(
                colors: [Color.black.opacity(vignetteOpacity), .clear],
                center: .center,
                startRadius: 400,
                endRadius: 1200
            )
            .blendMode(.softLight)
            .ignoresSafeArea()

            // Optional center sheen to amplify the liquid glass look
            if centerSheenOpacity > 0.0 {
                RadialGradient(
                    colors: [Color.white.opacity(centerSheenOpacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 600
                )
                .blendMode(.overlay)
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
    }
}


