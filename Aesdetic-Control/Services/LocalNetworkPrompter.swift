import Foundation
import Network
import os.log

/// Forces the Local Network permission prompt by starting a short-lived Bonjour browse.
@available(iOS 14.0, *)
final class LocalNetworkPrompter {
    static let shared = LocalNetworkPrompter()

    private let logger = Logger(subsystem: "com.aesdetic.control", category: "LocalNetwork")
    private var browsers: [NWBrowser] = []
    private var hasTriggeredThisSession = false
    private let triggerTimeout: TimeInterval = 2.0

    private init() {}

    func trigger() {
        guard !hasTriggeredThisSession else { return }
        hasTriggeredThisSession = true

        let types = ["_wled._tcp"]
        let queue = DispatchQueue(label: "local.network.prompt")

        browsers = types.map { type in
            let parameters = NWParameters.tcp
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: parameters)

            browser.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let error):
                    self?.logger.error("Local network prompt browse failed: \(error.localizedDescription)")
                case .ready:
                    self?.logger.info("Local network prompt browse ready for \(type)")
                default:
                    break
                }
            }

            browser.start(queue: queue)
            return browser
        }

        // Stop browsing shortly after to avoid keeping resources open.
        DispatchQueue.main.asyncAfter(deadline: .now() + triggerTimeout) { [weak self] in
            self?.browsers.forEach { $0.cancel() }
            self?.browsers.removeAll()
        }
    }
}
