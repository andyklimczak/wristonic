import XCTest
@testable import wristonic_Watch_App

@MainActor
final class CoverArtStoreTests: XCTestCase {
    func testDiskCacheServesImageWithoutRefetching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let firstStore = CoverArtStore()
        firstStore.configure(cacheDirectory: root, diskCacheLimitBytes: 1_000_000)

        let url = URL(string: "https://example.com/cover-1.png")!
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0xQAAAAASUVORK5CYII=")!
        var fetchCount = 0

        let firstImage = await firstStore.uiImage(for: url) { _ in
            fetchCount += 1
            return pngData
        }

        XCTAssertNotNil(firstImage)
        XCTAssertEqual(fetchCount, 1)

        let secondStore = CoverArtStore()
        secondStore.configure(cacheDirectory: root, diskCacheLimitBytes: 1_000_000)

        let secondImage = await secondStore.uiImage(for: url) { _ in
            fetchCount += 1
            return pngData
        }

        XCTAssertNotNil(secondImage)
        XCTAssertEqual(fetchCount, 1)
    }

    func testCachedUIImageLoadsSynchronouslyFromDiskCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let firstStore = CoverArtStore()
        firstStore.configure(cacheDirectory: root, diskCacheLimitBytes: 1_000_000)

        let url = URL(string: "https://example.com/cover-2.png")!
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0xQAAAAASUVORK5CYII=")!

        let image = await firstStore.uiImage(for: url) { _ in
            pngData
        }

        XCTAssertNotNil(image)

        let secondStore = CoverArtStore()
        secondStore.configure(cacheDirectory: root, diskCacheLimitBytes: 1_000_000)

        XCTAssertNotNil(secondStore.cachedUIImage(for: url))
    }
}
