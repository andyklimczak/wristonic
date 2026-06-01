import Combine
import Foundation

@MainActor
final class LibraryRepository: ObservableObject {
    @Published private(set) var cachedSnapshot: CachedLibrarySnapshot = .empty

    private enum RefreshKey: Hashable {
        case artists
        case albums(String)
        case artistAlbums(String)
    }

    private let cacheStore: JSONFileStore<CachedLibrarySnapshot>
    private let clientProvider: () throws -> SubsonicClient
    private let downloadRecordsProvider: () -> [DownloadRecord]
    private let settingsStore: SettingsStore
    private var cacheSaveTask: Task<Void, Never>?
    private var refreshTasks: [RefreshKey: Task<Void, Error>] = [:]

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

    func clearCache() async {
        _ = await cacheSaveTask?.result
        cacheSaveTask = nil
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks = [:]
        cachedSnapshot = .empty
        try? await cacheStore.deleteFile()
    }

    @discardableResult
    func refreshArtistsInBackground() -> Task<Void, Error>? {
        guard !settingsStore.settings.offlineOnly else {
            return nil
        }
        return refreshTask(for: .artists) { repository in
            _ = try await repository.artists(forceRefresh: true)
        }
    }

    @discardableResult
    func refreshAlbumsInBackground(sortMode: AlbumSortMode) -> Task<Void, Error>? {
        guard !settingsStore.settings.offlineOnly else {
            return nil
        }
        return refreshTask(for: .albums(sortMode.rawValue)) { repository in
            _ = try await repository.albums(sortMode: sortMode, forceRefresh: true)
        }
    }

    @discardableResult
    func refreshArtistAlbumsInBackground(artistID: String) -> Task<Void, Error>? {
        guard !settingsStore.settings.offlineOnly else {
            return nil
        }
        return refreshTask(for: .artistAlbums(artistID)) { repository in
            _ = try await repository.artistAlbums(artistID: artistID, forceRefresh: true)
        }
    }

    func artists(forceRefresh: Bool = false) async throws -> [ArtistSummary] {
        if settingsStore.settings.offlineOnly {
            return offlineArtists()
        }
        if !forceRefresh, !cachedSnapshot.artists.isEmpty {
            return cachedSnapshot.artists
        }
        do {
            let artists = try await clientProvider().artists()
            cachedSnapshot.artists = artists
            cachedSnapshot.lastUpdatedAt = Date()
            persistCachedSnapshot()
            return artists
        } catch {
            if !cachedSnapshot.artists.isEmpty {
                return cachedSnapshot.artists
            }
            throw error
        }
    }

    func albums(sortMode: AlbumSortMode, forceRefresh: Bool = false) async throws -> [AlbumSummary] {
        if settingsStore.settings.offlineOnly {
            return offlineAlbums(sortMode: sortMode)
        }
        if !forceRefresh, let cached = cachedSnapshot.albumsBySort[sortMode.rawValue], !cached.isEmpty {
            return cached
        }
        do {
            let albums = try await clientProvider().albums(sortMode: sortMode)
            cachedSnapshot.albumsBySort[sortMode.rawValue] = albums
            cachedSnapshot.lastUpdatedAt = Date()
            persistCachedSnapshot()
            return albums
        } catch {
            if let cached = cachedSnapshot.albumsBySort[sortMode.rawValue], !cached.isEmpty {
                return cached
            }
            throw error
        }
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
        do {
            let albums = try await clientProvider().albums(for: artistID)
            cachedSnapshot.albumsByArtist[artistID] = albums
            cachedSnapshot.lastUpdatedAt = Date()
            persistCachedSnapshot()
            return albums
        } catch {
            if let cached = cachedSnapshot.albumsByArtist[artistID], !cached.isEmpty {
                return cached
            }
            throw error
        }
    }

