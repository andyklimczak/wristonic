import SwiftUI
import UIKit

@MainActor
final class CoverArtStore {
    static let shared = CoverArtStore()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> Image? {
        if let cached = cache.object(forKey: url as NSURL) {
            return Image(uiImage: cached)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return Image(uiImage: image)
        } catch {
            return nil
        }
    }
}
