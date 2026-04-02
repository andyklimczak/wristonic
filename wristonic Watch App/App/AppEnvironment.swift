import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let settingsStore: SettingsStore
    let repository: LibraryRepository
    let downloadManager: DownloadManager
    let playbackCacheManager: PlaybackCacheManager
    let playbackReportingManager: PlaybackReportingManager
    let playbackCoordinator: PlaybackCoordinator

    private let transportFactory: (ServerConfiguration) -> Transporting
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore,
        repository: LibraryRepository,
        downloadManager: DownloadManager,
        playbackCacheManager: PlaybackCacheManager,
        playbackReportingManager: PlaybackReportingManager,
        playbackCoordinator: PlaybackCoordinator,
        transportFactory: @escaping (ServerConfiguration) -> Transporting
    ) {
        self.settingsStore = settingsStore
        self.repository = repository
        self.downloadManager = downloadManager
        self.playbackCacheManager = playbackCacheManager
        self.playbackReportingManager = playbackReportingManager
        self.playbackCoordinator = playbackCoordinator
        self.transportFactory = transportFactory
        bindChildObjects()
    }

    static func live() throws -> AppEnvironment {
        if DemoMode.isEnabled {
            return try demo()
        }

        let settingsStore = SettingsStore()
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: try AppPaths.storeFile(named: "cache.json"))
        let recordsStore = JSONFileStore<[DownloadRecord]>(url: try AppPaths.storeFile(named: "downloads.json"))
        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: try AppPaths.storeFile(named: "playback-history.json"))
        let playbackCacheStore = JSONFileStore<[PlaybackCacheRecord]>(url: try AppPaths.storeFile(named: "playback-cache.json"))
        let playbackScrobbleStore = JSONFileStore<[PendingPlaybackScrobble]>(url: try AppPaths.storeFile(named: "playback-scrobbles.json"))
        let downloadsDirectory = try AppPaths.downloadsDirectory()
        let playbackCacheDirectory = try AppPaths.playbackCacheDirectory()

        let transportFactory: (ServerConfiguration) -> Transporting = { configuration in
            URLSessionTransport(
                allowInsecureConnections: configuration.allowInsecureConnections,
                allowedHost: configuration.baseURL.host
            )
        }

        var environment: AppEnvironment!

        let downloadManager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: recordsStore,
            historyStore: historyStore,
            downloadsDirectory: downloadsDirectory,
            clientProvider: {
                try environment.makeClient()
            }
        )

        let playbackCacheManager = PlaybackCacheManager(
            recordsStore: playbackCacheStore,
            cacheDirectory: playbackCacheDirectory,
            clientProvider: {
                try environment.makeClient()
            }
        )

        let playbackReportingManager = PlaybackReportingManager(
            queueStore: playbackScrobbleStore,
            settingsStore: settingsStore,
            clientProvider: {
                try environment.makeClient()
            }
        )

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: {
                try environment.makeClient()
            },
            downloadRecordsProvider: {
                downloadManager.records
            }
        )

        let playbackCoordinator = PlaybackCoordinator(
            downloadManager: downloadManager,
            playbackCacheManager: playbackCacheManager,
            playbackReportingManager: playbackReportingManager,
            settingsStore: settingsStore,
            clientProvider: {
                try environment.makeClient()
            }
        )

        environment = AppEnvironment(
            settingsStore: settingsStore,
            repository: repository,
            downloadManager: downloadManager,
            playbackCacheManager: playbackCacheManager,
            playbackReportingManager: playbackReportingManager,
            playbackCoordinator: playbackCoordinator,
            transportFactory: transportFactory
        )
        return environment
    }

    static func demo() throws -> AppEnvironment {
        let suiteName = "com.andy.wristonic.demo"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "com.andy.wristonic.demo"))
        settingsStore.settings.serverURLString = "https://demo.navidrome.local"
        settingsStore.settings.username = "demo"
        settingsStore.password = "demo"

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("wristonic-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let cacheStore = JSONFileStore<CachedLibrarySnapshot>(url: tempRoot.appendingPathComponent("cache.json"))
        let recordsStore = JSONFileStore<[DownloadRecord]>(url: tempRoot.appendingPathComponent("downloads.json"))
        let historyStore = JSONFileStore<[String: PlaybackHistory]>(url: tempRoot.appendingPathComponent("history.json"))
        let playbackCacheStore = JSONFileStore<[PlaybackCacheRecord]>(url: tempRoot.appendingPathComponent("playback-cache.json"))
        let playbackScrobbleStore = JSONFileStore<[PendingPlaybackScrobble]>(url: tempRoot.appendingPathComponent("playback-scrobbles.json"))
        let downloadsDirectory = tempRoot.appendingPathComponent("downloads", isDirectory: true)
        let playbackCacheDirectory = tempRoot.appendingPathComponent("playback-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: playbackCacheDirectory, withIntermediateDirectories: true)

        if ProcessInfo.processInfo.environment["WRISTONIC_PRESEED_DOWNLOADS"] == "1" {
            let albumDirectory = downloadsDirectory.appendingPathComponent("album-1", isDirectory: true)
            try FileManager.default.createDirectory(at: albumDirectory, withIntermediateDirectories: true)
            let fileURL = albumDirectory.appendingPathComponent("1-track-1.mp3")
            try Data(repeating: 0x1, count: 1024).write(to: fileURL)
            let record = DownloadRecord(
                album: AlbumSummary(
                    id: "album-1",
                    name: "Analog Dawn",
                    artistID: "artist-1",
                    artistName: "Aurora Echo",
                    coverArtID: "cover-1",
                    songCount: 2,
                    duration: 420,
                    year: 2024,
                    createdAt: ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")
                ),
                tracks: [
                    Track(id: "track-1", albumID: "album-1", title: "First Light", artistID: "artist-1", artistName: "Aurora Echo", albumName: "Analog Dawn", duration: 210, trackNumber: 1, discNumber: 1, contentType: "audio/mpeg", suffix: "mp3", path: nil),
                    Track(id: "track-2", albumID: "album-1", title: "Glass Signal", artistID: "artist-1", artistName: "Aurora Echo", albumName: "Analog Dawn", duration: 210, trackNumber: 2, discNumber: 1, contentType: "audio/mpeg", suffix: "mp3", path: nil)
                ],
                downloadedTracks: [
                    DownloadedTrackRecord(trackID: "track-1", relativePath: "album-1/1-track-1.mp3", bytes: 1024)
                ],
                pinned: false,
                state: DownloadState(status: .downloaded, progress: 1, errorMessage: nil),
                downloadedAt: Date(),
                totalBytes: 1024,
                playCount: 1,
                lastPlayedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode([record])
            try data.write(to: tempRoot.appendingPathComponent("downloads.json"), options: .atomic)
        }

        let transportFactory: (ServerConfiguration) -> Transporting = { _ in
            DemoTransport()
        }

        var environment: AppEnvironment!

        let downloadManager = DownloadManager(
            settingsStore: settingsStore,
            recordsStore: recordsStore,
            historyStore: historyStore,
            downloadsDirectory: downloadsDirectory,
            clientProvider: {
                try environment.makeClient()
            }
        )

        let playbackCacheManager = PlaybackCacheManager(
            recordsStore: playbackCacheStore,
            cacheDirectory: playbackCacheDirectory,
            clientProvider: {
                try environment.makeClient()
            }
        )

        let playbackReportingManager = PlaybackReportingManager(
            queueStore: playbackScrobbleStore,
            settingsStore: settingsStore,
            clientProvider: {
                try environment.makeClient()
            }
        )

        let repository = LibraryRepository(
            cacheStore: cacheStore,
            settingsStore: settingsStore,
            clientProvider: {
                try environment.makeClient()
            },
            downloadRecordsProvider: {
                downloadManager.records
            }
        )

        let playbackCoordinator = PlaybackCoordinator(
            downloadManager: downloadManager,
            playbackCacheManager: playbackCacheManager,
            playbackReportingManager: playbackReportingManager,
            settingsStore: settingsStore,
            clientProvider: {
                try environment.makeClient()
            }
        )

        environment = AppEnvironment(
            settingsStore: settingsStore,
            repository: repository,
            downloadManager: downloadManager,
            playbackCacheManager: playbackCacheManager,
            playbackReportingManager: playbackReportingManager,
            playbackCoordinator: playbackCoordinator,
            transportFactory: transportFactory
        )
        return environment
    }

    func bootstrap() async {
        await settingsStore.persist()
        await repository.loadCachedSnapshot()
        await downloadManager.load()
        await playbackCacheManager.load()
        await playbackReportingManager.load()
        playbackReportingManager.flushIfNeeded(force: false)
    }

    func makeClient() throws -> SubsonicClient {
        let configuration = try settingsStore.buildServerConfiguration()
        return SubsonicClient(configuration: configuration, transport: transportFactory(configuration))
    }

    private func bindChildObjects() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        downloadManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        playbackCoordinator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
