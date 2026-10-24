import SwiftUI
import UIKit

// MARK: - Animated pattern backgrounds

// Cute moving wallpapers for the top of Home: polka dots, clouds, candy
// stripes, hearts, stars, sprinkles, flowers, bubbles and gingham. They
// follow your accent colour and dark mode, and can be turned off in Settings.
enum AppBackground: String, CaseIterable, Identifiable {
    case dots, clouds, stripes, hearts, stars, sprinkles, flowers, bubbles, gingham, off
    var id: String { rawValue }
    static let storageKey = "sugerly.background"

    var label: String {
        switch self {
        case .dots: return "Polka dots"
        case .clouds: return "Clouds"
        case .stripes: return "Stripes"
        case .hearts: return "Hearts"
        case .stars: return "Stars"
        case .sprinkles: return "Sprinkles"
        case .flowers: return "Flowers"
        case .bubbles: return "Bubbles"
        case .gingham: return "Gingham"
        case .off: return "Off"
        }
    }

    var icon: String {
        switch self {
        case .dots: return "circle.grid.3x3.fill"
        case .clouds: return "cloud.fill"
        case .stripes: return "line.3.horizontal"
        case .hearts: return "heart.fill"
        case .stars: return "sparkles"
        case .sprinkles: return "wand.and.stars"
        case .flowers: return "camera.macro"
        case .bubbles: return "bubbles.and.sparkles"
        case .gingham: return "squareshape.split.2x2"
        case .off: return "circle.slash"
        }
    }
}

extension View {
    // Home and the menu use this instead of the plain background.
    func patternBackground() -> some View {
        modifier(PatternBackgroundModifier())
    }
}

private struct PatternBackgroundModifier: ViewModifier {
    @AppStorage(AppBackground.storageKey) private var choice = AppBackground.dots.rawValue
    @AppStorage("sugerly.background.still") private var still = false
    @Environment(\.backgroundPaused) private var paused
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let kind = AppBackground(rawValue: choice) ?? .dots
        // The page itself keeps its identity whatever background is picked;
        // only the background layer is swapped.
        content
            .background {
                if kind == .off {
                    GlowLayer().ignoresSafeArea()
                } else {
                    // A new id for each look, so a freshly picked pattern (or
                    // colour, or dark mode) starts moving again straight away.
                    PatternBackground(kind: kind, animated: !still && !paused && scenePhase == .active)
                        .id("\(kind.rawValue)-\(scheme == .dark)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)")
                        .transition(.opacity)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: choice)
    }
}

// The pattern you picked, as a soft wallpaper at the top of Home that fades
// into the plain background. (Behind the whole page it fought with the
// cards and everything looked busy; up top it's a cute header instead.)
struct HeaderWallpaper: View {
    @AppStorage(AppBackground.storageKey) private var choice = AppBackground.dots.rawValue
    @AppStorage("sugerly.background.still") private var still = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let kind = AppBackground(rawValue: choice) ?? .dots
        if kind != .off {
            PatternBackground(kind: kind, animated: !still && scenePhase == .active)
                .id("\(kind.rawValue)-\(scheme == .dark)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)")
                .transition(.opacity)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .black, location: 0.3),
                        .init(color: .black.opacity(0.9), location: 0.6),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .animation(reduceWallpaperMotion ? nil : .easeInOut(duration: 0.4), value: choice)
        }
    }

    private var reduceWallpaperMotion: Bool { UIAccessibility.isReduceMotionEnabled }
}

// Nothing moves behind a sheet or menu (it would only slow down what's on top).
private struct BackgroundPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var backgroundPaused: Bool {
        get { self[BackgroundPausedKey.self] }
        set { self[BackgroundPausedKey.self] = newValue }
    }
}

// Soft accent glows (the plain page background). The blurred glows are
// drawn once into a small picture and reused by every page, so opening a
// page doesn't have to blur them again (that made pages stutter in).
struct GlowLayer: View {
    @Environment(\.colorScheme) private var scheme
    @State private var drawn: UIImage?

    var body: some View {
        let key = GlowArt.key(scheme)
        let image = GlowArt.cache[key] ?? drawn
        Palette.bg
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: key) {
                if GlowArt.cache[key] == nil { drawn = GlowArt.render(key, scheme: scheme) }
            }
    }
}

@MainActor
enum GlowArt {
    static var cache: [String: UIImage] = [:]

    static func key(_ scheme: ColorScheme) -> String {
        "\(scheme == .dark)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)-\(Theme.custom?.light ?? 0)"
    }

