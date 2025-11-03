import SwiftUI

/// Full-screen liquid glass overlay approximating Apple's modern iOS glass style.
/// Blur is optional; when disabled, the overlay provides sheen, soft-light depth,
/// and vignette without applying a material blur.
struct LiquidGlassOverlay: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// 0.0 disables blur entirely; values 0.3–0.9 apply system blur at given opacity
    var blurOpacity: Double = 0.0
    var highlightOpacity: Double = 0.14
    var verticalTopOpacity: Double = 0.06
    var verticalBottomOpacity: Double = 0.06
    var vignetteOpacity: Double = 0.06
    var centerSheenOpacity: Double = 0.0

    var body: some View {
        let contrastMultiplier: Double = colorSchemeContrast == .increased ? 1.6 : 1.0
        let highlight = min(1.0, highlightOpacity * contrastMultiplier)
        let verticalTop = min(1.0, verticalTopOpacity * contrastMultiplier)
        let verticalBottom = min(1.0, verticalBottomOpacity * contrastMultiplier)
        let vignette = min(1.0, vignetteOpacity * contrastMultiplier)
        let sheen = min(1.0, centerSheenOpacity * contrastMultiplier)
        let blurAmount = colorSchemeContrast == .increased ? min(1.0, blurOpacity + 0.2) : blurOpacity
        let increasedBackdrop = colorSchemeContrast == .increased ? Color.black.opacity(0.2) : .clear
        let neutralBackdrop = Color.black.opacity(colorSchemeContrast == .increased ? 0.35 : 0.0)
        let primaryBackdrop = LinearGradient(colors: [increasedBackdrop, neutralBackdrop], startPoint: .top, endPoint: .bottom)
        
        ZStack {
            if colorSchemeContrast == .increased {
                primaryBackdrop
                    .ignoresSafeArea()
            }
            // Optional native blur/material
            if blurAmount > 0.0 {
                Color.clear
                    .background(.ultraThinMaterial)
                    .opacity(blurAmount)
                    .ignoresSafeArea()
            }

            // Soft top-left highlight sheen
            LinearGradient(
                colors: [
                    Color.white.opacity(highlight),
                    Color.white.opacity(highlight * 0.45),
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
                    Color.white.opacity(verticalTop),
                    .clear,
                    Color.black.opacity(verticalBottom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)
            .ignoresSafeArea()

            // Very subtle edge vignette to keep text contrast near borders
            RadialGradient(
                colors: [Color.black.opacity(vignette), .clear],
                center: .center,
                startRadius: 400,
                endRadius: 1200
            )
            .blendMode(.softLight)
            .ignoresSafeArea()

            // Optional center sheen to amplify the liquid glass look
            if sheen > 0.0 {
                RadialGradient(
                    colors: [Color.white.opacity(sheen), .clear],
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


