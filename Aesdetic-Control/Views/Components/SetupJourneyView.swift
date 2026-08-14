import SwiftUI

struct SetupJourneyView: View {
    @ObservedObject var coordinator: SetupJourneyCoordinator
    @ObservedObject var viewModel: DeviceControlViewModel
    let deviceTargetFrames: [String: CGRect]
    let onRevealDevice: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppBackground(includePhoto: coordinator.entryContext != .firstLaunch)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
                .ignoresSafeArea()

            stageContent
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.24), value: stageIdentity)
        .accessibilityIdentifier("setup-journey")
    }

    @ViewBuilder
    private var stageContent: some View {
        switch coordinator.stage {
        case .welcome:
            welcomeContent
        case .provisioning(let id, let purpose):
            AddDeviceProvisioningFlowView(
                viewModel: viewModel,
                purpose: purpose,
                onCancel: coordinator.cancelCurrentStage,
                onBeginProductSetup: coordinator.handleProvisioningResult
            )
            .id(id)
        case .productSetup(let id, let result):
            ProductSetupFlowView(
                device: result.device,
                provisionedSSID: result.wifiConfiguredDuringFlow ? result.configuredSSID : nil,
                onClose: coordinator.cancelCurrentStage,
                onComplete: coordinator.handleProductSetupCompletion,
                allowsManualClose: false,
                presentationStyle: .journey
            )
            .environmentObject(viewModel)
            .id(id)
        case .success(let completion):
            SetupJourneySuccessView(
                completion: completion,
                targetFrame: deviceTargetFrames[completion.canonicalDeviceID],
                reduceMotion: reduceMotion,
                onRevealDevice: onRevealDevice,
                onFinish: coordinator.dismiss
            )
        case nil:
            EmptyView()
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("aesdetic_logo_wordmark")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .accessibilityLabel("Aesdetic")

            VStack(spacing: 10) {
                Text("Welcome to Aesdetic")
                    .font(AppTypography.style(.largeTitle, weight: .bold))
                    .foregroundColor(primaryText)
                    .multilineTextAlignment(.center)

                Text("Set up your first device to get started.")
                    .font(AppTypography.style(.body))
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("Set Up My Device", action: coordinator.beginFirstDeviceSetup)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("first-launch-set-up-device")

                Button("Set Up Later", action: coordinator.skipFirstLaunch)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("first-launch-set-up-later")
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
    }

    private var stageIdentity: String {
        switch coordinator.stage {
        case .welcome: return "welcome"
        case .provisioning(let id, _): return "provisioning-\(id)"
        case .productSetup(let id, _): return "product-\(id)"
        case .success(let completion): return "success-\(completion.canonicalDeviceID)"
        case nil: return "none"
        }
    }

    private var primaryText: Color {
        Color.primary
    }

    private var secondaryText: Color {
        Color.secondary
    }
}

private struct SetupJourneySuccessView: View {
    let completion: ProductSetupCompletion
    let targetFrame: CGRect?
    let reduceMotion: Bool
    let onRevealDevice: (String) -> Void
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPreparingCompletion = false
    @State private var isCompleting = false

    var body: some View {
        GeometryReader { proxy in
            let destination = localDestination(in: proxy)

            ZStack {
                VStack(spacing: 22) {
                    Spacer()

                    Image("aesdetic_logo_wordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 180)
                        .opacity(isCompleting ? 0 : 1)

                    Text("Your Aesdetic device is ready")
                        .font(AppTypography.style(.largeTitle, weight: .bold))
                        .foregroundColor(primaryText)
                        .multilineTextAlignment(.center)
                        .opacity(isCompleting ? 0 : 1)

                    Color.clear.frame(height: 190)

                    VStack(spacing: 5) {
                        Text(completion.deviceName)
                            .font(AppTypography.style(.title2, weight: .semibold))
                            .foregroundColor(primaryText)
                        Text(completion.roomName)
                            .font(AppTypography.style(.subheadline))
                            .foregroundColor(secondaryText)
                    }
                    .opacity(isCompleting ? 0 : 1)

                    Button("Start Using Device") {
                        completeJourney()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 420)
                    .disabled(isPreparingCompletion)
                    .opacity(isCompleting ? 0 : 1)
                    .accessibilityIdentifier("setup-success-start-using")

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)

                Image(completion.productImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: isCompleting && destination != nil ? min(destination!.width * 0.42, 150) : 180,
                        height: isCompleting && destination != nil ? min(destination!.height * 0.72, 170) : 180
                    )
                    .shadow(color: successColor.opacity(isCompleting ? 0.18 : 0.55), radius: isCompleting ? 10 : 30)
                    .position(
                        x: isCompleting ? (destination?.midX ?? proxy.size.width / 2) : proxy.size.width / 2,
                        y: isCompleting ? (destination?.midY ?? proxy.size.height * 0.72) : proxy.size.height * 0.49
                    )
                    .opacity(reduceMotion && isCompleting ? 0 : 1)
                    .accessibilityHidden(true)
            }
            .opacity(reduceMotion && isCompleting ? 0 : 1)
        }
    }

    private func completeJourney() {
        guard !isPreparingCompletion else { return }
        isPreparingCompletion = true
        onRevealDevice(completion.canonicalDeviceID)
        Task { @MainActor in
            // Let the Devices tab lay out and publish the matching card frame.
            try? await Task.sleep(nanoseconds: 120_000_000)
            let duration = reduceMotion ? 0.25 : 0.72
            withAnimation(.easeInOut(duration: duration)) {
                isCompleting = true
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            onFinish()
        }
    }

    private func localDestination(in proxy: GeometryProxy) -> CGRect? {
        guard let targetFrame else { return nil }
        let rootFrame = proxy.frame(in: .global)
        return targetFrame.offsetBy(dx: -rootFrame.minX, dy: -rootFrame.minY)
    }

    private var successColor: Color {
        Color(hex: completion.initialColorHex)
    }

    private var primaryText: Color {
        AppTheme.tokens(for: colorScheme).textPrimary
    }

    private var secondaryText: Color {
        AppTheme.tokens(for: colorScheme).textSecondary
    }
}
