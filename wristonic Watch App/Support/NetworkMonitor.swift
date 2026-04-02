import Foundation
import Network

final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.andy.wristonic.network-monitor")
    private let onSatisfied: @MainActor () -> Void
    private var hasStarted = false

    init(onSatisfied: @escaping @MainActor () -> Void) {
        self.onSatisfied = onSatisfied
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        monitor.pathUpdateHandler = { [onSatisfied] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                onSatisfied()
            }
        }
        monitor.start(queue: queue)
    }
}
