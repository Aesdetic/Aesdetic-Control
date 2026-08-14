import Testing
@testable import Aesdetic_Control

@Suite
struct WLEDProvisioningCredentialsTests {
    @Test func validatesSecuredAndOpenCredentials() {
        var credentials = WLEDHomeWiFiCredentials(ssid: "Home", password: "", isOpenNetwork: false)
        #expect(!credentials.isValid)

        credentials.password = "password123"
        #expect(credentials.isValid)

        credentials.password = ""
        credentials.isOpenNetwork = true
        #expect(credentials.isValid)
    }

    @Test func validatesSSIDAndPasswordLengths() {
        #expect(!WLEDHomeWiFiCredentials(ssid: "", password: "password123", isOpenNetwork: false).isValid)
        #expect(!WLEDHomeWiFiCredentials(ssid: String(repeating: "a", count: 33), password: "password123", isOpenNetwork: false).isValid)
        #expect(!WLEDHomeWiFiCredentials(ssid: "Home", password: "short", isOpenNetwork: false).isValid)
        #expect(WLEDHomeWiFiCredentials(ssid: "Home", password: String(repeating: "a", count: 64), isOpenNetwork: false).isValid)
        #expect(!WLEDHomeWiFiCredentials(ssid: "Home", password: String(repeating: "a", count: 65), isOpenNetwork: false).isValid)
        #expect(WLEDHomeWiFiCredentials(ssid: " Home ", password: "password123", isOpenNetwork: false).isValid)
    }

    @Test func matchesSSIDExactlyAndSupportsHiddenNetworks() {
        let networks = [
            WiFiNetwork(ssid: "Home", signalStrength: -40, security: "WPA2", channel: 1, bssid: nil),
            WiFiNetwork(ssid: "Guest", signalStrength: -50, security: "Open", channel: 6, bssid: nil)
        ]

        #expect(WLEDHomeWiFiCredentials(ssid: "Home", password: "password123").matchingNetwork(in: networks)?.ssid == "Home")
        #expect(WLEDHomeWiFiCredentials(ssid: "home", password: "password123").matchingNetwork(in: networks) == nil)
        #expect(WLEDHomeWiFiCredentials(ssid: "Hidden", password: "password123").matchingNetwork(in: networks) == nil)
    }

    @Test func clearsPasswordWithoutChangingNetwork() {
        var credentials = WLEDHomeWiFiCredentials(ssid: "Home", password: "password123", isOpenNetwork: false)
        credentials.clearPassword()

        #expect(credentials.ssid == "Home")
        #expect(credentials.password.isEmpty)
        #expect(!credentials.isOpenNetwork)
    }
}
