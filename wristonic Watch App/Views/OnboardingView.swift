import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var didStartSetup = false

    var body: some View {
        NavigationStack {
            if didStartSetup {
                ServerSetupView(
                    title: "Add Server",
                    subtitle: "Connect to your Subsonic or Navidrome library.",
                    confirmTitle: "Connect",
                    showHeader: false,
                    onSuccess: nil
                )
            } else {
                List {
                    Section {
                        Button("Set Up Server") {
                            didStartSetup = true
                        }

                        Text("Set up your Subsonic server to browse artists, save albums offline, and listen directly on your watch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Welcome")
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: environment.settingsStore.needsServerSetup) { _, needsServerSetup in
            if needsServerSetup {
                didStartSetup = false
            }
        }
    }
}
