import SwiftUI

// Lightweight compatibility helpers for SwiftUI sensory feedback (iOS 17+)
extension View {
    @ViewBuilder
    func sensorySelection<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17, *) {
            self.sensoryFeedback(.selection, trigger: trigger)
        } else {
            self
        }
    }

    @ViewBuilder
    func sensorySuccess<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17, *) {
            self.sensoryFeedback(.success, trigger: trigger)
        } else {
            self
        }
    }
}


