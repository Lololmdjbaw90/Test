import SwiftUI

// Empty states with a little character instead of a stock icon: Mimi, the
// Sugerly bunny (hand-drawn art in every accent colour, so she matches
// yours), on a sketchbook card with a dashed edge.

struct MimiBuddy: View {
    enum Mood { case happy, sleepy, sad }
    var icon: String
    var mood: Mood = .happy
    var size: CGFloat = 110
    var animated = true
    @State private var shown = false

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

    // She stands still and just fades in.
    var body: some View {
        let s = size / 110
        ZStack {
            // soft shadow on the "floor"
            Ellipse().fill(Theme.main.opacity(0.14))
                .frame(width: 52 * s, height: 8 * s)
                .offset(y: size * 0.5 - 3 * s)
            Image(Self.imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: size)
        }
        .frame(width: size * 0.8, height: size)
        .opacity(shown || !animated ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { shown = true } }
        .onDisappear { shown = false }
        .accessibilityHidden(true)
    }
}

enum Doodles {
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
