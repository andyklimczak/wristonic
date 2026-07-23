import Foundation
import WatchKit

struct DownloadedFile {
    var url: URL
    var response: URLResponse
}

protocol DownloadServing {
    func download(
        for request: URLRequest,
        allowedInsecureHost: String?,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)?
    ) async throws -> DownloadedFile
}

extension DownloadServing {
    func download(
        for request: URLRequest,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)?
    ) async throws -> DownloadedFile {
        try await download(for: request, allowedInsecureHost: nil, onProgress: onProgress)
    }
}

final class BackgroundDownloadService: NSObject, URLSessionDownloadDelegate, DownloadServing {
    static let shared = BackgroundDownloadService()
    static let sessionIdentifier = "\(Bundle.main.bundleIdentifier ?? "com.andyklimczak.wristonic.watchkitapp").background-downloads"
    private static let insecureHostTaskDescriptionPrefix = "allow-insecure-host:"

    private let sessionIdentifier = BackgroundDownloadService.sessionIdentifier
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<DownloadedFile, Error>] = [:]
    private var stagedFiles: [Int: DownloadedFile] = [:]
    private var progressHandlers: [Int: @Sendable (Int64, Int64, Double) -> Void] = [:]
    private var progressSamples: [Int: (bytes: Int64, date: Date)] = [:]
    private var refreshTasks: [WKURLSessionRefreshBackgroundTask] = []

    func download(
        for request: URLRequest,
        allowedInsecureHost: String? = nil,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)? = nil
    ) async throws -> DownloadedFile {
        let task = session.downloadTask(with: request)
        if let allowedInsecureHost {
            task.taskDescription = Self.taskDescription(forAllowedInsecureHost: allowedInsecureHost)
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations[task.taskIdentifier] = continuation
            progressHandlers[task.taskIdentifier] = onProgress
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard
            let trust = challenge.protectionSpace.serverTrust,
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let allowedHost = Self.allowedInsecureHost(fromTaskDescription: task.taskDescription),
            challenge.protectionSpace.host.localizedCaseInsensitiveCompare(allowedHost) == .orderedSame
        else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
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
        guard let response = downloadTask.response else {
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .failure(URLError(.badServerResponse)))
            return
        }
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            complete(taskIdentifier: downloadTask.taskIdentifier, result: .failure(URLError(.badServerResponse)))
            return
        }

        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".download")
        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            lock.lock()
            stagedFiles[downloadTask.taskIdentifier] = DownloadedFile(url: temporaryURL, response: response)
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
        let now = Date()
        lock.lock()
        let handler = progressHandlers[downloadTask.taskIdentifier]
        let lastSample = progressSamples[downloadTask.taskIdentifier]
        progressSamples[downloadTask.taskIdentifier] = (totalBytesWritten, now)
        lock.unlock()

        guard let handler else {
            return
        }

        let bytesPerSecond: Double
        if let lastSample, totalBytesWritten >= lastSample.bytes {
            let elapsed = max(now.timeIntervalSince(lastSample.date), 0.25)
            bytesPerSecond = Double(totalBytesWritten - lastSample.bytes) / elapsed
        } else {
            bytesPerSecond = 0
        }
        handler(totalBytesWritten, totalBytesExpectedToWrite, bytesPerSecond)
    }

    private func complete(taskIdentifier: Int, result: Result<DownloadedFile, Error>) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: taskIdentifier)
        progressHandlers.removeValue(forKey: taskIdentifier)
        progressSamples.removeValue(forKey: taskIdentifier)
        if case .failure = result, let stagedFile = stagedFiles.removeValue(forKey: taskIdentifier) {
            try? FileManager.default.removeItem(at: stagedFile.url)
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

    private static func taskDescription(forAllowedInsecureHost host: String) -> String {
        insecureHostTaskDescriptionPrefix + host
    }

    private static func allowedInsecureHost(fromTaskDescription taskDescription: String?) -> String? {
        guard let taskDescription,
              taskDescription.hasPrefix(insecureHostTaskDescriptionPrefix) else {
            return nil
        }
        return String(taskDescription.dropFirst(insecureHostTaskDescriptionPrefix.count))
    }
}
