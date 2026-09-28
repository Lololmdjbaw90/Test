import SwiftUI

// MARK: - Animated pattern backgrounds

// Cute moving wallpapers for Home and the menu: polka dots, clouds, candy
// stripes, hearts and stars. They follow your accent colour and dark mode,
// and can be turned off in Settings.
enum AppBackground: String, CaseIterable, Identifiable {
    case dots, clouds, stripes, hearts, stars, off
    var id: String { rawValue }
    static let storageKey = "sugerly.background"

    var label: String {
        switch self {
        case .dots: return "Polka dots"
        case .clouds: return "Clouds"
        case .stripes: return "Stripes"
        case .hearts: return "Hearts"
        case .stars: return "Stars"
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

    func body(content: Content) -> some View {
        let kind = AppBackground(rawValue: choice) ?? .dots
        if kind == .off {
            content.sugarBackground()
        } else {
            content.background {
                PatternBackground(kind: kind, animated: !still)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
    }
}

// Each pattern is drawn once (a little bigger than the screen) and then just
// slides — the phone's graphics chip moves it, so it costs almost nothing
// and never slows the app down. It stops when the page isn't showing.
struct PatternBackground: View {
    let kind: AppBackground
    var animated = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var go = false

    private struct Colors {
        var dark: Bool
        var main: Color
        var light: Color
    }

    var body: some View {
        let colors = Colors(dark: scheme == .dark, main: Theme.main, light: Theme.light)
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                base(colors)
                switch kind {
                case .dots:
                    sliding(dx: 52, dy: 0, duration: 8, size: size) { ctx, s in Self.dots(&ctx, s, colors) }
                case .stripes:
                    sliding(dx: 40, dy: 0, duration: 5, size: size) { ctx, s in Self.stripes(&ctx, s, colors) }
                case .hearts:
                    sliding(dx: 0, dy: 86.4, duration: 9, size: size) { ctx, s in Self.hearts(&ctx, s, colors) }
                case .stars:
                    twinkle(size: size, colors)
                case .clouds:
                    Canvas { ctx, s in Self.sky(&ctx, s, colors) }.frame(width: size.width, height: size.height)
                    sliding(dx: Self.cloudSpacing(size), dy: 0, duration: 40, size: size) { ctx, s in Self.cloudLanes(&ctx, s, colors, visibleWidth: size.width) }
                    Canvas { ctx, s in Self.cloudBank(&ctx, s, colors) }.frame(width: size.width, height: size.height)
                case .off:
                    EmptyView()
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
        .background(Palette.bg)
        .onAppear { go = animated && !reduceMotion }
        .onDisappear { go = false }
        .onChange(of: animated) { _, now in go = now && !reduceMotion }
    }

    private func sliding(dx: CGFloat, dy: CGFloat, duration: Double, size: CGSize, draw: @escaping (inout GraphicsContext, CGSize) -> Void) -> some View {
        Canvas { ctx, s in draw(&ctx, s) }
            .frame(width: size.width + dx, height: size.height + abs(dy))
            .offset(x: go ? -dx : 0, y: go ? -abs(dy) : 0)
            .animation(go ? .linear(duration: duration).repeatForever(autoreverses: false) : .easeOut(duration: 0.2), value: go)
    }

    private func twinkle(size: CGSize, _ c: Colors) -> some View {
        ZStack {
            Canvas { ctx, s in Self.stars(&ctx, s, c, even: true) }
                .opacity(go ? 0.25 : 1)
                .animation(go ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default, value: go)
            Canvas { ctx, s in Self.stars(&ctx, s, c, even: false) }
                .opacity(go ? 1 : 0.25)
                .animation(go ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default, value: go)
        }
        .frame(width: size.width, height: size.height)
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
            while x < size.width + gap {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += gap
            }
            context.fill(path, with: .color(tint.opacity(alpha)))
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
        while y < size.height + gap {
            var x: CGFloat = row % 2 == 0 ? 14 : 14 + gap / 2
            while x < size.width + gap {
                path.addPath(heartPath(CGRect(x: x - 7, y: y - 7, width: 14, height: 12.6)))
                x += gap
            }
            y += gap * 0.8
            row += 1
        }
        context.fill(path, with: .color(tint.opacity(c.dark ? 0.16 : 0.18)))
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

// The picker in Settings: small live previews of each background.
struct BackgroundPicker: View {
    @AppStorage(AppBackground.storageKey) private var choice = AppBackground.dots.rawValue
    @AppStorage("sugerly.background.still") private var still = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AppBackground.allCases) { kind in
                        let on = choice == kind.rawValue
                        Button { withAnimation(.snappy) { choice = kind.rawValue } } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if kind == .off {
                                        Palette.bg
                                        Image(systemName: "circle.slash").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.muted)
                                    } else {
                                        PatternBackground(kind: kind, animated: on && !still)
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
    }
}
