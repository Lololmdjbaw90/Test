import SwiftUI

// Mimi, the Sugerly bunny (hand-drawn art in every accent colour, so she
// matches yours), for the few full-screen moments, and the plain card every
// empty list uses.

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

// The card every empty state uses: the page's own icon in a soft circle,
// a short title, one line of help and, when there's something to do, a
// plain button. (`animated` and `mood` stay so every caller still compiles;
// Mimi now only shows on the full-screen covers.)
struct EmptyCard: View {
    let icon: String
    let title: String
    let text: String
    var animated = true
    var mood: MimiBuddy.Mood? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            Image(systemName: icon)
                .font(.system(size: compact ? 20 : 24, weight: .regular))
                .foregroundStyle(Palette.text2)
                .frame(width: compact ? 48 : 56, height: compact ? 48 : 56)
                .background(Palette.surface2, in: Circle())
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title).font(.jakarta(compact ? 16 : 17, .semibold)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Text(text).font(.jakarta(14)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(OutlineButtonStyle(height: 40))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, compact ? 20 : 28)
        .sugarCard(radius: 16)
    }
}