    static func render(_ key: String, scheme: ColorScheme) -> UIImage? {
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: GlowShapes()
            .frame(width: 430, height: 932)
            .environment(\.colorScheme, scheme))
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        if cache.count > 8 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

private struct GlowShapes: View {
    var body: some View {
        ZStack {
            Palette.bg
        }
    }
}

extension View {
    // Page background: a light page with soft colour glows (your pastel,
    // peach, lavender, mint) that drift slowly behind everything.
    func sugarBackground() -> some View { modifier(SugarBackground()) }
}

private struct SugarBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content.background {
            ZStack(alignment: .top) {
                Palette.bg
                AuroraLayer()
                LinearGradient(stops: [
                    .init(color: Theme.light.opacity(dark ? 0.16 : 0.45), location: 0),
                    .init(color: Palette.bg.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
            }
            .ignoresSafeArea()
            .animation(Motion.fade, value: Theme.mainHex)
        }
    }
}

// Big soft glows of colour, drawn once into a picture and slowly drifted
// and breathed by Core Animation (nothing is redrawn while they move).
struct AuroraLayer: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.backgroundPaused) private var paused

    var body: some View {
        let key = AuroraArt.key(scheme)
        if let image = AuroraArt.image(key, scheme: scheme) {
            DriftView(image: image, moving: !reduceMotion && !paused && Motion.ambient)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

@MainActor
enum AuroraArt {
    static var cache: [String: UIImage] = [:]

    static func key(_ scheme: ColorScheme) -> String {
        "\(scheme == .dark)-\(Theme.mainHex)-\(Theme.lightHex)"
    }

    static func image(_ key: String, scheme: ColorScheme) -> UIImage? {
        if let hit = cache[key] { return hit }
        let dark = scheme == .dark
        let blobs: [(UInt32, CGPoint, CGFloat, Double)] = [
            (dark ? Theme.mainHex : Theme.lightHex, CGPoint(x: 0.12, y: 0.08), 0.75, dark ? 0.22 : 0.62),
            (dark ? Theme.partnerHex : Theme.peachHex, CGPoint(x: 0.95, y: 0.16), 0.6, dark ? 0.16 : 0.42),
            (dark ? 0x5B4BB0 : 0xD9CBFF, CGPoint(x: 0.88, y: 0.55), 0.65, dark ? 0.18 : 0.5),
            (dark ? 0x1F6B5A : 0xC4F1DE, CGPoint(x: 0.08, y: 0.72), 0.6, dark ? 0.14 : 0.48),
            (dark ? Theme.partnerHex : 0xFFE9B0, CGPoint(x: 0.7, y: 0.97), 0.55, dark ? 0.12 : 0.42),
        ]
        let size = CGSize(width: 390, height: 844)
        let canvas = Canvas { ctx, s in
            for (hex, at, radius, alpha) in blobs {
                let center = CGPoint(x: at.x * s.width, y: at.y * s.height)
                let r = radius * s.width
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(hex: hex, opacity: alpha), Color(hex: hex, opacity: alpha * 0.45), Color(hex: hex, opacity: 0)]),
                                               center: center, startRadius: 0, endRadius: r))
            }
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.uiImage else { return nil }
        if cache.count > 8 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

// The glows: a picture a little bigger than the page that slowly wanders
// and swells (Core Animation, on the graphics chip).
private struct DriftView: UIViewRepresentable {
    let image: UIImage
    var moving: Bool

    func makeUIView(context: Context) -> Drifter { Drifter() }

    func updateUIView(_ view: Drifter, context: Context) {
        view.update(image: image, moving: moving)
    }

    final class Drifter: UIView {
        private let glow = CALayer()
        private var image: UIImage?
        private var moving = false
        private var laidOut = CGSize.zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            clipsToBounds = true
            glow.contentsGravity = .resize
            layer.addSublayer(glow)
        }

        required init?(coder: NSCoder) { nil }

        func update(image: UIImage, moving: Bool) {
            guard image !== self.image || moving != self.moving else { return }
            self.image = image
            self.moving = moving
            glow.contents = image.cgImage
            setNeedsLayout()
            restart()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.frame = bounds.insetBy(dx: -bounds.width * 0.12, dy: -bounds.height * 0.08)
            CATransaction.commit()
            // The drift is measured in page sizes: start again when it changes.
            if bounds.size != laidOut {
                laidOut = bounds.size
                restart()
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            restart()
        }

        private func restart() {
            glow.removeAllAnimations()
            guard window != nil, moving, bounds.width > 0 else { return }
            let wander = CABasicAnimation(keyPath: "transform.translation")
            wander.fromValue = NSValue(cgSize: CGSize(width: -bounds.width * 0.07, height: -bounds.height * 0.03))
            wander.toValue = NSValue(cgSize: CGSize(width: bounds.width * 0.07, height: bounds.height * 0.04))
            wander.duration = 13
            wander.autoreverses = true
            wander.repeatCount = .infinity
            wander.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wander.isRemovedOnCompletion = false
            glow.add(wander, forKey: "wander")
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 1.0
            breathe.toValue = 1.1
            breathe.duration = 9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathe.isRemovedOnCompletion = false
            glow.add(breathe, forKey: "breathe")
        }
    }
}

// Each pattern is drawn once (a little bigger than the screen) into a
// picture, and the phone's graphics chip slides it (Core Animation). Nothing
// is redrawn while it moves, so scrolling, swiping back and opening sheets
// stay smooth. It stops when the page isn't showing.
struct PatternBackground: View {
    let kind: AppBackground
    var animated = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    // The moving layers, drawn once into pictures.
    @State private var art: [String: UIImage] = [:]
    @State private var artSize: CGSize = .zero

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.backgroundPaused) private var paused
    @AppStorage("sugerly.background.speed") private var speed = 1.5
    @AppStorage("sugerly.background.intensity") private var intensity = 1.0
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private static let bitmapCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    private struct Colors {
        var dark: Bool
        var main: Color
        var light: Color
    }

    private var moving: Bool { animated && !reduceMotion && !paused && !lowPower && scenePhase == .active }

    var body: some View {
        let colors = Colors(dark: scheme == .dark, main: Theme.main, light: Theme.light)
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                base(colors)
                switch kind {
                case .dots:
                    sliding("dots", dx: 52, dy: 0, duration: 8, size: size, colors)
                case .stripes:
                    sliding("stripes", dx: 40, dy: 0, duration: 5, size: size, colors)
                case .hearts:
                    sliding("hearts", dx: 0, dy: 86.4, duration: 9, size: size, colors)
                case .stars:
                    twinkle(size: size, colors)
                case .sprinkles:
                    sliding("sprinkles", dx: 64, dy: 64, duration: 10, size: size, colors)
                case .flowers:
                    sliding("flowers", dx: 90, dy: 0, duration: 14, size: size, colors)
                case .bubbles:
                    sliding("bubbles", dx: 0, dy: 140, duration: 12, size: size, colors)
                case .gingham:
                    sliding("gingham", dx: 36, dy: 36, duration: 9, size: size, colors)
                case .clouds:
                    // A soft sky, small far clouds drifting slowly, bigger
                    // near ones a little quicker, and a fluffy bank below.
                    Canvas { ctx, s in Self.sky(&ctx, s, colors) }.frame(width: size.width, height: size.height)
                    sliding("clouds-far", dx: Self.cloudSpacing(near: false, width: size.width), dy: 0, duration: 70, size: size, colors)
                    sliding("clouds-near", dx: Self.cloudSpacing(near: true, width: size.width), dy: 0, duration: 42, size: size, colors)
                    Canvas { ctx, s in Self.cloudBank(&ctx, s, colors) }.frame(width: size.width, height: size.height)
                case .off:
                    EmptyView()
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .opacity(min(1, max(0.15, intensity)))
            .task(id: "\(size)-\(kind.rawValue)-\(Theme.mainHex)-\(Theme.lightHex)-\(scheme == .dark)") {
                await Task.yield()
                guard !Task.isCancelled else { return }
                draw(size, colors)
            }
        }
        .background(Palette.bg)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // What each moving layer draws.
    private static func painter(_ name: String, _ size: CGSize, _ c: Colors) -> (inout GraphicsContext, CGSize) -> Void {
        switch name {
        case "dots": return { ctx, s in Self.dots(&ctx, s, c) }
        case "stripes": return { ctx, s in Self.stripes(&ctx, s, c) }
        case "hearts": return { ctx, s in Self.hearts(&ctx, s, c) }
        case "stars-even": return { ctx, s in Self.stars(&ctx, s, c, even: true) }
        case "stars-odd": return { ctx, s in Self.stars(&ctx, s, c, even: false) }
        case "sprinkles": return { ctx, s in Self.sprinkles(&ctx, s, c) }
        case "flowers": return { ctx, s in Self.flowers(&ctx, s, c) }
        case "bubbles": return { ctx, s in Self.bubbles(&ctx, s, c) }
        case "gingham": return { ctx, s in Self.gingham(&ctx, s, c) }
        case "clouds-far": return { ctx, s in Self.cloudLanes(&ctx, s, c, near: false, visibleWidth: size.width) }
        default: return { ctx, s in Self.cloudLanes(&ctx, s, c, near: true, visibleWidth: size.width) }
        }
    }

    // Draws the moving layers into pictures (once per screen size).
    private func draw(_ size: CGSize, _ c: Colors) {
        guard size.width > 1, size.height > 1 else { return }
        let layers: [(String, CGSize)]
        switch kind {
        case .dots: layers = [("dots", CGSize(width: size.width + 52, height: size.height))]
        case .stripes: layers = [("stripes", CGSize(width: size.width + 40, height: size.height))]
        case .hearts: layers = [("hearts", CGSize(width: size.width, height: size.height + 86.4))]
        case .clouds:
            layers = [("clouds-far", CGSize(width: size.width + Self.cloudSpacing(near: false, width: size.width), height: size.height)),
                      ("clouds-near", CGSize(width: size.width + Self.cloudSpacing(near: true, width: size.width), height: size.height))]
        case .stars: layers = [("stars-even", size), ("stars-odd", size)]
        case .sprinkles: layers = [("sprinkles", CGSize(width: size.width + 64, height: size.height + 64))]
        case .flowers: layers = [("flowers", CGSize(width: size.width + 90, height: size.height))]
        case .bubbles: layers = [("bubbles", CGSize(width: size.width, height: size.height + 140))]
        case .gingham: layers = [("gingham", CGSize(width: size.width + 36, height: size.height + 36))]
        case .off: layers = []
        }
        var next: [String: UIImage] = [:]
        for (name, full) in layers {
            let key = "\(name)-\(full)-\(Theme.mainHex)-\(Theme.lightHex)-\(c.dark)" as NSString
            if let cached = Self.bitmapCache.object(forKey: key) { next[name] = cached; continue }
            let paint = Self.painter(name, size, c)
            let renderer = ImageRenderer(content: Canvas { ctx, s in paint(&ctx, s) }.frame(width: full.width, height: full.height))
            // Patterns are soft decoration; 1.5x keeps their texture small.
            renderer.scale = min(displayScale, 1.5)
            renderer.isOpaque = false
            if let image = renderer.uiImage {
                next[name] = image
                Self.bitmapCache.setObject(image, forKey: key, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
            }
        }
        art = next
        artSize = size
    }

    @ViewBuilder
    private func sliding(_ name: String, dx: CGFloat, dy: CGFloat, duration: Double, size: CGSize, _ c: Colors) -> some View {
        if moving, let image = art[name] {
            LayerMover(image: image, dx: dx, dy: abs(dy), duration: duration * min(3, max(0.7, speed)))
                .frame(width: size.width, height: size.height)
        } else if let image = art[name] {
            Image(uiImage: image).resizable()
                .frame(width: size.width + dx, height: size.height + abs(dy))
        } else {
            let paint = Self.painter(name, size, c)
            Canvas { ctx, s in paint(&ctx, s) }
                .frame(width: size.width + dx, height: size.height + abs(dy))
        }
    }

    @ViewBuilder
    private func twinkle(size: CGSize, _ c: Colors) -> some View {
        if moving, let even = art["stars-even"], let odd = art["stars-odd"] {
            ZStack {
                LayerMover(image: even, duration: 3.2 * speed, fade: true, startFaded: false)
                LayerMover(image: odd, duration: 3.2 * speed, fade: true, startFaded: true)
            }
            .frame(width: size.width, height: size.height)
        } else {
            let even = Self.painter("stars-even", size, c)
            let odd = Self.painter("stars-odd", size, c)
            ZStack {
                Canvas { ctx, s in even(&ctx, s) }
                Canvas { ctx, s in odd(&ctx, s) }.opacity(0.25)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // Soft base: blush at the bottom (like the pictures), deep plum in dark mode.
    private func base(_ c: Colors) -> some View {
        LinearGradient(colors: [c.dark ? Color(hex: 0x140A11) : Color.white.opacity(0.92), c.dark ? c.main.opacity(0.3) : c.light.opacity(0.7)],
                       startPoint: .top, endPoint: .bottom)
    }

    // Polka dots, a little stronger towards the bottom.
    private static func dots(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let gap: CGFloat = 26
        let tint = c.dark ? c.light : c.main
        var row = 0
        var y: CGFloat = 8
        while y < size.height + gap {
            let depth = max(0, min(1, y / max(1, size.height)))
            let alpha = c.dark ? 0.06 + depth * 0.16 : 0.05 + depth * 0.22
            let radius = 5.2 + depth * 1.6
            var x: CGFloat = row % 2 == 0 ? 6 : 6 + gap / 2
            var path = Path()
            var shine = Path()
            while x < size.width + gap {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                // A little candy shine on each dot.
                shine.addEllipse(in: CGRect(x: x - radius * 0.62, y: y - radius * 0.66, width: radius * 0.6, height: radius * 0.46))
                x += gap
            }
            context.fill(path, with: .color(tint.opacity(alpha)))
            context.fill(shine, with: .color(.white.opacity(c.dark ? 0.1 : 0.6 * depth + 0.15)))
            y += gap * 0.86
            row += 1
        }
    }

    private static func stripes(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let width: CGFloat = 20
        var path = Path()
        var x: CGFloat = 0
        while x < size.width + width {
            path.addRect(CGRect(x: x, y: 0, width: width, height: size.height))
            x += width * 2
        }
        let tint = c.dark ? c.light : c.main
        context.fill(path, with: .linearGradient(Gradient(colors: [tint.opacity(c.dark ? 0.04 : 0.03), tint.opacity(c.dark ? 0.16 : 0.2)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private static func hearts(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let gap: CGFloat = 54
        let tint = c.dark ? c.light : c.main
        var row = 0
        var y: CGFloat = 20
        var path = Path()
        var shine = Path()
        while y < size.height + gap {
            var x: CGFloat = row % 2 == 0 ? 14 : 14 + gap / 2
            // Every other row a little smaller (the pattern still repeats
            // every two rows, so it loops smoothly).
            let w: CGFloat = row % 2 == 0 ? 15 : 11
            while x < size.width + gap {
                path.addPath(heartPath(CGRect(x: x - w / 2, y: y - w / 2, width: w, height: w * 0.9)))
                shine.addEllipse(in: CGRect(x: x - w * 0.36, y: y - w * 0.36, width: w * 0.2, height: w * 0.16))
                x += gap
            }
            y += gap * 0.8
            row += 1
        }
        context.fill(path, with: .color(tint.opacity(c.dark ? 0.2 : 0.22)))
        context.fill(shine, with: .color(.white.opacity(c.dark ? 0.12 : 0.6)))
    }

    // Candy sprinkles in six colours, sliding gently down and to the side.
    private static func sprinkles(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let tile: CGFloat = 64
        let colors: [Color] = [c.main, c.light, Color(hex: 0xFFB38A), Color(hex: 0xB19CFF), Color(hex: 0x7FD8BE), Color(hex: 0xFFD166)]
        let spots: [(CGFloat, CGFloat, Double)] = [(10, 12, 30), (42, 9, -40), (25, 33, 70), (53, 41, 15), (9, 52, -60), (37, 57, 45)]
        let alpha = c.dark ? 0.42 : 0.5
        var y: CGFloat = -tile
        while y < size.height + tile {
            var x: CGFloat = -tile
            while x < size.width + tile {
                for (i, spot) in spots.enumerated() {
                    var piece = context
                    piece.translateBy(x: x + spot.0, y: y + spot.1)
                    piece.rotate(by: .degrees(spot.2))
                    let rect = CGRect(x: -6, y: -1.9, width: 12, height: 3.8)
                    piece.fill(Path(roundedRect: rect, cornerRadius: 1.9), with: .color(colors[i % colors.count].opacity(alpha)))
                }
                x += tile
            }
            y += tile
        }
    }

    // Little daisies drifting sideways.
    private static func flowers(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let tile: CGFloat = 90
        let tint = c.dark ? c.light : c.main
        let center = Color(hex: 0xFFD166).opacity(c.dark ? 0.5 : 0.75)
        var row = 0
        var y: CGFloat = 22
        while y < size.height + tile {
            var x: CGFloat = row % 2 == 0 ? 22 : 22 + tile / 2
            let radius: CGFloat = row % 2 == 0 ? 10 : 7.5
            while x < size.width + tile {
                flower(&context, CGPoint(x: x, y: y), radius: radius, petals: tint.opacity(c.dark ? 0.22 : 0.24), center: center)
                x += tile
            }
            y += tile * 0.62
            row += 1
        }
    }

    private static func flower(_ context: inout GraphicsContext, _ p: CGPoint, radius r: CGFloat, petals: Color, center: Color) {
        var path = Path()
        for i in 0..<5 {
            let angle = Double(i) / 5 * 2 * Double.pi - Double.pi / 2
            let cx = p.x + CGFloat(cos(angle)) * r * 0.85
            let cy = p.y + CGFloat(sin(angle)) * r * 0.85
            path.addEllipse(in: CGRect(x: cx - r * 0.6, y: cy - r * 0.6, width: r * 1.2, height: r * 1.2))
        }
        context.fill(path, with: .color(petals))
        context.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.42, y: p.y - r * 0.42, width: r * 0.84, height: r * 0.84)), with: .color(center))
    }

    // Soap bubbles with a shine, floating up.
    private static func bubbles(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let period: CGFloat = 140
        let tint = c.dark ? c.light : c.main
        var y: CGFloat = -period
        while y < size.height + period {
            var i = 0
            var x: CGFloat = 16
            while x < size.width + 24 {
                let r = 5 + CGFloat(i * 37 % 11) / 11 * 10
                let by = y + CGFloat(i * 53 % 17) / 17 * period
                let rect = CGRect(x: x - r, y: by - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(c.dark ? 0.08 : 0.07)))
                context.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(c.dark ? 0.32 : 0.3)), lineWidth: 1.4)
                let s = r * 0.34
                context.fill(Path(ellipseIn: CGRect(x: x - r * 0.5, y: by - r * 0.58, width: s, height: s * 0.8)), with: .color(.white.opacity(c.dark ? 0.3 : 0.8)))
                x += 44
                i += 1
            }
            y += period
        }
    }

    // Soft picnic gingham, sliding slowly.
    private static func gingham(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let cell: CGFloat = 18
        let tint = (c.dark ? c.light : c.main).opacity(c.dark ? 0.07 : 0.085)
        var columns = Path()
        var x: CGFloat = 0
        while x < size.width + cell * 2 {
            columns.addRect(CGRect(x: x, y: 0, width: cell, height: size.height))
            x += cell * 2
        }
        var rows = Path()
        var y: CGFloat = 0
        while y < size.height + cell * 2 {
            rows.addRect(CGRect(x: 0, y: y, width: size.width, height: cell))
            y += cell * 2
        }
        context.fill(columns, with: .color(tint))
        context.fill(rows, with: .color(tint))
    }

    static func heartPath(_ r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3), control1: CGPoint(x: r.midX - r.width * 0.1, y: r.maxY - r.height * 0.15), control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.62))
        p.addArc(center: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62), control2: CGPoint(x: r.midX + r.width * 0.1, y: r.maxY - r.height * 0.15))
        p.closeSubpath()
        return p
    }

    private static func stars(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors, even: Bool) {
        let gap: CGFloat = 48
        let tint = c.dark ? Color.white : c.main
        var row = 0
        var y: CGFloat = 20
        var path = Path()
        while y < size.height + gap {
            var x: CGFloat = row % 2 == 0 ? 18 : 18 + gap / 2
            var col = 0
            while x < size.width + gap {
                if ((row + col) % 2 == 0) == even {
                    path.addPath(sparkle(CGPoint(x: x, y: y), (row * 3 + col) % 3 == 0 ? 8 : 6))
                }
                x += gap
                col += 1
            }
            y += gap * 0.85
            row += 1
        }
        context.fill(path, with: .color(tint.opacity(c.dark ? 0.35 : 0.3)))
    }

    private static func sparkle(_ c: CGPoint, _ radius: CGFloat) -> Path {
        var p = Path()
        let inner = radius * 0.3
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? radius : inner
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    // MARK: clouds

    // Clouds are a little smaller on small previews (Settings).
    private static func cloudScale(_ width: CGFloat) -> CGFloat { min(1, max(0.5, width / 390)) }

    // Each layer repeats every this many points across, so sliding it by
    // exactly that much loops with no seam.
    static func cloudSpacing(near: Bool, width: CGFloat) -> CGFloat { (near ? 300 : 210) * cloudScale(width) }

    // A soft sky: your pastel, a little deeper towards the bottom.
    private static func sky(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let top = c.dark ? c.main.opacity(0.18) : c.light.opacity(0.35)
        let bottom = c.dark ? c.main.opacity(0.32) : c.light.opacity(0.65)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    // Rows of clouds, far and near ones taking turns down the page. Every
    // row has its own height band (a cloud reaches 0.36 of its width above
    // its centre and 0.24 below, shadow included) with clear sky between
    // bands, so clouds never touch, even though the two layers drift at
    // different speeds; within a row they're one spacing apart (so the
    // layer loops). No row reaches the bank at the bottom.
    private static func cloudLanes(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors, near: Bool, visibleWidth: CGFloat) {
        let k = cloudScale(visibleWidth)
        let spacing = cloudSpacing(near: near, width: visibleWidth)
        // (centre, width, near, where along the row it starts)
        let rows: [(y: CGFloat, width: CGFloat, near: Bool, phase: CGFloat)] = [
            (60, 70, false, 0.6), (150, 128, true, 0.15), (235, 60, false, 0.95), (320, 110, true, 0.52),
        ]
        let period: CGFloat = 340
        let floor = size.height - 125 * k
        let style = CloudArt.Style(fill: c.dark ? Color(hex: 0x3A2632) : .white,
                                   shade: c.dark ? c.main.opacity(0.32) : c.light.opacity(0.75))
        var layer = context
        layer.opacity = near ? 1 : (c.dark ? 0.6 : 0.75)
        var base: CGFloat = 0
        while base * k < floor {
            for row in rows where row.near == near {
                let y = (base + row.y) * k
                let width = row.width * k
                guard y + width * 0.24 < floor else { continue }
                var x = row.phase * spacing - spacing
                while x < size.width + spacing {
                    CloudArt.draw(&layer, center: CGPoint(x: x, y: y), width: width, style: style)
                    x += spacing
                }
            }
            base += period
        }
    }

    // A fluffy bank of clouds along the bottom.
    private static func cloudBank(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let style = CloudArt.Style(fill: c.dark ? Color(hex: 0x3A2632) : .white,
                                   shade: c.dark ? c.main.opacity(0.32) : c.light.opacity(0.75))
        let k = cloudScale(size.width)
        var bank = Path()
        let radii: [CGFloat] = [46, 34, 52, 38, 44, 32, 50]
        var x: CGFloat = -20
        var i = 0
        while x < size.width + 60 {
            let r = radii[i % radii.count] * k
            bank.addEllipse(in: CGRect(x: x - r, y: size.height - r * 1.25, width: r * 2, height: r * 2))
            x += r * 1.35
            i += 1
        }
        bank.addRect(CGRect(x: -20, y: size.height - 26 * k, width: size.width + 40, height: 60))
        CloudArt.fill(&context, bank, height: 90 * k, style: style)
    }
}

// The one cloud used everywhere (the Clouds background and the bunny's
// cloudy sky): a flat bottom and four round puffs as one smooth shape, white
// with a soft shade along its underside and a soft shadow below it. No
// outlines.
enum CloudArt {
    struct Style {
        var fill: Color
        var shade: Color
    }

    static func path(center c: CGPoint, width w: CGFloat) -> Path {
        var p = Path()
        // The flat base.
        p.addRoundedRect(in: CGRect(x: c.x - w / 2, y: c.y - w * 0.03, width: w, height: w * 0.22),
                         cornerSize: CGSize(width: w * 0.11, height: w * 0.11))
        // Puffs: across, up, and how big (all as parts of the width).
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, 0.01, 0.17), (-0.1, -0.08, 0.23), (0.15, -0.1, 0.26), (0.34, 0.0, 0.15)]
        for puff in puffs {
            let r = w * puff.2
            p.addEllipse(in: CGRect(x: c.x + w * puff.0 - r, y: c.y + w * puff.1 - r, width: r * 2, height: r * 2))
        }
        return p
    }

    static func draw(_ context: inout GraphicsContext, center: CGPoint, width: CGFloat, style: Style) {
        fill(&context, path(center: center, width: width), height: width * 0.46, style: style)
    }

    // Shadow, body, then the shade on its lower part (clipped to the cloud).
    static func fill(_ context: inout GraphicsContext, _ shape: Path, height: CGFloat, style: Style) {
        let box = shape.boundingRect
        context.fill(shape.offsetBy(dx: 0, dy: height * 0.1), with: .color(style.shade.opacity(0.45)))
        context.fill(shape, with: .color(style.fill))
        var inner = context
        inner.clip(to: shape)
        inner.fill(Path(box), with: .linearGradient(
            Gradient(stops: [.init(color: style.shade.opacity(0), location: 0.45), .init(color: style.shade.opacity(0.55), location: 1)]),
            startPoint: CGPoint(x: box.midX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)))
    }
}

// Previews already drawn this session, per look (dark mode + colours), so
// opening Settings again shows them straight away.
@MainActor
private enum BackgroundPreviews {
    static var drawn: [String: [AppBackground: UIImage]] = [:]

