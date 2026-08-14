import Testing
@testable import Aesdetic_Control

@Suite
struct WLEDNetworkConfigurationTests {
    @Test func normalizesMDNSLikeWLEDWebUI() {
        let configuration = WLEDNetworkConfiguration(
            mdnsName: " https://aesdetic.test.local/ "
        )

        #expect(configuration.normalizedMDNSName == "aesdetic.test")
        #expect(configuration.isValid)
    }

    @Test func validatesWriteOnlyAPPasswordReplacement() {
        var configuration = WLEDNetworkConfiguration(
            apPassword: "",
            apPasswordConfigured: true
        )

        #expect(configuration.isValid)

        configuration.apPassword = "short"
        #expect(!configuration.isValid)
        #expect(configuration.validationIssues.contains("Fallback hotspot password must be empty to preserve it or 8-63 characters to replace it."))

        configuration.apPassword = "newpass123"
        #expect(configuration.isValid)
    }

    @Test func locksWLEDAPBehaviorAndTXPowerOptions() {
        #expect(WLEDNetworkConfiguration.apBehaviorLabel(for: 0) == "No connection after boot")
        #expect(WLEDNetworkConfiguration.apBehaviorLabel(for: 3) == "Never (not recommended)")
        #expect(WLEDNetworkConfiguration.txPowerLabel(for: 78) == "19.5 dBm")

        var configuration = WLEDNetworkConfiguration(apBehavior: 9, txPower: 99)
        #expect(!configuration.isValid)
        #expect(configuration.validationIssues.contains("Fallback hotspot behavior must match one of WLED's AP opens options."))
        #expect(configuration.validationIssues.contains("WiFi transmit power must match one of WLED's supported TX power options."))

        configuration.apBehavior = 4
        configuration.txPower = 52
        #expect(configuration.isValid)
    }
}
