import Testing
@testable import Aesdetic_Control

struct WLEDFirmwareUpdateServiceTests {
    @Test("Native firmware installation is fail-closed by default")
    func nativeInstallationDefaultsOff() {
        #expect(WLEDFirmwareUpdateService.nativeInstallationEnabled == false)
    }

    @Test("Bundled catalog only selects the approved ESP32 WLED build")
    func bundledCatalogSelectsOnlyApprovedProfile() {
        let supported = WLEDFirmwareIdentity(
            version: "0.15.3",
            architecture: "esp32",
            brand: "WLED",
            product: "FOSS",
            repository: nil,
            buildID: nil
        )
        let unsupported = WLEDFirmwareIdentity(
            version: "0.15.3",
            architecture: "esp32-s3",
            brand: "WLED",
            product: "FOSS",
            repository: "wled/WLED",
            buildID: nil
        )

        let profile = WLEDFirmwareCatalog.bundled.profile(for: supported)
        #expect(profile?.assetName(for: "16.0.0") == "WLED_16.0.0_ESP32.bin")
        #expect(WLEDFirmwareCatalog.bundled.profile(for: unsupported) == nil)
    }

    @Test("Customer-facing update phases stay free of OTA terminology")
    func customerFacingProgressIsSimple() {
        #expect(WLEDFirmwareUpdatePhase.preflight.customerMessage == "Preparing your lamp")
        #expect(WLEDFirmwareUpdatePhase.installing.customerMessage == "Installing supported software")
        #expect(WLEDFirmwareUpdatePhase.checking.customerMessage == "Checking everything is ready")
    }

    @Test("Approved baseline skips WLED 0.16 and newer")
    func baselineComparison() {
        #expect(VersionComparator.compare("0.15.3", WLEDFirmwareUpdateService.approvedBaselineVersion) == .orderedAscending)
        #expect(VersionComparator.compare("16.0.0", WLEDFirmwareUpdateService.approvedBaselineVersion) == .orderedSame)
        #expect(VersionComparator.compare("16.0.1", WLEDFirmwareUpdateService.approvedBaselineVersion) == .orderedDescending)
    }
}
