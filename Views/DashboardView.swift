struct EnhancedDeviceOverviewCard: View {
    let device: WLEDDevice
    @State private var isPressed = false
    
    var body: some View {
        NavigationLink(destination: DeviceDetailView(device: device)) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with device icon and status
                HStack {
                    ZStack {
                        Circle()
                            .fill(device.isOnline ? 
                                LinearGradient(colors: [device.currentColor.opacity(0.3), device.currentColor.opacity(0.1)], 
                                             startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)], 
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: device.productType.systemImage)
                            .foregroundColor(device.isOnline ? device.currentColor : .gray)
                            .font(.title2)
                            .fontWeight(.medium)
                    }
                    .scaleEffect(isPressed ? 0.95 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Connection status indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(device.isOnline ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                                .scaleEffect(device.isOnline ? 1.0 : 0.8)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), 
                                         value: device.isOnline)
                            
                            Text(device.isOnline ? "Online" : "Offline")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(device.isOnline ? .green : .gray)
                        }
                        
                        // Last seen information
                        if !device.isOnline, let lastSeen = device.lastSeen {
                            Text("Last seen \(relativeDateString(from: lastSeen))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(device.name), \(device.isOnline ? "online" : "offline")")
                .accessibilityHint("Tap to view device details and controls")
                
                // Device name and info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(device.isOnline ? .primary : .secondary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    
                    HStack {
                        if device.isOnline {
                            Label("\(device.brightness)%", systemImage: "sun.max.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Brightness \(device.brightness) percent")
                        } else {
                            Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .accessibilityLabel("Device unavailable")
                        }
                        
                        Spacer()
                        
                        // IP Address for quick reference
                        Text(device.ipAddress)
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                            .accessibilityLabel("IP address \(device.ipAddress)")
                    }
                }
                
                // Enhanced color and brightness indicator
                if device.isOnline {
                    HStack(spacing: 8) {
                        // Color preview with gradient
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [device.currentColor, device.currentColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                            )
                            .accessibilityLabel("Current color")
                        
                        // Brightness percentage with icon
                        HStack(spacing: 2) {
                            Image(systemName: device.brightness > 50 ? "sun.max.fill" : "sun.min.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(device.brightness)%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Brightness \(device.brightness) percent")
                    }
                    .transition(.opacity.combined(with: .scale))
                } else {
                    // Offline state indicator
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
                            )
                        
                        Image(systemName: "moon.fill")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.clear)
                    .shadow(
                        color: device.isOnline ? 
                            device.currentColor.opacity(0.15) : 
                            Color.black.opacity(0.05),
                        radius: isPressed ? 2 : 4,
                        x: 0,
                        y: isPressed ? 1 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        device.isOnline ? 
                            device.currentColor.opacity(0.2) : 
                            Color.gray.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "View Details") {
            // Navigation handled by NavigationLink
        }
    }
    
    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Empty State Component

struct EmptyDevicesPrompt: View {
    var body: some View {
        VStack(spacing: 20) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "lightbulb.2")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("No devices found")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                
                Text("Make sure your WLED devices are connected to the same WiFi network and powered on.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                NavigationLink(destination: DeviceControlView()) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Discover Devices")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .accessibilityLabel("Go to device discovery")
                .accessibilityHint("Navigate to find and connect WLED devices")
                
