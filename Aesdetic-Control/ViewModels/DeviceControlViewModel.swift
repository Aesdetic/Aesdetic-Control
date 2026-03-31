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

struct DiagnosticsEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

private struct PendingPlaylistRename: Codable, Identifiable, Equatable {
    let id: UUID
    let deviceId: String
    let playlistId: Int
    var desiredName: String
    var retries: Int
    var lastAttemptAt: Date?

    init(
        id: UUID = UUID(),
        deviceId: String,
        playlistId: Int,
        desiredName: String,
        retries: Int = 0,
        lastAttemptAt: Date? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.playlistId = playlistId
        self.desiredName = desiredName
        self.retries = retries
        self.lastAttemptAt = lastAttemptAt
    }
}

struct DeviceEffectState {
    var effectId: Int
    var speed: Int
    var intensity: Int
    var paletteId: Int?  // Optional: omit when sending custom colors
    var custom1: Int?
    var custom2: Int?
    var custom3: Int?
    var option1: Bool?
    var option2: Bool?
    var option3: Bool?
    var isEnabled: Bool
    
    static let `default` = DeviceEffectState(effectId: 0, speed: 128, intensity: 128, paletteId: nil, custom1: nil, custom2: nil, custom3: nil, option1: nil, option2: nil, option3: nil, isEnabled: false)
}

enum PalettePreviewEntry: Equatable {
    case color(index: Int, r: Int, g: Int, b: Int)
    case placeholder(String)
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
    let automationId: UUID?
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
        automationId: UUID? = nil,
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
        self.automationId = automationId
        self.title = title
        self.startDate = startDate
        self.progress = progress
        self.isCancellable = isCancellable
        self.expectedEnd = expectedEnd
        self.nativeTransition = nativeTransition
    }
    
    static func == (lhs: ActiveRunStatus, rhs: ActiveRunStatus) -> Bool {
        lhs.id == rhs.id
            && lhs.deviceId == rhs.deviceId
            && lhs.kind == rhs.kind
            && lhs.automationId == rhs.automationId
            && lhs.title == rhs.title
    }
}

struct TransitionDraftSession: Equatable {
    var gradientA: LEDGradient
    var gradientB: LEDGradient
    var stopTemperaturesA: [UUID: Double]
    var stopTemperaturesB: [UUID: Double]
    var stopWhiteLevelsA: [UUID: Double]
    var stopWhiteLevelsB: [UUID: Double]
    var brightnessA: Double
    var brightnessB: Double
    var selectedStartPresetId: UUID?
    var selectedEndPresetId: UUID?
    var transitionOn: Bool
    var isExpanded: Bool
    var isSavingPreset: Bool
    var showSaveSuccess: Bool
    var updatedAt: Date
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

