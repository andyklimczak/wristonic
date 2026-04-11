import XCTest
@testable import wristonic_Watch_App

@MainActor
final class CoverArtStoreTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipOnGitHubActions("Skipped on GitHub Actions because watchOS image decoding is unstable in CI.")
    }

    func testDiskCacheServesImageWithoutRefetching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let firstStore = CoverArtStore()
        firstStore.configure(cacheDirectory: root, diskCacheLimitBytes: 1_000_000)

        let url = URL(string: "https://example.com/cover-1.png")!
        let pngData = makePNGData()
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
        let pngData = makePNGData()

        let image = await firstStore.uiImage(for: url) { _ in
            pngData
        }

        XCTAssertNotNil(image)

        let secondStore = CoverArtStore()
        secondStore.configure(cacheDirectory: root, diskCacheLimitBytes: 1_000_000)

        XCTAssertNotNil(secondStore.cachedUIImage(for: url))
    }

    private func makePNGData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==")!
    }
}
