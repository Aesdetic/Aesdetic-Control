import Foundation

actor ColorPipeline {
    private let api: WLEDAPIService
    private var uploadingPixels: Set<String> = []
    private var pendingBri: [String: Int] = [:]

    init(api: WLEDAPIService = .shared) {
        self.api = api
    }

    private func flushPendingBrightness(_ device: WLEDDevice) async {
        if let v = pendingBri.removeValue(forKey: device.id) {
            let st = WLEDStateUpdate(on: true, bri: max(0, min(255, v)))
            _ = try? await api.updateState(for: device, state: st)
        }
    }

    // Public wrappers for runners
    func enqueuePendingBrightness(_ device: WLEDDevice, _ bri: Int) async {
        pendingBri[device.id] = bri
    }

    func flushPendingBrightnessPublic(_ device: WLEDDevice) async {
        await flushPendingBrightness(device)
    }

    func apply(_ intent: ColorIntent, to device: WLEDDevice) async {
        switch intent.mode {
        case .solid:
            // brightness-only fast path
            if let bri = intent.brightness, intent.solidRGB == nil, intent.perLEDHex == nil, intent.effectId == nil, intent.paletteId == nil {
                if uploadingPixels.contains(device.id) {
                    pendingBri[device.id] = bri
                    return
                } else {
                    _ = try? await api.setBrightness(for: device, brightness: bri)
                    return
                }
            }
            if let rgb = intent.solidRGB {
                // Log the exact color data being sent
                if rgb.count == 5 {
                    let ww = rgb[3]
                    let cw = rgb[4]
                    let totalWhite = ww + cw
                    
                    // Estimate power comparison (simplified)
                    // RGB mixing for white typically uses ~70% of max power per channel
                    // Dedicated WW/CW uses ~50% of max power per channel (more efficient)
                    let estimatedRGBPower = Int(Double(totalWhite) * 0.7)
                    let estimatedWWCWPower = Int(Double(totalWhite) * 0.5)
                    let powerSavings = estimatedRGBPower - estimatedWWCWPower
                    let efficiencyGain = powerSavings > 0 ? Int((Double(powerSavings) / Double(estimatedRGBPower)) * 100) : 0
                    
                    print("📡 ColorPipeline → WLED RGBWW: [\(rgb[0]), \(rgb[1]), \(rgb[2]), \(rgb[3]), \(rgb[4])]")
                    print("   ⚡ Using dedicated WW/CW LEDs: ~\(efficiencyGain)% more efficient than RGB mixing")
                    print("   💡 Brightness: ~\(totalWhite) | Est. power: \(estimatedWWCWPower) vs RGB: \(estimatedRGBPower)")
                } else if rgb.count == 3 {
                    let totalBrightness = rgb[0] + rgb[1] + rgb[2]
                    print("📡 ColorPipeline → WLED RGB: [\(rgb[0]), \(rgb[1]), \(rgb[2])]")
                    print("   🎨 Using RGB LEDs | Total brightness: ~\(totalBrightness)")
                } else {
                    print("📡 ColorPipeline → WLED: \(rgb)")
                }
                _ = try? await api.setColor(for: device, color: rgb)
            }
        case .perLED:
            if let frame = intent.perLEDHex {
                uploadingPixels.insert(device.id)
                defer { uploadingPixels.remove(device.id) }
                try? await api.setSegmentPixels(
                    for: device,
                    segmentId: intent.segmentId,
                    startIndex: 0,
                    hexColors: frame,
                    afterChunk: { [weak self] in
                        guard let self = self else { return }
                        await self.flushPendingBrightness(device)
                    }
                )
                // Final flush after upload completes
                await flushPendingBrightness(device)
            }
        case .palette:
            // Minimal placeholder: rely on higher-level service methods for now
            // Effect/palette combo typically done via updateState
            break
        }
    }

    func cancelUploads(for deviceId: String) {
        // Placeholder for future cooperative cancellation
    }
}


