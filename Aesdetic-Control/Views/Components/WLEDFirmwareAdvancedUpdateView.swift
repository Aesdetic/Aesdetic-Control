import SwiftUI

/// Deliberately technical update surface. Everyday customers only see the
/// Aesdetic-recommended software action in Settings.
struct WLEDFirmwareAdvancedUpdateView: View {
    let device: WLEDDevice

    @Environment(\.dismiss) private var dismiss
    @State private var assessment: WLEDFirmwareUpdateAssessment?
    @State private var phase: WLEDFirmwareUpdatePhase?
    @State private var message: String?
    @State private var showInstallConfirmation = false
    @State private var showManualUpdater = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Advanced update options")
                        .font(AppTypography.style(.title2, weight: .semibold))
                        .settingsForegroundStyle(.primary)

                    Text("Use this only when you deliberately want to manage WLED software yourself.")
                        .font(AppTypography.style(.subheadline))
                        .foregroundColor(.white.opacity(0.84))

                    content
                }
                .padding(20)
            }
            .background(Color.black.opacity(0.88).ignoresSafeArea())
            .navigationTitle("WLED Software")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .task { await checkForLatest() }
        .confirmationDialog(
            "Install latest official WLED?",
            isPresented: $showInstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("I Understand & Install", role: .destructive) {
                Task { await installLatest() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Aesdetic Control is tested with WLED 0.16. Newer official WLED releases may change functionality, settings, or compatibility with this app. Continue only if you understand these risks. Keep your phone on the same Wi-Fi network and do not remove power during the update.")
        }
        .sheet(isPresented: $showManualUpdater) {
            WLEDWebConfigView(url: URL(string: "http://\(device.ipAddress)/update")!)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let phase {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(phase.customerMessage)
                    .font(AppTypography.style(.body, weight: .semibold))
                    .settingsForegroundStyle(.primary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.12))
            .cornerRadius(12)
        } else if let assessment {
            switch assessment {
            case .upToDate(let current, let target):
                Text("WLED \(current) is already current for the latest official release (\(target)).")
                    .foregroundColor(.white.opacity(0.9))
            case .available(let current, let target, _):
                Text("Current: WLED \(current)\nLatest official release: WLED \(target)")
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(.white.opacity(0.9))
                Button {
                    showInstallConfirmation = true
                } label: {
                    SettingsButton(title: "Install Latest Official WLED", icon: "arrow.up.circle.fill")
                }
            case .manualUpdateRequired(let reason), .unavailable(let reason):
                Text(reason)
                    .font(AppTypography.style(.subheadline))
                    .foregroundColor(.white.opacity(0.9))
                Button { showManualUpdater = true } label: {
                    SettingsButton(title: "Open Manual WLED Update", icon: "arrow.up.circle")
                }
            }
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Checking latest official WLED…")
                    .foregroundColor(.white.opacity(0.9))
            }
        }

        if let message {
            Text(message)
                .font(AppTypography.style(.caption))
                .foregroundColor(.orange.opacity(0.95))
        }

        Button { Task { await checkForLatest() } } label: {
            SettingsButton(title: "Check Again", icon: "arrow.clockwise")
        }
        .disabled(phase != nil)
    }

    private func checkForLatest() async {
        guard phase == nil else { return }
        message = nil
        assessment = nil
        do {
            assessment = try await WLEDFirmwareUpdateService.shared.latestOfficialAssessment(for: device)
        } catch {
            assessment = .unavailable("Could not check for the latest official WLED release.")
            message = error.localizedDescription
        }
    }

    private func installLatest() async {
        message = nil
        do {
            _ = try await WLEDFirmwareUpdateService.shared.installLatestOfficialUpdate(for: device) { updatePhase in
                phase = updatePhase
            }
            phase = nil
            await checkForLatest()
            message = "The lamp has restarted with the latest official WLED software."
        } catch {
            phase = nil
            message = error.localizedDescription
        }
    }
}
