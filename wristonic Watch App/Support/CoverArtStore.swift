import SwiftUI
import UIKit

@MainActor
final class CoverArtStore {
    static let shared = CoverArtStore()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> Image? {
        guard let image = await uiImage(for: url) else {
            return nil
        }
        return Image(uiImage: image)
    }

    func uiImage(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}
