import UIKit

/// Covers kept in memory, decoded and ready to draw. A cover that was shown
/// before, or fetched ahead for the next songs, appears at once.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private var loading: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        images.countLimit = 300
    }

    func cached(_ url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    /// The cover at `url`; a second request for it waits for the first.
    func image(for url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = loading[url] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Loads covers that will be needed soon, such as those of the next songs.
    func prefetch(_ urls: [URL]) {
        for url in urls where cached(url) == nil && loading[url] == nil {
            Task { _ = await image(for: url) }
        }
    }
}
