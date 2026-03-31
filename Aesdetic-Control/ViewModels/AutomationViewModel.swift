//
//  AutomationViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine
import UIKit

@MainActor
class AutomationViewModel: ObservableObject {
    
    // MARK: - Singleton
    static let shared = AutomationViewModel()
    
    @Published var automations: [Automation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var lastDeviceImportAt: Date?
    private let importThrottleSeconds: TimeInterval = 8
    
    private init() {
        // Use the AutomationStore for data management
        AutomationStore.shared.$automations
            .assign(to: \.automations, on: self)
            .store(in: &cancellables)

        DeviceControlViewModel.shared.$devices
            .map { devices in
                devices
                    .filter { !$0.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .map(\.id)
                    .sorted()
            }
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] deviceIds in
                guard let self, !deviceIds.isEmpty else { return }
                Task { await self.refreshAutomations(force: true) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshAutomations() }
            }
            .store(in: &cancellables)
    }
    
    func refreshAutomations(force: Bool = false) async {
        if isLoading { return }
        if !force,
           let lastDeviceImportAt,
           Date().timeIntervalSince(lastDeviceImportAt) < importThrottleSeconds {
            return
        }
        isLoading = true
        errorMessage = nil

        await AutomationStore.shared.importOnDeviceAutomationsFromDevices()
        lastDeviceImportAt = Date()
        isLoading = false
    }
    
    func toggleAutomation(_ automation: Automation) {
        var updatedAutomation = automation
        updatedAutomation.enabled.toggle()
        AutomationStore.shared.update(updatedAutomation)
    }
    
    // MARK: - Computed Properties
    
    var enabledAutomations: [Automation] {
        automations.filter { $0.enabled }
    }
} 
