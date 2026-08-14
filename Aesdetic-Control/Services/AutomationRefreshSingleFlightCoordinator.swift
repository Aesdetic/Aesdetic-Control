import Foundation

@MainActor
final class AutomationRefreshSingleFlightCoordinator {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var entriesByDeviceId: [String: Entry] = [:]

    func isInFlight(deviceId: String) -> Bool {
        entriesByDeviceId[deviceId] != nil
    }

    func run(
        deviceId: String,
        operation: @escaping @MainActor () async -> Void
    ) async {
        if let existing = entriesByDeviceId[deviceId] {
            await existing.task.value
            return
        }

        let token = UUID()
        let task = Task<Void, Never> { @MainActor in
            await operation()
        }
        entriesByDeviceId[deviceId] = Entry(token: token, task: task)
        await task.value

        if entriesByDeviceId[deviceId]?.token == token {
            entriesByDeviceId.removeValue(forKey: deviceId)
        }
    }
}
