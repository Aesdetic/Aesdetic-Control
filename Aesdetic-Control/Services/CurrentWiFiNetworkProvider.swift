import CoreLocation
import Foundation
import NetworkExtension
import os.log

@MainActor
protocol CurrentWiFiNetworkProviding {
    func currentSSID(requestPermissionIfNeeded: Bool) async -> String?
}

@MainActor
final class CurrentWiFiNetworkProvider: NSObject, CurrentWiFiNetworkProviding, @preconcurrency CLLocationManagerDelegate {
    static let shared = CurrentWiFiNetworkProvider()

    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "com.aesdetic.control", category: "CurrentWiFi")
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func currentSSID(requestPermissionIfNeeded: Bool) async -> String? {
        if requestPermissionIfNeeded {
            let status = locationManager.authorizationStatus
            if status == .notDetermined {
                logger.info("Requesting location authorization for current Wi-Fi identification")
                await withCheckedContinuation { continuation in
                    authorizationContinuation = continuation
                    locationManager.requestWhenInUseAuthorization()
                }
            }

            guard locationManager.authorizationStatus == .authorizedWhenInUse ||
                    locationManager.authorizationStatus == .authorizedAlways else {
                return nil
            }

            if locationManager.accuracyAuthorization == .reducedAccuracy {
                await withCheckedContinuation { continuation in
                    locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WiFiSetup") { _ in
                        continuation.resume()
                    }
                }
            }
        }

        return await NEHotspotNetwork.fetchCurrent()?.ssid
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }
}
