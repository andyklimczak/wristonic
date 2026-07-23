import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showClearServerConfirmation = false

    private let bitrateOptions = [96, 128, 192, 256]

    var body: some View {
        List {
            Section("Server") {
                NavigationLink("Server Setup") {
                    ServerSetupView(
                        title: "Server",
                        subtitle: "Update your Subsonic connection.",
                        confirmTitle: "Test Connection",
                        onSuccess: nil
                    )
                }
            }

            Section("Playback") {
                Picker("Bitrate", selection: bitrateBinding) {
                    ForEach(bitrateOptions, id: \.self) { bitrate in
                        Text("\(bitrate) kbps").tag(bitrate)
                    }
                }
                Toggle("Offline Only", isOn: offlineOnlyBinding)
            }

            Section("UI") {
                Picker("Artist Album Sort", selection: artistAlbumSortModeBinding) {
                    ForEach(ArtistAlbumSortMode.allCases) { sortMode in
                        Text(sortMode.displayName).tag(sortMode)
                    }
                }
                Toggle("Show Playlists", isOn: showPlaylistsBinding)
                Toggle("Show Internet Radio", isOn: showInternetRadioBinding)
                Toggle("Show Shuffle", isOn: showShuffleBinding)
            }

            Section("Storage") {
                NavigationLink {
                    StorageSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storage")
                        Text("Cap \(environment.settingsStore.settings.storageCapGB) GB")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Saved \(environment.settingsStore.savedBytes.byteCountString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear Server", role: .destructive) {
                    showClearServerConfirmation = true
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: environment.settingsStore.settings) { _, _ in
            Task { await environment.settingsStore.persist() }
        }
        .confirmationDialog(
            "Clear saved server, downloads, and cached data from this watch?",
            isPresented: $showClearServerConfirmation
        ) {
            Button("Clear Server", role: .destructive) {
                Task { await environment.clearServerData() }
            }
            Button("Cancel", role: .cancel) {
            }
        }
    }

    private var bitrateBinding: Binding<Int> {
        Binding(
            get: { environment.settingsStore.settings.preferredBitrateKbps },
            set: { environment.settingsStore.settings.preferredBitrateKbps = $0 }
        )
    }

    private var offlineOnlyBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.offlineOnly },
            set: { environment.settingsStore.settings.offlineOnly = $0 }
        )
    }

    private var showInternetRadioBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.showInternetRadio },
            set: { environment.settingsStore.settings.showInternetRadio = $0 }
        )
    }

    private var artistAlbumSortModeBinding: Binding<ArtistAlbumSortMode> {
        Binding(
            get: { environment.settingsStore.settings.artistAlbumSortMode },
            set: { environment.settingsStore.settings.artistAlbumSortMode = $0 }
        )
    }

    private var showPlaylistsBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.showPlaylists },
            set: { environment.settingsStore.settings.showPlaylists = $0 }
        )
    }

    private var showShuffleBinding: Binding<Bool> {
        Binding(
            get: { environment.settingsStore.settings.showShuffle },
            set: { environment.settingsStore.settings.showShuffle = $0 }
        )
    }
}
