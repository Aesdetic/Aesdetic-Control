import Foundation
import SwiftUI

actor GradientTransitionRunner {
    private var cancelIds: Set<String> = []
    private var runningDeviceIds: Set<String> = []
    private let pipeline: ColorPipeline

    init(pipeline: ColorPipeline) {
        self.pipeline = pipeline
    }

    func cancel(deviceId: String) {
        if runningDeviceIds.contains(deviceId) {
            cancelIds.insert(deviceId)
        } else {
            cancelIds.remove(deviceId)
        }
    }

    func start(
        device: WLEDDevice,
        from: LEDGradient,
        to: LEDGradient,
        durationSec: Double,
        fps: Int = 60,
        segmentId: Int = 0,
        onProgress: ((Double) -> Void)? = nil
    ) async {
        await start(
            device: device,
            from: from,
            to: to,
            durationSec: durationSec,
            fps: fps,
            segmentId: segmentId,
            aBrightness: nil,
            bBrightness: nil,
            onProgress: onProgress
        )
    }
    
    func start(
        device: WLEDDevice,
        from: LEDGradient,
        to: LEDGradient,
        durationSec: Double,
        fps: Int = 60,
        segmentId: Int = 0,
        aBrightness: Int?,
        bBrightness: Int?,
        onProgress: ((Double) -> Void)? = nil
    ) async {
        cancelIds.remove(device.id)
        while runningDeviceIds.contains(device.id) {
            await Task.yield()
        }
        runningDeviceIds.insert(device.id)

        let total = max(0.1, durationSec)
        let ledCount = device.state?.segments.first?.len ?? 120
        let frameInterval = 1.0 / Double(max(fps, 1))
        let start = Date()
        defer {
            runningDeviceIds.remove(device.id)
            cancelIds.remove(device.id)
        }

        while true {
            if cancelIds.contains(device.id) { break }
            if Task.isCancelled { break }

            let elapsed = Date().timeIntervalSince(start)
            let tLinear = min(1.0, max(0.0, elapsed / total))
            let t = (tLinear < 0.5)
                ? (4.0 * tLinear * tLinear * tLinear)
                : (1.0 - pow(-2.0 * tLinear + 2.0, 3.0) / 2.0)

            let interpStops = interpolateStops(from: from, to: to, t: t)
            let g = LEDGradient(stops: interpStops)
            let hex = GradientSampler.sample(g, ledCount: ledCount, gamma: 2.2)

            var intent = ColorIntent(deviceId: device.id, mode: .perLED)
            intent.segmentId = segmentId
            intent.perLEDHex = hex
            
            // Handle brightness tweening if brightness values are provided
            if let aBright = aBrightness, let bBright = bBrightness {
                let interpBrightness = Int(round(Double(aBright) * (1.0 - t) + Double(bBright) * t))
                intent.brightness = interpBrightness
                
                // Use the pipeline's brightness handling
                await pipeline.enqueuePendingBrightness(device, interpBrightness)
                await pipeline.flushPendingBrightnessPublic(device)
            }
            
            await pipeline.apply(intent, to: device)

            onProgress?(t)

            if t >= 1.0 { break }
            await Task.yield()
            let ns = UInt64(frameInterval * 1_000_000_000.0)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private func interpolateStops(from: LEDGradient, to: LEDGradient, t: Double) -> [GradientStop] {
        let a = from.stops.sorted { $0.position < $1.position }
        let b = to.stops.sorted { $0.position < $1.position }
        let count = max(a.count, b.count, 2)
        let denom = Double(max(1, count - 1))
        let positions = (0..<count).map { Double($0) / denom }

        func colorAt(_ stops: [GradientStop], _ pos: Double) -> Color {
            GradientSampler.sampleColor(at: pos, stops: stops)
        }

        return positions.map { pos in
            let ca = colorAt(a, pos).toRGBArray()
            let cb = colorAt(b, pos).toRGBArray()
            let r = Int(round(Double(ca[0]) * (1.0 - t) + Double(cb[0]) * t))
            let g = Int(round(Double(ca[1]) * (1.0 - t) + Double(cb[1]) * t))
            let b = Int(round(Double(ca[2]) * (1.0 - t) + Double(cb[2]) * t))
            let mixed = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
            return GradientStop(position: pos, hexColor: mixed.toHex())
        }
    }
}


