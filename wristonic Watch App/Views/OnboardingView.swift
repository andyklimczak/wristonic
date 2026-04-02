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
                        Text("Welcome to wristonic")
                            .font(.headline)
                        Text("Set up your Subsonic server to browse artists, save albums offline, and listen directly on your watch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("What You Need") {
                        Label("Server URL", systemImage: "network")
                        Label("Username and password", systemImage: "person.crop.circle")
                        Label("Subsonic or Navidrome", systemImage: "music.note.list")
                    }

                    Section {
                        Button("Set Up Server") {
                            didStartSetup = true
                        }
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
