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

struct PatternBackground: View {
    let kind: AppBackground
    var animated = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = animated && !reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moving)) { timeline in
            let t = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas(rendersAsynchronously: true) { context, size in
                draw(&context, size: size, t: t)
            }
        }
        .background(Palette.bg)
    }

    private var dark: Bool { scheme == .dark }

    // Soft base: blush at the bottom (like the pictures), deep plum in dark mode.
    private func base(_ context: inout GraphicsContext, _ size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let top = dark ? Color(hex: 0x140A11) : Color.white
        let bottom = dark ? Theme.main.opacity(0.28) : Theme.light.opacity(0.55)
        context.fill(Path(rect), with: .color(Palette.bg))
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [top.opacity(dark ? 1 : 0.9), bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        base(&context, size)
        switch kind {
        case .dots: dots(&context, size, t)
        case .clouds: clouds(&context, size, t)
        case .stripes: stripes(&context, size, t)
        case .hearts: hearts(&context, size, t)
        case .stars: stars(&context, size, t)
        case .off: break
        }
    }

    // Halftone polka dots drifting diagonally, stronger towards the bottom.
    private func dots(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let gap: CGFloat = 26
        let drift = CGFloat((t * 8).truncatingRemainder(dividingBy: Double(gap * 2)))
        let tint = dark ? Theme.light : Theme.main
        var row = -2
        var y = -gap * 2 + drift * 0.5
        while y < size.height + gap {
            let depth = max(0, min(1, y / max(1, size.height)))
            let alpha = dark ? 0.06 + depth * 0.16 : 0.05 + depth * 0.22
            let radius = 5.2 + depth * 1.6
            let shift = (row % 2 == 0 ? 0 : gap / 2) + drift
            var x = -gap * 2 + shift
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

    // Neat rows of puffy clouds with a candy outline drifting over a
    // polka-dot sky, and a scalloped cloud bank along the bottom.
    private func clouds(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let skyTop = dark ? Theme.main.opacity(0.18) : Theme.light.opacity(0.28)
        let skyBottom = dark ? Theme.main.opacity(0.3) : Theme.light.opacity(0.5)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [skyTop, skyBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        // Tidy polka dots in the sky.
        let gap: CGFloat = 24
        var sky = Path()
        var row = 0
        var y: CGFloat = 10
        while y < size.height {
            var x: CGFloat = row % 2 == 0 ? 8 : 8 + gap / 2
            while x < size.width + gap {
                sky.addEllipse(in: CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8))
                x += gap
            }
            y += gap * 0.86
            row += 1
        }
        context.fill(sky, with: .color(.white.opacity(dark ? 0.09 : 0.8)))

        let fill = dark ? Color(hex: 0x2A1822) : Color.white
        let edge = Theme.light.opacity(dark ? 0.55 : 0.9)

        // Clouds in even lanes, every other lane shifted half a step.
        let width = min(160, max(110, size.width * 0.36))
        let spacing = width * 2.1
        let laneGap: CGFloat = 165
        let slide = CGFloat((t * 7).truncatingRemainder(dividingBy: Double(spacing)))
        var lane = 0
        var laneY: CGFloat = 80
        while laneY < size.height - 90 {
            var x = -spacing + (lane % 2 == 0 ? 0 : spacing / 2) + slide
            let bob = CGFloat(sin(t * 0.7 + Double(lane) * 1.3)) * 3
            while x < size.width + spacing {
                let cloud = cloudPath(center: CGPoint(x: x, y: laneY + bob), width: width)
                context.stroke(cloud, with: .color(edge), lineWidth: 6)
                context.fill(cloud, with: .color(fill))
                x += spacing
            }
            laneY += laneGap
            lane += 1
        }

        // Scalloped cloud bank at the bottom.
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
    private func cloudPath(center c: CGPoint, width w: CGFloat) -> Path {
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

    // Candy stripes gently sliding sideways, fading to white at the top.
    private func stripes(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let width: CGFloat = 20
        let slide = CGFloat((t * 10).truncatingRemainder(dividingBy: Double(width * 2)))
        var path = Path()
        var x = -width * 2 + slide
        while x < size.width + width {
            path.addRect(CGRect(x: x, y: 0, width: width, height: size.height))
            x += width * 2
        }
        let tint = dark ? Theme.light : Theme.main
        context.fill(path, with: .linearGradient(Gradient(colors: [tint.opacity(dark ? 0.04 : 0.03), tint.opacity(dark ? 0.16 : 0.2)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    // Little hearts floating up in a loose grid.
    private func hearts(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let gap: CGFloat = 54
        let rise = CGFloat((t * 12).truncatingRemainder(dividingBy: Double(gap)))
        let tint = dark ? Theme.light : Theme.main
        var row = 0
        var y = size.height + gap - rise
        while y > -gap {
            let depth = max(0, min(1, y / max(1, size.height)))
            var x: CGFloat = row % 2 == 0 ? 14 : 14 + gap / 2
            var path = Path()
            while x < size.width + gap {
                let s: CGFloat = 13 + CGFloat(sin(Double(x) * 0.05 + t)) * 1.5
                path.addPath(heartPath(CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s * 0.9)))
                x += gap
            }
            context.fill(path, with: .color(tint.opacity((dark ? 0.08 : 0.08) + depth * 0.16)))
            y -= gap * 0.8
            row += 1
        }
    }

    private func heartPath(_ r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3), control1: CGPoint(x: r.midX - r.width * 0.1, y: r.maxY - r.height * 0.15), control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.62))
        p.addArc(center: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62), control2: CGPoint(x: r.midX + r.width * 0.1, y: r.maxY - r.height * 0.15))
        p.closeSubpath()
        return p
    }

    // Four-point stars that twinkle on and off.
    private func stars(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let gap: CGFloat = 48
        let tint = dark ? Color.white : Theme.main
        var row = 0
        var y: CGFloat = 20
        while y < size.height + gap {
            var x: CGFloat = row % 2 == 0 ? 18 : 18 + gap / 2
            while x < size.width + gap {
                let seed = Double(x * 0.37 + y * 0.91)
                let twinkle = (sin(t * 1.6 + seed) + 1) / 2
                let r = CGFloat(4 + twinkle * 4)
                context.fill(sparkle(CGPoint(x: x, y: y), r), with: .color(tint.opacity(0.08 + twinkle * (dark ? 0.3 : 0.28))))
                x += gap
            }
            y += gap * 0.85
            row += 1
        }
    }

    private func sparkle(_ c: CGPoint, _ radius: CGFloat) -> Path {
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
