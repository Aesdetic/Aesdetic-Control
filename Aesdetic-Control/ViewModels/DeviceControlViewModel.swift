//
//  DeviceControlViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine
import SwiftUI
import os.log

extension OSLog {
    private static var subsystem = "com.aesdetic.control"
    static let effects = OSLog(subsystem: subsystem, category: "effects")
}

struct DeviceEffectState {
    var effectId: Int
    var speed: Int
    var intensity: Int
    var paletteId: Int?  // Optional: omit when sending custom colors
    var isEnabled: Bool
    
    static let `default` = DeviceEffectState(effectId: 0, speed: 128, intensity: 128, paletteId: nil, isEnabled: false)
}

/// Metadata for native WLED transitions (on-device transitions using tt parameter)
struct NativeTransitionInfo: Equatable {
    let targetColorRGB: [Int]  // [r, g, b]
    let targetBrightness: Int
    let durationSeconds: Double
}

/// Tracks active automation/transition runs per device
struct ActiveRunStatus: Equatable {
    let id: UUID  // Unique identifier for this run
    let deviceId: String
    let kind: RunKind
    let title: String
    let startDate: Date
    var progress: Double  // 0.0 to 1.0
    let isCancellable: Bool
    let expectedEnd: Date?  // When this run is expected to complete (for native transitions)
    let nativeTransition: NativeTransitionInfo?  // Metadata for native WLED transitions
    
    enum RunKind: Equatable {
        case automation
        case transition
        case effect
        case applying  // Short-lived, no progress (preset/playlist/directState)
    }
    
    init(
        id: UUID = UUID(),
        deviceId: String,
        kind: RunKind,
        title: String,
        startDate: Date,
        progress: Double = 0.0,
        isCancellable: Bool = true,
        expectedEnd: Date? = nil,
        nativeTransition: NativeTransitionInfo? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.kind = kind
        self.title = title
        self.startDate = startDate
        self.progress = progress
        self.isCancellable = isCancellable
        self.expectedEnd = expectedEnd
        self.nativeTransition = nativeTransition
    }
    
    static func == (lhs: ActiveRunStatus, rhs: ActiveRunStatus) -> Bool {
        lhs.id == rhs.id && lhs.deviceId == rhs.deviceId && lhs.kind == rhs.kind && lhs.title == rhs.title
    }
}

@MainActor
class DeviceControlViewModel: ObservableObject {
    static let shared = DeviceControlViewModel()
    private static let maxEffectColorSlots = 3
    private let directColorTransitionSeconds: Double = 0.35
    private let directBrightnessTransitionSeconds: Double = 0.35
    private static let gradientFriendlyEffectIds: Set<Int> = [
        2,   // Breathe
        3,   // Smooth Flow
        27,  // Flow
        37,  // Loading
        46,  // Rain Fall
        47,  // Sweep
        54,  // Fog
        102, // Candle
        140, // Freqwave (audio-reactive)
        149  // Fireplace
    ]
    
    private static let fallbackGradientFriendlyEffects: [EffectMetadata] = [
        EffectMetadata(
            id: 2,
            name: "Breathe",
            description: "Breathe between gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 2
        ),
        EffectMetadata(
            id: 3,
            name: "Smooth Flow",
            description: "Smooth flow animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 27,
            name: "Flow",
            description: "Flow animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 37,
            name: "Loading",
            description: "Loading animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 46,
            name: "Rain Fall",
            description: "Rain fall animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 47,
            name: "Sweep",
            description: "Sweep animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 54,
            name: "Fog",
            description: "Fog animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 102,
            name: "Candle",
            description: "Warm candle flicker with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: true,
            isSoundReactive: false,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 140,
            name: "Freqwave",
            description: "Frequency wave visualization that maps audio frequencies to colors. Reacts to music beats and audio input.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: true,
            colorSlotCount: 3
        ),
        EffectMetadata(
            id: 149,
            name: "Fireplace",
            description: "Warm fireplace animation with gradient colors.",
            parameters: [
                EffectParameter(index: 0, label: "Effect speed", kind: .speed),
                EffectParameter(index: 1, label: "Effect intensity", kind: .intensity)
            ],
            supportsPalette: false,
            isSoundReactive: false,
            colorSlotCount: 3
        )
    ]
    
    private static func colors(for gradient: LEDGradient, slotCount: Int) -> [[Int]] {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let clampedSlots = max(1, min(maxEffectColorSlots, slotCount))
        guard !sortedStops.isEmpty else {
            return Array(repeating: [255, 255, 255], count: clampedSlots)
        }

        if clampedSlots == 1 {
            let rgb = sortedStops.first!.color.toRGBArray()
            return [[rgb[0], rgb[1], rgb[2]]]
        }

        // Prefer actual stop colors whenever possible so the effect palette matches UI stops
        if sortedStops.count >= clampedSlots {
            let maxIndex = sortedStops.count - 1
            let positions = (0..<clampedSlots).map { Double($0) / Double(clampedSlots - 1) }
            let indices = positions.map { Int(round($0 * Double(maxIndex))) }
            return indices.map { idx in
                let rgb = sortedStops[min(maxIndex, max(0, idx))].color.toRGBArray()
                return [rgb[0], rgb[1], rgb[2]]
            }
        }

        // Not enough stops to fill every slot – fall back to interpolated colors
        let positions = (0..<clampedSlots).map { Double($0) / Double(clampedSlots - 1) }
        return positions.map { t in
            let color = GradientSampler.sampleColor(at: t, stops: sortedStops, interpolation: gradient.interpolation)
            let rgb = color.toRGBArray()
            return [rgb[0], rgb[1], rgb[2]]
        }
    }

    
    // MARK: - Device Sorting
    
    enum DeviceSortOption: String, CaseIterable {
        case name = "Name"
        case location = "Location"
        case status = "Status"
        case brightness = "Brightness"
        
        var title: String {
            return self.rawValue
        }
    }
    
    enum WLEDError: Identifiable, Equatable {
        case deviceOffline(deviceName: String?)
        case timeout(deviceName: String?)
        case invalidResponse
        case apiError(message: String)
        
        var id: String {
            switch self {
            case .deviceOffline(let name):
                return "deviceOffline-\(name ?? "unknown")"
            case .timeout(let name):
                return "timeout-\(name ?? "unknown")"
            case .invalidResponse:
                return "invalidResponse"
            case .apiError(let message):
                return "apiError-\(message)"
            }
        }
        
        var message: String {
            switch self {
            case .deviceOffline(let name):
                if let name, !name.isEmpty {
                    return "\(name) is offline."
                }
                return "The device appears to be offline."
            case .timeout(let name):
                if let name, !name.isEmpty {
                    return "\(name) is not responding."
                }
                return "The device did not respond in time."
            case .invalidResponse:
                return "Received an unexpected response from WLED."
            case .apiError(let message):
                return message
            }
        }
        
        var iconName: String {
            switch self {
            case .deviceOffline:
                return "wifi.exclamationmark"
            case .timeout:
                return "clock.arrow.circlepath"
            case .invalidResponse:
                return "exclamationmark.triangle.fill"
            case .apiError:
                return "bolt.horizontal.circle.fill"
            }
        }
        
        var actionTitle: String? {
            switch self {
            case .deviceOffline, .timeout:
                return "Retry"
            case .invalidResponse, .apiError:
                return nil
            }
        }
    }
    
    @Published var sortOption: DeviceSortOption = .name
    @Published var locationFilter: DeviceLocation = .all
    @Published var selectedLocationFilter: DeviceLocation = .all
    @Published var webSocketConnectionStatus: WLEDWebSocketManager.ConnectionStatus = .disconnected
    
    // Active run tracking (automations/transitions)
    @Published var activeRunStatus: [String: ActiveRunStatus] = [:]
    private var transitionCancelLockUntil: [String: Date] = [:]
    private var savedTransitionDefaults: [String: Int?] = [:]
    private var savedTransitionDefaultRunIds: [String: UUID] = [:]
    private var playlistUnsupportedDevices: Set<String> = []
    
    // Watchdog state for monitoring stalled runs
    private struct RunWatchdog {
        var lastProgressAt: Date
        var lastProgressValue: Double
        var runStartAt: Date
    }
    private var runWatchdogs: [String: RunWatchdog] = [:]
    private var watchdogTask: Task<Void, Never>?
    
    // Watchdog constants
    private let watchdogTimeoutSeconds: TimeInterval = 10.0  // Cancel if no progress for 10 seconds
    private let watchdogCheckInterval: TimeInterval = 2.0     // Check every 2 seconds

    private func lockTransitionCancel(for deviceId: String, seconds: TimeInterval = 1.5) {
        transitionCancelLockUntil[deviceId] = Date().addingTimeInterval(seconds)
    }

    private func setTemporaryTransitionDefault(for device: WLEDDevice, deciseconds: Int, runId: UUID) async {
        if savedTransitionDefaults[device.id] == nil {
            savedTransitionDefaults[device.id] = device.state?.transitionDeciseconds
            savedTransitionDefaultRunIds[device.id] = runId
        }
        let stateUpdate = WLEDStateUpdate(transitionDeciseconds: max(0, deciseconds))
        _ = try? await apiService.updateState(for: device, state: stateUpdate)
    }

    private func restoreTransitionDefaultIfNeeded(for device: WLEDDevice, runId: UUID?) async {
        if let storedRunId = savedTransitionDefaultRunIds[device.id], let runId, storedRunId != runId {
            return
        }
        guard savedTransitionDefaults.keys.contains(device.id) else { return }
        let restoredDeciseconds = savedTransitionDefaults[device.id] ?? nil
        if let restoredDeciseconds {
            let stateUpdate = WLEDStateUpdate(transitionDeciseconds: max(0, restoredDeciseconds))
            _ = try? await apiService.updateState(for: device, state: stateUpdate)
        }
        await MainActor.run {
            if let index = devices.firstIndex(where: { $0.id == device.id }),
               let state = devices[index].state {
                devices[index].state = WLEDState(
                    brightness: state.brightness,
                    isOn: state.isOn,
                    segments: state.segments,
                    transitionDeciseconds: restoredDeciseconds,
                    presetId: state.presetId,
                    playlistId: state.playlistId
                )
            }
        }
        savedTransitionDefaults.removeValue(forKey: device.id)
        savedTransitionDefaultRunIds.removeValue(forKey: device.id)
    }
    
    // Computed filtered devices based on current filters - Optimized with memoization
    var filteredDevices: [WLEDDevice] {
        let now = Date()
        
        // Return cached result if recent enough
        if now.timeIntervalSince(lastFilterUpdate) < filterUpdateThrottle && !cachedFilteredDevices.isEmpty {
            return cachedFilteredDevices
        }
        
        // Recompute filtered devices
        var filtered = devices
        
        // Apply location filter
        if selectedLocationFilter != .all {
            filtered = filtered.filter { $0.location == selectedLocationFilter }
        }
        
        // Apply sorting
        switch sortOption {
        case .name:
            filtered = filtered.sorted { $0.name < $1.name }
        case .location:
            filtered = filtered.sorted { $0.location.displayName < $1.location.displayName }
        case .status:
            filtered = filtered.sorted { $0.isOnline && !$1.isOnline }
        case .brightness:
            filtered = filtered.sorted { $0.brightness > $1.brightness }
        }
        
        // Update cache
        cachedFilteredDevices = filtered
        lastFilterUpdate = now
        
        return filtered
    }
    
    // MARK: - State Management Optimization
    
    @Published var devices: [WLEDDevice] = [] {
        didSet {
            // Optimized: Quick check for count change first (O(1))
            guard devices.count == oldValue.count else {
                // Count changed - invalidate cache
                cachedFilteredDevices = []
                lastFilterUpdate = .distantPast
                return
            }
            
            // Only do comparison if count is same (short-circuit optimization)
            // Check if any device ID or online status changed - stops at first difference
            let hasChanges = zip(devices, oldValue).contains { $0.id != $1.id || $0.isOnline != $1.isOnline }
            if hasChanges {
                // Invalidate filter cache when devices change
                cachedFilteredDevices = []
                lastFilterUpdate = .distantPast
            }
        }
    }
    @Published var isScanning: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentError: WLEDError?
    @Published var reconnectionStatus: [String: String] = [:]
    private var allowActiveHealthChecks: Bool = false
    
    // Service dependencies
    private let apiService = WLEDAPIService.shared
    private let colorPipeline = ColorPipeline()
    private lazy var transitionRunner = GradientTransitionRunner(pipeline: colorPipeline)
    let wledService = WLEDDiscoveryService()
    private let coreDataManager = CoreDataManager.shared
    private let webSocketManager = WLEDWebSocketManager.shared
    private let connectionMonitor = WLEDConnectionMonitor.shared
    
    // Combine cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Capability Detection
    private let capabilityDetector = CapabilityDetector.shared
    
    /// Local cache of device capabilities for synchronous access from MainActor
    private var deviceCapabilities: [String: WLEDCapabilities] = [:]
    private var deviceLedCounts: [String: Int] = [:]
    
    // Effect metadata caching
    @Published private(set) var rawEffectMetadata: [String: [String]] = [:]
    @Published private(set) var effectMetadataBundles: [String: EffectMetadataBundle] = [:]
    @Published private(set) var effectStates: [String: [Int: DeviceEffectState]] = [:]
    @Published private(set) var segmentCCTFormats: [String: [Int: Bool]] = [:]
    @Published private(set) var presetsCache: [String: [WLEDPreset]] = [:]
    @Published private(set) var presetLoadingStates: [String: Bool] = [:]
    @Published private(set) var latestGradientStops: [String: [GradientStop]] = [:]
    @Published private(set) var latestEffectGradientStops: [String: [GradientStop]] = [:]
    @Published private(set) var latestTransitionDurations: [String: Double] = [:]
    private var effectMetadataLastFetched: [String: Date] = [:]
    private var lastGradientBeforeEffect: [String: [GradientStop]] = [:]
    private let effectMetadataRefreshInterval: TimeInterval = 300 // 5 minute cache
    private var ledPreferencesLastFetched: [String: Date] = [:]
    private let ledPreferencesRefreshInterval: TimeInterval = 300
    private let temperatureStopsCCTKeyPrefix = "temperatureStopsCCTEnabled."
    private let defaultCCTKelvinMin: Int = 1900
    private let defaultCCTKelvinMax: Int = 10091
    private var cctKelvinRanges: [String: ClosedRange<Int>] = [:]

    private var appManagedSegmentDevices: Set<String> = []
    private struct SegmentBounds: Equatable {
        let start: Int
        let stop: Int
    }
    private var appManagedSegmentLayouts: [String: [SegmentBounds]] = [:]
    private let defaultSegmentCount: Int = 12
    private let maxSegmentCount: Int = 16
    private let perLedFallbackLedLimit: Int = 30
    private let maxWLEDTransitionDeciseconds: Int = 65535
    private let segmentedTransitionMaxStepSeconds: Double = 60.0
    private let segmentedTransitionMinStepSeconds: Double = 5.0
    private let segmentedTransitionMaxSteps: Int = 120
    private let segmentedTransitionSleepSliceSeconds: Double = 1.0
    private let playlistLongTransitionThresholdSeconds: Double = 600.0
    private let presetSaveRetryAttempts: Int = 3
    private let presetVerifyRetryAttempts: Int = 4
    private let presetSaveDelayNanos: UInt64 = 500_000_000
    private let presetVerifyDelayNanos: UInt64 = 600_000_000
    private let playlistSaveRetryAttempts: Int = 3
    private let playlistVerifyRetryAttempts: Int = 4
    private let playlistSaveDelayNanos: UInt64 = 600_000_000
    private let playlistVerifyDelayNanos: UInt64 = 700_000_000
    private var temporaryPlaylistIds: [String: Int] = [:]
    private var temporaryPresetIds: [String: [Int]] = [:]
    
    private let gradientDefaultsPrefix = "latestGradientStops."
    private let effectGradientDefaultsPrefix = "latestEffectGradientStops."
    private let transitionDurationDefaultsPrefix = "latestTransitionDurations."
    
    // User interaction tracking for optimistic updates
    private var lastUserInput: [String: Date] = [:]
    private let userInputProtectionWindow: TimeInterval = 1.5
    
    // Brightness preservation: Store last brightness before turning off
    // This allows restoring brightness when device is turned back on
    private var lastBrightnessBeforeOff: [String: Int] = [:]
    
    private func isUnderUserControl(_ deviceId: String) -> Bool {
        guard let lastInput = lastUserInput[deviceId] else { return false }
        return Date().timeIntervalSince(lastInput) < userInputProtectionWindow
    }
    
    private func markUserInteraction(_ deviceId: String) {
        lastUserInput[deviceId] = Date()
    }

    private func clampedTransitionMs(for durationSeconds: Double?) -> Int? {
        guard let durationSeconds else { return nil }
        let ms = Int(durationSeconds * 1000.0)
        let maxMs = maxWLEDTransitionDeciseconds * 100
        return min(ms, maxMs)
    }

