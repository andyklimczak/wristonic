import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var albums: [AlbumSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var hasLoadedInitialAlbums = false

    private var sortMode: AlbumSortMode {
        environment.settingsStore.settings.albumSortMode
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AlbumSortSelectionView(sortMode: sortModeBinding)
                } label: {
                    HStack {
                        Text("Albums")
                        Spacer()
                        Text(sortMode.displayName)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isLoading && albums.isEmpty {
                ProgressView()
            } else if let errorMessage, albums.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if albums.isEmpty {
                Text(environment.settingsStore.settings.offlineOnly ? "No downloaded albums." : "No albums found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(albumID: album.id, initialAlbum: album)
                    } label: {
                        AlbumRowView(
                            album: album,
                            isDownloaded: environment.downloadManager.hasLocalContent(albumID: album.id),
                            artworkURL: preferredCoverArtURL(environment: environment, albumID: album.id, coverArtID: album.coverArtID),
                            isCurrentPlaying: environment.playbackCoordinator.currentAlbum?.id == album.id
                        )
                    }
                }
            }
        }
        .navigationTitle("Albums")
        .task {
            guard !hasLoadedInitialAlbums else {
                return
            }
            hasLoadedInitialAlbums = true
            await loadAlbums()
        }
        .refreshable {
            await loadAlbums(forceRefresh: true)
        }
        .onChange(of: environment.settingsStore.settings.albumSortMode) { _, _ in
            Task { await loadAlbums() }
        }
        .onChange(of: environment.settingsStore.settings.offlineOnly) { _, _ in
            Task { await loadAlbums() }
        }
    }

    private func loadAlbums(forceRefresh: Bool = true) async {
        guard forceRefresh, !environment.settingsStore.settings.offlineOnly else {
            await loadAlbumsFromRepository(forceRefresh: forceRefresh)
            return
        }

        syncAlbumsFromCache()
        isLoading = albums.isEmpty
        do {
            try await environment.repository.refreshAlbumsInBackground(sortMode: sortMode)?.value
            syncAlbumsFromCache()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadAlbumsFromRepository(forceRefresh: Bool) async {
        isLoading = true
        do {
            albums = try await environment.repository.albums(sortMode: sortMode, forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func syncAlbumsFromCache() {
        if let cached = environment.repository.cachedSnapshot.albumsBySort[sortMode.rawValue], !cached.isEmpty {
            albums = cached
        }
    }

    private var sortModeBinding: Binding<AlbumSortMode> {
        Binding(
            get: { environment.settingsStore.settings.albumSortMode },
            set: { newValue in
                environment.settingsStore.settings.albumSortMode = newValue
                Task { await environment.settingsStore.persist() }
            }
        )
    }
}

struct AlbumSortSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sortMode: AlbumSortMode

    var body: some View {
        List {
            sortRow(for: .alphabeticalByName)
            sortRow(for: .random)
            sortRow(for: .recentlyAdded)
            sortRow(for: .recentlyPlayed)
            sortRow(for: .mostPlayed)
        }
        .navigationTitle("Sort")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sortRow(for mode: AlbumSortMode) -> some View {
        Button {
            sortMode = mode
            dismiss()
        } label: {
            HStack {
                Text(mode.displayName)
                Spacer()
                if mode == sortMode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}
