import SwiftUI
import UIKit
import ImageIO

// Moving pictures (GIF / animated WebP): GIF profile pictures and banners,
// GIFs and stickers in chats. Frames are decoded off the main thread, shrunk
// to the size they're shown at and cached.
enum AnimatedImages {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 64 * 1024 * 1024
        // Low on memory: let go of every unpacked picture so iOS doesn't
        // close the app.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            c.removeAllObjects()
        }
        return c
    }()

    // The most memory one moving picture may take once unpacked. Stickers
    // and GIFs used to unpack every frame at full size (a single sticker
    // could take 80 MB), which crashed chats and the editor's sticker picker.
    static let defaultBudget = 12 * 1024 * 1024
    // Small grid cells.
    static let thumbBudget = 3 * 1024 * 1024

    static func looksAnimated(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains(".gif") || lower.contains(".webp") || lower.contains("giphy.com") || lower.contains("tenor.com") || lower.contains("image%2fgif") || lower.contains("-anim")
    }

    static func cached(_ url: String, maxPixel: CGFloat, maxFrames: Int = 90) -> UIImage? {
        cache.object(forKey: "\(url)#\(Int(maxPixel))#\(maxFrames)" as NSString)
    }

    // maxFrames keeps grids of many GIFs light (thumbnails skip frames).
    static func load(_ url: String, maxPixel: CGFloat = 480, maxFrames: Int = 90, budget: Int = defaultBudget) async -> UIImage? {
        let key = "\(url)#\(Int(maxPixel))#\(maxFrames)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let link = URL(string: url) else { return nil }
        var request = URLRequest(url: link)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        // Scrolled away meanwhile: don't unpack it.
        guard !Task.isCancelled else { return nil }
        // Only a couple unpack at once, so a grid of GIFs can't spike memory.
        await DecodeGate.shared.enter()
        if let hit = cache.object(forKey: key) {
            await DecodeGate.shared.leave()
            return hit
        }
        guard !Task.isCancelled else {
            await DecodeGate.shared.leave()
            return nil
        }
        let image = await Task.detached(priority: .userInitiated) { decode(data, maxPixel: maxPixel, maxFrames: maxFrames, budget: budget) }.value
        await DecodeGate.shared.leave()
        if let image { cache.setObject(image, forKey: key, cost: cost(image)) }
        return image
    }

    // Memory the unpacked frames take (repeated frames share one picture).
    static func cost(_ image: UIImage) -> Int {
        let frames = Set((image.images ?? [image]).map { ObjectIdentifier($0) }).count
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4) * max(1, frames)
    }

    nonisolated static func decode(_ data: Data, maxPixel: CGFloat, maxFrames: Int = 90, budget: Int = defaultBudget) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        var pixel = maxPixel
        var wanted = min(count, max(1, maxFrames))
        // Fit the frames in the memory budget: shrink them a little first so
        // the motion stays smooth, then skip frames if it still doesn't fit.
        if count > 1, let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 {
            let longest = max(w, h)
            func bytes(_ side: Double) -> Double {
                let s = min(1, side / longest)
                return (w * s) * (h * s) * 4
            }
            let room = Double(max(budget, 256 * 1024))
            if Double(wanted) * bytes(Double(pixel)) > room {
                let smooth = Double(min(wanted, 24))
                let side = longest * (room / (smooth * w * h * 4)).squareRoot()
                pixel = CGFloat(max(64, min(Double(pixel), side)))
                wanted = max(1, min(wanted, Int(room / bytes(Double(pixel)))))
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixel,
        ]
        if count <= 1 || maxFrames <= 1 {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return UIImage(data: data) }
            return UIImage(cgImage: cg)
        }
        // Long animations keep every n-th frame so memory stays small.
        let step = max(1, Int((Double(count) / Double(max(1, wanted))).rounded(.up)))
        var frames: [UIImage] = []
        var delays: [Double] = []
        var i = 0
        while i < count {
            autoreleasepool {
                if let cg = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) {
                    frames.append(UIImage(cgImage: cg))
                    delays.append((i..<min(count, i + step)).reduce(0) { $0 + frameDelay(source, $1) })
                }
            }
            i += step
        }
        guard !frames.isEmpty else { return nil }
        // UIImageView shows every frame for the same time, so frames meant to
        // stay up longer are repeated (the same image, so no extra memory).
        let unit = max(0.02, delays.min() ?? 0.1)
        var timed: [UIImage] = []
        for (frame, d) in zip(frames, delays) { timed += Array(repeating: frame, count: max(1, Int((d / unit).rounded()))) }
        if timed.count > frames.count * 12 { return UIImage.animatedImage(with: frames, duration: max(0.1, delays.reduce(0, +))) }
        return UIImage.animatedImage(with: timed, duration: max(0.1, Double(timed.count) * unit))
    }

    // The original file, for big GIFs played at full quality.
    nonisolated(unsafe) private static let files: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 40 * 1024 * 1024
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            c.removeAllObjects()
        }
        return c
    }()

    static func file(_ url: String) -> Data? { files.object(forKey: url as NSString) as Data? }

    static func loadFile(_ url: String) async -> Data? {
        if let hit = file(url) { return hit }
        guard let link = URL(string: url) else { return nil }
        var request = URLRequest(url: link)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request), !data.isEmpty else { return nil }
        files.setObject(data as NSData, forKey: url as NSString, cost: data.count)
        return data
    }

    nonisolated static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        var value: Double?
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            value = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        } else if let webp = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            value = (webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double) ?? (webp[kCGImagePropertyWebPDelayTime] as? Double)
        }
        guard let v = value, v > 0.011 else { return 0.1 }
        return v
    }
}

