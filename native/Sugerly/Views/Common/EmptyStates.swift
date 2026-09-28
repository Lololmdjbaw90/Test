import SwiftUI

// Empty states with a little character instead of a stock icon: Mimi, the
// Sugerly bunny (hand-drawn art in every accent colour, so she matches
// yours), thinking about what's missing, on a sketchbook card with a dashed
// edge and doodles. She hops, sways or droops with the mood.

struct MimiBuddy: View {
    enum Mood { case happy, sleepy, sad }
    var icon: String
    var mood: Mood = .happy
    var size: CGFloat = 110
    var animated = true

    // One drawing per accent colour.
    static var imageName: String {
        switch Theme.accent {
        case .rose: return "MimiRose"
        case .lavender: return "MimiLavender"
        case .mint: return "MimiMint"
        case .peach: return "MimiPeach"
        case .sky: return "MimiSky"
        }
    }

    var body: some View {
        let s = size / 110
        ZStack {
            // soft shadow on the "floor"
            Ellipse().fill(Theme.main.opacity(0.14))
                .frame(width: 52 * s, height: 8 * s)
                .offset(y: size * 0.5 - 3 * s)
            bunny(s)
            thought(s)
                .offset(x: size * 0.5, y: -size * 0.34)
            doodles(s)
        }
        .frame(width: size * 1.55, height: size)
        .accessibilityHidden(true)
    }

    private func bunny(_ s: CGFloat) -> some View {
        Image(Self.imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: size)
            .saturation(mood == .sad ? 0.8 : 1)
            // happy: a little hop and squish; sleepy: a slow sway; sad: a droop
            .phaseAnimator(animated ? [0, 1, 2] : [0]) { v, k in
                v.scaleEffect(x: stretch(k), y: 2 - stretch(k), anchor: .bottom)
                    .offset(y: lift(k) * s)
                    .rotationEffect(.degrees(rotation(k)), anchor: .bottom)
            } animation: { k in
                switch mood {
                case .happy: return k == 1 ? .easeOut(duration: 0.28) : k == 2 ? .easeIn(duration: 0.22) : .spring(response: 0.4, dampingFraction: 0.5).delay(1.6)
                case .sleepy: return .easeInOut(duration: 1.8)
                case .sad: return .easeInOut(duration: 2.2)
                }
            }
    }

    private func stretch(_ k: Int) -> CGFloat { mood == .happy && k == 2 ? 1.05 : 1 }

    private func lift(_ k: Int) -> CGFloat {
        guard k == 1 else { return 0 }
        switch mood {
        case .happy: return -7
        case .sleepy: return -2
        case .sad: return 0
        }
    }

    private func rotation(_ k: Int) -> Double {
        switch mood {
        case .happy: return k == 1 ? -4 : 0
        case .sleepy: return k == 1 ? -3 : k == 2 ? 3 : 0
        case .sad: return k == 1 ? 5 : 3
        }
    }

    // A little thought bubble with what's missing.
    private func thought(_ s: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(systemName: icon)
                .font(.system(size: 13 * s, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32 * s, height: 32 * s)
                .background(Theme.gradient, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5 * s))
                .shadow(color: Theme.main.opacity(0.3), radius: 4 * s, y: 2 * s)
            Circle().fill(Theme.light).frame(width: 8 * s, height: 8 * s)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5 * s))
                .offset(x: -9 * s, y: 11 * s)
            Circle().fill(Theme.light).frame(width: 5 * s, height: 5 * s)
                .offset(x: -16 * s, y: 19 * s)
        }
        .phaseAnimator(animated ? [false, true] : [false]) { v, up in
            v.offset(y: up ? -3 * s : 0)
        } animation: { _ in .easeInOut(duration: 1.3) }
    }

    // Hand-drawn little sparkles and a heart around Mimi.
    private func doodles(_ s: CGFloat) -> some View {
        ZStack {
            Doodles.sparkle
                .stroke(Theme.main.opacity(0.7), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 16 * s, height: 16 * s)
                .offset(x: -62 * s, y: -30 * s)
                .phaseAnimator(animated ? [0.6, 1.0] : [1.0]) { v, k in v.scaleEffect(k).opacity(k) } animation: { _ in .easeInOut(duration: 0.9) }
            Doodles.sparkle
                .stroke(Color(hex: 0xF0A020).opacity(0.75), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 11 * s, height: 11 * s)
                .offset(x: 70 * s, y: 12 * s)
            Doodles.heart
                .stroke(Theme.main.opacity(0.55), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 13 * s, height: 12 * s)
                .rotationEffect(.degrees(-14))
                .offset(x: -56 * s, y: 26 * s)
            Circle().fill(Theme.light.opacity(0.8)).frame(width: 5 * s, height: 5 * s).offset(x: 54 * s, y: 34 * s)
            Circle().fill(Theme.light.opacity(0.6)).frame(width: 4 * s, height: 4 * s).offset(x: -46 * s, y: -48 * s)
        }
    }
}

