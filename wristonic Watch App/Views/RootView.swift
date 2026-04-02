import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Artists") {
                    ArtistsView()
                }

                NavigationLink("Albums") {
                    AlbumsView()
                }

                NavigationLink("Settings") {
                    SettingsView()
                }

                NowPlayingLinkSection()
            }
            .navigationTitle("wristonic")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(environment)
        }
        .onAppear {
            showOnboarding = environment.settingsStore.needsServerSetup
        }
        .onChange(of: environment.settingsStore.needsServerSetup) { _, needsServerSetup in
            showOnboarding = needsServerSetup
        }
    }
}
