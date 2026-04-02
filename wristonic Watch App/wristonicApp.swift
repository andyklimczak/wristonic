import SwiftUI

@main
struct wristonic_Watch_AppApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        let resolvedEnvironment = (try? AppEnvironment.live()) ?? {
            fatalError("Unable to create app environment.")
        }()
        _environment = StateObject(wrappedValue: resolvedEnvironment)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
        }
    }
}
