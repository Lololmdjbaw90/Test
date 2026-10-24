import SwiftUI
import UIKit
import CoreText

// Round candy lettering like the Sugerly wordmark. Render each word once:
// the outline and dots do not add live masks or shadows while scrolling.
struct StickerTitle: View {
    let text: String
    @ScaledMetric private var size: CGFloat

    init(text: String, size: CGFloat = 34) {
        self.text = text
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        let artwork = StickerTitleArt.image(text, accent: Theme.mainHex)
        let scale = min(size, 64) / StickerTitleArt.fontSize
        Image(uiImage: artwork)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: artwork.size.width * scale,
                   maxHeight: artwork.size.height * scale, alignment: .leading)
            .accessibilityLabel(text)
            .accessibilityRemoveTraits(.isImage)
            .accessibilityAddTraits([.isStaticText, .isHeader])
    }
}

@MainActor
private enum StickerTitleArt {
    static let fontSize: CGFloat = 64
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    static func image(_ title: String, accent: UInt32) -> UIImage {
        let key = "v2-\(title)-\(accent)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let font = UIFont(name: "LilitaOne", size: fontSize)
            ?? UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let text = NSAttributedString(string: title, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(text)
        let letters = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<count {
                if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                    letters.addPath(glyph, transform: .init(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        guard !letters.isEmpty else { return UIImage() }
        // The outline is a real shape (the letters grown by a round edge),
        // filled rather than stroked, so no stray stroke bits poke out
        // where the letters' own outlines overlap. Generous room all round
        // so nothing is ever cut off.
        let edge: CGFloat = 5.5
        let padding: CGFloat = edge + 6
        let depth: CGFloat = 4
        let bounds = letters.boundingBoxOfPath
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                         tx: padding - bounds.minX, ty: padding + bounds.maxY)
        let path = letters.copy(using: &transform)!
        let outline = path.copy(strokingWithWidth: edge * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let canvas = CGSize(width: ceil(bounds.width + padding * 2),
                            height: ceil(bounds.height + padding * 2 + depth))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let base = UIColor(hex: accent)
        func mixed(_ target: CGFloat, _ amount: CGFloat) -> UIColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r + (target - r) * amount,
                           green: g + (target - g) * amount,
                           blue: b + (target - b) * amount, alpha: 1)
        }
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let context = renderer.cgContext
            func fill(_ shape: CGPath, _ color: UIColor, dy: CGFloat = 0) {
                context.saveGState()
                context.translateBy(x: 0, y: dy)
                context.addPath(shape)
                context.addPath(path)
                context.setFillColor(color.cgColor)
                context.fillPath(using: .winding)
                context.restoreGState()
            }
            // A small solid edge underneath, then the dark outline.
            fill(outline, mixed(0, 0.65), dy: depth)
            fill(outline, mixed(0, 0.5))
            // The letters: mostly white, a soft blush of your colour at the
            // bottom, and faint dots.
            context.saveGState()
            context.addPath(path)
            context.clip(using: .winding)
            let colors = [UIColor.white.cgColor, mixed(1, 0.93).cgColor, mixed(1, 0.7).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.55, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: padding),
                                           end: CGPoint(x: 0, y: canvas.height - padding - depth), options: [])
            }
            context.setFillColor(base.withAlphaComponent(0.1).cgColor)
            let spacing: CGFloat = 10
            for y in stride(from: padding, through: canvas.height, by: spacing) {
                for x in stride(from: padding, through: canvas.width, by: spacing) {
                    let dot = CGRect(x: x, y: y, width: 3.6, height: 3.6)
                    context.addPath(CGPath(roundedRect: dot, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                    context.fillPath()
                }
            }
            context.restoreGState()
        }
        cache.setObject(image, forKey: key,
                        cost: Int(canvas.width * canvas.height * format.scale * format.scale * 4))
        return image
    }
}
