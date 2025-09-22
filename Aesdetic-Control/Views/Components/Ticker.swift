import Foundation
import Combine
import UIKit

final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published var tick: Int = 0
    private var timer: Timer?

    private init() {
        start()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tick &+= 1
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func appDidEnterBackground() {
        stop()
    }

    @objc private func appDidBecomeActive() {
        start()
    }
}


