import UIKit

/// Covers kept in memory, decoded and ready to draw. A cover that was shown
/// before, or fetched ahead for the next songs, appears at once.
///
/// Covers come from the Sonos player, which serves few at a time. So at most
/// four load at once, and the newest request goes first: covers that just
/// scrolled into view come before those that scrolled past.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private var loading: [URL: Task<UIImage?, Never>] = [:]
    private let maxLoads = 4
    private var loads = 0
    /// Requests waiting for a free load, newest last.
    private var waiting: [CheckedContinuation<Void, Never>] = []

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
        let task = Task { await load(url) }
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

    private func load(_ url: URL) async -> UIImage? {
        await startLoad()
        defer { endLoad() }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }.value
    }

    private func startLoad() async {
        if loads < maxLoads {
            loads += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    /// Hands the load to the newest waiting request, or frees it.
    private func endLoad() {
        if let next = waiting.popLast() {
            next.resume()
        } else {
            loads -= 1
        }
    }
}
