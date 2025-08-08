import SwiftUI
import PhotosUI
import UIKit
import CoreGraphics

struct DeviceDetailView: View {
    let device: WLEDDevice
    @ObservedObject var viewModel: DeviceControlViewModel
    let onDismiss: () -> Void

    // Color state
    @State private var selectedSolidColor: Color
    @State private var gradientStartColor: Color
    @State private var gradientEndColor: Color
    @State private var isApplying: Bool = false

    // Effects state
    @State private var selectedEffectId: Int = 0
    @State private var effectSpeed: Double = 128
    @State private var effectIntensity: Double = 128
    @State private var selectedPaletteId: Int = 0

    // Device sync (UDP) state
    @State private var udpSend: Bool = true
    @State private var udpRecv: Bool = true
    @State private var udpSendGroup: Int = 0
    @State private var udpRecvGroup: Int = 0

    // Image sampling
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var sampledPreview: Image?
    @State private var samplingTask: Task<Void, Never>? = nil

    init(device: WLEDDevice, viewModel: DeviceControlViewModel, onDismiss: @escaping () -> Void) {
        self.device = device
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedSolidColor = State(initialValue: device.currentColor)
        _gradientStartColor = State(initialValue: device.currentColor)
        _gradientEndColor = State(initialValue: device.currentColor)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        deviceHeader
                        colorSection
                        // Defer heavy sections until scrolled into view to avoid upfront cost
                        LazyAppear { gradientSection }
                        LazyAppear { effectsSection }
                        LazyAppear { deviceSyncSection }
                        LazyAppear { presetsSection }
                        LazyAppear { groupApplySection }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { onDismiss() }
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Reduce background work while on heavy detail view
            WLEDConnectionMonitor.shared.pauseMonitoring()
            // Initialize UDP settings from state if available
            if let udp = device.state?.udpSync {
                udpSend = udp.send ?? udpSend
                udpRecv = udp.recv ?? udpRecv
                udpSendGroup = udp.sgrp ?? udpSendGroup
                udpRecvGroup = udp.rgrp ?? udpRecvGroup
            }
        }
        .onDisappear {
            // Release memory-heavy resources when leaving the screen
            samplingTask?.cancel()
            samplingTask = nil
            sampledPreview = nil
            selectedPhotoItem = nil
            // Resume background monitoring
            WLEDConnectionMonitor.shared.resumeMonitoring()
        }
    }

    // MARK: - Sections

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.title3).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(device.ipAddress)
                        .font(.caption).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.isOnline ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(device.isOnline ? "Online" : "Offline")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(device.isOnline ? .green : .red)
                }
            }

            HStack(spacing: 12) {
                Button(action: { viewModel.connectRealTimeForDevice(device) }) {
                    labelButton(icon: "bolt.horizontal.circle", title: "Real-Time")
                }
                Button(action: { Task { await viewModel.forceReconnection(device) } }) {
                    labelButton(icon: "arrow.clockwise.circle", title: "Reconnect")
                }
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private func labelButton(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.white)
            Text(title)
                .foregroundColor(.white)
                .font(.subheadline).fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3)))
        .cornerRadius(10)
    }

    private func applyButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        }
        .buttonStyle(.plain)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(.white)

            // Solid color picker + quick chips
            HStack(spacing: 12) {
                ColorPicker("", selection: $selectedSolidColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3)))

                ForEach(quickColors.indices, id: \.self) { index in
                    let color = quickColors[index]
                    Button { selectedSolidColor = color } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color)
                            .frame(width: 36, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                applyButton(title: "Apply") {
                    Task { await applySolidColor() }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var gradientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gradient Color Bar")
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(.white)

            // Gradient preview bar with two stops editable
            VStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.18))
                        )
                        .frame(height: 25)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [gradientStartColor, gradientEndColor], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 25)
                }

                HStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Text("Start").font(.caption).foregroundColor(.gray)
                        ColorPicker("", selection: $gradientStartColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3)))
                    }
                    VStack(spacing: 8) {
                        Text("End").font(.caption).foregroundColor(.gray)
                        ColorPicker("", selection: $gradientEndColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3)))
                    }

                    Spacer()

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundColor(.white)
                            Text("From Image")
                                .foregroundColor(.white)
                                .font(.subheadline).fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3)))
                        .cornerRadius(10)
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        samplingTask?.cancel()
                        samplingTask = Task { await sampleColors(from: newItem) }
                    }

                    applyButton(title: "Apply") {
                        Task { await applyGradient() }
                    }
                }

                if let preview = sampledPreview {
                    HStack(spacing: 12) {
                        preview
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipped()
                            .cornerRadius(8)
                        Text("Sampled colors applied to gradient stops")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects")
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(.white)

            // Simple effect picker (subset)
            Picker("Effect", selection: $selectedEffectId) {
                ForEach(0..<sampleEffects.count, id: \.self) { index in
                    let effect = sampleEffects[index]
                    Text(effect.name).tag(effect.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Speed").font(.caption).foregroundColor(.gray)
                    Slider(value: $effectSpeed, in: 0...255)
                }
                VStack(alignment: .leading) {
                    Text("Intensity").font(.caption).foregroundColor(.gray)
                    Slider(value: $effectIntensity, in: 0...255)
                }
            }

            HStack {
                applyButton(title: "Apply Effect") {
                    Task { await applyEffect() }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var deviceSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Sync")
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(.white)

            Toggle(isOn: $udpSend) {
                Text("UDP Send").foregroundColor(.white)
            }
            Toggle(isOn: $udpRecv) {
                Text("UDP Receive").foregroundColor(.white)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Send Group").font(.caption).foregroundColor(.gray)
                    Stepper(value: $udpSendGroup, in: 0...255) {
                        Text("\(udpSendGroup)").foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Receive Group").font(.caption).foregroundColor(.gray)
                    Stepper(value: $udpRecvGroup, in: 0...255) {
                        Text("\(udpRecvGroup)").foregroundColor(.white)
                    }
                }
                Spacer()
            }

            HStack {
                applyButton(title: "Apply Sync") {
                    Task { await applyUDPSync() }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach([1,2,3,4,5], id: \.self) { presetId in
                        Button(action: {
                            Task { await applyPreset(presetId) }
                        }) {
                            Text("Preset \(presetId)")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.black)
                                .frame(height: 36)
                                .padding(.horizontal, 12)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private var groupApplySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apply to Selected Devices")
                .font(.headline).fontWeight(.semibold)
                .foregroundColor(.white)

            HStack {
                Button(action: {
                    Task { await applyColorToSelectedDevices() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundColor(.white)
                        Text("Apply Current Color")
                            .foregroundColor(.white)
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3)))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - Actions

    private func applySolidColor() async {
        guard device.isOnline else { return }
        await viewModel.updateDeviceColor(device, color: selectedSolidColor)
    }

    private func applyGradient() async {
        guard device.isOnline else { return }
        let rgbStops = [gradientStartColor.toRGBArray(), gradientEndColor.toRGBArray()]
        let segment = SegmentUpdate(id: 0, col: rgbStops)
        let update = WLEDStateUpdate(seg: [segment])
        do {
            _ = try await WLEDAPIService.shared.updateState(for: device, state: update)
        } catch {
            print("Failed to apply gradient: \(error)")
        }
    }

    private func applyEffect() async {
        guard device.isOnline else { return }
        do {
            _ = try await WLEDAPIService.shared.setEffect(
                selectedEffectId,
                forSegment: 0,
                speed: Int(effectSpeed),
                intensity: Int(effectIntensity),
                palette: selectedPaletteId,
                device: device
            )
        } catch {
            print("Failed to apply effect: \(error)")
        }
    }

    private func applyUDPSync() async {
        let udp = UDPSyncUpdate(send: udpSend, recv: udpRecv, sgrp: udpSendGroup, rgrp: udpRecvGroup)
        let update = WLEDStateUpdate(udpn: udp)
        do {
            _ = try await WLEDAPIService.shared.updateState(for: device, state: update)
        } catch {
            print("Failed to apply UDP sync: \(error)")
        }
    }

    private func applyPreset(_ id: Int) async {
        guard device.isOnline else { return }
        do {
            _ = try await WLEDAPIService.shared.applyPreset(id, to: device, transition: 20)
        } catch {
            print("Failed to apply preset: \(error)")
        }
    }

    private func applyColorToSelectedDevices() async {
        guard !viewModel.selectedDevices.isEmpty else { return }
        await viewModel.batchSetColor(selectedSolidColor)
    }

    // MARK: - Helpers

    private var quickColors: [Color] {
        [.red, .orange, .yellow, .green, .blue, .purple, .pink, .white]
    }

    private var sampleEffects: [(id: Int, name: String)] {
        [
            (0, "Solid"),
            (1, "Blink"),
            (3, "Breathe"),
            (8, "Color Wipe"),
            (11, "Rainbow"),
            (13, "Candle"),
            (45, "Fireworks")
        ]
    }

    private func sampleColors(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            // Prefer file URL to avoid loading entire image into memory
            if let url = try await item.loadTransferable(type: URL.self) {
                try await processImage(at: url)
            } else if let data = try await item.loadTransferable(type: Data.self) {
                // Fallback: Data, but immediately downsample inside an autoreleasepool
                try await processImage(from: data)
            }
        } catch {
            print("Image sampling failed: \(error)")
        }
    }

    // MARK: - Image processing helpers
    private func processImage(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let opts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
                    guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { cont.resume(returning: ()); return }
                    let thumbOpts: CFDictionary = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: 128
                    ] as CFDictionary
                    guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { cont.resume(returning: ()); return }
                    let left = self.averageColor(in: thumb, rectFraction: CGRect(x: 0, y: 0, width: 0.5, height: 1))
                    let right = self.averageColor(in: thumb, rectFraction: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
                    DispatchQueue.main.async {
                        if let l = left { self.gradientStartColor = l }
                        if let r = right { self.gradientEndColor = r }
                        self.sampledPreview = Image(decorative: thumb, scale: 1.0)
                        cont.resume(returning: ())
                    }
                }
            }
        }
    }

    private func processImage(from data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let opts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
                    guard let src = CGImageSourceCreateWithData(data as NSData, opts) else { cont.resume(returning: ()); return }
                    let thumbOpts: CFDictionary = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceThumbnailMaxPixelSize: 128
                    ] as CFDictionary
                    guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { cont.resume(returning: ()); return }
                    let left = self.averageColor(in: thumb, rectFraction: CGRect(x: 0, y: 0, width: 0.5, height: 1))
                    let right = self.averageColor(in: thumb, rectFraction: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
                    DispatchQueue.main.async {
                        if let l = left { self.gradientStartColor = l }
                        if let r = right { self.gradientEndColor = r }
                        self.sampledPreview = Image(decorative: thumb, scale: 1.0)
                        cont.resume(returning: ())
                    }
                }
            }
        }
    }

    // Compute average color by rendering the region into a tiny buffer (e.g., 32x32)
    private func averageColor(in cgImage: CGImage, rectFraction: CGRect, sampleSize: Int = 32) -> Color? {
        let imgW = cgImage.width
        let imgH = cgImage.height
        let cropRect = CGRect(
            x: rectFraction.origin.x * CGFloat(imgW),
            y: rectFraction.origin.y * CGFloat(imgH),
            width: rectFraction.size.width * CGFloat(imgW),
            height: rectFraction.size.height * CGFloat(imgH)
        ).integral
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * sampleSize
        let bitsPerComponent = 8

        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        guard let dataPtr = context.data else { return nil }
        let buffer = dataPtr.bindMemory(to: UInt8.self, capacity: sampleSize * sampleSize * bytesPerPixel)

        var rTotal: Int = 0, gTotal: Int = 0, bTotal: Int = 0
        var idx = 0
        let pixelCount = sampleSize * sampleSize
        for _ in 0..<pixelCount {
            rTotal += Int(buffer[idx])
            gTotal += Int(buffer[idx + 1])
            bTotal += Int(buffer[idx + 2])
            idx += 4
        }
        guard pixelCount > 0 else { return nil }
        let rAvg = Double(rTotal) / Double(pixelCount) / 255.0
        let gAvg = Double(gTotal) / Double(pixelCount) / 255.0
        let bAvg = Double(bTotal) / Double(pixelCount) / 255.0
        return Color(red: rAvg, green: gAvg, blue: bAvg)
    }
}

import SwiftUI



// MARK: - LazyAppear helper
fileprivate struct LazyAppear<Content: View>: View {
    @State private var isVisible: Bool = false
    let content: () -> Content
    
    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        Group {
            if isVisible {
                content()
            } else {
                // Lightweight placeholder to keep layout height reasonable
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 1)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
