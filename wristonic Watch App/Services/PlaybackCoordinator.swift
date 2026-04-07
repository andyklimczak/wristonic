import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlaybackCoordinator: NSObject, ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentAlbum: AlbumSummary?
    @Published private(set) var currentRadioStation: InternetRadioStation?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isRepeatingAlbum = false
    @Published var lastError: String?

    private let player = AVPlayer()
    private let downloadManager: DownloadManager
    private let playbackCacheManager: PlaybackCacheManager
    private let playbackReportingManager: PlaybackReportingManager
    private let settingsStore: SettingsStore
    private let clientProvider: () throws -> SubsonicClient
    private var timeObserverToken: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var currentTrackListenSeconds: TimeInterval = 0
    private var currentSourceCandidates: [URL] = []
    private var candidateIndex = 0
    private var nowPlayingArtworkID: String?
    private var nowPlayingArtwork: MPMediaItemArtwork?

    init(
        downloadManager: DownloadManager,
        playbackCacheManager: PlaybackCacheManager,
        playbackReportingManager: PlaybackReportingManager,
        settingsStore: SettingsStore,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.downloadManager = downloadManager
        self.playbackCacheManager = playbackCacheManager
        self.playbackReportingManager = playbackReportingManager
        self.settingsStore = settingsStore
        self.clientProvider = clientProvider
        super.init()
        configureObservers()
        configureRemoteCommands()
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
        currentRadioStation = nil
        currentAlbum = albumDetail.album
        queue = albumDetail.tracks
        currentIndex = min(max(index, 0), max(albumDetail.tracks.count - 1, 0))
        await playCurrentTrack()
    }

    func play(radioStation: InternetRadioStation) {
        finalizePlaybackRecord()
        playbackCacheManager.cancelPrefetch()
        currentTrack = nil
        currentAlbum = nil
        currentRadioStation = radioStation
        queue = []
        currentIndex = 0
        elapsed = 0
        duration = 0
        currentTrackListenSeconds = 0
        currentSourceCandidates = []
        candidateIndex = 0
        lastError = nil
        updateArtworkIfNeeded()

        let item = AVPlayerItem(url: radioStation.streamURL)
        item.preferredForwardBufferDuration = 1
        player.automaticallyWaitsToMinimizeStalling = false
        player.replaceCurrentItem(with: item)
        activateAudioSession()
        player.play()
        isPlaying = player.timeControlStatus == .playing
        isBuffering = !isPlaying
        refreshNowPlayingInfo()
    }

    func togglePlayback() {
        if isPlaying || isBuffering {
            player.pause()
            isPlaying = false
            isBuffering = false
        } else if currentTrack != nil || currentRadioStation != nil {
            activateAudioSession()
            player.play()
            let status = player.timeControlStatus
            isPlaying = status == .playing
            isBuffering = status == .waitingToPlayAtSpecifiedRate || (currentRadioStation != nil && status != .playing)
        }
        refreshNowPlayingInfo()
    }

    func stop() {
        finalizePlaybackRecord()
        playbackCacheManager.cancelPrefetch()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentAlbum = nil
        currentRadioStation = nil
        queue = []
        currentIndex = 0
        isPlaying = false
        isBuffering = false
        elapsed = 0
        duration = 0
        currentTrackListenSeconds = 0
        currentSourceCandidates = []
        candidateIndex = 0
        nowPlayingArtworkID = nil
        nowPlayingArtwork = nil
        refreshNowPlayingInfo()
    }

    func seek(by delta: TimeInterval) {
        guard currentTrack != nil else { return }
        let upperBound = duration > 0 ? duration : max(elapsed + delta, 0)
        let target = min(max(elapsed + delta, 0), upperBound)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time)
        elapsed = target
        currentTrackListenSeconds = max(currentTrackListenSeconds, target)
        refreshNowPlayingInfo()
    }

    func skipForward() async {
        guard currentRadioStation == nil else { return }
        guard currentIndex + 1 < queue.count else { return }
        finalizePlaybackRecord()
        currentIndex += 1
        await playCurrentTrack()
    }

    func skipBackward() async {
        guard currentRadioStation == nil else { return }
        if elapsed > 5 {
            await player.seek(to: .zero)
            refreshNowPlayingInfo()
            return
        }
        guard currentIndex > 0 else { return }
        finalizePlaybackRecord()
        currentIndex -= 1
        await playCurrentTrack()
    }

    func isCurrentTrack(_ track: Track) -> Bool {
        currentTrack?.id == track.id
    }

    func toggleRepeatAlbum() {
        guard currentRadioStation == nil else { return }
        isRepeatingAlbum.toggle()
        refreshNowPlayingInfo()
    }

    private func playCurrentTrack() async {
        guard let track = queue[safe: currentIndex] else { return }
        currentTrack = track
        lastError = nil
        currentTrackListenSeconds = 0
        updateArtworkIfNeeded()

        if let localURL = downloadManager.localFileURL(for: track) {
            currentSourceCandidates = [localURL]
        } else if let cachedURL = playbackCacheManager.localFileURL(for: track) {
            currentSourceCandidates = [cachedURL]
        } else if settingsStore.settings.offlineOnly {
            lastError = "This track is not downloaded."
            isPlaying = false
            isBuffering = false
            return
        } else {
            do {
                currentSourceCandidates = try clientProvider().streamCandidates(for: track, preferTranscoding: true).map(\.request.url!).filter { !$0.absoluteString.isEmpty }
            } catch {
                lastError = error.localizedDescription
                isPlaying = false
                isBuffering = false
                return
            }
        }

        candidateIndex = 0
        startPlaybackCaching()
        refreshNowPlayingInfo()
        await startCurrentCandidate()
    }

    private func startPlaybackCaching() {
        guard !settingsStore.settings.offlineOnly else {
            playbackCacheManager.cancelPrefetch()
            return
        }

        let permanentlyDownloadedTrackIDs = Set(
            queue.compactMap { track in
                downloadManager.localFileURL(for: track) == nil ? nil : track.id
            }
        )
        playbackCacheManager.primePlaybackQueue(queue, currentIndex: currentIndex, excludingTrackIDs: permanentlyDownloadedTrackIDs)
    }

    private func startCurrentCandidate() async {
        guard let track = currentTrack else { return }
        guard let url = currentSourceCandidates[safe: candidateIndex] else {
            lastError = "Unable to play \(track.title)."
            isPlaying = false
            return
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 0
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        activateAudioSession()
        player.play()
        isPlaying = true
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        playbackReportingManager.reportNowPlaying(track: track)
        playbackReportingManager.flushIfNeeded(force: false)
        refreshNowPlayingInfo()
    }

    private func configureObservers() {
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] currentTime in
            guard let self else { return }
            let nextElapsed = currentTime.seconds.isFinite ? currentTime.seconds : 0
            let nextDuration = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0
            let timeControlStatus = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                elapsed = nextElapsed
                duration = nextDuration
                currentTrackListenSeconds = max(currentTrackListenSeconds, nextElapsed)
                isPlaying = timeControlStatus == .playing
                isBuffering = timeControlStatus == .waitingToPlayAtSpecifiedRate
                refreshNowPlayingInfo()
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
        guard currentRadioStation == nil else {
            isPlaying = false
            isBuffering = false
            refreshNowPlayingInfo()
            return
        }
        finalizePlaybackRecord()
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            await playCurrentTrack()
        } else {
            if isRepeatingAlbum, !queue.isEmpty {
                currentIndex = 0
                await playCurrentTrack()
            } else {
                isPlaying = false
                isBuffering = false
                refreshNowPlayingInfo()
            }
        }
    }

    private func finalizePlaybackRecord() {
        guard let track = currentTrack else { return }
        if downloadManager.recordPlayback(for: track, listenedSeconds: currentTrackListenSeconds) {
            playbackReportingManager.enqueueScrobble(for: track)
        }
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        commandCenter.playCommand.addTarget(self, action: #selector(handlePlayCommand(_:)))
        commandCenter.pauseCommand.addTarget(self, action: #selector(handlePauseCommand(_:)))
        commandCenter.nextTrackCommand.addTarget(self, action: #selector(handleNextTrackCommand(_:)))
        commandCenter.previousTrackCommand.addTarget(self, action: #selector(handlePreviousTrackCommand(_:)))
        commandCenter.togglePlayPauseCommand.addTarget(self, action: #selector(handleTogglePlayPauseCommand(_:)))
    }

    private func refreshNowPlayingInfo() {
        if let station = currentRadioStation {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: station.name,
                MPMediaItemPropertyArtist: "Internet Radio",
                MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
            ]

            if let nowPlayingArtwork {
                info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
            }

            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            return
        }

        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyAlbumTitle: track.albumName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count
        ]

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateArtworkIfNeeded() {
        guard let coverArtID = currentAlbum?.coverArtID ?? currentRadioStation?.coverArtID else {
            nowPlayingArtworkID = nil
            nowPlayingArtwork = nil
            refreshNowPlayingInfo()
            return
        }

        guard nowPlayingArtworkID != coverArtID || nowPlayingArtwork == nil else {
            return
        }

        nowPlayingArtworkID = coverArtID
        nowPlayingArtwork = nil

        guard let client = try? clientProvider(),
              let coverArtURL = client.coverArtURL(for: coverArtID) else {
            refreshNowPlayingInfo()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard nowPlayingArtworkID == coverArtID else { return }
            guard let image = await CoverArtStore.shared.uiImage(for: coverArtURL, loader: { url in
                if url.isFileURL {
                    return try Data(contentsOf: url)
                }
                return try await client.data(for: URLRequest(url: url)).0
            }) else {
                refreshNowPlayingInfo()
                return
            }

            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            refreshNowPlayingInfo()
        }
    }

    @objc
    private func handlePlayCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil || currentRadioStation != nil else { return .commandFailed }
        if !isPlaying && !isBuffering {
            activateAudioSession()
            player.play()
            let status = player.timeControlStatus
            isPlaying = status == .playing
            isBuffering = status == .waitingToPlayAtSpecifiedRate || (currentRadioStation != nil && status != .playing)
            refreshNowPlayingInfo()
        }
        return .success
    }

    @objc
    private func handlePauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil || currentRadioStation != nil else { return .commandFailed }
        if isPlaying || isBuffering {
            player.pause()
            isPlaying = false
            isBuffering = false
            refreshNowPlayingInfo()
        }
        return .success
    }

    @objc
    private func handleNextTrackCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard currentRadioStation == nil else { return .commandFailed }
        guard currentIndex + 1 < queue.count else { return .commandFailed }
        Task { await skipForward() }
        return .success
    }

    @objc
    private func handlePreviousTrackCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard currentRadioStation == nil else { return .commandFailed }
        guard !queue.isEmpty else { return .commandFailed }
        Task { await skipBackward() }
        return .success
    }

    @objc
    private func handleTogglePlayPauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil || currentRadioStation != nil else { return .commandFailed }
        togglePlayback()
        return .success
    }
}
