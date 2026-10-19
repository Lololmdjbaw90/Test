import SwiftUI
import UIKit
import CoreText

// Round candy lettering like the Sugerly wordmark. Render each word once:
// the outline and dots do not add live masks or shadows while scrolling.
struct StickerTitle: View {
    let text: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat

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
        let key = "\(title)-\(accent)" as NSString
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
        let bounds = letters.boundingBoxOfPath
        let padding: CGFloat = 9
        let depth: CGFloat = 4
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                         tx: padding - bounds.minX, ty: padding + bounds.maxY)
        let path = letters.copy(using: &transform)!
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
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setLineWidth(11)
            // A small solid extrusion, rather than a blurred glow.
            context.saveGState()
            context.translateBy(x: 0, y: depth)
            context.addPath(path)
            context.setFillColor(mixed(0, 0.65).cgColor)
            context.setStrokeColor(mixed(0, 0.65).cgColor)
            context.drawPath(using: .fillStroke)
            context.restoreGState()
            context.addPath(path)
            context.setStrokeColor(mixed(0, 0.48).cgColor)
            context.strokePath()
            context.addPath(path)
            context.clip()
            let colors = [mixed(1, 0.8).cgColor, mixed(1, 0.38).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: padding),
                                           end: CGPoint(x: 0, y: canvas.height - padding), options: [])
            }
            context.setFillColor(base.withAlphaComponent(0.17).cgColor)
            let spacing: CGFloat = 10
            for y in stride(from: padding, through: canvas.height, by: spacing) {
                for x in stride(from: padding, through: canvas.width, by: spacing) {
                    let dot = CGRect(x: x, y: y, width: 3.6, height: 3.6)
                    context.addPath(CGPath(roundedRect: dot, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                    context.fillPath()
                }
            }
        }
        cache.setObject(image, forKey: key,
                        cost: Int(canvas.width * canvas.height * format.scale * format.scale * 4))
        return image
    }
}
