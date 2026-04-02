import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentAlbum: AlbumSummary?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var lastError: String?

    private let player = AVPlayer()
    private let downloadManager: DownloadManager
    private let settingsStore: SettingsStore
    private let clientProvider: () throws -> SubsonicClient
    private var timeObserverToken: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var currentTrackListenSeconds: TimeInterval = 0
    private var currentSourceCandidates: [URL] = []
    private var candidateIndex = 0

    init(
        downloadManager: DownloadManager,
        settingsStore: SettingsStore,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.downloadManager = downloadManager
        self.settingsStore = settingsStore
        self.clientProvider = clientProvider
        configureObservers()
    }

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
    }

    func play(albumDetail: AlbumDetail, startAt index: Int) async {
        currentAlbum = albumDetail.album
        queue = albumDetail.tracks
        currentIndex = min(max(index, 0), max(albumDetail.tracks.count - 1, 0))
        await playCurrentTrack()
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func skipForward() async {
        guard currentIndex + 1 < queue.count else { return }
        finalizePlaybackRecord()
        currentIndex += 1
        await playCurrentTrack()
    }

    func skipBackward() async {
        if elapsed > 5 {
            await player.seek(to: .zero)
            return
        }
        guard currentIndex > 0 else { return }
        finalizePlaybackRecord()
        currentIndex -= 1
        await playCurrentTrack()
    }

    private func playCurrentTrack() async {
        guard let track = queue[safe: currentIndex] else { return }
        currentTrack = track
        lastError = nil
        currentTrackListenSeconds = 0

        if let localURL = downloadManager.localFileURL(for: track) {
            currentSourceCandidates = [localURL]
        } else if settingsStore.settings.offlineOnly {
            lastError = "This track is not downloaded."
            isPlaying = false
            return
        } else {
            do {
                currentSourceCandidates = try clientProvider().streamCandidates(for: track, preferTranscoding: true).map(\.request.url!).filter { !$0.absoluteString.isEmpty }
            } catch {
                lastError = error.localizedDescription
                isPlaying = false
                return
            }
        }

        candidateIndex = 0
        await startCurrentCandidate()
    }

    private func startCurrentCandidate() async {
        guard let track = currentTrack else { return }
        guard let url = currentSourceCandidates[safe: candidateIndex] else {
            lastError = "Unable to play \(track.title)."
            isPlaying = false
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
    }

    private func configureObservers() {
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] currentTime in
            guard let self else { return }
            let nextElapsed = currentTime.seconds.isFinite ? currentTime.seconds : 0
            let nextDuration = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                guard let self else { return }
                elapsed = nextElapsed
                duration = nextDuration
                currentTrackListenSeconds = max(currentTrackListenSeconds, nextElapsed)
                isPlaying = playing
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, notification.object as? AVPlayerItem === player.currentItem else { return }
            Task { await self.handleTrackFinished() }
        }
    }

    private func handleTrackFinished() async {
        finalizePlaybackRecord()
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            await playCurrentTrack()
        } else {
            isPlaying = false
        }
    }

    private func finalizePlaybackRecord() {
        guard let track = currentTrack else { return }
        downloadManager.recordPlayback(for: track, listenedSeconds: currentTrackListenSeconds)
    }
}
