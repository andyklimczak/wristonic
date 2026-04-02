import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        RootView()
            .task {
                await environment.bootstrap()
            }
    }
}
