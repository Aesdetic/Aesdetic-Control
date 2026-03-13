import SwiftUI
import UIKit

struct AppBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                neutralGlassLayer(width: width, height: height)

                NoiseTexture()
                    .opacity(0.02)
                    .blendMode(.overlay)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
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
                    Color.white.opacity(0.24),
                    .clear
                ]),
                center: UnitPoint(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: width * 1.05
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    .clear,
                    Color.black.opacity(0.05)
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
