import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if environment.settingsStore.needsServerSetup {
                OnboardingView()
                    .environmentObject(environment)
            } else {
                NavigationStack {
                    List {
                        NowPlayingSummarySection()

                        NavigationLink {
                            ArtistsView()
                        } label: {
                            Label("Artists", systemImage: "music.mic")
                        }

                        NavigationLink {
                            AlbumsView()
                        } label: {
                            Label("Albums", systemImage: "square.stack")
                        }

                        if environment.settingsStore.settings.showInternetRadio {
                            NavigationLink {
                                InternetRadioView()
                            } label: {
                                Label("Internet Radio", systemImage: "dot.radiowaves.left.and.right")
                            }
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }

                    }
                    .navigationTitle("wristonic")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
