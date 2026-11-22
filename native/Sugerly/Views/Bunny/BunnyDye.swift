import SwiftUI
import UIKit

// How clothes and accessories take a colour. They used to be turned round
// the colour wheel (hue rotation), which coloured every piece differently
// (a blue skirt with red trim came out in two clashing colours) and never
// quite matched the swatch you picked. Now they're dyed: every coloured part
// becomes the colour you picked, with the drawing's own shading kept, and
// white, grey and the outline stay as they were (BunnyDye.metal).
enum BunnyDye {
    // How light each picture's coloured parts are on average (0…1), worked
    // out once per picture, so the dye lands on the swatch's own colour.
    nonisolated(unsafe) private static var anchors: [String: Float] = [:]
    private static let lock = NSLock()

    static func anchor(_ key: String, _ image: UIImage?) -> Float {
        lock.lock()
        if let hit = anchors[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let image else { return 0.5 }
        let made = measure(image)
        lock.lock()
        anchors[key] = made
        lock.unlock()
        return made
    }

    private static func measure(_ image: UIImage) -> Float {
        guard let cg = image.cgImage else { return 0.5 }
        let w = 66, h = 90
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0.5 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total = 0.0, weight = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 128 {
            let a = Double(pixels[i + 3]) / 255
            let r = Double(pixels[i]) / 255 / a, g = Double(pixels[i + 1]) / 255 / a, b = Double(pixels[i + 2]) / 255 / a
            let hi = max(r, g, b), lo = min(r, g, b)
            // Only the coloured parts (the same ones the dye changes).
            guard hi > 0.2, hi - lo > 0.2 * hi else { continue }
            let colourful = (hi - lo) / hi
            total += (0.299 * r + 0.587 * g + 0.114 * b) * colourful
            weight += colourful
        }
        return weight > 0 ? Float(total / weight) : 0.5
    }
}

extension View {
    /// Dyes a clothing picture `tint`'s colour; "Original" leaves it as drawn.
    @ViewBuilder
    func bunnyDye(_ tint: BunnyTint?, anchor: Float) -> some View {
        if let tint, !tint.hue.isNaN {
            colorEffect(ShaderLibrary.bunnyDye(.color(Color(hex: tint.swatch)), .float(anchor)))
        } else {
            self
        }
    }
}