    private func isSolidGradient(_ gradient: LEDGradient) -> Bool {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        guard let firstHex = sortedStops.first?.hexColor else { return false }
        return sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == firstHex }
    }

    private func segmentedStepPlan(for durationSeconds: Double) -> (steps: Int, stepDuration: Double) {
        let safeDuration = max(0.1, durationSeconds)
        let idealStep = safeDuration / Double(segmentedTransitionMaxSteps)
        let clampedStep = min(segmentedTransitionMaxStepSeconds, max(segmentedTransitionMinStepSeconds, idealStep))
        let steps = max(1, Int(ceil(safeDuration / clampedStep)))
        let actualStep = safeDuration / Double(steps)
        return (steps, actualStep)
    }

    private func isRunActive(deviceId: String, runId: UUID) async -> Bool {
        await MainActor.run {
            activeRunStatus[deviceId]?.id == runId
        }
    }

    private func waitForRunContinuation(deviceId: String, runId: UUID, durationSeconds: Double) async -> Bool {
        guard durationSeconds > 0 else { return await isRunActive(deviceId: deviceId, runId: runId) }
        var remaining = durationSeconds
        let slice = min(segmentedTransitionSleepSliceSeconds, durationSeconds)
        while remaining > 0 {
            if Task.isCancelled { return false }
            let step = min(slice, remaining)
            let nanos = UInt64(step * 1_000_000_000.0)
            try? await Task.sleep(nanoseconds: nanos)
            remaining -= step
            if !(await isRunActive(deviceId: deviceId, runId: runId)) {
                return false
            }
        }
        return true
    }

    private func defaultTransitionMs(for device: WLEDDevice) -> Int? {
        if savedTransitionDefaults.keys.contains(device.id) {
            guard let deciseconds = savedTransitionDefaults[device.id] ?? nil else { return nil }
            let ms = deciseconds * 100
            let maxMs = maxWLEDTransitionDeciseconds * 100
            return min(ms, maxMs)
        }
        guard let deciseconds = device.state?.transitionDeciseconds else { return nil }
        let ms = deciseconds * 100
        let maxMs = maxWLEDTransitionDeciseconds * 100
        return min(ms, maxMs)
    }

    private func resolvedTransitionMs(for device: WLEDDevice, fallbackSeconds: Double?) -> Int? {
        if let ms = defaultTransitionMs(for: device) {
            return ms
        }
        guard let fallbackSeconds else { return nil }
        return Int(max(0, fallbackSeconds * 1000.0))
    }

    private func allowPerLedFallback(for device: WLEDDevice) -> Bool {
        let advancedEnabled = UserDefaults.standard.bool(forKey: "advancedUIEnabled")
        let perLedEnabled = UserDefaults.standard.bool(forKey: "perLedTransitionsEnabled")
        let ledCount = totalLEDCount(for: device)
        return perLedEnabled && advancedEnabled && ledCount <= perLedFallbackLedLimit
    }

    func totalLEDCount(for device: WLEDDevice) -> Int {
        let cachedCount = deviceLedCounts[device.id] ?? 0
        if let segments = device.state?.segments, !segments.isEmpty {
            if let maxStop = segments.compactMap({ $0.stop }).max(), maxStop > 0 {
                return max(maxStop, cachedCount)
            }
            let sumLen = segments.compactMap({ $0.len }).reduce(0, +)
            if sumLen > 0 {
                return max(sumLen, cachedCount)
            }
            if let firstLen = segments.first?.len, firstLen > 0 {
                return max(firstLen, cachedCount)
            }
        }
        return cachedCount > 0 ? cachedCount : 120
    }
    
    func automationGradient(for device: WLEDDevice) -> LEDGradient {
        if let cachedStops = latestGradientStops[device.id], !cachedStops.isEmpty {
            return LEDGradient(stops: cachedStops)
        }
        let hex = device.currentColor.toHex()
        return LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ])
    }
    
    func runAutomationTransition(
        for device: WLEDDevice,
        startGradient: LEDGradient,
        startBrightness: Int,
        endGradient: LEDGradient,
        endBrightness: Int,
        durationSeconds: Double,
        startStopTemperatures: [UUID: Double]? = nil,
        startStopWhiteLevels: [UUID: Double]? = nil,
        endStopTemperatures: [UUID: Double]? = nil,
        endStopWhiteLevels: [UUID: Double]? = nil,
        segmentId: Int = 0,
        automationName: String? = nil
    ) async {
        await cancelActiveTransitionIfNeeded(for: device)
        await transitionRunner.cancel(deviceId: device.id)
        
        let requestedDuration = durationSeconds
        var durationSeconds = durationSeconds
        let ledCount = totalLEDCount(for: device)
        // Use native transition up to 1 hour (policy), then clamp for manual transitions.
        let maxNativeSeconds = maxWLEDNativeTransitionSeconds
        #if DEBUG
        let startStopsCount = startGradient.stops.count
        let endStopsCount = endGradient.stops.count
        print("🔎 Transition start for \(device.name): duration=\(durationSeconds)s, maxNative=\(maxNativeSeconds)s, startStops=\(startStopsCount), endStops=\(endStopsCount)")
        #endif

        let startIsSolid = isSolidGradient(startGradient)
        let endIsSolid = isSolidGradient(endGradient)
        let requiresSegmentedStepper = !(startIsSolid && endIsSolid)
        let exceedsNativeCap = durationSeconds > maxNativeSeconds
        let usePlaylistForLongTransition = automationName == nil && durationSeconds >= playlistLongTransitionThresholdSeconds
        let useSegmentedStepper = requiresSegmentedStepper || exceedsNativeCap

        if !useSegmentedStepper, durationSeconds > maxNativeSeconds {
            #if DEBUG
            print("⚠️ Transition duration exceeds native cap for \(device.name). Capping to \(maxNativeSeconds)s (requested \(durationSeconds)s).")
            #endif
            durationSeconds = maxNativeSeconds
        }

        // Ensure realtime override is released so WLED can honor transitions.
        await apiService.releaseRealtimeOverride(for: device)

        #if DEBUG
        if usePlaylistForLongTransition {
            print("🔎 Transition path for \(device.name): playlist duration=\(requestedDuration)s threshold=\(playlistLongTransitionThresholdSeconds)s")
        } else if useSegmentedStepper {
            let reason = exceedsNativeCap ? "duration>nativeCap" : "multi-stop gradient"
            print("🔎 Transition path for \(device.name): segmented-stepper duration=\(requestedDuration)s reason=\(reason)")
        } else {
            print("🔎 Transition path for \(device.name): native-tt duration=\(durationSeconds)s")
        }
        #endif
        
        await applyGradientStopsAcrossStrip(
            device,
            stops: startGradient.stops,
            ledCount: ledCount,
            stopTemperatures: startStopTemperatures,
            stopWhiteLevels: startStopWhiteLevels,
            disableActiveEffect: true,
            segmentId: segmentId,
            interpolation: startGradient.interpolation,
            brightness: startBrightness,
            on: true,
            forceNoPerCallTransition: true,
            releaseRealtimeOverride: false,
            userInitiated: false,
            preferSegmented: true
        )
        
        // Set active run status
        let runTitle = automationName ?? "Transition"
        let startDate = Date()
        let runKind: ActiveRunStatus.RunKind = automationName != nil ? .automation : .transition
        let effectiveDuration = useSegmentedStepper ? requestedDuration : durationSeconds
        let expectedEnd = effectiveDuration > 0 ? startDate.addingTimeInterval(effectiveDuration) : nil
        let nativeTransition: NativeTransitionInfo? = (!useSegmentedStepper && endIsSolid && startIsSolid)
            ? NativeTransitionInfo(
                targetColorRGB: Color(hex: endGradient.stops.first?.hexColor ?? "#000000").toRGBArray(),
                targetBrightness: endBrightness,
                durationSeconds: durationSeconds
            )
            : nil
        #if DEBUG
        let nativeEligible = durationSeconds <= maxNativeSeconds
        print("🔎 Transition path check for \(device.name): startSolid=\(startIsSolid), endSolid=\(endIsSolid), nativeEligible=\(nativeEligible), segmented=\(useSegmentedStepper)")
        #endif
        let runId = UUID()
        await MainActor.run {
            activeRunStatus[device.id] = ActiveRunStatus(
                id: runId,
                deviceId: device.id,
                kind: runKind,
                title: runTitle,
                startDate: startDate,
                progress: 0.0,
                isCancellable: true,
                expectedEnd: expectedEnd,
                nativeTransition: nativeTransition
            )
            runWatchdogs[device.id] = RunWatchdog(
                lastProgressAt: startDate,
                lastProgressValue: 0.0,
                runStartAt: startDate
            )
            startWatchdogTaskIfNeeded()
        }

        if usePlaylistForLongTransition {
            if let playlist = await createTransitionPlaylist(
                device: device,
                from: startGradient,
                to: endGradient,
                durationSeconds: requestedDuration,
                startBrightness: startBrightness,
                endBrightness: endBrightness,
                persist: false,
                label: nil
            ),
            await startPlaylist(device: device, playlistId: playlist.playlistId) {
                #if DEBUG
                print("✅ Transition playlist started for \(device.name): playlistId=\(playlist.playlistId)")
                #endif
                await MainActor.run {
                    latestGradientStops[device.id] = endGradient.stops
                }
                return
            } else {
                #if DEBUG
                print("⚠️ Transition playlist failed for \(device.name). Falling back to stepper/native.")
                #endif
            }
        }

        if useSegmentedStepper {
            let stepPlan = segmentedStepPlan(for: effectiveDuration)
            #if DEBUG
            print("🔎 Segmented transition plan for \(device.name): steps=\(stepPlan.steps), step=\(String(format: "%.2f", stepPlan.stepDuration))s, total=\(String(format: "%.2f", effectiveDuration))s")
            #endif
            let steps = stepPlan.steps
            let stepDuration = stepPlan.stepDuration
            for step in 1...steps {
                if Task.isCancelled { break }
                if !(await isRunActive(deviceId: device.id, runId: runId)) { break }
                let t = Double(step) / Double(steps)
                let stepStops = interpolateStops(from: startGradient, to: endGradient, t: t)
                let interpBrightness = Int(round(Double(startBrightness) * (1.0 - t) + Double(endBrightness) * t))
                let stepGradient = LEDGradient(stops: stepStops, interpolation: endGradient.interpolation)
                await applySegmentedGradient(
                    device,
                    gradient: stepGradient,
                    stopTemperatures: nil,
                    stopWhiteLevels: nil,
                    brightness: interpBrightness,
                    on: true,
                    transitionDurationSeconds: stepDuration,
                    forceNoPerCallTransition: false,
                    releaseRealtimeOverride: false,
                    segmentId: segmentId,
                    disableActiveEffect: false
                )
                if step < steps {
                    let shouldContinue = await waitForRunContinuation(
                        deviceId: device.id,
                        runId: runId,
                        durationSeconds: stepDuration
                    )
                    if !shouldContinue { break }
                }
            }
            #if DEBUG
            print("✅ Segmented transition completed for \(device.name): duration=\(effectiveDuration)s")
            #endif
        } else {
            await applyGradientStopsAcrossStrip(
                device,
                stops: endGradient.stops,
                ledCount: ledCount,
                stopTemperatures: endStopTemperatures,
                stopWhiteLevels: endStopWhiteLevels,
                disableActiveEffect: true,
                segmentId: segmentId,
                interpolation: endGradient.interpolation,
                brightness: endBrightness,
                on: true,
                transitionDurationSeconds: durationSeconds,
                releaseRealtimeOverride: false,
                userInitiated: false,
                preferSegmented: true
            )
            #if DEBUG
            print("✅ Transition applied via native transition for \(device.name): duration=\(durationSeconds)s")
            #endif
        }
        
        await MainActor.run {
            latestGradientStops[device.id] = endGradient.stops
        }
    }
    
    func runSimpleGradientFade(
        for device: WLEDDevice,
        targetGradient: LEDGradient,
        targetBrightness: Int,
        durationSeconds: Double,
        segmentId: Int = 0,
        automationName: String? = nil
    ) async {
        let current = automationGradient(for: device)
        let startBrightness = device.brightness
        await runAutomationTransition(
            for: device,
            startGradient: current,
            startBrightness: startBrightness,
            endGradient: targetGradient,
            endBrightness: targetBrightness,
            durationSeconds: durationSeconds,
            segmentId: segmentId,
            automationName: automationName
        )
    }
    
    // Pending toggles tracking (anti-flicker)
    private var pendingToggles: [String: Bool] = [:]
    private var toggleTimers: [String: Timer] = [:]
    
    // Track when gradient was just applied to prevent WebSocket color overwrites
    private var gradientApplicationTimes: [String: Date] = [:]
    private let gradientProtectionWindow: TimeInterval = 3.0 // 3 seconds protection after gradient application (increased for per-LED uploads)
    
    // Add this dictionary to coordinate with UI-level optimistic state
    private var uiToggleStates: [String: Bool] = [:]

    // Pending rename tracking to prevent WebSocket rollbacks
    private struct PendingRename {
        let targetName: String
        let initiatedAt: Date
    }
    private var pendingRenames: [String: PendingRename] = [:]
    private let renameProtectionWindow: TimeInterval = 8.0
    
    // Real-time control state
    @Published var isRealTimeEnabled: Bool = true

    private func shouldSendWebSocketUpdate(_ update: WLEDStateUpdate) -> Bool {
        let segCount = update.seg?.count ?? 0
        if segCount > 6 {
            return false
        }
        return true
    }
    
    // Multi-device batch operations
    @Published var selectedDevices: Set<String> = []
    @Published var isBatchMode: Bool = false
    @Published var batchOperationInProgress: Bool = false
    
    // State change batching for performance
    private var pendingDeviceUpdates: [String: WLEDDevice] = [:]
    private var batchUpdateTimer: Timer?
    private let batchUpdateInterval: TimeInterval = 0.15 // Reduced to 150ms for better responsiveness
    
    // Performance optimization: Device state cache
    private var deviceStateCache: [String: (device: WLEDDevice, lastUpdate: Date)] = [:]
    private let cacheExpirationInterval: TimeInterval = 5.0 // 5 seconds cache expiration
    
    // Optimized device filtering with memoization
    private var cachedFilteredDevices: [WLEDDevice] = []
    private var lastFilterUpdate: Date = .distantPast
    private let filterUpdateThrottle: TimeInterval = 0.1 // 100ms throttle for filtering
    
    // MARK: - App Lifecycle Management
    
    /// Immediately check device status when app becomes active
    @MainActor
    func checkDeviceStatusOnAppActive() async {
        guard allowActiveHealthChecks else {
            print("Skipping device status check (active checks disabled)")
            return
        }
        print("🔄 App became active - checking device status immediately")
        
        // Get all persisted devices
        let persistedDevices = await coreDataManager.fetchDevices()
        
        // Perform immediate health checks for all devices
        for device in persistedDevices {
            performImmediateHealthCheckDetached(for: device)
        }
        
        // Also trigger connection monitor to perform immediate checks
        await connectionMonitor.performImmediateHealthChecks()
    }
    
    /// Perform immediate health check for a single device off the main actor.
    private func performImmediateHealthCheckDetached(for device: WLEDDevice) {
        let apiService = self.apiService
        Task.detached {
            do {
                // Quick HTTP ping to check if device is reachable
                let _ = try await apiService.getState(for: device)
                
                // Device is online - update status immediately
                await MainActor.run {
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[index].isOnline = true
                        self.devices[index].lastSeen = Date()
                        print("✅ Immediate check: \(device.name) is online")
                    }
                    self.clearError()
                }
                
                await DeviceCleanupManager.shared.processQueue(for: device.id)
                
            } catch {
                // Device is offline - update status immediately
                await MainActor.run {
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[index].isOnline = false
                        print("❌ Immediate check: \(device.name) is offline")
                    }
                    self.presentError(.deviceOffline(deviceName: device.name))
                }
            }
        }
    }
    
    // MARK: - Memory Management
    
    private func startMemoryMonitoring() {
        // Monitor memory usage every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.logMemoryUsage()
            }
        }
    }
    
    @MainActor
    private func logMemoryUsage() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let memoryUsageMB = Double(memoryInfo.resident_size) / 1024.0 / 1024.0
            print("Memory usage: \(String(format: "%.2f", memoryUsageMB)) MB")
            
            // Warn if memory usage is high (raised threshold to 200MB for iOS apps)
            if memoryUsageMB > 200 {
                #if DEBUG
                print("⚠️ High memory usage detected: \(String(format: "%.2f", memoryUsageMB)) MB")
                #endif
            }
        }
    }
    
    func clearUIOptimisticState(deviceId: String) {
        uiToggleStates.removeValue(forKey: deviceId)
    }
    
    func setUIOptimisticState(deviceId: String, isOn: Bool) {
        uiToggleStates[deviceId] = isOn
    }

    func getCurrentPowerState(for deviceId: String) -> Bool {
        if let optimisticState = uiToggleStates[deviceId] {
            return optimisticState
        }
        return devices.first { $0.id == deviceId }?.isOn ?? false
    }
    

    // MARK: - Initialization
    
    private init() {
        setupSubscriptions()
        loadDevicesFromPersistence()
        setupWebSocketSubscriptions()
        
        // Start memory monitoring
        startMemoryMonitoring()
    }
    
    deinit {
        cancellables.removeAll()
        batchUpdateTimer?.invalidate()
        // Clean up all toggle timers
        toggleTimers.values.forEach { $0.invalidate() }
        toggleTimers.removeAll()
        
        // Cancel watchdog task
        watchdogTask?.cancel()
        
        // Note: webSocketManager.disconnectAll() is main actor-isolated
        // WebSocket connections will be cleaned up when the main actor context is deallocated
        
        // Clear all device-related collections
        pendingDeviceUpdates.removeAll()
        pendingToggles.removeAll()
        uiToggleStates.removeAll()
        lastUserInput.removeAll()
        runWatchdogs.removeAll()
        
        print("DeviceControlViewModel deinit - Memory cleaned up")
    }
    
    // MARK: - Subscription Setup
    
    private func setupSubscriptions() {
        // Subscribe to discovered devices from WLEDDiscoveryService
        wledService.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discoveredDevices in
                Task {
                    await self?.handleDiscoveredDevices(discoveredDevices)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to scanning status
        wledService.$isScanning
            .receive(on: DispatchQueue.main)
            .assign(to: \.isScanning, on: self)
            .store(in: &cancellables)
        
        // Listen for device discovery notifications
        NotificationCenter.default.publisher(for: NSNotification.Name("DeviceDiscovered"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let userInfo = notification.userInfo,
                   let deviceId = userInfo["deviceId"] as? String,
                   let isOnline = userInfo["isOnline"] as? Bool,
                   isOnline {
                    self?.markDeviceOnline(deviceId)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupWebSocketSubscriptions() {
        // Subscribe to WebSocket state updates
        webSocketManager.deviceStateUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stateUpdate in
                // Defer state writes to next runloop to avoid re-entrant view updates
                DispatchQueue.main.async { [weak self] in
                    self?.handleWebSocketStateUpdate(stateUpdate)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to connection status changes
        webSocketManager.$connectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.webSocketConnectionStatus, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Batched Device Updates
    
    private func scheduleDeviceUpdate(_ device: WLEDDevice) {
        pendingDeviceUpdates[device.id] = device
        
        // Cancel existing timer and start new one
        batchUpdateTimer?.invalidate()
        batchUpdateTimer = Timer.scheduledTimer(withTimeInterval: batchUpdateInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.processBatchedUpdates()
            }
        }
    }
    
    private func processBatchedUpdates() {
        guard !pendingDeviceUpdates.isEmpty else { return }
        
        // Apply all pending updates at once to minimize UI notifications
        var updatedDevices = devices
        var hasChanges = false
        
        for (deviceId, updatedDevice) in pendingDeviceUpdates {
            if let index = updatedDevices.firstIndex(where: { $0.id == deviceId }) {
                // Only update if there are actual changes
                if !devicesAreEqual(updatedDevices[index], updatedDevice) {
                    updatedDevices[index] = updatedDevice
                    hasChanges = true
                }
            }
        }
        
        if hasChanges {
            devices = updatedDevices
        }
        
        pendingDeviceUpdates.removeAll()
        batchUpdateTimer = nil
    }
    
    private func devicesAreEqual(_ device1: WLEDDevice, _ device2: WLEDDevice) -> Bool {
        return device1.id == device2.id &&
               device1.isOn == device2.isOn &&
               device1.brightness == device2.brightness &&
               device1.isOnline == device2.isOnline &&
               device1.name == device2.name &&
               device1.ipAddress == device2.ipAddress &&
               device1.autoWhiteMode == device2.autoWhiteMode &&
               device1.currentColor == device2.currentColor // Simple color comparison
    }
    
    // MARK: - Optimized WebSocket State Updates
    
    private func handleWebSocketStateUpdate(_ stateUpdate: WLEDDeviceStateUpdate) {
        guard let index = devices.firstIndex(where: { $0.id == stateUpdate.deviceId }) else {
            return
        }
        
        // If the UI has an optimistic state for this device, don't let WebSockets override it.
        if uiToggleStates[stateUpdate.deviceId] != nil {
            return
        }

        // Skip update if device is under user control (prevent conflicts)
        if isUnderUserControl(stateUpdate.deviceId) {
            return
        }
        
        // Skip update if currently toggling to prevent flicker
        if pendingToggles[stateUpdate.deviceId] != nil {
            return
        }
        
        var updatedDevice = devices[index]
        var hasSignificantChanges = false
        
        if let state = stateUpdate.state {
            // Check for significant state changes to prevent jitter
            let powerChanged = updatedDevice.isOn != state.isOn
            let brightnessChanged = abs(updatedDevice.brightness - state.brightness) > 15 // Increased threshold to 15
            
            if powerChanged || brightnessChanged {
                hasSignificantChanges = true
                
                updatedDevice.isOn = state.isOn
                updatedDevice.brightness = state.brightness
                updatedDevice.isOnline = true
                updatedDevice.lastSeen = stateUpdate.timestamp
                
                // Update effect state from WebSocket (always safe to update)
                if let segment = state.segments.first {
                    let segmentId = segment.id ?? 0
                    var segmentStates = effectStates[stateUpdate.deviceId] ?? [:]
                    let cached = segmentStates[segmentId] ?? .default
                    let fxValue = segment.fx ?? cached.effectId
                    let newEffectState = DeviceEffectState(
                        effectId: fxValue,
                        speed: segment.sx ?? cached.speed,
                        intensity: segment.ix ?? cached.intensity,
                        paletteId: segment.pal ?? cached.paletteId,
                        isEnabled: fxValue != 0
                    )
                    segmentStates[segmentId] = newEffectState
                    effectStates[stateUpdate.deviceId] = segmentStates
                    
                    #if DEBUG
                    if fxValue != 0 {
                        os_log("[Effects][WS] Device %{public}@ segment %d: fx=%d sx=%d ix=%d pal=%@", log: OSLog.effects, type: .debug, updatedDevice.name, segmentId, fxValue, newEffectState.speed, newEffectState.intensity, String(describing: newEffectState.paletteId))
                    }
                    #endif
                }
                
                // Update color if available from segments
                // CRITICAL: Don't overwrite color if device has active CCT temperature OR active effect
                // OR if gradient was just applied (to prevent WebSocket echo from overwriting gradient)
                if let segment = state.segments.first {
                    let segmentId = segment.id ?? 0
                    let effectState = effectStates[stateUpdate.deviceId]?[segmentId]
                    let hasActiveEffect = effectState?.isEnabled == true && (effectState?.effectId ?? 0) != 0
                    let normalized = segment.cctNormalized
                    updatedDevice.temperature = normalized

                    // Check if gradient was just applied (within protection window)
                    let gradientJustApplied: Bool
                    if let gradientTime = gradientApplicationTimes[stateUpdate.deviceId] {
                        let elapsed = Date().timeIntervalSince(gradientTime)
                        gradientJustApplied = elapsed < gradientProtectionWindow
                    } else {
                        gradientJustApplied = false
                    }

                    // Only update color if effect isn't active AND gradient wasn't just applied
                    if !hasActiveEffect && !gradientJustApplied {
                        if let normalized {
                            updatedDevice.currentColor = Color.color(fromCCTTemperature: normalized)
                        } else if let color = derivedColor(from: segment) {
                            updatedDevice.currentColor = color
                        }
                    } else {
                        #if DEBUG
                        if hasActiveEffect, let fx = effectState?.effectId {
                            print("🔵 handleWebSocketStateUpdate: Skipping color update - Effect is active (fx=\(fx))")
                        }
                        if gradientJustApplied {
                            print("🔵 handleWebSocketStateUpdate: Skipping color update - Gradient was just applied (protection window active)")
                        }
                        #endif
                    }
                }
            }
        }
        
        // Update device info if available (always safe to update)
        if let info = stateUpdate.info {
            let deviceId = stateUpdate.deviceId
            if let pending = pendingRenames[deviceId] {
                let elapsed = Date().timeIntervalSince(pending.initiatedAt)
                if info.name == pending.targetName {
                    // Rename confirmed by device - accept and clear pending state
                    if updatedDevice.name != info.name {
                        updatedDevice.name = info.name
                        hasSignificantChanges = true
                    }
                    pendingRenames.removeValue(forKey: deviceId)
                } else if elapsed < renameProtectionWindow {
                    // Skip applying stale name while rename is in flight
                } else {
                    // Rename appears to have failed or timed out - clear pending and accept info name
                    pendingRenames.removeValue(forKey: deviceId)
                    if updatedDevice.name != info.name {
                        updatedDevice.name = info.name
                        hasSignificantChanges = true
                    }
                }
            } else if updatedDevice.name != info.name {
                updatedDevice.name = info.name
                hasSignificantChanges = true
            }
        }
        
        // Use batched updates for better performance
        if hasSignificantChanges {
            scheduleDeviceUpdate(updatedDevice)
            
            // Persist the updated state in background
            Task.detached(priority: .background) {
                await CoreDataManager.shared.saveDevice(updatedDevice)
            }
        } else {
            // Just update the last seen timestamp for connection tracking (no UI update needed)
            devices[index].lastSeen = stateUpdate.timestamp
            devices[index].isOnline = true
        }
    }
    
    // MARK: - Multi-Device Batch Operations
    
    func toggleBatchMode() {
        isBatchMode.toggle()
        if !isBatchMode {
            selectedDevices.removeAll()
        }
    }
    
    func selectDevice(_ deviceId: String) {
        guard isBatchMode else { return }
        selectedDevices.insert(deviceId)
    }
    
    func deselectDevice(_ deviceId: String) {
        selectedDevices.remove(deviceId)
    }
    
    func selectAllDevices() {
        guard isBatchMode else { return }
        selectedDevices = Set(filteredDevices.map { $0.id })
    }
    
    func deselectAllDevices() {
        selectedDevices.removeAll()
    }
    
    func batchTogglePower() async {
        await performBatchOperation { device in
            await self.toggleDevicePower(device)
        }
    }
    
    func batchSetBrightness(_ brightness: Int) async {
        await performBatchOperation { device in
            await self.updateDeviceBrightness(device, brightness: brightness)
        }
    }
    
    func batchSetColor(_ color: Color) async {
        await performBatchOperation { device in
            await self.updateDeviceColor(device, color: color)
        }
    }
    
    func batchConnectRealTime() async {
        guard isRealTimeEnabled else { return }
        
        let selectedDeviceList = devices.filter { selectedDevices.contains($0.id) }
        let priorities = Dictionary(uniqueKeysWithValues: selectedDeviceList.enumerated().map { 
            ($0.element.id, $0.offset + 10) // Higher priority for selected devices
        })
        
        await webSocketManager.connectToDevices(selectedDeviceList, priorities: priorities)
    }
    
    func batchDisconnectRealTime() {
        for deviceId in selectedDevices {
            webSocketManager.disconnect(from: deviceId)
        }
    }
    
    private func performBatchOperation(_ operation: @escaping @MainActor (WLEDDevice) async -> Void) async {
        guard !selectedDevices.isEmpty else { return }
        
        batchOperationInProgress = true
        defer { batchOperationInProgress = false }
        
        let selectedDeviceList = devices.filter { selectedDevices.contains($0.id) }
        
        await withTaskGroup(of: Void.self) { group in
            for device in selectedDeviceList {
                group.addTask { @MainActor in
                    await operation(device)
                }
            }
        }
    }
    
    // MARK: - Enhanced Device Management
    
    func optimizeWebSocketConnections() {
        webSocketManager.optimizeConnections()
    }
    
    func getConnectionStatus(for device: WLEDDevice) -> WLEDWebSocketManager.DeviceConnectionStatus? {
        return webSocketManager.getConnectionStatus(for: device.id)
    }
    
    func connectWithPriority(_ device: WLEDDevice, priority: Int = 0) {
        webSocketManager.connect(to: device, priority: priority)
    }
    
    func refreshDeviceMetrics() {
        // Connection metrics are automatically updated by the WebSocket manager
        // This method can be used to trigger manual updates if needed
    }
    
    // MARK: - Enhanced WebSocket Management
    
    private func connectWebSocketsForAllDevices() {
        guard isRealTimeEnabled else { return }
        
        // Prioritize devices that are currently online and recently used
        let onlineDevices = devices.filter { $0.isOnline }
        let priorities = Dictionary(uniqueKeysWithValues: onlineDevices.enumerated().map { 
            ($0.element.id, $0.offset) 
        })
        
        Task {
            await webSocketManager.connectToDevices(onlineDevices, priorities: priorities)
        }
    }
    
    private func disconnectAllWebSockets() {
        webSocketManager.disconnectAll()
    }
    
    private func connectWebSocketIfNeeded(for device: WLEDDevice) {
        guard isRealTimeEnabled && device.isOnline else { return }
        
        // Check if already connected
        let connectionStatus = webSocketManager.getConnectionStatus(for: device.id)
        if connectionStatus?.status != .connected {
            // Assign higher priority to newly online devices
            let priority = Int(Date().timeIntervalSince1970) % 1000
            webSocketManager.connect(to: device, priority: priority)
        }
    }
    
    private func disconnectWebSocket(for device: WLEDDevice) {
        webSocketManager.disconnect(from: device.id)
    }
    
    // MARK: - Device Management
    
    private func loadDevicesFromPersistence() {
        Task { @MainActor in
            let persistedDevices = await coreDataManager.fetchDevices()
            await MainActor.run {
                let placeholders = persistedDevices.filter { self.isPlaceholderDevice($0) }
                self.devices = persistedDevices.filter { !self.isPlaceholderDevice($0) }

                // CRITICAL: Preload persisted gradients for all devices on app start
                // This ensures gradients are available immediately when power toggle happens
                for device in self.devices {
                    if let persisted = loadPersistedGradient(for: device.id), !persisted.isEmpty {
                        latestGradientStops[device.id] = persisted
                        #if DEBUG
                        print("🔵 Preloaded gradient for \(device.name): \(persisted.count) stops")
                        #endif
                    }
                }

                for placeholder in placeholders {
                    Task {
                        await self.coreDataManager.deleteDevice(id: placeholder.id)
                    }
                }
                
                // Register persisted devices with connection monitor
                for device in self.devices {
                    self.connectionMonitor.registerDevice(device)
                }

                for device in self.devices {
                    Task {
                        await self.refreshLEDPreferencesIfNeeded(for: device)
                    }
                }
                
                // Auto-connect real-time WebSocket for online devices if enabled
                if self.isRealTimeEnabled {
                    let onlineDevices = self.devices.filter { $0.isOnline }
                    if !onlineDevices.isEmpty {
                        // Small delay to allow app to fully initialize
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            self.connectWebSocketsForAllDevices()
                        }
                    }
                }
            }
        }
    }
    
    /// Perform initial device status check when app launches
    private func performInitialDeviceStatusCheck() async {
        print("🚀 App launched - performing initial device status check")
        
        // Quick parallel health checks for all devices
        for device in devices {
            performImmediateHealthCheckDetached(for: device)
        }
    }
    
    private func handleDiscoveredDevices(_ discoveredDevices: [WLEDDevice]) async {
        let realDeviceIPs = Set(discoveredDevices.filter { !isPlaceholderDevice($0) }.map { $0.ipAddress })
        for discoveredDevice in discoveredDevices {
            if isPlaceholderDevice(discoveredDevice), realDeviceIPs.contains(discoveredDevice.ipAddress) {
                continue
            }
            if isPlaceholderDevice(discoveredDevice),
               devices.contains(where: { $0.ipAddress == discoveredDevice.ipAddress && !isPlaceholderDevice($0) }) {
                continue
            }

            if !isPlaceholderDevice(discoveredDevice),
               let placeholderIndex = devices.firstIndex(where: { isPlaceholderDevice($0) && $0.ipAddress == discoveredDevice.ipAddress }) {
                let placeholderId = devices[placeholderIndex].id
                devices.remove(at: placeholderIndex)
                Task {
                    await coreDataManager.deleteDevice(id: placeholderId)
                }
            }

            // Check if device already exists
            if let existingIndex = devices.firstIndex(where: { $0.id == discoveredDevice.id }) {
                // Update existing device with any new information
                var updatedDevice = devices[existingIndex]
                updatedDevice.name = discoveredDevice.name
                updatedDevice.ipAddress = discoveredDevice.ipAddress
                updatedDevice.productType = discoveredDevice.productType
                updatedDevice.isOnline = discoveredDevice.isOnline  // CRITICAL: Update online status
                updatedDevice.brightness = discoveredDevice.brightness
                updatedDevice.isOn = discoveredDevice.isOn
                updatedDevice.currentColor = discoveredDevice.currentColor
                updatedDevice.autoWhiteMode = discoveredDevice.autoWhiteMode ?? updatedDevice.autoWhiteMode
                updatedDevice.lastSeen = Date()
                
                devices[existingIndex] = updatedDevice
                if !isPlaceholderDevice(updatedDevice) {
                    await coreDataManager.saveDevice(updatedDevice)
                }
                
                // Force UI update to reflect the new online status
                await MainActor.run {
                    objectWillChange.send()
                }
            } else {
                // Add new device
                var newDevice = discoveredDevice
                newDevice.lastSeen = Date()
                devices.append(newDevice)
                if !isPlaceholderDevice(newDevice) {
                    await coreDataManager.saveDevice(newDevice)
                }
                
                // Force UI update for new device
                await MainActor.run {
                    objectWillChange.send()
                }
            }
            
            // Register with connection monitor
            if !isPlaceholderDevice(discoveredDevice) {
                connectionMonitor.registerDevice(discoveredDevice)
            }
            
            // Connect WebSocket if real-time is enabled
            if !isPlaceholderDevice(discoveredDevice) {
                connectWebSocketIfNeeded(for: discoveredDevice)
            }

            if !isPlaceholderDevice(discoveredDevice) {
                Task {
                    await refreshLEDPreferencesIfNeeded(for: discoveredDevice)
                }
            }
        }
    }

    private func isPlaceholderDevice(_ device: WLEDDevice) -> Bool {
        return device.id.hasPrefix("ip:")
    }
    
    private func updateDeviceHealthStatus(_ healthStatus: [String: Bool]) {
        var hasChanges = false
        for (deviceId, isOnline) in healthStatus {
            if let index = devices.firstIndex(where: { $0.id == deviceId }) {
                if devices[index].isOnline != isOnline {
                    devices[index].isOnline = isOnline
                    hasChanges = true
                }
            }
        }
        
        // Force UI update if any device status changed
        if hasChanges {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Real-Time State Management
    
    // MARK: - Enhanced Device Control
    
    /// Force a device to be marked as online (useful after successful discovery)
    func markDeviceOnline(_ deviceId: String) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].isOnline = true
            devices[index].lastSeen = Date()
            objectWillChange.send()
            Task {
                await refreshLEDPreferencesIfNeeded(for: devices[index])
            }
        }
    }
    
    func toggleDevicePower(_ device: WLEDDevice) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        await cancelActiveRun(for: device, force: true)
        
        // The UI will have already registered the optimistic state.
        // The `targetState` is what the UI *wants* the device to be.
        let targetState: Bool = await MainActor.run {
            if let optimisticState = uiToggleStates[device.id] {
                return optimisticState
            } else {
                // Fallback: get fresh device state and calculate target
                let freshDevice = self.devices.first(where: { $0.id == device.id }) ?? device
                return !freshDevice.isOn
            }
        }
        
        // Get device state before toggle to check if we're turning on
        let actualDeviceBeforeToggle = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        let wasOff = !actualDeviceBeforeToggle.isOn
        let isTurningOn = wasOff && targetState
        let isTurningOff = actualDeviceBeforeToggle.isOn && !targetState
        
        // CRITICAL: Preserve brightness before turning off
        // This allows restoring it when device is turned back on
        if isTurningOff && actualDeviceBeforeToggle.brightness > 0 {
            await MainActor.run {
                self.lastBrightnessBeforeOff[device.id] = actualDeviceBeforeToggle.brightness
            }
        }
        
        // Mark interaction and set pending toggle
        markUserInteraction(device.id)
        pendingToggles[device.id] = targetState
        
        // Set a timer to clear the pending state if API call fails/hangs
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pendingToggles.removeValue(forKey: device.id)
                self?.uiToggleStates.removeValue(forKey: device.id)
            }
        }
        toggleTimers[device.id] = timer

        // CRITICAL: If turning on with gradient, skip separate updateDeviceState call
        // Include on=true in gradient application instead to prevent color flash
        if isTurningOn, let persistedStops = gradientStops(for: device.id), !persistedStops.isEmpty {
            // CRITICAL: Mark user interaction BEFORE gradient restoration to prevent WebSocket overwrites
            markUserInteraction(device.id)
            
            // Get device state and LED count
            // CRITICAL: Restore preserved brightness when turning on
                let updatedDevice = await MainActor.run {
                var dev = self.devices.first(where: { $0.id == device.id }) ?? device
                dev.isOn = targetState  // Update local state optimistically
                
                // Restore preserved brightness if available, otherwise use device brightness or default
                if let preservedBrightness = self.lastBrightnessBeforeOff[device.id], preservedBrightness > 0 {
                    dev.brightness = preservedBrightness
                } else if dev.brightness == 0 {
                    // If brightness is 0 (device was off), use default brightness
                    dev.brightness = 128  // Default to 50% brightness
                }
                
                return dev
                }
                let ledCount = totalLEDCount(for: updatedDevice)
            
            // CRITICAL: Apply gradient WITH power-on in SAME API call (skip updateDeviceState)
            // Include on=true and brightness in the gradient application
            // This ensures everything happens atomically - no gap for WLED to show restored colors
            await applyGradientStopsAcrossStrip(
                updatedDevice,
                stops: persistedStops,
                ledCount: ledCount,
                disableActiveEffect: true,  // Always disable effects during power-on restoration
                brightness: updatedDevice.brightness,  // Apply restored brightness with gradient
                on: true,  // Include power-on in gradient application
                preferSegmented: true
            )
            
            // Update local state optimistically
            // CRITICAL: Also update brightness to match restored brightness value
            // This ensures UI syncs correctly when device is turned on
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[index].isOn = targetState
                    self.devices[index].isOnline = true
                    self.devices[index].brightness = updatedDevice.brightness  // CRITICAL: Update brightness to restored value
                }
            }
            
            // Persist the change
            var deviceToSave = updatedDevice
            deviceToSave.isOn = targetState
            deviceToSave.isOnline = true
            deviceToSave.lastSeen = Date()
            await coreDataManager.saveDevice(deviceToSave)
            
            // Small delay then check if WLED restored any effects and disable them
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Fetch actual state to check for restored effects
            do {
                let response = try await apiService.getState(for: device)
                if let segment = response.state.segments.first, let fxValue = segment.fx, fxValue != 0 {
                    // WLED restored an effect - disable it
                    let segmentUpdate = SegmentUpdate(id: segment.id ?? 0, fx: 0, pal: 0, frz: false)
                    let effectOffUpdate = WLEDStateUpdate(seg: [segmentUpdate])
                    _ = try? await apiService.updateState(for: updatedDevice, state: effectOffUpdate)
                    
                    // Re-apply gradient to ensure it's not overwritten by effect
                    // CRITICAL: Include on=true to ensure device stays on during gradient restoration
                    // This prevents WebSocket updates or WLED's own state from interfering with power state
                await applyGradientStopsAcrossStrip(
                    updatedDevice,
                    stops: persistedStops,
                    ledCount: ledCount,
                        disableActiveEffect: true,
                        brightness: updatedDevice.brightness,  // Apply brightness with gradient
                        on: true,  // CRITICAL: Ensure device stays on during gradient restoration
                        userInitiated: false  // State restoration, not user-initiated
                    )
                }
            } catch {
                #if DEBUG
                print("⚠️ Failed to check for restored effects after power-on: \(error)")
                #endif
            }
        } else if isTurningOn {
            // Turning on but no gradient - use simple power update
            // CRITICAL: Restore preserved brightness when turning on
            let preservedBrightness = await MainActor.run {
                self.lastBrightnessBeforeOff[device.id]
            }
            
            await updateDeviceState(device) { currentDevice in
                var updatedDevice = currentDevice
                updatedDevice.isOn = targetState
                
                // Restore preserved brightness if available
                if let preservedBrightness = preservedBrightness, preservedBrightness > 0 {
                    updatedDevice.brightness = preservedBrightness
                } else if updatedDevice.brightness == 0 {
                    // If brightness is 0 (device was off), use default brightness
                    updatedDevice.brightness = 128  // Default to 50% brightness
                }
                
                return updatedDevice
            }
        } else {
            // Turning off - use simple power update
            await updateDeviceState(device) { currentDevice in
                var updatedDevice = currentDevice
                updatedDevice.isOn = targetState
                return updatedDevice
            }
        }
        
        // On success, clear the pending state from the timer
        await MainActor.run {
            pendingToggles.removeValue(forKey: device.id)
            toggleTimers[device.id]?.invalidate()
            toggleTimers.removeValue(forKey: device.id)
            uiToggleStates.removeValue(forKey: device.id)
        }
    }
    
    
    func updateDeviceBrightness(_ device: WLEDDevice, brightness: Int, userInitiated: Bool = true) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        if userInitiated {
            await cancelActiveRun(for: device, force: true)
        }
        
        markUserInteraction(device.id)
        
        // CRITICAL: WLED treats brightness 0% as "off" (on: false)
        // When brightness is 0%, we should turn device off
        // When brightness goes from 0% to >0%, we should turn device on
        let actualDevice = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        // CRITICAL: Check both power state AND brightness to detect when device is transitioning from off to on
        // A device can have isOn=false while brightness>0 (remembered brightness), so we must check both
        // wasOff = device is currently off (either isOn=false OR brightness==0) AND we're increasing brightness
        let wasOff = (!actualDevice.isOn || actualDevice.brightness == 0) && brightness > 0
        let isTurningOff = actualDevice.brightness > 0 && brightness == 0
        let hasPersistedGradient = gradientStops(for: device.id)?.isEmpty == false
        let activeEffectState = currentEffectState(for: device, segmentId: 0)
        let isEffectEnabled = activeEffectState.isEnabled && activeEffectState.effectId != 0
        
        // If turning off (brightness to 0%), turn device off first
        if isTurningOff {
            // CRITICAL: Preserve brightness before turning off
            // This allows restoring it when brightness is increased from 0%
            await MainActor.run {
                if actualDevice.brightness > 0 {
                    self.lastBrightnessBeforeOff[device.id] = actualDevice.brightness
                }
            }
            
            await updateDeviceState(device) { currentDevice in
                var updatedDevice = currentDevice
                updatedDevice.isOn = false
                updatedDevice.brightness = 0
                return updatedDevice
            }
            return
        }
        
        // If restoring brightness from 0 and we have a gradient, restore the gradient instead
        // This prevents WLED from showing a default color before gradient is applied
        if wasOff && hasPersistedGradient {
            if let persistedStops = gradientStops(for: device.id), !persistedStops.isEmpty {
                // CRITICAL: Mark user interaction BEFORE gradient restoration to prevent WebSocket overwrites
                // This ensures WebSocket updates don't interfere with gradient restoration
                markUserInteraction(device.id)
                
                // CRITICAL: Fetch actual state from WLED to see what it restored
                // When brightness goes to 0%, WLED might restore effects/presets when brightness comes back
                var actualState: WLEDState?
                do {
                    let response = try await apiService.getState(for: device)
                    actualState = response.state
                    
                    // CRITICAL: Only update state (for effect checking), NOT brightness
                    // The brightness from WLED response is likely 0 (device was off), but we're about to apply
                    // the user's requested brightness. Updating brightness here creates a window where
                    // device state shows incorrect brightness, potentially causing UI inconsistencies.
                    await MainActor.run {
                        if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                            // Only update state, preserve current brightness (will be updated with requested value)
                            self.devices[index].state = response.state
                            // DO NOT update brightness here - it will be set to the requested value below
                        }
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to fetch state after brightness restoration: \(error)")
                    #endif
                }
                
                let updatedDevice = await MainActor.run {
                    var dev = self.devices.first(where: { $0.id == device.id }) ?? device
                    dev.brightness = brightness
                    
                    // CRITICAL: Update preserved brightness when restoring from 0%
                    // This ensures brightness is preserved for future power-on operations
                    if brightness > 0 {
                        self.lastBrightnessBeforeOff[device.id] = brightness
                    }
                    
                    return dev
                }
                let ledCount = totalLEDCount(for: updatedDevice)
                
                // CRITICAL: Check actual WLED state for active effects
                // WLED might restore effects/presets when brightness comes back from 0%
                var hasActiveEffect = false
                if let state = actualState, let segment = state.segments.first {
                    let fxValue = segment.fx ?? 0
                    hasActiveEffect = fxValue != 0
                    
                    if hasActiveEffect {
                        // Disable effect before applying gradient
                        let segmentUpdate = SegmentUpdate(id: segment.id ?? 0, fx: 0, pal: 0, frz: false)
                        let effectOffUpdate = WLEDStateUpdate(seg: [segmentUpdate])
                        _ = try? await apiService.updateState(for: updatedDevice, state: effectOffUpdate)
                        
                        // Update effect state cache
                        await MainActor.run {
                            var segmentStates = self.effectStates[device.id] ?? [:]
                            let segmentId = segment.id ?? 0
                            segmentStates[segmentId] = DeviceEffectState(
                                effectId: 0,
                                speed: segment.sx ?? 128,
                                intensity: segment.ix ?? 128,
                                paletteId: segment.pal,
                                isEnabled: false
                            )
                            self.effectStates[device.id] = segmentStates
                        }
                        
                        // Small delay to ensure effect is disabled
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                }
                
                // CRITICAL: Restore gradient WITH power-on and brightness in SAME API call
                // Include on=true when restoring from 0% brightness
                // This ensures everything happens atomically - no gap for WLED to show restored colors
                await applyGradientStopsAcrossStrip(
                    updatedDevice,
                    stops: persistedStops,
                    ledCount: ledCount,
                    disableActiveEffect: hasActiveEffect,  // Disable if we found an active effect
                    brightness: brightness,  // Apply brightness with gradient
                    on: true,  // CRITICAL: Turn device on when restoring brightness from 0%
                    userInitiated: true,  // User changed brightness, cancel any active runs
                    preferSegmented: true
                )
                
                // Update local state
                await MainActor.run {
                    if let index = devices.firstIndex(where: { $0.id == device.id }) {
                        devices[index].brightness = brightness
                        devices[index].isOn = true  // CRITICAL: Ensure isOn is true when brightness > 0
                        devices[index].isOnline = true
                    }
                    
                    // CRITICAL: Preserve brightness for future power-on operations
                    if brightness > 0 {
                        self.lastBrightnessBeforeOff[device.id] = brightness
                    }
                    
                    clearError()
                }
                
                // Persist the change
                var deviceToSave = updatedDevice
                deviceToSave.brightness = brightness
                deviceToSave.isOnline = true
                deviceToSave.lastSeen = Date()
                await coreDataManager.saveDevice(deviceToSave)
                
                return
            }
        }
        
        // Normal brightness update
        // CRITICAL: If brightness is 0%, turn device off (WLED treats brightness 0% as off)
        if brightness == 0 {
            await updateDeviceState(device) { currentDevice in
                var updatedDevice = currentDevice
                updatedDevice.isOn = false
                updatedDevice.brightness = 0
                return updatedDevice
            }
            return
        }
        
        // CRITICAL: If we have a gradient, only update brightness (no color resend).
        if hasPersistedGradient, !isEffectEnabled, (gradientStops(for: device.id)?.isEmpty == false) {
            await updateDeviceState(device) { currentDevice in
                var updatedDevice = currentDevice
                updatedDevice.brightness = brightness
                updatedDevice.isOn = true
                return updatedDevice
            }
            if brightness > 0 {
                self.lastBrightnessBeforeOff[device.id] = brightness
            }
        } else {
            // No gradient - use simple brightness update
            // CRITICAL: WLED treats brightness 0% as "off" (on: false)
            // Include on state in brightness update to ensure proper state
            let shouldBeOn = brightness > 0
            let transitionMs = resolvedTransitionMs(for: device, fallbackSeconds: directBrightnessTransitionSeconds)
            let stateUpdate = WLEDStateUpdate(
                on: shouldBeOn ? true : false,  // CRITICAL: Explicitly set on=false when brightness is 0%
                bri: brightness,
                transition: transitionMs
            )
        
        do {
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            
            // Send WebSocket update if connected
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                    webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
                }
            }
            
            await MainActor.run {
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].brightness = brightness
                        devices[index].isOn = shouldBeOn  // CRITICAL: Update isOn based on brightness
                    devices[index].isOnline = true
                }
                    
                    // CRITICAL: Preserve brightness for future power-on operations
                    if brightness > 0 {
                        self.lastBrightnessBeforeOff[device.id] = brightness
                    }
                    
                clearError()
            }
            
            // Persist the change
            var updatedDevice = device
            updatedDevice.brightness = brightness
                updatedDevice.isOn = shouldBeOn  // CRITICAL: Update isOn based on brightness
            updatedDevice.isOnline = true
            updatedDevice.lastSeen = Date()
            await coreDataManager.saveDevice(updatedDevice)
            
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            await MainActor.run {
                self.presentError(mappedError)
                }
            }
        }
    }
    
    func updateDeviceColor(_ device: WLEDDevice, color: Color) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        await cancelActiveRun(for: device, force: true)
        markUserInteraction(device.id)

        let hex = color.toHex()
        let stops = [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ]
        let ledCount = totalLEDCount(for: device)
        let transitionDurationSeconds = defaultTransitionMs(for: device) == nil
            ? directColorTransitionSeconds
            : nil
        await applyGradientStopsAcrossStrip(
            device,
            stops: stops,
            ledCount: ledCount,
            disableActiveEffect: true,
            on: true,
            transitionDurationSeconds: transitionDurationSeconds,
            userInitiated: true,
            preferSegmented: true
        )
    }
    
    /// Apply CCT (Correlated Color Temperature) to a device
    /// - Parameters:
    ///   - device: The WLED device
    ///   - temperature: Temperature slider value (0.0-1.0, where 0=warm, 1=cool)
    ///   - withColor: Optional RGB color to set along with CCT
    func applyCCT(to device: WLEDDevice, temperature: Double, withColor: [Int]? = nil, segmentId: Int = 0) async {
        markUserInteraction(device.id)
        guard supportsCCT(for: device, segmentId: segmentId) else { return }
        let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: segmentId)
        let cct: Int = usesKelvin ? kelvinValue(for: device, normalized: temperature) : Segment.eightBitValue(fromNormalized: temperature)
        
        do {
            if let color = withColor {
                _ = try await apiService.setColor(for: device, color: color, cct: cct)
            } else {
                // CRITICAL: When sending CCT-only, we must send ONLY CCT (no RGB)
                // However, if the device doesn't support CCT or has it disabled,
                // WLED will ignore the CCT value. As a fallback, we can send the RGB
                // color that WLED would produce from CCT, but ONLY if CCT fails.
                // For now, try CCT-only first (correct approach)
                if usesKelvin {
                    _ = try await apiService.setCCT(for: device, cctKelvin: cct, segmentId: segmentId)
                } else {
                    _ = try await apiService.setCCT(for: device, cct: cct, segmentId: segmentId)
                }
                
                // Note: If device doesn't support CCT, WLED will ignore the CCT value
                // The device capabilities are checked via supportsCCT() before calling this function
                // For CCT 0 (warm), WLED produces #FFA000 (orange)
                // For CCT 255 (cool), WLED produces #CBDBFF (cool white)
            }
            
            if isRealTimeEnabled {
                // CRITICAL: When sending CCT via WebSocket, ensure col is NOT included
                // WLED uses col if present, even if cct is also present
                // Only include col if withColor is explicitly provided
                let segment = SegmentUpdate(
                    id: segmentId,
                    col: nil,  // Explicitly nil - JSON encoder will omit this field
                    cct: cct,
                    fx: 0  // Disable effects to allow CCT to work
                )
                let stateUpdate = WLEDStateUpdate(seg: [segment])
                
                // Debug logging
                #if DEBUG
                print("🔵 WebSocket CCT update: segmentId=\(segmentId), cct=\(cct), col=nil")
                #endif
                
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[index].temperature = temperature
                    self.devices[index].isOnline = true
                    
                       // CRITICAL FIX: Update local device color optimistically based on CCT
                       // This prevents WebSocket state updates from overwriting with old RGB colors
                       // Use shared CCT color calculation utility
                       self.devices[index].currentColor = Color.color(fromCCTTemperature: temperature)
                    
                    #if DEBUG
                    print("🔵 applyCCT: Updated local device color optimistically for CCT-based color")
                    #endif
                }
                self.clearError()
            }
            
            var updatedDevice = device
            updatedDevice.temperature = temperature
            updatedDevice.isOnline = true
            updatedDevice.lastSeen = Date()
            await coreDataManager.saveDevice(updatedDevice)
            
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
    }
    
    func setDevicePower(_ device: WLEDDevice, isOn: Bool) async {
        await cancelActiveRun(for: device, force: true)
        markUserInteraction(device.id)
        
        // Get device state before power change to check if we're turning on
        let actualDeviceBeforeChange = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        let wasOff = !actualDeviceBeforeChange.isOn
        let isTurningOn = wasOff && isOn
        let isTurningOff = actualDeviceBeforeChange.isOn && !isOn
        
        // CRITICAL: Preserve brightness before turning off
        // This allows restoring it when device is turned back on
        if isTurningOff && actualDeviceBeforeChange.brightness > 0 {
            await MainActor.run {
                self.lastBrightnessBeforeOff[device.id] = actualDeviceBeforeChange.brightness
            }
        }
        
        // CRITICAL: If turning on with gradient, skip separate updateDeviceState call
        // Include on=true in gradient application instead to prevent color flash
        if isTurningOn, let persistedStops = gradientStops(for: device.id), !persistedStops.isEmpty {
            // CRITICAL: Mark user interaction BEFORE gradient restoration to prevent WebSocket overwrites
            markUserInteraction(device.id)
            
            // Get device state and LED count
            // CRITICAL: Restore preserved brightness when turning on
            let updatedDevice = await MainActor.run {
                var dev = self.devices.first(where: { $0.id == device.id }) ?? device
                dev.isOn = isOn  // Update local state optimistically
                
                // Restore preserved brightness if available, otherwise use device brightness or default
                if let preservedBrightness = self.lastBrightnessBeforeOff[device.id], preservedBrightness > 0 {
                    dev.brightness = preservedBrightness
                } else if dev.brightness == 0 {
                    // If brightness is 0 (device was off), use default brightness
                    dev.brightness = 128  // Default to 50% brightness
                }
                
                return dev
            }
            let ledCount = totalLEDCount(for: updatedDevice)
            
            // CRITICAL: Apply gradient WITH power-on in SAME API call (skip updateDeviceState)
            // Include on=true and brightness in the gradient application
            // This ensures everything happens atomically - no gap for WLED to show restored colors
            await applyGradientStopsAcrossStrip(
                updatedDevice,
                stops: persistedStops,
                ledCount: ledCount,
                disableActiveEffect: true,  // Always disable effects during power-on restoration
                brightness: updatedDevice.brightness,  // Apply restored brightness with gradient
                on: true,  // Include power-on in gradient application
                preferSegmented: true
            )
            
            // Update local state optimistically
            // CRITICAL: Also update brightness to match restored brightness value
            // This ensures UI syncs correctly when device is turned on
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[index].isOn = isOn
                    self.devices[index].isOnline = true
                    self.devices[index].brightness = updatedDevice.brightness  // CRITICAL: Update brightness to restored value
                }
            }
            
            // Persist the change
            var deviceToSave = updatedDevice
            deviceToSave.isOn = isOn
            deviceToSave.isOnline = true
            deviceToSave.lastSeen = Date()
            await coreDataManager.saveDevice(deviceToSave)
            
            // Small delay then check if WLED restored any effects and disable them
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Fetch actual state to check for restored effects
            do {
                let response = try await apiService.getState(for: device)
                if let segment = response.state.segments.first, let fxValue = segment.fx, fxValue != 0 {
                    // WLED restored an effect - disable it
                    let segmentUpdate = SegmentUpdate(id: segment.id ?? 0, fx: 0, pal: 0, frz: false)
                    let effectOffUpdate = WLEDStateUpdate(seg: [segmentUpdate])
                    _ = try? await apiService.updateState(for: updatedDevice, state: effectOffUpdate)
                    
                    // Re-apply gradient to ensure it's not overwritten by effect
                    // CRITICAL: Include on=true to ensure device stays on during gradient restoration
                    // This prevents WebSocket updates or WLED's own state from interfering with power state
                    await applyGradientStopsAcrossStrip(
                        updatedDevice,
                        stops: persistedStops,
                        ledCount: ledCount,
                        disableActiveEffect: true,
                        brightness: updatedDevice.brightness,  // Apply brightness with gradient
                        on: true,  // CRITICAL: Ensure device stays on during gradient restoration
                        userInitiated: false,  // State restoration, not user-initiated
                        preferSegmented: true
                    )
                }
            } catch {
                #if DEBUG
                print("⚠️ Failed to check for restored effects after power-on: \(error)")
                #endif
            }
        } else if isTurningOn {
            // Turning on but no gradient - use simple power update
            // CRITICAL: Restore preserved brightness when turning on
            let preservedBrightness = await MainActor.run {
                self.lastBrightnessBeforeOff[device.id]
            }
        
        await updateDeviceState(device) { currentDevice in
            var updatedDevice = currentDevice
            updatedDevice.isOn = isOn
                
                // Restore preserved brightness if available
                if let preservedBrightness = preservedBrightness, preservedBrightness > 0 {
                    updatedDevice.brightness = preservedBrightness
                } else if updatedDevice.brightness == 0 {
                    // If brightness is 0 (device was off), use default brightness
                    updatedDevice.brightness = 128  // Default to 50% brightness
                }
                
            return updatedDevice
            }
        } else {
            // Turning off or no change - use simple power update
            await updateDeviceState(device) { currentDevice in
                var updatedDevice = currentDevice
                updatedDevice.isOn = isOn
                return updatedDevice
            }
        }
    }
    

    func setUDPSync(_ device: WLEDDevice, send: Bool?, recv: Bool?, network: Int? = nil) async {
        // Build UDPN update and call API; optimistic no-op on UI
        let udpn = UDPNUpdate(send: send, recv: recv, nn: network)
        let state = WLEDStateUpdate(udpn: udpn)
        _ = try? await apiService.updateState(for: device, state: state)
    }
    
    private func updateDeviceState(_ device: WLEDDevice, update: (WLEDDevice) -> WLEDDevice) async {
        let updatedDevice = update(device)
        
        do {
            // Check if we have a persisted gradient that will be restored
            let hasPersistedGradient = gradientStops(for: device.id)?.isEmpty == false
            let transitionMs = resolvedTransitionMs(for: updatedDevice, fallbackSeconds: directBrightnessTransitionSeconds)
            
            // Create state update based on changes
            // CRITICAL FIX: If we have a persisted gradient, DON'T send col field
            // This prevents WLED from applying a solid color before gradient restoration
            // WLED will preserve existing colors when only on/bri are sent
            // However, if device is turning ON, WLED might restore its own state from memory
            // So we still don't send col - let gradient restoration handle colors immediately after
            let stateUpdate: WLEDStateUpdate
            if hasPersistedGradient {
                // Only send power and brightness - don't send color
                // Gradient will be restored immediately after power-on completes
                // This prevents WLED from showing its restored colors before our gradient
                stateUpdate = WLEDStateUpdate(
                    on: updatedDevice.isOn,
                    bri: updatedDevice.brightness,
                    seg: nil,  // Don't send segment color - let gradient restoration handle it
                    transition: transitionMs
                )
            } else {
                // No persisted gradient - send solid color as before
                let rgb = updatedDevice.currentColor.toRGBArray()
                stateUpdate = WLEDStateUpdate(
                on: updatedDevice.isOn,
                bri: updatedDevice.brightness,
                seg: [SegmentUpdate(col: [[rgb[0], rgb[1], rgb[2]]])],
                transition: transitionMs
            )
            }
            
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            
            // Send WebSocket update if connected (for faster local feedback)
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            
            // Update local device list immediately with optimistic update
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[index] = updatedDevice
                    self.devices[index].isOnline = true // Ensure device stays online after successful update
                    
                    // Sync to widget
                    WidgetDataSync.shared.syncDevice(self.devices[index])
                }
                self.clearError()
            }
            
            // Persist to Core Data
            await coreDataManager.saveDevice(updatedDevice)
            
            // DO NOT call refreshDeviceState here - it causes race conditions with user input
            
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            await MainActor.run {
                if case .deviceOffline = mappedError {
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[index].isOnline = false
                    }
                } else {
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        self.devices[index].isOnline = true
                    }
                }
                self.presentError(mappedError)
            }
        }
    }
    
    // MARK: - Device Discovery
    
    func startScanning() async {
        wledService.startDiscovery()
    }

    func startPassiveDiscovery() {
        wledService.startPassiveDiscovery()
    }
    
    func stopScanning() async {
        wledService.stopDiscovery()
    }
    
    func addDeviceByIP(_ ipAddress: String) {
        wledService.addDeviceByIP(ipAddress)
    }

    func enableActiveHealthChecksIfNeeded() {
        guard !allowActiveHealthChecks else { return }
        allowActiveHealthChecks = true
        Task { @MainActor in
            await performInitialDeviceStatusCheck()
        }
    }
    
    func refreshDevices() async {
        // Coalesce refresh storms with a short TTL window
        if let last = _lastRefreshRequested, Date().timeIntervalSince(last) < 1.5 { return }
        _lastRefreshRequested = Date()
        isLoading = true
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        // Limit concurrency to avoid memory/network pressure
        let limit = 4
        var index = 0
        while index < devices.count {
            await withTaskGroup(of: Void.self) { group in
                for d in devices[index..<min(index+limit, devices.count)] {
                    group.addTask { @MainActor [weak self] in
                        await self?.refreshDeviceState(d)
                    }
                }
                for await _ in group { }
            }
            index += limit
        }
    }
    
    func refreshDeviceState(_ device: WLEDDevice) async {
        // Skip refresh for off-subnet devices to avoid timeouts/energy drain
        if !isIPInCurrentSubnets(device.ipAddress) { return }
        do {
            let response = try await apiService.getState(for: device)
            let ledCount = response.info.leds.count
            if ledCount > 0 {
                deviceLedCounts[device.id] = ledCount
            }
            
            // Detect and cache capabilities using CapabilityDetector
            let seglc = response.info.leds.seglc ?? fallbackSeglc(from: response.info.leds, state: response.state)
            if let seglc {
                let capabilities = await capabilityDetector.detect(deviceId: device.id, seglc: seglc)
                // Cache locally for synchronous access from MainActor
                await MainActor.run {
                    self.deviceCapabilities[device.id] = capabilities
                }
            }
            
            await fetchEffectMetadataIfNeeded(for: device)
            
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    var updatedDevice = self.devices[index]
                    updatedDevice.state = response.state
                    updatedDevice.brightness = response.state.brightness
                    updatedDevice.isOn = response.state.isOn
                    updatedDevice.isOnline = true
                    updatedDevice.lastSeen = Date()
                    
                    // CRITICAL FIX: Don't update color if device is under user control or gradient was just applied
                    // This prevents refreshDeviceState from overwriting gradient colors during restoration
                    let isUnderControl = self.isUnderUserControl(device.id)
                    let gradientJustApplied: Bool
                    if let gradientTime = self.gradientApplicationTimes[device.id] {
                        let elapsed = Date().timeIntervalSince(gradientTime)
                        gradientJustApplied = elapsed < self.gradientProtectionWindow
                    } else {
                        gradientJustApplied = false
                    }
                    
                    // Only update color if device is NOT under user control AND gradient wasn't just applied
                    if !isUnderControl && !gradientJustApplied {
                        if let segment = response.state.segments.first {
                            let segmentId = segment.id ?? 0
                            let effectState = self.effectStates[device.id]?[segmentId]
                            let hasActiveEffect = effectState?.isEnabled == true && (effectState?.effectId ?? 0) != 0
                            let normalized = segment.cctNormalized
                            updatedDevice.temperature = normalized

                            if let normalized, !hasActiveEffect {
                                updatedDevice.currentColor = Color.color(fromCCTTemperature: normalized)
                            } else if let color = derivedColor(from: segment), !hasActiveEffect {
                                updatedDevice.currentColor = color
                            }
                        }
                    } else {
                        #if DEBUG
                        if isUnderControl {
                            print("🔵 refreshDeviceState: Skipping color update - Device under user control")
                        }
                        if gradientJustApplied {
                            print("🔵 refreshDeviceState: Skipping color update - Gradient was just applied")
                        }
                        #endif
                    }
                    
                    self.devices[index] = updatedDevice
                    
                    // Sync to widget
                    WidgetDataSync.shared.syncDevice(updatedDevice)
                }

                // Capture CCT format per segment for future Kelvin support
                var segmentFormats = self.segmentCCTFormats[device.id] ?? [:]
                for (idx, segment) in response.state.segments.enumerated() {
                    let segmentIdentifier = segment.id ?? idx
                    segmentFormats[segmentIdentifier] = segment.cctIsKelvin
                }
                self.segmentCCTFormats[device.id] = segmentFormats

                // Capture effect state per segment for UI binding
                var segmentStates = self.effectStates[device.id] ?? [:]
                for (idx, segment) in response.state.segments.enumerated() {
                    let segmentIdentifier = segment.id ?? idx
                    let cached = segmentStates[segmentIdentifier] ?? .default
                    let fxValue = segment.fx ?? cached.effectId
                    let newState = DeviceEffectState(
                        effectId: fxValue,
                        speed: segment.sx ?? cached.speed,
                        intensity: segment.ix ?? cached.intensity,
                        paletteId: segment.pal ?? cached.paletteId,
                        isEnabled: fxValue != 0
                    )
                    segmentStates[segmentIdentifier] = newState
                }
                self.effectStates[device.id] = segmentStates
            }
            
            // Update persistence
            var persistDevice = device
            persistDevice.state = response.state
            persistDevice.brightness = response.state.brightness
            persistDevice.isOn = response.state.isOn
            persistDevice.isOnline = true
            persistDevice.lastSeen = Date()
            
            if let segment = response.state.segments.first {
                if let color = derivedColor(from: segment) {
                    persistDevice.currentColor = color
                }
                persistDevice.temperature = segment.cctNormalized
            }
            
            await coreDataManager.saveDevice(persistDevice)
            
            clearError()
            
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            if case .deviceOffline = mappedError {
                presentError(mappedError)
            }
        }
    }

    // MARK: - Capability Helpers
    func supportsCCT(for device: WLEDDevice, segmentId: Int = 0) -> Bool {
        // Use local cache for synchronous access from MainActor
        if let capabilities = deviceCapabilities[device.id],
           let segmentCap = capabilities.capabilities(for: segmentId) {
            return segmentCap.supportsCCT
        }
        if device.temperature != nil {
            return true
        }
        if let segments = device.state?.segments,
           segments.contains(where: { $0.cct != nil }) {
            return true
        }
        return false
    }
    
    func supportsWhite(for device: WLEDDevice, segmentId: Int = 0) -> Bool {
        // Use local cache for synchronous access from MainActor
        if let capabilities = deviceCapabilities[device.id],
           let segmentCap = capabilities.capabilities(for: segmentId) {
            return segmentCap.supportsWhite
        }
        if let segments = device.state?.segments {
            let hasWhite = segments.contains { segment in
                guard let colors = segment.colors else { return false }
                return colors.contains { $0.count >= 4 }
            }
            if hasWhite {
                return true
            }
        }
        return false
    }
    
    func supportsRGB(for device: WLEDDevice, segmentId: Int = 0) -> Bool {
        // Use local cache for synchronous access from MainActor
        guard let capabilities = deviceCapabilities[device.id],
              let segmentCap = capabilities.capabilities(for: segmentId) else {
            return true // Default to true for RGB
        }
        return segmentCap.supportsRGB
    }
    
    func getSegmentCount(for device: WLEDDevice) -> Int {
        guard let capabilities = deviceCapabilities[device.id] else {
            return 1 // Default to single segment
        }
        return capabilities.segments.count
    }
    
    func hasMultipleSegments(for device: WLEDDevice) -> Bool {
        return getSegmentCount(for: device) > 1
    }
    
    func getRawEffectMetadata(for device: WLEDDevice) -> [String]? {
        rawEffectMetadata[device.id]
    }
    
    private func fetchEffectMetadataIfNeeded(for device: WLEDDevice) async {
        let now = Date()
        let lastFetch = effectMetadataLastFetched[device.id] ?? .distantPast
        guard now.timeIntervalSince(lastFetch) > effectMetadataRefreshInterval else { return }
        do {
            let metadataLines = try await apiService.fetchEffectMetadata(for: device)
            effectMetadataLastFetched[device.id] = now
            rawEffectMetadata[device.id] = metadataLines
            if let bundle = EffectMetadataParser.parse(lines: metadataLines) {
                effectMetadataBundles[device.id] = bundle
            }
        } catch {
            // Silently ignore metadata fetch failures to avoid impacting main flow
        }
    }
    
    func effectMetadata(for device: WLEDDevice) -> EffectMetadataBundle? {
        effectMetadataBundles[device.id]
    }

    func colorSafeEffects(for device: WLEDDevice) -> [EffectMetadata] {
        guard let bundle = effectMetadata(for: device) else {
            return DeviceControlViewModel.fallbackGradientFriendlyEffects
        }
        let filtered = bundle.effects.filter { metadata in
            // Allow sound-reactive effects if they're in our approved list (e.g., Music Sync ID 139)
            if metadata.isSoundReactive {
                return DeviceControlViewModel.gradientFriendlyEffectIds.contains(metadata.id)
            }
            let supportsColors = metadata.colorSlotCount >= 1
            return supportsColors || DeviceControlViewModel.gradientFriendlyEffectIds.contains(metadata.id)
        }
        let list = filtered.isEmpty ? DeviceControlViewModel.fallbackGradientFriendlyEffects : filtered
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func colorSafeEffectOptions(for device: WLEDDevice) -> [EffectMetadata] {
        let effects = colorSafeEffects(for: device)
        return effects.isEmpty ? DeviceControlViewModel.fallbackGradientFriendlyEffects : effects
    }
    
    func applyColorSafeEffect(
        _ effectId: Int,
        with gradient: LEDGradient,
        segmentId: Int = 0,
        device: WLEDDevice,
        userInitiated: Bool = true
    ) async {
        if userInitiated {
            await cancelActiveRun(for: device, releaseRealtimeOverride: false, force: true)
            markUserInteraction(device.id)
        } else {
            await cancelActiveTransitionIfNeeded(for: device)
        }
        await colorPipeline.cancelUploads(for: device.id)
        
        // CRITICAL: Determine if we need to release realtime override atomically
        // Only needed when coming from per-LED gradient mode, not when switching between effects
        // We'll include lor: 0 in the same API call as the effect to prevent flash
        let currentState = currentEffectState(for: device, segmentId: segmentId)
        let isComingFromGradient = !currentState.isEnabled || currentState.effectId == 0
        let needsRealtimeRelease = isComingFromGradient
        
        if lastGradientBeforeEffect[device.id] == nil {
            let baseline = gradientStops(for: device.id) ?? [
                GradientStop(position: 0.0, hexColor: device.currentColor.toHex()),
                GradientStop(position: 1.0, hexColor: device.currentColor.toHex())
            ]
            lastGradientBeforeEffect[device.id] = baseline
        }
        let availableEffects = colorSafeEffectOptions(for: device)
        guard let metadata = availableEffects.first(where: { $0.id == effectId }) else {
            #if DEBUG
            os_log("[Effects] Requested effect %d not found in catalog", effectId)
            #endif
            return
        }
        
        // If this is a sound-reactive effect, enable audio reactive mode in WLED
        if metadata.isSoundReactive {
            #if DEBUG
            os_log("[Effects] Sound-reactive effect detected, enabling audio reactive mode", log: OSLog.effects, type: .debug)
            #endif
            do {
                // Check current status first
                let wasEnabled = try? await apiService.isAudioReactiveEnabled(for: device)
                if wasEnabled == true {
                    #if DEBUG
                    os_log("[Effects] Audio reactive mode already enabled", log: OSLog.effects, type: .debug)
                    #endif
                } else {
                    // Enable audio reactive
                    _ = try await apiService.enableAudioReactive(for: device)
                    #if DEBUG
                    os_log("[Effects] Audio reactive mode enabled successfully", log: OSLog.effects, type: .debug)
                    #endif
                    
                    // Verify it was enabled
                    let isNowEnabled = try? await apiService.isAudioReactiveEnabled(for: device)
                    if isNowEnabled == true {
                        #if DEBUG
                        os_log("[Effects] Audio reactive mode verified as enabled", log: OSLog.effects, type: .info)
                        #endif
                    } else {
                        #if DEBUG
                        os_log("[Effects] WARNING: Audio reactive mode may not be enabled. Check WLED web interface.", log: OSLog.effects, type: .error)
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                os_log("[Effects] Failed to enable/verify audio reactive mode: %{public}@", log: OSLog.effects, type: .error, error.localizedDescription)
                #endif
                // Continue anyway - the effect might still work if audio reactive is already enabled
            }
        }
        
        let slotCount = min(DeviceControlViewModel.maxEffectColorSlots,
                            max(1, metadata.colorSlotCount))
        let colorArray = DeviceControlViewModel.colors(for: gradient, slotCount: slotCount)
        #if DEBUG
        os_log("[Effects] Applying effect %{public}@ (id %d) with %d colors to device %{public}@", metadata.name, effectId, colorArray.count, device.name)
        os_log("[Effects]   gradient input stops=%{public@}", log: OSLog.effects, type: .debug, gradient.stops.map { $0.hexColor }.description)
        for (index, rgb) in colorArray.enumerated() {
            os_log("[Effects]   color[%d] = (%d,%d,%d)", index, rgb[0], rgb[1], rgb[2])
        }
        #endif
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.effectId = effectId
        // Don't set palette when we're providing custom colors - let WLED use the colors directly
        // Only use palette if the effect supports it and we're NOT providing colors
        state.paletteId = nil  // Omit palette when sending colors
        state.isEnabled = true
        updateEffectGradient(gradient, for: device)
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        
        // CRITICAL: When switching effects, ensure we get the current device brightness
        // This prevents brightness from being reset during effect switch
        let currentDevice = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        _ = currentDevice.brightness > 0 ? currentDevice.brightness : 255 // Unused
        
        // CRITICAL: Apply effect with colors, brightness, and realtime release atomically
        // Include lor: 0 in the same call if needed to prevent flash
        let useFullStrip = true
        await applyEffectState(state, to: currentDevice, segmentId: segmentId, colors: colorArray, turnOn: true, releaseRealtime: needsRealtimeRelease, fullStrip: useFullStrip)
        logEffectApplication(effectId: effectId, device: device, colors: colorArray)
    }
    
    /// Public method to load effect metadata (triggers fetch if needed)
    func loadEffectMetadata(for device: WLEDDevice) async {
        await fetchEffectMetadataIfNeeded(for: device)
    }
    
    func currentEffectState(for device: WLEDDevice, segmentId: Int = 0) -> DeviceEffectState {
        effectStates[device.id]?[segmentId] ?? .default
    }
    
    func segmentUsesKelvinCCT(for device: WLEDDevice, segmentId: Int = 0) -> Bool {
        segmentCCTFormats[device.id]?[segmentId] ?? false
    }

    func cctKelvinRange(for device: WLEDDevice) -> ClosedRange<Int> {
        cctKelvinRanges[device.id] ?? (defaultCCTKelvinMin...defaultCCTKelvinMax)
    }

    private func kelvinValue(for device: WLEDDevice, normalized: Double) -> Int {
        let range = cctKelvinRange(for: device)
        let clamped = min(max(normalized, 0.0), 1.0)
        let span = Double(range.upperBound - range.lowerBound)
        return Int(round(Double(range.lowerBound) + clamped * span))
    }

    func temperatureStopsUseCCT(for device: WLEDDevice) -> Bool {
        UserDefaults.standard.bool(forKey: temperatureStopsCCTKeyPrefix + device.id)
    }

    func setTemperatureStopsUseCCT(_ enabled: Bool, for device: WLEDDevice) {
        UserDefaults.standard.set(enabled, forKey: temperatureStopsCCTKeyPrefix + device.id)
    }

    private func refreshLEDPreferencesIfNeeded(for device: WLEDDevice, force: Bool = false) async {
        guard !isPlaceholderDevice(device), device.isOnline else { return }
        let now = Date()
        if !force, let lastFetch = ledPreferencesLastFetched[device.id],
           now.timeIntervalSince(lastFetch) < ledPreferencesRefreshInterval {
            return
        }
        ledPreferencesLastFetched[device.id] = now

        do {
            let config = try await apiService.getLEDConfiguration(for: device)
            let mode = AutoWhiteMode(rawValue: config.autoWhiteMode) ?? .none
            if let minKelvin = config.cctKelvinMin,
               let maxKelvin = config.cctKelvinMax,
               minKelvin < maxKelvin {
                cctKelvinRanges[device.id] = minKelvin...maxKelvin
            } else {
                cctKelvinRanges.removeValue(forKey: device.id)
            }
            await MainActor.run {
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].autoWhiteMode = mode
                }
            }
            var updated = devices.first(where: { $0.id == device.id }) ?? device
            updated.autoWhiteMode = mode
            await coreDataManager.saveDevice(updated)
        } catch {
            // Ignore LED preference fetch failures to avoid blocking discovery.
        }
    }

    private func fallbackSeglc(from leds: LedInfo, state: WLEDState) -> [Int]? {
        if let lc = leds.lc {
            return [lc]
        }
        var flags = 0
        if leds.rgbw == true || leds.wv == true {
            flags |= 0b010
        }
        if leds.cct == true {
            flags |= 0b100
        }
        if flags == 0 {
            let hasWhite = state.segments.contains { segment in
                guard let colors = segment.colors else { return false }
                return colors.contains { $0.count >= 4 }
            }
            let hasCct = state.segments.contains { $0.cct != nil }
            if hasWhite {
                flags |= 0b010
            }
            if hasCct {
                flags |= 0b100
            }
        }
        if flags == 0 {
            return nil
        }
        flags |= 0b001
        return [flags]
    }

    func setEffect(for device: WLEDDevice, segmentId: Int = 0, effectId: Int) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.effectId = effectId
        state.paletteId = nil // ensure palette reset for color-slot effects
        state.isEnabled = true
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, colors: nil, turnOn: true, fullStrip: useFullStrip)
    }
    
    /// Disable effects for a device/segment (set fx: 0)
    /// This allows CCT and solid colors to work properly
    /// Note: Does NOT automatically restore gradient - caller should handle that separately if needed
    func disableEffect(for device: WLEDDevice, segmentId: Int = 0) async {
        os_log("[Effects] Disabling effect for device %{public}@, segment %d", log: OSLog.effects, type: .debug, device.name, segmentId)
        await cancelActiveTransitionIfNeeded(for: device)
        await colorPipeline.cancelUploads(for: device.id)
        // Don't call releaseRealtimeOverride here - it can interfere with gradient application
        // Only release realtime if we're actually switching to effects mode
        markUserInteraction(device.id)
        
        // CRITICAL: Get current device brightness BEFORE disabling effect
        // When disabling effects, WLED might restore brightness to a high value (255), causing a flash
        // We need to preserve the current brightness and include it in the effect-disable call
        let currentDevice = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        let currentBrightness = currentDevice.brightness
        
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.effectId = 0  // Effect ID 0 = effects disabled
        state.isEnabled = false
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        
        let restoreStops = gradientStops(for: device.id)
        let stops = (restoreStops?.isEmpty == false) ? restoreStops! : [
            GradientStop(position: 0.0, hexColor: device.currentColor.toHex()),
            GradientStop(position: 1.0, hexColor: device.currentColor.toHex())
        ]
        let restoreInterpolation = effectGradientStops(for: device.id)?.isEmpty == false
            ? LEDGradient(stops: effectGradientStops(for: device.id)!).interpolation
            : LEDGradient(stops: stops).interpolation
        await applyGradientStopsAcrossStrip(
            currentDevice,
            stops: stops,
            ledCount: totalLEDCount(for: currentDevice),
            disableActiveEffect: true,
            segmentId: 0,
            interpolation: restoreInterpolation,
            brightness: currentBrightness,
            on: currentDevice.isOn,
            userInitiated: false,
            preferSegmented: true
        )
        
        lastGradientBeforeEffect.removeValue(forKey: device.id)
        
        #if DEBUG
        os_log("[Effects] Disabled effect on %{public}@ and restored main gradient", device.name)
        #endif
    }
    
    func updateEffectSpeed(for device: WLEDDevice, segmentId: Int = 0, speed: Int) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.speed = max(0, min(255, speed))
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, fullStrip: useFullStrip)
    }
    
    func updateEffectIntensity(for device: WLEDDevice, segmentId: Int = 0, intensity: Int) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.intensity = max(0, min(255, intensity))
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, fullStrip: useFullStrip)
    }
    
    func updateEffectPalette(for device: WLEDDevice, segmentId: Int = 0, paletteId: Int) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.paletteId = max(0, paletteId)  // Only set palette when explicitly requested (no colors)
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, colors: nil, turnOn: nil, fullStrip: useFullStrip)
    }
    
    private func updateEffectStateCache(_ state: DeviceEffectState, deviceId: String, segmentId: Int) {
        var segmentStates = effectStates[deviceId] ?? [:]
        segmentStates[segmentId] = state
        effectStates[deviceId] = segmentStates
    }
    
    private func applyEffectState(
        _ state: DeviceEffectState,
        to device: WLEDDevice,
        segmentId: Int,
        colors: [[Int]]? = nil,
        turnOn: Bool? = nil,
        releaseRealtime: Bool = false,
        fullStrip: Bool = false
    ) async {
        do {
            let currentDevice = devices.first(where: { $0.id == device.id }) ?? device
            #if DEBUG
            os_log("[Effects] Sending fx=%d speed=%d intensity=%d palette=%@ turnOn=%@ colors=%@ to device %{public}@ segment %d", log: OSLog.effects, type: .debug, state.effectId, state.speed, state.intensity, String(describing: state.paletteId), String(describing: turnOn), String(describing: colors), device.name, segmentId)
            #endif
            
            let effectivePalette: Int? = colors != nil ? nil : state.paletteId
            let deviceBrightness: Int?
            if turnOn == true {
                let fallback = lastBrightnessBeforeOff[device.id] ?? 128
                deviceBrightness = currentDevice.brightness > 0 ? currentDevice.brightness : fallback
            } else if currentDevice.brightness > 0 {
                deviceBrightness = currentDevice.brightness
            } else {
                deviceBrightness = nil
            }
            let responseState: WLEDState
            if fullStrip {
                let totalLEDs = totalLEDCount(for: currentDevice)
                let useAppSegments = appManagedSegmentDevices.contains(device.id)
                    || appManagedSegmentLayouts[device.id] != nil
                var updates: [SegmentUpdate] = []
                if useAppSegments {
                    let count = segmentCount(for: totalLEDs)
                    let ranges = segmentStops(totalLEDs: totalLEDs, segmentCount: count)
                    let includeLayout: Bool
                    if let layout = appManagedSegmentLayouts[device.id], layout.count == count {
                        includeLayout = false
                    } else {
                        let segments = currentDevice.state?.segments ?? []
                        includeLayout = !segmentsMatchLayout(segments, layout: ranges.map { SegmentBounds(start: $0.start, stop: $0.stop) }, segmentCount: count)
                    }
                    for (idx, range) in ranges.enumerated() {
                        updates.append(
                            SegmentUpdate(
                                id: idx,
                                start: includeLayout ? range.start : nil,
                                stop: includeLayout ? range.stop : nil,
                                on: turnOn,
                                col: colors,
                                cct: nil,
                                fx: state.effectId,
                                sx: state.speed,
                                ix: state.intensity,
                                pal: effectivePalette,
                                frz: false
                            )
                        )
                    }
                } else {
                    updates.append(
                        SegmentUpdate(
                            id: segmentId,
                            start: 0,
                            stop: totalLEDs,
                            len: totalLEDs,
                            on: turnOn,
                            col: colors,
                            cct: nil,
                            fx: state.effectId,
                            sx: state.speed,
                            ix: state.intensity,
                            pal: effectivePalette,
                            frz: false
                        )
                    )
                }
                let managedIds = Set(updates.compactMap { $0.id })
                var knownIds = Set<Int>()
                if let segments = currentDevice.state?.segments, !segments.isEmpty {
                    for (index, segment) in segments.enumerated() {
                        knownIds.insert(segment.id ?? index)
                    }
                } else if let layout = appManagedSegmentLayouts[device.id], !layout.isEmpty {
                    knownIds = Set(0..<layout.count)
                } else if useAppSegments {
                    knownIds = Set(0..<segmentCount(for: totalLEDs))
                }
                for id in knownIds where !managedIds.contains(id) {
                    updates.append(SegmentUpdate(id: id, on: false, fx: 0, pal: 0))
                }
                let stateUpdate = WLEDStateUpdate(
                    on: turnOn,
                    bri: deviceBrightness,
                    seg: updates,
                    lor: releaseRealtime ? 0 : nil
                )
                let response = try await apiService.updateState(for: device, state: stateUpdate)
                responseState = response.state
            } else {
                let response = try await apiService.setEffect(
                    state.effectId,
                    forSegment: segmentId,
                    speed: state.speed,
                    intensity: state.intensity,
                    palette: state.paletteId,
                    colors: colors,
                    device: device,
                    turnOn: turnOn,
                    releaseRealtime: releaseRealtime  // Include realtime release atomically
                )
                responseState = response
            }
            
            #if DEBUG
            print("[Effects][API] Initial response has \(responseState.segments.count) segment(s)")
            #endif
            
            // WLED's POST /json/state might not return segments, so fetch state separately to verify
            // Skip verification fetch for full-strip effects to reduce timeouts/lag.
            var verifiedSegments = responseState.segments
            if responseState.segments.isEmpty {
                if fullStrip {
                    verifiedSegments = []
                } else {
                    #if DEBUG
                    print("[Effects][API] Response missing segments, fetching fresh state to verify...")
                    #endif
                    do {
                        // Small delay to let WLED process the update
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        let verifiedResponse = try await apiService.getState(for: device)
                        verifiedSegments = verifiedResponse.state.segments
                        #if DEBUG
                        print("[Effects][API] Fresh state fetch returned \(verifiedSegments.count) segment(s)")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[Effects][WARNING] Failed to fetch fresh state for verification: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
            
            #if DEBUG
            if let seg = verifiedSegments.first(where: { ($0.id ?? 0) == segmentId }) ?? verifiedSegments.first {
                print("[Effects][API] Verified segment: fx=\(seg.fx ?? -1) pal=\(seg.pal ?? -1) sx=\(seg.sx ?? -1) ix=\(seg.ix ?? -1) on=\(seg.on ?? false)")
                print("[Effects][API] Verified colors: \(String(describing: seg.colors))")
                
                // Verify effect was actually applied
                if let returnedFx = seg.fx {
                    if returnedFx == 0 {
                        print("[Effects][WARNING] ⚠️ Effect was disabled! Sent fx=\(state.effectId) but WLED returned fx=0 (disabled)")
                    } else if returnedFx != state.effectId {
                        print("[Effects][WARNING] ⚠️ Effect mismatch! Sent fx=\(state.effectId) but WLED returned fx=\(returnedFx)")
                    } else {
                        print("[Effects][SUCCESS] ✅ Effect \(state.effectId) confirmed active on device")
                    }
                } else {
                    print("[Effects][WARNING] ⚠️ WLED response missing fx field!")
                }
            } else if !fullStrip {
                print("[Effects][ERROR] ❌ No segment found in verified state!")
            }
            #endif
            
            // Update cached effect state from verified response
            await MainActor.run {
                var segmentStates = effectStates[device.id] ?? [:]
                if let seg = verifiedSegments.first(where: { ($0.id ?? 0) == segmentId }) ?? verifiedSegments.first {
                    let confirmedState = DeviceEffectState(
                        effectId: seg.fx ?? state.effectId,
                        speed: seg.sx ?? state.speed,
                        intensity: seg.ix ?? state.intensity,
                        paletteId: seg.pal ?? state.paletteId,
                        isEnabled: (seg.fx ?? 0) != 0
                    )
                    segmentStates[segmentId] = confirmedState
                    effectStates[device.id] = segmentStates
                } else if fullStrip {
                    segmentStates[segmentId] = state
                    effectStates[device.id] = segmentStates
                }
            }
            
            clearError()
        } catch {
            #if DEBUG
            os_log("[Effects][ERROR] Failed to apply effect: %{public}@", log: OSLog.effects, type: .error, error.localizedDescription)
            #endif
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
    }
    
    private func updateDevice(_ deviceId: String, with state: WLEDState) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            var updatedDevice = devices[index]
            updatedDevice.brightness = state.brightness
            updatedDevice.isOn = state.isOn
            updatedDevice.state = state
            updatedDevice.lastSeen = Date()
            if let segment = state.segments.first {
                updatedDevice.temperature = segment.cctNormalized
                if let color = derivedColor(from: segment) {
                    updatedDevice.currentColor = color
                }
            }
            devices[index] = updatedDevice
            deviceStateCache[deviceId] = (updatedDevice, Date())
            Task.detached(priority: .background) {
                await CoreDataManager.shared.saveDevice(updatedDevice)
            }
        }
    }
    
    private func stateUpdate(from state: WLEDState) -> WLEDStateUpdate {
        let segments = state.segments.map { segment in
            SegmentUpdate(
                id: segment.id,
                start: segment.start,
                stop: segment.stop,
                len: segment.len,
                grp: segment.grp,
                spc: segment.spc,
                ofs: segment.ofs,
                on: segment.on,
                bri: segment.bri,
                col: segment.colors,
                cct: segment.cct,
                fx: segment.fx,
                sx: segment.sx,
                ix: segment.ix,
                pal: segment.pal,
                sel: segment.sel,
                rev: segment.rev,
                mi: segment.mi,
                cln: segment.cln,
                frz: segment.frz
            )
        }
        return WLEDStateUpdate(
            on: state.isOn,
            bri: state.brightness,
            seg: segments
        )
    }
    
    // MARK: - Refresh Coalescing
    private var _lastRefreshRequested: Date?
    
    // MARK: - Additional Device Control Methods
    
    func setDeviceBrightness(_ device: WLEDDevice, brightness: Int) async {
        await updateDeviceBrightness(device, brightness: brightness)
    }
    
    func setDeviceColor(_ device: WLEDDevice, color: Color) async {
        await updateDeviceColor(device, color: color)
    }
    
    func refreshAllDevicesStates() async {
        await refreshDevices()
    }
    
    // Method for DashboardViewModel compatibility
    func refreshAllDevices() async {
        await refreshDevices()
    }
    
    // MARK: - Reconnection Control
    
    func forceReconnection(_ device: WLEDDevice) async {
        await connectionMonitor.forceReconnection(device.id)
    }
    
    func resetReconnectionAttempts(_ device: WLEDDevice) {
        connectionMonitor.resetReconnectionAttempts(device.id)
    }
    
    func getReconnectionStatus(_ device: WLEDDevice) -> String {
        return connectionMonitor.getReconnectionStatus(device.id)
    }
    
    func getConnectionHistory(_ device: WLEDDevice) -> [ConnectionAttempt] {
        return connectionMonitor.getConnectionHistory(device.id)
    }
    
    func isDeviceOnline(_ device: WLEDDevice) -> Bool {
        return connectionMonitor.isDeviceOnline(device.id)
    }
    
    // MARK: - Real-Time Control
    
    func enableRealTimeUpdates() {
        isRealTimeEnabled = true
    }
    
    func disableRealTimeUpdates() {
        isRealTimeEnabled = false
    }
    
    func toggleRealTimeUpdates() {
        isRealTimeEnabled.toggle()
    }
    
    func connectRealTimeForDevice(_ device: WLEDDevice) {
        // Skip off-subnet devices
        guard isIPInCurrentSubnets(device.ipAddress) else { return }
        connectWebSocketIfNeeded(for: device)
    }
    
    func disconnectRealTimeForDevice(_ device: WLEDDevice) {
        disconnectWebSocket(for: device)
    }
    
    func refreshRealTimeConnections() {
        if isRealTimeEnabled {
            connectWebSocketsForAllDevices()
        } else {
            disconnectAllWebSockets()
        }
    }
    
    // MARK: - Prefetching Helpers
    
    /// Warm up data and connections for a device detail view
    func prefetchDeviceDetailData(for device: WLEDDevice) async {
        // Refresh latest state in background if on subnet
        if isIPInCurrentSubnets(device.ipAddress) {
            await refreshDeviceState(device)
        }
        
        // Ensure real-time connection if enabled
        if isIPInCurrentSubnets(device.ipAddress) {
            connectWebSocketIfNeeded(for: device)
        }
    }

    // MARK: - Network Helpers
    private func isIPInCurrentSubnets(_ ip: String) -> Bool {
        let bases = currentSubnetBases()
        let base = subnetBase(for: ip)
        return bases.contains(base)
    }

    private func currentSubnetBases() -> Set<String> {
        var bases: Set<String> = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return bases }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("bridge") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: host)
                    let base = subnetBase(for: ip)
                    if !base.isEmpty { bases.insert(base) }
                }
            }
        }
        return bases
    }

    private func subnetBase(for ip: String) -> String {
        let comps = ip.split(separator: ".")
        if comps.count >= 3 { return "\(comps[0]).\(comps[1]).\(comps[2])" }
        return ""
    }
    
    // MARK: - Error Handling
    
    func dismissError() {
        clearError()
    }
    
    private func clearError() {
        currentError = nil
        errorMessage = nil
    }
    
    private func presentError(_ error: WLEDError) {
        if currentError == error { return }
        currentError = error
        errorMessage = error.message
    }
    
    private func resolvedDeviceName(for device: WLEDDevice?, providedName: String?) -> String? {
        if let provided = providedName, !provided.isEmpty { return provided }
        return device?.name
    }
    
    private func mapToWLEDError(_ error: Error, device: WLEDDevice?) -> WLEDError {
        if let apiError = error as? WLEDAPIError {
            switch apiError {
            case .deviceOffline(let name), .deviceUnreachable(let name):
                return .deviceOffline(deviceName: resolvedDeviceName(for: device, providedName: name))
            case .timeout, .maxRetriesExceeded:
                return .timeout(deviceName: device?.name)
            case .invalidResponse, .decodingError, .encodingError:
                return .invalidResponse
            case .invalidURL:
                return .apiError(message: "Invalid device URL configuration.")
            case .unsupportedOperation(let operation):
                return .apiError(message: "Operation \(operation) is not supported on this device.")
            case .deviceBusy(let name):
                let resolved = resolvedDeviceName(for: device, providedName: name) ?? "Device"
                return .apiError(message: "\(resolved) is busy. Try again shortly.")
            case .networkError(let underlying):
                return .apiError(message: underlying.localizedDescription)
            case .httpError:
                return .apiError(message: apiError.errorDescription ?? "HTTP error")
            case .invalidConfiguration:
                return .apiError(message: "Invalid configuration. Check API settings.")
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout(deviceName: device?.name)
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .deviceOffline(deviceName: device?.name)
            default:
                return .apiError(message: urlError.localizedDescription)
            }
        }
        return .apiError(message: error.localizedDescription)
    }

    // MARK: - Gradient Helpers (foundation)

    /// Apply gradient stops across the LED strip (original per-LED implementation)
    /// - Parameters:
    ///   - device: The WLED device
    ///   - stops: Gradient stops to apply
    ///   - ledCount: Number of LEDs
    ///   - stopTemperatures: Optional mapping of stop IDs to temperature values (0.0-1.0)
    ///   - disableActiveEffect: Whether to disable active effects before applying gradient (default: false to avoid interference)
    /// Determine if a gradient should use WLED native transition (tt) or client-side transition
    /// - Parameters:
    ///   - stops: Gradient stops to check
    ///   - durationSeconds: Duration of transition (> 0 for native transition)
    /// - Returns: true if should use native WLED transition, false if client-side is needed
    func shouldUseNativeTransition(stops: [GradientStop], durationSeconds: Double) -> Bool {
        guard durationSeconds > 0 else { return false }
        
        // Centralized solid color detection: single stop OR all stops have same color
        let sortedStops = stops.sorted { $0.position < $1.position }
        guard let firstColorHex = sortedStops.first?.hexColor else { return false }
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == firstColorHex }
        
        // Use native transition for solid colors (WLED can handle simple color transitions efficiently)
        // For complex gradients with multiple colors, use client-side transition runner
        return isSolidColor
    }
    
    func applyGradientStopsAcrossStrip(_ device: WLEDDevice, stops: [GradientStop], ledCount: Int, stopTemperatures: [UUID: Double]? = nil, stopWhiteLevels: [UUID: Double]? = nil, disableActiveEffect: Bool = false, segmentId: Int = 0, interpolation: GradientInterpolation = .linear, brightness: Int? = nil, on: Bool? = nil, transitionDurationSeconds: Double? = nil, forceNoPerCallTransition: Bool = false, releaseRealtimeOverride: Bool = true, userInitiated: Bool = true, preferSegmented: Bool = false) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        if userInitiated, activeRunStatus[device.id] != nil {
            await cancelActiveRun(for: device, force: true)
        }
        
        // CRITICAL: Mark user interaction only for user-driven updates
        if userInitiated {
            markUserInteraction(device.id)
        }
        
        let sortedStops = stops.sorted { $0.position < $1.position }
        latestGradientStops[device.id] = sortedStops
        persistLatestGradient(sortedStops, for: device.id)
        let allowPerLed = allowPerLedFallback(for: device)
        
        // OPTIMIZATION: Solid color detection (single stop OR all stops have same color)
        // Use segment col field for solid colors (more efficient than per-LED upload)
        // This matches WLED's recommended approach for solid colors
        let firstColorHex = sortedStops.first?.hexColor
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == firstColorHex }
        let willUseSegmented = isSolidColor
            ? (preferSegmented || appManagedSegmentDevices.contains(device.id))
            : (preferSegmented || transitionDurationSeconds != nil || !allowPerLed || appManagedSegmentDevices.contains(device.id))

        // Only disable effects ahead of time for per-LED uploads.
        if disableActiveEffect,
           currentEffectState(for: device, segmentId: segmentId).isEnabled,
           !willUseSegmented {
            // Simply set effect to 0 without the full disableEffect flow that causes interference
            var state = currentEffectState(for: device, segmentId: segmentId)
            state.effectId = 0
            state.isEnabled = false
            updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
            
            // Send minimal effect-off update (no releaseRealtimeOverride, no recursive gradient call)
            let segmentUpdate = SegmentUpdate(id: segmentId, fx: 0, pal: 0, frz: false)
            let stateUpdate = WLEDStateUpdate(seg: [segmentUpdate])
            _ = try? await apiService.updateState(for: device, state: stateUpdate)
        }

        if isSolidColor, willUseSegmented {
            let gradient = LEDGradient(stops: sortedStops, interpolation: interpolation)
            await applySegmentedGradient(
                device,
                gradient: gradient,
                stopTemperatures: stopTemperatures,
                stopWhiteLevels: stopWhiteLevels,
                brightness: brightness,
                on: on,
                transitionDurationSeconds: transitionDurationSeconds,
                forceNoPerCallTransition: forceNoPerCallTransition,
                releaseRealtimeOverride: releaseRealtimeOverride,
                segmentId: segmentId,
                disableActiveEffect: disableActiveEffect
            )
            return
        }

        if !isSolidColor, willUseSegmented {
            let gradient = LEDGradient(stops: sortedStops, interpolation: interpolation)
            await applySegmentedGradient(
                device,
                gradient: gradient,
                stopTemperatures: stopTemperatures,
                stopWhiteLevels: stopWhiteLevels,
                brightness: brightness,
                on: on,
                transitionDurationSeconds: transitionDurationSeconds,
                forceNoPerCallTransition: forceNoPerCallTransition,
                releaseRealtimeOverride: releaseRealtimeOverride,
                segmentId: segmentId,
                disableActiveEffect: disableActiveEffect
            )
            return
        }
        
        if isSolidColor, let singleStop = sortedStops.first {
            // Check if this is truly a solid color (no temperature variation)
            let hasTemperature = stopTemperatures?[singleStop.id] != nil
            let allStopsHaveSameTemp: Bool
            if let tempMap = stopTemperatures, !tempMap.isEmpty {
                // CRITICAL: Use sortedStops consistently (not unsorted stops) for code consistency
                // While functionally harmless for single-stop cases, this ensures consistency throughout the function
                let temperatures = sortedStops.compactMap { tempMap[$0.id] }
                allStopsHaveSameTemp = temperatures.count <= 1 || temperatures.allSatisfy { abs($0 - temperatures[0]) < 0.001 }
            } else {
                allStopsHaveSameTemp = true
            }
            
            // Use segment col field for single solid color (more efficient)
            let rgb = Color(hex: singleStop.hexColor).toRGBArray()
            var cct: Int? = nil
            var normalizedTemp: Double? = nil
            var whiteLevel: Int? = nil
            let supportsWhiteValue = supportsWhite(for: device, segmentId: segmentId)
            let allowManualWhite = supportsWhiteValue && UserDefaults.standard.bool(forKey: "advancedUIEnabled")
            let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
            let supportsCCTDevice = supportsCCT(for: device, segmentId: segmentId)
            
            // Handle CCT if provided and consistent
            if hasTemperature, allStopsHaveSameTemp, let temp = stopTemperatures?[singleStop.id] {
                normalizedTemp = temp
                let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: segmentId)
                cct = usesKelvin
                    ? kelvinValue(for: device, normalized: temp)
                    : Segment.eightBitValue(fromNormalized: temp)
            }

            if allowManualWhite, let whiteMap = stopWhiteLevels, !whiteMap.isEmpty {
                let whiteValues = sortedStops.compactMap { whiteMap[$0.id] }
                let allStopsHaveSameWhite = whiteValues.count == sortedStops.count &&
                    (whiteValues.count <= 1 || whiteValues.allSatisfy { abs($0 - whiteValues[0]) < 0.001 })
                if allStopsHaveSameWhite, let level = whiteMap[singleStop.id] {
                    whiteLevel = Int(round(max(0.0, min(1.0, level)) * 255.0))
                } else if isSolidColor, let level = whiteMap[singleStop.id] {
                    whiteLevel = Int(round(max(0.0, min(1.0, level)) * 255.0))
                }
            }
            let useCCTOnly = allowCCTTemperatureStops && supportsCCTDevice && cct != nil && whiteLevel == nil

            #if DEBUG
            if let cct, useCCTOnly {
                print("🔵 [Gradient] Solid color uses CCT-only update (segmentId=\(segmentId), cct=\(cct))")
            } else if let cct {
                if let whiteLevel {
                    print("🔵 [Gradient] Solid color uses CCT + white update (segmentId=\(segmentId), cct=\(cct), white=\(whiteLevel))")
                } else {
                    print("🔵 [Gradient] Solid color uses CCT-only update (segmentId=\(segmentId), cct=\(cct))")
                }
            } else if let whiteLevel {
                print("🔵 [Gradient] Solid color uses RGBW update (segmentId=\(segmentId), white=\(whiteLevel))")
            }
            #endif
            
            // Build segment update with col field (WLED's efficient solid color method)
            let segment: SegmentUpdate
            if let cctValue = cct, useCCTOnly {
                let derivedRGB = normalizedTemp.map { rgbArrayForTemperature($0) } ?? [0, 0, 0]
                let clearColor = supportsWhiteValue ? (derivedRGB + [0]) : derivedRGB
                let clearSegment = SegmentUpdate(
                    id: segmentId,
                    col: [clearColor],
                    fx: disableActiveEffect ? 0 : nil
                )
                let clearState = WLEDStateUpdate(
                    on: on,
                    bri: brightness,
                    seg: [clearSegment],
                    transition: nil
                )
                do {
                    _ = try await apiService.updateState(for: device, state: clearState)
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to clear RGB before CCT update for device \(device.name): \(error)")
                    #endif
                }
                segment = SegmentUpdate(
                    id: segmentId,
                    cct: cctValue,
                    fx: disableActiveEffect ? 0 : nil
                )
            } else {
                var colorArray = [rgb[0], rgb[1], rgb[2]]
                if let whiteLevel {
                    colorArray.append(whiteLevel)
                }
                segment = SegmentUpdate(
                    id: segmentId,
                    col: [colorArray],
                    fx: disableActiveEffect ? 0 : nil
                )
            }
            // CRITICAL: Include on and brightness in state update if provided
            // This ensures power-on/brightness is applied ALONG WITH color in SAME API call
            // This prevents WLED from showing restored colors before color is applied
            // Include transition time if provided (for solid color transitions)
            let transitionMs = forceNoPerCallTransition ? nil : clampedTransitionMs(for: transitionDurationSeconds)
            let stateUpdate = WLEDStateUpdate(
                on: on,  // CRITICAL: Include power state if provided (for power-on operations)
                bri: brightness,  // Set brightness if provided
                seg: [segment],
                transition: transitionMs  // Include transition time for native WLED transition
            )
            
            do {
                _ = try await apiService.updateState(for: device, state: stateUpdate)
                
                // Send WebSocket update if connected
                if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                    webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
                }
                
                // Mark gradient application time to prevent WebSocket overwrites
                await MainActor.run {
                    self.gradientApplicationTimes[device.id] = Date()
                    
                    // Optimistically update the device's current color, brightness, and power state
                    // CRITICAL: Update all state that was included in the API call to keep UI in sync
                    if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                        if let temp = normalizedTemp {
                            if let whiteLevel {
                                self.devices[index].currentColor = Color.color(fromRGBArray: rgb, white: whiteLevel)
                            } else {
                                self.devices[index].currentColor = Color.color(fromCCTTemperature: temp)
                            }
                            self.devices[index].temperature = temp
                        } else if let whiteLevel {
                            self.devices[index].currentColor = Color.color(fromRGBArray: rgb, white: whiteLevel)
                            self.devices[index].temperature = nil
                        } else {
                            self.devices[index].currentColor = Color(hex: singleStop.hexColor)
                            self.devices[index].temperature = nil
                        }
                        // CRITICAL: Update brightness if provided in API call
                        if let brightnessValue = brightness {
                            self.devices[index].brightness = brightnessValue
                        }
                        // CRITICAL: Update power state if provided in API call
                        if let onValue = on {
                            self.devices[index].isOn = onValue
                        }
                    }
                }
                
                #if DEBUG
                print("✅ [Gradient] Applied single-stop solid color via segment col field (optimized)")
                #endif
                return  // Early return - more efficient than per-LED upload
            } catch {
                // Fallback to per-LED upload only if allowed
                #if DEBUG
                print("⚠️ [Gradient] Segment col update failed: \(error)")
                #endif
                if !allowPerLed {
                    return
                }
            }
        }
        
        if !allowPerLed {
            return
        }
        
        // Multi-stop gradient: Use per-LED colors (required for gradient blending)
        // CRITICAL: Use sortedStops consistently (not unsorted stops) for code consistency and correctness
        // This ensures gradient colors are sampled in the correct order matching temperature collection
        let gradient = LEDGradient(stops: sortedStops, interpolation: interpolation)
        let resolvedLedCount = appManagedSegmentDevices.contains(device.id) ? totalLEDCount(for: device) : max(1, ledCount)
        let frame = GradientSampler.sample(gradient, ledCount: resolvedLedCount, interpolation: interpolation)
        var intent = ColorIntent(deviceId: device.id, mode: .perLED)
        intent.segmentId = segmentId
        intent.perLEDHex = frame
        
        // CRITICAL: Set on and brightness if provided
        // This ensures power-on/brightness is applied ALONG WITH gradient colors in SAME API call
        // This prevents WLED from showing restored colors before gradient is applied
        if let onValue = on {
            intent.on = onValue
        }
        if let bri = brightness {
            intent.brightness = bri
        }
        
        // Check if all stops have the same temperature, send CCT if they do
        let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
        if allowCCTTemperatureStops, let tempMap = stopTemperatures, !tempMap.isEmpty {
            // CRITICAL: Use sortedStops consistently (not unsorted stops) for code consistency and correctness
            // This ensures temperatures are collected in the same order as stops are processed
            // Collect all temperatures from stops that have them
            let temperatures = sortedStops.compactMap { stop -> Double? in
                tempMap[stop.id]
            }
            if temperatures.count == sortedStops.count, !temperatures.isEmpty {
                // If all stops with temperatures share the same temperature, use it
                let firstTemp = temperatures[0]
                let allSame = temperatures.allSatisfy { abs($0 - firstTemp) < 0.001 }
                
                if allSame {
                    // Convert temperature (0.0-1.0) to CCT (0-255)
                    let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: segmentId)
                    let cct = usesKelvin
                        ? kelvinValue(for: device, normalized: firstTemp)
                        : Segment.eightBitValue(fromNormalized: firstTemp)
                    if supportsCCT(for: device, segmentId: segmentId) {
                        intent.cct = cct
                    }
                }
            }
        }
        
        await colorPipeline.apply(intent, to: device)
        
        // Mark gradient application time to prevent WebSocket overwrites
        await MainActor.run {
            self.gradientApplicationTimes[device.id] = Date()
            
            // Optimistically update the device's current color to the first stop
            if let index = self.devices.firstIndex(where: { $0.id == device.id }),
               let firstStop = sortedStops.first {
                self.devices[index].currentColor = Color(hex: firstStop.hexColor)
                self.devices[index].temperature = nil
            }
        }
    }

    private func segmentCount(for ledCount: Int) -> Int {
        guard ledCount > 0 else { return 0 }
        let capped = min(defaultSegmentCount, maxSegmentCount)
        return min(ledCount, max(2, capped))
    }

    private func segmentStops(totalLEDs: Int, segmentCount: Int) -> [(start: Int, stop: Int)] {
        guard totalLEDs > 0, segmentCount > 0 else { return [] }
        let base = totalLEDs / segmentCount
        let remainder = totalLEDs % segmentCount
        var stops: [(Int, Int)] = []
        var cursor = 0
        for idx in 0..<segmentCount {
            let extra = idx < remainder ? 1 : 0
            let len = max(1, base + extra)
            let start = cursor
            let stop = min(totalLEDs, cursor + len)
            stops.append((start: start, stop: stop))
            cursor = stop
        }
        return stops
    }

    private func segmentsMatchLayout(
        _ segments: [Segment],
        layout: [SegmentBounds],
        segmentCount: Int
    ) -> Bool {
        guard segmentCount > 0, segments.count >= segmentCount else { return false }
        for idx in 0..<segmentCount {
            let target = layout[idx]
            let segment = segments.first(where: { ($0.id ?? idx) == idx }) ?? segments[idx]
            if segment.start != target.start || segment.stop != target.stop {
                return false
            }
        }
        return true
    }

    private func segmentColors(for gradient: LEDGradient, count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let denom = Double(count)
        return (0..<count).map { idx in
            let t = (Double(idx) + 0.5) / denom
            let color = GradientSampler.sampleColor(at: t, stops: sortedStops, interpolation: gradient.interpolation)
            return color.toRGBArray()
        }
    }

    private func segmentWhiteLevels(
        for gradient: LEDGradient,
        count: Int,
        stopWhiteLevels: [UUID: Double]?
    ) -> [Int]? {
        guard count > 0, let stopWhiteLevels, !stopWhiteLevels.isEmpty else { return nil }
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let values = sortedStops.map { stopWhiteLevels[$0.id] ?? 0.0 }
        let hasWhite = values.contains { abs($0) > 0.0001 }
        guard hasWhite else { return nil }
        let denom = Double(count)
        return (0..<count).map { idx in
            let t = (Double(idx) + 0.5) / denom
            let value = interpolateScalar(stops: sortedStops, values: values, t: t, interpolation: gradient.interpolation)
            let clamped = max(0.0, min(1.0, value))
            return Int(round(clamped * 255.0))
        }
    }

    private func boundingStopIndices(for t: Double, stops: [GradientStop]) -> (Int, Int)? {
        guard !stops.isEmpty else { return nil }
        let clampedT = max(0.0, min(1.0, t))
        if let first = stops.first, clampedT <= first.position {
            return (0, 0)
        }
        if let last = stops.last, clampedT >= last.position {
            let lastIndex = max(0, stops.count - 1)
            return (lastIndex, lastIndex)
        }
        for idx in 0..<(stops.count - 1) {
            if clampedT >= stops[idx].position && clampedT <= stops[idx + 1].position {
                return (idx, idx + 1)
            }
        }
        return nil
    }

    private func segmentTemperatures(
        for gradient: LEDGradient,
        count: Int,
        stopTemperatures: [UUID: Double]?
    ) -> [Double?] {
        guard count > 0, let stopTemperatures, !stopTemperatures.isEmpty else {
            return Array(repeating: nil, count: count)
        }
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let denom = Double(count)
        return (0..<count).map { idx in
            let t = (Double(idx) + 0.5) / denom
            guard let (aIndex, bIndex) = boundingStopIndices(for: t, stops: sortedStops) else {
                return nil
            }
            let aStop = sortedStops[aIndex]
            let bStop = sortedStops[bIndex]
            guard let aTemp = stopTemperatures[aStop.id], let bTemp = stopTemperatures[bStop.id] else {
                return nil
            }
            if aIndex == bIndex {
                return aTemp
            }
            let span = max(0.000001, bStop.position - aStop.position)
            let rawLocalT = (t - aStop.position) / span
            let easedLocalT = applyInterpolation(rawLocalT, mode: gradient.interpolation)
            return aTemp + (bTemp - aTemp) * easedLocalT
        }
    }

    private func rgbArrayForTemperature(_ temperature: Double) -> [Int] {
        let color = Color.color(fromCCTTemperature: temperature)
        return color.toRGBArray()
    }

    private func interpolateScalar(
        stops: [GradientStop],
        values: [Double],
        t: Double,
        interpolation: GradientInterpolation
    ) -> Double {
        let clampedT = max(0.0, min(1.0, t))
        guard let first = stops.first, let last = stops.last else { return 0.0 }
        if clampedT <= first.position { return values.first ?? 0.0 }
        if clampedT >= last.position { return values.last ?? 0.0 }
        var aIndex = 0
        var bIndex = 1
        for idx in 0..<(stops.count - 1) {
            if clampedT >= stops[idx].position && clampedT <= stops[idx + 1].position {
                aIndex = idx
                bIndex = idx + 1
                break
            }
        }
        let a = stops[aIndex]
        let b = stops[bIndex]
        let span = max(0.000001, b.position - a.position)
        let rawLocalT = (clampedT - a.position) / span
        let easedLocalT = applyInterpolation(rawLocalT, mode: interpolation)
        let aValue = values[aIndex]
        let bValue = values[bIndex]
        return aValue + (bValue - aValue) * easedLocalT
    }

    private func applyInterpolation(_ t: Double, mode: GradientInterpolation) -> Double {
        let clampedT = max(0.0, min(1.0, t))
        switch mode {
        case .linear:
            return clampedT
        case .easeInOut:
            if clampedT < 0.5 {
                return 4 * clampedT * clampedT * clampedT
            }
            return 1 - pow(-2 * clampedT + 2, 3) / 2
        case .easeIn:
            return clampedT * clampedT * clampedT
        case .easeOut:
            return 1 - pow(1 - clampedT, 3)
        case .cubic:
            let t2 = clampedT * clampedT
            let t3 = t2 * clampedT
            return 3 * t2 - 2 * t3
        }
    }

    private func uniformCCTIfAvailable(
        device: WLEDDevice,
        stops: [GradientStop],
        stopTemperatures: [UUID: Double]?
    ) -> Int? {
        guard let temps = stopTemperatures, !temps.isEmpty else { return nil }
        if supportsCCT(for: device, segmentId: 0) == false {
            return nil
        }
        let sortedStops = stops.sorted { $0.position < $1.position }
        let values = sortedStops.compactMap { temps[$0.id] }
        guard values.count == sortedStops.count, !values.isEmpty else { return nil }
        let first = values[0]
        guard values.allSatisfy({ abs($0 - first) < 0.001 }) else { return nil }
        let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: 0)
        return usesKelvin
            ? kelvinValue(for: device, normalized: first)
            : Segment.eightBitValue(fromNormalized: first)
    }

    private func uniformNormalizedTemperatureIfAvailable(
        stops: [GradientStop],
        stopTemperatures: [UUID: Double]?
    ) -> Double? {
        guard let temps = stopTemperatures, !temps.isEmpty else { return nil }
        let sortedStops = stops.sorted { $0.position < $1.position }
        let values = sortedStops.compactMap { temps[$0.id] }
        guard values.count == sortedStops.count, !values.isEmpty else { return nil }
        let first = values[0]
        guard values.allSatisfy({ abs($0 - first) < 0.001 }) else { return nil }
        return first
    }

    private func uniformWhiteLevelIfAvailable(
        stops: [GradientStop],
        stopWhiteLevels: [UUID: Double]?
    ) -> Int? {
        guard let levels = stopWhiteLevels, !levels.isEmpty else { return nil }
        let sortedStops = stops.sorted { $0.position < $1.position }
        let values = sortedStops.compactMap { levels[$0.id] }
        guard values.count == sortedStops.count, !values.isEmpty else { return nil }
        let first = values[0]
        guard values.allSatisfy({ abs($0 - first) < 0.001 }) else { return nil }
        return Int(round(max(0.0, min(1.0, first)) * 255.0))
    }

    private func derivedColor(from segment: Segment) -> Color? {
        if let normalized = segment.cctNormalized {
            return Color.color(fromCCTTemperature: normalized)
        }
        if let colors = segment.colors,
           let first = colors.first,
           first.count >= 3 {
            return Color.color(fromRGBArray: first)
        }
        return nil
    }

    private func applySegmentedGradient(
        _ device: WLEDDevice,
        gradient: LEDGradient,
        stopTemperatures: [UUID: Double]?,
        stopWhiteLevels: [UUID: Double]?,
        brightness: Int?,
        on: Bool?,
        transitionDurationSeconds: Double?,
        forceNoPerCallTransition: Bool,
        releaseRealtimeOverride: Bool,
        segmentId: Int,
        disableActiveEffect: Bool
    ) async {
        appManagedSegmentDevices.insert(device.id)

        let totalLEDs = totalLEDCount(for: device)
        guard totalLEDs > 0 else { return }
        let count = segmentCount(for: totalLEDs)
        let stops = segmentStops(totalLEDs: totalLEDs, segmentCount: count)
        let layout = stops.map { SegmentBounds(start: $0.start, stop: $0.stop) }
        let existingLayout = appManagedSegmentLayouts[device.id]
        let deviceSegments = device.state?.segments ?? []
        let layoutMatches = segmentsMatchLayout(deviceSegments, layout: layout, segmentCount: count)
        let includeLayout = existingLayout == nil || existingLayout != layout || !layoutMatches
        let colors = segmentColors(for: gradient, count: count)
        let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
        let supportsCCTDevice = supportsCCT(for: device, segmentId: 0)
        let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: 0)
        let segmentTemperatures = (allowCCTTemperatureStops && supportsCCTDevice)
            ? segmentTemperatures(for: gradient, count: count, stopTemperatures: stopTemperatures)
            : nil
        let supportsWhiteValue = supportsWhite(for: device, segmentId: 0)
        let allowManualWhite = supportsWhiteValue && UserDefaults.standard.bool(forKey: "advancedUIEnabled")
        let manualWhiteLevels = allowManualWhite
            ? segmentWhiteLevels(for: gradient, count: count, stopWhiteLevels: stopWhiteLevels)
            : nil
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == sortedStops.first?.hexColor }
        let uniformTemp = uniformNormalizedTemperatureIfAvailable(stops: gradient.stops, stopTemperatures: stopTemperatures)
        let effectiveTemp = uniformTemp ?? (isSolidColor ? stopTemperatures?.values.first : nil)
        let uniformWhite = allowManualWhite
            ? uniformWhiteLevelIfAvailable(stops: gradient.stops, stopWhiteLevels: stopWhiteLevels)
            : nil
        let effectiveWhite: Int? = {
            if let uniformWhite {
                return uniformWhite
            }
            if allowManualWhite, isSolidColor, let first = stopWhiteLevels?.values.first {
                return Int(round(max(0.0, min(1.0, first)) * 255.0))
            }
            return nil
        }()
        let useWhite = manualWhiteLevels != nil || effectiveWhite != nil
        let hasCCTSegments = segmentTemperatures?.contains { $0 != nil } ?? false
        let effectReset = disableActiveEffect ? 0 : nil

        #if DEBUG
        if hasCCTSegments {
            print("🔵 [Segmented] Using mixed CCT/RGB updates")
        } else if useWhite, let effectiveWhite {
            print("🔵 [Segmented] Using RGBW update (white=\(effectiveWhite))")
        }
        #endif

        var updates: [SegmentUpdate] = []
        updates.reserveCapacity(stops.count)
        for (idx, range) in stops.enumerated() {
            let rgb = colors[idx]
            var col: [[Int]]? = [[rgb[0], rgb[1], rgb[2]]]
            var cctValue: Int? = nil
            let whiteValue = manualWhiteLevels?[idx] ?? effectiveWhite
            if let temp = segmentTemperatures?[idx],
               allowCCTTemperatureStops,
               supportsCCTDevice,
               whiteValue == nil {
                col = nil
                cctValue = usesKelvin
                    ? kelvinValue(for: device, normalized: temp)
                    : Segment.eightBitValue(fromNormalized: temp)
            } else if useWhite, let whiteValue {
                col = [[rgb[0], rgb[1], rgb[2], whiteValue]]
            }
            updates.append(
                SegmentUpdate(
                    id: idx,
                    start: includeLayout ? range.start : nil,
                    stop: includeLayout ? range.stop : nil,
                    on: on,
                    col: col,
                    cct: cctValue,
                    fx: effectReset,
                    pal: effectReset
                )
            )
        }

        let cctOnlySegments = updates.filter { $0.cct != nil && $0.col == nil }
        if !cctOnlySegments.isEmpty {
            var clearUpdates: [SegmentUpdate] = []
            clearUpdates.reserveCapacity(cctOnlySegments.count)
            for segment in cctOnlySegments {
                let derivedRGB: [Int]
                if let id = segment.id,
                   let temps = segmentTemperatures,
                   id >= 0,
                   id < temps.count,
                   let temp = temps[id] {
                    derivedRGB = rgbArrayForTemperature(temp)
                } else {
                    derivedRGB = [0, 0, 0]
                }
                let clearColor = supportsWhiteValue ? (derivedRGB + [0]) : derivedRGB
                clearUpdates.append(
                    SegmentUpdate(
                        id: segment.id,
                        start: segment.start,
                        stop: segment.stop,
                        on: on,
                        col: [clearColor],
                        fx: effectReset,
                        pal: effectReset
                    )
                )
            }
            let clearState = WLEDStateUpdate(
                on: on,
                bri: brightness,
                seg: clearUpdates,
                transition: nil
            )
            do {
                _ = try await apiService.updateState(for: device, state: clearState)
            } catch {
                #if DEBUG
                print("⚠️ Failed to clear RGB before CCT update for device \(device.name): \(error)")
                #endif
            }
        }

        if let existingSegments = device.state?.segments, !existingSegments.isEmpty {
            let managedIds = Set(0..<count)
            for (index, segment) in existingSegments.enumerated() {
                let existingId = segment.id ?? index
                if !managedIds.contains(existingId) {
                    updates.append(
                        SegmentUpdate(
                            id: existingId,
                            on: false,
                            fx: 0,
                            pal: 0
                        )
                    )
                }
            }
        }

        if disableActiveEffect {
            var segmentStates = effectStates[device.id] ?? [:]
            let updateIds = Set(updates.compactMap { $0.id })
            for id in updateIds {
                let existing = segmentStates[id] ?? .default
                segmentStates[id] = DeviceEffectState(
                    effectId: 0,
                    speed: existing.speed,
                    intensity: existing.intensity,
                    paletteId: nil,
                    isEnabled: false
                )
            }
            effectStates[device.id] = segmentStates
        }

        let transitionMs = forceNoPerCallTransition ? nil : clampedTransitionMs(for: transitionDurationSeconds)
        let shouldReleaseRealtime = releaseRealtimeOverride && transitionDurationSeconds != nil && !forceNoPerCallTransition
        let stateUpdate = WLEDStateUpdate(
            on: on,
            bri: brightness,
            seg: updates,
            transition: transitionMs,
            lor: shouldReleaseRealtime ? 0 : nil
        )

        do {
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            await MainActor.run {
                gradientApplicationTimes[device.id] = Date()
                appManagedSegmentLayouts[device.id] = layout
                let segmentStates: [Segment] = stops.enumerated().map { idx, range in
                    let length = max(0, range.stop - range.start)
                    return Segment(
                        id: idx,
                        start: range.start,
                        stop: range.stop,
                        len: length,
                        grp: nil,
                        spc: nil,
                        ofs: nil,
                        on: on,
                        bri: nil,
                        colors: nil,
                        cct: nil,
                        fx: effectReset,
                        sx: nil,
                        ix: nil,
                        pal: nil,
                        sel: nil,
                        rev: nil,
                        mi: nil,
                        cln: nil,
                        frz: nil
                    )
                }
                if let index = devices.firstIndex(where: { $0.id == device.id }),
                   let firstRGB = colors.first {
                    let firstTemp = segmentTemperatures?.first ?? effectiveTemp
                    let firstWhite = allowManualWhite ? (manualWhiteLevels?.first ?? effectiveWhite) : nil
                    let firstUsesCCT = allowCCTTemperatureStops &&
                        supportsCCTDevice &&
                        segmentTemperatures?.first != nil &&
                        firstWhite == nil
                    if firstUsesCCT, let temp = firstTemp {
                        devices[index].currentColor = Color.color(fromCCTTemperature: temp)
                    } else if useWhite, let whiteValue = firstWhite {
                        devices[index].currentColor = Color.color(fromRGBArray: firstRGB, white: whiteValue)
                    } else {
                        devices[index].currentColor = Color(
                            red: Double(firstRGB[0]) / 255.0,
                            green: Double(firstRGB[1]) / 255.0,
                            blue: Double(firstRGB[2]) / 255.0
                        )
                    }
                    devices[index].temperature = firstTemp
                    if let bri = brightness {
                        devices[index].brightness = bri
                    }
                    if let onValue = on {
                        devices[index].isOn = onValue
                    }
                    if let state = devices[index].state {
                        devices[index].state = WLEDState(
                            brightness: state.brightness,
                            isOn: state.isOn,
                            segments: segmentStates,
                            transitionDeciseconds: state.transitionDeciseconds,
                            presetId: state.presetId,
                            playlistId: state.playlistId
                        )
                    } else {
                        devices[index].state = WLEDState(
                            brightness: devices[index].brightness,
                            isOn: devices[index].isOn,
                            segments: segmentStates,
                            transitionDeciseconds: nil,
                            presetId: nil,
                            playlistId: nil
                        )
                    }
                }
                deviceLedCounts[device.id] = totalLEDs
            }
        } catch {
            #if DEBUG
            print("⚠️ Failed segmented gradient update for device \(device.name): \(error)")
            #endif
        }
    }

    private func segmentedPresetState(
        device: WLEDDevice,
        gradient: LEDGradient,
        brightness: Int,
        on: Bool,
        temperature: Double?,
        whiteLevel: Double?
    ) -> WLEDStateUpdate {
        let totalLEDs = totalLEDCount(for: device)
        let count = segmentCount(for: totalLEDs)
        let stops = segmentStops(totalLEDs: totalLEDs, segmentCount: count)
        let colors = segmentColors(for: gradient, count: count)
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == sortedStops.first?.hexColor }
        let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
        let supportsCCTDevice = supportsCCT(for: device, segmentId: 0)
        let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: 0)
        let cctValue: Int? = (isSolidColor && allowCCTTemperatureStops && supportsCCTDevice)
            ? temperature.map { temp in
                usesKelvin
                    ? kelvinValue(for: device, normalized: temp)
                    : Segment.eightBitValue(fromNormalized: temp)
            }
            : nil
        let whiteValue = whiteLevel.map { Int(round(max(0.0, min(1.0, $0)) * 255.0)) }
        let useCCTOnly = isSolidColor && cctValue != nil && whiteValue == nil

        var updates: [SegmentUpdate] = []
        for (idx, range) in stops.enumerated() {
            let rgb = colors[idx]
            var col: [[Int]]? = [[rgb[0], rgb[1], rgb[2]]]
            if useCCTOnly {
                col = nil
            } else if let whiteValue {
                col = [[rgb[0], rgb[1], rgb[2], whiteValue]]
            }
            updates.append(
                SegmentUpdate(
                    id: idx,
                    start: range.start,
                    stop: range.stop,
                    on: on,
                    col: col,
                    cct: useCCTOnly ? cctValue : nil,
                    fx: 0,
                    pal: 0
                )
            )
        }

        return WLEDStateUpdate(
            on: on,
            bri: brightness,
            seg: updates
        )
    }

    private func availableIds(from maxId: Int, excluding used: Set<Int>, count: Int) -> [Int]? {
        guard count > 0 else { return [] }
        var results: [Int] = []
        for id in stride(from: maxId, through: 1, by: -1) {
            guard !used.contains(id) else { continue }
            results.append(id)
            if results.count == count {
                break
            }
        }
        return results.count == count ? results : nil
    }

    private func availablePlaylistId(excluding used: Set<Int>) -> Int? {
        for id in stride(from: 250, through: 1, by: -1) {
            if !used.contains(id) {
                return id
            }
        }
        return nil
    }

    private func savePresetWithRetry(_ request: WLEDPresetSaveRequest, device: WLEDDevice) async throws {
        var lastError: Error?
        for attempt in 1...presetSaveRetryAttempts {
            do {
                try await apiService.savePreset(request, to: device)
                let delay = presetSaveDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
                return
            } catch {
                lastError = error
                if attempt < presetSaveRetryAttempts {
                    let delay = presetSaveDelayNanos * UInt64(attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError ?? WLEDAPIError.invalidResponse
    }

    private func verifyPresetIds(_ presetIds: [Int], device: WLEDDevice) async -> Bool {
        for attempt in 1...presetVerifyRetryAttempts {
            if let presets = try? await apiService.fetchPresets(for: device) {
                let savedIds = Set(presets.map { $0.id })
                if presetIds.allSatisfy({ savedIds.contains($0) }) {
                    return true
                }
            }
            if attempt < presetVerifyRetryAttempts {
                let delay = presetVerifyDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        return false
    }

    private func savePlaylistWithRetry(_ request: WLEDPlaylistSaveRequest, device: WLEDDevice) async throws {
        var lastError: Error?
        for attempt in 1...playlistSaveRetryAttempts {
            do {
                _ = try await apiService.savePlaylist(request, to: device)
                let delay = playlistSaveDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
                return
            } catch {
                lastError = error
                if attempt < playlistSaveRetryAttempts {
                    let delay = playlistSaveDelayNanos * UInt64(attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError ?? WLEDAPIError.invalidResponse
    }

    private func verifyPlaylistId(_ playlistId: Int, device: WLEDDevice) async -> Bool {
        if !(await apiService.isPlaylistStoreSupported(for: device)) {
            if let presets = try? await apiService.fetchPresets(for: device) {
                let savedIds = Set(presets.map { $0.id })
                return savedIds.contains(playlistId)
            }
            return true
        }
        for attempt in 1...playlistVerifyRetryAttempts {
            if let playlists = try? await apiService.fetchPlaylists(for: device),
               playlists.contains(where: { $0.id == playlistId }) {
                return true
            }
            if attempt < playlistVerifyRetryAttempts {
                let delay = playlistVerifyDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        return false
    }

    struct TransitionPlaylistResult {
        let playlistId: Int
        let stepPresetIds: [Int]
    }

    func createTransitionPlaylist(
        device: WLEDDevice,
        from: LEDGradient,
        to: LEDGradient,
        durationSeconds: Double,
        startBrightness: Int,
        endBrightness: Int,
        persist: Bool = false,
        label: String? = nil,
        existingPlaylistId: Int? = nil,
        existingStepPresetIds: [Int]? = nil,
        startTemperature: Double? = nil,
        endTemperature: Double? = nil,
        startWhiteLevel: Double? = nil,
        endWhiteLevel: Double? = nil
    ) async -> TransitionPlaylistResult? {
        let autoStepPrefix = persist ? "Automation Step " : "Auto Step "
        let autoTransitionPrefix = persist ? "Automation Transition " : "Auto Transition "
        var playlistStoreSupported = await apiService.isPlaylistStoreSupported(for: device)
        var existingPlaylists: [WLEDPlaylist] = []
        if playlistStoreSupported {
            do {
                existingPlaylists = try await apiService.fetchPlaylists(for: device)
            } catch {
                if !(await apiService.isPlaylistStoreSupported(for: device)) {
                    playlistStoreSupported = false
                    #if DEBUG
                    print("⚠️ Playlist store unsupported for \(device.name); falling back to psave playlists.")
                    #endif
                } else {
                    #if DEBUG
                    print("⚠️ Playlist creation failed: unable to fetch playlists for \(device.name): \(error.localizedDescription)")
                    #endif
                    playlistUnsupportedDevices.insert(device.id)
                    return nil
                }
            }
        }
        #if DEBUG
        let storageMode = persist ? "persistent" : "temporary"
        let playlistStorage = playlistStoreSupported ? "playlist-store" : "psave"
        print("🔎 Playlist build for \(device.name): mode=2-preset, storage=\(storageMode), playlist=\(playlistStorage), duration=\(String(format: "%.1f", durationSeconds))s")
        #endif

        var existingPresets: [WLEDPreset]
        do {
            existingPresets = try await apiService.fetchPresets(for: device)
        } catch {
            let apiError = error as? WLEDAPIError
            if !persist,
               case .httpError(let statusCode) = apiError,
               statusCode == 501 {
                #if DEBUG
                print("⚠️ Playlist creation warning: preset list unavailable for \(device.name); using empty preset set for auto IDs.")
                #endif
                existingPresets = []
            } else {
                #if DEBUG
                print("⚠️ Playlist creation failed: unable to fetch presets for \(device.name): \(error.localizedDescription)")
                #endif
                return nil
            }
        }
        var usedPresetIds = Set(existingPresets.map { $0.id })
        var reusableStepPresetIds: [Int] = []
        if let existingStepPresetIds, existingStepPresetIds.count == 2 {
            reusableStepPresetIds = existingStepPresetIds
            reusableStepPresetIds.forEach { usedPresetIds.remove($0) }
        }
        var usedPlaylistIds: Set<Int>
        if playlistStoreSupported {
            usedPlaylistIds = Set(existingPlaylists.map { $0.id })
        } else {
            usedPlaylistIds = usedPresetIds
        }
        var resolvedPlaylistId: Int? = nil
        if let existingPlaylistId, usedPlaylistIds.contains(existingPlaylistId) {
            resolvedPlaylistId = existingPlaylistId
            usedPlaylistIds.remove(existingPlaylistId)
        }
        if resolvedPlaylistId == nil {
            var selectedId = availablePlaylistId(excluding: usedPlaylistIds)
            if selectedId == nil && !persist {
                if playlistStoreSupported {
                    let autoPlaylistIds = existingPlaylists
                        .filter { $0.name.hasPrefix(autoTransitionPrefix) }
                        .map { $0.id }
                    if !autoPlaylistIds.isEmpty {
                        #if DEBUG
                        print("🧹 Cleaning \(autoPlaylistIds.count) auto playlists to free slots for \(device.name).")
                        #endif
                        for listId in autoPlaylistIds {
                            _ = try? await apiService.deletePlaylist(id: listId, device: device)
                        }
                        let refreshedPlaylists = (try? await apiService.fetchPlaylists(for: device)) ?? []
                        usedPlaylistIds = Set(refreshedPlaylists.map { $0.id })
                        selectedId = availablePlaylistId(excluding: usedPlaylistIds)
                    }
                } else {
                    let autoTransitionIds = existingPresets
                        .filter { $0.name.hasPrefix(autoTransitionPrefix) }
                        .map { $0.id }
                    if !autoTransitionIds.isEmpty {
                        #if DEBUG
                        print("🧹 Cleaning \(autoTransitionIds.count) auto transition presets to free slots for \(device.name).")
                        #endif
                        for presetId in autoTransitionIds {
                            _ = try? await apiService.deletePreset(id: presetId, device: device)
                        }
                        existingPresets = (try? await apiService.fetchPresets(for: device)) ?? []
                        usedPresetIds = Set(existingPresets.map { $0.id })
                        reusableStepPresetIds.forEach { usedPresetIds.remove($0) }
                        usedPlaylistIds = usedPresetIds
                        selectedId = availablePlaylistId(excluding: usedPlaylistIds)
                    }
                }
            }
            guard let resolvedId = selectedId else {
                #if DEBUG
                print("⚠️ Playlist creation failed: no available playlist IDs for \(device.name).")
                #endif
                return nil
            }
            resolvedPlaylistId = resolvedId
        }
        if let resolvedPlaylistId, !playlistStoreSupported {
            usedPresetIds.insert(resolvedPlaylistId)
        }

        let needsStepIds = reusableStepPresetIds.count != 2
        var allocatedPresetIds: [Int]? = nil
        if needsStepIds {
            allocatedPresetIds = availableIds(from: 250, excluding: usedPresetIds, count: 2)
            if allocatedPresetIds == nil && !persist {
                let autoPresetIds = existingPresets.filter {
                    $0.name.hasPrefix(autoStepPrefix)
                }
                    .map { $0.id }
                if !autoPresetIds.isEmpty {
                    #if DEBUG
                    print("🧹 Cleaning \(autoPresetIds.count) auto presets to free slots for \(device.name).")
                    #endif
                    for presetId in autoPresetIds {
                        _ = try? await apiService.deletePreset(id: presetId, device: device)
                    }
                    let refreshedPresets = (try? await apiService.fetchPresets(for: device)) ?? []
                    usedPresetIds = Set(refreshedPresets.map { $0.id })
                    reusableStepPresetIds.forEach { usedPresetIds.remove($0) }
                    allocatedPresetIds = availableIds(from: 250, excluding: usedPresetIds, count: 2)
                }
            }
        }

        if needsStepIds, allocatedPresetIds == nil {
            #if DEBUG
            print("⚠️ Playlist creation failed: insufficient preset slots (2 needed) for \(device.name).")
            #endif
            return nil
        }

        var stepPresetIds = reusableStepPresetIds
        if needsStepIds, let allocatedPresetIds {
            stepPresetIds = Array(allocatedPresetIds.prefix(2))
        }

        guard let playlistId = resolvedPlaylistId, stepPresetIds.count == 2 else {
            #if DEBUG
            print("⚠️ Playlist creation failed: missing playlist or step presets for \(device.name).")
            #endif
            return nil
        }

        let shouldCleanupStepPresets = needsStepIds
        func cleanupAllocatedStepPresets() async {
            guard shouldCleanupStepPresets, !stepPresetIds.isEmpty else { return }
            await DeviceCleanupManager.shared.requestDelete(type: .preset, device: device, ids: stepPresetIds)
        }

        let stepCount = stepPresetIds.count
        let stepDenom = Double(max(1, stepCount - 1))
        for (idx, presetId) in stepPresetIds.enumerated() {
            let t = Double(idx) / stepDenom
            let stops = interpolateStops(from: from, to: to, t: t)
            let brightness = Int(round(Double(startBrightness) * (1.0 - t) + Double(endBrightness) * t))
            let state = segmentedPresetState(
                device: device,
                gradient: LEDGradient(stops: stops, interpolation: to.interpolation),
                brightness: brightness,
                on: true,
                temperature: idx == 0 ? startTemperature : endTemperature,
                whiteLevel: idx == 0 ? startWhiteLevel : endWhiteLevel
            )
            let request = WLEDPresetSaveRequest(
                id: presetId,
                name: "Auto Step \(presetId)",
                quickLoad: false,
                state: state
            )
            do {
                try await savePresetWithRetry(request, device: device)
            } catch {
                #if DEBUG
                print("⚠️ Playlist creation failed: preset save error for \(device.name): \(error.localizedDescription)")
                #endif
                await cleanupAllocatedStepPresets()
                return nil
            }
        }
        // Verify presets exist before building playlist.
        if !(await verifyPresetIds(stepPresetIds, device: device)) {
            #if DEBUG
            print("⚠️ Playlist creation failed: missing presets after save for \(device.name): \(stepPresetIds)")
            #endif
            await cleanupAllocatedStepPresets()
            return nil
        }

        let transitionDeciseconds = min(maxWLEDTransitionDeciseconds, Int(durationSeconds * 10.0))
        let durations = [1, 0]  // Use a non-zero hold for entry 1 for better device compatibility
        let transitions = [transitionDeciseconds, 0]
        let playlistName = label?.isEmpty == false ? label! : "\(autoTransitionPrefix)\(playlistId)"
        let playlistRequest = WLEDPlaylistSaveRequest(
            id: playlistId,
            name: playlistName,
            ps: stepPresetIds,
            dur: durations,
            transition: transitions,
            repeat: nil
        )

        do {
            try await savePlaylistWithRetry(playlistRequest, device: device)
            #if DEBUG
            if let playlists = try? await apiService.fetchPlaylists(for: device),
               let saved = playlists.first(where: { $0.id == playlistId }) {
                print("🔎 Playlist saved for \(device.name): id=\(saved.id), ps=\(saved.presets.count), dur=\(saved.duration.count), transition=\(saved.transition.count)")
            }
            #endif
            if !(await verifyPlaylistId(playlistId, device: device)) {
                #if DEBUG
                print("⚠️ Playlist still missing after verification for \(device.name).")
                #endif
                playlistUnsupportedDevices.insert(device.id)
                await cleanupAllocatedStepPresets()
                return nil
            }
        } catch {
            #if DEBUG
            print("⚠️ Playlist creation failed: playlist save error for \(device.name): \(error.localizedDescription)")
            #endif
            await cleanupAllocatedStepPresets()
            return nil
        }

        if !persist {
            await MainActor.run {
                temporaryPlaylistIds[device.id] = playlistId
                temporaryPresetIds[device.id] = stepPresetIds
            }
        }
        return TransitionPlaylistResult(playlistId: playlistId, stepPresetIds: stepPresetIds)
    }

    func saveTransitionPresetToDevice(_ preset: TransitionPreset, device: WLEDDevice) async -> TransitionPlaylistResult? {
        let result = await createTransitionPlaylist(
            device: device,
            from: preset.gradientA,
            to: preset.gradientB,
            durationSeconds: preset.durationSec,
            startBrightness: preset.brightnessA,
            endBrightness: preset.brightnessB,
            persist: true,
            label: preset.name,
            existingPlaylistId: preset.wledPlaylistId,
            existingStepPresetIds: preset.wledStepPresetIds,
            startTemperature: preset.temperatureA,
            endTemperature: preset.temperatureB,
            startWhiteLevel: preset.whiteLevelA,
            endWhiteLevel: preset.whiteLevelB
        )

        guard let result else { return nil }

        if let existingPlaylistId = preset.wledPlaylistId, existingPlaylistId != result.playlistId {
            await DeviceCleanupManager.shared.requestDelete(type: .playlist, device: device, ids: [existingPlaylistId])
        }
        if let existingStepPresetIds = preset.wledStepPresetIds,
           Set(existingStepPresetIds) != Set(result.stepPresetIds) {
            await DeviceCleanupManager.shared.requestDelete(type: .preset, device: device, ids: existingStepPresetIds)
        }

        return result
    }

    func startPlaylist(device: WLEDDevice, playlistId: Int) async -> Bool {
        do {
            let state = try await apiService.applyPlaylist(playlistId, to: device, releaseRealtime: true)
            #if DEBUG
            print("✅ Playlist started for \(device.name): playlistId=\(playlistId)")
            print("🔎 Playlist state for \(device.name): pl=\(state.playlistId.map(String.init) ?? "nil"), ps=\(state.presetId.map(String.init) ?? "nil"), tt=\(state.transitionDeciseconds.map(String.init) ?? "nil")")
            #endif
            let immediateMatch = state.playlistId == playlistId || state.presetId == playlistId
            if immediateMatch {
                return true
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            if let fetched = try? await apiService.getState(for: device) {
                let fetchedState = fetched.state
                #if DEBUG
                print("🔎 Playlist fetched state for \(device.name): pl=\(fetchedState.playlistId.map(String.init) ?? "nil"), ps=\(fetchedState.presetId.map(String.init) ?? "nil"), tt=\(fetchedState.transitionDeciseconds.map(String.init) ?? "nil")")
                #endif
                if fetchedState.playlistId == playlistId || fetchedState.presetId == playlistId {
                    return true
                }
            } else {
                #if DEBUG
                print("⚠️ Failed to fetch state after playlist start for \(device.name)")
                #endif
            }

            return false
        } catch {
            #if DEBUG
            print("⚠️ Failed to start playlist \(playlistId) for \(device.name): \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func cleanupTransitionPlaylist(device: WLEDDevice) async {
        let playlistId = temporaryPlaylistIds[device.id]
        let presetIds = temporaryPresetIds[device.id] ?? []
        guard playlistId != nil || !presetIds.isEmpty else { return }

        if let playlistId {
            await DeviceCleanupManager.shared.requestDelete(type: .playlist, device: device, ids: [playlistId])
        }
        if !presetIds.isEmpty {
            await DeviceCleanupManager.shared.requestDelete(type: .preset, device: device, ids: presetIds)
        }
        temporaryPlaylistIds.removeValue(forKey: device.id)
        temporaryPresetIds.removeValue(forKey: device.id)
    }

    private func interpolateStops(from: LEDGradient, to: LEDGradient, t: Double) -> [GradientStop] {
        let a = from.stops.sorted { $0.position < $1.position }
        let b = to.stops.sorted { $0.position < $1.position }
        let count = max(a.count, b.count, 2)
        let denom = Double(max(1, count - 1))
        let positions = (0..<count).map { Double($0) / denom }
        return positions.map { pos in
            let ca = GradientSampler.sampleColor(at: pos, stops: a, interpolation: from.interpolation).toRGBArray()
            let cb = GradientSampler.sampleColor(at: pos, stops: b, interpolation: to.interpolation).toRGBArray()
            let r = Int(round(Double(ca[0]) * (1.0 - t) + Double(cb[0]) * t))
            let g = Int(round(Double(ca[1]) * (1.0 - t) + Double(cb[1]) * t))
            let b = Int(round(Double(ca[2]) * (1.0 - t) + Double(cb[2]) * t))
            let mixed = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
            return GradientStop(position: pos, hexColor: mixed.toHex())
        }
    }

    func startSmoothABStreaming(_ device: WLEDDevice, from: LEDGradient, to: LEDGradient, durationSec: Double, fps: Int = 60, aBrightness: Int? = nil, bBrightness: Int? = nil) async {
        let startBrightness = aBrightness ?? device.brightness
        let endBrightness = bBrightness ?? device.brightness
        await runAutomationTransition(
            for: device,
            startGradient: from,
            startBrightness: startBrightness,
            endGradient: to,
            endBrightness: endBrightness,
            durationSeconds: durationSec,
            segmentId: 0
        )
    }

    func cancelStreaming(for device: WLEDDevice) async {
        await transitionRunner.cancel(deviceId: device.id)
    }

    // MARK: - Helper Functions
    
    private func hexStringToRGB(_ hex: String) -> (Int, Int, Int) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Int((rgb & 0xFF0000) >> 16)
        let g = Int((rgb & 0x00FF00) >> 8)
        let b = Int(rgb & 0x0000FF)
        
        return (r, g, b)
    }
    
    // MARK: - Device Rename
    func renameDevice(_ device: WLEDDevice, to name: String) async {
        do {
            // First, update the WLED device configuration
            _ = try await apiService.updateConfig(for: device, name: name)
            pendingRenames[device.id] = PendingRename(targetName: name, initiatedAt: Date())
            
            // Then update locally
            var updatedDevice = device
            updatedDevice.name = name
            updatedDevice.lastSeen = Date()
            
            // Update local device list
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    self.devices[index].name = name
                    self.devices[index].lastSeen = Date()
                }
            }
            
            // Persist to Core Data
            await coreDataManager.saveDevice(updatedDevice)
            
            clearError()
            
        } catch {
            pendingRenames.removeValue(forKey: device.id)
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
    }
    
    // MARK: - Device Location Update
    func updateDeviceLocation(_ device: WLEDDevice, location: DeviceLocation) async {
        // Update locally (location is stored only in the app, not on WLED device)
        var updatedDevice = device
        updatedDevice.location = location
        updatedDevice.lastSeen = Date()
        
        // Update local device list
        await MainActor.run {
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[index].location = location
                self.devices[index].lastSeen = Date()
            }
        }
        
        // Persist to Core Data
        await coreDataManager.saveDevice(updatedDevice)
    }
    
    // MARK: - Gradient Application with Independent Brightness
    func applyGradientA(_ gradient: LEDGradient, aBrightness: Int?, to device: WLEDDevice) async {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        latestGradientStops[device.id] = sortedStops
        persistLatestGradient(sortedStops, for: device.id)
        // Apply gradient with optional brightness override
        let ledCount = totalLEDCount(for: device)
        await applyGradientStopsAcrossStrip(
            device,
            stops: sortedStops,
            ledCount: ledCount,
            disableActiveEffect: true,
            segmentId: 0,
            interpolation: gradient.interpolation,
            brightness: aBrightness,
            on: true,
            userInitiated: false,
            preferSegmented: true
        )
    }
    
    func applyGradientB(_ gradient: LEDGradient, bBrightness: Int?, to device: WLEDDevice) async {
        // Secondary gradient for transitions - same as A for now
        await applyGradientA(gradient, aBrightness: bBrightness, to: device)
    }
    
    func cancelActiveTransitionIfNeeded(for device: WLEDDevice) async {
        await transitionRunner.cancel(deviceId: device.id)
        await colorPipeline.cancelUploads(for: device.id)
    }
    
    /// Cancel any active run (transition/automation) for a device
    /// This is called automatically on manual user input, or can be called manually via UI
    func cancelActiveRun(for device: WLEDDevice, releaseRealtimeOverride: Bool = true, force: Bool = false) async {
        if !force,
           let lockUntil = transitionCancelLockUntil[device.id],
           Date() < lockUntil,
           let run = activeRunStatus[device.id],
           run.kind == .transition {
            #if DEBUG
            print("⏳ Skipping cancel for \(device.name) (transition lock active)")
            #endif
            return
        }
        let runId = await MainActor.run {
            activeRunStatus[device.id]?.id
        }
        // Check if there's a native WLED transition running that needs to be stopped
        let nativeTransitionInfo = await MainActor.run {
            activeRunStatus[device.id]?.nativeTransition
        }
        
        // If native transition is active, send immediate state update to stop it
        if let nativeInfo = nativeTransitionInfo {
            // Send immediate override with transition: 0 to jump to target state
            let segment = SegmentUpdate(
                id: 0,
                col: [[nativeInfo.targetColorRGB[0], nativeInfo.targetColorRGB[1], nativeInfo.targetColorRGB[2]]]
            )
            let immediateState = WLEDStateUpdate(
                on: true,
                bri: nativeInfo.targetBrightness,
                seg: [segment],
                transition: 0  // No transition - jump immediately to target
            )
            
            do {
                _ = try await apiService.updateState(for: device, state: immediateState)
                #if DEBUG
                print("🛑 Stopped native WLED transition for device \(device.name) by jumping to target state")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ Failed to stop native transition for device \(device.name): \(error.localizedDescription)")
                #endif
            }
        }
        
        // Cancel transition runner and uploads
        await cancelActiveTransitionIfNeeded(for: device)
        
        // Release real-time override if needed
        if releaseRealtimeOverride {
            await apiService.releaseRealtimeOverride(for: device)
        }
        
        // Clear active run status
        await MainActor.run {
            activeRunStatus.removeValue(forKey: device.id)
            // Clear watchdog
            runWatchdogs.removeValue(forKey: device.id)
            transitionCancelLockUntil.removeValue(forKey: device.id)
        }
        await restoreTransitionDefaultIfNeeded(for: device, runId: runId)
        
        #if DEBUG
        print("🛑 Cancelled active run for device \(device.name)")
        #endif
    }
    
    // MARK: - Watchdog Management
    
    /// Start the watchdog task if not already running
    private func startWatchdogTaskIfNeeded() {
        guard watchdogTask == nil || watchdogTask?.isCancelled == true else { return }
        
        watchdogTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.checkForStalledRuns()
                try? await Task.sleep(nanoseconds: UInt64(self.watchdogCheckInterval * 1_000_000_000))
            }
        }
    }
    
    /// Check for stalled runs and auto-cancel them
    private func checkForStalledRuns() async {
        let now = Date()
        let deviceIds = Array(runWatchdogs.keys)
        
        for deviceId in deviceIds {
            guard let watchdog = runWatchdogs[deviceId],
                  let runStatus = activeRunStatus[deviceId] else {
                // Run status cleared but watchdog still exists - clean up
                runWatchdogs.removeValue(forKey: deviceId)
                continue
            }
            
            // Only watchdog runs that should have progress updates
            guard runStatus.kind == .transition || runStatus.kind == .automation else {
                // Skip watchdog for .applying runs (they're short-lived)
                // Skip .effect runs (not currently tracked with progress)
                continue
            }
            
            // State-based progress for native/device-side transitions.
            if let expectedEnd = runStatus.expectedEnd {
                let total = expectedEnd.timeIntervalSince(runStatus.startDate)
                if total > 0 {
                    let elapsed = now.timeIntervalSince(runStatus.startDate)
                    let progress = min(1.0, max(0.0, elapsed / total))
                    if runStatus.progress != progress, runStatus.id == activeRunStatus[deviceId]?.id {
                        activeRunStatus[deviceId]?.progress = progress
                        runWatchdogs[deviceId]?.lastProgressAt = now
                        runWatchdogs[deviceId]?.lastProgressValue = progress
                    }
                }
                if now >= expectedEnd, runStatus.id == activeRunStatus[deviceId]?.id {
                    #if DEBUG
                    if runStatus.nativeTransition != nil {
                        print("✅ Watchdog: Native transition completed for device \(deviceId)")
                    } else {
                        print("✅ Watchdog: Timed transition completed for device \(deviceId)")
                    }
                    #endif
                    activeRunStatus.removeValue(forKey: deviceId)
                    runWatchdogs.removeValue(forKey: deviceId)
                }
                continue
            }
            
            // Check if progress has stalled (only for client-side transitions with progress callbacks)
            let timeSinceLastProgress = now.timeIntervalSince(watchdog.lastProgressAt)
            
            if timeSinceLastProgress > watchdogTimeoutSeconds {
                // Progress has stalled - auto-cancel
                #if DEBUG
                print("⏱️ Watchdog: Auto-cancelling stalled run for device \(deviceId)")
                print("   Run: \(runStatus.title), Last progress: \(Int(watchdog.lastProgressValue * 100))% at \(watchdog.lastProgressAt)")
                print("   Time since last progress: \(String(format: "%.1f", timeSinceLastProgress))s")
                #endif
                
                // Find the device and cancel the run
                if let device = devices.first(where: { $0.id == deviceId }) {
                    await cancelActiveRun(for: device)
                } else {
                    // Device not found - just clean up
                    await MainActor.run {
                        activeRunStatus.removeValue(forKey: deviceId)
                        runWatchdogs.removeValue(forKey: deviceId)
                    }
                }
            }
        }
    }
    
    func gradientStops(for deviceId: String) -> [GradientStop]? {
        if let stops = latestGradientStops[deviceId], !stops.isEmpty {
            return stops
        }
        if let persisted = loadPersistedGradient(for: deviceId), !persisted.isEmpty {
            latestGradientStops[deviceId] = persisted
            return persisted
        }
        return nil
    }
    
    private func persistLatestGradient(_ stops: [GradientStop], for deviceId: String) {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        UserDefaults.standard.set(data, forKey: gradientDefaultsPrefix + deviceId)
    }
    
    private func loadPersistedGradient(for deviceId: String) -> [GradientStop]? {
        guard let data = UserDefaults.standard.data(forKey: gradientDefaultsPrefix + deviceId) else { return nil }
        return try? JSONDecoder().decode([GradientStop].self, from: data)
    }
    
    func transitionDuration(for deviceId: String) -> Double? {
        if let cached = latestTransitionDurations[deviceId] {
            return cached
        }
        if let persisted = loadPersistedTransitionDuration(for: deviceId) {
            latestTransitionDurations[deviceId] = persisted
            return persisted
        }
        return nil
    }
    
    func setTransitionDuration(_ seconds: Double, for deviceId: String) {
        latestTransitionDurations[deviceId] = seconds
        persistTransitionDuration(seconds, for: deviceId)
    }
    
    private func persistTransitionDuration(_ value: Double, for deviceId: String) {
        UserDefaults.standard.set(value, forKey: transitionDurationDefaultsPrefix + deviceId)
    }
    
    private func loadPersistedTransitionDuration(for deviceId: String) -> Double? {
        let key = transitionDurationDefaultsPrefix + deviceId
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }
    
    func applyColorIntent(_ intent: ColorIntent, to device: WLEDDevice) async {
        // Public method to apply color intents via ColorPipeline
        await colorPipeline.apply(intent, to: device)
    }
    
    func startTransition(
        from: LEDGradient,
        aBrightness: Int,
        to: LEDGradient,
        bBrightness: Int,
        durationSec: Double,
        device: WLEDDevice,
        startStopTemperatures: [UUID: Double]? = nil,
        startStopWhiteLevels: [UUID: Double]? = nil,
        endStopTemperatures: [UUID: Double]? = nil,
        endStopWhiteLevels: [UUID: Double]? = nil
    ) async {
        await cancelActiveTransitionIfNeeded(for: device)
        setTransitionDuration(durationSec, for: device.id)
        Task { @MainActor [weak self] in
            await self?.runAutomationTransition(
                for: device,
                startGradient: from,
                startBrightness: aBrightness,
                endGradient: to,
                endBrightness: bBrightness,
                durationSeconds: durationSec,
                startStopTemperatures: startStopTemperatures,
                startStopWhiteLevels: startStopWhiteLevels,
                endStopTemperatures: endStopTemperatures,
                endStopWhiteLevels: endStopWhiteLevels,
                segmentId: 0
            )
        }
    }
    
    func stopTransitionAndRevertToA(device: WLEDDevice) async {
        // Cancel runner, apply gradient A
        await cancelActiveRun(for: device, force: true)
        // Note: caller should apply gradient A after this
    }

    // MARK: - Segments
    func updateSegmentBounds(device: WLEDDevice, segmentId: Int, start: Int, stop: Int) async {
        let seg = SegmentUpdate(id: segmentId, start: start, stop: stop)
        let state = WLEDStateUpdate(seg: [seg])
        _ = try? await apiService.updateState(for: device, state: state)
        // Optimistic update: adjust device.brightness or lastSeen only; avoid mutating nested state structures that may be immutable in models
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx].lastSeen = Date()
            devices[idx].isOnline = true
        }
    }

    // MARK: - Scenes

    func saveCurrentScene(device: WLEDDevice, primaryStops: [GradientStop], transitionEnabled: Bool, secondaryStops: [GradientStop]?, durationSec: Double?, aBrightness: Int?, bBrightness: Int?, effectsEnabled: Bool, effectId: Int?, paletteId: Int?, speed: Int?, intensity: Int?, name: String) {
        let scene = Scene(
            name: name,
            deviceId: device.id,
            brightness: device.brightness,
            primaryStops: primaryStops,
            transitionEnabled: transitionEnabled,
            secondaryStops: secondaryStops,
            durationSec: durationSec,
            aBrightness: aBrightness,
            bBrightness: bBrightness,
            effectsEnabled: effectsEnabled,
            effectId: effectId,
            paletteId: paletteId,
            speed: speed,
            intensity: intensity
        )
        ScenesStore.shared.add(scene)
    }

    func applyScene(_ scene: Scene, to device: WLEDDevice, userInitiated: Bool = true) async {
        // 1) Cancel any running streams
        await cancelStreaming(for: device)

        // 2) Brightness first (bri-only)
        await updateDeviceBrightness(device, brightness: scene.brightness, userInitiated: userInitiated)

        // 3) Effects
        if scene.effectsEnabled {
            // If base colors are available, set them via segment update first
            if let baseA = scene.primaryStops.first?.color.toRGBArray() {
                let seg = SegmentUpdate(id: 0, col: [[baseA[0], baseA[1], baseA[2]]])
                let st = WLEDStateUpdate(seg: [seg])
                _ = try? await apiService.updateState(for: device, state: st)
            }
            _ = try? await apiService.setEffect(
                scene.effectId ?? 0,
                forSegment: 0,
                speed: scene.speed,
                intensity: scene.intensity,
                palette: scene.paletteId,
                device: device,
                turnOn: true,
                releaseRealtime: false  // Scenes don't need realtime release
            )
            return
        }

        // 4) Transition vs static
        if scene.transitionEnabled, let secondary = scene.secondaryStops, let dur = scene.durationSec {
            let gA = LEDGradient(stops: scene.primaryStops, interpolation: .linear)
            let gB = LEDGradient(stops: secondary, interpolation: .linear)
            await startSmoothABStreaming(
                device,
                from: gA,
                to: gB,
                durationSec: dur,
                fps: 60,
                aBrightness: scene.aBrightness,
                bBrightness: scene.bBrightness
            )
        } else {
            let ledCount = totalLEDCount(for: device)
            await applyGradientStopsAcrossStrip(device, stops: scene.primaryStops, ledCount: ledCount, userInitiated: userInitiated, preferSegmented: true)
        }
    }
    
    func presets(for device: WLEDDevice) -> [WLEDPreset] {
        presetsCache[device.id] ?? []
    }
    
    func isLoadingPresets(for device: WLEDDevice) -> Bool {
        presetLoadingStates[device.id] ?? false
    }
    
    func nextPresetId(for device: WLEDDevice) -> Int {
        let existing = Set(presets(for: device).map { $0.id })
        var candidate = 1
        while existing.contains(candidate) {
            candidate += 1
        }
        return candidate
    }
    
    func loadPresets(for device: WLEDDevice, force: Bool = false) async {
        if presetsCache[device.id] != nil && !force { return }
        presetLoadingStates[device.id] = true
        do {
            let presets = try await apiService.fetchPresets(for: device)
            presetsCache[device.id] = presets
            clearError()
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
        presetLoadingStates[device.id] = false
    }
    
    func refreshPresets(for device: WLEDDevice) async {
        await loadPresets(for: device, force: true)
    }
    
    func applyPreset(_ preset: WLEDPreset, to device: WLEDDevice, transition: Int? = nil) async {
        markUserInteraction(device.id)
        do {
            let state = try await apiService.applyPreset(preset.id, to: device, transition: transition)
            updateDevice(device.id, with: state)
            clearError()
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
    }
    
    func savePreset(name: String, quickLoad: Bool, for device: WLEDDevice, presetId: Int? = nil) async {
        markUserInteraction(device.id)
        presetLoadingStates[device.id] = true
        do {
            let response = try await apiService.getState(for: device)
            let stateUpdate = stateUpdate(from: response.state)
            let id = presetId ?? nextPresetId(for: device)
            let request = WLEDPresetSaveRequest(id: id, name: name, quickLoad: quickLoad, state: stateUpdate)
            try await apiService.savePreset(request, to: device)
            presetsCache[device.id] = try await apiService.fetchPresets(for: device)
            clearError()
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
        presetLoadingStates[device.id] = false
    }

    func effectGradientStops(for deviceId: String) -> [GradientStop]? {
        if let stops = latestEffectGradientStops[deviceId], !stops.isEmpty {
            return stops
        }
        if let persisted = loadPersistedEffectGradient(for: deviceId), !persisted.isEmpty {
            latestEffectGradientStops[deviceId] = persisted
            return persisted
        }
        return nil
    }
    
    func updateEffectGradient(_ gradient: LEDGradient, for device: WLEDDevice) {
        let stops = gradient.stops.sorted { $0.position < $1.position }
        latestEffectGradientStops[device.id] = stops
        persistEffectGradient(stops, for: device.id)
    }
    
    private func persistEffectGradient(_ stops: [GradientStop], for deviceId: String) {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        UserDefaults.standard.set(data, forKey: effectGradientDefaultsPrefix + deviceId)
    }
    
    private func loadPersistedEffectGradient(for deviceId: String) -> [GradientStop]? {
        guard let data = UserDefaults.standard.data(forKey: effectGradientDefaultsPrefix + deviceId) else { return nil }
        return try? JSONDecoder().decode([GradientStop].self, from: data)
    }
    
    private func logEffectApplication(effectId: Int, device: WLEDDevice, colors: [[Int]]) {
        #if DEBUG
        if let metadata = colorSafeEffectOptions(for: device).first(where: { $0.id == effectId }) {
            os_log("[Effects] Applied %{public}@ (%d) to %{public}@ with %d colors", metadata.name, effectId, device.name, colors.count)
        } else {
            os_log("[Effects] Applied effect id %d to %{public}@ with %d colors", effectId, device.name, colors.count)
        }
        for (index, rgb) in colors.enumerated() {
            os_log("[Effects]   color[%d] = (%d,%d,%d)", index, rgb[0], rgb[1], rgb[2])
        }
        #endif
    }
    
    // MARK: - Brightness Preservation Helpers
    
    /// Get the preserved brightness for a device (brightness before it was turned off)
    func getPreservedBrightness(for deviceId: String) -> Int? {
        return lastBrightnessBeforeOff[deviceId]
    }
    
    /// Get the effective brightness for a device
    /// Returns preserved brightness if device is off and brightness is 0, otherwise returns current brightness
    /// This ensures UI shows the correct brightness value even when device is turned off
    func getEffectiveBrightness(for device: WLEDDevice) -> Int {
        // If device is off and brightness is 0, return preserved brightness if available
        if !device.isOn && device.brightness == 0 {
            if let preserved = lastBrightnessBeforeOff[device.id], preserved > 0 {
                return preserved
            }
            // Device is off but no preserved brightness - return default
            return 128
        }
        // Device is on - return current brightness (or default if 0)
        return device.brightness > 0 ? device.brightness : 128
    }
    
    // MARK: - Recovery Functions
    
    /// Emergency recovery: Clear all protection windows and release real-time override
    /// Use this when device appears stuck and unresponsive to user input
    func clearProtectionWindows(for device: WLEDDevice) async {
        // Clear user interaction protection
        lastUserInput.removeValue(forKey: device.id)
        
        // Clear gradient application protection
        gradientApplicationTimes.removeValue(forKey: device.id)
        
        // Clear pending toggles
        pendingToggles.removeValue(forKey: device.id)
        toggleTimers[device.id]?.invalidate()
        toggleTimers.removeValue(forKey: device.id)
        
        // Clear UI toggle states
        uiToggleStates.removeValue(forKey: device.id)
        
        // Cancel any active transitions/uploaders
        await cancelActiveTransitionIfNeeded(for: device)
        await colorPipeline.cancelUploads(for: device.id)
        
        // Release real-time override (lor: 0)
        await apiService.releaseRealtimeOverride(for: device)
        
        #if DEBUG
        print("🔄 Cleared all protection windows and released real-time override for device \(device.name)")
        #endif
    }
} 
