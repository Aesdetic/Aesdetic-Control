import SwiftUI

struct SaveSceneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = ScenesStore.shared
    let device: WLEDDevice

    // Inputs captured from current panes (inject from parent in a fuller setup)
    var capture: () -> Scene

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Scene name", text: $name)
                }
            }
            .navigationTitle("Save Scene")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var scene = capture()
                        if !name.trimmingCharacters(in: .whitespaces).isEmpty { scene.name = name }
                        store.add(scene)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}


