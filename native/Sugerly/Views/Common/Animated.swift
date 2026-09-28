import SwiftUI
import UIKit
import ImageIO

// Moving pictures (GIF / animated WebP): GIF profile pictures and banners,
// GIFs and stickers in chats. Frames are decoded off the main thread, shrunk
// to the size they're shown at and cached.
enum AnimatedImages {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 120 * 1024 * 1024
        return c
    }()

    static func looksAnimated(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains(".gif") || lower.contains(".webp") || lower.contains("giphy.com") || lower.contains("tenor.com") || lower.contains("image%2fgif") || lower.contains("-anim")
    }

    static func cached(_ url: String, maxPixel: CGFloat, maxFrames: Int = 90) -> UIImage? {
        cache.object(forKey: "\(url)#\(Int(maxPixel))#\(maxFrames)" as NSString)
    }

    // maxFrames keeps grids of many GIFs light (thumbnails skip frames).
    static func load(_ url: String, maxPixel: CGFloat = 480, maxFrames: Int = 90) async -> UIImage? {
        let key = "\(url)#\(Int(maxPixel))#\(maxFrames)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let link = URL(string: url) else { return nil }
        var request = URLRequest(url: link)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let image = await Task.detached(priority: .userInitiated) { decode(data, maxPixel: maxPixel, maxFrames: maxFrames) }.value
        if let image {
            let frames = CGFloat(image.images?.count ?? 1)
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4 * frames))
        }
        return image
    }

    nonisolated static func decode(_ data: Data, maxPixel: CGFloat, maxFrames: Int = 90) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        if count <= 1 {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return UIImage(data: data) }
            return UIImage(cgImage: cg)
        }
        // Long animations keep every n-th frame so memory stays small.
        let step = max(1, Int((Double(count) / Double(max(1, maxFrames))).rounded(.up)))
        var frames: [UIImage] = []
        var total: Double = 0
        var i = 0
        while i < count {
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) {
                frames.append(UIImage(cgImage: cg))
                total += delay(source, i) * Double(step)
            }
            i += step
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(0.1, total))
    }

    nonisolated private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
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
    }

    func makeUIView(context: Context) -> Box {
        let box = Box()
        box.imageView.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        box.imageView.image = image
        box.imageView.startAnimating()
        return box
    }

    func updateUIView(_ box: Box, context: Context) {
        box.imageView.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        if box.imageView.image !== image {
            box.imageView.image = image
            box.imageView.startAnimating()
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
