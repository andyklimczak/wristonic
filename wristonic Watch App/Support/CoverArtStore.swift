import SwiftUI
import UIKit
import CryptoKit
import ImageIO

@MainActor
final class CoverArtStore {
    private struct ProcessedCoverArt {
        let image: UIImage
        let diskData: Data
    }

    static let shared = CoverArtStore()

    private let cache = NSCache<NSURL, UIImage>()
    private let maximumPixelSize: CGFloat = 128
    private var inFlightTasks: [NSURL: Task<ProcessedCoverArt?, Never>] = [:]
    private let maxConcurrentLoads = 2
    private var activeLoads = 0
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []
    private let fileManager: FileManager
    private var cacheDirectory: URL?
    private var diskCacheLimitBytes: Int64 = 75_000_000

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        cache.countLimit = 24
        cache.totalCostLimit = 3_000_000
    }

    func configure(cacheDirectory: URL, diskCacheLimitBytes: Int64 = 20_000_000) {
        self.cacheDirectory = cacheDirectory
        self.diskCacheLimitBytes = diskCacheLimitBytes
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL, loader: @escaping (URL) async throws -> Data) async -> Image? {
        guard let image = await uiImage(for: url, loader: loader) else {
            return nil
        }
        return Image(uiImage: image)
    }

    func cachedImage(for url: URL) -> Image? {
        guard let image = cachedUIImage(for: url) else {
            return nil
        }
        return Image(uiImage: image)
    }

    func clear() async {
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        cache.removeAllObjects()
        waitingContinuations.forEach { $0.resume() }
        waitingContinuations.removeAll()
        activeLoads = 0

        guard let cacheDirectory else {
            return
        }

        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
        }
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func uiImage(for url: URL, loader: @escaping (URL) async throws -> Data) async -> UIImage? {
        let key = url as NSURL
        if let cached = cachedUIImage(for: url) {
            return cached
        }
        if let task = inFlightTasks[key] {
            return await task.value?.image
        }

        let task = Task<ProcessedCoverArt?, Never> {
            await self.acquirePermit()
            defer {
                self.releasePermit()
            }
            if Task.isCancelled {
                return nil
            }
            do {
                let data = try await loader(url)
                if Task.isCancelled {
                    return nil
                }
                return await self.processedCoverArt(from: data)
            } catch {
                return nil
            }
        }
        inFlightTasks[key] = task
        let artwork = await task.value
        inFlightTasks[key] = nil

        if let artwork {
            let image = artwork.image
            cache.setObject(image, forKey: key, cost: imageCost(image))
            if !url.isFileURL {
                await persistDiskCachedImageData(artwork.diskData, for: url)
            }
            return image
        }
        return nil
    }

    func cachedUIImage(for url: URL) -> UIImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let cached = loadDiskCachedImage(for: url) {
            cache.setObject(cached, forKey: key, cost: imageCost(cached))
            return cached
        }
        return nil
    }

    private func loadDiskCachedImage(for url: URL) -> UIImage? {
        guard !url.isFileURL, let cachedFileURL = cachedFileURL(for: url) else {
            return nil
        }
        guard let data = try? Data(contentsOf: cachedFileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: cachedFileURL.path)
        return image
    }

    private func persistDiskCachedImageData(_ data: Data, for url: URL) async {
        guard let cachedFileURL = cachedFileURL(for: url) else {
            return
        }
        let cacheDirectory = cachedFileURL.deletingLastPathComponent()
        let diskCacheLimitBytes = self.diskCacheLimitBytes

        await Task.detached(priority: .utility) {
            Self.writeDiskCachedImage(
                data,
                to: cachedFileURL,
                cacheDirectory: cacheDirectory,
                diskCacheLimitBytes: diskCacheLimitBytes
            )
        }.value
    }

    private func cachedFileURL(for url: URL) -> URL? {
        guard let cacheDirectory else {
            return nil
        }
        let digest = SHA256.hash(data: Data(cacheKey(for: url).utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
        return cacheDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func cacheKey(for url: URL) -> String {
        guard !url.isFileURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?
            .filter { $0.name != "t" && $0.name != "s" }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return (lhs.value ?? "") < (rhs.value ?? "")
                }
                return lhs.name < rhs.name
            }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private func processedCoverArt(from data: Data) async -> ProcessedCoverArt? {
        let maximumPixelSize = Int(maximumPixelSize)
        guard let thumbnailData = await Task.detached(priority: .userInitiated, operation: {
            Self.downsampledJPEG(from: data, maximumPixelSize: maximumPixelSize)
        }).value,
            let image = UIImage(data: thumbnailData) else {
            return nil
        }

        return ProcessedCoverArt(image: image, diskData: thumbnailData)
    }

    private nonisolated static func downsampledJPEG(from data: Data, maximumPixelSize: Int) -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        guard let imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        CGImageDestinationAddImage(destination, imageRef, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }

    private nonisolated static func writeDiskCachedImage(
        _ data: Data,
        to cachedFileURL: URL,
        cacheDirectory: URL,
        diskCacheLimitBytes: Int64
    ) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cachedFileURL, options: .atomic)
        enforceDiskCacheLimit(
            in: cacheDirectory,
            diskCacheLimitBytes: diskCacheLimitBytes,
            fileManager: fileManager
        )
    }

    private nonisolated static func enforceDiskCacheLimit(
        in cacheDirectory: URL,
        diskCacheLimitBytes: Int64,
        fileManager: FileManager
    ) {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: Array(resourceKeys)) else {
            return
        }

        var entries: [(url: URL, size: Int64, modifiedAt: Date)] = []
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            entries.append((url: fileURL, size: size, modifiedAt: modifiedAt))
            totalBytes += size
        }

        guard totalBytes > diskCacheLimitBytes else {
            return
        }

        for entry in entries.sorted(by: { $0.modifiedAt < $1.modifiedAt }) where totalBytes > diskCacheLimitBytes {
            try? fileManager.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }

    private func acquirePermit() async {
        if activeLoads < maxConcurrentLoads {
            activeLoads += 1
            return
        }

        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    private func releasePermit() {
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            continuation.resume()
            return
        }

        activeLoads = max(activeLoads - 1, 0)
    }
}
