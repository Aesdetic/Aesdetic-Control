import SwiftUI
import UIKit

struct AppBackground: View {
    @State private var currentTime = Date()
    private let dayStartHour = 6
    private let nightStartHour = 19
    private let forceDarkMode = true
    private let updateTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let maxDimension = max(proxy.size.width, proxy.size.height)
            let isNight = forceDarkMode ? true : isNightTime(currentTime)

            ZStack {
                lightLayer(maxDimension: maxDimension)

                darkLayer(maxDimension: maxDimension)
                    .opacity(isNight ? 1 : 0)
                    .animation(.easeInOut(duration: 4.0), value: isNight)

                NoiseTexture()
                    .opacity(0.12)
                    .blendMode(.overlay)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .onReceive(updateTimer) { now in
            currentTime = now
        }
    }

    private func lightLayer(maxDimension: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.97, blue: 0.95), location: 0.0),
                    .init(color: Color(red: 0.99, green: 0.92, blue: 0.90), location: 0.33),
                    .init(color: Color(red: 0.90, green: 0.90, blue: 0.95), location: 1.0)
                ]),
                center: .topLeading,
                startRadius: 0,
                endRadius: maxDimension * 1.1
            )

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 1.0, green: 0.84, blue: 0.78).opacity(0.65), location: 0.0),
                    .init(color: Color(red: 1.0, green: 0.86, blue: 0.80).opacity(0.0), location: 0.7)
                ]),
                center: UnitPoint(x: 0.12, y: 0.42),
                startRadius: 0,
                endRadius: maxDimension * 0.8
            )
            .blendMode(.screen)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.95, green: 0.86, blue: 1.0).opacity(0.55), location: 0.0),
                    .init(color: Color(red: 0.95, green: 0.88, blue: 1.0).opacity(0.0), location: 0.68)
                ]),
                center: UnitPoint(x: 0.78, y: 0.38),
                startRadius: 0,
                endRadius: maxDimension * 0.75
            )
            .blendMode(.screen)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.76, green: 0.94, blue: 1.0).opacity(0.45), location: 0.0),
                    .init(color: Color(red: 0.78, green: 0.93, blue: 1.0).opacity(0.0), location: 0.7)
                ]),
                center: UnitPoint(x: 0.88, y: 0.78),
                startRadius: 0,
                endRadius: maxDimension * 0.7
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.32),
                    Color.white.opacity(0.06),
                    Color.black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.2)
                ]),
                center: .center,
                startRadius: maxDimension * 0.2,
                endRadius: maxDimension * 0.95
            )
            .blendMode(.multiply)
        }
    }

    private func darkLayer(maxDimension: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.16, green: 0.16, blue: 0.2), location: 0.0),
                    .init(color: Color(red: 0.12, green: 0.12, blue: 0.16), location: 0.45),
                    .init(color: Color(red: 0.06, green: 0.07, blue: 0.1), location: 1.0)
                ]),
                center: .topLeading,
                startRadius: 0,
                endRadius: maxDimension * 1.1
            )

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.58, green: 0.36, blue: 0.3).opacity(0.32), location: 0.0),
                    .init(color: Color(red: 0.52, green: 0.36, blue: 0.32).opacity(0.0), location: 0.7)
                ]),
                center: UnitPoint(x: 0.14, y: 0.48),
                startRadius: 0,
                endRadius: maxDimension * 0.85
            )
            .blendMode(.screen)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.38, green: 0.3, blue: 0.55).opacity(0.3), location: 0.0),
                    .init(color: Color(red: 0.34, green: 0.30, blue: 0.50).opacity(0.0), location: 0.7)
                ]),
                center: UnitPoint(x: 0.82, y: 0.42),
                startRadius: 0,
                endRadius: maxDimension * 0.8
            )
            .blendMode(.screen)

            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 0.18, green: 0.42, blue: 0.55).opacity(0.28), location: 0.0),
                    .init(color: Color(red: 0.20, green: 0.36, blue: 0.48).opacity(0.0), location: 0.7)
                ]),
                center: UnitPoint(x: 0.86, y: 0.78),
                startRadius: 0,
                endRadius: maxDimension * 0.75
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.0),
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.6)
                ]),
                center: .center,
                startRadius: maxDimension * 0.2,
                endRadius: maxDimension * 0.95
            )
            .blendMode(.multiply)
        }
    }

    private func isNightTime(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= nightStartHour || hour < dayStartHour
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
