import SwiftUI

/// Subtle backdrop blur + dim layer used behind setup flows.
struct SetupBackdropBlur: View {
    var blurOpacity: Double = 0.44
    var dimOpacity: Double = 0.03

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(blurOpacity)

            Rectangle()
                .fill(Color.black.opacity(dimOpacity))
        }
        .ignoresSafeArea()
    }
}
