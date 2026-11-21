import SwiftUI

enum ComplicationLaunch {
    enum Page: Hashable { case nowPlaying }

    static func path(for url: URL, hasTrack: Bool, hasStation: Bool) -> [Page]? {
        guard url.absoluteString == "wristonic://complication" else { return nil }
        return hasTrack || hasStation ? [.nowPlaying] : []
    }
}

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var navigation = LibraryNavigation()

    private struct LibraryNavigation {
        let id = UUID()
        var path: [ComplicationLaunch.Page] = []
    }

    var body: some View {
        Group {
            if environment.settingsStore.needsServerSetup {
                OnboardingView()
                    .environmentObject(environment)
            } else {
                NavigationStack(path: $navigation.path) {
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

                        if environment.settingsStore.settings.showPlaylists {
                            NavigationLink {
                                PlaylistsView()
                            } label: {
                                Label("Playlists", systemImage: "music.note.list")
                            }
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
                    .navigationDestination(for: ComplicationLaunch.Page.self) { _ in
                        NowPlayingView()
                    }
                }
                .id(navigation.id)
            }
        }
        .onOpenURL { url in
            guard !environment.settingsStore.needsServerSetup else { return }
            let playback = environment.playbackCoordinator
            guard let path = ComplicationLaunch.path(
                for: url,
                hasTrack: playback.currentTrack != nil,
                hasStation: playback.currentRadioStation != nil
            ) else { return }
            // A face launch should leave any previously open detail screen behind.
            navigation = LibraryNavigation(path: path)
        }
    }
}
