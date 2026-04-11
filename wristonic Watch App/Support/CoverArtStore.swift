import SwiftUI
import UIKit
import CryptoKit
import ImageIO

@MainActor
final class CoverArtStore {
    static let shared = CoverArtStore()

    private let cache = NSCache<NSURL, UIImage>()
    private let maximumPixelSize: CGFloat = 128
    private var inFlightTasks: [NSURL: Task<UIImage?, Never>] = [:]
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
            return await task.value
        }

        let task = Task<UIImage?, Never> {
            await self.acquirePermit()
            defer {
                Task { @MainActor in
                    self.releasePermit()
                }
            }
            if Task.isCancelled {
                return nil
            }
            do {
                let data = try await loader(url)
                if Task.isCancelled {
                    return nil
                }
                guard let image = self.processedImage(from: data) else { return nil }
                return image
            } catch {
                return nil
            }
        }
        inFlightTasks[key] = task
        let image = await task.value
        inFlightTasks[key] = nil

        if let image {
            cache.setObject(image, forKey: key, cost: imageCost(image))
            if !url.isFileURL {
                persistDiskCachedImage(image, for: url)
            }
        }
        return image
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
              let image = processedImage(from: data) else {
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: cachedFileURL.path)
        return image
    }

    private func persistDiskCachedImage(_ image: UIImage, for url: URL) {
        guard let cachedFileURL = cachedFileURL(for: url),
              let data = image.jpegData(compressionQuality: 0.82) else {
            return
        }
        try? fileManager.createDirectory(at: cachedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cachedFileURL, options: .atomic)
        enforceDiskCacheLimit()
    }

    private func cachedFileURL(for url: URL) -> URL? {
        guard let cacheDirectory else {
            return nil
        }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
        return cacheDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func processedImage(from data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        if let imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) {
            return UIImage(cgImage: imageRef)
        }
        return UIImage(data: data)
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func enforceDiskCacheLimit() {
        guard let cacheDirectory else {
            return
        }

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
