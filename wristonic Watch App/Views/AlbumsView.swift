import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var albums: [AlbumSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

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
            await loadAlbums()
        }
        .refreshable {
            await loadAlbums(forceRefresh: true)
        }
        .onChange(of: environment.settingsStore.settings.albumSortMode) { _, newSortMode in
            Task { await loadAlbums(forceRefresh: newSortMode != .alphabeticalByName) }
        }
        .onChange(of: environment.settingsStore.settings.offlineOnly) { _, _ in
            Task { await loadAlbums() }
        }
    }

    private func loadAlbums(forceRefresh: Bool = false) async {
        isLoading = true
        do {
            albums = try await environment.repository.albums(sortMode: sortMode, forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
