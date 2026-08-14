import SwiftUI
import UIKit

struct AppBackground: View {
    @AppStorage(AppBackgroundPreference.selectedChoiceKey) private var selectedBackground = AppBackgroundChoice.defaultChoice.rawValue
    @AppStorage(AppBackgroundPreference.customVersionKey) private var customBackgroundVersion: Double = 0
    @AppStorage(AppBackgroundPreference.blurEnabledKey) private var backgroundBlurEnabled = AppBackgroundPreference.defaultBlurEnabled
    @AppStorage(AppBackgroundPreference.blurIntensityKey) private var backgroundBlurIntensity = AppBackgroundPreference.defaultBlurIntensity
    @State private var loadedPhotoID: String?
    @State private var loadedPhotoImage: UIImage?
    var includePhoto: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let backgroundChoice = resolvedBackgroundChoice
            let photoID = photoLoadID(for: backgroundChoice)

            ZStack {
                // Always render a full-canvas base first, so we never fall through to
                // an opaque system/window color during transient layout passes.
                neutralGlassLayer(width: width, height: height)

                if includePhoto,
                   backgroundChoice.usesPhotoLayer,
                   loadedPhotoID == photoID,
                   let backgroundImage = loadedPhotoImage {
                    photoLayer(
                        image: backgroundImage,
                        width: width,
                        height: height,
                        usesMaterialOverlay: backgroundChoice != .custom
                    )
                }
            }
            .task(id: photoID) {
                await loadPhotoIfNeeded(for: backgroundChoice, photoID: photoID)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var resolvedBackgroundChoice: AppBackgroundChoice {
        let choice = AppBackgroundChoice(rawValue: selectedBackground) ?? .defaultChoice
        if choice == .custom && !AppBackgroundPreference.customBackgroundExists {
            return .defaultChoice
        }
        _ = customBackgroundVersion
        return choice
    }

    private func photoLoadID(for choice: AppBackgroundChoice) -> String {
        guard includePhoto, choice.usesPhotoLayer else { return "none" }
        if choice == .custom {
            return "\(choice.rawValue)-\(customBackgroundVersion)"
        }
        return choice.rawValue
    }

    @MainActor
    private func loadPhotoIfNeeded(for choice: AppBackgroundChoice, photoID: String) async {
        guard includePhoto, choice.usesPhotoLayer else {
            loadedPhotoID = photoID
            loadedPhotoImage = nil
            return
        }
        guard loadedPhotoID != photoID || loadedPhotoImage == nil else { return }

        loadedPhotoImage = AppBackgroundPreference.image(for: choice)
        loadedPhotoID = photoID
    }

    private func photoLayer(
        image: UIImage,
        width: CGFloat,
        height: CGFloat,
        usesMaterialOverlay: Bool
    ) -> some View {
        let vignetteOuterRadius = max(width, height) * 0.96
        let blurRadius = backgroundBlurEnabled
            ? AppBackgroundPreference.blurRadius(for: backgroundBlurIntensity)
            : 0
        let minimumDimension = max(1, min(width, height))
        let photoOverscanScale = 1 + ((2 * blurRadius) / minimumDimension)

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .saturation(0.92)
                .contrast(1.02)
                .scaleEffect(photoOverscanScale)
                .blur(radius: blurRadius, opaque: true)
                .frame(width: width, height: height)
                .clipped()
                .ignoresSafeArea()

            if usesMaterialOverlay {
                // Subtle global backdrop blur over bundled photos (less intense than setup overlay).
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.16)
                    .ignoresSafeArea()
            }

            photoLegibilityScrim

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.07)
                ]),
                center: .center,
                startRadius: width * 0.22,
                endRadius: vignetteOuterRadius
            )
            .ignoresSafeArea()
        }
    }

    private var photoLegibilityScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.20), location: 0.00),
                .init(color: Color.black.opacity(0.12), location: 0.16),
                .init(color: Color.black.opacity(0.04), location: 0.38),
                .init(color: Color.black.opacity(0.03), location: 0.64),
                .init(color: Color.black.opacity(0.12), location: 0.88),
                .init(color: Color.black.opacity(0.18), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.multiply)
        .ignoresSafeArea()
    }

    private func neutralGlassLayer(width: CGFloat, height: CGFloat) -> some View {
        // Keep the 03C composition mapped to the full portrait canvas.
        // Radii are width-based to avoid zoom-like scaling across tab containers.
        let topLeftRadius = width * 0.92
        let topRightRadius = width * 0.88
        let midLeftRadius = width * 0.78
        let centerRadius = width * 0.86
        let lowerLeftRadius = width * 0.74
        let bottomRightRadius = width * 1.02
        let vignetteOuterRadius = max(width, height) * 0.96

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.953, green: 0.949, blue: 0.941),
                    Color(red: 0.922, green: 0.906, blue: 0.886)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Portrait-optimized blob layout (tuned for vertical screens)
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.835, green: 0.804, blue: 0.768).opacity(0.62), location: 0.0),
                    .init(color: Color(red: 0.867, green: 0.839, blue: 0.804).opacity(0.0), location: 0.6)
                ]),
                center: UnitPoint(x: 0.18, y: 0.16),
                startRadius: 0,
                endRadius: topLeftRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.825, green: 0.799, blue: 0.765).opacity(0.42), location: 0.0),
                    .init(color: Color(red: 0.825, green: 0.799, blue: 0.765).opacity(0.0), location: 0.65)
                ]),
                center: UnitPoint(x: 0.22, y: 0.42),
                startRadius: 0,
                endRadius: midLeftRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.742, green: 0.769, blue: 0.792).opacity(0.56), location: 0.0),
                    .init(color: Color(red: 0.788, green: 0.812, blue: 0.831).opacity(0.0), location: 0.6)
                ]),
                center: UnitPoint(x: 0.78, y: 0.18),
                startRadius: 0,
                endRadius: topRightRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.809, green: 0.791, blue: 0.760).opacity(0.34), location: 0.0),
                    .init(color: Color(red: 0.809, green: 0.791, blue: 0.760).opacity(0.0), location: 0.66)
                ]),
                center: UnitPoint(x: 0.52, y: 0.56),
                startRadius: 0,
                endRadius: centerRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.834, green: 0.813, blue: 0.785).opacity(0.30), location: 0.0),
                    .init(color: Color(red: 0.834, green: 0.813, blue: 0.785).opacity(0.0), location: 0.68)
                ]),
                center: UnitPoint(x: 0.22, y: 0.86),
                startRadius: 0,
                endRadius: lowerLeftRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.815, green: 0.793, blue: 0.764).opacity(0.56), location: 0.0),
                    .init(color: Color(red: 0.847, green: 0.827, blue: 0.800).opacity(0.0), location: 0.6)
                ]),
                center: UnitPoint(x: 0.84, y: 0.92),
                startRadius: 0,
                endRadius: bottomRightRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.11)
                ]),
                center: .center,
                startRadius: width * 0.22,
                endRadius: vignetteOuterRadius
            )
            .blendMode(.multiply)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.06),
                    .clear
                ]),
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: width * 1.05
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.015),
                    .clear,
                    Color.black.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)
        }
    }

}

private struct NoiseTexture: View {
    private static let image = NoiseTexture.makeImage()

    var body: some View {
        Image(uiImage: Self.image)
            .resizable()
            .scaledToFill()
    }

    private static func makeImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.setFillColor(UIColor(white: 1.0, alpha: 1.0).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            let count = Int(size.width * size.height * 1.5)
            for _ in 0..<count {
                let gray = CGFloat(Int.random(in: 0...255)) / 255.0
                let alpha = CGFloat.random(in: 0.06...0.2)
                ctx.setFillColor(UIColor(white: gray, alpha: alpha).cgColor)
                let x = Int.random(in: 0..<Int(size.width))
                let y = Int.random(in: 0..<Int(size.height))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }
}
