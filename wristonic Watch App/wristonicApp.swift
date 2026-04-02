import SwiftUI
import WatchKit

@main
struct wristonic_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            environment.playbackReportingManager.notifyAppDidBecomeActive()
        }
    }
}
