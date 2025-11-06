import Foundation
import Combine

final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published var tick: Int = 0
    private var timer: Timer?

    private init() {
        start()
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
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
}


