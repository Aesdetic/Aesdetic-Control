import SwiftUI

struct EditPresetNameDialog: View {
    let currentName: String
    let onSave: (String) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var editedName: String = ""
    @State private var showDeleteConfirmation = false
    
    init(currentName: String, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Preset Name Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preset Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter preset name", text: $editedName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !editedName.isEmpty {
                                saveName()
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Delete") {
                            showDeleteConfirmation = true
                        }
                        .buttonStyle(DeleteButtonStyle())
                        
                        Button("Save") {
                            saveName()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(editedName.isEmpty || editedName == currentName)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Preset")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Delete Preset", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this preset? This action cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            editedName = currentName
            // Auto-focus text field after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveName() {
        guard !editedName.isEmpty && editedName != currentName else { return }
        onSave(editedName)
        dismiss()
    }
}

struct DeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.red.opacity(0.15))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}