enum Doodles {
    // A four-point sparkle with slightly curved sides, like a pen doodle.
    static let sparkle = DoodleShape { r in
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: CGPoint(x: c.x, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: CGPoint(x: c.x + r.width * 0.08, y: c.y - r.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: CGPoint(x: c.x + r.width * 0.08, y: c.y + r.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: CGPoint(x: c.x - r.width * 0.08, y: c.y + r.height * 0.08))
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: CGPoint(x: c.x - r.width * 0.08, y: c.y - r.height * 0.08))
        return p
    }

    static let heart = DoodleShape { r in
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3), control1: CGPoint(x: r.midX - r.width * 0.2, y: r.maxY - r.height * 0.2), control2: CGPoint(x: r.minX, y: r.midY + r.height * 0.1))
        p.addArc(center: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY + r.height * 0.3), radius: r.width * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.midY + r.height * 0.1), control2: CGPoint(x: r.midX + r.width * 0.2, y: r.maxY - r.height * 0.2))
        return p
    }

    // A wobbly underline.
    static let squiggle = DoodleShape { r in
        var p = Path()
        let steps = 5
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        for i in 0..<steps {
            let x0 = r.minX + r.width * CGFloat(i) / CGFloat(steps)
            let x1 = r.minX + r.width * CGFloat(i + 1) / CGFloat(steps)
            p.addQuadCurve(to: CGPoint(x: x1, y: r.midY), control: CGPoint(x: (x0 + x1) / 2, y: i % 2 == 0 ? r.minY : r.maxY))
        }
        return p
    }
}

struct DoodleShape: Shape {
    let make: @Sendable (CGRect) -> Path
    func path(in rect: CGRect) -> Path { make(rect) }
}

// The sketchbook card every empty state uses.
struct EmptyCard: View {
    let icon: String
    let title: String
    let text: String
    var animated = true
    var mood: MimiBuddy.Mood? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var compact = false

    private var face: MimiBuddy.Mood {
        if let mood { return mood }
        if icon.contains("exclamationmark") || icon.contains("lock") || icon.contains("wifi") { return .sad }
        if icon.contains("checkmark") || icon.contains("sparkles") || icon.contains("crown") { return .happy }
        return .sleepy
    }

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            MimiBuddy(icon: icon, mood: face, size: compact ? 96 : 124, animated: animated)
                .padding(.bottom, 2)
            Text(title).font(.display(compact ? 21 : 25)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Doodles.squiggle
                .stroke(Theme.main.opacity(0.55), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: compact ? 54 : 70, height: 7)
            Text(text).font(.jakarta(14)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.jakarta(14, .heavy)).foregroundStyle(Theme.main)
                        .padding(.horizontal, 18).frame(height: 38)
                        .background(Theme.soft, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.main.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(BouncyStyle(scale: 0.93))
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, compact ? 18 : 24)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Palette.surface)
                .overlay { SketchDots().clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)) }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.light.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, dash: [7, 6]))
        }
    }
}

// Faint dotted-paper texture.
private struct SketchDots: View {
    var body: some View {
        Canvas { ctx, size in
            let gap: CGFloat = 16
            var y: CGFloat = gap / 2
            while y < size.height {
                var x: CGFloat = gap / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Palette.border.opacity(0.9)))
                    x += gap
                }
                y += gap
            }
        }
        .allowsHitTesting(false)
    }
}
