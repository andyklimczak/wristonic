import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var artists: [ArtistSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading && artists.isEmpty {
                ProgressView()
            } else if let errorMessage, artists.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if artists.isEmpty {
                Text(environment.settingsStore.settings.offlineOnly ? "No downloaded artists." : "No artists found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        ArtistListRowView(artist: artist)
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .task {
            await loadArtists()
        }
        .refreshable {
            await loadArtists(forceRefresh: true)
        }
        .onChange(of: environment.settingsStore.settings.offlineOnly) { _, _ in
            Task { await loadArtists() }
        }
    }

    private func loadArtists(forceRefresh: Bool = false) async {
        isLoading = true
        do {
            artists = try await environment.repository.artists(forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ArtistListRowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let artist: ArtistSummary

    @State private var artworkURL: URL?

    var body: some View {
        ArtistRowView(
            artist: artist,
            hasDownloads: environment.downloadManager.hasDownloadedArtist(artistID: artist.id),
            artworkURL: artworkURL
        )
        .task(id: artist.id) {
            await loadArtwork()
        }
    }

    private func loadArtwork() async {
        if let coverArtID = cachedCoverArtID() {
            artworkURL = coverArtURL(for: coverArtID)
            return
        }

        guard !environment.settingsStore.settings.offlineOnly else {
            artworkURL = nil
            return
        }

        do {
            let albums = try await environment.repository.artistAlbums(artistID: artist.id)
            artworkURL = coverArtURL(for: albums.first?.coverArtID)
        } catch {
            artworkURL = nil
        }
    }

    private func cachedCoverArtID() -> String? {
        if let cachedAlbum = environment.repository.cachedSnapshot.albumsByArtist[artist.id]?.first {
            return cachedAlbum.coverArtID
        }

        return environment.downloadManager.downloadedRecords()
            .first(where: { $0.album.artistID == artist.id })?
            .album
            .coverArtID
    }

    private func coverArtURL(for coverArtID: String?) -> URL? {
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let artist: ArtistSummary

    @State private var albums: [AlbumSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading && albums.isEmpty {
                ProgressView()
            } else if let errorMessage, albums.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if albums.isEmpty {
                Text("No albums found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(albumID: album.id, initialAlbum: album)
                    } label: {
                        AlbumRowView(
                            album: album,
                            isDownloaded: environment.downloadManager.hasLocalContent(albumID: album.id),
                            artworkURL: coverArtURL(for: album.coverArtID),
                            isCurrentPlaying: environment.playbackCoordinator.currentAlbum?.id == album.id
                        )
                    }
                }
            }
        }
        .navigationTitle(artist.name)
        .task {
            await loadAlbums()
        }
        .refreshable {
            await loadAlbums(forceRefresh: true)
        }
    }

    private func loadAlbums(forceRefresh: Bool = false) async {
        isLoading = true
        do {
            albums = try await environment.repository.artistAlbums(artistID: artist.id, forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func coverArtURL(for coverArtID: String?) -> URL? {
        do {
            return try environment.makeClient().coverArtURL(for: coverArtID)
        } catch {
            return nil
        }
    }
}
