import AVFoundation
import Combine
import Foundation
import MediaPlayer
import OSLog
import UIKit
import WatchKit

enum PlaybackTimeline {
    static func checkpoint(elapsed: TimeInterval, playerTime: TimeInterval) -> TimeInterval {
        if playerTime.isFinite, playerTime > 0 { return playerTime }
        return elapsed.isFinite ? max(0, elapsed) : 0
    }

    static func endedEarly(at position: TimeInterval, expectedDuration: TimeInterval?) -> Bool {
        guard let expectedDuration, expectedDuration.isFinite, expectedDuration > 0 else { return false }
        // Compare against library metadata, not the duration of a truncated AVPlayerItem.
        return expectedDuration - position > max(5, expectedDuration * 0.05)
    }

    static func reachedCheckpoint(_ checkpoint: TimeInterval, actual: TimeInterval, seekFinished: Bool) -> Bool {
        seekFinished && actual.isFinite && abs(actual - checkpoint) <= 0.25
    }
}

private struct TrackPlaybackSource {
    enum Kind: String { case saved, cached, stream }
    let kind: Kind
    let url: URL
}

private enum TrackPlaybackError: LocalizedError {
    case offline
    case incompleteTrack
    case checkpointUnavailable

    var errorDescription: String? {
        switch self {
        case .offline: return "This track is not downloaded."
        case .incompleteTrack: return "The audio ended before the track finished."
        case .checkpointUnavailable: return "Unable to resume at the previous position."
        }
    }
}

protocol AudioSessionManaging {
    func activatePlaybackSession() async throws
}

struct LiveAudioSessionManager: AudioSessionManaging {
    func activatePlaybackSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.activate(options: []) { activated, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if activated {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AudioSessionActivationError.notActivated)
                }
            }
        }
    }
}

private enum AudioSessionActivationError: LocalizedError {
    case notActivated

    var errorDescription: String? {
        "Session activation failed."
    }
}

