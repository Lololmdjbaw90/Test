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

    // One drawing per accent colour; custom colours turn the rose one.
    static var imageName: String {
        if Theme.custom != nil { return "MimiRose" }
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
        ZStack {
            Image(Self.imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: size)
                .tintShift(Theme.tint)
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
            MimiBuddy(icon: icon, mood: face, size: compact ? 72 : 92, animated: animated)
                .padding(.bottom, 4)
            Text(title).font(.display(compact ? 20 : 23)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Text(text).font(.jakarta(14)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.jakarta(14, .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 18).frame(minHeight: 38)
                        .background {
                            Capsule().fill(Theme.candy).shadow(color: Theme.glow(0.28), radius: 6, y: 3)
                        }
                }
                .buttonStyle(BouncyStyle(scale: 0.92))
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, compact ? 18 : 26)
        // A clean white card: Mimi and the button bring the colour.
        .sugarCard(radius: 22)
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
