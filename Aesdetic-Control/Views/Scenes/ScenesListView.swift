import SwiftUI

struct ScenesListView: View {
    @ObservedObject var store = ScenesStore.shared
    @EnvironmentObject var viewModel: DeviceControlViewModel
    let device: WLEDDevice

    var body: some View {
        List {
            ForEach(store.scenes.filter { $0.deviceId == device.id }) { scene in
                HStack {
                    VStack(alignment: .leading) {
                        Text(scene.name).font(.headline)
                        Text("Saved: \(scene.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Apply") {
                        Task { await viewModel.applyScene(scene, to: device) }
                    }
                    .sensorySuccess(trigger: scene.id)
                }
            }
            .onDelete { idx in
                idx.map { store.scenes.filter { $0.deviceId == device.id }[$0].id }.forEach { store.remove($0) }
            }
        }
        .navigationTitle("Scenes")
    }
}


