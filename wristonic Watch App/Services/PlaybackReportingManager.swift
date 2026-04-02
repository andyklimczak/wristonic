import Foundation

@MainActor
final class PlaybackReportingManager {
    private let queueStore: JSONFileStore<[PendingPlaybackScrobble]>
    private let settingsStore: SettingsStore
    private let clientProvider: () throws -> SubsonicClient
    private let maxRetryAttempts: Int
    private let baseRetryDelay: TimeInterval
    private let maxRetryDelay: TimeInterval

    private var queue: [PendingPlaybackScrobble] = []
    private var processingTask: Task<Void, Never>?

    init(
        queueStore: JSONFileStore<[PendingPlaybackScrobble]>,
        settingsStore: SettingsStore,
        maxRetryAttempts: Int = 20,
        baseRetryDelay: TimeInterval = 30,
        maxRetryDelay: TimeInterval = 6 * 60 * 60,
        clientProvider: @escaping () throws -> SubsonicClient
    ) {
        self.queueStore = queueStore
        self.settingsStore = settingsStore
        self.maxRetryAttempts = maxRetryAttempts
        self.baseRetryDelay = baseRetryDelay
        self.maxRetryDelay = maxRetryDelay
        self.clientProvider = clientProvider
    }

    func load() async {
        queue = (try? await queueStore.load(default: [])) ?? []
    }

    func notifyAppDidBecomeActive() {
        flushIfNeeded(force: false)
    }

    func reportNowPlaying(track: Track) {
        guard settingsStore.canConnect else {
            return
        }

        Task {
            do {
                try await clientProvider().reportNowPlaying(trackID: track.id)
            } catch {
            }
        }
    }

    func enqueueScrobble(for track: Track, listenedAt: Date = Date()) {
        queue.append(
            PendingPlaybackScrobble(
                id: UUID().uuidString,
                trackID: track.id,
                listenedAt: listenedAt,
                createdAt: Date(),
                attempts: 0,
                nextRetryAt: listenedAt
            )
        )
        persist()
        flushIfNeeded(force: true)
    }

    func flushIfNeeded(force: Bool = false) {
        guard processingTask == nil else {
            return
        }
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue(force: force)
        }
    }

    private func processQueue(force: Bool) async {
        defer { processingTask = nil }

        while !queue.isEmpty {
            guard settingsStore.canConnect else {
                return
            }

            guard let client = try? clientProvider() else {
                return
            }

            let now = Date()
            guard let index = nextEligibleIndex(force: force, now: now) else {
                return
            }

            do {
                try await client.scrobble(trackID: queue[index].trackID, listenedAt: queue[index].listenedAt, submission: true)
                queue.remove(at: index)
                persist()
            } catch {
                queue[index].attempts += 1
                if queue[index].attempts >= maxRetryAttempts {
                    queue.remove(at: index)
                } else {
                    queue[index].nextRetryAt = now.addingTimeInterval(retryDelay(afterAttempt: queue[index].attempts))
                }
                persist()
                return
            }
        }
    }

    private func nextEligibleIndex(force: Bool, now: Date) -> Int? {
        queue.enumerated()
            .filter { force || $0.element.nextRetryAt <= now }
            .min { lhs, rhs in
                if lhs.element.nextRetryAt != rhs.element.nextRetryAt {
                    return lhs.element.nextRetryAt < rhs.element.nextRetryAt
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }?
            .offset
    }

    private func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
        let exponentialFactor = pow(2, Double(max(attempt - 1, 0)))
        return min(baseRetryDelay * exponentialFactor, maxRetryDelay)
    }

    private func persist() {
        let currentQueue = queue
        Task {
            try? await queueStore.save(currentQueue)
        }
    }
}
