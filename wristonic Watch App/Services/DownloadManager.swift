import Combine
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []
    @Published private(set) var storagePolicy = StoragePolicy(capBytes: 8_000_000_000, savedBytes: 0, pinnedBytes: 0)

    private let recordsStore: JSONFileStore<[DownloadRecord]>
    private let historyStore: JSONFileStore<[String: PlaybackHistory]>
    private let settingsStore: SettingsStore
    private let clientProvider: () throws -> SubsonicClient
    private let fileManager: FileManager
    private let downloadsDirectory: URL
    private var playbackHistory: [String: PlaybackHistory] = [:]
    private var processingTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        recordsStore: JSONFileStore<[DownloadRecord]>,
        historyStore: JSONFileStore<[String: PlaybackHistory]>,
        downloadsDirectory: URL,
        fileManager: FileManager = .default,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.settingsStore = settingsStore
        self.recordsStore = recordsStore
        self.historyStore = historyStore
        self.downloadsDirectory = downloadsDirectory
        self.fileManager = fileManager
        self.clientProvider = clientProvider
    }

    func load() async {
        let loadedRecords = (try? await recordsStore.load(default: [])) ?? []
        let loadedHistory = (try? await historyStore.load(default: [:])) ?? [:]
        playbackHistory = loadedHistory
        records = loadedRecords.map { record in
            var updated = record
            if updated.state.status == .downloading {
                updated.state = DownloadState(status: .queued, progress: 0, errorMessage: nil)
            }
            updated.downloadedTracks = updated.downloadedTracks.filter { downloadedTrack in
                fileManager.fileExists(atPath: localFileURL(for: downloadedTrack).path)
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
        refreshStoragePolicy()
        persist()
        startProcessingQueueIfNeeded()
    }

    func state(for albumID: String) -> DownloadState {
        records.first(where: { $0.album.id == albumID })?.state ?? .notDownloaded
    }

    func isPinned(albumID: String) -> Bool {
        records.first(where: { $0.album.id == albumID })?.pinned ?? false
    }

    func hasLocalContent(albumID: String) -> Bool {
        records.first(where: { $0.album.id == albumID })?.hasDownloadedContent ?? false
    }

    func hasDownloadedArtist(artistID: String) -> Bool {
        records.contains { $0.album.artistID == artistID && $0.hasDownloadedContent }
    }

    func localFileURL(for track: Track) -> URL? {
        guard let downloadedTrack = records.first(where: { $0.album.id == track.albumID })?.downloadedTracks.first(where: { $0.trackID == track.id }) else {
            return nil
        }
        return localFileURL(for: downloadedTrack)
    }

    func localCoverArtURL(for albumID: String) -> URL? {
        guard let relativePath = records.first(where: { $0.album.id == albumID })?.localCoverArtRelativePath else {
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

    func deleteDownloadedAlbum(albumID: String) {
        guard let index = records.firstIndex(where: { $0.album.id == albumID }) else {
            return
        }
        let record = records[index]
        record.downloadedTracks.forEach { downloadedTrack in
            try? fileManager.removeItem(at: localFileURL(for: downloadedTrack))
        }
        if let directory = albumDirectory(albumID: albumID), fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }
        records[index].downloadedTracks = []
        records[index].localCoverArtRelativePath = nil
        records[index].coverArtBytes = 0
        records[index].state = .notDownloaded
        records[index].downloadedAt = nil
        records[index].totalBytes = 0
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
        playbackHistory.removeAll()
        refreshStoragePolicy()
        try? await recordsStore.deleteFile()
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
        let savedBytes = records.reduce(into: Int64(0)) { partialResult, record in
            partialResult += record.savedBytes
        }
        let pinnedBytes = records.filter(\.pinned).reduce(into: Int64(0)) { partialResult, record in
            partialResult += record.savedBytes
        }
        storagePolicy = StoragePolicy(capBytes: settingsStore.capBytes, savedBytes: savedBytes, pinnedBytes: pinnedBytes)
        settingsStore.updateSavedBytes(savedBytes)
    }

    func downloadedRecords() -> [DownloadRecord] {
        records.filter(\.hasDownloadedContent)
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
        while let index = records.firstIndex(where: { $0.state.status == .queued }) {
            do {
                try await download(recordAt: index)
            } catch {
                records[index].state = DownloadState(status: .failed, progress: 0, errorMessage: error.localizedDescription)
                persist()
            }
        }
    }

    private func download(recordAt index: Int) async throws {
        let record = records[index]
        let projectedExisting = storagePolicy.savedBytes - record.savedBytes
        if projectedExisting >= settingsStore.capBytes && !record.pinned {
            try enforceStorageCap(projectedAdditionalBytes: 0, excludingAlbumID: record.album.id)
        }

        let client = try clientProvider()
        records[index].state = DownloadState(status: .downloading, progress: 0, errorMessage: nil)
        persist()

        let totalTrackCount = max(record.tracks.count, 1)
        var downloadedTracks = record.downloadedTracks

        for (offset, track) in record.tracks.enumerated() {
            if downloadedTracks.contains(where: { $0.trackID == track.id }) {
                records[index].state = DownloadState(
                    status: .downloading,
                    progress: Double(offset + 1) / Double(totalTrackCount),
                    errorMessage: nil,
                    transferRateBytesPerSecond: nil
                )
                continue
            }

            let albumID = record.album.id
            let completedTracks = downloadedTracks.count
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
            downloadedTracks.append(downloaded)
            records[index].downloadedTracks = downloadedTracks
            records[index].state = DownloadState(
                status: .downloading,
                progress: Double(offset + 1) / Double(totalTrackCount),
                errorMessage: nil,
                transferRateBytesPerSecond: nil
            )
            persist()
        }

        if let downloadedCoverArt = try await downloadCoverArt(for: record.album, client: client) {
            records[index].localCoverArtRelativePath = downloadedCoverArt.relativePath
            records[index].coverArtBytes = downloadedCoverArt.bytes
        }

        records[index].downloadedTracks = downloadedTracks
        records[index].downloadedAt = Date()
        records[index].totalBytes = downloadedTracks.reduce(into: Int64(0)) { $0 += $1.bytes }
        records[index].state = DownloadState(status: .downloaded, progress: 1, errorMessage: nil, transferRateBytesPerSecond: nil)
        refreshStoragePolicy()
        try enforceStorageCap(projectedAdditionalBytes: 0, excludingAlbumID: nil)
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
                let temporaryURL = try await BackgroundDownloadService.shared.download(for: candidate.request) { totalBytesWritten, totalBytesExpectedToWrite, bytesPerSecond in
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

        let temporaryURL = try await BackgroundDownloadService.shared.download(for: URLRequest(url: coverArtURL))
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

    private func enforceStorageCap(projectedAdditionalBytes: Int64, excludingAlbumID: String?) throws {
        refreshStoragePolicy()
        var projectedSavedBytes = storagePolicy.savedBytes + projectedAdditionalBytes
        guard projectedSavedBytes > settingsStore.capBytes else {
            return
        }

        let pinnedBytes = records.filter(\.pinned).reduce(into: Int64(0)) { $0 += $1.savedBytes }
        guard pinnedBytes <= settingsStore.capBytes else {
            throw DownloadError.pinnedAlbumsExceedCap
        }

        let candidates = records
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

        for candidate in candidates where projectedSavedBytes > settingsStore.capBytes {
            deleteDownloadedAlbum(albumID: candidate.album.id)
            projectedSavedBytes = storagePolicy.savedBytes + projectedAdditionalBytes
        }

        if projectedSavedBytes > settingsStore.capBytes {
            throw DownloadError.storageCapExceeded
        }
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

    private func localFileURL(for downloadedTrack: DownloadedTrackRecord) -> URL {
        downloadsDirectory.appendingPathComponent(downloadedTrack.relativePath, isDirectory: false)
    }

    private func persist() {
        refreshStoragePolicy()
        let currentRecords = records
        let currentHistory = playbackHistory
        Task {
            try? await recordsStore.save(currentRecords)
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