    // Also kept on the phone, so after the first time Settings shows them
    // at once instead of drawing nine pictures while you scroll.
    private static var folder: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ key: String, _ kind: AppBackground) -> URL {
        folder.appendingPathComponent("v2-\(key)-\(kind.rawValue).png")
    }

    static func load(_ key: String) -> [AppBackground: UIImage]? {
        var found: [AppBackground: UIImage] = [:]
        for kind in AppBackground.allCases where kind != .off {
            guard let image = UIImage(contentsOfFile: file(key, kind).path) else { return nil }
            found[kind] = image
        }
        return found
    }

    static func save(_ images: [AppBackground: UIImage], _ key: String) {
        let files = images.map { (file(key, $0.key), $0.value) }
        DispatchQueue.global(qos: .utility).async {
            for (url, image) in files { try? image.pngData()?.write(to: url, options: .atomic) }
        }
    }
}

// The picker in Settings: small live previews of each background.
struct BackgroundPicker: View {
    @AppStorage(AppBackground.storageKey) private var choice = AppBackground.dots.rawValue
    @AppStorage("sugerly.background.still") private var still = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    // Each look drawn once into a little picture (cheap to scroll past).
    @State private var previews: [AppBackground: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AppBackground.allCases) { kind in
                        let on = choice == kind.rawValue
                        Button { withMotion(Motion.standard) { choice = kind.rawValue } } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if kind == .off {
                                        Palette.bg
                                        Image(systemName: "circle.slash").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.muted)
                                    } else if let image = previews[kind] {
                                        Image(uiImage: image).resizable()
                                    } else {
                                        Palette.surface2
                                    }
                                }
                                .frame(width: 74, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Palette.border), lineWidth: on ? 3 : 1))
                                .shadow(color: on ? Theme.main.opacity(0.3) : .clear, radius: 8, y: 3)
                                Label(kind.label, systemImage: kind.icon).labelStyle(.titleOnly)
                                    .font(.jakarta(11, .bold)).foregroundStyle(on ? Theme.main : Palette.text2)
                            }
                        }
                        .buttonStyle(BouncyStyle(scale: 0.94))
                    }
                }
                .padding(.vertical, 4)
            }
            Toggle(isOn: Binding(get: { !still }, set: { still = !$0 })) {
                Label("Animate the background", systemImage: "wand.and.stars").font(.jakarta(14, .semibold)).foregroundStyle(Palette.text)
            }
            .tint(Theme.main)
        }
        .task(id: previewKey) { await drawPreviews() }
    }

    private var previewKey: String { "\(scheme == .dark)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)" }

    // Drawing all of them at once, while Settings was still sliding open,
    // made the page stutter. Now: reuse ones already drawn, otherwise wait
    // until the page is open and draw one per frame, each fading in.
    private func drawPreviews() async {
        let key = previewKey
        if let ready = BackgroundPreviews.drawn[key] { previews = ready; return }
        if let saved = BackgroundPreviews.load(key) {
            BackgroundPreviews.drawn[key] = saved
            previews = saved
            return
        }
        previews = [:]
        try? await Task.sleep(for: .milliseconds(450))
        var drawn: [AppBackground: UIImage] = [:]
        for kind in AppBackground.allCases where kind != .off {
            guard !Task.isCancelled else { return }
            let renderer = ImageRenderer(content: PatternBackground(kind: kind, animated: false)
                .frame(width: 74, height: 104)
                .environment(\.colorScheme, scheme))
            renderer.scale = scale
            drawn[kind] = renderer.uiImage
            withAnimation(.easeOut(duration: 0.2)) { previews = drawn }
            try? await Task.sleep(for: .milliseconds(16))
        }
        BackgroundPreviews.drawn[key] = drawn
        BackgroundPreviews.save(drawn, key)
    }
}

