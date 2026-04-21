import Foundation

@MainActor
final class PlaybackCacheManager {
    private let recordsStore: JSONFileStore<[PlaybackCacheRecord]>
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let clientProvider: () throws -> SubsonicClient
    private let prefetchTrackCount: Int
    private(set) var records: [PlaybackCacheRecord] = []
    private var warmCacheTask: Task<Void, Never>?

    init(
        recordsStore: JSONFileStore<[PlaybackCacheRecord]>,
        cacheDirectory: URL,
        fileManager: FileManager = .default,
        prefetchTrackCount: Int = 3,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.recordsStore = recordsStore
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
        self.prefetchTrackCount = prefetchTrackCount
        self.clientProvider = clientProvider
    }

    func load() async {
        let loadedRecords = (try? await recordsStore.load(default: [])) ?? []
        records = loadedRecords.filter { record in
            fileManager.fileExists(atPath: localFileURL(for: record).path)
        }
        persist()
    }

    func cancelPrefetch() {
        warmCacheTask?.cancel()
        warmCacheTask = nil
    }

    func clear() async {
        cancelPrefetch()
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
        }
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        records.removeAll()
        try? await recordsStore.deleteFile()
    }

    func localFileURL(for track: Track) -> URL? {
        guard let index = records.firstIndex(where: { $0.trackID == track.id }) else {
            return nil
        }

        let url = localFileURL(for: records[index])
        guard fileManager.fileExists(atPath: url.path) else {
            records.remove(at: index)
            persist()
            return nil
        }

        records[index].lastAccessedAt = Date()
        persist()
        return url
    }

    func primePlaybackQueue(_ queue: [Track], currentIndex: Int, excludingTrackIDs: Set<String>) {
        guard queue.indices.contains(currentIndex) else {
            cancelPrefetch()
            return
        }

        let startIndex = currentIndex + 1
        guard queue.indices.contains(startIndex) else {
            trimCache(keeping: [])
            cancelPrefetch()
            return
        }

        let endIndex = min(startIndex + prefetchTrackCount - 1, queue.count - 1)
        let desiredTracks = Array(queue[startIndex...endIndex]).filter { !excludingTrackIDs.contains($0.id) }
        let desiredTrackIDs = Set(desiredTracks.map(\.id))

        trimCache(keeping: desiredTrackIDs)

        guard !desiredTracks.isEmpty else {
            cancelPrefetch()
            return
        }

        warmCacheTask?.cancel()
        warmCacheTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { warmCacheTask = nil }

            guard let client = try? clientProvider() else {
                return
            }

            for track in desiredTracks {
                guard !Task.isCancelled else {
                    return
                }
                if localFileURL(for: track) != nil {
                    continue
                }
                guard let cached = try? await cacheTrack(track, client: client) else {
                    continue
                }
                records.removeAll { $0.trackID == track.id }
                records.append(cached)
                trimCache(keeping: desiredTrackIDs)
                persist()
            }
        }
    }

    private func cacheTrack(_ track: Track, client: SubsonicClient) async throws -> PlaybackCacheRecord {
        let candidates = client.streamCandidates(for: track, preferTranscoding: true)
        guard !candidates.isEmpty else {
            throw SubsonicClientError.unsupportedMediaType
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                let (temporaryURL, _) = try await client.download(for: candidate.request)
                if Task.isCancelled {
                    try? fileManager.removeItem(at: temporaryURL)
                    throw CancellationError()
                }

                let fileName = "\(track.albumID)-\(track.trackNumber)-\(track.id).\(candidate.fileExtension)"
                let destinationURL = cacheDirectory.appendingPathComponent(fileName, isDirectory: false)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let now = Date()
                return PlaybackCacheRecord(
                    trackID: track.id,
                    relativePath: fileName,
                    bytes: fileSize,
                    cachedAt: now,
                    lastAccessedAt: now
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        throw lastError ?? SubsonicClientError.unsupportedMediaType
    }

    private func trimCache(keeping desiredTrackIDs: Set<String>) {
        let removable = records.filter { !desiredTrackIDs.contains($0.trackID) }
        guard !removable.isEmpty else {
            return
        }

        for record in removable {
            try? fileManager.removeItem(at: localFileURL(for: record))
        }
        records.removeAll { !desiredTrackIDs.contains($0.trackID) }
        persist()
    }

    private func localFileURL(for record: PlaybackCacheRecord) -> URL {
        cacheDirectory.appendingPathComponent(record.relativePath, isDirectory: false)
    }

    private func persist() {
        let currentRecords = records
        Task {
            try? await recordsStore.save(currentRecords)
        }
    }
}