@MainActor
final class PlaybackCoordinator: NSObject, ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var currentAlbum: AlbumSummary?
    @Published private(set) var currentPlaylist: PlaylistSummary?
    @Published private(set) var currentRadioStation: InternetRadioStation?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isRepeatingAlbum = false
    @Published var lastError: String?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "wristonic", category: "Playback")
    private let player: AVPlayer
    private let downloadManager: DownloadManager
    private let playbackCacheManager: PlaybackCacheManager
    private let playbackReportingManager: PlaybackReportingManager
    private let settingsStore: SettingsStore
    private let audioSessionManager: AudioSessionManaging
    private let validateAudio: LocalAudioFile.Validator
    private let clientProvider: () throws -> SubsonicClient
    private var timeObserverToken: Any?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemTimeJumpObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var currentTrackListenSeconds: TimeInterval = 0
    private var trackSource: TrackPlaybackSource?
    private var pendingRecoveryPosition: TimeInterval?
    private var attemptedRecovery = false
    private var startedCurrentItem = false
    private var reportedCurrentTrack = false
    private var sourcePreparationTask: Task<URL, Error>?
    private var nowPlayingArtworkID: String?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var shouldPlayAlbumStartHaptic = false
    private var shouldResumePlaybackAfterInterruption = false
    private var playbackRequested = false
    private var playbackRequestGeneration = 0
    // A paused AVPlayer during validation/session activation must not clear the
    // loading state or turn a user's pause into a second playback request.
    private var preparingPlaybackRequest: Int?

    init(
        downloadManager: DownloadManager,
        playbackCacheManager: PlaybackCacheManager,
        playbackReportingManager: PlaybackReportingManager,
        settingsStore: SettingsStore,
        audioSessionManager: AudioSessionManaging? = nil,
        validateAudio: LocalAudioFile.Validator? = nil,
        player: AVPlayer? = nil,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.downloadManager = downloadManager
        self.playbackCacheManager = playbackCacheManager
        self.playbackReportingManager = playbackReportingManager
        self.settingsStore = settingsStore
        self.audioSessionManager = audioSessionManager ?? LiveAudioSessionManager()
        self.validateAudio = validateAudio ?? LocalAudioFile.validate
        self.player = player ?? AVPlayer()
        self.clientProvider = clientProvider
        super.init()
        isRepeatingAlbum = settingsStore.settings.isRepeatingAlbum
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
        if let itemFailureObserver {
            NotificationCenter.default.removeObserver(itemFailureObserver)
        }
        if let itemTimeJumpObserver {
            NotificationCenter.default.removeObserver(itemTimeJumpObserver)
        }
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
        }
        timeControlStatusObserver?.invalidate()
        itemStatusObserver?.invalidate()
    }

    func play(albumDetail: AlbumDetail, startAt index: Int, shuffled: Bool = false) async {
        playbackRequested = true
        currentRadioStation = nil
        currentPlaylist = nil
        currentAlbum = albumDetail.album
        queue = shuffled ? albumDetail.tracks.shuffled() : albumDetail.tracks
        currentIndex = shuffled ? 0 : min(max(index, 0), max(albumDetail.tracks.count - 1, 0))
        shouldPlayAlbumStartHaptic = true
        await playCurrentTrack()
    }

    func play(playlistDetail: PlaylistDetail, startAt index: Int, shuffled: Bool = false) async {
        playbackRequested = true
        currentRadioStation = nil
        currentAlbum = nil
        currentPlaylist = playlistDetail.playlist
        queue = shuffled ? playlistDetail.tracks.shuffled() : playlistDetail.tracks
        currentIndex = shuffled ? 0 : min(max(index, 0), max(playlistDetail.tracks.count - 1, 0))
        shouldPlayAlbumStartHaptic = true
        await playCurrentTrack()
    }

    func play(radioStation: InternetRadioStation) async {
        playbackRequested = true
        finalizePlaybackRecord()
        playbackCacheManager.cancelPrefetch()
        currentTrack = nil
        currentAlbum = nil
        currentPlaylist = nil
        currentRadioStation = radioStation
        queue = []
        currentIndex = 0
        shouldPlayAlbumStartHaptic = false
        elapsed = 0
        duration = 0
        currentTrackListenSeconds = 0
        resetTrackPreparation()
        lastError = nil
        updateArtworkIfNeeded()

        let item = AVPlayerItem(url: radioStation.streamURL)
        item.preferredForwardBufferDuration = 1
        player.automaticallyWaitsToMinimizeStalling = false
        observeCurrentItem(item)
        player.replaceCurrentItem(with: item)
        let requestGeneration = beginPlaybackRequest()
        defer { finishPreparingPlaybackRequest(requestGeneration) }
        guard await activateAudioSession(for: requestGeneration) else { return }
        shouldResumePlaybackAfterInterruption = false
        player.play()
        isPlaying = player.timeControlStatus == .playing
        isBuffering = !isPlaying
        refreshNowPlayingInfo()
    }

    func togglePlayback() async {
        if playbackRequested && (isPlaying || isBuffering || preparingPlaybackRequest != nil) {
            pausePlayback()
        } else if currentTrack != nil || currentRadioStation != nil {
            playbackRequested = true
            await resumePlayback()
        }
        refreshNowPlayingInfo()
    }

    func stop() {
        cancelPlaybackRequest()
        finalizePlaybackRecord()
        playbackCacheManager.cancelPrefetch()
        player.pause()
        removeCurrentItemObservers()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentAlbum = nil
        currentPlaylist = nil
        currentRadioStation = nil
        queue = []
        currentIndex = 0
        shouldPlayAlbumStartHaptic = false
        isPlaying = false
        isBuffering = false
        elapsed = 0
        duration = 0
        currentTrackListenSeconds = 0
        resetTrackPreparation()
        shouldResumePlaybackAfterInterruption = false
        nowPlayingArtworkID = nil
        nowPlayingArtwork = nil
        refreshNowPlayingInfo()
    }

    func seek(by delta: TimeInterval) {
        guard currentTrack != nil, pendingRecoveryPosition == nil, preparingPlaybackRequest == nil else { return }
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
            guard pendingRecoveryPosition == nil, preparingPlaybackRequest == nil else { return }
            let item = player.currentItem
            if await player.seek(to: .zero), item === player.currentItem {
                elapsed = 0
                refreshNowPlayingInfo()
            }
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
        settingsStore.settings.isRepeatingAlbum = isRepeatingAlbum
        Task { await settingsStore.persist() }
        refreshNowPlayingInfo()
    }

    private func playCurrentTrack() async {
        guard let track = queue[safe: currentIndex] else {
            shouldPlayAlbumStartHaptic = false
            return
        }
        resetTrackPreparation()
        currentTrack = track
        lastError = nil
        elapsed = 0
        duration = track.duration ?? 0
        currentTrackListenSeconds = 0
        updateArtworkIfNeeded()
        await startTrackPlayback()
    }

    private func resolveTrackSource(_ track: Track, recovering: Bool) async throws -> TrackPlaybackSource {
        if !recovering, let url = downloadManager.localFileURL(for: track) {
            return TrackPlaybackSource(kind: .saved, url: url)
        }
        if let url = playbackCacheManager.localFileURL(for: track) {
            return TrackPlaybackSource(kind: .cached, url: url)
        }
        guard !settingsStore.settings.offlineOnly else { throw TrackPlaybackError.offline }

        // A cold start still streams immediately. Only the recovery path (or a
        // connection requiring our transport) waits for a seekable local file.
        if recovering || requiresTransportBackedPlayback {
            let task = Task { try await playbackCacheManager.cacheTrackForPlayback(track) }
            sourcePreparationTask = task
            return TrackPlaybackSource(kind: .cached, url: try await task.value)
        }
        let candidate = try clientProvider().streamCandidates(for: track, preferTranscoding: true).first
        guard let url = candidate?.request.url else { throw SubsonicClientError.unsupportedMediaType }
        return TrackPlaybackSource(kind: .stream, url: url)
    }

    private func resetTrackPreparation() {
        sourcePreparationTask?.cancel()
        sourcePreparationTask = nil
        trackSource = nil
        pendingRecoveryPosition = nil
        attemptedRecovery = false
        reportedCurrentTrack = false
    }

    private var requiresTransportBackedPlayback: Bool {
        settingsStore.settings.allowInsecureConnections &&
        settingsStore.normalizedURL?.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
    }

    private func startPlaybackCaching() {
        guard !settingsStore.settings.offlineOnly else {
            playbackCacheManager.cancelPrefetch()
            return
        }

        guard queue.indices.contains(currentIndex), queue.indices.contains(currentIndex + 1) else {
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

    private func startTrackPlayback() async {
        guard let track = currentTrack else { return }
        sourcePreparationTask?.cancel()
        sourcePreparationTask = nil
        removeCurrentItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        trackSource = nil
        startedCurrentItem = false
        lastError = nil
        let requestGeneration = beginPlaybackRequest()
        defer { finishPreparingPlaybackRequest(requestGeneration) }
        refreshNowPlayingInfo()

        let checkpoint = pendingRecoveryPosition
        do {
            let source = try await resolveTrackSource(track, recovering: checkpoint != nil)
            guard isCurrentPlaybackRequest(requestGeneration) else { return }
            sourcePreparationTask = nil
            trackSource = source
            if source.kind != .stream {
                try await validateAudio(source.url)
            }
            guard isCurrentPlaybackRequest(requestGeneration) else { return }
            guard source.kind != .stream || !settingsStore.settings.offlineOnly else { throw TrackPlaybackError.offline }
            logger.debug("Starting track from \(source.kind.rawValue, privacy: .public)")

            let asset = AVURLAsset(url: source.url)
            if let checkpoint, checkpoint > 0 {
                let fileDuration = try await asset.load(.duration).seconds
                guard isCurrentPlaybackRequest(requestGeneration) else { return }
                // An out-of-bounds seek can stall rather than completing with false.
                guard fileDuration.isFinite, checkpoint < fileDuration else {
                    logger.notice("Recovery file ends at \(fileDuration, privacy: .public)s before checkpoint \(checkpoint, privacy: .public)s")
                    playbackCacheManager.discardCachedFile(for: track, matching: source.url)
                    throw TrackPlaybackError.checkpointUnavailable
                }
            }
            let item = AVPlayerItem(asset: asset)
            player.automaticallyWaitsToMinimizeStalling = true
            observeCurrentItem(item)
            player.replaceCurrentItem(with: item)
            guard await activateAudioSession(for: requestGeneration) else { return }

            if let checkpoint, checkpoint > 0 {
                let target = CMTime(seconds: checkpoint, preferredTimescale: 600)
                let didSeek = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                guard isCurrentPlaybackRequest(requestGeneration) else { return }
                let actual = player.currentTime().seconds
                guard PlaybackTimeline.reachedCheckpoint(checkpoint, actual: actual, seekFinished: didSeek) else {
                    logger.notice("Recovery seek failed: target=\(checkpoint, privacy: .public) actual=\(actual, privacy: .public)")
                    playbackCacheManager.discardCachedFile(for: track, matching: source.url)
                    throw TrackPlaybackError.checkpointUnavailable
                }
                elapsed = actual
                logger.notice("Recovered from a local file at \(actual, privacy: .public)s")
            }

            pendingRecoveryPosition = nil
            shouldResumePlaybackAfterInterruption = false
            player.play()
            updatePlaybackStatus()
        } catch {
            guard isCurrentPlaybackRequest(requestGeneration) else { return }
            sourcePreparationTask = nil
            await handleCurrentItemFailure(error)
        }
    }

    private func configureObservers() {
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] currentTime in
            guard let self, let item = player.currentItem else { return }
            let nextElapsed = currentTime.seconds.isFinite ? currentTime.seconds : 0
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === player.currentItem,
                      preparingPlaybackRequest == nil, playbackRequested else { return }
                let itemDuration = item.duration.seconds
                let nextDuration: TimeInterval
                if itemDuration.isFinite, itemDuration > 0 {
                    nextDuration = itemDuration
                } else {
                    nextDuration = currentTrack?.duration ?? 0
                }
                elapsed = nextElapsed
                duration = nextDuration
                currentTrackListenSeconds = max(currentTrackListenSeconds, nextElapsed)
                updatePlaybackStatus()
            }
        }

        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, preparingPlaybackRequest == nil, playbackRequested else { return }
                updatePlaybackStatus()
            }
        }

        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                await self?.handleAudioSessionInterruption(typeRawValue: rawType, optionsRawValue: rawOptions)
            }
        }
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        removeCurrentItemObservers()

        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self, weak item] observedItem, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === self.player.currentItem else { return }
                guard observedItem.status == .failed else { return }
                await self.handleCurrentItemFailure(observedItem.error)
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === self.player.currentItem else { return }
                await self.handleTrackFinished()
            }
        }

        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === self.player.currentItem else { return }
                await self.handleCurrentItemFailure(error)
            }
        }

        itemTimeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === player.currentItem, preparingPlaybackRequest == nil,
                      trackSource?.kind == .stream else { return }
                let newTime = item.currentTime().seconds
                if newTime.isFinite, elapsed - newTime > 2 {
                    logger.notice("Stream time moved back from \(self.elapsed, privacy: .public)s to \(newTime, privacy: .public)s on the same item")
                }
            }
        }
    }

    private func removeCurrentItemObservers() {
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        if let itemFailureObserver {
            NotificationCenter.default.removeObserver(itemFailureObserver)
            self.itemFailureObserver = nil
        }
        if let itemTimeJumpObserver {
            NotificationCenter.default.removeObserver(itemTimeJumpObserver)
            self.itemTimeJumpObserver = nil
        }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
    }

    private func handleTrackFinished() async {
        guard playbackRequested, preparingPlaybackRequest == nil else { return }
        guard currentRadioStation == nil else {
            isPlaying = false
            isBuffering = false
            refreshNowPlayingInfo()
            return
        }
        let position = PlaybackTimeline.checkpoint(elapsed: elapsed, playerTime: player.currentTime().seconds)
        if let trackSource {
            logger.debug("End of \(trackSource.kind.rawValue, privacy: .public) item at \(position, privacy: .public)s (expected \(self.currentTrack?.duration ?? 0, privacy: .public)s)")
            if trackSource.kind != .saved, PlaybackTimeline.endedEarly(at: position, expectedDuration: currentTrack?.duration) {
                logger.notice("Premature end: source=\(trackSource.kind.rawValue, privacy: .public) position=\(position, privacy: .public)s expected=\(self.currentTrack?.duration ?? 0, privacy: .public)s")
                await handleCurrentItemFailure(TrackPlaybackError.incompleteTrack)
                return
            }
        }
        currentTrackListenSeconds = max(currentTrackListenSeconds, position)
        finalizePlaybackRecord()
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            await playCurrentTrack()
        } else {
            if !queue.isEmpty {
                playAlbumFinishedHaptic()
            }
            if isRepeatingAlbum, !queue.isEmpty {
                currentIndex = 0
                await playCurrentTrack()
            } else {
                playbackRequested = false
                isPlaying = false
                isBuffering = false
                refreshNowPlayingInfo()
            }
        }
    }

    private func handleCurrentItemFailure(_ error: Error?) async {
        guard playbackRequested, let track = currentTrack else { return }
        let position = PlaybackTimeline.checkpoint(elapsed: elapsed, playerTime: player.currentTime().seconds)
        let failure = error as NSError?
        logger.notice("Track failure: source=\(self.trackSource?.kind.rawValue ?? "preparing", privacy: .public) position=\(position, privacy: .public)s error=\(failure?.domain ?? "unknown", privacy: .public)/\(failure?.code ?? 0, privacy: .public)")

        if let source = trackSource, !attemptedRecovery, !settingsStore.settings.offlineOnly {
            attemptedRecovery = true
            pendingRecoveryPosition = position
            elapsed = position
            if source.kind == .cached {
                playbackCacheManager.discardCachedFile(for: track, matching: source.url)
            }
            playbackCacheManager.cancelPrefetch()
            await startTrackPlayback()
            return
        }

        // Keep the checkpoint for a manual retry too; a failed recovery must
        // not turn Play into an implicit restart of the song.
        if pendingRecoveryPosition == nil, position > 0 {
            pendingRecoveryPosition = position
            elapsed = position
        }
        let message: String
        if attemptedRecovery {
            message = "Unable to resume \(track.title) at its previous position."
                + (error.map { " \($0.localizedDescription)" } ?? "")
        } else if trackSource?.kind == .saved || trackSource?.kind == .cached {
            message = "The saved file for \(track.title) cannot be played. Go online and download it again."
        } else {
            message = error?.localizedDescription ?? "Unable to play \(track.title)."
        }
        failPlayback(message)
    }

    private func updatePlaybackStatus() {
        let status = player.timeControlStatus
        isPlaying = status == .playing
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if status == .playing {
            playAlbumStartHapticIfNeeded()
            if let track = currentTrack, !startedCurrentItem {
                startedCurrentItem = true
                startPlaybackCaching()
                if !reportedCurrentTrack {
                    reportedCurrentTrack = true
                    playbackReportingManager.reportNowPlaying(track: track)
                    playbackReportingManager.flushIfNeeded(force: false)
                }
            }
        }
        refreshNowPlayingInfo()
    }

    private func failPlayback(_ message: String) {
        cancelPlaybackRequest()
        lastError = message
        shouldPlayAlbumStartHaptic = false
        refreshNowPlayingInfo()
    }

    private func playAlbumStartHapticIfNeeded() {
        guard shouldPlayAlbumStartHaptic else { return }
        shouldPlayAlbumStartHaptic = false
        WKInterfaceDevice.current().play(.start)
    }

    private func playAlbumFinishedHaptic() {
        WKInterfaceDevice.current().play(.click)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func finalizePlaybackRecord() {
        guard let track = currentTrack else { return }
        if downloadManager.recordPlayback(for: track, listenedSeconds: currentTrackListenSeconds) {
            playbackReportingManager.enqueueScrobble(for: track)
        }
    }

    private func activateAudioSession(for generation: Int) async -> Bool {
        do {
            try await audioSessionManager.activatePlaybackSession()
            return isCurrentPlaybackRequest(generation)
        } catch {
            if isCurrentPlaybackRequest(generation) {
                failPlayback(friendlyAudioSessionMessage(for: error))
            }
            return false
        }
    }

    private func friendlyAudioSessionMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("session activation failed") {
            return "Connect Bluetooth audio and try again."
        }
        return message
    }

    private func resumePlayback() async {
        // An interrupted seek must be completed before any replacement item plays.
        if currentTrack != nil, player.currentItem == nil || pendingRecoveryPosition != nil || player.currentItem?.status == .failed {
            await startTrackPlayback()
            return
        }
        let requestGeneration = beginPlaybackRequest()
        defer { finishPreparingPlaybackRequest(requestGeneration) }
        guard await activateAudioSession(for: requestGeneration) else { return }

        lastError = nil
        shouldResumePlaybackAfterInterruption = false
        player.play()
        updatePlaybackStatus()
    }

    private func beginPlaybackRequest() -> Int {
        playbackRequested = true
        playbackRequestGeneration += 1
        preparingPlaybackRequest = playbackRequestGeneration
        isPlaying = false
        isBuffering = true
        return playbackRequestGeneration
    }

    private func finishPreparingPlaybackRequest(_ generation: Int) {
        if preparingPlaybackRequest == generation {
            preparingPlaybackRequest = nil
        }
    }

    private func cancelPlaybackRequest() {
        playbackRequested = false
        playbackRequestGeneration += 1
        preparingPlaybackRequest = nil
        sourcePreparationTask?.cancel()
        sourcePreparationTask = nil
        player.pause()
        isPlaying = false
        isBuffering = false
        shouldResumePlaybackAfterInterruption = false
    }

    private func pausePlayback() {
        cancelPlaybackRequest()
    }

    private func isCurrentPlaybackRequest(_ generation: Int) -> Bool {
        playbackRequested && playbackRequestGeneration == generation
    }

    private func handleAudioSessionInterruption(typeRawValue: UInt?, optionsRawValue: UInt) async {
        guard let rawType = typeRawValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            shouldResumePlaybackAfterInterruption = isPlaying || isBuffering || player.rate > 0
            isPlaying = false
            isBuffering = false
            refreshNowPlayingInfo()

        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRawValue)
            let shouldResume = shouldResumePlaybackAfterInterruption && options.contains(.shouldResume)
            shouldResumePlaybackAfterInterruption = false

            guard shouldResume, currentTrack != nil || currentRadioStation != nil else {
                refreshNowPlayingInfo()
                return
            }

            if playbackRequested, preparingPlaybackRequest == nil {
                await resumePlayback()
            }

        @unknown default:
            shouldResumePlaybackAfterInterruption = false
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
        guard let coverArtID = currentAlbum?.coverArtID ?? currentPlaylist?.coverArtID ?? currentRadioStation?.coverArtID else {
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
            playbackRequested = true
            Task { await resumePlayback() }
        }
        return .success
    }

    @objc
    private func handlePauseCommand(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil || currentRadioStation != nil else { return .commandFailed }
        pausePlayback()
        refreshNowPlayingInfo()
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
        Task { await togglePlayback() }
        return .success
    }
}