// A picture moved (or faded) by Core Animation on the graphics chip, so a
// moving background costs nothing on the main thread.
private struct LayerMover: UIViewRepresentable {
    let image: UIImage
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var duration: Double
    var fade = false
    var startFaded = false

    func makeUIView(context: Context) -> MoverView { MoverView() }

    func updateUIView(_ view: MoverView, context: Context) {
        view.update(image: image, dx: dx, dy: dy, duration: duration, fade: fade, startFaded: startFaded)
    }

    final class MoverView: UIView {
        private let content = CALayer()
        private var image: UIImage?
        private var dx: CGFloat = 0
        private var dy: CGFloat = 0
        private var duration: Double = 1
        private var fade = false
        private var startFaded = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            clipsToBounds = true
            layer.addSublayer(content)
        }

        required init?(coder: NSCoder) { nil }

        func update(image: UIImage, dx: CGFloat, dy: CGFloat, duration: Double, fade: Bool, startFaded: Bool) {
            let changed = image !== self.image || dx != self.dx || dy != self.dy || duration != self.duration || fade != self.fade || startFaded != self.startFaded
            guard changed else { return }
            let replacingImage = self.image != nil && self.image !== image
            self.image = image
            self.dx = dx
            self.dy = dy
            self.duration = duration
            self.fade = fade
            self.startFaded = startFaded
            if replacingImage && !UIAccessibility.isReduceMotionEnabled {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.35
                content.add(fade, forKey: "wallpaper-fade")
            }
            content.contents = image.cgImage
            content.contentsScale = image.scale
            setNeedsLayout()
            restart()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.frame = CGRect(x: 0, y: 0, width: bounds.width + dx, height: bounds.height + dy)
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            restart()
        }

        private func restart() {
            content.removeAnimation(forKey: "move")
            guard window != nil, image != nil else { return }
            let animation: CABasicAnimation
            if fade {
                animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = startFaded ? 0.25 : 1.0
                animation.toValue = startFaded ? 1.0 : 0.25
                animation.autoreverses = true
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            } else {
                animation = CABasicAnimation(keyPath: "transform.translation")
                animation.fromValue = NSValue(cgSize: .zero)
                animation.toValue = NSValue(cgSize: CGSize(width: -dx, height: -dy))
            }
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            content.add(animation, forKey: "move")
        }
    }
}
