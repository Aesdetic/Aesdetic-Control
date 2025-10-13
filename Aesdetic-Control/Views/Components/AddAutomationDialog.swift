import SwiftUI

struct AddAutomationDialog: View {
    @Environment(\.dismiss) var dismiss
    let device: WLEDDevice
    let scenes: [Scene]
    var onSave: (Automation) -> Void

    @State private var automationName: String = ""
    @State private var selectedSceneId: UUID? = nil
    @State private var selectedTime: Date = Date()
    @State private var selectedWeekdays: [Bool] = Array(repeating: false, count: 7)
    
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Automation Details") {
                    TextField("Automation Name", text: $automationName)
                        .listRowBackground(Color.white.opacity(0.1))
                        .foregroundColor(.white)

                    Picker("Scene", selection: $selectedSceneId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(scenes.filter { $0.deviceId == device.id }) { scene in
                            Text(scene.name).tag(scene.id as UUID?)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                }
                .headerProminence(.increased)

                Section("Schedule") {
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .listRowBackground(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .datePickerStyle(.graphical)

                    VStack(alignment: .leading) {
                        Text("Repeat")
                            .foregroundColor(.white)
                        HStack {
                            ForEach(DayOfWeek.allCases, id: \.self) { day in
                                DayToggle(day: day, isSelected: selectedWeekdays.contains { _ in false }) { isSelected in
                                    if let index = DayOfWeek.allCases.firstIndex(of: day) {
                                        selectedWeekdays[index] = isSelected
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .headerProminence(.increased)

                Button("Save Automation") {
                    saveAutomation()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowBackground(Color.clear)
                .disabled(automationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedSceneId == nil || !selectedWeekdays.contains(true))
            }
            .background(Color.black.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Add Automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func saveAutomation() {
        guard let sceneId = selectedSceneId else { return }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: selectedTime)

        let newAutomation = Automation(
            name: automationName,
            time: timeString,
            weekdays: selectedWeekdays,
            sceneId: sceneId,
            deviceId: device.id
        )
        onSave(newAutomation)
    }
}

enum DayOfWeek: String, Codable, CaseIterable, Hashable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

struct DayToggle: View {
    let day: DayOfWeek
    let isSelected: Bool
    var onToggle: (Bool) -> Void

    var body: some View {
        Button(action: {
            onToggle(!isSelected)
        }) {
            Text(day.shortName)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 30, height: 30)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(15)
        }
    }
}