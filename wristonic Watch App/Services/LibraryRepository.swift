import Combine
import Foundation

@MainActor
final class LibraryRepository: ObservableObject {
    @Published private(set) var cachedSnapshot: CachedLibrarySnapshot = .empty

    private let cacheStore: JSONFileStore<CachedLibrarySnapshot>
    private let clientProvider: () throws -> SubsonicClient
    private let downloadRecordsProvider: () -> [DownloadRecord]
    private let settingsStore: SettingsStore

    init(
        cacheStore: JSONFileStore<CachedLibrarySnapshot>,
        settingsStore: SettingsStore,
        clientProvider: @escaping () throws -> SubsonicClient,
        downloadRecordsProvider: @escaping () -> [DownloadRecord]
    ) {
        self.cacheStore = cacheStore
        self.settingsStore = settingsStore
        self.clientProvider = clientProvider
        self.downloadRecordsProvider = downloadRecordsProvider
    }

    func loadCachedSnapshot() async {
        if let snapshot = try? await cacheStore.load(default: .empty) {
            cachedSnapshot = snapshot
        }
    }

    func artists(forceRefresh: Bool = false) async throws -> [ArtistSummary] {
        if settingsStore.settings.offlineOnly {
            return offlineArtists()
        }
        if !forceRefresh, !cachedSnapshot.artists.isEmpty {
            return cachedSnapshot.artists
        }
        let artists = try await clientProvider().artists()
        cachedSnapshot.artists = artists
        cachedSnapshot.lastUpdatedAt = Date()
        try? await cacheStore.save(cachedSnapshot)
        return artists
    }

    func albums(sortMode: AlbumSortMode, forceRefresh: Bool = false) async throws -> [AlbumSummary] {
        if settingsStore.settings.offlineOnly {
            return offlineAlbums(sortMode: sortMode)
        }
        if !forceRefresh, let cached = cachedSnapshot.albumsBySort[sortMode.rawValue], !cached.isEmpty {
            return cached
        }
        let albums = try await clientProvider().albums(sortMode: sortMode)
        cachedSnapshot.albumsBySort[sortMode.rawValue] = albums
        cachedSnapshot.lastUpdatedAt = Date()
        try? await cacheStore.save(cachedSnapshot)
        return albums
    }

    func artistAlbums(artistID: String, forceRefresh: Bool = false) async throws -> [AlbumSummary] {
        if settingsStore.settings.offlineOnly {
            return downloadRecordsProvider()
                .filter { $0.album.artistID == artistID && $0.hasDownloadedContent }
                .map(\.album)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if !forceRefresh, let cached = cachedSnapshot.albumsByArtist[artistID], !cached.isEmpty {
            return cached
        }
        let albums = try await clientProvider().albums(for: artistID)
        cachedSnapshot.albumsByArtist[artistID] = albums
        cachedSnapshot.lastUpdatedAt = Date()
        try? await cacheStore.save(cachedSnapshot)
        return albums
    }

    func albumDetail(albumID: String, forceRefresh: Bool = false) async throws -> AlbumDetail {
        if settingsStore.settings.offlineOnly, let record = downloadRecordsProvider().first(where: { $0.album.id == albumID }) {
            return AlbumDetail(album: record.album, tracks: record.tracks)
        }
        if !forceRefresh, let cached = cachedSnapshot.albumDetails[albumID] {
            return cached
        }
        let detail = try await clientProvider().album(id: albumID)
        cachedSnapshot.albumDetails[albumID] = detail
        cachedSnapshot.lastUpdatedAt = Date()
        try? await cacheStore.save(cachedSnapshot)
        return detail
    }

    private func offlineArtists() -> [ArtistSummary] {
        let grouped = Dictionary(grouping: downloadRecordsProvider().filter(\.hasDownloadedContent), by: \.album.artistID)
        return grouped.map { artistID, albums in
            ArtistSummary(id: artistID, name: albums.first?.album.artistName ?? "Unknown Artist", albumCount: albums.count)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func offlineAlbums(sortMode: AlbumSortMode) -> [AlbumSummary] {
        let albums = downloadRecordsProvider()
            .filter(\.hasDownloadedContent)
            .map(\.album)

        switch sortMode {
        case .alphabeticalByName:
            return albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .random:
            return albums.shuffled()
        case .recentlyAdded:
            let records = downloadRecordsProvider().filter(\.hasDownloadedContent)
            return records.sorted {
                ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast)
            }.map(\.album)
        }
    }
}
