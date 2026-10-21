import SwiftUI

// Sugerly's loading sign: three little hearts in your colour that hop one
// after another (instead of the grey iPhone spinner). With Reduce Motion
// they only glow softly in turn.
struct SugarLoader: View {
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || RenderingBudget.shared.limited)) { context in
            hearts(at: context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func hearts(at t: Double) -> some View {
        HStack(spacing: size * 0.55) {
            ForEach(0..<3, id: \.self) { i in
                heart(hop: Self.hop(t, i))
            }
        }
        .padding(.top, size * 0.7)
    }

    private func heart(hop: Double) -> some View {
        let lift: CGFloat = reduceMotion ? 0 : -size * 0.7 * CGFloat(hop)
        let grow: CGFloat = reduceMotion ? 1 : 1 + 0.15 * CGFloat(hop)
        let fade: Double = reduceMotion ? 0.45 + 0.55 * hop : 1
        return Image(systemName: "heart.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.gradient)
            .offset(y: lift)
            .scaleEffect(grow)
            .opacity(fade)
    }

    // 0…1…0 for the first half of each beat, resting for the second half.
    private static func hop(_ t: Double, _ i: Int) -> Double {
        let raw: Double = t * 2.2 - Double(i) * 0.18
        let phase: Double = raw - raw.rounded(.down)
        return phase < 0.5 ? sin(phase * 2 * Double.pi) : 0
    }
}

// Little bars that dance while a song plays.
struct EqualizerBars: View {
    var color: Color = .white
    var height: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || RenderingBudget.shared.limited)) { context in
            bars(at: context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func bars(at t: Double) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 4, height: max(4, height * CGFloat(level(t, i))))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func level(_ t: Double, _ i: Int) -> Double {
        guard !reduceMotion else { return 0.6 }
        let speed: Double = 4.5 + Double(i) * 1.3
        let wave: Double = sin(t * speed + Double(i) * 0.9)
        return 0.3 + 0.7 * abs(wave)
    }
}
