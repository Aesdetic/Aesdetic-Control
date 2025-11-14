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
                // Pass CCT and white level if provided
                _ = try? await api.setColor(for: device, color: rgb, cct: intent.cct, white: intent.whiteLevel)
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
                    cct: intent.cct,  // Pass CCT if provided
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
        uploadingPixels.remove(deviceId)
        pendingBri.removeValue(forKey: deviceId)
    }
}


