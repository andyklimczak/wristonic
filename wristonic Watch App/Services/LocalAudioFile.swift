import AVFoundation
import Foundation

enum LocalAudioFile {
    typealias Validator = @MainActor (URL) async throws -> Void

    // Keep the real extension for AVFoundation, but do not expose a shared
    // destination to a different download while validation is suspended.
    static func stageDownload(from source: URL, for destination: URL, fileManager: FileManager) throws -> URL {
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)")
            .appendingPathExtension(destination.pathExtension)
        try fileManager.moveItem(at: source, to: staged)
        return staged
    }

    static func publish(_ staged: URL, at destination: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    static func validate(_ url: URL) async throws {
        try Task.checkCancellation()
        do {
            // Validate the saved container, not just HTTP status or Content-Type.
            // Subsonic errors and proxy login pages can arrive with HTTP 200.
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else {
                throw SubsonicClientError.unsupportedMediaType
            }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration).seconds
            guard !tracks.isEmpty, duration.isFinite, duration > 0 else {
                throw SubsonicClientError.unsupportedMediaType
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw SubsonicClientError.unsupportedMediaType
        }
    }
}
