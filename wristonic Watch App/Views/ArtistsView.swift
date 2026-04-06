import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var artists: [ArtistSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var groupedArtists: [(key: String, artists: [ArtistSummary])] {
        let grouped = Dictionary(grouping: artists) { artist in
            sectionKey(for: artist.name)
        }

        return grouped.keys.sorted(by: sectionOrder).map { key in
            (
                key: key,
                artists: grouped[key, default: []]
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            )
        }
    }

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
                ForEach(groupedArtists, id: \.key) { section in
                    Section(section.key) {
                        ForEach(section.artists) { artist in
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                            } label: {
                                ArtistListRowView(artist: artist)
                            }
                        }
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

    private func sectionKey(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first else {
            return "#"
        }

        let uppercase = String(trimmed.prefix(1)).uppercased()
        if let first = uppercase.first, first >= "A", first <= "Z" {
            return String(first)
        }

        if scalar.isHangul {
            return "한"
        }

        if scalar.isJapanese {
            return "あ"
        }

        return "#"
    }

    private func sectionOrder(lhs: String, rhs: String) -> Bool {
        func rank(for key: String) -> (Int, String) {
            switch key {
            case "한":
                return (1, key)
            case "あ":
                return (2, key)
            case "#":
                return (3, key)
            default:
                return (0, key)
            }
        }

        let left = rank(for: lhs)
        let right = rank(for: rhs)
        if left.0 != right.0 {
            return left.0 < right.0
        }
        return left.1 < right.1
    }
}

private extension Unicode.Scalar {
    var isHangul: Bool {
        switch value {
        case 0x1100...0x11FF,
             0x3130...0x318F,
             0xA960...0xA97F,
             0xAC00...0xD7AF,
             0xD7B0...0xD7FF:
            return true
        default:
            return false
        }
    }

    var isJapanese: Bool {
        switch value {
        case 0x3040...0x309F,
             0x30A0...0x30FF,
             0x31F0...0x31FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xFF66...0xFF9D:
            return true
        default:
            return false
        }
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
        if let albumID = cachedAlbumID(), let coverArtID = cachedCoverArtID() {
            artworkURL = preferredCoverArtURL(environment: environment, albumID: albumID, coverArtID: coverArtID)
            return
        }
        artworkURL = nil
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

    private func cachedAlbumID() -> String? {
        if let cachedAlbum = environment.repository.cachedSnapshot.albumsByArtist[artist.id]?.first {
            return cachedAlbum.id
        }

        return environment.downloadManager.downloadedRecords()
            .first(where: { $0.album.artistID == artist.id })?
            .album
            .id
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
                            artworkURL: preferredCoverArtURL(environment: environment, albumID: album.id, coverArtID: album.coverArtID),
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

}