    func albumDetail(albumID: String, forceRefresh: Bool = false) async throws -> AlbumDetail {
        let localDetail = downloadRecordsProvider()
            .first(where: { $0.album.id == albumID && !$0.tracks.isEmpty })
            .map { AlbumDetail(album: $0.album, tracks: $0.tracks) }

        if settingsStore.settings.offlineOnly, let localDetail {
            return localDetail
        }
        if !forceRefresh, let cached = cachedSnapshot.albumDetails[albumID] {
            return cached
        }
        if !forceRefresh, let localDetail {
            return localDetail
        }
        do {
            let detail = try await clientProvider().album(id: albumID)
            cachedSnapshot.albumDetails[albumID] = detail
            cachedSnapshot.lastUpdatedAt = Date()
            persistCachedSnapshot()
            return detail
        } catch {
            if let localDetail {
                return localDetail
            }
            throw error
        }
    }

    func playlists(forceRefresh: Bool = false) async throws -> [PlaylistSummary] {
        if settingsStore.settings.offlineOnly {
            return cachedSnapshot.playlists
        }
        if !forceRefresh, !cachedSnapshot.playlists.isEmpty {
            return cachedSnapshot.playlists
        }
        let playlists = try await clientProvider().playlists()
        cachedSnapshot.playlists = playlists
        cachedSnapshot.lastUpdatedAt = Date()
        persistCachedSnapshot()
        return playlists
    }

    func playlistDetail(playlistID: String, forceRefresh: Bool = false) async throws -> PlaylistDetail {
        let cachedDetail = cachedSnapshot.playlistDetails[playlistID]

        if settingsStore.settings.offlineOnly {
            if let cachedDetail {
                return offlinePlaylistDetail(cachedDetail)
            }
            throw SubsonicClientError.missingPayload("playlist")
        }
        if !forceRefresh, let cachedDetail {
            return cachedDetail
        }
        do {
            let detail = try await clientProvider().playlist(id: playlistID)
            cachedSnapshot.playlistDetails[playlistID] = detail
            cachedSnapshot.lastUpdatedAt = Date()
            persistCachedSnapshot()
            return detail
        } catch {
            if let cachedDetail {
                return cachedDetail
            }
            throw error
        }
    }

    func internetRadioStations(forceRefresh: Bool = false) async throws -> [InternetRadioStation] {
        if settingsStore.settings.offlineOnly {
            return []
        }
        if !forceRefresh, !cachedSnapshot.internetRadioStations.isEmpty {
            return cachedSnapshot.internetRadioStations
        }
        let stations = try await clientProvider().internetRadioStations()
        cachedSnapshot.internetRadioStations = stations
        cachedSnapshot.lastUpdatedAt = Date()
        persistCachedSnapshot()
        return stations
    }

    private func persistCachedSnapshot() {
        let snapshot = cachedSnapshot
        let previousTask = cacheSaveTask
        cacheSaveTask = Task { [cacheStore] in
            _ = await previousTask?.result
            try? await cacheStore.save(snapshot)
        }
    }

    private func refreshTask(
        for key: RefreshKey,
        operation: @escaping @MainActor (LibraryRepository) async throws -> Void
    ) -> Task<Void, Error> {
        if let existingTask = refreshTasks[key] {
            return existingTask
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                refreshTasks[key] = nil
            }
            try Task.checkCancellation()
            try await operation(self)
        }
        refreshTasks[key] = task
        return task
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
        case .recentlyPlayed:
            let records = downloadRecordsProvider().filter(\.hasDownloadedContent)
            return records.sorted {
                ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast)
            }.map(\.album)
        }
    }

    private func offlinePlaylistDetail(_ detail: PlaylistDetail) -> PlaylistDetail {
        let localTrackIDs = Set(
            downloadRecordsProvider()
                .flatMap(\.downloadedTracks)
                .map(\.trackID)
        )
        return PlaylistDetail(
            playlist: detail.playlist,
            tracks: detail.tracks.filter { localTrackIDs.contains($0.id) }
        )
    }
}
