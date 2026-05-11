import Combine
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []
    @Published private(set) var playlistRecords: [PlaylistDownloadRecord] = []
    @Published private(set) var storagePolicy = StoragePolicy(capBytes: 8_000_000_000, savedBytes: 0, pinnedBytes: 0)

    private let recordsStore: JSONFileStore<[DownloadRecord]>
    private let playlistRecordsStore: JSONFileStore<[PlaylistDownloadRecord]>?
    private let historyStore: JSONFileStore<[String: PlaybackHistory]>
    private let settingsStore: SettingsStore
    private let clientProvider: () throws -> SubsonicClient
    private let downloadService: DownloadServing
    private let fileManager: FileManager
    private let downloadsDirectory: URL
    private var playbackHistory: [String: PlaybackHistory] = [:]
    private var processingTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        recordsStore: JSONFileStore<[DownloadRecord]>,
        historyStore: JSONFileStore<[String: PlaybackHistory]>,
        playlistRecordsStore: JSONFileStore<[PlaylistDownloadRecord]>? = nil,
        downloadsDirectory: URL,
        downloadService: DownloadServing? = nil,
        fileManager: FileManager = .default,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.settingsStore = settingsStore
        self.recordsStore = recordsStore
        self.playlistRecordsStore = playlistRecordsStore
        self.historyStore = historyStore
        self.downloadsDirectory = downloadsDirectory
        self.downloadService = downloadService ?? BackgroundDownloadService.shared
        self.fileManager = fileManager
        self.clientProvider = clientProvider
    }

    func load() async {
        let loadedRecords = (try? await recordsStore.load(default: [])) ?? []
        let loadedPlaylistRecords = (try? await playlistRecordsStore?.load(default: [])) ?? []
        let loadedHistory = (try? await historyStore.load(default: [:])) ?? [:]
        playbackHistory = loadedHistory
        records = loadedRecords.map { record in
            var updated = record
            if updated.state.status == .downloading {
                updated.state = DownloadState(status: .queued, progress: 0, errorMessage: nil)
            }
            updated.downloadedTracks = updated.downloadedTracks.compactMap { downloadedTrack in
                guard fileManager.fileExists(atPath: localFileURL(for: downloadedTrack).path) else {
                    return nil
                }
                var migrated = downloadedTrack
                if migrated.ownerKeys.isEmpty {
                    migrated.ownerKeys = [Self.ownerKeyForAlbum(updated.album.id)]
                }
                return migrated
            }
            if let relativePath = updated.localCoverArtRelativePath {
                let coverArtURL = downloadsDirectory.appendingPathComponent(relativePath, isDirectory: false)
                if !fileManager.fileExists(atPath: coverArtURL.path) {
                    updated.localCoverArtRelativePath = nil
                    updated.coverArtBytes = 0
                }
            }
            if updated.downloadedTracks.isEmpty && updated.state.status == .downloaded {
                updated.state = .notDownloaded
            }
            return updated
        }
        playlistRecords = loadedPlaylistRecords.map { record in
            var updated = record
            if updated.state.status == .downloading {
                updated.state = DownloadState(status: .queued, progress: 0, errorMessage: nil)
            }
            updated.downloadedTrackIDs = uniqueTrackIDs(updated.downloadedTrackIDs).filter { downloadedTrack(for: $0) != nil }
            if let relativePath = updated.localCoverArtRelativePath {
                let coverArtURL = downloadsDirectory.appendingPathComponent(relativePath, isDirectory: false)
                if !fileManager.fileExists(atPath: coverArtURL.path) {
                    updated.localCoverArtRelativePath = nil
                    updated.coverArtBytes = 0
                }
            }
            if updated.downloadedTrackIDs.isEmpty {
                if updated.state.status == .downloaded {
                    updated.state = .notDownloaded
                }
                updated.localCoverArtRelativePath = nil
                updated.coverArtBytes = 0
            }
            return updated
        }
        refreshStoragePolicy()
        persist()
        if records.contains(where: { $0.state.status == .queued }) || playlistRecords.contains(where: { $0.state.status == .queued }) {
            startProcessingQueueIfNeeded()
        }
    }

    func state(for albumID: String) -> DownloadState {
        records.first(where: { $0.album.id == albumID })?.state ?? .notDownloaded
    }

    func playlistState(for playlistID: String) -> DownloadState {
        playlistRecords.first(where: { $0.playlist.id == playlistID })?.state ?? .notDownloaded
    }

    func isPinned(albumID: String) -> Bool {
        records.first(where: { $0.album.id == albumID })?.pinned ?? false
    }

    func hasLocalContent(albumID: String) -> Bool {
        records.first(where: { $0.album.id == albumID })?.hasDownloadedContent ?? false
    }

    func hasLocalContent(playlistID: String) -> Bool {
        playlistRecords.first(where: { $0.playlist.id == playlistID })?.hasDownloadedContent ?? false
    }

    func hasDownloadedArtist(artistID: String) -> Bool {
        records.contains { $0.album.artistID == artistID && $0.hasDownloadedContent }
    }

    func isAlbumFullyDownloaded(_ albumDetail: AlbumDetail) -> Bool {
        !albumDetail.tracks.isEmpty && albumDetail.tracks.allSatisfy { localFileURL(for: $0) != nil }
    }

    func isPlaylistFullyDownloaded(_ playlistDetail: PlaylistDetail) -> Bool {
        let uniqueTracks = uniqueTracks(playlistDetail.tracks)
        return !uniqueTracks.isEmpty && uniqueTracks.allSatisfy { localFileURL(for: $0) != nil }
    }

    func localFileURL(for track: Track) -> URL? {
        guard let downloadedTrack = downloadedTrack(for: track.id) else {
            return nil
        }
        let url = localFileURL(for: downloadedTrack)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func localCoverArtURL(for albumID: String) -> URL? {
        guard let relativePath = records.first(where: { $0.album.id == albumID })?.localCoverArtRelativePath else {
            return nil
        }
        let url = downloadsDirectory.appendingPathComponent(relativePath, isDirectory: false)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func localPlaylistCoverArtURL(for playlistID: String) -> URL? {
        guard let relativePath = playlistRecords.first(where: { $0.playlist.id == playlistID })?.localCoverArtRelativePath else {
            return nil
        }
        let url = downloadsDirectory.appendingPathComponent(relativePath, isDirectory: false)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func enqueue(albumDetail: AlbumDetail) {
        if let index = records.firstIndex(where: { $0.album.id == albumDetail.album.id }) {
            if records[index].state.status == .downloading || records[index].state.status == .queued {
                return
            }
            records[index].tracks = albumDetail.tracks
            records[index].album = albumDetail.album
            records[index].state = DownloadState(status: .queued, progress: 0, errorMessage: nil)
        } else {
            let record = DownloadRecord(
                album: albumDetail.album,
                tracks: albumDetail.tracks,
                downloadedTracks: [],
                localCoverArtRelativePath: nil,
                coverArtBytes: 0,
                pinned: false,
                state: DownloadState(status: .queued, progress: 0, errorMessage: nil),
                downloadedAt: nil,
                totalBytes: 0,
                playCount: 0,
                lastPlayedAt: nil
            )
            records.append(record)
        }
        persist()
        startProcessingQueueIfNeeded()
    }

    func enqueue(playlistDetail: PlaylistDetail) {
        if let index = playlistRecords.firstIndex(where: { $0.playlist.id == playlistDetail.playlist.id }) {
            if playlistRecords[index].state.status == .downloading || playlistRecords[index].state.status == .queued {
                return
            }
            playlistRecords[index].playlist = playlistDetail.playlist
            playlistRecords[index].tracks = playlistDetail.tracks
            playlistRecords[index].state = DownloadState(status: .queued, progress: 0, errorMessage: nil)
        } else {
            playlistRecords.append(
                PlaylistDownloadRecord(
                    playlist: playlistDetail.playlist,
                    tracks: playlistDetail.tracks,
                    downloadedTrackIDs: [],
                    state: DownloadState(status: .queued, progress: 0, errorMessage: nil),
                    downloadedAt: nil,
                    totalBytes: 0
                )
            )
        }
        persist()
        startProcessingQueueIfNeeded()
    }

    func deleteDownloadedAlbum(albumID: String) {
        removeOwner(Self.ownerKeyForAlbum(albumID), matchingTrackIDs: nil)
        if let index = records.firstIndex(where: { $0.album.id == albumID }) {
            if let directory = albumDirectory(albumID: albumID),
               fileManager.fileExists(atPath: directory.path),
               (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
            if records[index].downloadedTracks.isEmpty {
                records[index].localCoverArtRelativePath = nil
                records[index].coverArtBytes = 0
                records[index].state = .notDownloaded
                records[index].downloadedAt = nil
                records[index].totalBytes = 0
            } else {
                records[index].totalBytes = records[index].downloadedTracks.reduce(into: Int64(0)) { $0 += $1.bytes }
            }
        }
        refreshPlaylistDownloadedTrackIDs()
        refreshStoragePolicy()
        persist()
    }

    func deleteDownloadedPlaylist(playlistID: String) {
        removeOwner(Self.ownerKeyForPlaylist(playlistID), matchingTrackIDs: nil)
        if let index = playlistRecords.firstIndex(where: { $0.playlist.id == playlistID }) {
            if let relativePath = playlistRecords[index].localCoverArtRelativePath {
                try? fileManager.removeItem(at: downloadsDirectory.appendingPathComponent(relativePath, isDirectory: false))
            }
            if let directory = playlistDirectory(playlistID: playlistID),
               fileManager.fileExists(atPath: directory.path),
               (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
            playlistRecords[index].downloadedTrackIDs = []
            playlistRecords[index].localCoverArtRelativePath = nil
            playlistRecords[index].coverArtBytes = 0
            playlistRecords[index].state = .notDownloaded
            playlistRecords[index].downloadedAt = nil
            playlistRecords[index].totalBytes = 0
        }
        refreshStoragePolicy()
        persist()
    }

    func deleteAllDownloads() {
        processingTask?.cancel()
        processingTask = nil

        if fileManager.fileExists(atPath: downloadsDirectory.path) {
            try? fileManager.removeItem(at: downloadsDirectory)
        }
        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        records.removeAll()
        playlistRecords.removeAll()
        refreshStoragePolicy()
        persist()
    }

    func clearAllData() async {
        processingTask?.cancel()
        processingTask = nil

        if fileManager.fileExists(atPath: downloadsDirectory.path) {
            try? fileManager.removeItem(at: downloadsDirectory)
        }
        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        records.removeAll()
        playlistRecords.removeAll()
        playbackHistory.removeAll()
        refreshStoragePolicy()
        try? await recordsStore.deleteFile()
        try? await playlistRecordsStore?.deleteFile()
        try? await historyStore.deleteFile()
    }

    func togglePin(albumID: String) {
        guard let index = records.firstIndex(where: { $0.album.id == albumID }) else {
            return
        }
        records[index].pinned.toggle()
        refreshStoragePolicy()
        persist()
    }

    @discardableResult
    func recordPlayback(for track: Track, listenedSeconds: TimeInterval) -> Bool {
        let duration = track.duration ?? 0
        let threshold = min(max(duration * 0.5, 20), 120)
        guard listenedSeconds >= threshold || duration == 0 else {
            return false
        }
        let current = playbackHistory[track.id] ?? PlaybackHistory(trackID: track.id, playCount: 0, lastPlayedAt: nil)
        playbackHistory[track.id] = PlaybackHistory(trackID: track.id, playCount: current.playCount + 1, lastPlayedAt: Date())
        if let index = records.firstIndex(where: { $0.album.id == track.albumID }) {
            records[index].playCount += 1
            records[index].lastPlayedAt = Date()
            persist()
        }
        Task {
            try? await historyStore.save(playbackHistory)
        }
        return true
    }

    func refreshStoragePolicy() {
        let savedBytes = uniqueSavedBytes()
        let pinnedBytes = uniquePinnedBytes()
        storagePolicy = StoragePolicy(capBytes: settingsStore.capBytes, savedBytes: savedBytes, pinnedBytes: pinnedBytes)
        settingsStore.updateSavedBytes(savedBytes)
    }

    func downloadedRecords() -> [DownloadRecord] {
        records.filter(\.hasDownloadedContent)
    }

    func savedBytes(for playlistRecord: PlaylistDownloadRecord) -> Int64 {
        let wanted = Set(playlistRecord.downloadedTrackIDs)
        return uniqueDownloadedTracks()
            .filter { wanted.contains($0.trackID) }
            .reduce(into: playlistRecord.coverArtBytes) { $0 += $1.bytes }
    }

    static func ownerKeyForAlbum(_ albumID: String) -> String {
        "album:\(albumID)"
    }

    static func ownerKeyForPlaylist(_ playlistID: String) -> String {
        "playlist:\(playlistID)"
    }

    private func startProcessingQueueIfNeeded() {
        guard processingTask == nil else {
            return
        }
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
        }
    }

    private func processQueue() async {
        defer { processingTask = nil }
        while true {
            if let index = records.firstIndex(where: { $0.state.status == .queued }) {
                do {
                    try await download(recordAt: index)
                } catch {
                    if records.indices.contains(index) {
                        records[index].state = DownloadState(status: .failed, progress: 0, errorMessage: error.localizedDescription)
                        persist()
                    }
                }
                continue
            }

            if let index = playlistRecords.firstIndex(where: { $0.state.status == .queued }) {
                do {
                    try await download(playlistRecordAt: index)
                } catch {
                    if playlistRecords.indices.contains(index) {
                        playlistRecords[index].state = DownloadState(status: .failed, progress: 0, errorMessage: error.localizedDescription)
                        persist()
                    }
                }
                continue
            }

            break
        }
    }

    private func download(recordAt index: Int) async throws {
        let record = records[index]
        let projectedExisting = storagePolicy.savedBytes - record.savedBytes
        if projectedExisting >= settingsStore.capBytes && !record.pinned {
            try enforceStorageCap(projectedAdditionalBytes: 0, excludingAlbumID: record.album.id, excludingPlaylistID: nil)
        }

        let client = try clientProvider()
        let ownerKey = Self.ownerKeyForAlbum(record.album.id)
        records[index].state = DownloadState(status: .downloading, progress: 0, errorMessage: nil)
        persist()

        let totalTrackCount = max(record.tracks.count, 1)

        for (offset, track) in record.tracks.enumerated() {
            if let existing = downloadedTrack(for: track.id) {
                upsertDownloadedTrack(existing, for: track, ownerKey: ownerKey)
                records[index].state = DownloadState(
                    status: .downloading,
                    progress: Double(offset + 1) / Double(totalTrackCount),
                    errorMessage: nil,
                    transferRateBytesPerSecond: nil
                )
                persist()
                continue
            }

            let albumID = record.album.id
            let completedTracks = records[index].downloadedTracks.count
            let downloaded = try await downloadTrack(track, client: client) { [weak self] trackProgress, _, bytesPerSecond in
                Task { @MainActor [weak self] in
                    guard let self,
                          records.indices.contains(index),
                          records[index].album.id == albumID else {
                        return
                    }
                    let combinedProgress = (Double(completedTracks) + trackProgress) / Double(totalTrackCount)
                    records[index].state = DownloadState(
                        status: .downloading,
                        progress: combinedProgress,
                        errorMessage: nil,
                        transferRateBytesPerSecond: bytesPerSecond
                    )
                }
            }
            upsertDownloadedTrack(downloaded, for: track, ownerKey: ownerKey)
            records[index].state = DownloadState(
                status: .downloading,
                progress: Double(offset + 1) / Double(totalTrackCount),
                errorMessage: nil,
                transferRateBytesPerSecond: nil
            )
            persist()
        }

        if records.indices.contains(index),
           let downloadedCoverArt = try await downloadCoverArt(for: records[index].album, client: client) {
            records[index].localCoverArtRelativePath = downloadedCoverArt.relativePath
            records[index].coverArtBytes = downloadedCoverArt.bytes
        }

        if records.indices.contains(index) {
            records[index].downloadedAt = Date()
            records[index].totalBytes = records[index].downloadedTracks.reduce(into: Int64(0)) { $0 += $1.bytes }
            records[index].state = DownloadState(status: .downloaded, progress: 1, errorMessage: nil, transferRateBytesPerSecond: nil)
        }
        refreshPlaylistDownloadedTrackIDs()
        refreshStoragePolicy()
        try enforceStorageCap(projectedAdditionalBytes: 0, excludingAlbumID: nil, excludingPlaylistID: nil)
        persist()
    }

    private func download(playlistRecordAt index: Int) async throws {
        let record = playlistRecords[index]
        let client = try clientProvider()
        let ownerKey = Self.ownerKeyForPlaylist(record.playlist.id)
        let tracks = uniqueTracks(record.tracks)
        let totalTrackCount = max(tracks.count, 1)
        playlistRecords[index].state = DownloadState(status: .downloading, progress: 0, errorMessage: nil)
        persist()

        for (offset, track) in tracks.enumerated() {
            let downloaded: DownloadedTrackRecord
            if let existing = downloadedTrack(for: track.id) {
                downloaded = existing
            } else {
                let completedTracks = playlistRecords[index].downloadedTrackIDs.count
                let playlistID = record.playlist.id
                downloaded = try await downloadTrack(track, client: client) { [weak self] trackProgress, _, bytesPerSecond in
                    Task { @MainActor [weak self] in
                        guard let self,
                              playlistRecords.indices.contains(index),
                              playlistRecords[index].playlist.id == playlistID else {
                            return
                        }
                        let combinedProgress = (Double(completedTracks) + trackProgress) / Double(totalTrackCount)
                        playlistRecords[index].state = DownloadState(
                            status: .downloading,
                            progress: combinedProgress,
                            errorMessage: nil,
                            transferRateBytesPerSecond: bytesPerSecond
                        )
                    }
                }
            }

            upsertDownloadedTrack(downloaded, for: track, ownerKey: ownerKey)
            if playlistRecords.indices.contains(index),
               !playlistRecords[index].downloadedTrackIDs.contains(track.id) {
                playlistRecords[index].downloadedTrackIDs.append(track.id)
            }
            if playlistRecords.indices.contains(index) {
                playlistRecords[index].state = DownloadState(
                    status: .downloading,
                    progress: Double(offset + 1) / Double(totalTrackCount),
                    errorMessage: nil,
                    transferRateBytesPerSecond: nil
                )
            }
            persist()
        }

        if playlistRecords.indices.contains(index),
           let downloadedCoverArt = try await downloadCoverArt(for: playlistRecords[index].playlist, client: client) {
            playlistRecords[index].localCoverArtRelativePath = downloadedCoverArt.relativePath
            playlistRecords[index].coverArtBytes = downloadedCoverArt.bytes
        }

        if playlistRecords.indices.contains(index) {
            playlistRecords[index].downloadedAt = Date()
            playlistRecords[index].totalBytes = savedBytes(for: playlistRecords[index])
            playlistRecords[index].state = DownloadState(status: .downloaded, progress: 1, errorMessage: nil, transferRateBytesPerSecond: nil)
        }
        refreshStoragePolicy()
        try enforceStorageCap(projectedAdditionalBytes: 0, excludingAlbumID: nil, excludingPlaylistID: nil)
        persist()
    }

    private func downloadTrack(
        _ track: Track,
        client: SubsonicClient,
        onProgress: @escaping @Sendable (Double, Int64?, Double) -> Void
    ) async throws -> DownloadedTrackRecord {
        let candidates = client.streamCandidates(for: track, preferTranscoding: true)
        guard !candidates.isEmpty else {
            throw SubsonicClientError.unsupportedMediaType
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                let temporaryURL = try await downloadService.download(for: candidate.request) { totalBytesWritten, totalBytesExpectedToWrite, bytesPerSecond in
                    let progress: Double
                    if totalBytesExpectedToWrite > 0 {
                        progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
                    } else {
                        progress = 0
                    }
                    onProgress(progress, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil, bytesPerSecond)
                }
                let albumDirectory = try self.albumDirectory(albumID: track.albumID, createIfNeeded: true)
                let fileName = "\(track.trackNumber)-\(track.id).\(candidate.fileExtension)"
                let destinationURL = albumDirectory.appendingPathComponent(fileName, isDirectory: false)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                return DownloadedTrackRecord(
                    trackID: track.id,
                    relativePath: "\(track.albumID)/\(fileName)",
                    bytes: fileSize
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SubsonicClientError.unsupportedMediaType
    }

    private func downloadCoverArt(for album: AlbumSummary, client: SubsonicClient) async throws -> (relativePath: String, bytes: Int64)? {
        guard let coverArtURL = client.coverArtURL(for: album.coverArtID) else {
            return nil
        }

        let temporaryURL = try await downloadService.download(for: URLRequest(url: coverArtURL), onProgress: nil)
        let albumDirectory = try self.albumDirectory(albumID: album.id, createIfNeeded: true)
        let destinationURL = albumDirectory.appendingPathComponent("coverart", isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return (relativePath: "\(album.id)/coverart", bytes: fileSize)
    }

    private func downloadCoverArt(for playlist: PlaylistSummary, client: SubsonicClient) async throws -> (relativePath: String, bytes: Int64)? {
        guard let coverArtURL = client.coverArtURL(for: playlist.coverArtID) else {
            return nil
        }

        let temporaryURL = try await downloadService.download(for: URLRequest(url: coverArtURL), onProgress: nil)
        let playlistDirectory = try self.playlistDirectory(playlistID: playlist.id, createIfNeeded: true)
        let destinationURL = playlistDirectory.appendingPathComponent("coverart", isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return (relativePath: "playlists/\(playlist.id)/coverart", bytes: fileSize)
    }

    private func enforceStorageCap(projectedAdditionalBytes: Int64, excludingAlbumID: String?, excludingPlaylistID: String?) throws {
        refreshStoragePolicy()
        var projectedSavedBytes = storagePolicy.savedBytes + projectedAdditionalBytes
        guard projectedSavedBytes > settingsStore.capBytes else {
            return
        }

        let pinnedBytes = uniquePinnedBytes()
        guard pinnedBytes <= settingsStore.capBytes else {
            throw DownloadError.pinnedAlbumsExceedCap
        }

        let albumCandidates = records
            .filter { !$0.pinned && $0.album.id != excludingAlbumID && $0.hasDownloadedContent }
            .sorted { lhs, rhs in
                if lhs.playCount != rhs.playCount {
                    return lhs.playCount < rhs.playCount
                }
                if lhs.lastPlayedAt != rhs.lastPlayedAt {
                    return (lhs.lastPlayedAt ?? .distantPast) < (rhs.lastPlayedAt ?? .distantPast)
                }
                return (lhs.downloadedAt ?? .distantPast) < (rhs.downloadedAt ?? .distantPast)
            }

        for candidate in albumCandidates where projectedSavedBytes > settingsStore.capBytes {
            deleteDownloadedAlbum(albumID: candidate.album.id)
            projectedSavedBytes = storagePolicy.savedBytes + projectedAdditionalBytes
        }

        let playlistCandidates = playlistRecords
            .filter { $0.playlist.id != excludingPlaylistID && $0.hasDownloadedContent }
            .sorted { ($0.downloadedAt ?? .distantPast) < ($1.downloadedAt ?? .distantPast) }

        for candidate in playlistCandidates where projectedSavedBytes > settingsStore.capBytes {
            deleteDownloadedPlaylist(playlistID: candidate.playlist.id)
            projectedSavedBytes = storagePolicy.savedBytes + projectedAdditionalBytes
        }

        if projectedSavedBytes > settingsStore.capBytes {
            throw DownloadError.storageCapExceeded
        }
    }

    private func ensureAlbumRecord(for track: Track) -> Int {
        if let index = records.firstIndex(where: { $0.album.id == track.albumID }) {
            if !records[index].tracks.contains(where: { $0.id == track.id }) {
                records[index].tracks.append(track)
            }
            return index
        }

        let album = AlbumSummary(
            id: track.albumID,
            name: track.albumName,
            artistID: track.artistID,
            artistName: track.artistName,
            coverArtID: nil,
            songCount: 0,
            duration: nil,
            year: nil,
            createdAt: nil
        )
        records.append(
            DownloadRecord(
                album: album,
                tracks: [track],
                downloadedTracks: [],
                localCoverArtRelativePath: nil,
                coverArtBytes: 0,
                pinned: false,
                state: .notDownloaded,
                downloadedAt: nil,
                totalBytes: 0,
                playCount: 0,
                lastPlayedAt: nil
            )
        )
        return records.count - 1
    }

    private func upsertDownloadedTrack(_ downloadedTrack: DownloadedTrackRecord, for track: Track, ownerKey: String) {
        let index = ensureAlbumRecord(for: track)
        var updatedTrack = downloadedTrack
        updatedTrack.ownerKeys.insert(ownerKey)

        if let downloadedIndex = records[index].downloadedTracks.firstIndex(where: { $0.trackID == track.id }) {
            records[index].downloadedTracks[downloadedIndex].ownerKeys.insert(ownerKey)
        } else {
            records[index].downloadedTracks.append(updatedTrack)
        }

        for recordIndex in records.indices {
            for trackIndex in records[recordIndex].downloadedTracks.indices where records[recordIndex].downloadedTracks[trackIndex].trackID == track.id {
                records[recordIndex].downloadedTracks[trackIndex].ownerKeys.insert(ownerKey)
            }
        }
    }

    private func removeOwner(_ ownerKey: String, matchingTrackIDs: Set<String>?) {
        for recordIndex in records.indices {
            var keptTracks: [DownloadedTrackRecord] = []
            for var downloadedTrack in records[recordIndex].downloadedTracks {
                guard matchingTrackIDs == nil || matchingTrackIDs?.contains(downloadedTrack.trackID) == true else {
                    keptTracks.append(downloadedTrack)
                    continue
                }
                downloadedTrack.ownerKeys.remove(ownerKey)
                if downloadedTrack.ownerKeys.isEmpty {
                    try? fileManager.removeItem(at: localFileURL(for: downloadedTrack))
                } else {
                    keptTracks.append(downloadedTrack)
                }
            }
            records[recordIndex].downloadedTracks = keptTracks
            if keptTracks.isEmpty && records[recordIndex].state.status == .downloaded {
                records[recordIndex].state = .notDownloaded
                records[recordIndex].downloadedAt = nil
                records[recordIndex].totalBytes = 0
            } else {
                records[recordIndex].totalBytes = keptTracks.reduce(into: Int64(0)) { $0 += $1.bytes }
            }
        }
        refreshPlaylistDownloadedTrackIDs()
    }

    private func refreshPlaylistDownloadedTrackIDs() {
        for index in playlistRecords.indices {
            let ownerKey = Self.ownerKeyForPlaylist(playlistRecords[index].playlist.id)
            let ids = records
                .flatMap(\.downloadedTracks)
                .filter { $0.ownerKeys.contains(ownerKey) && fileManager.fileExists(atPath: localFileURL(for: $0).path) }
                .map(\.trackID)
            playlistRecords[index].downloadedTrackIDs = uniqueTrackIDs(ids)
            playlistRecords[index].totalBytes = savedBytes(for: playlistRecords[index])
            if playlistRecords[index].downloadedTrackIDs.isEmpty && playlistRecords[index].state.status == .downloaded {
                if let relativePath = playlistRecords[index].localCoverArtRelativePath {
                    try? fileManager.removeItem(at: downloadsDirectory.appendingPathComponent(relativePath, isDirectory: false))
                }
                playlistRecords[index].state = .notDownloaded
                playlistRecords[index].downloadedAt = nil
                playlistRecords[index].localCoverArtRelativePath = nil
                playlistRecords[index].coverArtBytes = 0
                playlistRecords[index].totalBytes = 0
            }
        }
    }

    private func downloadedTrack(for trackID: String) -> DownloadedTrackRecord? {
        records
            .flatMap(\.downloadedTracks)
            .first { $0.trackID == trackID && fileManager.fileExists(atPath: localFileURL(for: $0).path) }
    }

    private func uniqueDownloadedTracks() -> [DownloadedTrackRecord] {
        var seen: Set<String> = []
        var tracks: [DownloadedTrackRecord] = []
        for downloadedTrack in records.flatMap(\.downloadedTracks) where fileManager.fileExists(atPath: localFileURL(for: downloadedTrack).path) {
            guard !seen.contains(downloadedTrack.trackID) else {
                continue
            }
            seen.insert(downloadedTrack.trackID)
            tracks.append(downloadedTrack)
        }
        return tracks
    }

    private func uniqueSavedBytes() -> Int64 {
        let trackBytes = uniqueDownloadedTracks().reduce(into: Int64(0)) { $0 += $1.bytes }
        let coverArtBytes = records.reduce(into: Int64(0)) { $0 += $1.coverArtBytes }
        let playlistCoverArtBytes = playlistRecords.reduce(into: Int64(0)) { $0 += $1.coverArtBytes }
        return trackBytes + coverArtBytes + playlistCoverArtBytes
    }

    private func uniquePinnedBytes() -> Int64 {
        var seen: Set<String> = []
        var bytes: Int64 = 0
        for record in records where record.pinned {
            bytes += record.coverArtBytes
            for downloadedTrack in record.downloadedTracks where fileManager.fileExists(atPath: localFileURL(for: downloadedTrack).path) {
                guard !seen.contains(downloadedTrack.trackID) else {
                    continue
                }
                seen.insert(downloadedTrack.trackID)
                bytes += downloadedTrack.bytes
            }
        }
        return bytes
    }

    private func uniqueTrackIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            unique.append(id)
        }
        return unique
    }

    private func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen: Set<String> = []
        var unique: [Track] = []
        for track in tracks where !seen.contains(track.id) {
            seen.insert(track.id)
            unique.append(track)
        }
        return unique
    }

    private func albumDirectory(albumID: String, createIfNeeded: Bool = false) throws -> URL {
        let directory = downloadsDirectory.appendingPathComponent(albumID, isDirectory: true)
        if createIfNeeded {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func albumDirectory(albumID: String) -> URL? {
        try? albumDirectory(albumID: albumID, createIfNeeded: false)
    }

    private func playlistDirectory(playlistID: String, createIfNeeded: Bool = false) throws -> URL {
        let directory = downloadsDirectory
            .appendingPathComponent("playlists", isDirectory: true)
            .appendingPathComponent(playlistID, isDirectory: true)
        if createIfNeeded {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func playlistDirectory(playlistID: String) -> URL? {
        try? playlistDirectory(playlistID: playlistID, createIfNeeded: false)
    }

    private func localFileURL(for downloadedTrack: DownloadedTrackRecord) -> URL {
        downloadsDirectory.appendingPathComponent(downloadedTrack.relativePath, isDirectory: false)
    }

    private func persist() {
        refreshStoragePolicy()
        let currentRecords = records
        let currentPlaylistRecords = playlistRecords
        let currentHistory = playbackHistory
        Task {
            try? await recordsStore.save(currentRecords)
            try? await playlistRecordsStore?.save(currentPlaylistRecords)
            try? await historyStore.save(currentHistory)
        }
    }
}

enum DownloadError: LocalizedError {
    case pinnedAlbumsExceedCap
    case storageCapExceeded

    var errorDescription: String? {
        switch self {
        case .pinnedAlbumsExceedCap:
            return "Pinned albums already exceed the size limit. Increase the cap or unpin some downloads."
        case .storageCapExceeded:
            return "The size limit would be exceeded by this download."
        }
    }
}