// Lets only two moving pictures unpack at the same time.
actor DecodeGate {
    static let shared = DecodeGate()
    private var free = 2
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if free > 0 {
            free -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            free += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

// Shows a UIImage — moving if it has frames.
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    var fill = true

    final class Box: UIView {
        let imageView = UIImageView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            imageView.clipsToBounds = true
            addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { imageView.startAnimating() }
            else { imageView.stopAnimating() }
        }
    }

    func makeUIView(context: Context) -> Box {
        let box = Box()
        box.imageView.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        box.imageView.image = image
        if box.window != nil { box.imageView.startAnimating() }
        return box
    }

    func updateUIView(_ box: Box, context: Context) {
        box.imageView.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        if box.imageView.image !== image {
            box.imageView.image = image
            if box.window != nil { box.imageView.startAnimating() }
        }
    }
}

// Cancellation is checked on ImageIO's callback thread before dispatching a
// frame to UIKit. A dismissed player must stop decoding, not just hide frames.
final class GIFPlaybackRun: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}

// Plays a GIF at full quality with its own timing, decoding each frame as it
// goes (profile pictures and banners), so nothing is shrunk or skipped.
struct LiveGIF: UIViewRepresentable {
    let data: Data
    var fill = true

    final class Player: UIView {
        var data: Data? { didSet { if data != oldValue { restart() } } }
        private var run: GIFPlaybackRun?

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            restart()
        }

        func stop() { run?.cancel(); run = nil }

        private func restart() {
            stop()
            guard window != nil, let data else { return }
            let mine = GIFPlaybackRun()
            run = mine
            if layer.contents == nil, let first = UIImage(data: data)?.cgImage { layer.contents = first }
            CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, image, stop in
                guard !mine.isCancelled, self != nil else {
                    mine.cancel()
                    stop.pointee = true
                    return
                }
                guard Thread.isMainThread else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !mine.isCancelled else { return }
                        self.layer.contents = image
                    }
                    return
                }
                MainActor.assumeIsolated {
                    guard let self, !mine.isCancelled else { stop.pointee = true; return }
                    self.layer.contents = image
                }
            }
        }
    }

    func makeUIView(context: Context) -> Player {
        let player = Player()
        player.layer.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        player.data = data
        return player
    }

    func updateUIView(_ player: Player, context: Context) {
        player.layer.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        player.data = data
    }

    static func dismantleUIView(_ player: Player, coordinator: ()) { player.stop() }
}

// A GIF from a link at full quality (falls back to the usual picture).
struct FullGIF: View {
    let url: String
    var fill = true
    @State private var data: Data?
    @State private var loadedURL = ""

    var body: some View {
        let shown = loadedURL == url ? data : nil
        Color.clear
            .overlay {
                if let file = shown ?? AnimatedImages.file(url) {
                    LiveGIF(data: file, fill: fill).transition(.opacity)
                } else {
                    Rectangle().fill(Palette.surface2)
                }
            }
            .clipped()
            .task(id: url) {
                if loadedURL != url { data = nil; loadedURL = url }
                guard !url.isEmpty, data == nil else { return }
                let target = url
                if let file = await AnimatedImages.loadFile(target), target == url {
                    withAnimation(.easeOut(duration: 0.2)) { data = file }
                }
            }
    }
}

// Picks the right view for a loaded picture.
struct LoadedImage: View {
    let image: UIImage
    var fill = true
    var body: some View {
        if image.images != nil {
            AnimatedImageView(image: image, fill: fill)
        } else if fill {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(uiImage: image).resizable().scaledToFit()
        }
    }
}
