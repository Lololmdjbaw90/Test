import SwiftUI

// Empty states with a little character instead of a stock icon: Mimi, a
// mochi bunny, holding a sticker of what's missing, on a sketchbook card with
// a dashed edge and doodles. Mimi blinks, bobs and changes face with the mood.

struct MimiBuddy: View {
    enum Mood { case happy, sleepy, sad }
    var icon: String
    var mood: Mood = .happy
    var size: CGFloat = 110
    var animated = true

    private let ink = Color(hex: 0x4A2B3A)
    private let blush = Color(hex: 0xFF9EB5)

    var body: some View {
        let s = size / 110
        ZStack {
            // soft shadow on the "floor"
            Ellipse().fill(Theme.main.opacity(0.12))
                .frame(width: 70 * s, height: 10 * s)
                .offset(y: 46 * s)
            character(s)
                .phaseAnimator(animated ? [false, true] : [false]) { v, up in
                    v.offset(y: up ? -4 * s : 0).rotationEffect(.degrees(up ? -2 : 2))
                } animation: { _ in .easeInOut(duration: 1.4) }
            doodles(s)
        }
        .frame(width: size * 1.35, height: size)
        .accessibilityHidden(true)
    }

    private func character(_ s: CGFloat) -> some View {
        let fill = LinearGradient(colors: [.white, Theme.light.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        let outline = Theme.main.opacity(0.45)
        return ZStack {
            // ears
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(fill)
                    .overlay(Capsule().strokeBorder(outline, lineWidth: 2 * s))
                    .overlay(Capsule().fill(blush.opacity(0.45)).padding(5 * s).padding(.top, 4 * s))
                    .frame(width: 18 * s, height: 34 * s)
                    .rotationEffect(.degrees(side * 14))
                    .offset(x: side * 20 * s, y: -38 * s)
            }
            // body
            RoundedRectangle(cornerRadius: 34 * s, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 34 * s, style: .continuous).strokeBorder(outline, lineWidth: 2 * s))
                .overlay(alignment: .topLeading) {
                    Ellipse().fill(.white.opacity(0.9)).frame(width: 16 * s, height: 9 * s)
                        .rotationEffect(.degrees(-20)).offset(x: 14 * s, y: 10 * s)
                }
                .frame(width: 86 * s, height: 68 * s)
            face(s).offset(y: 2 * s)
            // the sticker it's holding
            Image(systemName: icon)
                .font(.system(size: 14 * s, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34 * s, height: 34 * s)
                .background(Theme.gradient, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3 * s))
                .shadow(color: Theme.main.opacity(0.3), radius: 4 * s, y: 2 * s)
                .rotationEffect(.degrees(-12))
                .offset(x: 40 * s, y: 22 * s)
        }
    }

    @ViewBuilder
    private func face(_ s: CGFloat) -> some View {
        ZStack {
            // eyes
            HStack(spacing: 22 * s) {
                ForEach(0..<2, id: \.self) { i in
                    switch mood {
                    case .sleepy:
                        SmileArc().stroke(ink, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                            .frame(width: 10 * s, height: 5 * s)
                            .rotationEffect(.degrees(180))
                    default:
                        Capsule().fill(ink)
                            .frame(width: 7 * s, height: 10 * s)
                            .overlay(alignment: .topTrailing) {
                                Circle().fill(.white).frame(width: 2.6 * s, height: 2.6 * s).offset(x: -1 * s, y: 1.5 * s)
                            }
                            // open → (wait) → shut → open: a blink every couple of seconds
                            .phaseAnimator(animated ? [0, 1, 2] : [0]) { v, k in
                                v.scaleEffect(x: 1, y: k == 2 ? 0.12 : k == 1 ? 0.97 : 1)
                            } animation: { k in
                                switch k {
                                case 1: return .easeInOut(duration: 2.2)
                                case 2: return .easeIn(duration: 0.07)
                                default: return .easeOut(duration: 0.09)
                                }
                            }
                    }
                }
            }
            .offset(y: -6 * s)
            if mood == .sad {
                HStack(spacing: 26 * s) {
                    Capsule().fill(ink).frame(width: 8 * s, height: 2 * s).rotationEffect(.degrees(-18))
                    Capsule().fill(ink).frame(width: 8 * s, height: 2 * s).rotationEffect(.degrees(18))
                }
                .offset(y: -15 * s)
            }
            // cheeks
            HStack(spacing: 38 * s) {
                Ellipse().fill(blush.opacity(0.75)).frame(width: 12 * s, height: 7 * s)
                Ellipse().fill(blush.opacity(0.75)).frame(width: 12 * s, height: 7 * s)
            }
            .offset(y: 5 * s)
            // mouth
            SmileArc()
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
                .frame(width: 10 * s, height: 5 * s)
                .rotationEffect(.degrees(mood == .sad ? 180 : 0))
                .offset(y: mood == .sad ? 9 * s : 6 * s)
        }
    }

    // Hand-drawn little sparkles and a heart around Mimi.
    private func doodles(_ s: CGFloat) -> some View {
        ZStack {
            Doodle.sparkle
                .stroke(Theme.main.opacity(0.7), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 16 * s, height: 16 * s)
                .offset(x: -62 * s, y: -30 * s)
                .phaseAnimator(animated ? [0.6, 1.0] : [1.0]) { v, k in v.scaleEffect(k).opacity(k) } animation: { _ in .easeInOut(duration: 0.9) }
            Doodle.sparkle
                .stroke(Color(hex: 0xF0A020).opacity(0.75), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 11 * s, height: 11 * s)
                .offset(x: 64 * s, y: -40 * s)
            Doodle.heart
                .stroke(Theme.main.opacity(0.55), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 13 * s, height: 12 * s)
                .rotationEffect(.degrees(-14))
                .offset(x: -56 * s, y: 26 * s)
            Circle().fill(Theme.light.opacity(0.8)).frame(width: 5 * s, height: 5 * s).offset(x: 58 * s, y: -8 * s)
            Circle().fill(Theme.light.opacity(0.6)).frame(width: 4 * s, height: 4 * s).offset(x: -46 * s, y: -48 * s)
        }
    }
}

struct SmileArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        return p
    }
}

enum Doodle {
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
            MimiBuddy(icon: icon, mood: face, size: compact ? 80 : 104, animated: animated)
                .padding(.bottom, 2)
            Text(title).font(.display(compact ? 21 : 25)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Doodle.squiggle
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
