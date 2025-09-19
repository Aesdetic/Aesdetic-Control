import SwiftUI

struct ColorWheelSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var workingColor: Color
    let onDone: (Color) -> Void
    var onRemoveStop: (() -> Void)? = nil
    var canRemove: Bool = false

    init(initial: Color, canRemove: Bool = false, onRemoveStop: (() -> Void)? = nil, onDone: @escaping (Color) -> Void) {
        _workingColor = State(initialValue: initial)
        self.canRemove = canRemove
        self.onRemoveStop = onRemoveStop
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ColorPicker("", selection: $workingColor)
                    .labelsHidden()
                    .frame(height: 160)

                if canRemove, let remove = onRemoveStop {
                    Button(role: .destructive) {
                        remove()
                        dismiss()
                    } label: {
                        Label("Remove Stop", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(workingColor)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