                Button(action: {
                    // Add manual device entry functionality
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Manually")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .accessibilityLabel("Add device manually")
                .accessibilityHint("Enter device information manually")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.clear)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

struct AutomationOverviewSection: View {
    let automations: [Automation]
    let onToggle: (Automation) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Automations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Enhanced status summary with counts by state
                HStack(spacing: 8) {
                    if !activeAutomations.isEmpty {
                        StatusBadge(
                            count: activeAutomations.count,
                            label: "active",
                            color: .blue,
                            systemImage: "play.circle.fill"
                        )
                    }
                    
                    if !pendingAutomations.isEmpty {
                        StatusBadge(
                            count: pendingAutomations.count,
                            label: "pending",
                            color: .orange,
                            systemImage: "clock.fill"
                        )
                    }
                    
                    if enabledAutomations.isEmpty {
                        Text("No active automations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            // Next upcoming automation highlight
            if let nextAutomation = nextUpcomingAutomation {
                NextAutomationCard(automation: nextAutomation)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(automations) { automation in
                    EnhancedAutomationOverviewCard(
                        automation: automation,
                        onToggle: { onToggle(automation) }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    // Computed properties for easy access
    private var activeAutomations: [Automation] {
        automations.filter { $0.currentState == .active }
    }
    
    private var pendingAutomations: [Automation] {
        automations.filter { $0.currentState == .pending && $0.isEnabled }
    }
    
    private var enabledAutomations: [Automation] {
        automations.filter { $0.isEnabled }
    }
    
    private var nextUpcomingAutomation: Automation? {
        pendingAutomations
            .compactMap { automation -> (Automation, Date)? in
                guard let nextDate = automation.nextExecutionDate else { return nil }
                return (automation, nextDate)
            }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }
}

struct StatusBadge: View {
    let count: Int
    let label: String
    let color: Color
    let systemImage: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .accessibilityLabel("\(count) \(label) \(count == 1 ? "automation" : "automations")")
    }
}

struct NextAutomationCard: View {
    let automation: Automation
    @State private var timeRemaining: String = ""
    
    var body: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Next: \(automation.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(timeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(automation.timeString)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateTimeRemaining()
        }
        .onAppear {
            updateTimeRemaining()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next automation: \(automation.name) at \(automation.timeString), \(timeRemaining)")
    }
    
    private func updateTimeRemaining() {
        if let timeUntil = automation.timeUntilNextExecution, timeUntil > 0 {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            
            if let nextDate = automation.nextExecutionDate {
                timeRemaining = formatter.localizedString(for: nextDate, relativeTo: Date())
            } else {
                timeRemaining = "Soon"
            }
        } else {
            timeRemaining = "Starting soon"
        }
    }
}

struct EnhancedAutomationOverviewCard: View {
    let automation: Automation
    let onToggle: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HStack {
                // State indicator icon
                ZStack {
                    Circle()
                        .fill(automation.currentState.color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: automation.currentState.systemImage)
                        .foregroundColor(automation.currentState.color)
                        .font(.system(size: 16, weight: .medium))
                        .scaleEffect(automation.currentState == .active ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), 
                                 value: automation.currentState == .active)
                }
                .accessibilityLabel("\(automation.currentState.displayName) status")
                
                VStack(alignment: .leading, spacing: 4) {
                    // Automation name and type
                    HStack {
                        Text(automation.name)
                            .font(.headline)
                            .foregroundColor(automation.isEnabled ? .primary : .secondary)
                            .accessibilityAddTraits(.isHeader)
                        
                        Spacer()
                        
                        // Automation type badge
                        Text(automation.automationType.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    }
                    
                    // Status description and time info
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(automation.statusDescription)
                                .font(.caption)
                                .foregroundColor(automation.currentState.color)
                                .fontWeight(.medium)
                            
                            // Device count and duration
                            HStack(spacing: 8) {
                                Label("\(automation.devices.count)", systemImage: "lightbulb.2.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Label("\(Int(automation.duration / 60))m", systemImage: "timer")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Toggle switch
                        Toggle("", isOn: .init(
                            get: { automation.isEnabled },
                            set: { _ in onToggle() }
                        ))
                        .labelsHidden()
                        .scaleEffect(0.8)
                        .accessibilityLabel("Toggle \(automation.name)")
                    }
                }
            }
            .padding()
            .background(Color.clear)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            
            // Progress bar for active automations
            if automation.currentState == .active && automation.progress > 0 {
                VStack(spacing: 8) {
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Progress")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fontWeight(.medium)
                            
                            Text(automation.progressDescription)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        // Countdown timer
                        if let timeRemaining = automation.timeUntilCompletion, timeRemaining > 0 {
                            CountdownTimer(timeRemaining: timeRemaining)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Progress bar
                    ProgressView(value: automation.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(y: 0.6)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .accessibilityLabel("Progress: \(Int(automation.progress * 100)) percent complete")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Error message for failed automations
            if automation.currentState == .failed,
               let lastResult = automation.lastExecutionResult,
               let errorMessage = lastResult.errorMessage {
                VStack(spacing: 8) {
                    Divider()
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.clear)
        .cornerRadius(12)
        .shadow(radius: automation.currentState == .active ? 3 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(automation.currentState.color.opacity(0.3), 
                       lineWidth: automation.currentState == .active ? 1.5 : 0)
        )
        .onTapGesture {
            // Handle card tap for navigation to automation details
        }
        .onLongPressGesture(minimumDuration: 0.1) {
            // Visual feedback only
        } onPressingChanged: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = pressing
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(automation.name) automation, \(automation.currentState.displayName)")
        .accessibilityHint("Double tap to view details, use toggle to enable or disable")
    }
}

struct CountdownTimer: View {
    let timeRemaining: TimeInterval
    @State private var displayTime: String = ""
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption2)
                .foregroundColor(.blue)
            
            Text(displayTime)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateDisplayTime()
        }
        .onAppear {
            updateDisplayTime()
        }
        .accessibilityLabel("Time remaining: \(displayTime)")
    }
    
    private func updateDisplayTime() {
        let remaining = max(0, timeRemaining)
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        let seconds = Int(remaining) % 60
        
        if hours > 0 {
            displayTime = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            displayTime = String(format: "%d:%02d", minutes, seconds)
        }
    }
} 