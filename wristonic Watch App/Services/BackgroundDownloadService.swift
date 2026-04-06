import Foundation
import WatchKit

final class BackgroundDownloadService: NSObject, URLSessionDownloadDelegate {
    static let shared = BackgroundDownloadService()

    private let sessionIdentifier = "com.andy.wristonic.background-downloads"
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var stagedFiles: [Int: URL] = [:]
    private var progressHandlers: [Int: @Sendable (Int64, Int64, Double) -> Void] = [:]
    private var taskStartDates: [Int: Date] = [:]
    private var refreshTasks: [WKURLSessionRefreshBackgroundTask] = []

    func download(
        for request: URLRequest,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)? = nil
    ) async throws -> URL {
        let task = session.downloadTask(with: request)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations[task.taskIdentifier] = continuation
            progressHandlers[task.taskIdentifier] = onProgress
            taskStartDates[task.taskIdentifier] = Date()
            lock.unlock()
            task.resume()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for backgroundTask in backgroundTasks {
            guard let refreshTask = backgroundTask as? WKURLSessionRefreshBackgroundTask else {
                backgroundTask.setTaskCompletedWithSnapshot(false)
                continue
            }

            if refreshTask.sessionIdentifier == sessionIdentifier {
                lock.lock()
                refreshTasks.append(refreshTask)
                lock.unlock()
                _ = session
            } else {
                refreshTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".download")
        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            lock.lock()
            stagedFiles[downloadTask.taskIdentifier] = temporaryURL
            lock.unlock()
        } catch {
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(error))
            return
        }

        lock.lock()
        let fileURL = stagedFiles.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        guard let fileURL else {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(URLError(.cannotOpenFile)))
            return
        }
        complete(taskIdentifier: task.taskIdentifier, result: .success(fileURL))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let handler = progressHandlers[downloadTask.taskIdentifier]
        let startDate = taskStartDates[downloadTask.taskIdentifier]
        lock.unlock()

        guard let handler, let startDate else {
            return
        }

        let elapsed = max(Date().timeIntervalSince(startDate), 0.25)
        let bytesPerSecond = Double(totalBytesWritten) / elapsed
        handler(totalBytesWritten, totalBytesExpectedToWrite, bytesPerSecond)
    }

    private func complete(taskIdentifier: Int, result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: taskIdentifier)
        progressHandlers.removeValue(forKey: taskIdentifier)
        taskStartDates.removeValue(forKey: taskIdentifier)
        if case .failure = result, let stagedFile = stagedFiles.removeValue(forKey: taskIdentifier) {
            try? FileManager.default.removeItem(at: stagedFile)
        }
        lock.unlock()

        switch result {
        case .success(let url):
            continuation?.resume(returning: url)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }

        completeRefreshTasksIfIdle()
    }

    private func completeRefreshTasksIfIdle() {
        session.getAllTasks { [weak self] tasks in
            guard let self, tasks.isEmpty else { return }
            lock.lock()
            let tasksToComplete = refreshTasks
            refreshTasks.removeAll()
            lock.unlock()

            for refreshTask in tasksToComplete {
                refreshTask.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
