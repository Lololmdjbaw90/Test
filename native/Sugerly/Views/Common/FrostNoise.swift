import SwiftUI

// The frosted-glass grain: one small tile of fine light and dark specks
// (plus a few brighter flecks, like sugar frost), made once when the app
// starts and then repeated across glass like wallpaper. Being a still
// picture, the GPU keeps it and redraws it for free while things scroll.
enum FrostNoise {
    /// How strong the grain is in the tile itself; `frostGrain(strength:)`
    /// fades it down from here.
    static let strength = 0.1

    static let image: Image = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        // A fixed seed, so the grain looks the same every launch.
        var seed: UInt32 = 0x9E37_79B9
        func next() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            return Double(seed) / Double(UInt32.max)
        }
        for i in 0..<(size * size) {
            let n = next() - 0.5
            let fleck = next() > 0.985 ? 0.3 : 0
            let light = max(n, 0) * 2 * strength + fleck * strength
            let shade = max(-n, 0) * 2 * strength * 0.6
            // Premultiplied: white specks add light, dark specks a little shade.
            let alpha = min(1, light + shade)
            let white = UInt8(min(1, light) * 255)
            pixels[i * 4] = white
            pixels[i * 4 + 1] = white
            pixels[i * 4 + 2] = white
            pixels[i * 4 + 3] = UInt8(alpha * 255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let tile = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return Image(systemName: "circle").resizable() }
        // Two pixels a point, so each speck is half a point: fine, like frost.
        return Image(decorative: tile, scale: 2)
    }()
}