    private static let mainUIEffectExclusionsNormalized: Set<String> = {
        let names: [String] = [
            "blink",
            "auroa",
            "aurora",
            "blink rainbow",
            "chase flash",
            "chase flash rnd",
            "chase rainbow",
            "chase random",
            "chunchun",
            "colorful",
            "colorwaves",
            "dancing shadows",
            "dissolve rnd",
            "fill noise",
            "fire flicker",
            "flow strip",
            "glitter",
            "gradient",
            "haloween eyes",
            "halloween eyes",
            "lighthouse",
            "lightning",
            "loading",
            "meteor",
            "multi comet",
            "noise 1",
            "noise 2",
            "noise 3",
            "noise 4",
            "oscillate",
            "percent",
            "perlin move",
            "phased",
            "phased noise",
            "popcorn",
            "pride 2015",
            "railway",
            "rain",
            "rainbow runner",
            "rsvd",
            "scan",
            "scanner",
            "scanner dual",
            "sinelon",
            "sinelon duel",
            "sinelon dual",
            "sinelon rainbow",
            "solid",
            "solid glitter",
            "solid pattern",
            "solid pattern tri",
            "sparkle",
            "sparkle dark",
            "sparkle+",
            "spots",
            "spots fade",
            "stream 2",
            "strobe",
            "strobe mega",
            "strobe rainbow",
            "tetrix",
            "theater rainbow",
            "traffic light",
            "traffix light",
            "trifade",
            "triwipe",
            "twinkle",
            "twinklecat",
            "twinkle fox",
            "twinkleup",
            "wavesins"
        ]
        return Set(names.map { normalizeEffectName($0) })
    }()
    
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
            let color = GradientSampler.sampleColor(at: 0.5, stops: sortedStops, interpolation: gradient.interpolation)
            let rgb = color.toRGBArray()
            return [[rgb[0], rgb[1], rgb[2]]]
        }

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
                return "deviceOffline-" + (name ?? "unknown")
            case .timeout(let name):
                return "timeout-" + (name ?? "unknown")
            case .invalidResponse:
                return "invalidResponse"
            case .apiError(let message):
                return "apiError-" + message
            }
        }
        
        var message: String {
            switch self {
            case .deviceOffline(let name):
                if let name, !name.isEmpty {
                    return name + " is offline."
                }
                return "The device appears to be offline."
            case .timeout(let name):
                if let name, !name.isEmpty {
                    return name + " is not responding."
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
    @Published private(set) var presetWriteInProgress: Set<String> = []
    @Published private(set) var transitionCleanupInProgress: Set<String> = []
    @Published private(set) var transitionCleanupPendingCountByDeviceId: [String: Int] = [:]
    @Published private(set) var transitionCleanupBacklogCountByDeviceId: [String: Int] = [:]
    @Published private(set) var presetStoreHealthByDeviceId: [String: PresetStoreHealthState] = [:]
    @Published private(set) var lastPresetStoreHealthEventByDeviceId: [String: Date] = [:]
    @Published private(set) var lastPresetStoreHealthMessageByDeviceId: [String: String] = [:]
    @Published private(set) var pendingPresetStoreSyncItemsByDeviceId: [String: [PendingPresetStoreSyncItem]] = [:]
    @Published private(set) var transitionDraftSessionsByDeviceId: [String: TransitionDraftSession] = [:]
    @Published private(set) var queuedTransitionPresetApplyByDeviceId: [String: UUID] = [:]
    @Published private(set) var rebootWaitActiveByDeviceId: Set<String> = []
    @Published private(set) var rebootWaitRemainingSecondsByDeviceId: [String: Int] = [:]
    private var transitionCancelLockUntil: [String: Date] = [:]
    private var savedTransitionDefaults: [String: Int?] = [:]
    private var savedTransitionDefaultRunIds: [String: UUID] = [:]
    private var playlistUnsupportedDevices: Set<String> = []
    private struct TransitionFinalState {
        let runId: UUID
        let gradient: LEDGradient
        let brightness: Int
        let stopTemperatures: [UUID: Double]?
        let stopWhiteLevels: [UUID: Double]?
        let segmentId: Int
        let forceSegmentedOnly: Bool
    }
    private var pendingFinalStates: [String: TransitionFinalState] = [:]
    
    // Watchdog state for monitoring stalled runs
    private struct RunWatchdog {
        var lastProgressAt: Date
        var lastProgressValue: Double
        var runStartAt: Date
    }
    private var runWatchdogs: [String: RunWatchdog] = [:]
    private var watchdogTask: Task<Void, Never>?
    private var presetStoreFailureEventsByDeviceId: [String: [Date]] = [:]
    private var presetStoreWritePauseUntilByDeviceId: [String: Date] = [:]
    private var recentControlWriteSuccessAtByDeviceId: [String: Date] = [:]
    private var queuedTransitionPresetApplyTasksByDeviceId: [String: Task<Void, Never>] = [:]
    private var rebootWaitCountdownTasksByDeviceId: [String: Task<Void, Never>] = [:]
    private var rebootWaitProbeTasksByDeviceId: [String: Task<Void, Never>] = [:]
    private let controlWriteOnlineGraceInterval: TimeInterval = 12.0

    enum TransitionPresetSaveOutcome {
        case saved(TransitionPlaylistResult)
        case deferred(PendingPresetStoreSyncItem)
        case suppressedBusy
    }

    enum TransitionPresetFallbackReason: String {
        case missingWLEDPlaylistId
        case pendingSync
        case playlistStartFailed
        case playlistInvalidOrMissingSteps
        case legacyTempRangeIds
        case busyTimeout
        case shortDurationDirectApply
    }

    enum TransitionPresetApplyOutcome {
        case startedStoredPlaylist(playlistId: Int)
        case rebuiltTransition(reason: TransitionPresetFallbackReason)
        case deferredSyncThenRebuilt
        case suppressedBusy
        case aborted
    }

    enum TransitionPresetSaveAvailability: String {
        case ready
        case blockedLoading
        case blockedCleanupPending
        case blockedCleanupInProgress
        case blockedPresetWriteInProgress
        case blockedPresetStorePaused
    }

    enum HeavyOpQuiescenceResult {
        case ready
        case timedOut(reason: String)
    }

    enum StoredTransitionPlaylistValidation {
        case valid
        case missingPlaylistId
        case missingPlaylistRecord
        case missingStepPresets([Int])
        case legacyTempRangeIds
        case unknownReadFailure
    }
    
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
        let stateUpdate = WLEDStateUpdate(defaultTransitionDeciseconds: max(0, deciseconds))
        _ = try? await apiService.updateState(for: device, state: stateUpdate)
    }

    private func restoreTransitionDefaultIfNeeded(for device: WLEDDevice, runId: UUID?) async {
        if let storedRunId = savedTransitionDefaultRunIds[device.id], let runId, storedRunId != runId {
            return
        }
        guard savedTransitionDefaults.keys.contains(device.id) else { return }
        let restoredDeciseconds = savedTransitionDefaults[device.id] ?? nil
        if let restoredDeciseconds {
            let stateUpdate = WLEDStateUpdate(defaultTransitionDeciseconds: max(0, restoredDeciseconds))
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
                    playlistId: state.playlistId,
                    mainSegment: state.mainSegment
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
    @Published var discoveryErrorMessage: String?
    @Published var isNetworkAvailable: Bool = true
    @Published var diagnosticsLog: [DiagnosticsEntry] = []
    @Published private(set) var presetSlotStatus: [String: PresetSlotAvailability] = [:]
    @Published var currentError: WLEDError?
    @Published var reconnectionStatus: [String: String] = [:]
    @Published private(set) var activeDeviceId: String?
    @Published private(set) var syncProfilesBySource: [String: DeviceSyncProfile] = [:]
    @Published private(set) var syncDispatchSummaryBySource: [String: SyncDispatchSummary] = [:]
    private var allowActiveHealthChecks: Bool = true
    private let diagnosticsLogLimit: Int = 120
    
    // Service dependencies
    private let apiService = WLEDAPIService.shared
    private let colorPipeline = ColorPipeline()
    private lazy var transitionRunner = GradientTransitionRunner(pipeline: colorPipeline)
    let wledService = WLEDDiscoveryService()
    private let coreDataManager = CoreDataManager.shared
    private let webSocketManager = WLEDWebSocketManager.shared
    private let connectionMonitor = WLEDConnectionMonitor.shared
    private let deviceSyncManager = DeviceSyncManager.shared
    
    // Combine cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Capability Detection
    private let capabilityDetector = CapabilityDetector.shared
    
    /// Local cache of device capabilities for synchronous access from MainActor
    private var deviceCapabilities: [String: WLEDCapabilities] = [:]
    private var deviceLedCounts: [String: Int] = [:]
    private var deviceMaxSegmentCounts: [String: Int] = [:]
    
    // Effect metadata caching
    @Published private(set) var rawEffectMetadata: [String: [String]] = [:]
    @Published private(set) var effectMetadataBundles: [String: EffectMetadataBundle] = [:]
    @Published private(set) var effectStates: [String: [Int: DeviceEffectState]] = [:]
    @Published private(set) var audioReactiveEnabledByDevice: [String: Bool] = [:]
    @Published private(set) var segmentCCTFormats: [String: [Int: Bool]] = [:]
    @Published private(set) var presetsCache: [String: [WLEDPreset]] = [:]
    @Published private(set) var presetLoadingStates: [String: Bool] = [:]
    @Published private(set) var playlistsCache: [String: [WLEDPlaylist]] = [:]
    @Published private(set) var playlistLoadingStates: [String: Bool] = [:]
    @Published private(set) var presetNameMapsByDevice: [String: [Int: String]] = [:]
    @Published private(set) var playlistNameMapsByDevice: [String: [Int: String]] = [:]
    @Published private(set) var pendingPlaylistRenameIdsByDevice: [String: Set<Int>] = [:]
    private var presetModificationTimes: [String: Int] = [:]
    @Published private(set) var palettePreviewEntriesByDevice: [String: [Int: [PalettePreviewEntry]]] = [:]
    @Published private(set) var latestGradientStops: [String: [GradientStop]] = [:]
    @Published private(set) var latestEffectGradientStops: [String: [GradientStop]] = [:]
    @Published private(set) var latestMultiStopEffectGradients: [String: [GradientStop]] = [:]
    @Published private(set) var latestTransitionDurations: [String: Double] = [:]
    private var hasLiveGradientHydration: Set<String> = []
    private var lastLiveGradientReconcileAt: [String: Date] = [:]
    private let liveGradientReconcileCooldown: TimeInterval = 45.0
    private let liveGradientReconcileDistanceThreshold: Double = 18.0
    private var effectMetadataLastFetched: [String: Date] = [:]
    private var palettePreviewLastFetched: [String: Date] = [:]
    private var lastGradientBeforeEffect: [String: [GradientStop]] = [:]
    private let effectGradientMultiDefaultsPrefix = "latestEffectGradientStops.multi."
    private let effectMetadataRefreshInterval: TimeInterval = 300 // 5 minute cache
    private let palettePreviewRefreshInterval: TimeInterval = 300
    private var ledPreferencesLastFetched: [String: Date] = [:]
    private let ledPreferencesRefreshInterval: TimeInterval = 300
    private var ledPreferencesFetchInFlight: Set<String> = []
    private var ledStripTypeByDevice: [String: LEDStripType] = [:]
    private var ledColorOrderByDevice: [String: LEDColorOrder] = [:]
    private var deviceIsMatrixById: [String: Bool] = [:]
    private let temperatureStopsCCTKeyPrefix = "temperatureStopsCCTEnabled."
    private let manualSegmentationKeyPrefix = "manualSegmentationEnabled."
    private let activeSegmentCountKeyPrefix = "activeSegmentCount."
    private let defaultCCTKelvinMin: Int = 1900
    private let defaultCCTKelvinMax: Int = 10091
    private var cctKelvinRanges: [String: ClosedRange<Int>] = [:]
    private var didPreloadPersistedDevices: Bool = false
    private var pendingDiscoveryStateRefreshTasks: [String: Task<Void, Never>] = [:]
    private let discoveryStateRefreshDebounceNanos: UInt64 = 450_000_000

    private var appManagedSegmentDevices: Set<String> = []
    private var segmentAutoRestoreInFlight: Set<String> = []
    private var segmentAutoRestoreLastAttemptAt: [String: Date] = [:]
    private let segmentAutoRestoreCooldownSeconds: TimeInterval = 25.0
    private struct SegmentBounds: Equatable {
        let start: Int
        let stop: Int
    }
    private var appManagedSegmentLayouts: [String: [SegmentBounds]] = [:]
    private let defaultSegmentCountFloor: Int = 12
    private let defaultSegmentQualityRatio: Double = 0.75
    private let perLedFallbackLedLimit: Int = 30
    private let maxWLEDTransitionDeciseconds: Int = 65535
    private let segmentedTransitionMaxStepSeconds: Double = 60.0
    private let segmentedTransitionMinStepSeconds: Double = 5.0
    private let segmentedTransitionMaxSteps: Int = 120
    private let segmentedTransitionSleepSliceSeconds: Double = 1.0
    private let playlistLongTransitionThresholdSeconds: Double = 120.0
    // Safety default: avoid writing temp transition steps/playlists to presets.json.
    // Persistent transition saves (+Preset) still use playlist/preset storage.
    private let enableTemporaryPresetStoreBackedTransitions: Bool = false
    private let presetSaveRetryAttempts: Int = 3
    private let presetVerifyRetryAttempts: Int = 4
    private let presetSaveDelayNanos: UInt64 = 500_000_000
    private let presetVerifyDelayNanos: UInt64 = 600_000_000
    private let playlistSaveRetryAttempts: Int = 3
    private let playlistVerifyRetryAttempts: Int = 4
    private let playlistSaveDelayNanos: UInt64 = 600_000_000
    private let playlistVerifyDelayNanos: UInt64 = 700_000_000
    private let playlistStartDelayNanos: UInt64 = 400_000_000
    private let pendingPlaylistRenameQueueKey = "aesdetic_pending_playlist_renames_v1"
    private let pendingPlaylistRenameRetryLimit = 10
    private let firstDiscoveryTimeSyncKeyPrefix = "aesdetic_first_discovery_time_sync_v1."
    private var pendingPlaylistRenames: [PendingPlaylistRename] = []
    private var temporaryPlaylistIds: [String: Int] = [:]
    private var temporaryPresetIds: [String: [Int]] = [:]
    private var playlistRunsByDevice: Set<String> = []
    private var firstDiscoveryTimeSyncAttemptedThisSession: Set<String> = []
    
    private let gradientDefaultsPrefix = "latestGradientStops."
    private let effectGradientDefaultsPrefix = "latestEffectGradientStops."
    private let transitionDurationDefaultsPrefix = "latestTransitionDurations."

    var playlistLongTransitionThreshold: Double {
        playlistLongTransitionThresholdSeconds
    }
    
    // User interaction tracking for optimistic updates
    private var lastUserInput: [String: Date] = [:]
    private let userInputProtectionWindow: TimeInterval = 1.5
    private let rebootWaitMaxSeconds: Int = 10
    private let rebootProbeInitialDelayNanos: UInt64 = 1_000_000_000
    private let rebootProbeIntervalNanos: UInt64 = 500_000_000
    
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

    private func hasKnownActiveRun(for deviceId: String) -> Bool {
        if activeRunStatus[deviceId] != nil { return true }
        if playlistRunsByDevice.contains(deviceId) { return true }
        if temporaryPlaylistIds[deviceId] != nil { return true }
        if let playlistId = devices.first(where: { $0.id == deviceId })?.state?.playlistId, playlistId > 0 {
            return true
        }
        return false
    }

    private func shouldSendPlaylistStopForStateWrite(_ deviceId: String) -> Bool {
        hasKnownActiveRun(for: deviceId)
    }

    private func markPlaylistStoppedLocally(deviceId: String) {
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        guard let currentState = devices[index].state else { return }
        guard currentState.playlistId != nil else { return }
        devices[index].state = WLEDState(
            brightness: currentState.brightness,
            isOn: currentState.isOn,
            segments: currentState.segments,
            transitionDeciseconds: currentState.transitionDeciseconds,
            presetId: currentState.presetId,
            playlistId: nil,
            mainSegment: currentState.mainSegment
        )
    }

    private func manualSegmentationKey(for deviceId: String) -> String {
        manualSegmentationKeyPrefix + deviceId
    }

    private func activeSegmentCountKey(for deviceId: String) -> String {
        activeSegmentCountKeyPrefix + deviceId
    }

    func deviceMaxSegmentCapacity(for device: WLEDDevice) -> Int {
        if let cached = deviceMaxSegmentCounts[device.id], cached > 0 {
            return cached
        }
        if let live = devices.first(where: { $0.id == device.id }),
           let segmentCount = live.state?.segments.count, segmentCount > 0 {
            return segmentCount
        }
        if let segmentCount = device.state?.segments.count, segmentCount > 0 {
            return segmentCount
        }
        return 1
    }

    func maximumUsableSegmentCount(for device: WLEDDevice) -> Int {
        let ledCount = totalLEDCount(for: device)
        let capacity = deviceMaxSegmentCapacity(for: device)
        return max(1, min(ledCount, capacity))
    }

    func recommendedActiveSegmentCount(for device: WLEDDevice) -> Int {
        let maxUsable = maximumUsableSegmentCount(for: device)
        return defaultAutoSegmentCount(maxUsableSegments: maxUsable)
    }

    func preferredActiveSegmentCount(for device: WLEDDevice) -> Int {
        let maxUsable = maximumUsableSegmentCount(for: device)
        let stored = UserDefaults.standard.integer(forKey: activeSegmentCountKey(for: device.id))
        if stored > 0 {
            return min(max(1, stored), maxUsable)
        }
        return recommendedActiveSegmentCount(for: device)
    }

    func setPreferredActiveSegmentCount(_ requestedCount: Int, for device: WLEDDevice) {
        let clamped = min(max(1, requestedCount), maximumUsableSegmentCount(for: device))
        UserDefaults.standard.set(clamped, forKey: activeSegmentCountKey(for: device.id))
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func applyActiveSegmentCount(_ requestedCount: Int, for device: WLEDDevice) async -> Bool {
        let liveDevice = devices.first(where: { $0.id == device.id }) ?? device
        let totalLEDs = totalLEDCount(for: liveDevice)
        guard totalLEDs > 0 else { return false }

        let maxUsable = max(1, min(totalLEDs, deviceMaxSegmentCapacity(for: liveDevice)))
        let count = min(max(1, requestedCount), maxUsable)
        let stops = segmentStops(totalLEDs: totalLEDs, segmentCount: count)
        guard !stops.isEmpty else { return false }

        let existingSegments = liveDevice.state?.segments ?? []
        let existingIds = Set(existingSegments.enumerated().map { index, segment in
            segment.id ?? index
        })

        var updates: [SegmentUpdate] = stops.enumerated().map { idx, bounds in
            SegmentUpdate(
                id: idx,
                start: bounds.start,
                stop: bounds.stop,
                on: true
            )
        }
        // Clear stale higher-index segments so they cannot black out or fragment the strip.
        // In WLED, stop <= start removes the segment definition.
        if !existingIds.isEmpty {
            let staleIds = existingIds.filter { $0 >= count }.sorted()
            if !staleIds.isEmpty {
                updates.append(contentsOf: staleIds.map { id in
                    SegmentUpdate(id: id, start: 0, stop: 0, on: false)
                })
            }
        }

        do {
            #if DEBUG
            let staleCount = updates.count - count
            print("segments.apply.count device=\(liveDevice.id) totalLEDs=\(totalLEDs) requested=\(requestedCount) active=\(count) staleCleared=\(max(0, staleCount))")
            #endif
            _ = try await apiService.updateState(
                for: liveDevice,
                state: WLEDStateUpdate(seg: updates, mainSegment: 0)
            )
            setPreferredActiveSegmentCount(count, for: liveDevice)
            await refreshDeviceState(liveDevice)
            return true
        } catch {
            #if DEBUG
            print("segments.apply.failed device=\(liveDevice.id) error=\(error.localizedDescription)")
            #endif
            return false
        }
    }

    func applySegmentColorOverride(device: WLEDDevice, segmentId: Int, color: Color) async -> Bool {
        let rgb = color.toRGBArray()
        let payloadColor = rgbArrayWithOptionalWhite(rgb, device: device, segmentId: segmentId)
        let update = SegmentUpdate(id: segmentId, on: true, col: [payloadColor], fx: 0, pal: 0)
        do {
            _ = try await apiService.updateState(for: device, state: WLEDStateUpdate(seg: [update]))
            await refreshDeviceState(device)
            return true
        } catch {
            return false
        }
    }

    func isManualSegmentationEnabled(for deviceId: String) -> Bool {
        UserDefaults.standard.bool(forKey: manualSegmentationKey(for: deviceId))
    }

    func setManualSegmentationEnabled(_ enabled: Bool, for deviceId: String) {
        UserDefaults.standard.set(enabled, forKey: manualSegmentationKey(for: deviceId))
        if enabled {
            appManagedSegmentDevices.remove(deviceId)
            appManagedSegmentLayouts[deviceId] = nil
        } else {
            appManagedSegmentDevices.insert(deviceId)
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func resetManualSegmentationForAllDevices() {
        for device in devices {
            setManualSegmentationEnabled(false, for: device.id)
        }
    }

    private func usesManualSegmentation(for deviceId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "advancedUIEnabled")
            && isManualSegmentationEnabled(for: deviceId)
    }

    private func allowsAppManagedSegments(for deviceId: String) -> Bool {
        !UserDefaults.standard.bool(forKey: "advancedUIEnabled")
            || !isManualSegmentationEnabled(for: deviceId)
    }

    private func shouldUseAppManagedSegments(for deviceId: String) -> Bool {
        guard allowsAppManagedSegments(for: deviceId) else { return false }
        return appManagedSegmentDevices.contains(deviceId)
            || appManagedSegmentLayouts[deviceId] != nil
    }

    private func clampedTransitionDeciseconds(for durationSeconds: Double?) -> Int? {
        guard let durationSeconds else { return nil }
        let deciseconds = Int((durationSeconds * 10.0).rounded())
        return min(max(0, deciseconds), maxWLEDTransitionDeciseconds)
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

    private struct PlaylistStepPlan {
        let steps: Int
        let durationDeciseconds: Int
        let transitionDeciseconds: Int
        let durations: [Int]
        let transitions: [Int]
        let effectiveDurationSeconds: Double
        let clampedDurationSeconds: Double
        let generatedTransitionPadDeciseconds: Int
        let timingModeLabel: String
        let totalTransitionSeconds: Double
    }

    private struct TransitionVisualDelta {
        let maxRGBDelta: Int
        let brightnessDelta: Int
    }

    private struct TransitionKeyframe {
        let t: Double
        let stops: [GradientStop]
        let brightness: Int
        let temperature: Double?
        let whiteLevel: Double?
    }

    private func playlistStepPlan(for durationSeconds: Double) -> PlaylistStepPlan {
        playlistStepPlan(
            for: durationSeconds,
            timingUnit: .deciseconds,
            maxStepSeconds: maxWLEDPlaylistTransitionSeconds,
            generatedTimingMode: .fullBlend
        )
    }

    func playlistTransitionDeciseconds(for durationSeconds: Double) -> Int {
        playlistStepPlan(for: durationSeconds, timingUnit: .deciseconds).transitionDeciseconds
    }

    func playlistEffectiveDurationSeconds(for durationSeconds: Double) -> Double {
        playlistStepPlan(for: durationSeconds, timingUnit: .deciseconds).effectiveDurationSeconds
    }

    private enum PlaylistTimingUnit: String {
        case deciseconds
    }

    private func playlistTimingUnit(for device: WLEDDevice) -> PlaylistTimingUnit {
        let key = "playlistTimingUnit.\(device.id)"
        if let stored = UserDefaults.standard.string(forKey: key),
           let unit = PlaylistTimingUnit(rawValue: stored),
           unit == .deciseconds {
            return unit
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return .deciseconds
    }

    private func playlistSteps(for durationSeconds: Double, legSeconds: Double) -> Int {
        let clampedDuration = min(maxWLEDPlaylistDurationSeconds, max(0.0, durationSeconds))
        guard clampedDuration > 0 else { return 1 }
        let safeLeg = min(maxWLEDPlaylistTransitionSeconds, max(1.0, legSeconds))
        return min(maxWLEDPlaylistEntries, Int(ceil(clampedDuration / safeLeg)) + 1)
    }

    private func playlistStepPlan(
        for durationSeconds: Double,
        timingUnit: PlaylistTimingUnit,
        maxStepSeconds: Double = maxWLEDPlaylistTransitionSeconds,
        fixedSteps: Int? = nil,
        generatedTimingMode: GeneratedPlaylistTimingMode = .fullBlend
    ) -> PlaylistStepPlan {
        let clampedDuration = min(maxWLEDPlaylistDurationSeconds, max(0.0, durationSeconds))
        if clampedDuration == 0 {
            return PlaylistStepPlan(
                steps: 1,
                durationDeciseconds: 0,
                transitionDeciseconds: 0,
                durations: [0],
                transitions: [0],
                effectiveDurationSeconds: 0,
                clampedDurationSeconds: 0,
                generatedTransitionPadDeciseconds: 0,
                timingModeLabel: generatedTimingMode.label,
                totalTransitionSeconds: 0
            )
        }

        let unitScale: Double
        switch timingUnit {
        case .deciseconds:
            unitScale = 10.0
        }

        let requestedUnits = max(1, Int(round(clampedDuration * unitScale)))
        let stepTarget = fixedSteps ?? playlistSteps(
            for: clampedDuration,
            legSeconds: min(maxWLEDPlaylistTransitionSeconds, max(1.0, maxStepSeconds))
        )
        let minimumStepsForTransitionLimit = max(
            1,
            Int(ceil(Double(requestedUnits) / Double(maxWLEDPlaylistTransitionDeciseconds)))
        )
        var steps = max(stepTarget, minimumStepsForTransitionLimit)
        steps = min(maxWLEDPlaylistEntries, steps)
        steps = min(steps, requestedUnits)
        steps = max(1, steps)

        let baseDurationUnits = max(1, requestedUnits / steps)
        let durationRemainder = max(0, requestedUnits % steps)
        var durations = Array(repeating: baseDurationUnits, count: steps)
        if durationRemainder > 0 {
            for idx in 0..<durationRemainder {
                durations[idx] += 1
            }
        }

        let transitions = durations.map { durationUnits in
            switch generatedTimingMode {
            case .fullBlend:
                return durationUnits > 0 ? min(durationUnits, maxWLEDPlaylistTransitionDeciseconds) : 0
            case .boundaryCompensated(let padDeciseconds):
                guard durationUnits > 0 else { return 0 }
                let clampedDuration = min(durationUnits, maxWLEDPlaylistTransitionDeciseconds)
                return max(1, min(clampedDuration, clampedDuration - max(0, padDeciseconds)))
            }
        }
        let totalDurationUnits = durations.reduce(0, +)
        let totalDuration = Double(totalDurationUnits) / unitScale
        let totalTransitionSeconds = Double(transitions.reduce(0, +)) / unitScale
        let padDeciseconds = generatedTimingMode.padDeciseconds
        return PlaylistStepPlan(
            steps: steps,
            durationDeciseconds: durations.first ?? 0,
            transitionDeciseconds: transitions.first ?? 0,
            durations: durations,
            transitions: transitions,
            effectiveDurationSeconds: totalDuration,
            clampedDurationSeconds: clampedDuration,
            generatedTransitionPadDeciseconds: padDeciseconds,
            timingModeLabel: generatedTimingMode.label,
            totalTransitionSeconds: totalTransitionSeconds
        )
    }

    private func usedPresetCount(for device: WLEDDevice) -> Int {
        presetSlotStatus[device.id]?.used ?? presetsCache[device.id]?.count ?? 0
    }

    private func sampledTransitionDelta(
        startGradient: LEDGradient,
        endGradient: LEDGradient,
        startBrightness: Int,
        endBrightness: Int,
        samples: Int = 12
    ) -> TransitionVisualDelta {
        let sampleCount = max(2, samples)
        let denom = Double(max(1, sampleCount - 1))
        var maxChannelDelta = 0
        for index in 0..<sampleCount {
            let t = Double(index) / denom
            let a = GradientSampler.sampleColor(at: t, stops: startGradient.stops, interpolation: startGradient.interpolation).toRGBArray()
            let b = GradientSampler.sampleColor(at: t, stops: endGradient.stops, interpolation: endGradient.interpolation).toRGBArray()
            let channelDelta = max(abs(a[0] - b[0]), max(abs(a[1] - b[1]), abs(a[2] - b[2])))
            maxChannelDelta = max(maxChannelDelta, channelDelta)
        }
        let brightnessDelta = abs(startBrightness - endBrightness)
        return TransitionVisualDelta(maxRGBDelta: maxChannelDelta, brightnessDelta: brightnessDelta)
    }

    private func baseLegSeconds(for delta: TransitionVisualDelta, context: TransitionGenerationContext) -> Double {
        let highDelta = delta.maxRGBDelta >= 96 || delta.brightnessDelta >= 80
        let mediumDelta = delta.maxRGBDelta >= 42 || delta.brightnessDelta >= 35
        switch context {
        case .temporaryLive:
            if highDelta { return 20 }
            if mediumDelta { return 24 }
            return 30
        case .persistentAutomation:
            if highDelta { return 30 }
            if mediumDelta { return 45 }
            return 60
        }
    }

    private func qualityLabel(for legSeconds: Double, context: TransitionGenerationContext) -> TransitionStepQualityLabel {
        switch context {
        case .temporaryLive:
            if legSeconds <= 22 { return .high }
            if legSeconds <= 30 { return .balanced }
            return .conservative
        case .persistentAutomation:
            if legSeconds <= 30 { return .high }
            if legSeconds <= 45 { return .balanced }
            return .conservative
        }
    }

    private func candidateLegSeconds(baseLegSeconds: Double, context: TransitionGenerationContext) -> [Double] {
        switch context {
        case .temporaryLive:
            return [baseLegSeconds]
        case .persistentAutomation:
            let all = [30.0, 45.0, 60.0, 65.0]
            return all.filter { $0 >= baseLegSeconds - 0.001 }
        }
    }

    private func maxDurationSeconds(forSlots slots: Int, legSeconds: Double) -> Double {
        // slotsRequired = steps + 1, steps = ceil(duration/leg) + 1
        // => ceil(duration/leg) <= slots - 3
        let maxLegs = max(0, slots - 3)
        return min(maxWLEDPlaylistDurationSeconds, Double(maxLegs) * legSeconds)
    }

    func planTransitionPlaylist(
        durationSec: Double,
        startGradient: LEDGradient,
        endGradient: LEDGradient,
        startBrightness: Int,
        endBrightness: Int,
        context: TransitionGenerationContext,
        device: WLEDDevice,
        automationGuaranteeCount: Int = 5
    ) -> TransitionStepProfile {
        plannedTransitionProfile(
            durationSec: durationSec,
            startGradient: startGradient,
            endGradient: endGradient,
            startBrightness: startBrightness,
            endBrightness: endBrightness,
            context: context,
            usedPresetCountOverride: nil,
            device: device,
            automationGuaranteeCount: automationGuaranteeCount
        )
    }

    private func plannedTransitionProfile(
        durationSec: Double,
        startGradient: LEDGradient,
        endGradient: LEDGradient,
        startBrightness: Int,
        endBrightness: Int,
        context: TransitionGenerationContext,
        usedPresetCountOverride: Int?,
        device: WLEDDevice,
        automationGuaranteeCount: Int
    ) -> TransitionStepProfile {
        let clampedDuration = min(maxWLEDPlaylistDurationSeconds, max(0.0, durationSec))
        let delta = sampledTransitionDelta(
            startGradient: startGradient,
            endGradient: endGradient,
            startBrightness: startBrightness,
            endBrightness: endBrightness
        )
        let baseLeg = baseLegSeconds(for: delta, context: context)
        let used = max(0, usedPresetCountOverride ?? usedPresetCount(for: device))
        let available = max(0, maxWLEDPresetSlots - used - presetSlotReserve)
        let safeGuaranteeCount = max(1, automationGuaranteeCount)
        let perAutomationBudget = context == .persistentAutomation ? available / safeGuaranteeCount : nil

        let candidates = candidateLegSeconds(baseLegSeconds: baseLeg, context: context)
        var chosenLeg = candidates.first ?? baseLeg
        var chosenSteps = playlistSteps(for: clampedDuration, legSeconds: chosenLeg)
        var chosenSlots = chosenSteps + 1
        var fitsBudget = true

        if let budget = perAutomationBudget {
            fitsBudget = chosenSlots <= budget
            if !fitsBudget {
                for candidate in candidates.dropFirst() {
                    let steps = playlistSteps(for: clampedDuration, legSeconds: candidate)
                    let slots = steps + 1
                    chosenLeg = candidate
                    chosenSteps = steps
                    chosenSlots = slots
                    fitsBudget = slots <= budget
                    if fitsBudget {
                        break
                    }
                }
            }
        }

        return TransitionStepProfile(
            context: context,
            baseLegSeconds: baseLeg,
            legSeconds: chosenLeg,
            qualityLabel: qualityLabel(for: chosenLeg, context: context),
            steps: chosenSteps,
            slotsRequired: chosenSlots,
            fitsBudget: fitsBudget,
            wasCoarsened: chosenLeg > baseLeg + 0.001,
            availableSlots: context == .persistentAutomation ? available : nil,
            perAutomationBudget: perAutomationBudget,
            reserve: context == .persistentAutomation ? presetSlotReserve : nil,
            maxDurationSecondsAtCurrentQuality: perAutomationBudget.map { maxDurationSeconds(forSlots: $0, legSeconds: chosenLeg) }
        )
    }

    private func transitionKeyframeTs(stepCount: Int, context: TransitionGenerationContext) -> [Double] {
        let count = max(1, stepCount)
        switch context {
        case .temporaryLive:
            return (0..<count).map { Double($0 + 1) / Double(count) }
        case .persistentAutomation:
            if count == 1 { return [1.0] }
            let denom = Double(max(1, count - 1))
            return (0..<count).map { Double($0) / denom }
        }
    }

    private func maxRGBDeltaBetweenStops(_ a: [GradientStop], _ b: [GradientStop], samples: Int = 12) -> Int {
        let sampleCount = max(2, samples)
        let denom = Double(max(1, sampleCount - 1))
        var maxDelta = 0
        for index in 0..<sampleCount {
            let t = Double(index) / denom
            let ca = GradientSampler.sampleColor(at: t, stops: a, interpolation: .linear).toRGBArray()
            let cb = GradientSampler.sampleColor(at: t, stops: b, interpolation: .linear).toRGBArray()
            let delta = max(abs(ca[0] - cb[0]), max(abs(ca[1] - cb[1]), abs(ca[2] - cb[2])))
            maxDelta = max(maxDelta, delta)
        }
        return maxDelta
    }

    private func cullNearDuplicateKeyframes(
        _ keyframes: [TransitionKeyframe],
        minimumCount: Int
    ) -> [TransitionKeyframe] {
        guard keyframes.count > 1 else { return keyframes }
        let floorCount = max(1, min(minimumCount, keyframes.count))
        var filtered: [TransitionKeyframe] = []
        filtered.reserveCapacity(keyframes.count)

        for (index, keyframe) in keyframes.enumerated() {
            guard let previous = filtered.last else {
                filtered.append(keyframe)
                continue
            }

            let remainingIncludingCurrent = keyframes.count - index
            let minimumStillNeeded = max(0, floorCount - filtered.count)
            if minimumStillNeeded >= remainingIncludingCurrent {
                filtered.append(keyframe)
                continue
            }

            let colorDelta = maxRGBDeltaBetweenStops(previous.stops, keyframe.stops)
            let brightnessDelta = abs(previous.brightness - keyframe.brightness)
            if colorDelta < 2 && brightnessDelta < 1 {
                continue
            }
            filtered.append(keyframe)
        }

        if let final = keyframes.last, filtered.last?.t != final.t {
            filtered.append(final)
        }
        if filtered.count < floorCount {
            return Array(keyframes.prefix(floorCount))
        }
        return filtered
    }

    #if DEBUG
    private func debugGradientSummary(_ gradient: LEDGradient) -> String {
        let stops = gradient.stops.sorted { $0.position < $1.position }
        let first = stops.first?.hexColor ?? "none"
        let last = stops.last?.hexColor ?? first
        return "stops=\(stops.count) first=\(first) last=\(last) interp=\(gradient.interpolation.rawValue)"
    }

    private func debugArraySummary(_ values: [Int]) -> String {
        guard !values.isEmpty else { return "[]" }
        if values.count <= 6 {
            return "[\(values.map(String.init).joined(separator: ", "))]"
        }
        let head = values.prefix(3).map(String.init).joined(separator: ", ")
        let tail = values.suffix(3).map(String.init).joined(separator: ", ")
        return "[\(head), ..., \(tail)] (count=\(values.count))"
    }

    private func debugOperationId(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8))"
    }

    private func debugOperationContext(_ operationId: String?) -> String {
        guard let operationId else { return "" }
        return " op=\(operationId)"
    }

    func debugPlaylistStepPlanForTests(
        durationSeconds: Double,
        generatedTimingMode: GeneratedPlaylistTimingMode = .fullBlend
    ) -> (
        steps: Int,
        durations: [Int],
        transitions: [Int],
        effectiveDurationSeconds: Double,
        padDeciseconds: Int,
        timingModeLabel: String
    ) {
        let plan = playlistStepPlan(
            for: durationSeconds,
            timingUnit: .deciseconds,
            generatedTimingMode: generatedTimingMode
        )
        return (
            plan.steps,
            plan.durations,
            plan.transitions,
            plan.effectiveDurationSeconds,
            plan.generatedTransitionPadDeciseconds,
            plan.timingModeLabel
        )
    }

    func debugTransitionPlanForTests(
        durationSeconds: Double,
        startGradient: LEDGradient,
        endGradient: LEDGradient,
        startBrightness: Int,
        endBrightness: Int,
        context: TransitionGenerationContext,
        usedPresetCount: Int,
        automationGuaranteeCount: Int = 5,
        device: WLEDDevice
    ) -> TransitionStepProfile {
        plannedTransitionProfile(
            durationSec: durationSeconds,
            startGradient: startGradient,
            endGradient: endGradient,
            startBrightness: startBrightness,
            endBrightness: endBrightness,
            context: context,
            usedPresetCountOverride: usedPresetCount,
            device: device,
            automationGuaranteeCount: automationGuaranteeCount
        )
    }

    func debugTransitionKeyframeTsForTests(stepCount: Int, context: TransitionGenerationContext) -> [Double] {
        transitionKeyframeTs(stepCount: stepCount, context: context)
    }

    func debugCulledKeyframeCountForTests(
        stepCount: Int,
        context: TransitionGenerationContext,
        minimumCount: Int,
        from: LEDGradient,
        to: LEDGradient,
        startBrightness: Int,
        endBrightness: Int
    ) -> (before: Int, after: Int) {
        let keyframes = transitionKeyframeTs(stepCount: stepCount, context: context).map { t in
            TransitionKeyframe(
                t: t,
                stops: interpolateStops(from: from, to: to, t: t),
                brightness: Int(round(Double(startBrightness) * (1.0 - t) + Double(endBrightness) * t)),
                temperature: nil,
                whiteLevel: nil
            )
        }
        let culled = cullNearDuplicateKeyframes(keyframes, minimumCount: minimumCount)
        return (keyframes.count, culled.count)
    }

    func debugPersistentTransitionIdAllocationForTests(
        usedIds: Set<Int>,
        stepCount: Int
    ) -> (playlistId: Int?, stepPresetIds: [Int]?) {
        let persistentAllowedUpper = max(1, temporaryTransitionReservedPresetLower - 1)
        let persistentAllowedRange = 1...persistentAllowedUpper
        let playlistId = availableFrontmostPlaylistId(excluding: usedIds, range: persistentAllowedRange)
        var exclusion = usedIds
        if let playlistId {
            exclusion.insert(playlistId)
        }
        let stepIds = availableContiguousIds(
            range: persistentAllowedRange,
            excluding: exclusion,
            count: stepCount
        )
        return (playlistId, stepIds)
    }
    #endif

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

    private func defaultTransitionDeciseconds(for device: WLEDDevice) -> Int? {
        if savedTransitionDefaults.keys.contains(device.id) {
            guard let deciseconds = savedTransitionDefaults[device.id] ?? nil else { return nil }
            return min(deciseconds, maxWLEDTransitionDeciseconds)
        }
        guard let deciseconds = device.state?.transitionDeciseconds else { return nil }
        return min(deciseconds, maxWLEDTransitionDeciseconds)
    }

    private func resolvedTransitionDeciseconds(for device: WLEDDevice, fallbackSeconds: Double?) -> Int? {
        if let deciseconds = defaultTransitionDeciseconds(for: device) {
            return deciseconds
        }
        guard let fallbackSeconds else { return nil }
        return max(0, Int((fallbackSeconds * 10.0).rounded()))
    }

    private func allowPerLedFallback(for device: WLEDDevice) -> Bool {
        let advancedEnabled = UserDefaults.standard.bool(forKey: "advancedUIEnabled")
        let perLedEnabled = UserDefaults.standard.bool(forKey: "perLedTransitionsEnabled")
        let ledCount = totalLEDCount(for: device)
        return perLedEnabled && advancedEnabled && ledCount <= perLedFallbackLedLimit
    }

    func preparePlaylistStart(
        device: WLEDDevice,
        startGradient: LEDGradient,
        startBrightness: Int,
        startStopTemperatures: [UUID: Double]?,
        startStopWhiteLevels: [UUID: Double]?,
        segmentId: Int
    ) async {
        await applyGradientStopsAcrossStrip(
            device,
            stops: startGradient.stops,
            ledCount: totalLEDCount(for: device),
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
        try? await Task.sleep(nanoseconds: playlistStartDelayNanos)
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
        automationName: String? = nil,
        forceSegmentedOnly: Bool = false
    ) async {
        await cancelActiveTransitionIfNeeded(for: device)
        await transitionRunner.cancel(deviceId: device.id)
        
        let requestedDuration = max(0, durationSeconds)
        var durationSeconds = requestedDuration
        let roundedDuration = (requestedDuration * 10.0).rounded() / 10.0
        let ledCount = totalLEDCount(for: device)
        // Use native transition up to the app policy cap (WLED supports up to maxWLEDTransitionSeconds).
        let maxNativeSeconds = maxWLEDNativeTransitionSeconds
        #if DEBUG
        let startStopsCount = startGradient.stops.count
        let endStopsCount = endGradient.stops.count
        print("🔎 Transition start for \(device.name): duration=\(durationSeconds)s, maxNative=\(maxNativeSeconds)s, startStops=\(startStopsCount), endStops=\(endStopsCount)")
        #endif

        let startIsSolid = isSolidGradient(startGradient)
        let endIsSolid = isSolidGradient(endGradient)
        let startUniformTemp = uniformNormalizedTemperatureIfAvailable(
            stops: startGradient.stops,
            stopTemperatures: startStopTemperatures
        )
        let endUniformTemp = uniformNormalizedTemperatureIfAvailable(
            stops: endGradient.stops,
            stopTemperatures: endStopTemperatures
        )
        let startUniformWhite = uniformWhiteLevelIfAvailable(
            stops: startGradient.stops,
            stopWhiteLevels: startStopWhiteLevels
        ).map { Double($0) / 255.0 }
        let endUniformWhite = uniformWhiteLevelIfAvailable(
            stops: endGradient.stops,
            stopWhiteLevels: endStopWhiteLevels
        ).map { Double($0) / 255.0 }
        let startPlaylistTemp = startUniformTemp ?? (startIsSolid ? startStopTemperatures?.values.first : nil)
        let endPlaylistTemp = endUniformTemp ?? (endIsSolid ? endStopTemperatures?.values.first : nil)
        let startPlaylistWhite = startUniformWhite ?? (startIsSolid ? startStopWhiteLevels?.values.first : nil)
        let endPlaylistWhite = endUniformWhite ?? (endIsSolid ? endStopWhiteLevels?.values.first : nil)
        let requiresSegmentedStepper = !(startIsSolid && endIsSolid)
        let exceedsNativeCap = durationSeconds > maxNativeSeconds
        let shouldPersistPlaylist = automationName != nil
        let allowPlaylistPathForThisRun = shouldPersistPlaylist || enableTemporaryPresetStoreBackedTransitions
        let usePlaylistForLongTransition = allowPlaylistPathForThisRun
            && (roundedDuration >= playlistLongTransitionThresholdSeconds)
        let useSegmentedStepper = forceSegmentedOnly
            ? true
            : ((requiresSegmentedStepper || exceedsNativeCap) && !usePlaylistForLongTransition)

        if !useSegmentedStepper, durationSeconds > maxNativeSeconds {
            #if DEBUG
            print("⚠️ Transition duration exceeds native cap for \(device.name). Capping to \(maxNativeSeconds)s (requested \(durationSeconds)s).")
            #endif
            durationSeconds = maxNativeSeconds
        }

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
            preferSegmented: true,
            forceSegmentedOnly: forceSegmentedOnly
        )
        
        // Set active run status
        let startDate = Date()
        let isLongPlaylist = usePlaylistForLongTransition
        let runTitle = isLongPlaylist ? "Loading..." : (automationName ?? "Transition")
        let runKind: ActiveRunStatus.RunKind = automationName != nil ? .automation : .transition
        let effectiveDuration = useSegmentedStepper ? requestedDuration : durationSeconds
        let expectedEnd = (isLongPlaylist && automationName == nil) ? nil : (effectiveDuration > 0 ? startDate.addingTimeInterval(effectiveDuration) : nil)
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
                persist: shouldPersistPlaylist,
                label: shouldPersistPlaylist ? automationName : nil,
                runId: runId,
                startTemperature: startPlaylistTemp,
                endTemperature: endPlaylistTemp,
                startWhiteLevel: startPlaylistWhite,
                endWhiteLevel: endPlaylistWhite
            ) {
                await preparePlaylistStart(
                    device: device,
                    startGradient: startGradient,
                    startBrightness: startBrightness,
                    startStopTemperatures: startStopTemperatures,
                    startStopWhiteLevels: startStopWhiteLevels,
                    segmentId: segmentId
                )
                if await startPlaylist(
                    device: device,
                    playlistId: playlist.playlistId,
                    assumeStarted: !shouldPersistPlaylist,
                    strictValidation: shouldPersistPlaylist,
                    debugExpectedStepPresetIds: playlist.stepPresetIds,
                    debugExpectedBoundarySeconds: cumulativePlaylistBoundarySeconds(durations: playlist.playlistDurations)
                ) {
                #if DEBUG
                print("✅ Transition playlist started for \(device.name): playlistId=\(playlist.playlistId)")
                #endif
                let playbackStart = Date()
                let effectiveDurationSeconds = playlist.effectiveDurationSeconds
                if let leaseId = playlist.temporaryLeaseId {
                    _ = await TemporaryTransitionCleanupService.shared.markRunning(
                        leaseId: leaseId,
                        runId: runId,
                        expectedEndAt: playbackStart.addingTimeInterval(effectiveDurationSeconds)
                    )
                }
                await MainActor.run {
                    latestGradientStops[device.id] = endGradient.stops
                    if let current = activeRunStatus[device.id], current.id == runId {
                        activeRunStatus[device.id] = ActiveRunStatus(
                            id: runId,
                            deviceId: device.id,
                            kind: runKind,
                            title: automationName ?? "Transition",
                            startDate: playbackStart,
                            progress: 0.0,
                            isCancellable: true,
                            expectedEnd: playbackStart.addingTimeInterval(effectiveDurationSeconds)
                        )
                    }
                    pendingFinalStates[device.id] = TransitionFinalState(
                        runId: runId,
                        gradient: endGradient,
                        brightness: endBrightness,
                        stopTemperatures: endStopTemperatures,
                        stopWhiteLevels: endStopWhiteLevels,
                        segmentId: segmentId,
                        forceSegmentedOnly: forceSegmentedOnly
                    )
                }
                if !shouldPersistPlaylist, enableTemporaryPresetStoreBackedTransitions {
                    await TemporaryTransitionCleanupService.shared.requestCleanup(
                        device: device,
                        endReason: .completed,
                        runId: runId,
                        playlistIdHint: playlist.playlistId,
                        stepPresetIdsHint: playlist.stepPresetIds
                    )
                    await refreshTransitionCleanupPendingCount(for: device.id)
                }
                return
                }
                if !shouldPersistPlaylist, enableTemporaryPresetStoreBackedTransitions {
                    if let leaseId = playlist.temporaryLeaseId {
                        await TemporaryTransitionCleanupService.shared.markCreationFailed(leaseId: leaseId, device: device)
                    } else {
                        await cleanupTransitionPlaylist(device: device, endReason: .creationFailed)
                    }
                }
            } else {
                #if DEBUG
                print("⚠️ Transition playlist failed for \(device.name). Falling back to stepper/native.")
                #endif
            }
        }

        if usePlaylistForLongTransition {
            let fallbackStart = Date()
            let fallbackTitle = automationName ?? "Transition"
            let fallbackExpectedEnd = effectiveDuration > 0 ? fallbackStart.addingTimeInterval(effectiveDuration) : nil
            let fallbackNative: NativeTransitionInfo? = (!useSegmentedStepper && endIsSolid && startIsSolid)
                ? NativeTransitionInfo(
                    targetColorRGB: Color(hex: endGradient.stops.first?.hexColor ?? "#000000").toRGBArray(),
                    targetBrightness: endBrightness,
                    durationSeconds: durationSeconds
                )
                : nil
            await MainActor.run {
                if let current = activeRunStatus[device.id], current.id == runId, current.expectedEnd == nil {
                    activeRunStatus[device.id] = ActiveRunStatus(
                        id: runId,
                        deviceId: device.id,
                        kind: runKind,
                        title: fallbackTitle,
                        startDate: fallbackStart,
                        progress: 0.0,
                        isCancellable: true,
                        expectedEnd: fallbackExpectedEnd,
                        nativeTransition: fallbackNative
                    )
                    runWatchdogs[device.id] = RunWatchdog(
                        lastProgressAt: fallbackStart,
                        lastProgressValue: 0.0,
                        runStartAt: fallbackStart
                    )
                }
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
                let stepTemperatures = interpolatedStopScalarMap(
                    stepStops: stepStops,
                    startStops: startGradient.stops,
                    startValuesById: startStopTemperatures,
                    startInterpolation: startGradient.interpolation,
                    endStops: endGradient.stops,
                    endValuesById: endStopTemperatures,
                    endInterpolation: endGradient.interpolation,
                    t: t
                )
                let stepWhiteLevels = interpolatedStopScalarMap(
                    stepStops: stepStops,
                    startStops: startGradient.stops,
                    startValuesById: startStopWhiteLevels,
                    startInterpolation: startGradient.interpolation,
                    endStops: endGradient.stops,
                    endValuesById: endStopWhiteLevels,
                    endInterpolation: endGradient.interpolation,
                    t: t
                )
                let interpBrightness = Int(round(Double(startBrightness) * (1.0 - t) + Double(endBrightness) * t))
                let stepGradient = LEDGradient(stops: stepStops, interpolation: endGradient.interpolation)
                await applySegmentedGradient(
                    device,
                    gradient: stepGradient,
                    stopTemperatures: stepTemperatures,
                    stopWhiteLevels: stepWhiteLevels,
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
                preferSegmented: true,
                forceSegmentedOnly: forceSegmentedOnly
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
    @Published var isRealTimeEnabled: Bool = true {
        didSet {
            refreshRealTimeConnections()
        }
    }
    private let offlineGracePeriod: TimeInterval = 60.0
    private let onlineStatusRefreshInterval: TimeInterval = 10.0
    private var onlineStatusTimer: Timer?
    private let lastSeenPersistInterval: TimeInterval = 60.0
    private var lastSeenPersistedAt: [String: Date] = [:]
    private var hasHandledForegroundActive: Bool = false
    private var lastImmediateHealthCheckAt: Date?
    private let immediateHealthCheckMinInterval: TimeInterval = 8.0

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
        guard !hasHandledForegroundActive else { return }
        hasHandledForegroundActive = true
        if isRealTimeEnabled {
            refreshRealTimeConnections()
        }
        guard allowActiveHealthChecks else {
            #if DEBUG
            print("Skipping device status check (active checks disabled)")
            #endif
            return
        }
        #if DEBUG
        print("🔄 App became active - checking device status immediately")
        #endif
        
        let persistedDevices = await coreDataManager.fetchDevices()
        let targets = persistedDevices.filter { !webSocketManager.isDeviceConnected($0.id) }
        if !targets.isEmpty {
            await performImmediateHealthChecksIfNeeded()
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
        #if DEBUG
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
            print("Memory usage (resident): \(String(format: "%.2f", memoryUsageMB)) MB")
            printMemoryFootprint()
        }
        #endif
    }

    @MainActor
    private func printMemoryFootprint() {
        #if DEBUG
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let physFootprintMB = Double(info.phys_footprint) / 1024.0 / 1024.0
        let residentMB = Double(info.resident_size) / 1024.0 / 1024.0
        let internalMB = Double(info.internal) / 1024.0 / 1024.0
        let compressedMB = Double(info.compressed) / 1024.0 / 1024.0
        print("🧠 Footprint - phys=\(String(format: "%.2f", physFootprintMB))MB resident=\(String(format: "%.2f", residentMB))MB internal=\(String(format: "%.2f", internalMB))MB compressed=\(String(format: "%.2f", compressedMB))MB")
        if physFootprintMB > 150 {
            print("⚠️ High memory footprint detected: \(String(format: "%.2f", physFootprintMB)) MB")
            print("🧠 Cache snapshot - devices=\(devices.count), effects=\(effectMetadataBundles.count), presets=\(presetsCache.count), gradients=\(latestGradientStops.count), effectGradients=\(latestEffectGradientStops.count), capabilities=\(deviceCapabilities.count), stateCache=\(deviceStateCache.count)")
        }
        #endif
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

    func isRebootWaitActive(for deviceId: String) -> Bool {
        rebootWaitActiveByDeviceId.contains(deviceId)
    }

    func rebootWaitRemainingSeconds(for deviceId: String) -> Int {
        rebootWaitRemainingSecondsByDeviceId[deviceId] ?? 0
    }

    // MARK: - Device Sync

    func syncProfile(for sourceId: String) -> DeviceSyncProfile {
        syncProfilesBySource[sourceId] ?? DeviceSyncProfile(sourceDeviceId: sourceId)
    }

    func isSyncTargetSelected(sourceId: String, targetId: String) -> Bool {
        syncProfile(for: sourceId).targetDeviceIds.contains(targetId)
    }

    func syncTargetCount(for sourceId: String) -> Int {
        syncProfile(for: sourceId).targetDeviceIds.count
    }

    func syncDispatchMessage(for sourceId: String) -> String? {
        syncDispatchSummaryBySource[sourceId]?.message
    }

    func toggleSyncTarget(sourceId: String, targetId: String) {
        guard sourceId != targetId else { return }
        Task { [weak self] in
            guard let self else { return }
            let profile = await deviceSyncManager.toggleTarget(sourceId: sourceId, targetId: targetId)
            let profiles = await deviceSyncManager.loadProfiles()
            await MainActor.run {
                self.syncProfilesBySource = profiles
                if !profile.isActive {
                    self.syncDispatchSummaryBySource.removeValue(forKey: sourceId)
                }
            }
        }
    }

    func clearSyncTargets(sourceId: String) {
        Task { [weak self] in
            guard let self else { return }
            _ = await deviceSyncManager.clearTargets(sourceId: sourceId)
            let profiles = await deviceSyncManager.loadProfiles()
            await MainActor.run {
                self.syncProfilesBySource = profiles
                self.syncDispatchSummaryBySource.removeValue(forKey: sourceId)
            }
        }
    }

    func copyNowFromSource(_ device: WLEDDevice) async {
        let source = devices.first(where: { $0.id == device.id }) ?? device
        let segmentId = primarySegmentId(for: source)
        let effectState = currentEffectState(for: source, segmentId: segmentId)
        if effectState.isEnabled, effectState.effectId != 0 {
            let gradientStops = effectGradientStops(for: source.id) ?? gradientStops(for: source.id) ?? [
                GradientStop(position: 0.0, hexColor: source.currentColor.toHex()),
                GradientStop(position: 1.0, hexColor: source.currentColor.toHex())
            ]
            let gradient = LEDGradient(stops: gradientStops)
            await propagateIfNeeded(
                source: source,
                payload: .effectState(effectId: effectState.effectId, gradient: gradient, segmentId: segmentId),
                origin: .user
            )
        } else {
            let stops = gradientStops(for: source.id) ?? [
                GradientStop(position: 0.0, hexColor: source.currentColor.toHex()),
                GradientStop(position: 1.0, hexColor: source.currentColor.toHex())
            ]
            await propagateIfNeeded(
                source: source,
                payload: .gradient(
                    stops: stops,
                    interpolation: .linear,
                    segmentId: segmentId,
                    brightness: source.brightness,
                    on: source.isOn
                ),
                origin: .user
            )
        }
    }

    func propagateIfNeeded(source: WLEDDevice, payload: ColorsSyncPayload, origin: SyncOrigin) async {
        guard origin == .user else { return }
        let sourceId = source.id
        let availableById = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let summary = await deviceSyncManager.dispatch(from: sourceId, availableDevicesById: availableById) { [weak self] target in
            guard let self else { return .skipped }
            return await self.applySyncPayload(payload, to: target)
        }
        await MainActor.run {
            self.syncDispatchSummaryBySource[sourceId] = summary
        }
    }

    private func applySyncPayload(_ payload: ColorsSyncPayload, to target: WLEDDevice) async -> DeviceSyncManager.DispatchOutcome {
        guard isDeviceOnline(target) || target.isOnline else {
            return .skipped
        }

        switch payload {
        case .brightness(let value):
            await updateDeviceBrightness(target, brightness: value, userInitiated: false, origin: .propagated)
            return .applied
        case .gradient(let stops, let interpolation, let segmentId, let brightness, let on):
            let targetSegmentId = min(segmentId, max(0, getSegmentCount(for: target) - 1))
            await applyGradientStopsAcrossStrip(
                target,
                stops: stops,
                ledCount: totalLEDCount(for: target),
                segmentId: targetSegmentId,
                interpolation: interpolation,
                brightness: brightness,
                on: on,
                userInitiated: false,
                origin: .propagated,
                preferSegmented: true
            )
            return targetSegmentId == segmentId ? .applied : .downgraded
        case .effectState(let effectId, let gradient, let segmentId):
            let targetSegmentId = min(segmentId, max(0, getSegmentCount(for: target) - 1))
            let hasEffect = allEffectOptions(for: target).contains { $0.id == effectId }
            if hasEffect {
                await applyColorSafeEffect(
                    effectId,
                    with: gradient,
                    segmentId: targetSegmentId,
                    device: target,
                    userInitiated: false,
                    includeAllEffects: true,
                    origin: .propagated
                )
                return targetSegmentId == segmentId ? .applied : .downgraded
            }

            await applyGradientStopsAcrossStrip(
                target,
                stops: gradient.stops,
                ledCount: totalLEDCount(for: target),
                segmentId: targetSegmentId,
                interpolation: gradient.interpolation,
                userInitiated: false,
                origin: .propagated,
                preferSegmented: true
            )
            return .downgraded
        case .effectParameter(let parameter):
            let requestedSegmentId: Int
            switch parameter {
            case .speed(let segmentId, _),
                    .intensity(let segmentId, _),
                    .custom(let segmentId, _, _),
                    .palette(let segmentId, _),
                    .segmentBrightness(let segmentId, _),
                    .option(let segmentId, _, _):
                requestedSegmentId = segmentId
            }
            let mappedSegmentId = min(requestedSegmentId, max(0, getSegmentCount(for: target) - 1))
            switch parameter {
            case .speed(_, let value):
                await updateEffectSpeed(for: target, segmentId: mappedSegmentId, speed: value, origin: .propagated)
            case .intensity(_, let value):
                await updateEffectIntensity(for: target, segmentId: mappedSegmentId, intensity: value, origin: .propagated)
            case .custom(_, let index, let value):
                await updateEffectCustomParameter(for: target, segmentId: mappedSegmentId, index: index, value: value, origin: .propagated)
            case .palette(_, let paletteId):
                if let paletteId {
                    await updateEffectPalette(for: target, segmentId: mappedSegmentId, paletteId: paletteId, origin: .propagated)
                } else {
                    await clearEffectPalette(for: target, segmentId: mappedSegmentId, origin: .propagated)
                }
            case .segmentBrightness(_, let value):
                await updateSegmentBrightness(for: target, segmentId: mappedSegmentId, brightness: value, origin: .propagated)
            case .option(_, let optionIndex, let value):
                await updateEffectOption(for: target, segmentId: mappedSegmentId, optionIndex: optionIndex, value: value, origin: .propagated)
            }
            return mappedSegmentId == requestedSegmentId ? .applied : .downgraded
        case .transitionStart(let transition):
            await startTransition(
                from: transition.from,
                aBrightness: transition.aBrightness,
                to: transition.to,
                bBrightness: transition.bBrightness,
                durationSec: transition.durationSec,
                device: target,
                startStopTemperatures: transition.startStopTemperatures,
                startStopWhiteLevels: transition.startStopWhiteLevels,
                endStopTemperatures: transition.endStopTemperatures,
                endStopWhiteLevels: transition.endStopWhiteLevels,
                forceSegmentedOnly: transition.forceSegmentedOnly,
                origin: .propagated
            )
            return .applied
        case .effectDisable(let segmentId):
            await disableEffect(for: target, segmentId: segmentId, origin: .propagated)
            return .applied
        }
    }
    

    // MARK: - Initialization
    
    private init() {
        UserDefaults.standard.register(defaults: [
            "forceCCTSlider": true
        ])
        UserDefaults.standard.set(true, forKey: "forceCCTSlider")
        loadPendingPlaylistRenameQueue()
        setupSubscriptions()
        preloadPersistedDevicesIfAvailable()
        loadDevicesFromPersistence()
        setupWebSocketSubscriptions()
        startOnlineStatusRefreshTimer()
        Task { [weak self] in
            guard let self else { return }
            let profiles = await deviceSyncManager.loadProfiles()
            await MainActor.run {
                self.syncProfilesBySource = profiles
            }
        }
        
        // Start memory monitoring
        #if DEBUG
        startMemoryMonitoring()
        #endif
    }
    
    deinit {
        cancellables.removeAll()
        batchUpdateTimer?.invalidate()
        // Clean up all toggle timers
        toggleTimers.values.forEach { $0.invalidate() }
        toggleTimers.removeAll()
        
        // Cancel watchdog task
        watchdogTask?.cancel()
        onlineStatusTimer?.invalidate()
        onlineStatusTimer = nil
        
        // Note: webSocketManager.disconnectAll() is main actor-isolated
        // WebSocket connections will be cleaned up when the main actor context is deallocated
        
        // Clear all device-related collections
        pendingDeviceUpdates.removeAll()
        pendingToggles.removeAll()
        uiToggleStates.removeAll()
        lastUserInput.removeAll()
        runWatchdogs.removeAll()
        rebootWaitCountdownTasksByDeviceId.values.forEach { $0.cancel() }
        rebootWaitCountdownTasksByDeviceId.removeAll()
        rebootWaitProbeTasksByDeviceId.values.forEach { $0.cancel() }
        rebootWaitProbeTasksByDeviceId.removeAll()
        
        #if DEBUG
        print("DeviceControlViewModel deinit - Memory cleaned up")
        #endif
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

        // Subscribe to discovery errors
        wledService.$discoveryErrorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.discoveryErrorMessage, on: self)
            .store(in: &cancellables)

        // Subscribe to connection monitor health status updates
        connectionMonitor.$deviceHealthStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] healthStatus in
                guard let self else { return }
                if self.isRealTimeEnabled { return }
                self.updateDeviceHealthStatus(healthStatus)
            }
            .store(in: &cancellables)

        connectionMonitor.$reconnectionStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.reconnectionStatus, on: self)
            .store(in: &cancellables)

        connectionMonitor.$isNetworkAvailable
            .receive(on: DispatchQueue.main)
            .assign(to: \.isNetworkAvailable, on: self)
            .store(in: &cancellables)

        webSocketManager.$deviceConnectionStatuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                Task { @MainActor in
                    self?.refreshOnlineStatusesFromWebSocket(statuses)
                }
            }
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

        // On app entry, prefer first live state over persisted/default gradient cache.
        maybeHydrateGradientFromLiveState(
            stateUpdate.state,
            for: stateUpdate.deviceId,
            reason: "websocket.initial"
        )
        
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
                if let segment = primarySegment(from: state) {
                    let segmentId = segment.id ?? primarySegmentId(from: state)
                    var segmentStates = effectStates[stateUpdate.deviceId] ?? [:]
                    let cached = segmentStates[segmentId] ?? .default
                    let fxValue = segment.fx ?? cached.effectId
                    let newEffectState = DeviceEffectState(
                        effectId: fxValue,
                        speed: segment.sx ?? cached.speed,
                        intensity: segment.ix ?? cached.intensity,
                        paletteId: segment.pal ?? cached.paletteId,
                        custom1: segment.c1 ?? cached.custom1,
                        custom2: segment.c2 ?? cached.custom2,
                        custom3: segment.c3 ?? cached.custom3,
                        option1: segment.o1 ?? cached.option1,
                        option2: segment.o2 ?? cached.option2,
                        option3: segment.o3 ?? cached.option3,
                        isEnabled: fxValue != 0
                    )
                    segmentStates[segmentId] = newEffectState
                    effectStates[stateUpdate.deviceId] = segmentStates
                    
                    #if DEBUG
                    if fxValue != 0 {
                        os_log("[Effects][WS] Device %{public}@ segment %d: fx=%d sx=%d ix=%d pal=%@", log: OSLog.effects, type: .debug, updatedDevice.name, segmentId, fxValue, newEffectState.speed, newEffectState.intensity, String(describing: newEffectState.paletteId))
                    }
                    #endif

                    if newEffectState.isEnabled,
                       fxValue != 0,
                       let effectStops = effectGradientStops(from: segment),
                       !effectStops.isEmpty {
                        updateEffectGradient(LEDGradient(stops: effectStops), for: updatedDevice)
                        if shouldAdoptEffectGradientAsMain(deviceId: stateUpdate.deviceId, effectStops: effectStops) {
                            latestGradientStops[stateUpdate.deviceId] = effectStops
                            persistLatestGradient(effectStops, for: stateUpdate.deviceId)
                            markGradientHydratedFromLiveState(stateUpdate.deviceId)
                            updatedDevice.currentColor = GradientSampler.sampleColor(at: 0.5, stops: effectStops)
                        }
                    }
                }
                
                // Update color if available from segments
                // CRITICAL: Don't overwrite color if device has active CCT temperature OR active effect
                // OR if gradient was just applied (to prevent WebSocket echo from overwriting gradient)
                if let segment = primarySegment(from: state) {
                    let segmentId = segment.id ?? primarySegmentId(from: state)
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
                        if let preferred = preferredDisplayColor(for: stateUpdate.deviceId) {
                            updatedDevice.currentColor = preferred
                        } else if let normalized {
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
                    if shouldApplyNameUpdate(existingName: updatedDevice.name, candidateName: info.name) {
                        updatedDevice.name = info.name
                        hasSignificantChanges = true
                    }
                }
            } else if shouldApplyNameUpdate(existingName: updatedDevice.name, candidateName: info.name) {
                updatedDevice.name = info.name
                hasSignificantChanges = true
            }
        }
        
        // Use batched updates for better performance
        if hasSignificantChanges {
            scheduleDeviceUpdate(updatedDevice)
            lastSeenPersistedAt[stateUpdate.deviceId] = stateUpdate.timestamp
            
            // Persist the updated state in background
            Task.detached(priority: .background) {
                await CoreDataManager.shared.saveDevice(updatedDevice)
            }
        } else {
            // Just update the last seen timestamp for connection tracking (no UI update needed)
            devices[index].lastSeen = stateUpdate.timestamp
            devices[index].isOnline = true
            persistLastSeenIfNeeded(for: devices[index], timestamp: stateUpdate.timestamp)
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
        webSocketManager.resumeConnections()
        
        let targets = devices.filter { !isPlaceholderDevice($0) }
        let priorities = targets.enumerated().reduce(into: [String: Int]()) { result, entry in
            let id = entry.element.id
            if let existing = result[id] {
                result[id] = min(existing, entry.offset)
            } else {
                result[id] = entry.offset
            }
        }
        
        Task {
            await webSocketManager.connectToDevices(targets, priorities: priorities)
        }
        refreshOnlineStatusesFromWebSocket(webSocketManager.deviceConnectionStatuses, logTransitions: false)
    }
    
    private func disconnectAllWebSockets() {
        webSocketManager.suspendAllConnections()
    }
    
    private func connectWebSocketIfNeeded(for device: WLEDDevice) {
        guard isRealTimeEnabled else { return }
        guard !isPlaceholderDevice(device) else { return }
        guard isIPInCurrentSubnets(device.ipAddress) else { return }
        
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
                self.applyPersistedDevices(persistedDevices, replaceExisting: self.devices.isEmpty, source: "async")
            }
        }
    }

    private func preloadPersistedDevicesIfAvailable() {
        guard !didPreloadPersistedDevices else { return }
        let persistedDevices = coreDataManager.fetchDevicesSync()
        guard !persistedDevices.isEmpty else { return }
        didPreloadPersistedDevices = true
        applyPersistedDevices(persistedDevices, replaceExisting: true, source: "sync")
    }

    private func applyPersistedDevices(_ persistedDevices: [WLEDDevice], replaceExisting: Bool, source: String) {
        let placeholders = persistedDevices.filter { isPlaceholderDevice($0) }
        let persisted = persistedDevices.filter { !isPlaceholderDevice($0) }

        var newlyAdded: [WLEDDevice] = []

        if replaceExisting || devices.isEmpty {
            devices = persisted
            newlyAdded = persisted
        } else {
            let existingIds = Set(devices.map { $0.id })
            newlyAdded = persisted.filter { !existingIds.contains($0.id) }
            if !newlyAdded.isEmpty {
                devices.append(contentsOf: newlyAdded)
            }
        }

        if !placeholders.isEmpty {
            for placeholder in placeholders {
                Task {
                    await coreDataManager.deleteDevice(id: placeholder.id)
                }
            }
        }

        guard !newlyAdded.isEmpty else { return }

        // Preload persisted gradients so UI doesn't start from black.
        for device in newlyAdded {
            if let persistedStops = loadPersistedGradient(for: device.id), !persistedStops.isEmpty {
                latestGradientStops[device.id] = persistedStops
                hasLiveGradientHydration.remove(device.id)
                if allowsAppManagedSegments(for: device.id) {
                    appManagedSegmentDevices.insert(device.id)
                }
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].currentColor = GradientSampler.sampleColor(at: 0.5, stops: persistedStops)
                }
                #if DEBUG
                print("🔵 Preloaded gradient for \(device.name) (\(source)): \(persistedStops.count) stops")
                #endif
            }
        }

        // Register persisted devices with connection monitor
        for device in newlyAdded {
            connectionMonitor.registerDevice(device)
        }

        for device in newlyAdded {
            Task {
                await refreshLEDPreferencesIfNeeded(for: device)
            }
        }

        if isRealTimeEnabled {
            connectWebSocketsForAllDevices()
        }
    }
    
    /// Perform initial device status check when app launches
    private func performInitialDeviceStatusCheck() async {
        #if DEBUG
        print("🚀 App launched - performing initial device status check")
        #endif
        await performImmediateHealthChecksIfNeeded()
    }

    @MainActor
    private func performImmediateHealthChecksIfNeeded(force: Bool = false) async {
        let now = Date()
        if !force,
           let last = lastImmediateHealthCheckAt,
           now.timeIntervalSince(last) < immediateHealthCheckMinInterval {
            #if DEBUG
            print("Skipping immediate health checks (recently performed)")
            #endif
            return
        }
        lastImmediateHealthCheckAt = now
        await connectionMonitor.performImmediateHealthChecks()
    }
    
    private func handleDiscoveredDevices(_ discoveredDevices: [WLEDDevice]) async {
        let realDeviceIPs = Set(discoveredDevices.filter { !isPlaceholderDevice($0) }.map { $0.ipAddress })
        for rawDiscoveredDevice in discoveredDevices {
            var discoveredDevice = rawDiscoveredDevice
            if isPlaceholderDevice(discoveredDevice), realDeviceIPs.contains(discoveredDevice.ipAddress) {
                continue
            }
            if isPlaceholderDevice(discoveredDevice),
               devices.contains(where: { $0.ipAddress == discoveredDevice.ipAddress && !isPlaceholderDevice($0) }) {
                continue
            }

            if !isPlaceholderDevice(discoveredDevice),
               let placeholderIndex = devices.firstIndex(where: { isPlaceholderDevice($0) && $0.ipAddress == discoveredDevice.ipAddress }) {
                let placeholderDevice = devices[placeholderIndex]
                let placeholderId = placeholderDevice.id
                migratePlaceholderRuntimeState(
                    from: placeholderDevice,
                    toDeviceId: discoveredDevice.id,
                    discoveredDevice: &discoveredDevice
                )
                if activeDeviceId == placeholderId {
                    activeDeviceId = discoveredDevice.id
                }
                if selectedDevices.remove(placeholderId) != nil {
                    selectedDevices.insert(discoveredDevice.id)
                }
                pendingDiscoveryStateRefreshTasks[placeholderId]?.cancel()
                pendingDiscoveryStateRefreshTasks.removeValue(forKey: placeholderId)
                devices.remove(at: placeholderIndex)
                Task {
                    await coreDataManager.deleteDevice(id: placeholderId)
                }
            }

            // Check if device already exists
            if let existingIndex = devices.firstIndex(where: { $0.id == discoveredDevice.id }) {
                // Update existing device with any new information
                var updatedDevice = devices[existingIndex]
                let previousOnline = updatedDevice.isOnline
                let previousName = updatedDevice.name
                if shouldApplyNameUpdate(existingName: updatedDevice.name, candidateName: discoveredDevice.name) {
                    updatedDevice.name = discoveredDevice.name
                }
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
                
                if previousName != updatedDevice.name {
                    let source = discoverySource(for: updatedDevice) ?? "Discovery"
                    appendDiagnostics("Name updated: \(previousName) -> \(updatedDevice.name) (\(source))")
                }
                if previousOnline == false && updatedDevice.isOnline {
                    let source = discoverySource(for: updatedDevice) ?? "Discovery"
                    appendDiagnostics("Device online via \(source): \(updatedDevice.name)")
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

                let source = discoverySource(for: newDevice) ?? "Discovery"
                appendDiagnostics("Discovered device: \(newDevice.name) (\(newDevice.ipAddress)) via \(source)")
                
                // Force UI update for new device
                await MainActor.run {
                    objectWillChange.send()
                }

                scheduleFirstDiscoveryTimeSyncIfNeeded(for: newDevice)
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
                scheduleDiscoveryStateRefresh(for: discoveredDevice.id)
            }
        }
    }

    private func firstDiscoveryTimeSyncKey(for deviceId: String) -> String {
        firstDiscoveryTimeSyncKeyPrefix + deviceId
    }

    private func scheduleFirstDiscoveryTimeSyncIfNeeded(for device: WLEDDevice) {
        guard !isPlaceholderDevice(device) else { return }
        guard !firstDiscoveryTimeSyncAttemptedThisSession.contains(device.id) else { return }
        guard !UserDefaults.standard.bool(forKey: firstDiscoveryTimeSyncKey(for: device.id)) else { return }

        firstDiscoveryTimeSyncAttemptedThisSession.insert(device.id)
        let targetDevice = device
        Task { [weak self] in
            guard let self else { return }
            let coordinate = await AutomationStore.shared.currentCoordinate()

            do {
                try await self.apiService.updateDeviceTimeSettings(
                    for: targetDevice,
                    timeZone: .current,
                    coordinate: coordinate
                )
                UserDefaults.standard.set(true, forKey: self.firstDiscoveryTimeSyncKey(for: targetDevice.id))
                if coordinate == nil {
                    self.appendDiagnostics("First discovery time sync completed (timezone only): \(targetDevice.name)")
                } else {
                    self.appendDiagnostics("First discovery time sync completed: \(targetDevice.name)")
                }
            } catch {
                self.appendDiagnostics("First discovery time sync failed for \(targetDevice.name): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func scheduleDiscoveryStateRefresh(for deviceId: String) {
        pendingDiscoveryStateRefreshTasks[deviceId]?.cancel()
        pendingDiscoveryStateRefreshTasks[deviceId] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.discoveryStateRefreshDebounceNanos)
            guard !Task.isCancelled else { return }
            let target = await MainActor.run { self.devices.first(where: { $0.id == deviceId }) }
            guard let target else {
                _ = await MainActor.run {
                    self.pendingDiscoveryStateRefreshTasks.removeValue(forKey: deviceId)
                }
                return
            }
            if WLEDWebSocketManager.shared.isDeviceConnected(deviceId) {
                _ = await MainActor.run {
                    self.pendingDiscoveryStateRefreshTasks.removeValue(forKey: deviceId)
                }
                return
            }
            await self.refreshDeviceState(target)
            _ = await MainActor.run {
                self.pendingDiscoveryStateRefreshTasks.removeValue(forKey: deviceId)
            }
        }
    }

    private func isPlaceholderDevice(_ device: WLEDDevice) -> Bool {
        return device.id.hasPrefix("ip:")
    }

    private func migratePlaceholderRuntimeState(
        from placeholderDevice: WLEDDevice,
        toDeviceId discoveredDeviceId: String,
        discoveredDevice: inout WLEDDevice
    ) {
        let placeholderId = placeholderDevice.id

        if let optimisticState = uiToggleStates[placeholderId] {
            uiToggleStates[discoveredDeviceId] = optimisticState
            uiToggleStates.removeValue(forKey: placeholderId)
        }
        if let pending = pendingToggles[placeholderId] {
            pendingToggles[discoveredDeviceId] = pending
            pendingToggles.removeValue(forKey: placeholderId)
        }
        if let timer = toggleTimers[placeholderId] {
            toggleTimers[discoveredDeviceId] = timer
            toggleTimers.removeValue(forKey: placeholderId)
        }
        if let userInputAt = lastUserInput[placeholderId] {
            lastUserInput[discoveredDeviceId] = userInputAt
            lastUserInput.removeValue(forKey: placeholderId)
        }
        if let recentWrite = recentControlWriteSuccessAtByDeviceId[placeholderId] {
            recentControlWriteSuccessAtByDeviceId[discoveredDeviceId] = recentWrite
            recentControlWriteSuccessAtByDeviceId.removeValue(forKey: placeholderId)

            // Prevent stale discovery state from immediately flipping a just-toggled device back off.
            if Date().timeIntervalSince(recentWrite) < 3.0 {
                discoveredDevice.isOn = placeholderDevice.isOn
                discoveredDevice.brightness = placeholderDevice.brightness
                discoveredDevice.currentColor = placeholderDevice.currentColor
            }
        }
    }

    private func primarySegmentId(from state: WLEDState?) -> Int {
        guard let state = state else { return 0 }
        if let mainId = state.mainSegment,
           state.segments.contains(where: { ($0.id ?? 0) == mainId }) {
            return mainId
        }
        if let first = state.segments.first {
            return first.id ?? 0
        }
        return 0
    }

    private func primarySegmentId(for device: WLEDDevice) -> Int {
        return primarySegmentId(from: device.state)
    }

    func preferredSegmentId(for device: WLEDDevice) -> Int {
        return primarySegmentId(from: device.state)
    }

    private func primarySegment(from state: WLEDState?) -> Segment? {
        guard let state = state else { return nil }
        let mainId = primarySegmentId(from: state)
        if let segment = state.segments.first(where: { ($0.id ?? 0) == mainId }) {
            return segment
        }
        return state.segments.first
    }

    private func preferredDisplayColor(for deviceId: String) -> Color? {
        guard UserDefaults.standard.bool(forKey: "advancedUIEnabled") == false else { return nil }
        guard shouldUseAppManagedSegments(for: deviceId) else { return nil }
        guard let stops = latestGradientStops[deviceId], !stops.isEmpty else { return nil }
        return GradientSampler.sampleColor(at: 0.5, stops: stops)
    }

    private func markGradientHydratedFromLiveState(_ deviceId: String) {
        hasLiveGradientHydration.insert(deviceId)
    }

    private func rememberedGradientStops(for deviceId: String) -> [GradientStop]? {
        if let cached = latestGradientStops[deviceId], !cached.isEmpty {
            return cached
        }
        if let persisted = loadPersistedGradient(for: deviceId), !persisted.isEmpty {
            return persisted
        }
        return nil
    }

    private func gradientDistanceScore(_ lhs: [GradientStop], _ rhs: [GradientStop]) -> Double {
        let samplePositions: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let distances = samplePositions.map { t -> Double in
            let lhsColor = GradientSampler.sampleColor(at: t, stops: lhs).toHex()
            let rhsColor = GradientSampler.sampleColor(at: t, stops: rhs).toHex()
            return colorDistance(lhsColor, rhsColor)
        }
        guard !distances.isEmpty else { return 0.0 }
        return distances.reduce(0.0, +) / Double(distances.count)
    }

    private func shouldAdoptLiveGradient(_ liveStops: [GradientStop], over rememberedStops: [GradientStop]) -> Bool {
        if rememberedStops.isEmpty { return true }
        if isEffectivelySingleColor(liveStops), isEffectivelySingleColor(rememberedStops) {
            let liveHex = GradientSampler.sampleColor(at: 0.5, stops: liveStops).toHex()
            let rememberedHex = GradientSampler.sampleColor(at: 0.5, stops: rememberedStops).toHex()
            return !areColorsNearEqual(liveHex, rememberedHex, threshold: liveGradientReconcileDistanceThreshold)
        }
        let score = gradientDistanceScore(liveStops, rememberedStops)
        return score >= liveGradientReconcileDistanceThreshold
    }

    private func maybeHydrateGradientFromLiveState(
        _ state: WLEDState?,
        for deviceId: String,
        force: Bool = false,
        reason: String
    ) {
        guard let state else { return }
        let now = Date()
        let remembered = rememberedGradientStops(for: deviceId)
        if let remembered, !remembered.isEmpty,
           !force,
           let last = lastLiveGradientReconcileAt[deviceId],
           now.timeIntervalSince(last) < liveGradientReconcileCooldown {
            return
        }
        // Never let background/live hydration clobber active local edits.
        if isUnderUserControl(deviceId) { return }
        if let gradientTime = gradientApplicationTimes[deviceId],
           Date().timeIntervalSince(gradientTime) < gradientProtectionWindow {
            return
        }
        // Ignore effect-driven states for main color reconciliation.
        if let segment = primarySegment(from: state), (segment.fx ?? 0) != 0 {
            return
        }
        guard let refreshedStops = gradientStopsFromStateSegments(state, deviceId: deviceId), !refreshedStops.isEmpty else {
            return
        }

        if let remembered, !remembered.isEmpty {
            lastLiveGradientReconcileAt[deviceId] = now
            guard shouldAdoptLiveGradient(refreshedStops, over: remembered) else {
                #if DEBUG
                print("gradient.hydrate.skip device=\(deviceId) reason=\(reason) mode=reconcile diff=below_threshold")
                #endif
                return
            }
            #if DEBUG
            let score = gradientDistanceScore(refreshedStops, remembered)
            print("gradient.hydrate.reconcile device=\(deviceId) reason=\(reason) score=\(String(format: "%.2f", score))")
            #endif
        } else if !force, hasLiveGradientHydration.contains(deviceId) {
            return
        } else {
            #if DEBUG
            print("gradient.hydrate.bootstrap device=\(deviceId) reason=\(reason)")
            #endif
        }

        latestGradientStops[deviceId] = refreshedStops
        persistLatestGradient(refreshedStops, for: deviceId)
        markGradientHydratedFromLiveState(deviceId)
        #if DEBUG
        print("gradient.hydrate.live device=\(deviceId) reason=\(reason) stops=\(refreshedStops.count)")
        #endif
    }

    private func discoverySource(for device: WLEDDevice) -> String? {
        return wledService.lastDiscoverySourceByDevice[device.id] ?? wledService.lastDiscoverySourceByIP[device.ipAddress]
    }

    private func appendDiagnostics(_ message: String) {
        let entry = DiagnosticsEntry(timestamp: Date(), message: message)
        diagnosticsLog.append(entry)
        if diagnosticsLog.count > diagnosticsLogLimit {
            diagnosticsLog.removeFirst(diagnosticsLog.count - diagnosticsLogLimit)
        }
    }

    private func isGenericDeviceName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        if lower == "wled" || lower == "wled-ap" || lower == "aesdetic-led" {
            return true
        }
        if lower.hasPrefix("wled-") {
            let suffix = lower.dropFirst(5)
            let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            let isHexOrNumeric = !suffix.isEmpty && suffix.unicodeScalars.allSatisfy { hexSet.contains($0) }
            if isHexOrNumeric { return true }
        }
        return false
    }

    private func shouldApplyNameUpdate(existingName: String, candidateName: String) -> Bool {
        let existingTrimmed = existingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateTrimmed = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidateTrimmed.isEmpty else { return false }
        if existingTrimmed == candidateTrimmed { return false }

        let existingGeneric = isGenericDeviceName(existingTrimmed)
        let candidateGeneric = isGenericDeviceName(candidateTrimmed)

        if existingGeneric && !candidateGeneric { return true }
        if !existingGeneric && candidateGeneric { return false }
        return true
    }
    
    private func updateDeviceHealthStatus(_ healthStatus: [String: Bool]) {
        var hasChanges = false
        for (deviceId, isOnline) in healthStatus {
            if let index = devices.firstIndex(where: { $0.id == deviceId }) {
                if devices[index].isOnline != isOnline {
                    devices[index].isOnline = isOnline
                    hasChanges = true
                    let statusLabel = isOnline ? "online" : "offline"
                    appendDiagnostics("Health check: \(devices[index].name) is \(statusLabel)")
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

    private func refreshOnlineStatusesFromWebSocket(_ statuses: [String: WLEDWebSocketManager.DeviceConnectionStatus], logTransitions: Bool = true) {
        guard isRealTimeEnabled else { return }
        let now = Date()
        var hasChanges = false

        for index in devices.indices {
            let deviceId = devices[index].id
            let status = statuses[deviceId]
            let wsStatus = status?.status
            let lastSeen = devices[index].lastSeen
            let withinGrace = now.timeIntervalSince(lastSeen) < offlineGracePeriod
            let recentControlWrite = recentControlWriteSuccessAtByDeviceId[deviceId]
                .map { now.timeIntervalSince($0) < controlWriteOnlineGraceInterval } ?? false
            let recentWSConnect = status?.lastConnected.map { now.timeIntervalSince($0) < offlineGracePeriod } ?? false
            let transientWSRecoveryWindow = (wsStatus == .connecting || wsStatus == .reconnecting)
                && (devices[index].isOnline || recentWSConnect || recentControlWrite)
            let shouldBeOnline = (wsStatus == .connected) || withinGrace || recentControlWrite || transientWSRecoveryWindow

            if devices[index].isOnline != shouldBeOnline {
                devices[index].isOnline = shouldBeOnline
                hasChanges = true
                if logTransitions {
                    let statusLabel = shouldBeOnline ? "online" : "offline"
                    appendDiagnostics("WebSocket status: \(devices[index].name) is \(statusLabel)")
                }
            }
        }

        if hasChanges {
            objectWillChange.send()
        }
    }

    private func persistLastSeenIfNeeded(for device: WLEDDevice, timestamp: Date) {
        let lastPersisted = lastSeenPersistedAt[device.id] ?? .distantPast
        guard timestamp.timeIntervalSince(lastPersisted) >= lastSeenPersistInterval else { return }
        lastSeenPersistedAt[device.id] = timestamp
        var updated = device
        updated.lastSeen = timestamp
        Task.detached(priority: .background) {
            await CoreDataManager.shared.saveDevice(updated)
        }
    }

    private func startOnlineStatusRefreshTimer() {
        onlineStatusTimer?.invalidate()
        onlineStatusTimer = Timer.scheduledTimer(withTimeInterval: onlineStatusRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshOnlineStatusesFromWebSocket(self.webSocketManager.deviceConnectionStatuses)
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

    @MainActor
    func removeDevice(_ device: WLEDDevice) async {
        // Disconnect realtime connections
        webSocketManager.disconnect(from: device.id)
        connectionMonitor.unregisterDevice(device.id)
        endRebootWait(for: device.id)

        // Clear in-memory caches
        pendingToggles.removeValue(forKey: device.id)
        uiToggleStates.removeValue(forKey: device.id)
        lastUserInput.removeValue(forKey: device.id)
        runWatchdogs.removeValue(forKey: device.id)
        activeRunStatus.removeValue(forKey: device.id)
        pendingFinalStates.removeValue(forKey: device.id)
        lastBrightnessBeforeOff.removeValue(forKey: device.id)
        savedTransitionDefaults.removeValue(forKey: device.id)
        savedTransitionDefaultRunIds.removeValue(forKey: device.id)
        temporaryPresetIds.removeValue(forKey: device.id)
        temporaryPlaylistIds.removeValue(forKey: device.id)
        playlistRunsByDevice.remove(device.id)
        hasLiveGradientHydration.remove(device.id)
        lastSeenPersistedAt.removeValue(forKey: device.id)
        deviceCapabilities.removeValue(forKey: device.id)
        deviceLedCounts.removeValue(forKey: device.id)
        deviceMaxSegmentCounts.removeValue(forKey: device.id)
        effectStates.removeValue(forKey: device.id)
        segmentCCTFormats.removeValue(forKey: device.id)
        presetsCache.removeValue(forKey: device.id)
        presetLoadingStates.removeValue(forKey: device.id)
        playlistsCache.removeValue(forKey: device.id)
        playlistLoadingStates.removeValue(forKey: device.id)
        presetModificationTimes.removeValue(forKey: device.id)
        latestGradientStops.removeValue(forKey: device.id)
        latestEffectGradientStops.removeValue(forKey: device.id)
        latestTransitionDurations.removeValue(forKey: device.id)
        effectMetadataLastFetched.removeValue(forKey: device.id)
        lastGradientBeforeEffect.removeValue(forKey: device.id)
        ledPreferencesLastFetched.removeValue(forKey: device.id)
        ledStripTypeByDevice.removeValue(forKey: device.id)
        deviceStateCache.removeValue(forKey: device.id)

        // Remove from UI list
        devices.removeAll { $0.id == device.id }
        cachedFilteredDevices = []
        lastFilterUpdate = .distantPast

        // Delete from persistence
        await coreDataManager.deleteDevice(id: device.id)
    }
    
    func toggleDevicePower(_ device: WLEDDevice) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        await cancelActiveRun(for: device, force: true, endReason: .cancelledByManualInput)
        
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
                if let segment = primarySegment(from: response.state), let fxValue = segment.fx, fxValue != 0 {
                    // WLED restored an effect - disable it
                    let segmentId = segment.id ?? primarySegmentId(from: response.state)
                    let segmentUpdate = SegmentUpdate(id: segmentId, fx: 0, pal: 0, frz: false)
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
    
    
    func updateDeviceBrightness(_ device: WLEDDevice, brightness: Int, userInitiated: Bool = true, origin: SyncOrigin = .user) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        if userInitiated {
            if hasKnownActiveRun(for: device.id) {
                await cancelActiveRun(for: device, force: true, endReason: .cancelledByManualInput)
            }
        }
        
        markUserInteraction(device.id)
        
        // CRITICAL: WLED treats brightness 0% as "off" (on: false)
        // When brightness is 0%, we should turn device off
        // When brightness goes from 0% to >0%, we should turn device on
        let actualDevice = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        let expectedPowerState = brightness > 0
        if actualDevice.brightness == brightness && actualDevice.isOn == expectedPowerState {
            return
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
            await propagateIfNeeded(source: device, payload: .brightness(value: 0), origin: origin)
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
                if let state = actualState, let segment = primarySegment(from: state) {
                    let fxValue = segment.fx ?? 0
                    hasActiveEffect = fxValue != 0
                    
                    if hasActiveEffect {
                        // Disable effect before applying gradient
                        let segmentId = segment.id ?? primarySegmentId(from: state)
                        let segmentUpdate = SegmentUpdate(id: segmentId, fx: 0, pal: 0, frz: false)
                        let effectOffUpdate = WLEDStateUpdate(seg: [segmentUpdate])
                        _ = try? await apiService.updateState(for: updatedDevice, state: effectOffUpdate)
                        
                        // Update effect state cache
                        await MainActor.run {
                            var segmentStates = self.effectStates[device.id] ?? [:]
                            let segmentId = segmentId
                            segmentStates[segmentId] = DeviceEffectState(
                                effectId: 0,
                                speed: segment.sx ?? 128,
                                intensity: segment.ix ?? 128,
                                paletteId: segment.pal,
                                custom1: segment.c1,
                                custom2: segment.c2,
                                custom3: segment.c3,
                                option1: segment.o1,
                                option2: segment.o2,
                                option3: segment.o3,
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
            await propagateIfNeeded(source: device, payload: .brightness(value: 0), origin: origin)
            return
        }
        var shouldPropagateBrightness = false
        
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
            shouldPropagateBrightness = true
        } else {
            // No gradient - use simple brightness update
            // CRITICAL: WLED treats brightness 0% as "off" (on: false)
            // Include on state in brightness update to ensure proper state
            let shouldBeOn = brightness > 0
            let transitionDeciseconds = resolvedTransitionDeciseconds(for: device, fallbackSeconds: directBrightnessTransitionSeconds)
            let stateUpdate = WLEDStateUpdate(
                on: shouldBeOn ? true : false,  // CRITICAL: Explicitly set on=false when brightness is 0%
                bri: brightness,
                transitionDeciseconds: transitionDeciseconds,
                lor: 0
            )
        
        do {
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            
            // Send WebSocket update if connected
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
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
            shouldPropagateBrightness = true
            
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            await MainActor.run {
                self.presentError(mappedError)
                }
            }
        }
        if shouldPropagateBrightness {
            await propagateIfNeeded(source: device, payload: .brightness(value: brightness), origin: origin)
        }
    }

    /// Update brightness while an effect is running without disrupting effect state.
    /// Uses WebSocket when available to avoid HTTP timeouts and skips run cancellation.
    func updateAnimationBrightness(_ device: WLEDDevice, brightness: Int) async {
        let clamped = max(1, min(255, brightness))
        let shouldBeOn = clamped > 0
        markUserInteraction(device.id)
        let transitionDeciseconds = resolvedTransitionDeciseconds(for: device, fallbackSeconds: directBrightnessTransitionSeconds)
        let stateUpdate = WLEDStateUpdate(
            on: shouldBeOn,
            bri: clamped,
            transitionDeciseconds: transitionDeciseconds
        )
        
        let wsConnected = webSocketManager.isDeviceConnected(device.id)
        if wsConnected {
            webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            await MainActor.run {
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].brightness = clamped
                    devices[index].isOn = shouldBeOn
                    devices[index].isOnline = true
                }
                if clamped > 0 {
                    self.lastBrightnessBeforeOff[device.id] = clamped
                }
                clearError()
            }
            var updatedDevice = device
            updatedDevice.brightness = clamped
            updatedDevice.isOn = shouldBeOn
            updatedDevice.isOnline = true
            updatedDevice.lastSeen = Date()
            await coreDataManager.saveDevice(updatedDevice)
            return
        }
        
        do {
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            await MainActor.run {
                if let index = devices.firstIndex(where: { $0.id == device.id }) {
                    devices[index].brightness = clamped
                    devices[index].isOn = shouldBeOn
                    devices[index].isOnline = true
                }
                if clamped > 0 {
                    self.lastBrightnessBeforeOff[device.id] = clamped
                }
                clearError()
            }
            var updatedDevice = device
            updatedDevice.brightness = clamped
            updatedDevice.isOn = shouldBeOn
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
    
    func updateDeviceColor(_ device: WLEDDevice, color: Color, origin: SyncOrigin = .user) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        await cancelActiveRun(for: device, force: true, endReason: .cancelledByManualInput)
        markUserInteraction(device.id)

        let hex = color.toHex()
        let stops = [
            GradientStop(position: 0.0, hexColor: hex),
            GradientStop(position: 1.0, hexColor: hex)
        ]
        let segmentId = primarySegmentId(for: device)
        let ledCount = totalLEDCount(for: device)
        let transitionDurationSeconds = defaultTransitionDeciseconds(for: device) == nil
            ? directColorTransitionSeconds
            : nil
        await applyGradientStopsAcrossStrip(
            device,
            stops: stops,
            ledCount: ledCount,
            disableActiveEffect: true,
            segmentId: segmentId,
            on: true,
            transitionDurationSeconds: transitionDurationSeconds,
            userInitiated: true,
            origin: origin,
            preferSegmented: true
        )
    }
    
    /// Apply CCT (Correlated Color Temperature) to a device
    /// - Parameters:
    ///   - device: The WLED device
    ///   - temperature: Temperature slider value (0.0-1.0, where 0=warm, 1=cool)
    ///   - withColor: Optional RGB color to set along with CCT
    func applyCCT(to device: WLEDDevice, temperature: Double, withColor: [Int]? = nil, segmentId: Int? = nil) async {
        markUserInteraction(device.id)
        let targetSegmentId = segmentId ?? primarySegmentId(for: device)
        guard supportsCCTOutput(for: device, segmentId: targetSegmentId) else { return }
        let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: targetSegmentId)
        let cct: Int = usesKelvin ? kelvinValue(for: device, normalized: temperature) : Segment.eightBitValue(fromNormalized: temperature)
        
        do {
            if let color = withColor {
                _ = try await apiService.setColor(for: device, color: color, cct: cct, segmentId: targetSegmentId)
            } else {
                // CRITICAL: When sending CCT-only, we must send ONLY CCT (no RGB)
                // However, if the device doesn't support CCT or has it disabled,
                // WLED will ignore the CCT value. As a fallback, we can send the RGB
                // color that WLED would produce from CCT, but ONLY if CCT fails.
                // For now, try CCT-only first (correct approach)
                if usesKelvin {
                    _ = try await apiService.setCCT(for: device, cctKelvin: cct, segmentId: targetSegmentId)
                } else {
                    _ = try await apiService.setCCT(for: device, cct: cct, segmentId: targetSegmentId)
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
                    id: targetSegmentId,
                    col: nil,  // Explicitly nil - JSON encoder will omit this field
                    cct: cct,
                    fx: 0  // Disable effects to allow CCT to work
                )
                let stateUpdate = WLEDStateUpdate(seg: [segment])
                
                // Debug logging
                #if DEBUG
                print("🔵 WebSocket CCT update: segmentId=\(segmentId ?? -1), cct=\(cct), col=nil")
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
        await cancelActiveRun(for: device, force: true, endReason: .cancelledByManualInput)
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
                if let segment = primarySegment(from: response.state), let fxValue = segment.fx, fxValue != 0 {
                    // WLED restored an effect - disable it
                    let segmentId = segment.id ?? primarySegmentId(from: response.state)
                    let segmentUpdate = SegmentUpdate(id: segmentId, fx: 0, pal: 0, frz: false)
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

    func fetchUDPSyncState(for device: WLEDDevice) async -> (send: Bool, recv: Bool, network: Int)? {
        do {
            return try await apiService.fetchUDPSyncConfig(for: device)
        } catch {
            return nil
        }
    }

    func rebootDevice(_ device: WLEDDevice) async {
        await cancelActiveRun(for: device, force: true)
        markUserInteraction(device.id)
        clearUIOptimisticState(deviceId: device.id)
        let wasOnlineBeforeReboot = isDeviceOnline(device) || device.isOnline

        do {
            try await apiService.rebootDevice(device)
            clearError()
            beginRebootWait(for: device)
        } catch {
            if wasOnlineBeforeReboot && isExpectedRebootDisconnect(error) {
                clearError()
                beginRebootWait(for: device)
            } else {
                let mappedError = mapToWLEDError(error, device: device)
                presentError(mappedError)
            }
        }
    }

    private func beginRebootWait(for device: WLEDDevice) {
        endRebootWait(for: device.id)
        rebootWaitActiveByDeviceId.insert(device.id)
        rebootWaitRemainingSecondsByDeviceId[device.id] = rebootWaitMaxSeconds

        let deviceId = device.id
        let waitSeconds = rebootWaitMaxSeconds

        rebootWaitCountdownTasksByDeviceId[deviceId] = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: waitSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || !self.rebootWaitActiveByDeviceId.contains(deviceId) { return }
                self.rebootWaitRemainingSecondsByDeviceId[deviceId] = remaining
            }

            if self.rebootWaitActiveByDeviceId.contains(deviceId) {
                self.endRebootWait(for: deviceId)
            }
        }

        rebootWaitProbeTasksByDeviceId[deviceId] = Task { @MainActor [weak self] in
            guard let self else { return }
            // Avoid reading stale pre-reboot state immediately after issuing reboot.
            try? await Task.sleep(nanoseconds: self.rebootProbeInitialDelayNanos)

            while self.rebootWaitActiveByDeviceId.contains(deviceId) {
                if Task.isCancelled { return }
                do {
                    await self.apiService.invalidateStateCache(for: deviceId)
                    _ = try await self.apiService.getState(for: device)
                    self.clearUIOptimisticState(deviceId: deviceId)
                    await self.refreshDeviceState(device)
                    self.endRebootWait(for: deviceId)
                    return
                } catch {
                    // Keep waiting until state is reachable again or countdown expires.
                }
                try? await Task.sleep(nanoseconds: self.rebootProbeIntervalNanos)
            }
        }
    }

    private func endRebootWait(for deviceId: String) {
        rebootWaitCountdownTasksByDeviceId[deviceId]?.cancel()
        rebootWaitCountdownTasksByDeviceId.removeValue(forKey: deviceId)
        rebootWaitProbeTasksByDeviceId[deviceId]?.cancel()
        rebootWaitProbeTasksByDeviceId.removeValue(forKey: deviceId)
        rebootWaitActiveByDeviceId.remove(deviceId)
        rebootWaitRemainingSecondsByDeviceId.removeValue(forKey: deviceId)
    }

    private func isExpectedRebootDisconnect(_ error: Error) -> Bool {
        if let apiError = error as? WLEDAPIError {
            switch apiError {
            case .timeout, .deviceOffline, .deviceUnreachable:
                return true
            case .networkError(let nested):
                if let urlError = nested as? URLError {
                    switch urlError.code {
                    case .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                        return true
                    default:
                        return false
                    }
                }
                return false
            default:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }
    
    private func updateDeviceState(_ device: WLEDDevice, update: (WLEDDevice) -> WLEDDevice) async {
        let updatedDevice = update(device)
        
        do {
            // Check if we have a persisted gradient that will be restored
            let hasPersistedGradient = gradientStops(for: device.id)?.isEmpty == false
            let transitionDeciseconds = resolvedTransitionDeciseconds(for: updatedDevice, fallbackSeconds: directBrightnessTransitionSeconds)
            let playlistStopValue: Int? = shouldSendPlaylistStopForStateWrite(device.id) ? -1 : nil
            
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
                    transitionDeciseconds: transitionDeciseconds,
                    pl: playlistStopValue,
                    lor: 0
                )
            } else {
                let isTurningOn = (!device.isOn || device.brightness == 0) && updatedDevice.isOn && updatedDevice.brightness > 0
                let shouldAvoidBlackOnPowerOn = isTurningOn && isNearBlack(updatedDevice.currentColor)

                if shouldAvoidBlackOnPowerOn {
                    // Preserve WLED's remembered color on first power-on when local color is still uninitialized.
                    stateUpdate = WLEDStateUpdate(
                        on: updatedDevice.isOn,
                        bri: updatedDevice.brightness,
                        seg: nil,
                        transitionDeciseconds: transitionDeciseconds,
                        pl: playlistStopValue,
                        lor: 0
                    )
                } else {
                    // No persisted gradient - send solid color as before
                    let rgb = rgbArrayWithOptionalWhite(updatedDevice.currentColor.toRGBArray(), device: device)
                    stateUpdate = WLEDStateUpdate(
                        on: updatedDevice.isOn,
                        bri: updatedDevice.brightness,
                        seg: [SegmentUpdate(col: [rgb])],
                        transitionDeciseconds: transitionDeciseconds,
                        pl: playlistStopValue,
                        lor: 0
                    )
                }
            }
            
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            let writeSucceededAt = Date()
            
            // Send WebSocket update if connected (for faster local feedback)
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            
            // Update local device list immediately with optimistic update
            await MainActor.run {
                if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                    var committed = updatedDevice
                    committed.isOnline = true
                    committed.lastSeen = writeSucceededAt
                    self.devices[index] = committed
                    self.devices[index].isOnline = true // Ensure device stays online after successful update
                    self.devices[index].lastSeen = writeSucceededAt
                    
                    // Sync to widget
                    WidgetDataSync.shared.syncDevice(self.devices[index])
                }
                self.noteControlWriteSuccess(deviceId: device.id)
                self.clearError()
            }
            
            // Persist to Core Data
            var persistedDevice = updatedDevice
            persistedDevice.isOnline = true
            persistedDevice.lastSeen = writeSucceededAt
            await coreDataManager.saveDevice(persistedDevice)
            
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

    private func isNearBlack(_ color: Color, threshold: Int = 2) -> Bool {
        let rgb = color.toRGBArray()
        guard rgb.count >= 3 else { return true }
        return rgb[0] <= threshold && rgb[1] <= threshold && rgb[2] <= threshold
    }
    
    // MARK: - Device Discovery
    
    func startScanning() async {
        wledService.startDiscovery()
    }

    func startPassiveDiscovery() {
        wledService.startPassiveDiscovery()
    }

    func requestLocalNetworkPermission() {
        LocalNetworkPrompter.shared.trigger()
    }

    func dismissDiscoveryError() {
        discoveryErrorMessage = nil
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
            await handlePresetModificationIfNeeded(response, device: device)
            let ledCount = response.info.leds.count
            if ledCount > 0 {
                deviceLedCounts[device.id] = ledCount
            }
            if let maxseg = response.info.leds.maxseg, maxseg > 0 {
                deviceMaxSegmentCounts[device.id] = maxseg
            }
            if let matrix = response.info.leds.matrix {
                deviceIsMatrixById[device.id] = matrix.w > 0 && matrix.h > 0
            } else {
                deviceIsMatrixById[device.id] = false
            }
            
            // Detect and cache capabilities using CapabilityDetector
            let seglc = response.info.leds.seglc ?? fallbackSeglc(from: response.info.leds, state: response.state)
            if let seglc {
                if !seglc.isEmpty {
                    let existing = deviceMaxSegmentCounts[device.id] ?? 0
                    if seglc.count > existing {
                        deviceMaxSegmentCounts[device.id] = seglc.count
                    }
                }
                let capabilities = await capabilityDetector.detect(deviceId: device.id, seglc: seglc)
                // Cache locally for synchronous access from MainActor
                await MainActor.run {
                    self.deviceCapabilities[device.id] = capabilities
                }
            }

            await refreshLEDPreferencesIfNeeded(for: device)
            
            await fetchEffectMetadataIfNeeded(for: device)
            
            await MainActor.run {
                // Event-driven reconcile: bootstrap once if needed, otherwise
                // adopt live state only when significantly different.
                self.maybeHydrateGradientFromLiveState(
                    response.state,
                    for: device.id,
                    reason: "refresh.event"
                )

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
                        if let segment = primarySegment(from: response.state) {
                            let segmentId = segment.id ?? primarySegmentId(from: response.state)
                            let effectState = self.effectStates[device.id]?[segmentId]
                            let hasActiveEffect = effectState?.isEnabled == true && (effectState?.effectId ?? 0) != 0
                            if !hasActiveEffect,
                               self.latestGradientStops[device.id] != nil || self.loadPersistedGradient(for: device.id) != nil {
                                self.maybeHydrateGradientFromLiveState(
                                    response.state,
                                    for: device.id,
                                    reason: "refresh.reconcile"
                                )
                            }
                            let normalized = segment.cctNormalized
                            updatedDevice.temperature = normalized

                            if let normalized, !hasActiveEffect {
                                if let preferred = self.preferredDisplayColor(for: device.id) {
                                    updatedDevice.currentColor = preferred
                                } else {
                                    updatedDevice.currentColor = Color.color(fromCCTTemperature: normalized)
                                }
                            } else if let color = derivedColor(from: segment), !hasActiveEffect {
                                if let preferred = self.preferredDisplayColor(for: device.id) {
                                    updatedDevice.currentColor = preferred
                                } else {
                                    updatedDevice.currentColor = color
                                }
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
                        custom1: segment.c1 ?? cached.custom1,
                        custom2: segment.c2 ?? cached.custom2,
                        custom3: segment.c3 ?? cached.custom3,
                        option1: segment.o1 ?? cached.option1,
                        option2: segment.o2 ?? cached.option2,
                        option3: segment.o3 ?? cached.option3,
                        isEnabled: fxValue != 0
                    )
                    segmentStates[segmentIdentifier] = newState
                }
                self.effectStates[device.id] = segmentStates

                // If an effect is active, derive a gradient from the current segment colors.
                // This keeps the UI in sync after app relaunch without overriding device state.
                if let segment = primarySegment(from: response.state) {
                    let segmentIdentifier = segment.id ?? primarySegmentId(from: response.state)
                    if let effectState = segmentStates[segmentIdentifier],
                       effectState.isEnabled,
                       effectState.effectId != 0,
                       let effectStops = effectGradientStops(from: segment),
                       !effectStops.isEmpty {
                        self.updateEffectGradient(LEDGradient(stops: effectStops), for: device)
                        if shouldAdoptEffectGradientAsMain(deviceId: device.id, effectStops: effectStops) {
                            self.latestGradientStops[device.id] = effectStops
                            self.persistLatestGradient(effectStops, for: device.id)
                            self.markGradientHydratedFromLiveState(device.id)
                            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                                self.devices[index].currentColor = GradientSampler.sampleColor(at: 0.5, stops: effectStops)
                            }
                        }
                    }
                }
            }
            
            // Update persistence
            var persistDevice = device
            persistDevice.state = response.state
            persistDevice.brightness = response.state.brightness
            persistDevice.isOn = response.state.isOn
            persistDevice.isOnline = true
            persistDevice.lastSeen = Date()
            
            if let segment = primarySegment(from: response.state) {
                if let preferred = preferredDisplayColor(for: device.id) {
                    persistDevice.currentColor = preferred
                } else if let color = derivedColor(from: segment) {
                    persistDevice.currentColor = color
                }
                persistDevice.temperature = segment.cctNormalized
            }
            
            await coreDataManager.saveDevice(persistDevice)
            
            clearError()

            await maybeAutoRestoreSegmentsAfterReboot(device: device, response: response)
            
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            if case .deviceOffline = mappedError {
                presentError(mappedError)
            }
        }
    }

    // MARK: - Capability Helpers
    func supportsCCT(for device: WLEDDevice, segmentId: Int = 0) -> Bool {
        if UserDefaults.standard.bool(forKey: "forceCCTSlider") {
            return true
        }
        if cctKelvinRanges[device.id] != nil {
            return true
        }
        if let stripType = ledStripTypeByDevice[device.id], stripType.usesCCT {
            return true
        }
        // Use local cache for synchronous access from MainActor
        if let capabilities = deviceCapabilities[device.id],
           let segmentCap = capabilities.capabilities(for: segmentId) {
            return segmentCap.supportsCCT
        }
        if let segment = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId }),
           let lc = segment.lc {
            return (lc & 0b100) != 0
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

    func supportsCCTOutput(for device: WLEDDevice, segmentId: Int = 0) -> Bool {
        if cctKelvinRanges[device.id] != nil {
            return true
        }
        if let stripType = ledStripTypeByDevice[device.id], stripType.usesCCT {
            return true
        }
        if let capabilities = deviceCapabilities[device.id],
           let segmentCap = capabilities.capabilities(for: segmentId) {
            return segmentCap.supportsCCT
        }
        if let segment = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId }),
           let lc = segment.lc {
            return (lc & 0b100) != 0
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
        if let stripType = ledStripTypeByDevice[device.id], stripType.usesWhiteChannel {
            return true
        }
        if cctKelvinRanges[device.id] != nil {
            return true
        }
        // Use local cache for synchronous access from MainActor
        if let capabilities = deviceCapabilities[device.id],
           let segmentCap = capabilities.capabilities(for: segmentId) {
            return segmentCap.supportsWhite
        }
        if let segment = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId }),
           let lc = segment.lc {
            return (lc & 0b010) != 0
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
        if let segment = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId }),
           let lc = segment.lc {
            return (lc & 0b001) != 0
        }
        // Use local cache for synchronous access from MainActor
        guard let capabilities = deviceCapabilities[device.id],
              let segmentCap = capabilities.capabilities(for: segmentId) else {
            return true // Default to true for RGB
        }
        return segmentCap.supportsRGB
    }

    private func rgbArrayWithOptionalWhite(_ rgb: [Int], device: WLEDDevice, segmentId: Int = 0) -> [Int] {
        guard rgb.count >= 3 else { return rgb }
        if supportsWhite(for: device, segmentId: segmentId), rgb.count == 3 {
            return rgb + [0]
        }
        return rgb
    }
    
    func getSegmentCount(for device: WLEDDevice) -> Int {
        if let segments = device.state?.segments, !segments.isEmpty {
            return segments.count
        }
        if let capabilities = deviceCapabilities[device.id], !capabilities.segments.isEmpty {
            return capabilities.segments.count
        }
        return 1 // Default to single segment
    }

    private func syncSegmentCapabilities(for device: WLEDDevice, segmentCount: Int) {
        guard segmentCount > 0 else { return }
        var capabilities = deviceCapabilities[device.id] ?? WLEDCapabilities(deviceId: device.id)
        let hasCCT = device.temperature != nil
            || (device.state?.segments.contains { $0.cct != nil } ?? false)
        let hasWhite = (device.state?.segments.contains { segment in
            guard let colors = segment.colors else { return false }
            return colors.contains { $0.count >= 4 }
        } ?? false) || (ledStripTypeByDevice[device.id]?.usesWhiteChannel ?? true)
        let template = capabilities.segments[0]
            ?? SegmentCapabilities(rgb: true, white: hasWhite, cct: hasCCT)

        var updated: [Int: SegmentCapabilities] = [:]
        for idx in 0..<segmentCount {
            updated[idx] = capabilities.segments[idx] ?? template
        }
        capabilities.segments = updated
        capabilities.lastUpdated = Date()
        deviceCapabilities[device.id] = capabilities
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
            async let namesTask = apiService.fetchEffectNames(for: device)
            async let fxTask = apiService.fetchFxData(for: device)
            let paletteNames = (try? await apiService.fetchPaletteNames(for: device)) ?? []
            let (effectNames, fxData) = try await (namesTask, fxTask)
            effectMetadataLastFetched[device.id] = now
            rawEffectMetadata[device.id] = fxData
            let bundle = EffectMetadataParser.parse(effectNames: effectNames, fxData: fxData, palettes: paletteNames)
            effectMetadataBundles[device.id] = bundle
        } catch {
            // Silently ignore metadata fetch failures to avoid impacting main flow
        }
    }

    func loadPalettePreviewsIfNeeded(for device: WLEDDevice, force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: "advancedUIEnabled") else { return }
        guard let bundle = effectMetadata(for: device), !bundle.palettes.isEmpty else { return }
        let now = Date()
        let lastFetch = palettePreviewLastFetched[device.id] ?? .distantPast
        guard force || now.timeIntervalSince(lastFetch) > palettePreviewRefreshInterval else { return }
        do {
            var aggregated: [Int: [PalettePreviewEntry]] = [:]
            var page = 0
            var maxPage = 0
            repeat {
                let response = try await apiService.fetchPalettePreviewPage(for: device, page: page)
                maxPage = response.maxPage
                let parsed = parsePalettePreviewEntries(response.palettes)
                aggregated.merge(parsed) { existing, _ in existing }
                page += 1
            } while page <= maxPage
            await MainActor.run {
                palettePreviewEntriesByDevice[device.id] = aggregated
                palettePreviewLastFetched[device.id] = now
            }
        } catch {
            // Silently ignore palette preview failures; UI will fall back to gradient colors.
        }
    }

    func palettePreviewStops(for device: WLEDDevice, paletteId: Int, fallbackGradient: LEDGradient) -> [GradientStop] {
        guard let entries = palettePreviewEntriesByDevice[device.id]?[paletteId],
              !entries.isEmpty else {
            return fallbackGradient.stops
        }
        return palettePreviewStops(from: entries, fallbackGradient: fallbackGradient)
    }

    private func parsePalettePreviewEntries(_ palettes: [String: Any]) -> [Int: [PalettePreviewEntry]] {
        var results: [Int: [PalettePreviewEntry]] = [:]
        for (key, value) in palettes {
            guard let paletteId = Int(key),
                  let entries = parsePalettePreviewEntryList(value),
                  !entries.isEmpty else { continue }
            results[paletteId] = entries
        }
        return results
    }

    private func parsePalettePreviewEntryList(_ raw: Any) -> [PalettePreviewEntry]? {
        guard let array = raw as? [Any] else { return nil }
        var entries: [PalettePreviewEntry] = []
        for item in array {
            if let token = item as? String {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    entries.append(.placeholder(trimmed))
                }
            } else if let list = item as? [Any], list.count >= 4 {
                let index = decodeInt(list[0])
                let r = decodeInt(list[1])
                let g = decodeInt(list[2])
                let b = decodeInt(list[3])
                if let index, let r, let g, let b {
                    entries.append(.color(index: index, r: r, g: g, b: b))
                }
            }
        }
        return entries.isEmpty ? nil : entries
    }

    private func palettePreviewStops(from entries: [PalettePreviewEntry], fallbackGradient: LEDGradient) -> [GradientStop] {
        let fallbackColors = paletteFallbackHexColors(from: fallbackGradient)
        let hasExplicitIndices = entries.allSatisfy { entry in
            if case .color = entry { return true }
            return false
        }
        let total = max(entries.count, 1)
        var stops: [GradientStop] = []
        for (idx, entry) in entries.enumerated() {
            let position: Double
            if hasExplicitIndices, case let .color(index, _, _, _) = entry {
                position = max(0.0, min(1.0, Double(index) / 255.0))
            } else {
                position = total > 1 ? Double(idx) / Double(total - 1) : 0.0
            }
            let hex: String
            switch entry {
            case let .color(_, r, g, b):
                hex = rgbHex(r, g, b)
            case let .placeholder(token):
                let normalized = token.lowercased()
                if normalized == "c1" {
                    hex = fallbackColors[0]
                } else if normalized == "c2" {
                    hex = fallbackColors[1]
                } else if normalized == "c3" {
                    hex = fallbackColors[2]
                } else if normalized == "r" {
                    hex = fallbackColors[idx % fallbackColors.count]
                } else {
                    hex = fallbackColors[0]
                }
            }
            stops.append(GradientStop(position: position, hexColor: hex))
        }
        if stops.count == 1, let first = stops.first {
            stops.append(GradientStop(position: 1.0, hexColor: first.hexColor))
        }
        return stops.sorted { $0.position < $1.position }
    }

    private func paletteFallbackHexColors(from gradient: LEDGradient) -> [String] {
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        guard !sortedStops.isEmpty else {
            return ["FF0000", "00FF00", "0000FF"]
        }
        if sortedStops.count == 1 {
            let hex = sortedStops[0].hexColor
            return [hex, hex, hex]
        }
        let positions: [Double] = [0.0, 0.5, 1.0]
        return positions.map { GradientSampler.sampleColor(at: $0, stops: sortedStops).toHex() }
    }

    private func rgbHex(_ r: Int, _ g: Int, _ b: Int) -> String {
        let clamp: (Int) -> Int = { min(255, max(0, $0)) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    private func decodeInt(_ value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let doubleValue as Double:
            return Int(doubleValue)
        case let stringValue as String:
            return Int(stringValue)
        default:
            return nil
        }
    }
    
    func effectMetadata(for device: WLEDDevice) -> EffectMetadataBundle? {
        effectMetadataBundles[device.id]
    }

    func colorSafeEffects(for device: WLEDDevice) -> [EffectMetadata] {
        guard let bundle = effectMetadata(for: device) else {
            return filterMainUIEffects(DeviceControlViewModel.fallbackGradientFriendlyEffects)
        }
        let isMatrix = deviceIsMatrixById[device.id]
        let filtered = bundle.effects.filter { metadata in
            if metadata.isTwoDOnly, let isMatrix, !isMatrix {
                return false
            }
            if metadata.paletteIsFixed {
                // Palette-locked effects don't honor our gradient colors.
                return false
            }
            // Allow sound-reactive effects if they're in our approved list (e.g., Music Sync ID 139)
            if metadata.isSoundReactive {
                return DeviceControlViewModel.gradientFriendlyEffectIds.contains(metadata.id)
            }
            let supportsColors = metadata.colorSlotCount >= 1
            return supportsColors || DeviceControlViewModel.gradientFriendlyEffectIds.contains(metadata.id)
        }
        let list = filtered.isEmpty ? DeviceControlViewModel.fallbackGradientFriendlyEffects : filtered
        let filteredList = filterMainUIEffects(list)
        return filteredList.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func colorSafeEffectOptions(for device: WLEDDevice) -> [EffectMetadata] {
        let effects = colorSafeEffects(for: device)
        return effects.isEmpty ? DeviceControlViewModel.fallbackGradientFriendlyEffects : effects
    }

    func allEffectOptions(for device: WLEDDevice) -> [EffectMetadata] {
        guard let bundle = effectMetadata(for: device) else {
            return DeviceControlViewModel.fallbackGradientFriendlyEffects
        }
        let isMatrix = deviceIsMatrixById[device.id]
        let filtered = bundle.effects.filter { metadata in
            if metadata.isTwoDOnly, let isMatrix, !isMatrix {
                return false
            }
            return true
        }
        let list = filtered.isEmpty ? DeviceControlViewModel.fallbackGradientFriendlyEffects : filtered
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func normalizeEffectName(_ name: String) -> String {
        let lowered = name.lowercased()
        let filtered = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    private func filterMainUIEffects(_ effects: [EffectMetadata]) -> [EffectMetadata] {
        effects.filter { metadata in
            !DeviceControlViewModel.mainUIEffectExclusionsNormalized.contains(
                DeviceControlViewModel.normalizeEffectName(metadata.name)
            )
        }
    }
    
    func applyColorSafeEffect(
        _ effectId: Int,
        with gradient: LEDGradient,
        segmentId: Int = 0,
        device: WLEDDevice,
        userInitiated: Bool = true,
        preferPaletteIfAvailable: Bool = false,
        includeAllEffects: Bool = false,
        origin: SyncOrigin = .user
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
        let needsRealtimeRelease = isComingFromGradient || userInitiated
        
        if lastGradientBeforeEffect[device.id] == nil {
            let baseline = gradientStops(for: device.id) ?? [
                GradientStop(position: 0.0, hexColor: device.currentColor.toHex()),
                GradientStop(position: 1.0, hexColor: device.currentColor.toHex())
            ]
            lastGradientBeforeEffect[device.id] = baseline
        }
        let availableEffects = includeAllEffects ? allEffectOptions(for: device) : colorSafeEffectOptions(for: device)
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
                    await MainActor.run {
                        self.audioReactiveEnabledByDevice[device.id] = true
                    }
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
                        await MainActor.run {
                            self.audioReactiveEnabledByDevice[device.id] = true
                        }
                    } else {
                        #if DEBUG
                        os_log("[Effects] WARNING: Audio reactive mode may not be enabled. Check WLED web interface.", log: OSLog.effects, type: .error)
                        #endif
                        await MainActor.run {
                            self.audioReactiveEnabledByDevice[device.id] = false
                        }
                    }
                }
            } catch {
                #if DEBUG
                os_log("[Effects] Failed to enable/verify audio reactive mode: %{public}@", log: OSLog.effects, type: .error, error.localizedDescription)
                #endif
                // Continue anyway - the effect might still work if audio reactive is already enabled
                await MainActor.run {
                    self.audioReactiveEnabledByDevice[device.id] = false
                }
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
        let usePalette = preferPaletteIfAvailable && state.paletteId != nil
        if !usePalette {
            // Don't set palette when we're providing custom colors - let WLED use the colors directly
            state.paletteId = nil  // Omit palette when sending colors
        }
        state.isEnabled = true
        updateEffectGradient(gradient, for: device)
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        
        // CRITICAL: When switching effects, ensure we get the current device brightness
        // This prevents brightness from being reset during effect switch
        let currentDevice = await MainActor.run {
            self.devices.first(where: { $0.id == device.id }) ?? device
        }
        
        // CRITICAL: Apply effect with colors, brightness, and realtime release atomically
        // Include lor: 0 in the same call if needed to prevent flash
        let useFullStrip = true
        let colorsToSend = usePalette ? nil : colorArray
        await applyEffectState(state, to: currentDevice, segmentId: segmentId, colors: colorsToSend, turnOn: true, releaseRealtime: needsRealtimeRelease, fullStrip: useFullStrip)
        if let colorsToSend {
            logEffectApplication(effectId: effectId, device: device, colors: colorsToSend)
        }
        await propagateIfNeeded(
            source: device,
            payload: .effectState(effectId: effectId, gradient: gradient, segmentId: segmentId),
            origin: origin
        )
    }
    
    /// Public method to load effect metadata (triggers fetch if needed)
    func loadEffectMetadata(for device: WLEDDevice) async {
        await fetchEffectMetadataIfNeeded(for: device)
        await loadPalettePreviewsIfNeeded(for: device)
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

    func isAutoWhiteEnabled(for device: WLEDDevice) -> Bool {
        if let current = devices.first(where: { $0.id == device.id })?.autoWhiteMode {
            return current != .none
        }
        if let mode = device.autoWhiteMode {
            return mode != .none
        }
        return false
    }

    @MainActor
    private func refreshLEDPreferencesIfNeeded(for device: WLEDDevice, force: Bool = false) async {
        guard !isPlaceholderDevice(device) else { return }
        if ledPreferencesFetchInFlight.contains(device.id) {
            return
        }
        let now = Date()
        if !force, let lastFetch = ledPreferencesLastFetched[device.id],
           now.timeIntervalSince(lastFetch) < ledPreferencesRefreshInterval {
            return
        }
        ledPreferencesFetchInFlight.insert(device.id)
        defer {
            ledPreferencesFetchInFlight.remove(device.id)
        }

        do {
            let config = try await apiService.getLEDConfiguration(for: device)
            let stripType = LEDStripType.fromWLEDType(config.stripType)
            let colorOrder = LEDColorOrder(rawValue: config.colorOrder)
            let hasCctRange = (config.cctKelvinMin != nil && config.cctKelvinMax != nil)
            let usesCCT = (stripType?.usesCCT ?? false) || hasCctRange
            let usesWhite = (stripType?.usesWhiteChannel ?? false) || usesCCT

            if let stripType {
                ledStripTypeByDevice[device.id] = stripType
            } else {
                ledStripTypeByDevice.removeValue(forKey: device.id)
            }
            if let colorOrder {
                ledColorOrderByDevice[device.id] = colorOrder
            } else {
                ledColorOrderByDevice.removeValue(forKey: device.id)
            }

            let segmentCount = max(1, getSegmentCount(for: device))
            if usesWhite || usesCCT {
                var capabilities = deviceCapabilities[device.id] ?? WLEDCapabilities(deviceId: device.id)
                let template = SegmentCapabilities(rgb: true, white: usesWhite, cct: usesCCT)
                var updated: [Int: SegmentCapabilities] = [:]
                for idx in 0..<segmentCount {
                    updated[idx] = template
                }
                capabilities.segments = updated
                capabilities.lastUpdated = Date()
                deviceCapabilities[device.id] = capabilities
            }
            let mode = AutoWhiteMode(rawValue: config.autoWhiteMode) ?? .none
            if let minKelvin = config.cctKelvinMin,
               let maxKelvin = config.cctKelvinMax,
               minKelvin < maxKelvin {
                cctKelvinRanges[device.id] = minKelvin...maxKelvin
            } else {
                cctKelvinRanges.removeValue(forKey: device.id)
            }
            ledPreferencesLastFetched[device.id] = now
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

    func refreshLEDPreferences(for device: WLEDDevice) async {
        await refreshLEDPreferencesIfNeeded(for: device, force: true)
    }

    private func fallbackSeglc(from leds: LedInfo, state: WLEDState) -> [Int]? {
        let segmentFlags = state.segments.compactMap { $0.lc }
        if !segmentFlags.isEmpty {
            return segmentFlags
        }
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
        await applyEffectState(state, to: device, segmentId: segmentId, colors: nil, turnOn: true, releaseRealtime: true, fullStrip: useFullStrip)
    }
    
    /// Disable effects for a device/segment (set fx: 0)
    /// This allows CCT and solid colors to work properly
    /// Note: Does NOT automatically restore gradient - caller should handle that separately if needed
    func disableEffect(for device: WLEDDevice, segmentId: Int = 0, origin: SyncOrigin = .user) async {
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
            origin: .propagated,
            preferSegmented: true
        )
        
        lastGradientBeforeEffect.removeValue(forKey: device.id)
        
        #if DEBUG
        os_log("[Effects] Disabled effect on %{public}@ and restored main gradient", device.name)
        #endif
        await propagateIfNeeded(source: device, payload: .effectDisable(segmentId: segmentId), origin: origin)
    }
    
    func updateEffectSpeed(for device: WLEDDevice, segmentId: Int = 0, speed: Int, origin: SyncOrigin = .user) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.speed = max(0, min(255, speed))
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, releaseRealtime: true, fullStrip: useFullStrip)
        await propagateIfNeeded(
            source: device,
            payload: .effectParameter(.speed(segmentId: segmentId, value: state.speed)),
            origin: origin
        )
    }
    
    func updateEffectIntensity(for device: WLEDDevice, segmentId: Int = 0, intensity: Int, origin: SyncOrigin = .user) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.intensity = max(0, min(255, intensity))
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, releaseRealtime: true, fullStrip: useFullStrip)
        await propagateIfNeeded(
            source: device,
            payload: .effectParameter(.intensity(segmentId: segmentId, value: state.intensity)),
            origin: origin
        )
    }

    func updateEffectCustomParameter(
        for device: WLEDDevice,
        segmentId: Int = 0,
        index: Int,
        value: Int,
        origin: SyncOrigin = .user
    ) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        let clamped = max(0, min(255, value))
        switch index {
        case 2:
            state.custom1 = clamped
        case 3:
            state.custom2 = clamped
        case 4:
            state.custom3 = clamped
        default:
            break
        }
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, releaseRealtime: true, fullStrip: useFullStrip)
        await propagateIfNeeded(
            source: device,
            payload: .effectParameter(.custom(segmentId: segmentId, index: index, value: clamped)),
            origin: origin
        )
    }

    func segmentBrightnessValue(for device: WLEDDevice, segmentId: Int = 0) -> Int {
        if let segment = device.state?.segments.first(where: { ($0.id ?? 0) == segmentId }) {
            return segment.bri ?? 255
        }
        if let first = device.state?.segments.first {
            return first.bri ?? 255
        }
        return 255
    }

    func updateSegmentBrightness(for device: WLEDDevice, segmentId: Int = 0, brightness: Int, origin: SyncOrigin = .user) async {
        let clamped = max(0, min(255, brightness))
        markUserInteraction(device.id)
        let segUpdate = SegmentUpdate(id: segmentId, bri: clamped)
        let stateUpdate = WLEDStateUpdate(seg: [segUpdate])

        let wsConnected = webSocketManager.isDeviceConnected(device.id)
        if wsConnected {
            webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            await MainActor.run {
                if let index = devices.firstIndex(where: { $0.id == device.id }),
                   let state = devices[index].state {
                    let updatedSegments = state.segments.enumerated().map { idx, segment in
                        let segId = segment.id ?? idx
                        return segId == segmentId
                            ? segmentWithBrightness(segment, brightness: clamped)
                            : segment
                    }
                    devices[index].state = WLEDState(
                        brightness: state.brightness,
                        isOn: state.isOn,
                        segments: updatedSegments,
                        transitionDeciseconds: state.transitionDeciseconds,
                        presetId: state.presetId,
                        playlistId: state.playlistId,
                        mainSegment: state.mainSegment
                    )
                    devices[index].isOnline = true
                }
                clearError()
            }
            var updatedDevice = device
            updatedDevice.isOnline = true
            updatedDevice.lastSeen = Date()
            await coreDataManager.saveDevice(updatedDevice)
            await propagateIfNeeded(
                source: device,
                payload: .effectParameter(.segmentBrightness(segmentId: segmentId, value: clamped)),
                origin: origin
            )
            return
        }

        do {
            _ = try await apiService.updateState(for: device, state: stateUpdate)
            if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
                webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
            }
            await MainActor.run {
                if let index = devices.firstIndex(where: { $0.id == device.id }),
                   let state = devices[index].state {
                    let updatedSegments = state.segments.enumerated().map { idx, segment in
                        let segId = segment.id ?? idx
                        return segId == segmentId
                            ? segmentWithBrightness(segment, brightness: clamped)
                            : segment
                    }
                    devices[index].state = WLEDState(
                        brightness: state.brightness,
                        isOn: state.isOn,
                        segments: updatedSegments,
                        transitionDeciseconds: state.transitionDeciseconds,
                        presetId: state.presetId,
                        playlistId: state.playlistId,
                        mainSegment: state.mainSegment
                    )
                    devices[index].isOnline = true
                }
                clearError()
            }
            var updatedDevice = device
            updatedDevice.isOnline = true
            updatedDevice.lastSeen = Date()
            await coreDataManager.saveDevice(updatedDevice)
            await propagateIfNeeded(
                source: device,
                payload: .effectParameter(.segmentBrightness(segmentId: segmentId, value: clamped)),
                origin: origin
            )
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            await MainActor.run {
                self.presentError(mappedError)
            }
        }
    }

    func clearEffectPalette(for device: WLEDDevice, segmentId: Int = 0, origin: SyncOrigin = .user) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.paletteId = nil
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, colors: nil, turnOn: nil, releaseRealtime: true, fullStrip: useFullStrip)
        await propagateIfNeeded(
            source: device,
            payload: .effectParameter(.palette(segmentId: segmentId, paletteId: nil)),
            origin: origin
        )
    }

    func refreshAudioReactiveStatus(for device: WLEDDevice) async {
        let enabled = (try? await apiService.isAudioReactiveEnabled(for: device)) ?? false
        await MainActor.run {
            self.audioReactiveEnabledByDevice[device.id] = enabled
        }
    }

    func audioReactiveEnabled(for device: WLEDDevice) -> Bool? {
        audioReactiveEnabledByDevice[device.id]
    }
    
    func updateEffectPalette(for device: WLEDDevice, segmentId: Int = 0, paletteId: Int, origin: SyncOrigin = .user) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        state.paletteId = max(0, paletteId)  // Only set palette when explicitly requested (no colors)
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, colors: nil, turnOn: nil, releaseRealtime: true, fullStrip: useFullStrip)
        await propagateIfNeeded(
            source: device,
            payload: .effectParameter(.palette(segmentId: segmentId, paletteId: state.paletteId)),
            origin: origin
        )
    }

    func updateEffectOption(for device: WLEDDevice, segmentId: Int = 0, optionIndex: Int, value: Bool, origin: SyncOrigin = .user) async {
        await cancelActiveTransitionIfNeeded(for: device)
        markUserInteraction(device.id)
        var state = currentEffectState(for: device, segmentId: segmentId)
        switch optionIndex {
        case 1:
            state.option1 = value
        case 2:
            state.option2 = value
        case 3:
            state.option3 = value
        default:
            return
        }
        updateEffectStateCache(state, deviceId: device.id, segmentId: segmentId)
        let useFullStrip = true
        await applyEffectState(state, to: device, segmentId: segmentId, colors: nil, turnOn: nil, releaseRealtime: true, fullStrip: useFullStrip)
        await propagateIfNeeded(
            source: device,
            payload: .effectParameter(.option(segmentId: segmentId, optionIndex: optionIndex, value: value)),
            origin: origin
        )
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
                let useAppSegments = shouldUseAppManagedSegments(for: device.id)
                let manualSegments = usesManualSegmentation(for: device.id)
                var updates: [SegmentUpdate] = []
                if useAppSegments {
                    let count = segmentCount(for: currentDevice, ledCount: totalLEDs)
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
                                c1: state.custom1,
                                c2: state.custom2,
                                c3: state.custom3,
                                o1: state.option1,
                                o2: state.option2,
                                o3: state.option3,
                                frz: false
                            )
                        )
                    }
                } else if manualSegments, let segments = currentDevice.state?.segments, !segments.isEmpty {
                    for (index, segment) in segments.enumerated() {
                        let resolvedId = segment.id ?? index
                        updates.append(
                            SegmentUpdate(
                                id: resolvedId,
                                on: turnOn,
                                col: colors,
                                cct: nil,
                                fx: state.effectId,
                                sx: state.speed,
                                ix: state.intensity,
                                pal: effectivePalette,
                                c1: state.custom1,
                                c2: state.custom2,
                                c3: state.custom3,
                                o1: state.option1,
                                o2: state.option2,
                                o3: state.option3,
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
                            c1: state.custom1,
                            c2: state.custom2,
                            c3: state.custom3,
                            o1: state.option1,
                            o2: state.option2,
                            o3: state.option3,
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
                    knownIds = Set(0..<segmentCount(for: currentDevice, ledCount: totalLEDs))
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
                    custom1: state.custom1,
                    custom2: state.custom2,
                    custom3: state.custom3,
                    option1: state.option1,
                    option2: state.option2,
                    option3: state.option3,
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
                        custom1: seg.c1 ?? state.custom1,
                        custom2: seg.c2 ?? state.custom2,
                        custom3: seg.c3 ?? state.custom3,
                        option1: seg.o1 ?? state.option1,
                        option2: seg.o2 ?? state.option2,
                        option3: seg.o3 ?? state.option3,
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
        let isUnderControl = isUnderUserControl(deviceId)
        let gradientJustApplied: Bool
        if let gradientTime = gradientApplicationTimes[deviceId] {
            gradientJustApplied = Date().timeIntervalSince(gradientTime) < gradientProtectionWindow
        } else {
            gradientJustApplied = false
        }
        let mainSegment = primarySegment(from: state)
        let hasActiveEffect = ((mainSegment?.fx) ?? 0) != 0
        if !isUnderControl && !gradientJustApplied && !hasActiveEffect,
           latestGradientStops[deviceId] != nil || loadPersistedGradient(for: deviceId) != nil {
            maybeHydrateGradientFromLiveState(
                state,
                for: deviceId,
                reason: "state.update"
            )
        }

        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            var updatedDevice = devices[index]
            updatedDevice.brightness = state.brightness
            updatedDevice.isOn = state.isOn
            updatedDevice.state = state
            updatedDevice.lastSeen = Date()
            if let segment = primarySegment(from: state) {
                updatedDevice.temperature = segment.cctNormalized
                if let preferred = preferredDisplayColor(for: deviceId) {
                    updatedDevice.currentColor = preferred
                } else if let color = derivedColor(from: segment) {
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
    
    private func stateUpdate(from state: WLEDState, device: WLEDDevice) -> WLEDStateUpdate {
        let segments = state.segments.map { segment in
            let segmentId = segment.id ?? 0
            let colors = segment.colors?.map { rgb in
                guard rgb.count >= 3 else { return rgb }
                if supportsWhite(for: device, segmentId: segmentId), rgb.count == 3 {
                    return rgb + [0]
                }
                return rgb
            }
            return SegmentUpdate(
                id: segment.id,
                start: segment.start,
                stop: segment.stop,
                len: segment.len,
                grp: segment.grp,
                spc: segment.spc,
                ofs: segment.ofs,
                on: segment.on,
                bri: segment.bri,
                col: colors,
                cct: segment.cct,
                fx: segment.fx,
                sx: segment.sx,
                ix: segment.ix,
                pal: segment.pal,
                c1: segment.c1,
                c2: segment.c2,
                c3: segment.c3,
                sel: segment.sel,
                rev: segment.rev,
                mi: segment.mi,
                cln: segment.cln,
                o1: segment.o1,
                o2: segment.o2,
                o3: segment.o3,
                si: segment.si,
                m12: segment.m12,
                setId: segment.setId,
                name: segment.name,
                frz: segment.frz
            )
        }
        return WLEDStateUpdate(
            on: state.isOn,
            bri: state.brightness,
            seg: segments,
            mainSegment: state.mainSegment
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

    func setActiveDevice(_ device: WLEDDevice?) {
        let resolvedDevice: WLEDDevice? = {
            guard let device else { return nil }
            if let exact = devices.first(where: { $0.id == device.id }) {
                return exact
            }
            if let canonical = devices.first(where: { $0.ipAddress == device.ipAddress && !isPlaceholderDevice($0) }) {
                return canonical
            }
            return devices.first(where: { $0.ipAddress == device.ipAddress }) ?? device
        }()
        let newId = resolvedDevice?.id
        guard newId != activeDeviceId else { return }
        activeDeviceId = newId
        guard isRealTimeEnabled,
              let target = resolvedDevice,
              !isPlaceholderDevice(target) else { return }
        connectWebSocketIfNeeded(for: target)
    }

    func clearActiveDeviceIfNeeded(_ deviceId: String) {
        guard activeDeviceId == deviceId else { return }
        setActiveDevice(nil)
    }
    
    func connectRealTimeForDevice(_ device: WLEDDevice) {
        // Skip off-subnet devices
        guard isIPInCurrentSubnets(device.ipAddress) else { return }
        setActiveDevice(device)
        connectWebSocketIfNeeded(for: device)
    }
    
    func disconnectRealTimeForDevice(_ device: WLEDDevice) {
        clearActiveDeviceIfNeeded(device.id)
        webSocketManager.disconnect(from: device.id)
    }
    
    func refreshRealTimeConnections() {
        if isRealTimeEnabled {
            connectWebSocketsForAllDevices()
        } else {
            disconnectAllWebSockets()
        }
    }

    func pauseRealTimeConnectionsIfNeeded() {
        guard isRealTimeEnabled else { return }
        hasHandledForegroundActive = false
        connectionMonitor.pauseBackgroundOperations()
        webSocketManager.suspendAllConnections()
    }

    func resumeRealTimeConnectionsIfNeeded() {
        guard isRealTimeEnabled else { return }
        connectionMonitor.resumeBackgroundOperations()
        webSocketManager.resumeConnections()
        connectWebSocketsForAllDevices()
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
        if isBenignCancelledNoise(error) {
            #if DEBUG
            print("⚠️ Suppressing benign cancelled error banner: \(error.message)")
            #endif
            return
        }
        if currentError == error { return }
        currentError = error
        errorMessage = error.message
    }

    private func isBenignCancelledNoise(_ error: WLEDError) -> Bool {
        switch error {
        case .apiError(let message):
            let lowered = message.lowercased()
            return lowered.contains("cancelled") || lowered.contains("canceled")
        default:
            return false
        }
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
    
    func applyGradientStopsAcrossStrip(_ device: WLEDDevice, stops: [GradientStop], ledCount: Int, stopTemperatures: [UUID: Double]? = nil, stopWhiteLevels: [UUID: Double]? = nil, disableActiveEffect: Bool = false, segmentId: Int = 0, interpolation: GradientInterpolation = .linear, brightness: Int? = nil, on: Bool? = nil, transitionDurationSeconds: Double? = nil, forceNoPerCallTransition: Bool = false, releaseRealtimeOverride: Bool = true, userInitiated: Bool = true, origin: SyncOrigin = .user, preferSegmented: Bool = false, forceSegmentedOnly: Bool = false) async {
        // CRITICAL: Auto-cancel any active transitions/runs on manual input
        if userInitiated {
            if hasKnownActiveRun(for: device.id) {
                await cancelActiveRun(for: device, force: true, endReason: .cancelledByManualInput)
            }
        }
        
        // CRITICAL: Mark user interaction only for user-driven updates
        if userInitiated {
            markUserInteraction(device.id)
        }
        
        let sortedStops = stops.sorted { $0.position < $1.position }
        let propagationPayload = ColorsSyncPayload.gradient(
            stops: sortedStops,
            interpolation: interpolation,
            segmentId: segmentId,
            brightness: brightness,
            on: on
        )
        latestGradientStops[device.id] = sortedStops
        persistLatestGradient(sortedStops, for: device.id)
        let allowPerLed = forceSegmentedOnly ? false : allowPerLedFallback(for: device)
        let preferSegments = preferSegmented || forceSegmentedOnly
        
        // OPTIMIZATION: Solid color detection (single stop OR all stops have same color)
        // Use segment col field for solid colors (more efficient than per-LED upload)
        // This matches WLED's recommended approach for solid colors
        let firstColorHex = sortedStops.first?.hexColor
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == firstColorHex }
        let appManagedSegments = shouldUseAppManagedSegments(for: device.id)
        let manualSegments = usesManualSegmentation(for: device.id)
        let willUseSegmented = isSolidColor
            ? (preferSegments || appManagedSegments || manualSegments)
            : (preferSegments || transitionDurationSeconds != nil || !allowPerLed || appManagedSegments || manualSegments)

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
            await propagateIfNeeded(source: device, payload: propagationPayload, origin: origin)
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
            await propagateIfNeeded(source: device, payload: propagationPayload, origin: origin)
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
            let allowManualWhite = supportsWhiteValue
                && UserDefaults.standard.bool(forKey: "advancedUIEnabled")
            let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
            let supportsCCTDevice = supportsCCTOutput(for: device, segmentId: segmentId)
            
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
                    seg: [clearSegment]
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
                } else if supportsWhiteValue {
                    colorArray.append(0)
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
            let transitionDeciseconds = forceNoPerCallTransition ? nil : clampedTransitionDeciseconds(for: transitionDurationSeconds)
            let stateUpdate = WLEDStateUpdate(
                on: on,  // CRITICAL: Include power state if provided (for power-on operations)
                bri: brightness,  // Set brightness if provided
                seg: [segment],
                transitionDeciseconds: transitionDeciseconds  // Include transition time for native WLED transition
            )
            
            do {
                _ = try await apiService.updateState(for: device, state: stateUpdate)
                let writeSucceededAt = Date()
                
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
                        self.devices[index].isOnline = true
                        self.devices[index].lastSeen = writeSucceededAt
                    }
                    self.noteControlWriteSuccess(deviceId: device.id)
                }
                
                #if DEBUG
                print("✅ [Gradient] Applied single-stop solid color via segment col field (optimized)")
                #endif
                await propagateIfNeeded(source: device, payload: propagationPayload, origin: origin)
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
        let resolvedLedCount = (shouldUseAppManagedSegments(for: device.id) || usesManualSegmentation(for: device.id))
            ? totalLEDCount(for: device)
            : max(1, ledCount)
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
                    if supportsCCTOutput(for: device, segmentId: segmentId) {
                        intent.cct = cct
                    }
                }
            }
        }
        
        await colorPipeline.apply(intent, to: device)
        let writeSucceededAt = Date()
        
        // Mark gradient application time to prevent WebSocket overwrites
        await MainActor.run {
            self.gradientApplicationTimes[device.id] = Date()
            
            // Optimistically update the device's current color to the first stop
            if let index = self.devices.firstIndex(where: { $0.id == device.id }),
               let firstStop = sortedStops.first {
                self.devices[index].currentColor = Color(hex: firstStop.hexColor)
                self.devices[index].temperature = nil
                self.devices[index].isOnline = true
                self.devices[index].lastSeen = writeSucceededAt
            }
            self.noteControlWriteSuccess(deviceId: device.id)
        }
        await propagateIfNeeded(source: device, payload: propagationPayload, origin: origin)
    }

    private func defaultAutoSegmentCount(maxUsableSegments: Int) -> Int {
        guard maxUsableSegments > 0 else { return 1 }
        let floor = min(defaultSegmentCountFloor, maxUsableSegments)
        let qualityTarget = Int((Double(maxUsableSegments) * defaultSegmentQualityRatio).rounded())
        let recommended = max(floor, qualityTarget)
        return min(maxUsableSegments, max(1, recommended))
    }

    private func segmentCount(for device: WLEDDevice, ledCount: Int) -> Int {
        guard ledCount > 0 else { return 0 }
        let maxUsable = maximumUsableSegmentCount(for: device)
        let preferred = preferredActiveSegmentCount(for: device)
        return min(max(1, preferred), maxUsable)
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

    private func maybeAutoRestoreSegmentsAfterReboot(device: WLEDDevice, response: WLEDResponse) async {
        guard !usesManualSegmentation(for: device.id) else { return }
        guard !segmentAutoRestoreInFlight.contains(device.id) else { return }
        if let lastAttempt = segmentAutoRestoreLastAttemptAt[device.id],
           Date().timeIntervalSince(lastAttempt) < segmentAutoRestoreCooldownSeconds {
            return
        }

        let storedPreferred = UserDefaults.standard.integer(forKey: activeSegmentCountKey(for: device.id))
        guard storedPreferred > 1 else { return }

        let activeCount = max(1, response.state.segments.count)
        guard activeCount <= 1 else { return }

        let ledCount = max(1, response.info.leds.count)
        let reportedMax = max(1, response.info.leds.maxseg ?? deviceMaxSegmentCapacity(for: device))
        let maxUsable = max(1, min(ledCount, reportedMax))
        let target = min(maxUsable, storedPreferred)
        guard target > activeCount else { return }

        segmentAutoRestoreInFlight.insert(device.id)
        segmentAutoRestoreLastAttemptAt[device.id] = Date()
        #if DEBUG
        print("segments.auto_restore.begin device=\(device.id) active=\(activeCount) target=\(target) reportedMax=\(reportedMax)")
        #endif

        let liveDevice = await MainActor.run { () -> WLEDDevice in
            devices.first(where: { $0.id == device.id }) ?? device
        }
        let success = await applyActiveSegmentCount(target, for: liveDevice)
        #if DEBUG
        print("segments.auto_restore.\(success ? "success" : "failed") device=\(device.id) target=\(target)")
        #endif
        await MainActor.run {
            _ = segmentAutoRestoreInFlight.remove(device.id)
        }
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
        let denom = Double(max(1, count - 1))
        return (0..<count).map { idx in
            let t = count == 1 ? 0.5 : (Double(idx) / denom)
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
        let denom = Double(max(1, count - 1))
        return (0..<count).map { idx in
            let t = count == 1 ? 0.5 : (Double(idx) / denom)
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
        let denom = Double(max(1, count - 1))
        return (0..<count).map { idx in
            let t = count == 1 ? 0.5 : (Double(idx) / denom)
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
        if supportsCCTOutput(for: device, segmentId: 0) == false {
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

    private func segmentWithBrightness(_ segment: Segment, brightness: Int) -> Segment {
        Segment(
            id: segment.id,
            start: segment.start,
            stop: segment.stop,
            len: segment.len,
            grp: segment.grp,
            spc: segment.spc,
            ofs: segment.ofs,
            on: segment.on,
            bri: brightness,
            colors: segment.colors,
            cct: segment.cct,
            lc: segment.lc,
            fx: segment.fx,
            sx: segment.sx,
            ix: segment.ix,
            pal: segment.pal,
            c1: segment.c1,
            c2: segment.c2,
            c3: segment.c3,
            sel: segment.sel,
            rev: segment.rev,
            mi: segment.mi,
            cln: segment.cln,
            o1: segment.o1,
            o2: segment.o2,
            o3: segment.o3,
            si: segment.si,
            m12: segment.m12,
            setId: segment.setId,
            name: segment.name,
            frz: segment.frz
        )
    }

    private func effectGradientStops(from segment: Segment) -> [GradientStop]? {
        guard let colors = segment.colors, !colors.isEmpty else { return nil }
        let rgbColors: [Color] = colors.compactMap { raw in
            guard raw.count >= 3 else { return nil }
            return Color.color(fromRGBArray: raw)
        }
        guard !rgbColors.isEmpty else { return nil }
        let limited = Array(rgbColors.prefix(3))
        let positions: [Double]
        switch limited.count {
        case 1:
            positions = [0.0, 1.0]
            return [
                GradientStop(position: positions[0], hexColor: limited[0].toHex()),
                GradientStop(position: positions[1], hexColor: limited[0].toHex())
            ]
        case 2:
            positions = [0.0, 1.0]
        default:
            positions = [0.0, 0.5, 1.0]
        }
        return zip(positions, limited).map { position, color in
            GradientStop(position: position, hexColor: color.toHex())
        }
    }

    private typealias SegmentColorSample = (start: Int, stop: Int?, hex: String)

    private func gradientStopsFromStateSegments(_ state: WLEDState, deviceId: String? = nil) -> [GradientStop]? {
        let segmentColors: [SegmentColorSample] = state.segments.compactMap { segment in
            guard let colors = segment.colors,
                  let first = colors.first,
                  first.count >= 3 else {
                return nil
            }
            let colorHex = Color.color(fromRGBArray: first).toHex()
            return (start: max(0, segment.start ?? 0), stop: segment.stop, hex: colorHex)
        }
        guard !segmentColors.isEmpty else { return nil }

        if segmentColors.count == 1, let only = segmentColors.first {
            return [
                GradientStop(position: 0.0, hexColor: only.hex),
                GradientStop(position: 1.0, hexColor: only.hex)
            ]
        }

        var sorted = segmentColors.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return (lhs.stop ?? 0) < (rhs.stop ?? 0)
            }
            return lhs.start < rhs.start
        }
        if let deviceId,
           let preferredLimit = preferredHydrationSegmentLimit(for: deviceId),
           sorted.count > preferredLimit {
            // Ignore stale extra segments beyond app-managed active segment count.
            #if DEBUG
            print("gradient.hydrate.limit device=\(deviceId) from=\(sorted.count) to=\(preferredLimit)")
            #endif
            sorted = Array(sorted.prefix(preferredLimit))
        }
        sorted = suppressIsolatedSegmentColorNoise(sorted)
        guard !sorted.isEmpty else { return nil }

        let maxStop = sorted.compactMap(\.stop).max()
            ?? state.segments.compactMap(\.stop).max()
            ?? ((sorted.last?.start ?? 0) + 1)
        let denominator = max(maxStop - 1, 1)

        var stops: [GradientStop] = []
        for (index, item) in sorted.enumerated() {
            let fallbackPosition = sorted.count > 1 ? Double(index) / Double(sorted.count - 1) : 0.0
            let clamped = min(1.0, max(0.0, Double(item.start) / Double(denominator)))
            let position = clamped.isFinite ? clamped : fallbackPosition
            if let last = stops.last, abs(last.position - position) < 0.0001 {
                stops.removeLast()
            }
            stops.append(GradientStop(position: position, hexColor: item.hex))
        }

        guard !stops.isEmpty else { return nil }
        if let first = stops.first, first.position > 0.0 {
            stops.insert(GradientStop(position: 0.0, hexColor: first.hexColor), at: 0)
        }
        if let last = stops.last, last.position < 1.0 {
            stops.append(GradientStop(position: 1.0, hexColor: last.hexColor))
        }
        if stops.count == 1, let only = stops.first {
            return [
                GradientStop(position: 0.0, hexColor: only.hexColor),
                GradientStop(position: 1.0, hexColor: only.hexColor)
            ]
        }
        let advancedUI = UserDefaults.standard.bool(forKey: "advancedUIEnabled")
        let maxDisplayStops = advancedUI ? 10 : 6
        return compactGradientStopsForDisplay(stops, maxStops: maxDisplayStops)
    }

    private func preferredHydrationSegmentLimit(for deviceId: String) -> Int? {
        let stored = UserDefaults.standard.integer(forKey: activeSegmentCountKey(for: deviceId))
        guard stored > 0 else { return nil }
        return max(1, stored)
    }

    private func suppressIsolatedSegmentColorNoise(_ samples: [SegmentColorSample]) -> [SegmentColorSample] {
        // Preserve small/manual layouts exactly; denoise only longer app-generated strips.
        guard samples.count >= 5 else { return samples }

        var keep = Array(repeating: true, count: samples.count)
        // Remove short spike runs (1-3 segments) when bounded by similar neighbors.
        // This handles random cluster artifacts around the middle of a smooth gradient.
        let maxSpikeRun = min(3, samples.count - 2)
        if maxSpikeRun >= 1 {
            for run in 1...maxSpikeRun {
                var start = 1
                while start + run < samples.count {
                    let left = samples[start - 1]
                    let right = samples[start + run]
                    let neighborsAgree = areColorsNearEqual(left.hex, right.hex, threshold: 16.0)
                    if neighborsAgree {
                        let runIndices = start..<(start + run)
                        let strongSpike = runIndices.allSatisfy { idx in
                            colorDistance(samples[idx].hex, left.hex) >= 34.0
                                && colorDistance(samples[idx].hex, right.hex) >= 34.0
                        }
                        if strongSpike {
                            for idx in runIndices {
                                keep[idx] = false
                            }
                            start += run
                            continue
                        }
                    }
                    start += 1
                }
            }
        }

        for index in 1..<(samples.count - 1) {
            if !keep[index] { continue }
            let prev = samples[index - 1]
            let current = samples[index]
            let next = samples[index + 1]

            let neighborsAgree = areColorsNearEqual(prev.hex, next.hex, threshold: 14.0)
            let currentDiffersStrongly = colorDistance(current.hex, prev.hex) >= 36.0
                && colorDistance(current.hex, next.hex) >= 36.0
            if neighborsAgree && currentDiffersStrongly {
                keep[index] = false
            }
        }

        var filtered = samples.enumerated().compactMap { idx, sample in
            keep[idx] ? sample : nil
        }

        // Endpoint cleanup for stale edge colors after segment-count/layout changes.
        if filtered.count >= 4 {
            let first = filtered[0]
            let second = filtered[1]
            let third = filtered[2]
            if areColorsNearEqual(second.hex, third.hex, threshold: 14.0),
               colorDistance(first.hex, second.hex) >= 42.0 {
                filtered[0] = (start: first.start, stop: first.stop, hex: second.hex)
            }

            let lastIndex = filtered.count - 1
            let last = filtered[lastIndex]
            let prev = filtered[lastIndex - 1]
            let prev2 = filtered[lastIndex - 2]
            if areColorsNearEqual(prev.hex, prev2.hex, threshold: 14.0),
               colorDistance(last.hex, prev.hex) >= 42.0 {
                filtered[lastIndex] = (start: last.start, stop: last.stop, hex: prev.hex)
            }
        }

        #if DEBUG
        if filtered.count != samples.count {
            print("gradient.hydrate.denoise removed=\(samples.count - filtered.count) kept=\(filtered.count)")
        }
        #endif

        return filtered
    }

    private func compactGradientStopsForDisplay(_ inputStops: [GradientStop], maxStops: Int) -> [GradientStop] {
        let sorted = inputStops.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return [] }

        if isEffectivelySingleColor(sorted) {
            return [GradientStop(position: 0.0, hexColor: sorted[0].hexColor)]
        }
        guard sorted.count > 2 else { return sorted }

        // Keep anchors and add stops only where there is a true color discontinuity.
        let deltas: [Double] = zip(sorted, sorted.dropFirst()).map { lhs, rhs in
            colorDistance(lhs.hexColor, rhs.hexColor)
        }
        let medianDelta = median(deltas.filter { $0 > 0.0 }) ?? 0.0
        // Adaptive threshold: ignores smooth ramps, captures sudden jumps.
        let shiftThreshold = max(28.0, medianDelta * 2.35)

        var keepIndices: Set<Int> = [0, sorted.count - 1]
        for idx in 1..<sorted.count {
            let delta = deltas[idx - 1]
            if delta >= shiftThreshold {
                keepIndices.insert(idx - 1)
                keepIndices.insert(idx)
            }
        }

        var kept = keepIndices.sorted().map { sorted[$0] }
        kept = collapseAdjacentNearDuplicateStops(kept)

        // If nothing was detected as a shift, keep only left/right anchors.
        if kept.count <= 2 {
            let first = sorted.first!
            let last = sorted.last!
            if areColorsNearEqual(first.hexColor, last.hexColor) {
                return [GradientStop(position: 0.0, hexColor: first.hexColor)]
            }
            return [
                GradientStop(position: 0.0, hexColor: first.hexColor),
                GradientStop(position: 1.0, hexColor: last.hexColor)
            ]
        }

        if kept.count > maxStops {
            // Keep strongest discontinuities first (endpoints always retained).
            let edgeScores: [(idx: Int, score: Double)] = kept.enumerated().compactMap { idx, stop in
                if idx == 0 || idx == kept.count - 1 { return nil }
                let prev = kept[idx - 1]
                let next = kept[idx + 1]
                let score = max(
                    colorDistance(prev.hexColor, stop.hexColor),
                    colorDistance(stop.hexColor, next.hexColor)
                )
                return (idx, score)
            }
            let slots = max(0, maxStops - 2)
            let chosenInteriorIndices = Set(edgeScores.sorted { $0.score > $1.score }.prefix(slots).map(\.idx))
            kept = kept.enumerated().compactMap { idx, stop in
                if idx == 0 || idx == kept.count - 1 || chosenInteriorIndices.contains(idx) {
                    return stop
                }
                return nil
            }.sorted { $0.position < $1.position }
        }

        if let first = kept.first, first.position > 0 {
            kept.insert(GradientStop(position: 0.0, hexColor: first.hexColor), at: 0)
        }
        if let last = kept.last, last.position < 1 {
            kept.append(GradientStop(position: 1.0, hexColor: last.hexColor))
        }
        return kept.sorted { $0.position < $1.position }
    }

    private func colorDistance(_ lhsHex: String, _ rhsHex: String) -> Double {
        let lhs = Color(hex: lhsHex).toRGBArray()
        let rhs = Color(hex: rhsHex).toRGBArray()
        guard lhs.count >= 3, rhs.count >= 3 else { return 0.0 }
        let dr = Double(lhs[0] - rhs[0])
        let dg = Double(lhs[1] - rhs[1])
        let db = Double(lhs[2] - rhs[2])
        return sqrt((dr * dr) + (dg * dg) + (db * db))
    }

    private func areColorsNearEqual(_ lhsHex: String, _ rhsHex: String, threshold: Double = 8.0) -> Bool {
        colorDistance(lhsHex, rhsHex) <= threshold
    }

    private func isEffectivelySingleColor(_ stops: [GradientStop], threshold: Double = 8.0) -> Bool {
        guard let first = stops.first else { return true }
        return stops.allSatisfy { colorDistance(first.hexColor, $0.hexColor) <= threshold }
    }

    private func collapseAdjacentNearDuplicateStops(_ stops: [GradientStop], threshold: Double = 8.0) -> [GradientStop] {
        guard !stops.isEmpty else { return [] }
        var result: [GradientStop] = [stops[0]]
        for stop in stops.dropFirst() {
            if let last = result.last, colorDistance(last.hexColor, stop.hexColor) <= threshold {
                continue
            }
            result.append(stop)
        }
        return result
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func shouldAdoptEffectGradientAsMain(deviceId: String, effectStops: [GradientStop]) -> Bool {
        if let existing = latestGradientStops[deviceId], !existing.isEmpty {
            let unique = Set(existing.map { $0.hexColor.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased() })
            if unique.count == 1, let only = unique.first, only == "000000" {
                return true
            }
            return false
        }
        return true
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
        let manualSegments = usesManualSegmentation(for: device.id)
        if !manualSegments {
            appManagedSegmentDevices.insert(device.id)
        }

        let totalLEDs = totalLEDCount(for: device)
        guard totalLEDs > 0 else { return }
        await waitForPresetWriteIfNeeded(deviceId: device.id)
        let manualSegmentsOrdered: [Segment] = {
            guard manualSegments else { return [] }
            let segments = device.state?.segments ?? []
            guard !segments.isEmpty else { return [] }
            return segments.sorted { (lhs, rhs) in
                (lhs.start ?? 0) < (rhs.start ?? 0)
            }
        }()
        let manualSegmentIds: [Int] = {
            guard manualSegments else { return [] }
            guard !manualSegmentsOrdered.isEmpty else { return [] }
            return manualSegmentsOrdered.enumerated().map { index, segment in
                segment.id ?? index
            }
        }()
        let count: Int
        if manualSegments {
            count = manualSegmentIds.isEmpty ? 1 : manualSegmentIds.count
        } else {
            count = segmentCount(for: device, ledCount: totalLEDs)
        }
        let stops = segmentStops(totalLEDs: totalLEDs, segmentCount: count)
        let layout = stops.map { SegmentBounds(start: $0.start, stop: $0.stop) }
        let existingLayout = appManagedSegmentLayouts[device.id]
        let deviceSegments = device.state?.segments ?? []
        let layoutMatches = segmentsMatchLayout(deviceSegments, layout: layout, segmentCount: count)
        let includeLayout = !manualSegments && (existingLayout == nil || existingLayout != layout || !layoutMatches)
        let colors: [[Int]]
        if manualSegments, !manualSegmentsOrdered.isEmpty {
            let total = Double(max(1, totalLEDs))
            colors = manualSegmentsOrdered.map { segment in
                let start = Double(segment.start ?? 0)
                let stop = Double(segment.stop ?? segment.start ?? 0)
                let midpoint = max(0, min(total, (start + stop) / 2.0))
                let t = max(0.0, min(1.0, midpoint / total))
                let color = GradientSampler.sampleColor(
                    at: t,
                    stops: gradient.stops.sorted { $0.position < $1.position },
                    interpolation: gradient.interpolation
                )
                return color.toRGBArray()
            }
        } else {
            colors = segmentColors(for: gradient, count: count)
        }
        let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
        let supportsCCTDevice = supportsCCTOutput(for: device, segmentId: 0)
        let usesKelvin = segmentUsesKelvinCCT(for: device, segmentId: 0)
        let manualSegmentPositions: [Double]? = {
            guard manualSegments, !manualSegmentsOrdered.isEmpty else { return nil }
            let total = Double(max(1, totalLEDs))
            return manualSegmentsOrdered.map { segment in
                let start = Double(segment.start ?? 0)
                let stop = Double(segment.stop ?? segment.start ?? 0)
                let midpoint = max(0, min(total, (start + stop) / 2.0))
                return max(0.0, min(1.0, midpoint / total))
            }
        }()
        let manualSegmentTemperatures: [Double?]? = {
            guard let positions = manualSegmentPositions,
                  let stopTemperatures,
                  !stopTemperatures.isEmpty else { return nil }
            let sortedStops = gradient.stops.sorted { $0.position < $1.position }
            return positions.map { t in
                guard let (aIndex, bIndex) = boundingStopIndices(for: t, stops: sortedStops) else {
                    return nil
                }
                let aStop = sortedStops[aIndex]
                let bStop = sortedStops[bIndex]
                guard let aTemp = stopTemperatures[aStop.id],
                      let bTemp = stopTemperatures[bStop.id] else {
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
        }()
        let segmentTemperatures = (allowCCTTemperatureStops && supportsCCTDevice)
            ? (manualSegments ? (manualSegmentTemperatures ?? segmentTemperatures(for: gradient, count: count, stopTemperatures: stopTemperatures))
                              : segmentTemperatures(for: gradient, count: count, stopTemperatures: stopTemperatures))
            : nil
        let supportsWhiteValue = supportsWhite(for: device, segmentId: 0)
        let allowManualWhite = supportsWhiteValue
            && UserDefaults.standard.bool(forKey: "advancedUIEnabled")
        let manualSegmentWhiteLevels: [Int]? = {
            guard let positions = manualSegmentPositions,
                  let stopWhiteLevels,
                  !stopWhiteLevels.isEmpty else { return nil }
            let sortedStops = gradient.stops.sorted { $0.position < $1.position }
            let values = sortedStops.map { stopWhiteLevels[$0.id] ?? 0.0 }
            let hasWhite = values.contains { abs($0) > 0.0001 }
            guard hasWhite else { return nil }
            return positions.map { t in
                let value = interpolateScalar(stops: sortedStops, values: values, t: t, interpolation: gradient.interpolation)
                let clamped = max(0.0, min(1.0, value))
                return Int(round(clamped * 255.0))
            }
        }()
        let manualWhiteLevels = allowManualWhite
            ? (manualSegments ? (manualSegmentWhiteLevels ?? segmentWhiteLevels(for: gradient, count: count, stopWhiteLevels: stopWhiteLevels))
                              : segmentWhiteLevels(for: gradient, count: count, stopWhiteLevels: stopWhiteLevels))
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
            let resolvedSegmentId = manualSegmentIds.isEmpty ? idx : manualSegmentIds[idx]
            let rgb = colors[idx]
            var base = [rgb[0], rgb[1], rgb[2]]
            let whiteValue = manualWhiteLevels?[idx] ?? effectiveWhite
            if supportsWhiteValue, whiteValue == nil {
                base.append(0)
            }
            var col: [[Int]]? = [base]
            var cctValue: Int? = nil
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
                    id: resolvedSegmentId,
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

        let segmentTemperatureById: [Int: Double] = {
            guard let segmentTemperatures else { return [:] }
            var mapping: [Int: Double] = [:]
            for (idx, maybeTemp) in segmentTemperatures.enumerated() {
                guard let temp = maybeTemp else { continue }
                let resolvedSegmentId = manualSegmentIds.isEmpty ? idx : manualSegmentIds[idx]
                mapping[resolvedSegmentId] = temp
            }
            return mapping
        }()

        let cctOnlySegments = updates.filter { $0.cct != nil && $0.col == nil }
        if !cctOnlySegments.isEmpty {
            var clearUpdates: [SegmentUpdate] = []
            clearUpdates.reserveCapacity(cctOnlySegments.count)
            for segment in cctOnlySegments {
                let derivedRGB: [Int]
                if let id = segment.id,
                   let temp = segmentTemperatureById[id] {
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
                seg: clearUpdates
            )
            let cleared = await updateStateWithRetry(
                device,
                stateUpdate: clearState,
                context: "clear RGB before CCT"
            )
            if !cleared {
                #if DEBUG
                print("⚠️ Failed to clear RGB before CCT update for device \(device.name)")
                #endif
            }
        }

        if includeLayout, let existingSegments = device.state?.segments, !existingSegments.isEmpty {
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
                    custom1: existing.custom1,
                    custom2: existing.custom2,
                    custom3: existing.custom3,
                    option1: existing.option1,
                    option2: existing.option2,
                    option3: existing.option3,
                    isEnabled: false
                )
            }
            effectStates[device.id] = segmentStates
        }

        let transitionDeciseconds = forceNoPerCallTransition ? nil : clampedTransitionDeciseconds(for: transitionDurationSeconds)
        let shouldReleaseRealtime = releaseRealtimeOverride && !forceNoPerCallTransition
        let stateUpdate = WLEDStateUpdate(
            on: on,
            bri: brightness,
            seg: updates,
            transitionDeciseconds: transitionDeciseconds,
            lor: shouldReleaseRealtime ? 0 : nil
        )

        let updated = await updateStateWithRetry(
            device,
            stateUpdate: stateUpdate,
            context: "segmented gradient update"
        )
        guard updated else {
            #if DEBUG
            print("⚠️ Failed segmented gradient update for device \(device.name)")
            #endif
            return
        }
        if isRealTimeEnabled, shouldSendWebSocketUpdate(stateUpdate) {
            webSocketManager.sendStateUpdate(stateUpdate, to: device.id)
        }
        let writeSucceededAt = Date()
        await MainActor.run {
            gradientApplicationTimes[device.id] = Date()
            if !manualSegments {
                appManagedSegmentLayouts[device.id] = layout
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
                devices[index].isOnline = true
                devices[index].lastSeen = writeSucceededAt
                if !manualSegments {
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
                    if let state = devices[index].state {
                        devices[index].state = WLEDState(
                            brightness: state.brightness,
                            isOn: state.isOn,
                            segments: segmentStates,
                            transitionDeciseconds: state.transitionDeciseconds,
                            presetId: state.presetId,
                            playlistId: state.playlistId,
                            mainSegment: state.mainSegment
                        )
                    } else {
                        devices[index].state = WLEDState(
                            brightness: devices[index].brightness,
                            isOn: devices[index].isOn,
                            segments: segmentStates,
                            transitionDeciseconds: nil,
                            presetId: nil,
                            playlistId: nil,
                            mainSegment: nil
                        )
                    }
                    syncSegmentCapabilities(for: devices[index], segmentCount: segmentStates.count)
                }
            }
            deviceLedCounts[device.id] = totalLEDs
        }
    }

    private func segmentedPresetState(
        device: WLEDDevice,
        gradient: LEDGradient,
        brightness: Int,
        on: Bool,
        temperature: Double?,
        whiteLevel: Double?,
        includeSegmentBounds: Bool = true
    ) -> WLEDStateUpdate {
        let totalLEDs = totalLEDCount(for: device)
        let count = segmentCount(for: device, ledCount: totalLEDs)
        let stops = segmentStops(totalLEDs: totalLEDs, segmentCount: count)
        let colors = segmentColors(for: gradient, count: count)
        let sortedStops = gradient.stops.sorted { $0.position < $1.position }
        let isSolidColor = sortedStops.count == 1 || sortedStops.allSatisfy { $0.hexColor == sortedStops.first?.hexColor }
        let allowCCTTemperatureStops = temperatureStopsUseCCT(for: device)
        let supportsCCTDevice = supportsCCTOutput(for: device, segmentId: 0)
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
            let baseSegment = device.state?.segments.first(where: { $0.id == idx })
                ?? (device.state?.segments.indices.contains(idx) == true ? device.state?.segments[idx] : nil)
            let rgb = colors[idx]
            let col: [[Int]]?
            if useCCTOnly {
                col = nil
            } else if let whiteValue {
                col = [[rgb[0], rgb[1], rgb[2], whiteValue]]
            } else {
                col = [[rgb[0], rgb[1], rgb[2], 0]]
            }
            updates.append(
                SegmentUpdate(
                    id: idx,
                    start: includeSegmentBounds ? range.start : nil,
                    stop: includeSegmentBounds ? range.stop : nil,
                    grp: baseSegment?.grp ?? 1,
                    spc: baseSegment?.spc ?? 0,
                    ofs: baseSegment?.ofs ?? 0,
                    on: on,
                    bri: baseSegment?.bri ?? 255,
                    col: col,
                    cct: useCCTOnly ? cctValue : (baseSegment?.cct ?? 127),
                    fx: 0,
                    sx: baseSegment?.sx ?? 128,
                    ix: baseSegment?.ix ?? 128,
                    pal: 0,
                    c1: baseSegment?.c1 ?? 128,
                    c2: baseSegment?.c2 ?? 128,
                    c3: baseSegment?.c3 ?? 16,
                    sel: baseSegment?.sel ?? true,
                    rev: baseSegment?.rev ?? false,
                    mi: baseSegment?.mi ?? false,
                    cln: baseSegment?.cln,
                    o1: baseSegment?.o1 ?? false,
                    o2: baseSegment?.o2 ?? false,
                    o3: baseSegment?.o3 ?? false,
                    si: baseSegment?.si ?? 0,
                    m12: baseSegment?.m12 ?? 0,
                    setId: baseSegment?.setId ?? 0,
                    name: baseSegment?.name ?? "",
                    frz: baseSegment?.frz ?? false
                )
            )
        }

        return WLEDStateUpdate(
            on: on,
            bri: brightness,
            seg: updates,
            mainSegment: device.state?.mainSegment
        )
    }

    func presetStateForGradient(
        device: WLEDDevice,
        gradient: LEDGradient,
        brightness: Int,
        temperature: Double?,
        whiteLevel: Double?,
        includeSegmentBounds: Bool = true
    ) -> WLEDStateUpdate {
        segmentedPresetState(
            device: device,
            gradient: gradient,
            brightness: brightness,
            on: true,
            temperature: temperature,
            whiteLevel: whiteLevel,
            includeSegmentBounds: includeSegmentBounds
        )
    }

    private func availableIds(from maxId: Int, through minId: Int = 1, excluding used: Set<Int>, count: Int) -> [Int]? {
        guard count > 0 else { return [] }
        var results: [Int] = []
        for id in stride(from: maxId, through: minId, by: -1) {
            guard !used.contains(id) else { continue }
            results.append(id)
            if results.count == count {
                break
            }
        }
        return results.count == count ? results : nil
    }

    private func availableContiguousIds(
        range: ClosedRange<Int>,
        excluding used: Set<Int>,
        count: Int
    ) -> [Int]? {
        guard count > 0 else { return [] }
        var runStart: Int?
        var runLength = 0
        for id in range {
            if used.contains(id) {
                runStart = nil
                runLength = 0
                continue
            }
            if runStart == nil {
                runStart = id
                runLength = 1
            } else {
                runLength += 1
            }
            if let runStart, runLength == count {
                return Array(runStart...(runStart + count - 1))
            }
        }
        return nil
    }

    private func availablePlaylistId(excluding used: Set<Int>, range: ClosedRange<Int> = 1...250) -> Int? {
        for id in stride(from: range.upperBound, through: range.lowerBound, by: -1) {
            if !used.contains(id) {
                return id
            }
        }
        return nil
    }

    private func availableFrontmostPlaylistId(excluding used: Set<Int>, range: ClosedRange<Int>) -> Int? {
        for id in range where !used.contains(id) {
            return id
        }
        return nil
    }

    private func hasRecentPresetStoreTransportFailure(deviceId: String, within seconds: TimeInterval = 12.0) -> Bool {
        guard let eventAt = lastPresetStoreHealthEventByDeviceId[deviceId],
              Date().timeIntervalSince(eventAt) <= seconds else {
            return false
        }
        let message = (lastPresetStoreHealthMessageByDeviceId[deviceId] ?? "").lowercased()
        return message.contains("timed out")
            || message.contains("timeout")
            || message.contains("network")
            || message.contains("503")
            || message.contains("service unavailable")
    }

    private func shouldFailFastTemporaryPlaylistBuild(device: WLEDDevice) async -> Bool {
        if isPresetStoreWritePaused(for: device.id) {
            return true
        }
        if hasRecentPresetStoreTransportFailure(deviceId: device.id) {
            return true
        }
        if await apiService.isStateWriteBackoffActive(deviceId: device.id) {
            return true
        }
        return false
    }

    private func isTransientPresetStoreWriteError(_ error: Error) -> Bool {
        guard let apiError = error as? WLEDAPIError else {
            let message = error.localizedDescription.lowercased()
            return message.contains("timed out")
                || message.contains("timeout")
                || message.contains("network")
                || message.contains("503")
                || message.contains("service unavailable")
        }
        switch apiError {
        case .timeout, .networkError, .deviceBusy, .deviceOffline, .deviceUnreachable:
            return true
        case .httpError(let statusCode):
            return statusCode == 429 || statusCode >= 500
        default:
            return false
        }
    }

    private func waitForStateWriteBackoffIfNeeded(
        deviceId: String,
        timeoutSeconds: TimeInterval = 3.0
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while await apiService.isStateWriteBackoffActive(deviceId: deviceId), Date() < deadline {
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func savePresetWithRetry(
        _ request: WLEDPresetSaveRequest,
        device: WLEDDevice,
        retryAttempts: Int = 3
    ) async throws {
        var lastError: Error?
        let attempts = max(1, retryAttempts)
        for attempt in 1...attempts {
            if attempts > 1 {
                await waitForStateWriteBackoffIfNeeded(deviceId: device.id)
            }
            do {
                try await apiService.savePreset(request, to: device)
                let delay = presetSaveDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
                return
            } catch {
                lastError = error
                guard attempt < attempts, isTransientPresetStoreWriteError(error) else { break }
                let backoffNanos = max(
                    presetSaveDelayNanos * UInt64(attempt),
                    UInt64(min(2.4, 0.45 * Double(attempt)) * 1_000_000_000)
                )
                try? await Task.sleep(nanoseconds: backoffNanos)
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

    private func savePlaylistWithRetry(
        _ request: WLEDPlaylistSaveRequest,
        device: WLEDDevice,
        retryAttempts: Int = 3
    ) async throws {
        var lastError: Error?
        let attempts = max(1, retryAttempts)
        for attempt in 1...attempts {
            if attempts > 1 {
                await waitForStateWriteBackoffIfNeeded(deviceId: device.id)
            }
            do {
                _ = try await apiService.savePlaylist(request, to: device)
                let delay = playlistSaveDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
                return
            } catch {
                lastError = error
                guard attempt < attempts, isTransientPresetStoreWriteError(error) else { break }
                let backoffNanos = max(
                    playlistSaveDelayNanos * UInt64(attempt),
                    UInt64(min(2.8, 0.55 * Double(attempt)) * 1_000_000_000)
                )
                try? await Task.sleep(nanoseconds: backoffNanos)
            }
        }
        throw lastError ?? WLEDAPIError.invalidResponse
    }

    private func verifyPlaylistId(_ playlistId: Int, device: WLEDDevice) async -> Bool {
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
        let effectiveDurationSeconds: Double
        let stepProfile: TransitionStepProfile
        let playlistDurations: [Int]
        let playlistTransitions: [Int]
        let temporaryLeaseId: UUID?
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
        runId: UUID? = nil,
        debugOperationId: String? = nil,
        startTemperature: Double? = nil,
        endTemperature: Double? = nil,
        startWhiteLevel: Double? = nil,
        endWhiteLevel: Double? = nil
    ) async -> TransitionPlaylistResult? {
        if !persist, !enableTemporaryPresetStoreBackedTransitions {
            #if DEBUG
            print("transition.playlist_build.skipped_temporary_disabled device=\(device.id)")
            #endif
            return nil
        }
        let autoStepPrefix = persist ? "Automation Step " : "Auto Step "
        let autoTransitionPrefix = persist ? "Automation Transition " : "Auto Transition "
        #if DEBUG
        let storageMode = persist ? "persistent" : "temporary"
        let effectiveOperationId = debugOperationId
            ?? runId.map { "run-\($0.uuidString.prefix(8))" }
            ?? self.debugOperationId(prefix: persist ? "playlist-persist" : "playlist-temp")
        let operationContext = debugOperationContext(effectiveOperationId)
        print("🔎 Playlist build for \(device.name): mode=2-preset, storage=\(storageMode), playlist=psave, duration=\(String(format: "%.1f", durationSeconds))s\(operationContext)")
        #endif
        var temporaryLeaseId: UUID?
        if !persist, await shouldFailFastTemporaryPlaylistBuild(device: device) {
            #if DEBUG
            print("⚠️ Playlist creation skipped for \(device.name): recent timeout/backoff window active.")
            #endif
            return nil
        }

        switch await waitForHeavyOpQuiescence(deviceId: device.id, timeout: 15.0) {
        case .ready:
            break
        case .timedOut(let reason):
            #if DEBUG
            print("⚠️ Playlist creation deferred/aborted for \(device.name): heavy-op quiescence timeout (\(reason))")
            #endif
            return nil
        }

        var existingPresets: [WLEDPreset]
        if persist {
            do {
                existingPresets = try await apiService.fetchPresets(for: device)
            } catch {
                #if DEBUG
                print("⚠️ Playlist creation failed: unable to fetch presets for \(device.name): \(error.localizedDescription)")
                #endif
                return nil
            }
        } else {
            // Temporary transition IDs are isolated in reserved range; avoid blocking on
            // preset catalog reads when the device is under load.
            existingPresets = presetsCache[device.id] ?? []
            #if DEBUG
            if existingPresets.isEmpty {
                print("transition.playlist_build.temp_skip_catalog_read device=\(device.id)")
            } else {
                print("transition.playlist_build.temp_using_cached_catalog device=\(device.id) count=\(existingPresets.count)")
            }
            #endif
        }
        if isCorruptedPresetPayload(existingPresets) {
            #if DEBUG
            print("⚠️ Playlist creation failed: presets.json appears corrupted for \(device.name).")
            #endif
            return nil
        }
        updatePresetSlotStatus(for: device, presets: existingPresets)
        var usedPresetIds = Set(existingPresets.map { $0.id }.filter { (1...250).contains($0) })
        let context: TransitionGenerationContext = persist ? .persistentAutomation : .temporaryLive
        let stepProfile = planTransitionPlaylist(
            durationSec: durationSeconds,
            startGradient: from,
            endGradient: to,
            startBrightness: startBrightness,
            endBrightness: endBrightness,
            context: context,
            device: device
        )
        if persist, !stepProfile.fitsBudget {
            #if DEBUG
            let budgetText = stepProfile.perAutomationBudget.map(String.init) ?? "n/a"
            let maxDuration = stepProfile.maxDurationSecondsAtCurrentQuality ?? 0
            print("⚠️ Playlist creation blocked by 5-automation budget for \(device.name): required=\(stepProfile.slotsRequired) budget=\(budgetText) quality=\(stepProfile.qualityLabel.rawValue) maxDuration=\(String(format: "%.1f", maxDuration))s")
            #endif
            return nil
        }

        let timingUnit = playlistTimingUnit(for: device)
        let seamMode = persist ? "stored-start" : "preapplied-start"
        let baseTs = transitionKeyframeTs(stepCount: stepProfile.steps, context: context)
        let brightnessFallback = lastBrightnessBeforeOff[device.id] ?? device.state?.brightness ?? 128
        let rawKeyframes = baseTs.map { t in
            let interpolatedBrightness = Int(round(Double(startBrightness) * (1.0 - t) + Double(endBrightness) * t))
            return TransitionKeyframe(
                t: t,
                stops: interpolateStops(from: from, to: to, t: t),
                brightness: interpolatedBrightness > 0 ? interpolatedBrightness : max(1, brightnessFallback),
                temperature: interpolateOptional(startTemperature, endTemperature, t: t),
                whiteLevel: interpolateOptional(startWhiteLevel, endWhiteLevel, t: t)
            )
        }
        let clampedDuration = min(maxWLEDPlaylistDurationSeconds, max(0.0, durationSeconds))
        let requestedDeciseconds = clampedDuration > 0 ? max(1, Int(round(clampedDuration * 10.0))) : 0
        let minStepCountForTiming = requestedDeciseconds > 0
            ? max(1, Int(ceil(Double(requestedDeciseconds) / Double(maxWLEDPlaylistTransitionDeciseconds))))
            : 1
        let keyframes = cullNearDuplicateKeyframes(rawKeyframes, minimumCount: minStepCountForTiming)
        let stepCount = keyframes.count
        let stepPlan = playlistStepPlan(
            for: durationSeconds,
            timingUnit: timingUnit,
            fixedSteps: stepCount,
            generatedTimingMode: .boundaryCompensated(padDeciseconds: 3)
        )
        #if DEBUG
        let budgetText = stepProfile.perAutomationBudget.map(String.init) ?? "n/a"
        print("🔎 Playlist planner for \(device.name): context=\(context.rawValue) seam=\(seamMode) legSec=\(String(format: "%.1f", stepProfile.legSeconds)) quality=\(stepProfile.qualityLabel.rawValue) slots=\(stepProfile.slotsRequired) budget=\(budgetText) fits=\(stepProfile.fitsBudget)")
        print("🔎 Playlist keyframes for \(device.name): preCull=\(rawKeyframes.count) postCull=\(keyframes.count)")
        #endif

        let playlistSlotCount = 1
        let persistentAllowedUpper = max(1, temporaryTransitionReservedPresetLower - 1)
        let persistentAllowedRange = 1...persistentAllowedUpper
        let persistentRangeContains: (Int) -> Bool = { persistentAllowedRange.contains($0) }

        let existingStepIds = (existingStepPresetIds ?? []).filter { (1...250).contains($0) }
        let canReuseStepPresets = existingStepIds.count == stepCount
            && Set(existingStepIds).isSubset(of: usedPresetIds)
            && (!persist || existingStepIds.allSatisfy(persistentRangeContains))
        let canReusePlaylistId = existingPlaylistId.map {
            (1...250).contains($0)
                && usedPresetIds.contains($0)
                && (!persist || persistentRangeContains($0))
        } ?? false
        let requiredSlots = (canReuseStepPresets ? 0 : stepCount) + (canReusePlaylistId ? 0 : playlistSlotCount)
        if persist && !hasPresetCapacity(for: device, requiredSlots: requiredSlots, presets: existingPresets) {
            #if DEBUG
            let remaining = max(0, maxWLEDPresetSlots - existingPresets.count)
            print("⚠️ Playlist creation blocked: remaining=\(remaining), reserve=\(presetSlotReserve), required=\(requiredSlots) for \(device.name).")
            #endif
            return nil
        }
        var reusableStepPresetIds: [Int] = []
        if canReuseStepPresets {
            reusableStepPresetIds = existingStepIds
            reusableStepPresetIds.forEach { usedPresetIds.remove($0) }
        }
        var usedPlaylistIds = usedPresetIds
        var resolvedPlaylistId: Int? = nil
        if let existingPlaylistId, canReusePlaylistId {
            resolvedPlaylistId = existingPlaylistId
            usedPlaylistIds.remove(existingPlaylistId)
        }
        if resolvedPlaylistId == nil {
            let playlistRange = persist
                ? persistentAllowedRange
                : (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper)
            let selectedId = persist
                ? availableFrontmostPlaylistId(excluding: usedPlaylistIds, range: playlistRange)
                : availablePlaylistId(excluding: usedPlaylistIds, range: playlistRange)
            guard let resolvedId = selectedId else {
                #if DEBUG
                if persist {
                    print("⚠️ Playlist creation failed: no available playlist IDs for \(device.name).")
                } else {
                    let reservedFree = (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper)
                        .filter { !usedPlaylistIds.contains($0) }
                        .count
                    print("⚠️ Temporary transition blocked for \(device.name): no playlist ID in reserved range \(temporaryTransitionReservedPresetLower)-\(temporaryTransitionReservedPresetUpper), free=\(reservedFree)")
                }
                #endif
                return nil
            }
            resolvedPlaylistId = resolvedId
        }
        if let resolvedPlaylistId {
            usedPresetIds.insert(resolvedPlaylistId)
        }

        let needsStepIds = reusableStepPresetIds.count != stepCount
        var allocatedPresetIds: [Int]? = nil
        if needsStepIds {
            allocatedPresetIds = persist
                ? availableContiguousIds(
                    range: persistentAllowedRange,
                    excluding: usedPresetIds,
                    count: stepCount
                )
                : availableIds(
                    from: temporaryTransitionReservedPresetUpper,
                    through: temporaryTransitionReservedPresetLower,
                    excluding: usedPresetIds,
                    count: stepCount
                )
        }

        if needsStepIds, allocatedPresetIds == nil {
            #if DEBUG
            if persist {
                print("⚠️ Playlist creation failed: insufficient contiguous preset slots (\(stepCount) needed) in persistent range for \(device.name).")
            } else {
                let reservedUsed = usedPresetIds.filter { (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0) }
                let reservedFree = (temporaryTransitionReservedPresetUpper - temporaryTransitionReservedPresetLower + 1) - reservedUsed.count
                let slotsRequired = stepCount + (resolvedPlaylistId == nil ? 1 : 0)
                print("⚠️ Temporary transition blocked for \(device.name): needs \(slotsRequired) reserved slots in \(temporaryTransitionReservedPresetLower)-\(temporaryTransitionReservedPresetUpper), only \(max(0, reservedFree)) available")
            }
            #endif
            return nil
        }

        var stepPresetIds = reusableStepPresetIds
        if needsStepIds, let allocatedPresetIds {
            stepPresetIds = Array(allocatedPresetIds.prefix(stepCount))
        }
        stepPresetIds = stepPresetIds.sorted()
        let presetSaveAttempts = persist ? presetSaveRetryAttempts : 1
        let playlistSaveAttempts = persist ? playlistSaveRetryAttempts : 1

        guard let playlistId = resolvedPlaylistId, stepPresetIds.count == stepCount else {
            #if DEBUG
            print("⚠️ Playlist creation failed: missing playlist or step presets for \(device.name).")
            #endif
            return nil
        }

        #if DEBUG
        print("transition.playlist_build.ids device=\(device.id)\(operationContext) persist=\(persist) playlist=\(playlistId) stepIds=\(stepPresetIds)")
        #endif

        if !persist {
            let lease = await TemporaryTransitionCleanupService.shared.registerLease(
                deviceId: device.id,
                runId: runId,
                playlistId: playlistId,
                stepPresetIds: []
            )
            temporaryLeaseId = lease.leaseId
            #if DEBUG
            print("🔎 Temporary cleanup lease for \(device.name): leaseId=\(lease.leaseId.uuidString) playlistId=\(playlistId)\(operationContext)")
            #endif
        }

        await MainActor.run {
            _ = presetWriteInProgress.insert(device.id)
        }
        defer {
            Task { @MainActor in
                presetWriteInProgress.remove(device.id)
            }
        }

        let shouldCleanupStepPresets = needsStepIds
        func cleanupAllocatedStepPresets() async {
            guard shouldCleanupStepPresets, !stepPresetIds.isEmpty else { return }
            await DeviceCleanupManager.shared.requestDelete(
                type: .preset,
                device: device,
                ids: stepPresetIds,
                source: persist ? .automation : .temporaryTransition,
                leaseId: temporaryLeaseId,
                verificationRequired: !persist
            )
        }

        func cleanupFailedTemporaryOrAllocated() async {
            if let temporaryLeaseId {
                await TemporaryTransitionCleanupService.shared.markCreationFailed(
                    leaseId: temporaryLeaseId,
                    device: device
                )
            } else {
                await cleanupAllocatedStepPresets()
            }
        }

        let stepPresetCount = stepPresetIds.count
        if stepPlan.clampedDurationSeconds < durationSeconds {
            #if DEBUG
            print("⚠️ Playlist duration capped for \(device.name): requested=\(String(format: "%.1f", durationSeconds))s, clamped=\(String(format: "%.1f", stepPlan.clampedDurationSeconds))s")
            #endif
        }
        #if DEBUG
        let stepTransitionSeconds = Double(stepPlan.transitionDeciseconds) / 10.0
        let stepDurationSeconds = Double(stepPlan.durationDeciseconds) / 10.0
        print("🔎 Playlist step plan for \(device.name): steps=\(stepPresetCount), mode=\(stepPlan.timingModeLabel), boundaryPadDs=\(stepPlan.generatedTransitionPadDeciseconds), durStep=\(String(format: "%.2f", stepDurationSeconds))s (\(stepPlan.durationDeciseconds)ds) transitionStep=\(String(format: "%.2f", stepTransitionSeconds))s (\(stepPlan.transitionDeciseconds)ds)")
        print("🔎 Transition A->B for \(device.name): start=\(debugGradientSummary(from)) end=\(debugGradientSummary(to))")
        print("🔎 Playlist timing source for \(device.name): source=playlist.transition[] preset.transition_ignored_if_playlist_active=true tt_present=false")
        print("🔎 Playlist timing for \(device.name): requested=\(String(format: "%.1f", durationSeconds))s dur=\(debugArraySummary(stepPlan.durations)) transition=\(debugArraySummary(stepPlan.transitions)) total=\(String(format: "%.1f", stepPlan.effectiveDurationSeconds))s totalTransition=\(String(format: "%.1f", stepPlan.totalTransitionSeconds))s")
        if stepPlan.durations.count > 1 {
            var cumulative = 0
            let boundaries = stepPlan.durations.dropLast().map { duration -> Double in
                cumulative += duration
                return Double(cumulative) / 10.0
            }
            let boundarySummary = boundaries.map { String(format: "%.1f", $0) }.joined(separator: ", ")
            print("🔎 Playlist expected boundaries for \(device.name): \(boundarySummary)")
        }
        #endif
        #if DEBUG
        let debugIndices: Set<Int> = [0, stepPresetCount / 2, max(0, stepPresetCount - 1)]
        #endif
        func shouldAbortTemporaryCreation() async -> Bool {
            guard !persist, let runId else { return false }
            return await MainActor.run {
                if let active = activeRunStatus[device.id] {
                    return active.id != runId
                }
                return true
            }
        }
        for (idx, presetId) in stepPresetIds.enumerated() {
            if await shouldAbortTemporaryCreation() {
                if temporaryLeaseId != nil {
                    await TemporaryTransitionCleanupService.shared.requestCleanup(
                        device: device,
                        endReason: .cancelledByUser,
                        runId: runId,
                        playlistIdHint: playlistId,
                        stepPresetIdsHint: Array(stepPresetIds.prefix(idx))
                    )
                    await refreshTransitionCleanupPendingCount(for: device.id)
                }
                return nil
            }
            if !persist, await shouldFailFastTemporaryPlaylistBuild(device: device) {
                #if DEBUG
                print("⚠️ Playlist creation aborted for \(device.name): device entered timeout/backoff window mid-build.")
                #endif
                await cleanupFailedTemporaryOrAllocated()
                return nil
            }
            let keyframe = keyframes[idx]
            let t = keyframe.t
            let stops = keyframe.stops
            let presetBrightness = keyframe.brightness
            let tempValue = keyframe.temperature
            let whiteValue = keyframe.whiteLevel
            #if DEBUG
            if debugIndices.contains(idx) {
                let firstHex = stops.first?.hexColor ?? "none"
                let lastHex = stops.last?.hexColor ?? firstHex
                let tempText = tempValue.map { String(format: "%.2f", $0) } ?? "nil"
                let whiteText = whiteValue.map { String(format: "%.2f", $0) } ?? "nil"
                print("🔎 Step \(idx + 1)/\(stepPresetCount) presetId=\(presetId) t=\(String(format: "%.2f", t)) bri=\(presetBrightness) temp=\(tempText) white=\(whiteText) first=\(firstHex) last=\(lastHex)")
            }
            #endif
            let state = segmentedPresetState(
                device: device,
                gradient: LEDGradient(stops: stops, interpolation: to.interpolation),
                brightness: presetBrightness,
                on: true,
                temperature: tempValue,
                whiteLevel: whiteValue,
                includeSegmentBounds: true
            )
            let request = WLEDPresetSaveRequest(
                id: presetId,
                name: "\(autoStepPrefix)\(presetId)",
                quickLoad: nil,
                state: state,
                saveOnly: true,
                includeBrightness: true,
                saveSegmentBounds: true,
                selectedSegmentsOnly: false,
                transitionDeciseconds: device.state?.transitionDeciseconds ?? 7
            )
            do {
                try await savePresetWithRetry(
                    request,
                    device: device,
                    retryAttempts: presetSaveAttempts
                )
                if let temporaryLeaseId {
                    _ = await TemporaryTransitionCleanupService.shared.updateAllocatingLease(
                        leaseId: temporaryLeaseId,
                        appendStepPresetId: presetId
                    )
                }
            } catch {
                #if DEBUG
                print("⚠️ Playlist creation failed: preset save error for \(device.name): \(error.localizedDescription)")
                #endif
                await cleanupFailedTemporaryOrAllocated()
                return nil
            }
            // Give WLED time to flush presets.json between writes.
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        // Allow WLED to finalize the presets file before saving the playlist.
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Verify presets exist before building playlist for persistent saves.
        if persist {
            let presetsVerified = await verifyPresetIds(stepPresetIds, device: device)
            if !presetsVerified {
                #if DEBUG
                print("⚠️ Playlist creation warning: missing presets after save for \(device.name): \(stepPresetIds)")
                #endif
                await cleanupAllocatedStepPresets()
                return nil
            }
        }

        let durations = stepPlan.durations
        let transitions = stepPlan.transitions
        let playlistName = label?.isEmpty == false ? label! : "\(autoTransitionPrefix)\(playlistId)"
        let playlistRequest = WLEDPlaylistSaveRequest(
            id: playlistId,
            name: playlistName,
            ps: stepPresetIds,
            dur: durations,
            transition: transitions,
            repeat: 1,
            endPresetId: 0,
            shuffle: 0
        )
        #if DEBUG
        print("🔎 Playlist payload for \(device.name): id=\(playlistId) ps=\(stepPresetIds) dur=\(debugArraySummary(durations)) transition=\(debugArraySummary(transitions)) repeat=1 end=0 r=0")
        #endif

        if await shouldAbortTemporaryCreation() {
            if temporaryLeaseId != nil {
                await TemporaryTransitionCleanupService.shared.requestCleanup(
                    device: device,
                    endReason: .cancelledByUser,
                    runId: runId,
                    playlistIdHint: playlistId,
                    stepPresetIdsHint: stepPresetIds
                )
                await refreshTransitionCleanupPendingCount(for: device.id)
            }
            return nil
        }

        do {
            try await savePlaylistWithRetry(
                playlistRequest,
                device: device,
                retryAttempts: playlistSaveAttempts
            )
            if let temporaryLeaseId {
                _ = await TemporaryTransitionCleanupService.shared.markReady(
                    leaseId: temporaryLeaseId,
                    playlistId: playlistId,
                    stepPresetIds: stepPresetIds
                )
            }
            if persist {
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
                    await cleanupFailedTemporaryOrAllocated()
                    return nil
                }
            }
        } catch {
            #if DEBUG
            print("⚠️ Playlist creation failed: playlist save error for \(device.name): \(error.localizedDescription)")
            #endif
            await cleanupFailedTemporaryOrAllocated()
            return nil
        }

        if !persist {
            await MainActor.run {
                temporaryPlaylistIds[device.id] = playlistId
                temporaryPresetIds[device.id] = stepPresetIds
            }
        }
        #if DEBUG
        print("transition.playlist_build.success device=\(device.id)\(operationContext) playlist=\(playlistId) steps=\(stepPresetIds.count) persist=\(persist)")
        #endif
        return TransitionPlaylistResult(
            playlistId: playlistId,
            stepPresetIds: stepPresetIds,
            effectiveDurationSeconds: stepPlan.effectiveDurationSeconds,
            stepProfile: stepProfile,
            playlistDurations: durations,
            playlistTransitions: transitions,
            temporaryLeaseId: temporaryLeaseId
        )
    }

    func saveTransitionPresetToDevice(
        _ preset: TransitionPreset,
        device: WLEDDevice,
        debugOperationId: String? = nil
    ) async -> TransitionPlaylistResult? {
        #if DEBUG
        let operationContext = debugOperationContext(debugOperationId)
        print("transition_preset.save.path=createTransitionPlaylist_persist device=\(device.id)\(operationContext)")
        #endif
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
            debugOperationId: debugOperationId,
            startTemperature: preset.temperatureA,
            endTemperature: preset.temperatureB,
            startWhiteLevel: preset.whiteLevelA,
            endWhiteLevel: preset.whiteLevelB
        )

        guard let result else { return nil }

        #if DEBUG
        print("transition_preset.save.synced device=\(device.id)\(operationContext) playlist=\(result.playlistId) stepIds=\(result.stepPresetIds)")
        #endif

        if let existingPlaylistId = preset.wledPlaylistId, existingPlaylistId != result.playlistId {
            await DeviceCleanupManager.shared.requestDelete(type: .playlist, device: device, ids: [existingPlaylistId])
        }
        if let existingStepPresetIds = preset.wledStepPresetIds {
            let staleStepIds = Set(existingStepPresetIds).subtracting(Set(result.stepPresetIds))
            if !staleStepIds.isEmpty {
                await DeviceCleanupManager.shared.requestDelete(
                    type: .preset,
                    device: device,
                    ids: Array(staleStepIds).sorted()
                )
            }
        }

        return result
    }

    func saveTransitionPresetWithActiveRunHandling(
        device: WLEDDevice,
        presetInputSnapshot: TransitionPreset
    ) async -> TransitionPresetSaveOutcome? {
        let snappedPreset = presetInputSnapshot
        let deviceId = device.id
        #if DEBUG
        let operationId = debugOperationId(prefix: "preset-save")
        let operationContext = debugOperationContext(operationId)
        #else
        let operationId: String? = nil
        #endif
        await refreshTransitionCleanupPendingCount(for: deviceId)
        let initialAvailability = await MainActor.run { transitionPresetSaveAvailability(for: deviceId) }
        if initialAvailability == .blockedLoading {
            #if DEBUG
            print("preset_save.blocked device=\(deviceId)\(operationContext) reason=\(initialAvailability.rawValue)")
            #endif
            return .suppressedBusy
        }
        let activeStatus = await MainActor.run { activeRunStatus[deviceId] }

        let hasActiveRun = activeStatus != nil
        #if DEBUG
        let activeKind = activeStatus.map { String(describing: $0.kind) } ?? "none"
        print("preset_save.begin device=\(deviceId)\(operationContext) availability=\(initialAvailability.rawValue) activeRun=\(hasActiveRun) activeKind=\(activeKind)")
        #endif
        if hasActiveRun {
            #if DEBUG
            print("preset_save.active_transition_detected device=\(deviceId)\(operationContext)")
            print("preset_save.cancel_before_save device=\(deviceId)\(operationContext)")
            #endif
            await cancelActiveRun(for: device, force: true, endReason: .cancelledByPresetSave)
        }

        await refreshTransitionCleanupPendingCount(for: deviceId)
        if enableTemporaryPresetStoreBackedTransitions {
            await TemporaryTransitionCleanupService.shared.deferInteractiveConflictingCleanup(
                for: deviceId,
                until: Date().addingTimeInterval(4.0)
            )
        }
        let quiescence = await waitForHeavyOpQuiescence(deviceId: deviceId, timeout: 15.0)
        switch quiescence {
        case .ready:
            break
        case .timedOut(let reason):
            let deferred = enqueueDeferredPresetStoreSyncItem(
                deviceId: deviceId,
                kind: .transitionPresetSave,
                transitionPresetSnapshot: snappedPreset,
                error: "Deferred after quiescence timeout: \(reason)"
            )
            #if DEBUG
            print("preset_save.deferred_race_busy device=\(deviceId)\(operationContext) item=\(deferred.id.uuidString)")
            #endif
            return .deferred(deferred)
        }

        if isPresetStoreWritePaused(for: deviceId) {
            let deferred = enqueueDeferredPresetStoreSyncItem(
                deviceId: deviceId,
                kind: .transitionPresetSave,
                transitionPresetSnapshot: snappedPreset,
                error: "Deferred: preset store writes paused due to degraded device storage"
            )
            #if DEBUG
            print("preset_save.deferred device=\(deviceId)\(operationContext) item=\(deferred.id.uuidString)")
            #endif
            return .deferred(deferred)
        }

        #if DEBUG
        print("preset_save.start_after_cancel device=\(deviceId)\(operationContext)")
        #endif
        if let result = await saveTransitionPresetToDevice(
            snappedPreset,
            device: device,
            debugOperationId: operationId
        ) {
            markPresetStoreHealthyWriteSuccess(deviceId: deviceId)
            #if DEBUG
            print("preset_save.completed device=\(deviceId)\(operationContext) playlist=\(result.playlistId)")
            #endif
            return .saved(result)
        }

        await refreshTransitionCleanupPendingCount(for: deviceId)
        if let busyClassification = classifyTransitionPresetSaveBusyFailure(deviceId: deviceId) {
            let deferred = enqueueDeferredPresetStoreSyncItem(
                deviceId: deviceId,
                kind: .transitionPresetSave,
                transitionPresetSnapshot: snappedPreset,
                error: "Deferred after busy preset save failure: \(busyClassification)"
            )
            #if DEBUG
            print("preset_save.suppressed_busy device=\(deviceId)\(operationContext) classification=\(busyClassification)")
            print("preset_save.deferred_race_busy device=\(deviceId)\(operationContext) item=\(deferred.id.uuidString)")
            #endif
            return .deferred(deferred)
        }

        recordPresetStoreFailure(
            deviceId: deviceId,
            message: "Transition preset save failed"
        )
        #if DEBUG
        print("preset_save.failed device=\(deviceId)\(operationContext)")
        #endif
        return .suppressedBusy
    }

    func waitForTransitionApplyQuiescence(
        deviceId: String,
        timeout: TimeInterval = 15.0
    ) async -> HeavyOpQuiescenceResult {
        await waitForHeavyOpQuiescence(deviceId: deviceId, timeout: timeout)
    }

    func validateStoredTransitionPresetPlaylist(
        _ preset: TransitionPreset,
        device: WLEDDevice
    ) async -> StoredTransitionPlaylistValidation {
        guard let playlistId = preset.wledPlaylistId else {
            return .missingPlaylistId
        }
        if transitionPresetUsesReservedTempIds(preset) {
            return .legacyTempRangeIds
        }

        let playlists: [WLEDPlaylist]
        do {
            playlists = try await apiService.fetchPlaylists(for: device)
        } catch {
            return .unknownReadFailure
        }

        guard let playlist = playlists.first(where: { $0.id == playlistId }) else {
            return .missingPlaylistRecord
        }
        if playlist.presets.contains(where: { (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0) }) {
            return .legacyTempRangeIds
        }

        let expectedStepIds = preset.wledStepPresetIds?.isEmpty == false
            ? (preset.wledStepPresetIds ?? [])
            : playlist.presets

        guard !expectedStepIds.isEmpty else { return .valid }

        do {
            let presets = try await apiService.fetchPresets(for: device)
            let existingPresetIds = Set(presets.map(\.id))
            let missing = expectedStepIds.filter { !existingPresetIds.contains($0) }
            return missing.isEmpty ? .valid : .missingStepPresets(missing)
        } catch {
            return .unknownReadFailure
        }
    }

    func applyTransitionPreset(
        _ preset: TransitionPreset,
        to device: WLEDDevice
    ) async -> TransitionPresetApplyOutcome {
        await applyTransitionPreset(preset, to: device, queueOnSuppressedBusy: true)
    }

    private func applyTransitionPreset(
        _ preset: TransitionPreset,
        to device: WLEDDevice,
        queueOnSuppressedBusy: Bool
    ) async -> TransitionPresetApplyOutcome {
        let deviceId = device.id
        #if DEBUG
        let operationId = debugOperationId(prefix: "preset-apply")
        let operationContext = debugOperationContext(operationId)
        #else
        let operationId: String? = nil
        #endif
        var clearQueuedOnExit = queueOnSuppressedBusy
        defer {
            if clearQueuedOnExit {
                clearQueuedTransitionPresetApply(deviceId: deviceId)
            }
        }
        #if DEBUG
        print("transition_preset.apply.begin device=\(deviceId)\(operationContext) preset=\(preset.id.uuidString) sync=\(preset.wledSyncState.rawValue) playlist=\(preset.wledPlaylistId.map(String.init) ?? "nil")")
        #endif

        var replayPreset = preset
        var syncState = replayPreset.wledSyncState
        let shouldUseStoredPlaylist = replayPreset.wledPlaylistId != nil
            || syncState == .pendingSync
            || syncState == .syncFailed
            || syncState == .needsMigration

        // Fast path: for synced presets with a valid stored playlist, replay immediately.
        // This matches WLED's direct playlist start semantics and avoids unnecessary pre-cancel lag.
        if syncState == .synced,
           let playlistId = replayPreset.wledPlaylistId,
           !transitionPresetUsesReservedTempIds(replayPreset) {
            #if DEBUG
            print("transition_preset.apply.fast_replay_attempt device=\(deviceId)\(operationContext) playlistId=\(playlistId)")
            #endif
            let fastApplied = await startPlaylist(
                device: device,
                playlistId: playlistId,
                runTitle: preset.name,
                expectedDurationSeconds: preset.durationSec,
                transitionDeciseconds: nil,
                runKind: .transition,
                assumeStarted: false,
                strictValidation: true,
                preferWebSocketFirst: true
            )
            if fastApplied {
                await markTransitionPresetSynced(replayPreset)
                #if DEBUG
                print("transition_preset.apply.fast_replay_started device=\(deviceId)\(operationContext) playlistId=\(playlistId)")
                #endif
                return .startedStoredPlaylist(playlistId: playlistId)
            }
            #if DEBUG
            print("transition_preset.apply.fast_replay_failed device=\(deviceId)\(operationContext) playlistId=\(playlistId)")
            #endif
        }

        let activeStatus = await MainActor.run { activeRunStatus[deviceId] }
        if let activeStatus, activeStatus.kind == .transition || activeStatus.kind == .automation {
            await cancelActiveRun(for: device, force: true, endReason: .cancelledByManualInput)
        } else {
            await cancelActiveTransitionIfNeeded(for: device)
        }
        await refreshTransitionCleanupPendingCount(for: deviceId)
        if enableTemporaryPresetStoreBackedTransitions {
            await TemporaryTransitionCleanupService.shared.deferInteractiveConflictingCleanup(
                for: deviceId,
                until: Date().addingTimeInterval(4.0)
            )
        }

        #if DEBUG
        print("transition_preset.apply.wait_quiescence.begin device=\(deviceId)\(operationContext)")
        #endif
        switch await waitForTransitionApplyQuiescence(deviceId: deviceId, timeout: 15.0) {
        case .ready:
            #if DEBUG
            print("transition_preset.apply.wait_quiescence.ready device=\(deviceId)\(operationContext)")
            #endif
            break
        case .timedOut(let reason):
            #if DEBUG
            print("transition_preset.apply.wait_quiescence.timeout device=\(deviceId)\(operationContext) reason=\(reason)")
            print("transition_preset.apply.suppressed_busy device=\(deviceId)\(operationContext)")
            #endif
            if queueOnSuppressedBusy {
                clearQueuedOnExit = false
                queueTransitionPresetApply(presetId: preset.id, deviceId: deviceId)
            }
            return .suppressedBusy
        }

        if shouldUseStoredPlaylist {
            if syncState == .pendingSync || syncState == .syncFailed {
                if let promoted = await promotePendingTransitionPresetForReplay(
                    replayPreset,
                    device: device,
                    debugOperationId: operationId
                ) {
                    replayPreset.wledPlaylistId = promoted.playlistId
                    replayPreset.wledStepPresetIds = promoted.stepPresetIds
                    replayPreset.wledSyncState = .synced
                    replayPreset.lastWLEDSyncError = nil
                    replayPreset.lastWLEDSyncAt = Date()
                    syncState = .synced
                } else {
                    return await rebuildTransitionPreset(preset, device: device, outcomeForPendingSync: true)
                }
            }

            if syncState == .needsMigration || transitionPresetUsesReservedTempIds(replayPreset) {
                await markTransitionPresetNeedsMigration(replayPreset)
                return await rebuildTransitionPreset(preset, device: device, reason: .legacyTempRangeIds)
            }

            guard let playlistId = replayPreset.wledPlaylistId else {
                return await rebuildTransitionPreset(preset, device: device, reason: .missingWLEDPlaylistId)
            }

            #if DEBUG
            print("transition_preset.apply.replay_attempt device=\(deviceId)\(operationContext) playlistId=\(playlistId)")
            #endif
            let applied = await startPlaylist(
                device: device,
                playlistId: playlistId,
                runTitle: preset.name,
                expectedDurationSeconds: preset.durationSec,
                transitionDeciseconds: nil,
                runKind: .transition,
                strictValidation: true,
                preferWebSocketFirst: true
            )
            if applied {
                await markTransitionPresetSynced(replayPreset)
                #if DEBUG
                print("transition_preset.apply.replay_started device=\(deviceId)\(operationContext) playlistId=\(playlistId)")
                #endif
                return .startedStoredPlaylist(playlistId: playlistId)
            }

            let validation = await validateStoredTransitionPresetPlaylist(replayPreset, device: device)
            switch validation {
            case .legacyTempRangeIds:
                await markTransitionPresetNeedsMigration(replayPreset)
                #if DEBUG
                print("transition_preset.apply.legacy_temp_range_ids playlistId=\(playlistId)")
                #endif
                return await rebuildTransitionPreset(preset, device: device, reason: .legacyTempRangeIds)
            case .missingStepPresets(let ids):
                await markTransitionPresetSyncFailure(replayPreset, error: "Missing step presets: \(ids)")
                #if DEBUG
                print("transition_preset.apply.validation missingSteps=\(ids)")
                #endif
                return await rebuildTransitionPreset(preset, device: device, reason: .playlistInvalidOrMissingSteps)
            case .missingPlaylistRecord:
                await markTransitionPresetSyncFailure(replayPreset, error: "Missing playlist record")
                return await rebuildTransitionPreset(preset, device: device, reason: .playlistStartFailed)
            case .missingPlaylistId:
                return await rebuildTransitionPreset(preset, device: device, reason: .missingWLEDPlaylistId)
            case .unknownReadFailure:
                return await rebuildTransitionPreset(preset, device: device, reason: .playlistStartFailed)
            case .valid:
                return await rebuildTransitionPreset(preset, device: device, reason: .playlistStartFailed)
            }
        }

        if syncState == .synced && replayPreset.wledPlaylistId == nil {
            return await rebuildTransitionPreset(preset, device: device, reason: .missingWLEDPlaylistId)
        }
        return await rebuildTransitionPreset(preset, device: device, reason: .shortDurationDirectApply)
    }

    private func promotePendingTransitionPresetForReplay(
        _ preset: TransitionPreset,
        device: WLEDDevice,
        debugOperationId: String? = nil
    ) async -> TransitionPlaylistResult? {
        if isPresetStoreWritePaused(for: device.id) {
            #if DEBUG
            let operationContext = debugOperationContext(debugOperationId)
            print("transition_preset.apply.promote_skipped_paused device=\(device.id)\(operationContext)")
            #endif
            return nil
        }
        #if DEBUG
        let operationContext = debugOperationContext(debugOperationId)
        print("transition_preset.apply.promote_attempt device=\(device.id)\(operationContext) preset=\(preset.id.uuidString)")
        #endif
        guard let result = await saveTransitionPresetToDevice(
            preset,
            device: device,
            debugOperationId: debugOperationId
        ) else {
            #if DEBUG
            print("transition_preset.apply.promote_failed device=\(device.id)\(operationContext) preset=\(preset.id.uuidString)")
            #endif
            return nil
        }
        markPresetStoreHealthyWriteSuccess(deviceId: device.id)
        await updateTransitionPresetSyncMetadata(preset.id) { stored in
            stored.wledPlaylistId = result.playlistId
            stored.wledStepPresetIds = result.stepPresetIds
            stored.wledSyncState = .synced
            stored.lastWLEDSyncError = nil
            stored.lastWLEDSyncAt = Date()
        }
        #if DEBUG
        print("transition_preset.apply.promoted device=\(device.id)\(operationContext) playlist=\(result.playlistId) stepIds=\(result.stepPresetIds)")
        #endif
        return result
    }

    private func queueTransitionPresetApply(presetId: UUID, deviceId: String) {
        queuedTransitionPresetApplyByDeviceId[deviceId] = presetId
        queuedTransitionPresetApplyTasksByDeviceId[deviceId]?.cancel()
        queuedTransitionPresetApplyTasksByDeviceId[deviceId] = Task { [weak self] in
            guard let self else { return }
            await self.runQueuedTransitionPresetApply(deviceId: deviceId, presetId: presetId)
        }
        #if DEBUG
        print("transition_preset.apply.queued device=\(deviceId) preset=\(presetId.uuidString)")
        #endif
    }

    private func clearQueuedTransitionPresetApply(deviceId: String, presetId: UUID? = nil) {
        if let current = queuedTransitionPresetApplyByDeviceId[deviceId] {
            if let presetId, current != presetId { return }
            queuedTransitionPresetApplyByDeviceId.removeValue(forKey: deviceId)
        }
        queuedTransitionPresetApplyTasksByDeviceId[deviceId]?.cancel()
        queuedTransitionPresetApplyTasksByDeviceId.removeValue(forKey: deviceId)
    }

    private func runQueuedTransitionPresetApply(deviceId: String, presetId: UUID) async {
        defer {
            if queuedTransitionPresetApplyByDeviceId[deviceId] == presetId {
                queuedTransitionPresetApplyTasksByDeviceId.removeValue(forKey: deviceId)
            }
        }

        // Short settle to avoid fighting the just-triggered busy window.
        try? await Task.sleep(nanoseconds: 750_000_000)

        for _ in 0..<8 {
            if Task.isCancelled { return }
            if queuedTransitionPresetApplyByDeviceId[deviceId] != presetId { return }

            let quiescence = await waitForTransitionApplyQuiescence(deviceId: deviceId, timeout: 4.0)
            guard case .ready = quiescence else {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            guard let device = devices.first(where: { $0.id == deviceId }),
                  let preset = PresetsStore.shared.transitionPreset(id: presetId) else {
                clearQueuedTransitionPresetApply(deviceId: deviceId, presetId: presetId)
                return
            }

            let outcome = await applyTransitionPreset(preset, to: device, queueOnSuppressedBusy: false)
            switch outcome {
            case .startedStoredPlaylist, .rebuiltTransition, .deferredSyncThenRebuilt, .aborted:
                clearQueuedTransitionPresetApply(deviceId: deviceId, presetId: presetId)
                #if DEBUG
                print("transition_preset.apply.queued_completed device=\(deviceId) preset=\(presetId.uuidString)")
                #endif
                return
            case .suppressedBusy:
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
        }

        // Keep queued marker so user intent is still visible; task can be retriggered by a later tap.
        #if DEBUG
        if queuedTransitionPresetApplyByDeviceId[deviceId] == presetId {
            print("transition_preset.apply.queued_timeout device=\(deviceId) preset=\(presetId.uuidString)")
        }
        #endif
    }

    private func rebuildTransitionPreset(
        _ preset: TransitionPreset,
        device: WLEDDevice,
        reason: TransitionPresetFallbackReason? = nil,
        outcomeForPendingSync: Bool = false
    ) async -> TransitionPresetApplyOutcome {
        let fallbackReason = reason ?? .pendingSync
        #if DEBUG
        print("transition_preset.apply.fallback device=\(device.id) reason=\(fallbackReason.rawValue)")
        #endif
        let startTemps = preset.temperatureA.map { temp in
            Dictionary(uniqueKeysWithValues: preset.gradientA.stops.map { ($0.id, temp) })
        }
        let startWhites = preset.whiteLevelA.map { white in
            Dictionary(uniqueKeysWithValues: preset.gradientA.stops.map { ($0.id, white) })
        }
        let endTemps = preset.temperatureB.map { temp in
            Dictionary(uniqueKeysWithValues: preset.gradientB.stops.map { ($0.id, temp) })
        }
        let endWhites = preset.whiteLevelB.map { white in
            Dictionary(uniqueKeysWithValues: preset.gradientB.stops.map { ($0.id, white) })
        }
        await startTransition(
            from: preset.gradientA,
            aBrightness: preset.brightnessA,
            to: preset.gradientB,
            bBrightness: preset.brightnessB,
            durationSec: preset.durationSec,
            device: device,
            startStopTemperatures: startTemps,
            startStopWhiteLevels: startWhites,
            endStopTemperatures: endTemps,
            endStopWhiteLevels: endWhites
        )
        if fallbackReason == .legacyTempRangeIds || fallbackReason == .playlistInvalidOrMissingSteps {
            await markTransitionPresetPendingSync(
                preset,
                error: "WLED playlist replay invalid; rebuilt locally and pending re-sync"
            )
        }
        #if DEBUG
        print("transition_preset.apply.rebuilt device=\(device.id)")
        #endif
        return outcomeForPendingSync ? .deferredSyncThenRebuilt : .rebuiltTransition(reason: fallbackReason)
    }

    private func transitionPresetUsesReservedTempIds(_ preset: TransitionPreset) -> Bool {
        if let playlistId = preset.wledPlaylistId,
           (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains(playlistId) {
            return true
        }
        if let stepIds = preset.wledStepPresetIds,
           stepIds.contains(where: { (temporaryTransitionReservedPresetLower...temporaryTransitionReservedPresetUpper).contains($0) }) {
            return true
        }
        return false
    }

    private func markTransitionPresetSynced(_ preset: TransitionPreset) async {
        await updateTransitionPresetSyncMetadata(preset.id) { stored in
            stored.wledSyncState = .synced
            stored.lastWLEDSyncError = nil
            stored.lastWLEDSyncAt = Date()
        }
    }

    private func markTransitionPresetNeedsMigration(_ preset: TransitionPreset) async {
        await updateTransitionPresetSyncMetadata(preset.id) { stored in
            stored.wledSyncState = .needsMigration
            stored.lastWLEDSyncError = "Uses temporary reserved WLED IDs"
        }
    }

    private func markTransitionPresetPendingSync(_ preset: TransitionPreset, error: String) async {
        await updateTransitionPresetSyncMetadata(preset.id) { stored in
            stored.wledSyncState = .pendingSync
            stored.lastWLEDSyncError = error
        }
    }

    private func markTransitionPresetSyncFailure(_ preset: TransitionPreset, error: String) async {
        await updateTransitionPresetSyncMetadata(preset.id) { stored in
            if stored.wledSyncState != .needsMigration {
                stored.wledSyncState = .syncFailed
            }
            stored.lastWLEDSyncError = error
        }
    }

    private func updateTransitionPresetSyncMetadata(
        _ presetId: UUID,
        mutate: @escaping (inout TransitionPreset) -> Void
    ) async {
        await MainActor.run {
            guard var stored = PresetsStore.shared.transitionPreset(id: presetId) else { return }
            mutate(&stored)
            PresetsStore.shared.updateTransitionPreset(stored)
        }
    }

    func startPlaylist(
        device: WLEDDevice,
        playlistId: Int,
        runTitle: String? = nil,
        expectedDurationSeconds: Double? = nil,
        transitionDeciseconds: Int? = nil,
        runKind: ActiveRunStatus.RunKind = .transition,
        runAutomationId: UUID? = nil,
        assumeStarted: Bool = false,
        strictValidation: Bool = false,
        preferWebSocketFirst: Bool = true,
        debugExpectedStepPresetIds: [Int]? = nil,
        debugExpectedBoundarySeconds: [Double]? = nil
    ) async -> Bool {
        let runId = (runTitle != nil || expectedDurationSeconds != nil) ? UUID() : nil
        func markPlaylistStarted() {
            playlistRunsByDevice.insert(device.id)
        }
        func recordRunIfNeeded() {
            guard runTitle != nil || expectedDurationSeconds != nil else { return }
            let startDate = Date()
            let title = (runTitle?.isEmpty == false) ? runTitle! : "Transition"
            let expectedEnd = (expectedDurationSeconds ?? 0) > 0
                ? startDate.addingTimeInterval(expectedDurationSeconds ?? 0)
                : nil
            activeRunStatus[device.id] = ActiveRunStatus(
                id: runId ?? UUID(),
                deviceId: device.id,
                kind: runKind,
                automationId: runAutomationId,
                title: title,
                startDate: startDate,
                progress: 0.0,
                isCancellable: true,
                expectedEnd: expectedEnd
            )
            runWatchdogs[device.id] = RunWatchdog(
                lastProgressAt: startDate,
                lastProgressValue: 0.0,
                runStartAt: startDate
            )
            startWatchdogTaskIfNeeded()
        }

        if preferWebSocketFirst, webSocketManager.isDeviceConnected(device.id) {
            let wsState = WLEDStateUpdate(
                on: true,
                transitionDeciseconds: transitionDeciseconds,
                ps: playlistId,
                lor: 0
            )
            let wsDispatched = await webSocketManager.sendStateUpdateAwaitingDispatch(
                wsState,
                to: device.id,
                timeout: 0.35
            )
            if wsDispatched {
                #if DEBUG
                print("✅ Playlist WS dispatch for \(device.name): playlistId=\(playlistId)")
                debugPlaylistStateProbe(
                    device: device,
                    playlistId: playlistId,
                    expectedStepPresetIds: debugExpectedStepPresetIds,
                    expectedBoundarySeconds: debugExpectedBoundarySeconds
                )
                #endif
                if assumeStarted || !strictValidation {
                    markPlaylistStarted()
                    recordRunIfNeeded()
                    return true
                }
            } else {
                #if DEBUG
                print("⚠️ Playlist WS dispatch failed for \(device.name): playlistId=\(playlistId), falling back to HTTP")
                #endif
            }
        }

        do {
            let state = try await apiService.applyPlaylist(
                playlistId,
                to: device,
                releaseRealtime: true,
                transitionDeciseconds: transitionDeciseconds
            )
            #if DEBUG
            print("✅ Playlist started for \(device.name): playlistId=\(playlistId)")
            print("🔎 Playlist state for \(device.name): pl=\(state.playlistId.map(String.init) ?? "nil"), ps=\(state.presetId.map(String.init) ?? "nil"), tt=\(state.transitionDeciseconds.map(String.init) ?? "nil")")
            debugPlaylistStateProbe(
                device: device,
                playlistId: playlistId,
                expectedStepPresetIds: debugExpectedStepPresetIds,
                expectedBoundarySeconds: debugExpectedBoundarySeconds
            )
            #endif
            if assumeStarted {
                markPlaylistStarted()
                recordRunIfNeeded()
                return true
            }
            let playlistStepIds: Set<Int>?
            do {
                let playlists = try await apiService.fetchPlaylists(for: device)
                playlistStepIds = playlists
                    .first(where: { $0.id == playlistId })
                    .map { Set($0.presets) }
            } catch {
                playlistStepIds = nil
            }

            var observedPlaylistIds: Set<Int> = []
            var observedPresetIds: Set<Int> = []
            var observedStateFetch = false

            func trackObserved(_ candidate: WLEDState) {
                if let observedPlaylist = candidate.playlistId, observedPlaylist >= 0 {
                    observedPlaylistIds.insert(observedPlaylist)
                }
                if let observedPreset = candidate.presetId, observedPreset >= 0 {
                    observedPresetIds.insert(observedPreset)
                }
            }

            func isConfirmedPlaylistStart(_ candidate: WLEDState) -> Bool {
                if candidate.playlistId == playlistId || candidate.presetId == playlistId {
                    return true
                }
                if let playlistStepIds,
                   let presetId = candidate.presetId,
                   playlistStepIds.contains(presetId) {
                    return true
                }
                return false
            }

            trackObserved(state)
            if isConfirmedPlaylistStart(state) {
                markPlaylistStarted()
                recordRunIfNeeded()
                return true
            }
            if playlistStepIds == nil, !strictValidation {
                markPlaylistStarted()
                recordRunIfNeeded()
                return true
            }

            let verificationAttempts = strictValidation ? 6 : 1
            for attempt in 0..<verificationAttempts {
                let sleepNs: UInt64 = (attempt == 0) ? 500_000_000 : 350_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
                if let fetched = try? await apiService.getState(for: device) {
                    observedStateFetch = true
                    let fetchedState = fetched.state
                    trackObserved(fetchedState)
                    #if DEBUG
                    print("🔎 Playlist fetched state for \(device.name): pl=\(fetchedState.playlistId.map(String.init) ?? "nil"), ps=\(fetchedState.presetId.map(String.init) ?? "nil"), tt=\(fetchedState.transitionDeciseconds.map(String.init) ?? "nil")")
                    #endif
                    if isConfirmedPlaylistStart(fetchedState) {
                        markPlaylistStarted()
                        recordRunIfNeeded()
                        return true
                    }
                }
            }

            if strictValidation, playlistStepIds == nil {
                let observedAnyActiveSelection = observedPlaylistIds.contains(where: { $0 > 0 })
                    || observedPresetIds.contains(where: { $0 > 0 })
                if observedStateFetch && observedAnyActiveSelection {
                    #if DEBUG
                    print("⚠️ Playlist strict validation degraded for \(device.name): metadata unavailable, observed active playlist/preset IDs \(Array(observedPlaylistIds).sorted())/\(Array(observedPresetIds).sorted())")
                    #endif
                    markPlaylistStarted()
                    recordRunIfNeeded()
                    return true
                }
            }

            #if DEBUG
            if strictValidation, playlistStepIds == nil {
                print("⚠️ Strict playlist validation could not confirm start for \(device.name): playlist metadata unavailable")
            }
            #endif

            return false
        } catch {
            playlistRunsByDevice.remove(device.id)
            #if DEBUG
            print("⚠️ Failed to start playlist \(playlistId) for \(device.name): \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func cumulativePlaylistBoundarySeconds(durations: [Int]) -> [Double] {
        guard durations.count > 1 else { return [] }
        var cumulative = 0
        return durations.dropLast().map { duration in
            cumulative += max(0, duration)
            return Double(cumulative) / 10.0
        }
    }

    #if DEBUG
    private func debugPlaylistStateProbe(
        device: WLEDDevice,
        playlistId: Int,
        expectedStepPresetIds: [Int]? = nil,
        expectedBoundarySeconds: [Double]? = nil
    ) {
        var probeDelays: [UInt64] = [1_000_000_000, 3_000_000_000, 8_000_000_000]
        if let expectedBoundarySeconds, !expectedBoundarySeconds.isEmpty {
            let boundaryProbes = expectedBoundarySeconds
                .prefix(6)
                .flatMap { boundary in
                    [
                        max(0.5, boundary - 1.0),
                        boundary,
                        boundary + 1.0
                    ]
                }
                .map { UInt64(($0 * 1_000_000_000).rounded()) }
            probeDelays.append(contentsOf: boundaryProbes)
            probeDelays = Array(Set(probeDelays)).sorted()
        }
        let stepIndexByPreset: [Int: Int] = Dictionary(
            uniqueKeysWithValues: (expectedStepPresetIds ?? []).enumerated().map { ($0.element, $0.offset) }
        )
        var expectedStepStartByPreset: [Int: Double] = [:]
        if let expectedStepPresetIds, !expectedStepPresetIds.isEmpty {
            var starts = Array(repeating: 0.0, count: expectedStepPresetIds.count)
            if let expectedBoundarySeconds {
                for idx in 1..<expectedStepPresetIds.count {
                    starts[idx] = idx - 1 < expectedBoundarySeconds.count ? expectedBoundarySeconds[idx - 1] : starts[idx - 1]
                }
            }
            expectedStepStartByPreset = Dictionary(uniqueKeysWithValues: zip(expectedStepPresetIds, starts))
        }
        Task { [device] in
            var firstSeenAtByPreset: [Int: Double] = [:]
            var divergenceCount = 0
            let expectedPresetIdSet = Set(expectedStepPresetIds ?? [])
            for delay in probeDelays {
                try? await Task.sleep(nanoseconds: delay)
                let seconds = Double(delay) / 1_000_000_000
                if let fetched = try? await apiService.getState(for: device) {
                    let state = fetched.state
                    let observedPlaylistId = state.playlistId
                    let observedPresetId = state.presetId
                    let matchesExpected = observedPlaylistId == playlistId
                        || (observedPresetId != nil && expectedPresetIdSet.contains(observedPresetId!))
                    if !expectedPresetIdSet.isEmpty {
                        if matchesExpected {
                            divergenceCount = 0
                        } else {
                            divergenceCount += 1
                            if divergenceCount >= 2 {
                                await clearStaleTransitionRunIfProbeDiverged(
                                    deviceId: device.id,
                                    expectedPlaylistId: playlistId,
                                    observedPlaylistId: observedPlaylistId,
                                    observedPresetId: observedPresetId
                                )
                            }
                        }
                    }
                    if let presetId = state.presetId,
                       stepIndexByPreset[presetId] != nil {
                        let isFirstSeen = firstSeenAtByPreset[presetId] == nil
                        if isFirstSeen {
                            firstSeenAtByPreset[presetId] = seconds
                        }
                        let idx = stepIndexByPreset[presetId] ?? -1
                        let expectedStart = expectedStepStartByPreset[presetId]
                        let driftText: String
                        if isFirstSeen, let expectedStart {
                            let drift = seconds - expectedStart
                            driftText = " stepIdx=\(idx + 1) expectedStart=\(String(format: "%.1f", expectedStart))s firstSeenDrift≈\(String(format: "%+.1f", drift))s"
                        } else {
                            driftText = " stepIdx=\(idx + 1)"
                        }
                        print("🔎 Playlist probe for \(device.name): t=\(String(format: "%.1f", seconds))s pl=\(state.playlistId.map(String.init) ?? "nil"), ps=\(presetId), tt=\(state.transitionDeciseconds.map(String.init) ?? "nil")\(driftText)")
                    } else {
                        print("🔎 Playlist probe for \(device.name): t=\(String(format: "%.1f", seconds))s pl=\(state.playlistId.map(String.init) ?? "nil"), ps=\(state.presetId.map(String.init) ?? "nil"), tt=\(state.transitionDeciseconds.map(String.init) ?? "nil")")
                    }
                } else {
                    print("⚠️ Playlist probe failed for \(device.name) at t=\(String(format: "%.1f", seconds))s")
                }
            }
        }
    }
    #endif

    private func clearStaleTransitionRunIfProbeDiverged(
        deviceId: String,
        expectedPlaylistId: Int,
        observedPlaylistId: Int?,
        observedPresetId: Int?
    ) async {
        await MainActor.run {
            guard let run = activeRunStatus[deviceId], run.kind == .transition || run.kind == .automation else {
                return
            }
            activeRunStatus.removeValue(forKey: deviceId)
            runWatchdogs.removeValue(forKey: deviceId)
            #if DEBUG
            print("transition.probe_diverged device=\(deviceId) expectedPlaylist=\(expectedPlaylistId) observedPl=\(observedPlaylistId.map(String.init) ?? "nil") observedPs=\(observedPresetId.map(String.init) ?? "nil")")
            print("transition.ui_status_cleared_external_interrupt device=\(deviceId)")
            #endif
        }
    }

    func cleanupTransitionPlaylist(
        device: WLEDDevice,
        queueFallback: Bool = true,
        endReason: TemporaryTransitionEndReason
    ) async {
        if !enableTemporaryPresetStoreBackedTransitions {
            temporaryPlaylistIds.removeValue(forKey: device.id)
            temporaryPresetIds.removeValue(forKey: device.id)
            playlistRunsByDevice.remove(device.id)
            return
        }
        let playlistId = temporaryPlaylistIds[device.id]
        let presetIds = temporaryPresetIds[device.id] ?? []
        guard playlistId != nil || !presetIds.isEmpty else { return }
        await MainActor.run {
            _ = transitionCleanupInProgress.insert(device.id)
        }
        defer {
            Task { @MainActor in
                transitionCleanupInProgress.remove(device.id)
            }
        }
        await TemporaryTransitionCleanupService.shared.requestCleanup(
            device: device,
            endReason: endReason,
            runId: activeRunStatus[device.id]?.id,
            playlistIdHint: playlistId,
            stepPresetIdsHint: presetIds
        )
        await refreshTransitionCleanupPendingCount(for: device.id)
        temporaryPlaylistIds.removeValue(forKey: device.id)
        temporaryPresetIds.removeValue(forKey: device.id)
        playlistRunsByDevice.remove(device.id)
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

    private func sampledStopScalarValues(
        targetPositions: [Double],
        from stops: [GradientStop],
        valuesById: [UUID: Double]?,
        interpolation: GradientInterpolation
    ) -> [Double]? {
        guard !targetPositions.isEmpty, let valuesById, !valuesById.isEmpty else { return nil }
        let sortedStops = stops.sorted { $0.position < $1.position }
        guard !sortedStops.isEmpty else { return nil }
        guard let firstStop = sortedStops.first, let firstValue = valuesById[firstStop.id] else {
            return nil
        }
        var resolvedValues: [Double] = []
        resolvedValues.reserveCapacity(sortedStops.count)
        var lastKnownValue = firstValue
        for stop in sortedStops {
            if let value = valuesById[stop.id] {
                lastKnownValue = value
            }
            resolvedValues.append(lastKnownValue)
        }
        return targetPositions.map { position in
            interpolateScalar(
                stops: sortedStops,
                values: resolvedValues,
                t: position,
                interpolation: interpolation
            )
        }
    }

    private func interpolatedStopScalarMap(
        stepStops: [GradientStop],
        startStops: [GradientStop],
        startValuesById: [UUID: Double]?,
        startInterpolation: GradientInterpolation,
        endStops: [GradientStop],
        endValuesById: [UUID: Double]?,
        endInterpolation: GradientInterpolation,
        t: Double
    ) -> [UUID: Double]? {
        guard !stepStops.isEmpty else { return nil }
        let positions = stepStops.map(\.position)
        let startSamples = sampledStopScalarValues(
            targetPositions: positions,
            from: startStops,
            valuesById: startValuesById,
            interpolation: startInterpolation
        )
        let endSamples = sampledStopScalarValues(
            targetPositions: positions,
            from: endStops,
            valuesById: endValuesById,
            interpolation: endInterpolation
        )
        guard startSamples != nil || endSamples != nil else { return nil }
        let fromSamples = startSamples ?? endSamples!
        let toSamples = endSamples ?? startSamples!
        var result: [UUID: Double] = [:]
        for (index, stop) in stepStops.enumerated() {
            let value = fromSamples[index] + (toSamples[index] - fromSamples[index]) * t
            result[stop.id] = value
        }
        return result
    }

    private func interpolateOptional(_ start: Double?, _ end: Double?, t: Double) -> Double? {
        if let start, let end {
            return start + (end - start) * t
        }
        return start ?? end
    }

    private func isPresetDecodeError(_ error: WLEDAPIError?) -> Bool {
        guard let error else { return false }
        switch error {
        case .decodingError, .invalidResponse:
            return true
        default:
            return false
        }
    }

    private func isCorruptedPresetPayload(_ presets: [WLEDPreset]) -> Bool {
        if presets.isEmpty { return false }
        if presets.count == 1, let only = presets.first {
            return only.id == 0 && only.segment == nil && only.name == "Preset 0"
        }
        return false
    }

    private func shouldRetryBusyError(_ error: Error) -> Bool {
        guard let apiError = error as? WLEDAPIError else { return false }
        switch apiError {
        case .httpError(let statusCode) where statusCode == 503:
            return true
        case .deviceBusy:
            return true
        case .timeout, .deviceOffline, .deviceUnreachable:
            return true
        case .networkError(let underlying as URLError):
            switch underlying.code {
            case .cancelled:
                return false
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        case .networkError:
            return true
        default:
            return false
        }
    }

    private func updateStateWithRetry(
        _ device: WLEDDevice,
        stateUpdate: WLEDStateUpdate,
        context: String,
        maxAttempts: Int = 3
    ) async -> Bool {
        var delaySeconds: Double = 0.15
        for attempt in 1...maxAttempts {
            do {
                _ = try await apiService.updateState(for: device, state: stateUpdate)
                return true
            } catch {
                let canRetry = shouldRetryBusyError(error)
                #if DEBUG
                print("⚠️ \(context) attempt \(attempt) failed for \(device.name): \(error.localizedDescription)")
                #endif
                if canRetry && attempt < maxAttempts {
                    let nanos = UInt64(delaySeconds * 1_000_000_000.0)
                    try? await Task.sleep(nanoseconds: nanos)
                    delaySeconds = min(delaySeconds * 1.6, 0.8)
                    continue
                }
                return false
            }
        }
        return false
    }

    private func waitForPresetWriteIfNeeded(deviceId: String) async {
        let deadline = Date().addingTimeInterval(2.0)
        while presetWriteInProgress.contains(deviceId), Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    func isTransitionCleanupInProgress(for deviceId: String) -> Bool {
        transitionCleanupInProgress.contains(deviceId)
    }

    func transitionDraftSession(for deviceId: String) -> TransitionDraftSession? {
        transitionDraftSessionsByDeviceId[deviceId]
    }

    func setTransitionDraftSession(_ session: TransitionDraftSession?, for deviceId: String) {
        if let session {
            transitionDraftSessionsByDeviceId[deviceId] = session
        } else {
            transitionDraftSessionsByDeviceId.removeValue(forKey: deviceId)
        }
    }

    func updateTransitionDraftSaveUIState(
        deviceId: String,
        isSavingPreset: Bool,
        showSaveSuccess: Bool
    ) {
        guard var session = transitionDraftSessionsByDeviceId[deviceId] else { return }
        session.isSavingPreset = isSavingPreset
        session.showSaveSuccess = showSaveSuccess
        session.updatedAt = Date()
        transitionDraftSessionsByDeviceId[deviceId] = session
    }

    func isTransitionPresetSaveBlocked(for deviceId: String) -> Bool {
        transitionPresetSaveAvailability(for: deviceId) != .ready
    }

    func isTransitionPresetButtonDisabled(for deviceId: String) -> Bool {
        if let status = activeRunStatus[deviceId], status.kind == .transition, status.title == "Loading..." {
            return true
        }
        return false
    }

    func shouldAllowInteractivePresetSaveTap(for deviceId: String) -> Bool {
        !isTransitionPresetButtonDisabled(for: deviceId)
    }

    func transitionPresetSaveBlockReasonDebug(for deviceId: String) -> String? {
        let availability = transitionPresetSaveAvailability(for: deviceId)
        return availability == .ready ? nil : availability.rawValue
    }

    func transitionPresetSaveAvailability(for deviceId: String) -> TransitionPresetSaveAvailability {
        if let status = activeRunStatus[deviceId], status.kind == .transition, status.title == "Loading..." {
            return .blockedLoading
        }
        if enableTemporaryPresetStoreBackedTransitions {
            if transitionCleanupInProgress.contains(deviceId) {
                return .blockedCleanupInProgress
            }
            if (transitionCleanupPendingCountByDeviceId[deviceId] ?? 0) > 0 {
                return .blockedCleanupPending
            }
        }
        if presetWriteInProgress.contains(deviceId) {
            return .blockedPresetWriteInProgress
        }
        if isPresetStoreWritePauseActive(for: deviceId) {
            return .blockedPresetStorePaused
        }
        return .ready
    }

    func refreshTransitionCleanupPendingCount(for deviceId: String) async {
        if !enableTemporaryPresetStoreBackedTransitions {
            await MainActor.run {
                transitionCleanupPendingCountByDeviceId[deviceId] = 0
                transitionCleanupBacklogCountByDeviceId[deviceId] = 0
            }
            return
        }
        let counts = await TemporaryTransitionCleanupService.shared.cleanupCounts(for: deviceId)
        await MainActor.run {
            transitionCleanupPendingCountByDeviceId[deviceId] = counts.blocking
            transitionCleanupBacklogCountByDeviceId[deviceId] = counts.backlog
        }
    }

    private func waitForPresetStoreIdleWithTimeout(deviceId: String, timeout: TimeInterval) async -> Bool {
        let timeoutNs = UInt64(max(0.1, timeout) * 1_000_000_000.0)
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { [apiService] in
                await apiService.waitForPresetStoreIdle(deviceId: deviceId)
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNs)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    func waitForHeavyOpQuiescence(
        deviceId: String,
        timeout: TimeInterval = 15.0
    ) async -> HeavyOpQuiescenceResult {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        var pollCount = 0
        var lastReason = "unknown"
        #if DEBUG
        print("preset_save.wait_quiescence.begin device=\(deviceId)")
        #endif
        while Date() < deadline {
            if pollCount == 0 || pollCount % 3 == 0 {
                await refreshTransitionCleanupPendingCount(for: deviceId)
            }
            pollCount += 1

            if enableTemporaryPresetStoreBackedTransitions {
                if transitionCleanupInProgress.contains(deviceId) {
                    lastReason = "cleanup_in_progress_timeout"
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }

                if (transitionCleanupPendingCountByDeviceId[deviceId] ?? 0) > 0 {
                    lastReason = "cleanup_pending_timeout"
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
            }

            if presetWriteInProgress.contains(deviceId) {
                lastReason = "preset_write_timeout"
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                break
            }
            let idleReady = await waitForPresetStoreIdleWithTimeout(deviceId: deviceId, timeout: min(remaining, 2.0))
            if !idleReady {
                lastReason = "preset_store_idle_timeout"
                continue
            }

            // Final settle before beginning the next heavy operation.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await refreshTransitionCleanupPendingCount(for: deviceId)
            if enableTemporaryPresetStoreBackedTransitions {
                if transitionCleanupInProgress.contains(deviceId) {
                    lastReason = "cleanup_in_progress_timeout"
                    continue
                }
                if (transitionCleanupPendingCountByDeviceId[deviceId] ?? 0) > 0 {
                    lastReason = "cleanup_pending_timeout"
                    continue
                }
            }
            if presetWriteInProgress.contains(deviceId) {
                lastReason = "preset_write_timeout"
                continue
            }

            #if DEBUG
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000.0)
            print("preset_save.wait_quiescence.ready device=\(deviceId) ms=\(elapsedMs)")
            #endif
            return .ready
        }

        #if DEBUG
        print("preset_save.wait_quiescence.timeout device=\(deviceId) reason=\(lastReason)")
        #endif
        return .timedOut(reason: lastReason)
    }

    private func waitForTransitionCleanupIfNeeded(deviceId: String) async {
        if !enableTemporaryPresetStoreBackedTransitions {
            await refreshTransitionCleanupPendingCount(for: deviceId)
            return
        }
        let deadline = Date().addingTimeInterval(8)
        while transitionCleanupInProgress.contains(deviceId), Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        await refreshTransitionCleanupPendingCount(for: deviceId)
    }

    func notePresetStoreDegradedReadable(deviceId: String, message: String) {
        let now = Date()
        let previous = presetStoreHealthByDeviceId[deviceId] ?? .healthy
        if previous != .unsafeWritesPaused {
            presetStoreHealthByDeviceId[deviceId] = .degradedReadable
        }
        lastPresetStoreHealthEventByDeviceId[deviceId] = now
        lastPresetStoreHealthMessageByDeviceId[deviceId] = message
        #if DEBUG
        if previous != presetStoreHealthByDeviceId[deviceId] {
            print("preset_store.health.changed device=\(deviceId) state=degradedReadable")
        }
        #endif
    }

    func notePresetStoreHealthyReadSuccess(deviceId: String) {
        guard !isPresetStoreWritePauseActive(for: deviceId) else { return }
        let previous = presetStoreHealthByDeviceId[deviceId] ?? .healthy
        if previous != .healthy {
            presetStoreHealthByDeviceId[deviceId] = .healthy
            lastPresetStoreHealthEventByDeviceId[deviceId] = Date()
            lastPresetStoreHealthMessageByDeviceId[deviceId] = "healthy-read"
            presetStoreFailureEventsByDeviceId[deviceId] = []
            #if DEBUG
            print("preset_store.health.recovered_to_healthy device=\(deviceId)")
            #endif
        }
    }

    private func recordPresetStoreFailure(deviceId: String, message: String) {
        let now = Date()
        let windowStart = now.addingTimeInterval(-600)
        var events = presetStoreFailureEventsByDeviceId[deviceId] ?? []
        events.append(now)
        events = events.filter { $0 >= windowStart }
        presetStoreFailureEventsByDeviceId[deviceId] = events
        lastPresetStoreHealthEventByDeviceId[deviceId] = now
        lastPresetStoreHealthMessageByDeviceId[deviceId] = message

        if events.count >= 3 {
            let pauseUntil = now.addingTimeInterval(120)
            presetStoreWritePauseUntilByDeviceId[deviceId] = pauseUntil
            let previous = presetStoreHealthByDeviceId[deviceId] ?? .healthy
            presetStoreHealthByDeviceId[deviceId] = .unsafeWritesPaused
            #if DEBUG
            if previous != .unsafeWritesPaused {
                print("preset_store.health.unsafe_writes_paused device=\(deviceId) until=\(pauseUntil)")
            }
            #endif
        } else {
            let previous = presetStoreHealthByDeviceId[deviceId] ?? .healthy
            if previous == .healthy {
                presetStoreHealthByDeviceId[deviceId] = .degradedReadable
            }
            #if DEBUG
            if previous != presetStoreHealthByDeviceId[deviceId] {
                print("preset_store.health.degraded_readable device=\(deviceId)")
            }
            #endif
        }
    }

    private func markPresetStoreHealthyWriteSuccess(deviceId: String) {
        presetStoreFailureEventsByDeviceId[deviceId] = []
        presetStoreWritePauseUntilByDeviceId.removeValue(forKey: deviceId)
        let previous = presetStoreHealthByDeviceId[deviceId] ?? .healthy
        presetStoreHealthByDeviceId[deviceId] = .healthy
        lastPresetStoreHealthEventByDeviceId[deviceId] = Date()
        lastPresetStoreHealthMessageByDeviceId[deviceId] = "healthy"
        #if DEBUG
        if previous != .healthy {
            print("preset_store.health.recovered_to_healthy device=\(deviceId)")
        }
        #endif
    }

    private func isPresetStoreWritePaused(for deviceId: String) -> Bool {
        if let pauseUntil = presetStoreWritePauseUntilByDeviceId[deviceId] {
            if Date() < pauseUntil {
                return true
            }
            presetStoreWritePauseUntilByDeviceId.removeValue(forKey: deviceId)
            if presetStoreHealthByDeviceId[deviceId] == .unsafeWritesPaused {
                presetStoreHealthByDeviceId[deviceId] = .degradedReadable
            }
        }
        return false
    }

    private func isPresetStoreWritePauseActive(for deviceId: String) -> Bool {
        guard let pauseUntil = presetStoreWritePauseUntilByDeviceId[deviceId] else { return false }
        return Date() < pauseUntil
    }

    private func noteControlWriteSuccess(deviceId: String) {
        let now = Date()
        recentControlWriteSuccessAtByDeviceId[deviceId] = now
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices[index].isOnline = true
            devices[index].lastSeen = now
        }
    }

    func isPowerTogglePending(for deviceId: String) -> Bool {
        pendingToggles[deviceId] != nil
    }

    func awaitPowerToggleSettlement(for device: WLEDDevice, targetState: Bool, timeout: TimeInterval = 2.5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isPowerTogglePending(for: device.id), getCurrentPowerState(for: device.id) == targetState {
                return true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        await refreshDeviceState(device)
        return getCurrentPowerState(for: device.id) == targetState
    }

    private func classifyTransitionPresetSaveBusyFailure(deviceId: String) -> String? {
        if isPresetStoreWritePaused(for: deviceId) {
            return "paused"
        }
        let availability = transitionPresetSaveAvailability(for: deviceId)
        if availability != .ready {
            return availability.rawValue
        }
        let message = (lastPresetStoreHealthMessageByDeviceId[deviceId] ?? "").lowercased()
        if message.contains("503") || message.contains("service unavailable") {
            return "503"
        }
        if message.contains("timed out") || message.contains("timeout") {
            return "timeout"
        }
        return nil
    }

    @discardableResult
    private func enqueueDeferredPresetStoreSyncItem(
        deviceId: String,
        kind: PendingPresetStoreSyncItem.Kind,
        transitionPresetSnapshot: TransitionPreset? = nil,
        error: String?
    ) -> PendingPresetStoreSyncItem {
        var item = PendingPresetStoreSyncItem(
            deviceId: deviceId,
            kind: kind,
            transitionPresetSnapshot: transitionPresetSnapshot
        )
        item.lastError = error
        var items = pendingPresetStoreSyncItemsByDeviceId[deviceId] ?? []
        items.append(item)
        pendingPresetStoreSyncItemsByDeviceId[deviceId] = items
        return item
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
    func cancelActiveRun(
        for device: WLEDDevice,
        releaseRealtimeOverride: Bool = true,
        force: Bool = false,
        endReason: TemporaryTransitionEndReason = .cancelledByUser
    ) async {
        let activeRun = await MainActor.run {
            activeRunStatus[device.id]
        }
        if !force,
           let lockUntil = transitionCancelLockUntil[device.id],
           Date() < lockUntil,
           let run = activeRun,
           run.kind == .transition {
            #if DEBUG
            print("⏳ Skipping cancel for \(device.name) (transition lock active)")
            #endif
            return
        }
        if endReason == .cancelledByManualInput {
            if enableTemporaryPresetStoreBackedTransitions {
                await TemporaryTransitionCleanupService.shared.deferInteractiveConflictingCleanup(
                    for: device.id,
                    until: Date().addingTimeInterval(4.0)
                )
            }
            // Lock only after we decide to perform this cancel so the first
            // manual cancel is not skipped.
            lockTransitionCancel(for: device.id, seconds: 1.2)
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
            let rgb = rgbArrayWithOptionalWhite(nativeInfo.targetColorRGB, device: device)
            let segment = SegmentUpdate(
                id: 0,
                col: [rgb]
            )
            let immediateState = WLEDStateUpdate(
                on: true,
                bri: nativeInfo.targetBrightness,
                seg: [segment],
                transitionDeciseconds: 0  // No transition - jump immediately to target
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

        // Clear run UI immediately so cancel feels responsive while cleanup continues.
        await MainActor.run {
            activeRunStatus.removeValue(forKey: device.id)
            runWatchdogs.removeValue(forKey: device.id)
            transitionCancelLockUntil.removeValue(forKey: device.id)
            pendingFinalStates.removeValue(forKey: device.id)
        }

        let shouldStopPlaylist = await MainActor.run {
            hasKnownActiveRun(for: device.id)
        }
        if shouldStopPlaylist {
            if await stopPlaylistViaWebSocketIfConnected(device) {
                await MainActor.run {
                    playlistRunsByDevice.remove(device.id)
                    markPlaylistStoppedLocally(deviceId: device.id)
                }
                #if DEBUG
                print("🛑 Explicitly stopped active playlist for \(device.name) during cancel")
                #endif
            } else {
                do {
                    let state = try await apiService.stopPlaylist(on: device)
                    updateDevice(device.id, with: state)
                    await MainActor.run {
                        playlistRunsByDevice.remove(device.id)
                        markPlaylistStoppedLocally(deviceId: device.id)
                    }
                    #if DEBUG
                    print("🛑 Explicitly stopped active playlist for \(device.name) during cancel")
                    #endif
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to stop playlist during cancel for \(device.name): \(error.localizedDescription)")
                    #endif
                }
            }
        }

        let temporaryCleanupHints = await MainActor.run { () -> (Int?, [Int]) in
            (temporaryPlaylistIds[device.id], temporaryPresetIds[device.id] ?? [])
        }
        if enableTemporaryPresetStoreBackedTransitions,
           (temporaryCleanupHints.0 != nil || !temporaryCleanupHints.1.isEmpty) {
            await MainActor.run { () -> Void in
                transitionCleanupInProgress.insert(device.id)
            }
            await TemporaryTransitionCleanupService.shared.requestCleanup(
                device: device,
                endReason: endReason,
                runId: runId,
                playlistIdHint: temporaryCleanupHints.0,
                stepPresetIdsHint: temporaryCleanupHints.1
            )
            await refreshTransitionCleanupPendingCount(for: device.id)
            await MainActor.run { () -> Void in
                transitionCleanupInProgress.remove(device.id)
            }
        }
        
        // Release real-time override if needed
        if releaseRealtimeOverride {
            await apiService.releaseRealtimeOverride(for: device)
        }
        
        // Clear active run status
        await MainActor.run {
            playlistRunsByDevice.remove(device.id)
            temporaryPlaylistIds.removeValue(forKey: device.id)
            temporaryPresetIds.removeValue(forKey: device.id)
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

            if runStatus.title == "Loading..." {
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
                    if let finalState = pendingFinalStates[deviceId],
                       finalState.runId == runStatus.id,
                       let device = devices.first(where: { $0.id == deviceId }) {
                        await applyGradientStopsAcrossStrip(
                            device,
                            stops: finalState.gradient.stops,
                            ledCount: totalLEDCount(for: device),
                            stopTemperatures: finalState.stopTemperatures,
                            stopWhiteLevels: finalState.stopWhiteLevels,
                            disableActiveEffect: true,
                            segmentId: finalState.segmentId,
                            interpolation: finalState.gradient.interpolation,
                            brightness: finalState.brightness,
                            on: true,
                            forceNoPerCallTransition: true,
                            releaseRealtimeOverride: false,
                            userInitiated: false,
                            preferSegmented: true,
                            forceSegmentedOnly: finalState.forceSegmentedOnly
                        )
                        pendingFinalStates.removeValue(forKey: deviceId)
                    }
                    if let device = devices.first(where: { $0.id == deviceId }) {
                        await restoreTransitionDefaultIfNeeded(for: device, runId: runStatus.id)
                    }
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
                    await cancelActiveRun(for: device, endReason: .cancelledByWatchdog)
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
            hasLiveGradientHydration.remove(deviceId)
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
        endStopWhiteLevels: [UUID: Double]? = nil,
        forceSegmentedOnly: Bool = false,
        origin: SyncOrigin = .user
    ) async {
        await waitForTransitionCleanupIfNeeded(deviceId: device.id)
        await cancelActiveTransitionIfNeeded(for: device)
        setTransitionDuration(durationSec, for: device.id)
        await runAutomationTransition(
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
            segmentId: 0,
            forceSegmentedOnly: forceSegmentedOnly
        )
        let payload = TransitionSyncPayload(
            from: from,
            aBrightness: aBrightness,
            to: to,
            bBrightness: bBrightness,
            durationSec: durationSec,
            startStopTemperatures: startStopTemperatures,
            startStopWhiteLevels: startStopWhiteLevels,
            endStopTemperatures: endStopTemperatures,
            endStopWhiteLevels: endStopWhiteLevels,
            forceSegmentedOnly: forceSegmentedOnly
        )
        await propagateIfNeeded(source: device, payload: .transitionStart(payload), origin: origin)
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

    func captureSceneSnapshot(for device: WLEDDevice, name: String) -> Scene {
        let effectState = currentEffectState(for: device, segmentId: 0)
        let isEffectEnabled = effectState.isEnabled && effectState.effectId != 0
        let baseHex = device.currentColor.toHex()
        let fallbackStops = [
            GradientStop(position: 0.0, hexColor: baseHex),
            GradientStop(position: 1.0, hexColor: baseHex)
        ]
        let stops: [GradientStop] = {
            if isEffectEnabled, let effectStops = effectGradientStops(for: device.id), !effectStops.isEmpty {
                return effectStops
            }
            if let gradientStops = gradientStops(for: device.id), !gradientStops.isEmpty {
                return gradientStops
            }
            return fallbackStops
        }()
        let presetId = (device.state?.presetId ?? 0) > 0 ? device.state?.presetId : nil
        let playlistId = (device.state?.playlistId ?? 0) > 0 ? device.state?.playlistId : nil
        let resolvedPresetName = presetId.flatMap { presetName(for: $0, device: device) }
        let resolvedPlaylistName = playlistId.flatMap { playlistName(for: $0, device: device) }

        return Scene(
            name: name,
            deviceId: device.id,
            brightness: device.brightness,
            primaryStops: stops,
            transitionEnabled: false,
            secondaryStops: nil,
            durationSec: nil,
            aBrightness: nil,
            bBrightness: nil,
            effectsEnabled: isEffectEnabled,
            effectId: isEffectEnabled ? effectState.effectId : nil,
            paletteId: isEffectEnabled ? effectState.paletteId : nil,
            speed: isEffectEnabled ? effectState.speed : nil,
            intensity: isEffectEnabled ? effectState.intensity : nil,
            presetId: presetId,
            presetName: resolvedPresetName,
            playlistId: playlistId,
            playlistName: resolvedPlaylistName
        )
    }

    func applyScene(_ scene: Scene, to device: WLEDDevice, userInitiated: Bool = true) async {
        // 1) Cancel any running streams
        await cancelStreaming(for: device)

        // 2) Playlists and presets take priority
        if let playlistId = scene.playlistId, playlistId > 0 {
            markUserInteraction(device.id)
            let title = scene.playlistName ?? scene.name
            _ = await startPlaylist(device: device, playlistId: playlistId, runTitle: title, runKind: .applying)
            return
        }
        if let presetId = scene.presetId, presetId > 0 {
            _ = await applyPresetId(presetId, to: device)
            return
        }

        // 3) Brightness first (bri-only)
        await updateDeviceBrightness(device, brightness: scene.brightness, userInitiated: userInitiated)

        // 4) Effects
        if scene.effectsEnabled {
            // If base colors are available, set them via segment update first
            if let baseA = scene.primaryStops.first?.color.toRGBArray() {
                let rgb = rgbArrayWithOptionalWhite(baseA, device: device)
                let seg = SegmentUpdate(id: 0, col: [rgb])
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

        // 5) Transition vs static
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

    func playlists(for device: WLEDDevice) -> [WLEDPlaylist] {
        playlistsCache[device.id] ?? []
    }
    
    func isLoadingPresets(for device: WLEDDevice) -> Bool {
        presetLoadingStates[device.id] ?? false
    }

    func isLoadingPlaylists(for device: WLEDDevice) -> Bool {
        playlistLoadingStates[device.id] ?? false
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
            recordPresetNameMap(for: device.id, presets: presets)
            updatePresetSlotStatus(for: device, presets: presets)
            clearError()
        } catch {
            // If presets.json is unreadable, don't block save; keep local cache.
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
        presetLoadingStates[device.id] = false
    }

    func loadPlaylists(for device: WLEDDevice, force: Bool = false) async {
        if playlistsCache[device.id] != nil && !force {
            if hasPendingPlaylistRename(for: device.id) {
                let didMutate = await retryPendingPlaylistRenames(for: device)
                if didMutate, let refreshed = try? await apiService.fetchPlaylists(for: device) {
                    playlistsCache[device.id] = refreshed
                    recordPlaylistNameMap(for: device.id, playlists: refreshed)
                }
            }
            return
        }
        playlistLoadingStates[device.id] = true
        do {
            var playlists = try await apiService.fetchPlaylists(for: device)
            recordPlaylistNameMap(for: device.id, playlists: playlists)
            if hasPendingPlaylistRename(for: device.id) {
                let didMutate = await retryPendingPlaylistRenames(for: device)
                if didMutate, let refreshed = try? await apiService.fetchPlaylists(for: device) {
                    playlists = refreshed
                    recordPlaylistNameMap(for: device.id, playlists: playlists)
                }
            }
            playlistsCache[device.id] = playlists
            clearError()
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
        playlistLoadingStates[device.id] = false
    }
    
    func refreshPresets(for device: WLEDDevice) async {
        await loadPresets(for: device, force: true)
    }

    func refreshPlaylists(for device: WLEDDevice) async {
        await loadPlaylists(for: device, force: true)
    }

    func refreshPresetsIfModified(for device: WLEDDevice) async {
        do {
            let response = try await apiService.getState(for: device)
            await handlePresetModificationIfNeeded(response, device: device)
        } catch {
            // Ignore modification check failures
        }
    }

    private func handlePresetModificationIfNeeded(_ response: WLEDResponse, device: WLEDDevice) async {
        guard let pmt = response.info.fs?.presetLastModification else { return }
        let previous = presetModificationTimes[device.id]
        if previous != pmt {
            presetModificationTimes[device.id] = pmt
            await loadPresets(for: device, force: true)
            await loadPlaylists(for: device, force: true)
        }
    }

    private func recordPresetNameMap(for deviceId: String, presets: [WLEDPreset]) {
        let map = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.name) })
        presetNameMapsByDevice[deviceId] = map
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        var updated = devices[index]
        updated.presetNamesById = map
        devices[index] = updated
        deviceStateCache[deviceId] = (updated, Date())
        Task.detached(priority: .background) {
            await CoreDataManager.shared.saveDevice(updated)
        }
    }

    private func recordPlaylistNameMap(for deviceId: String, playlists: [WLEDPlaylist]) {
        let map = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0.name) })
        playlistNameMapsByDevice[deviceId] = map
        guard let index = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        var updated = devices[index]
        updated.playlistNamesById = map
        devices[index] = updated
        deviceStateCache[deviceId] = (updated, Date())
        Task.detached(priority: .background) {
            await CoreDataManager.shared.saveDevice(updated)
        }
    }

    private func hasPendingPlaylistRename(for deviceId: String) -> Bool {
        pendingPlaylistRenames.contains(where: { $0.deviceId == deviceId })
    }

    private func loadPendingPlaylistRenameQueue() {
        guard let data = UserDefaults.standard.data(forKey: pendingPlaylistRenameQueueKey) else {
            pendingPlaylistRenames = []
            pendingPlaylistRenameIdsByDevice = [:]
            return
        }
        if let queue = try? JSONDecoder().decode([PendingPlaylistRename].self, from: data) {
            pendingPlaylistRenames = queue
        } else {
            pendingPlaylistRenames = []
        }
        rebuildPendingPlaylistRenameIndex()
    }

    private func savePendingPlaylistRenameQueue() {
        if let data = try? JSONEncoder().encode(pendingPlaylistRenames) {
            UserDefaults.standard.set(data, forKey: pendingPlaylistRenameQueueKey)
        }
    }

    private func rebuildPendingPlaylistRenameIndex() {
        var index: [String: Set<Int>] = [:]
        for entry in pendingPlaylistRenames {
            index[entry.deviceId, default: []].insert(entry.playlistId)
        }
        pendingPlaylistRenameIdsByDevice = index
    }

    private func enqueuePendingPlaylistRename(deviceId: String, playlistId: Int, desiredName: String) {
        let trimmed = desiredName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = pendingPlaylistRenames.firstIndex(where: {
            $0.deviceId == deviceId && $0.playlistId == playlistId
        }) {
            pendingPlaylistRenames[index].desiredName = trimmed
            pendingPlaylistRenames[index].lastAttemptAt = Date()
        } else {
            pendingPlaylistRenames.append(
                PendingPlaylistRename(
                    deviceId: deviceId,
                    playlistId: playlistId,
                    desiredName: trimmed,
                    retries: 0,
                    lastAttemptAt: Date()
                )
            )
        }
        savePendingPlaylistRenameQueue()
        rebuildPendingPlaylistRenameIndex()
    }

    private func clearPendingPlaylistRename(deviceId: String, playlistId: Int) {
        let originalCount = pendingPlaylistRenames.count
        pendingPlaylistRenames.removeAll {
            $0.deviceId == deviceId && $0.playlistId == playlistId
        }
        guard pendingPlaylistRenames.count != originalCount else { return }
        savePendingPlaylistRenameQueue()
        rebuildPendingPlaylistRenameIndex()
    }

    private func shouldDeferPlaylistRename(for deviceId: String) -> Bool {
        if playlistRunsByDevice.contains(deviceId) {
            return true
        }
        guard let run = activeRunStatus[deviceId] else {
            return false
        }
        switch run.kind {
        case .transition, .automation, .effect:
            return true
        default:
            return false
        }
    }

    private func applyLocalPlaylistRename(deviceId: String, playlistId: Int, desiredName: String) {
        guard var playlists = playlistsCache[deviceId],
              let index = playlists.firstIndex(where: { $0.id == playlistId }) else {
            return
        }
        let current = playlists[index]
        playlists[index] = WLEDPlaylist(
            id: current.id,
            name: desiredName,
            presets: current.presets,
            duration: current.duration,
            transition: current.transition,
            repeat: current.repeat,
            endPresetId: current.endPresetId,
            shuffle: current.shuffle
        )
        playlistsCache[deviceId] = playlists
        recordPlaylistNameMap(for: deviceId, playlists: playlists)
    }

    private func retryPendingPlaylistRenames(for device: WLEDDevice) async -> Bool {
        let pending = pendingPlaylistRenames.filter { $0.deviceId == device.id }
        guard !pending.isEmpty else { return false }
        var didMutateRemoteState = false
        for entry in pending {
            do {
                try await apiService.renamePlaylistRecord(id: entry.playlistId, name: entry.desiredName, device: device)
                clearPendingPlaylistRename(deviceId: device.id, playlistId: entry.playlistId)
                didMutateRemoteState = true
            } catch {
                guard let index = pendingPlaylistRenames.firstIndex(where: { $0.id == entry.id }) else { continue }
                pendingPlaylistRenames[index].retries += 1
                pendingPlaylistRenames[index].lastAttemptAt = Date()
                if pendingPlaylistRenames[index].retries >= pendingPlaylistRenameRetryLimit {
                    pendingPlaylistRenames.remove(at: index)
                }
            }
        }
        savePendingPlaylistRenameQueue()
        rebuildPendingPlaylistRenameIndex()
        return didMutateRemoteState
    }
    
    @discardableResult
    func applyPresetId(
        _ presetId: Int,
        to device: WLEDDevice,
        transitionDeciseconds: Int? = nil,
        preferWebSocketFirst: Bool = true,
        markInteraction: Bool = true
    ) async -> Bool {
        if markInteraction {
            markUserInteraction(device.id)
        }
        if preferWebSocketFirst, webSocketManager.isDeviceConnected(device.id) {
            let wsState = WLEDStateUpdate(
                on: true,
                transitionDeciseconds: transitionDeciseconds,
                ps: presetId,
                lor: 0
            )
            let wsDispatched = await webSocketManager.sendStateUpdateAwaitingDispatch(
                wsState,
                to: device.id,
                timeout: 0.35
            )
            if wsDispatched {
                #if DEBUG
                print("✅ Preset WS dispatch for \(device.name): presetId=\(presetId)")
                #endif
                clearError()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let self,
                          let refreshed = self.devices.first(where: { $0.id == device.id }) else { return }
                    await self.refreshDeviceState(refreshed)
                }
                return true
            }
            #if DEBUG
            print("⚠️ Preset WS dispatch failed for \(device.name): presetId=\(presetId), falling back to HTTP")
            #endif
        }
        do {
            let state = try await apiService.applyPreset(presetId, to: device, transitionDeciseconds: transitionDeciseconds)
            updateDevice(device.id, with: state)
            clearError()
            return true
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func applyPreset(_ preset: WLEDPreset, to device: WLEDDevice, transitionDeciseconds: Int? = nil) async {
        _ = await applyPresetId(
            preset.id,
            to: device,
            transitionDeciseconds: transitionDeciseconds,
            preferWebSocketFirst: true,
            markInteraction: true
        )
    }

    private func stopPlaylistViaWebSocketIfConnected(_ device: WLEDDevice) async -> Bool {
        guard webSocketManager.isDeviceConnected(device.id) else {
            return false
        }
        let wsState = WLEDStateUpdate(pl: -1, lor: 0)
        let wsDispatched = await webSocketManager.sendStateUpdateAwaitingDispatch(
            wsState,
            to: device.id,
            timeout: 0.35
        )
        if wsDispatched {
            #if DEBUG
            print("✅ Playlist WS stop dispatch for \(device.name)")
            #endif
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self,
                      let refreshed = self.devices.first(where: { $0.id == device.id }) else { return }
                await self.refreshDeviceState(refreshed)
            }
        } else {
            #if DEBUG
            print("⚠️ Playlist WS stop dispatch failed for \(device.name), falling back to HTTP")
            #endif
        }
        return wsDispatched
    }

    @discardableResult
    func deletePresetRecord(_ presetId: Int, for device: WLEDDevice) async -> Bool {
        markUserInteraction(device.id)
        do {
            _ = try await apiService.deletePreset(id: presetId, device: device)
            await refreshPresets(for: device)
            await refreshPlaylists(for: device)
            clearError()
            return true
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func deletePlaylist(_ playlist: WLEDPlaylist, for device: WLEDDevice) async {
        markUserInteraction(device.id)
        do {
            _ = try await apiService.deletePlaylist(id: playlist.id, device: device)
            clearPendingPlaylistRename(deviceId: device.id, playlistId: playlist.id)
            await refreshPlaylists(for: device)
            await refreshPresets(for: device)
            clearError()
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
        }
    }

    func renamePresetRecord(_ presetId: Int, to name: String, for device: WLEDDevice) async -> Bool {
        markUserInteraction(device.id)
        do {
            try await apiService.renamePresetRecord(id: presetId, name: name, device: device)
            await refreshPresets(for: device)
            clearError()
            return true
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func renamePlaylistRecord(_ playlistId: Int, to name: String, for device: WLEDDevice) async -> Bool {
        markUserInteraction(device.id)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if shouldDeferPlaylistRename(for: device.id) {
            enqueuePendingPlaylistRename(deviceId: device.id, playlistId: playlistId, desiredName: trimmed)
            applyLocalPlaylistRename(deviceId: device.id, playlistId: playlistId, desiredName: trimmed)
            #if DEBUG
            print("playlist.rename.deferred_active_run device=\(device.id) playlistId=\(playlistId)")
            #endif
            clearError()
            return true
        }
        do {
            try await apiService.renamePlaylistRecord(id: playlistId, name: trimmed, device: device)
            clearPendingPlaylistRename(deviceId: device.id, playlistId: playlistId)
            await refreshPlaylists(for: device)
            await refreshPresets(for: device)
            clearError()
            return true
        } catch {
            enqueuePendingPlaylistRename(deviceId: device.id, playlistId: playlistId, desiredName: trimmed)
            applyLocalPlaylistRename(deviceId: device.id, playlistId: playlistId, desiredName: trimmed)
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func stopPlaylist(for device: WLEDDevice) async -> Bool {
        markUserInteraction(device.id)
        if await stopPlaylistViaWebSocketIfConnected(device) {
            playlistRunsByDevice.remove(device.id)
            clearError()
            return true
        }
        do {
            let state = try await apiService.stopPlaylist(on: device)
            updateDevice(device.id, with: state)
            playlistRunsByDevice.remove(device.id)
            clearError()
            return true
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func savePlaylistRecord(_ request: WLEDPlaylistSaveRequest, for device: WLEDDevice) async -> Bool {
        markUserInteraction(device.id)
        do {
            _ = try await apiService.savePlaylist(request, to: device)
            await refreshPlaylists(for: device)
            await refreshPresets(for: device)
            clearError()
            return true
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func testPlaylistRecord(_ request: WLEDPlaylistSaveRequest, for device: WLEDDevice) async -> Bool {
        markUserInteraction(device.id)
        do {
            let state = try await apiService.testPlaylist(request, on: device)
            updateDevice(device.id, with: state)
            clearError()
            return true
        } catch {
            let mappedError = mapToWLEDError(error, device: device)
            presentError(mappedError)
            return false
        }
    }

    func duplicatePlaylist(_ playlist: WLEDPlaylist, for device: WLEDDevice, name: String? = nil) async -> Bool {
        guard let nextId = nextPlaylistId(for: device) else {
            presentError(.apiError(message: "No available playlist IDs. Free up a preset/playlist slot first."))
            return false
        }
        let duplicateName = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "\(playlist.name) Copy"
        let request = WLEDPlaylistSaveRequest(
            id: nextId,
            name: duplicateName,
            ps: playlist.presets,
            dur: playlist.duration,
            transition: playlist.transition,
            repeat: playlist.repeat,
            endPresetId: playlist.endPresetId,
            shuffle: playlist.shuffle
        )
        return await savePlaylistRecord(request, for: device)
    }

    func nextPlaylistId(for device: WLEDDevice) -> Int? {
        let usedIds = Set(presets(for: device).map(\.id))
        for id in 1...maxWLEDPresetSlots where !usedIds.contains(id) {
            return id
        }
        return nil
    }

    func playlistName(for playlistId: Int, device: WLEDDevice) -> String? {
        playlistNameMapsByDevice[device.id]?[playlistId]
            ?? device.playlistNamesById?[playlistId]
    }

    func presetName(for presetId: Int, device: WLEDDevice) -> String? {
        presetNameMapsByDevice[device.id]?[presetId]
            ?? device.presetNamesById?[presetId]
    }

    func isPlaylistRenamePending(_ playlistId: Int, for device: WLEDDevice) -> Bool {
        pendingPlaylistRenameIdsByDevice[device.id]?.contains(playlistId) ?? false
    }
    
    func savePreset(name: String, quickLoadTag: String? = nil, for device: WLEDDevice, presetId: Int? = nil) async {
        markUserInteraction(device.id)
        presetLoadingStates[device.id] = true
        do {
            let existingIds = Set(presets(for: device).map { $0.id })
            let targetId = presetId ?? nextPresetId(for: device)
            let isNew = !existingIds.contains(targetId)
            if isNew && !hasPresetCapacity(for: device, requiredSlots: 1) {
                updatePresetSlotStatus(for: device)
                presentError(.apiError(message: "Preset storage nearly full. Free up presets before saving a new one."))
                presetLoadingStates[device.id] = false
                return
            }
            let response = try await apiService.getState(for: device)
            await handlePresetModificationIfNeeded(response, device: device)
            let stateUpdate = stateUpdate(from: response.state, device: device)
            let sanitizedQuickLoad = quickLoadTag?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let quickLoadValue = sanitizedQuickLoad?.isEmpty == false
                ? String(sanitizedQuickLoad!.prefix(8))
                : nil
            let request = WLEDPresetSaveRequest(
                id: targetId,
                name: name,
                quickLoad: quickLoadValue,
                state: stateUpdate,
                includeBrightness: true,
                saveSegmentBounds: true,
                selectedSegmentsOnly: false,
                transitionDeciseconds: response.state.transitionDeciseconds ?? 7
            )
            try await apiService.savePreset(request, to: device)
            let presets = try await apiService.fetchPresets(for: device)
            presetsCache[device.id] = presets
            recordPresetNameMap(for: device.id, presets: presets)
            updatePresetSlotStatus(for: device, presets: presets)
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

    func effectMultiStopGradientStops(for deviceId: String) -> [GradientStop]? {
        if let stops = latestMultiStopEffectGradients[deviceId], !stops.isEmpty {
            return stops
        }
        if let persisted = loadPersistedMultiStopEffectGradient(for: deviceId), !persisted.isEmpty {
            latestMultiStopEffectGradients[deviceId] = persisted
            return persisted
        }
        return nil
    }
    
    func updateEffectGradient(_ gradient: LEDGradient, for device: WLEDDevice) {
        let stops = gradient.stops.sorted { $0.position < $1.position }
        latestEffectGradientStops[device.id] = stops
        persistEffectGradient(stops, for: device.id)
        if isMultiStopGradient(stops) {
            latestMultiStopEffectGradients[device.id] = stops
            persistMultiStopEffectGradient(stops, for: device.id)
        }
    }
    
    private func persistEffectGradient(_ stops: [GradientStop], for deviceId: String) {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        UserDefaults.standard.set(data, forKey: effectGradientDefaultsPrefix + deviceId)
    }

    private func persistMultiStopEffectGradient(_ stops: [GradientStop], for deviceId: String) {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        UserDefaults.standard.set(data, forKey: effectGradientMultiDefaultsPrefix + deviceId)
    }
    
    private func loadPersistedEffectGradient(for deviceId: String) -> [GradientStop]? {
        guard let data = UserDefaults.standard.data(forKey: effectGradientDefaultsPrefix + deviceId) else { return nil }
        return try? JSONDecoder().decode([GradientStop].self, from: data)
    }

    private func loadPersistedMultiStopEffectGradient(for deviceId: String) -> [GradientStop]? {
        guard let data = UserDefaults.standard.data(forKey: effectGradientMultiDefaultsPrefix + deviceId) else { return nil }
        return try? JSONDecoder().decode([GradientStop].self, from: data)
    }

    private func isMultiStopGradient(_ stops: [GradientStop]) -> Bool {
        let unique = Set(stops.map { $0.hexColor.uppercased() })
        return unique.count > 1
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

extension DeviceControlViewModel {
    struct PresetSlotAvailability: Equatable {
        let used: Int
        let remaining: Int
        let reserve: Int
        let available: Int
        let total: Int
    }

    private func updatePresetSlotStatus(for device: WLEDDevice, presets: [WLEDPreset]? = nil) {
        let used = presets?.count ?? presetsCache[device.id]?.count ?? 0
        let total = maxWLEDPresetSlots
        let remaining = max(0, total - used)
        let reserve = presetSlotReserve
        let available = max(0, remaining - reserve)
        presetSlotStatus[device.id] = PresetSlotAvailability(
            used: used,
            remaining: remaining,
            reserve: reserve,
            available: available,
            total: total
        )
    }

    private func hasPresetCapacity(for device: WLEDDevice, requiredSlots: Int, presets: [WLEDPreset]? = nil) -> Bool {
        let used = presets?.count ?? presetsCache[device.id]?.count ?? 0
        let remaining = max(0, maxWLEDPresetSlots - used)
        let available = max(0, remaining - presetSlotReserve)
        return available >= requiredSlots
    }

    func presetSlotAvailability(for device: WLEDDevice) -> PresetSlotAvailability? {
        presetSlotStatus[device.id]
    }

    func requiredPresetSlotsForTransition(durationSeconds: Double, device: WLEDDevice) -> Int {
        let start = LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFFFFF"),
            GradientStop(position: 1.0, hexColor: "FFFFFF")
        ])
        let end = LEDGradient(stops: [
            GradientStop(position: 0.0, hexColor: "FFA000"),
            GradientStop(position: 1.0, hexColor: "FFA000")
        ])
        return planTransitionPlaylist(
            durationSec: durationSeconds,
            startGradient: start,
            endGradient: end,
            startBrightness: 128,
            endBrightness: 128,
            context: .persistentAutomation,
            device: device
        ).slotsRequired
    }
}
