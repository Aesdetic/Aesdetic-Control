import SwiftUI

struct RootContainer: View {
    var body: some View {
        ZStack {
            AppBackground()
            ContentView()
        }
        .preferredColorScheme(.dark)
    }
}


