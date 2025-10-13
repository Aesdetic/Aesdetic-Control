//
//  AutomationViewModel.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation
import Combine

@MainActor
class AutomationViewModel: ObservableObject {
    
    // MARK: - Singleton
    static let shared = AutomationViewModel()
    
    @Published var automations: [Automation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Use the AutomationStore for data management
        AutomationStore.shared.$automations
            .assign(to: \.automations, on: self)
            .store(in: &cancellables)
    }
    
    func refreshAutomations() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // The AutomationStore handles the data, so we just need to trigger a refresh
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