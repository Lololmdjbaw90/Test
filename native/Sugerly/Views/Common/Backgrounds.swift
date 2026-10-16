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
                        .id("\(kind.rawValue)-\(still)-\(scheme == .dark)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)")
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                }
            }
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
        // The calm design keeps the top of Home plain.
        let kind = AppBackground.off
        if kind != .off {
            PatternBackground(kind: kind, animated: !still && scenePhase == .active)
                .id("\(kind.rawValue)-\(still)-\(scheme == .dark)-\(Theme.accent.rawValue)-\(Theme.custom?.main ?? 0)")
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.8), location: 0.36),
                        .init(color: .black.opacity(0.7), location: 0.5),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
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
    // Page background: a soft rosy page with a gentle wash of your colour
    // at the very top that fades away as it goes down.
    func sugarBackground() -> some View { modifier(SugarBackground()) }
}

private struct SugarBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    // The page: warm cream-white, with the palette washing down from the
    // top — your pastel, then cream — and fading into the page.
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content.background {
            ZStack(alignment: .top) {
                Palette.bg
                LinearGradient(stops: [
                    .init(color: Theme.light.opacity(dark ? 0.16 : 0.42), location: 0),
                    .init(color: Palette.cream.opacity(dark ? 0.05 : 0.45), location: 0.5),
                    .init(color: Palette.bg.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 380)
            }
            .ignoresSafeArea()
            .animation(Motion.fade, value: Theme.mainHex)
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

    private struct Colors {
        var dark: Bool
        var main: Color
        var light: Color
    }

    private var moving: Bool { animated && !reduceMotion }

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
                    Canvas { ctx, s in Self.sky(&ctx, s, colors) }.frame(width: size.width, height: size.height)
                    sliding("clouds", dx: Self.cloudSpacing(size), dy: 0, duration: 40, size: size, colors)
                    Canvas { ctx, s in Self.cloudBank(&ctx, s, colors) }.frame(width: size.width, height: size.height)
                case .off:
                    EmptyView()
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .task(id: moving ? size : .zero) {
                guard moving, size != artSize || art.isEmpty else { return }
                draw(size, colors)
            }
        }
        .background(Palette.bg)
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
        default: return { ctx, s in Self.cloudLanes(&ctx, s, c, visibleWidth: size.width) }
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
        case .clouds: layers = [("clouds", CGSize(width: size.width + Self.cloudSpacing(size), height: size.height))]
        case .stars: layers = [("stars-even", size), ("stars-odd", size)]
        case .sprinkles: layers = [("sprinkles", CGSize(width: size.width + 64, height: size.height + 64))]
        case .flowers: layers = [("flowers", CGSize(width: size.width + 90, height: size.height))]
        case .bubbles: layers = [("bubbles", CGSize(width: size.width, height: size.height + 140))]
        case .gingham: layers = [("gingham", CGSize(width: size.width + 36, height: size.height + 36))]
        case .off: layers = []
        }
        var next: [String: UIImage] = [:]
        for (name, full) in layers {
            let paint = Self.painter(name, size, c)
            let renderer = ImageRenderer(content: Canvas { ctx, s in paint(&ctx, s) }.frame(width: full.width, height: full.height))
            renderer.scale = displayScale
            renderer.isOpaque = false
            if let image = renderer.uiImage { next[name] = image }
        }
        art = next
        artSize = size
    }

    @ViewBuilder
    private func sliding(_ name: String, dx: CGFloat, dy: CGFloat, duration: Double, size: CGSize, _ c: Colors) -> some View {
        if moving, let image = art[name] {
            LayerMover(image: image, dx: dx, dy: abs(dy), duration: duration)
                .frame(width: size.width, height: size.height)
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
                LayerMover(image: even, duration: 1.6, fade: true, startFaded: false)
                LayerMover(image: odd, duration: 1.6, fade: true, startFaded: true)
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
        LinearGradient(colors: [c.dark ? Color(hex: 0x140A11) : Color.white.opacity(0.92), c.dark ? c.main.opacity(0.28) : c.light.opacity(0.55)],
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

    private static func cloudWidth(_ size: CGSize) -> CGFloat { min(160, max(110, size.width * 0.36)) }
    static func cloudSpacing(_ size: CGSize) -> CGFloat { cloudWidth(size) * 2.1 }

    // Pink sky with tidy white polka dots.
    private static func sky(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let top = c.dark ? c.main.opacity(0.18) : c.light.opacity(0.28)
        let bottom = c.dark ? c.main.opacity(0.3) : c.light.opacity(0.5)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let gap: CGFloat = 24
        var dotsPath = Path()
        var row = 0
        var y: CGFloat = 10
        while y < size.height {
            var x: CGFloat = row % 2 == 0 ? 8 : 8 + gap / 2
            while x < size.width + gap {
                dotsPath.addEllipse(in: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8))
                x += gap
            }
            y += gap * 0.86
            row += 1
        }
        context.fill(dotsPath, with: .color(.white.opacity(c.dark ? 0.09 : 0.8)))
    }

    // Even lanes of clouds, every other lane shifted half a step.
    private static func cloudLanes(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors, visibleWidth: CGFloat) {
        let fill = c.dark ? Color(hex: 0x2A1822) : Color.white
        let edge = c.light.opacity(c.dark ? 0.55 : 0.9)
        let width = cloudWidth(CGSize(width: visibleWidth, height: size.height))
        let spacing = width * 2.1
        var lane = 0
        var laneY: CGFloat = 80
        var all = Path()
        while laneY < size.height - 90 {
            var x = (lane % 2 == 0 ? 0 : spacing / 2) - spacing / 2
            while x < size.width + spacing {
                all.addPath(cloudPath(center: CGPoint(x: x, y: laneY), width: width))
                x += spacing
            }
            laneY += 165
            lane += 1
        }
        context.stroke(all, with: .color(edge), lineWidth: 6)
        context.fill(all, with: .color(fill))
    }

    // Scalloped cloud bank along the bottom.
    private static func cloudBank(_ context: inout GraphicsContext, _ size: CGSize, _ c: Colors) {
        let fill = c.dark ? Color(hex: 0x2A1822) : Color.white
        let edge = c.light.opacity(c.dark ? 0.55 : 0.9)
        let r: CGFloat = 40
        var bank = Path()
        var bx: CGFloat = -r * 0.5
        while bx < size.width + r {
            bank.addEllipse(in: CGRect(x: bx - r, y: size.height - r * 1.35, width: r * 2, height: r * 2))
            bx += r * 1.45
        }
        bank.addRect(CGRect(x: 0, y: size.height - r * 0.5, width: size.width, height: r))
        context.stroke(bank, with: .color(edge), lineWidth: 6)
        context.fill(bank, with: .color(fill))
    }

    // A classic cute cloud: flat bottom and three round puffs.
    private static func cloudPath(center c: CGPoint, width w: CGFloat) -> Path {
        var p = Path()
        let h = w * 0.5
        p.addRoundedRect(in: CGRect(x: c.x - w / 2, y: c.y - h * 0.02, width: w, height: h * 0.42), cornerSize: CGSize(width: h * 0.21, height: h * 0.21))
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-0.24, 0.0, 0.19), (0.02, -0.16, 0.26), (0.27, 0.03, 0.16)]
        for puff in puffs {
            let rr = w * puff.2
            p.addEllipse(in: CGRect(x: c.x + w * puff.0 - rr, y: c.y + h * puff.1 - rr, width: rr * 2, height: rr * 2))
        }
        return p
    }
}

// Previews already drawn this session, per look (dark mode + colours), so
// opening Settings again shows them straight away.
@MainActor
private enum BackgroundPreviews {
    static var drawn: [String: [AppBackground: UIImage]] = [:]
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
            self.image = image
            self.dx = dx
            self.dy = dy
            self.duration = duration
            self.fade = fade
            self.startFaded = startFaded
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
